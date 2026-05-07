import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' show Position;
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/models/live_session_model.dart';
import '../../../core/services/blocks_repository.dart';
import '../../../core/services/location_service.dart';
import '../../../core/state/live_session.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/gradient_scaffold.dart';
import '../../../shared/widgets/icebreaker_logo.dart';
import '../../../shared/widgets/pill_button.dart';
import '../widgets/nearby_focus_card.dart';
import '../widgets/nearby_about_me_card.dart';

/// Nearby tab — Firestore-backed discovery carousel.
///
/// Discovery pipeline (Phase 1 — `live_sessions` is the authoritative source
/// of truth for live presence and discovery semantics):
///
///   1. Load the signed-in user's STABLE profile fields (gender, age) from
///      users/{uid} — these never change mid-session and are used for the
///      counterparty's mutual filtering of me.
///   2. Read the signed-in user's discovery SNAPSHOTS (maxDistance,
///      interestedIn, ageRange) from `LiveSession.currentSession` — these
///      were captured into `live_sessions/{uid}.*Snapshot` when Go Live
///      started, and are intentionally immutable for the session's lifetime.
///      Mid-session Edit Profile changes to interestedIn do NOT re-enter the
///      active session; they take effect at the next Go Live.
///   3. Load the user's blocked UIDs + reverse-block index (both streamed).
///   4. Read the user's position from `LiveSession.currentSession.lat/lng`
///      (or a direct device-GPS fallback on the very first pass, before the
///      first session position write has landed).
///   5. Compute current geohash-7 cell + 8 neighbours.
///   6. Subscribe to one Firestore stream per cell on `live_sessions` where
///        status         == 'active'
///        visibilityState == 'discoverable'
///        geohash        ∈ [prefix, prefix + '~')
///      The query shape matches the security rule exactly — Firestore can
///      prove the rule from the query alone and accept the listener.
///   7. For each candidate uid, STABLE profile fields (firstName, age,
///      gender, bio, photoUrl, plan, status, hometown, occupation, height,
///      lookingFor) are lazily loaded from users/{uid} into [_profileCache].
///   8. Changes to the current user's live_sessions doc (new position,
///      session ended) come via a [LiveSession] listener.  Resubscribe cells
///      when the geohash window moves; rebuild in place otherwise.
///   9. [_rebuildList] joins the candidate's live_sessions doc (position,
///      freshness, discovery snapshots) with the cached users profile
///      (identity + stable attributes), applies mutual preference filtering
///      off BOTH sides' session snapshots (never off their mutable users
///      prefs), excludes self + blocked + stale-position users, and enforces
///      the Haversine distance gate using my own maxDistance snapshot.
///
/// Geohash is a coarse bounding-box query helper only — the Haversine
/// distance is the authoritative filter that enforces the selected radius.
///
/// When not live: "Go Live" gate is shown.
/// When live but loading: spinner.
/// When live but empty: empty state.
class NearbyScreen extends StatefulWidget {
  const NearbyScreen({super.key});

  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends State<NearbyScreen>
    with WidgetsBindingObserver {
  late final PageController _pageController;
  int _currentIndex = 0;

  // Discovery state.
  bool _loadingDiscovery = true;
  _DiscoveryError? _discoveryError;
  /// Raw error message preserved for the stream-failure variants.  Surfaces
  /// the FirebaseException text (which for `failed-precondition` includes the
  /// Firebase Console "create index" URL) in the dev error UI so we can tell
  /// missing-index from permission-denied at a glance on a real device.
  String? _discoveryErrorDetail;
  List<_NearbyUser> _nearbyUsers = [];

  // Per-rebuild diagnostics — populated by [_rebuildList] every pass.
  // [_lastCandidateCount] is the deduped count of users seen across all cells
  // before any filter; [_lastExclusionCounts] breaks down which gate each
  // excluded uid hit.  Surfaced in [_buildEmptyState] when kDebugMode is true
  // so two-phone testing shows exactly why the carousel is empty.
  int _lastCandidateCount = 0;
  Map<String, int> _lastExclusionCounts = const {};

  // UID of the signed-in user — stored so the app-resume handler can call
  // _rebuildList without re-reading FirebaseAuth.
  String? _myUid;

  // Current user's position — sourced from LiveSession.currentSession after
  // the session's first writePosition lands; bootstrapped from direct device
  // GPS on the very first pass so cells can subscribe before that write
  // round-trips.
  double? _myLat;
  double? _myLng;

  // Active session snapshots — captured at Go Live time and held constant
  // for the session's lifetime.  Source: LiveSession.currentSession.
  //
  // Intentional: mid-session edits to users/{uid}.{interestedIn,
  // ageRangeMin/Max, maxDistanceMeters} do NOT alter these values.  A live
  // session is deterministic — new prefs take effect at the next Go Live.
  double _effectiveRadiusMeters = AppConstants.nearbyRadiusMeters;
  String? _myInterestedIn; // 'everyone' | 'men' | 'women' | 'non_binary'
  int _myAgeRangeMin = AppConstants.minAge;
  int _myAgeRangeMax = 99;

  // STABLE profile fields — read from users/{uid} once at discovery start
  // (gender + age effectively don't change mid-session).  Used so the
  // counterparty's mutual filter can evaluate me.
  String? _myGender; // 'male' | 'female' | 'non_binary' | 'other'
  int? _myAge;

  // Blocked user UIDs.
  Set<String> _blockedUids = {};

  // Per-cell snapshots: geohashPrefix → { userId → live_sessions data }.
  // Replacing the entire cell map on each snapshot correctly removes users
  // who went offline between snapshots without requiring docChanges tracking.
  final Map<String, Map<String, Map<String, dynamic>>> _cellSnapshots = {};

  // Per-uid users/{uid} profile cache for display + mutual-filter fields
  // that do NOT live on live_sessions.  Populated lazily the first time
  // each uid appears in a cell.  Cleared in _stopDiscovery.
  final Map<String, Map<String, dynamic>> _profileCache = {};

  // UIDs currently being fetched by _ensureProfileLoaded — guards against
  // duplicate reads when the same uid shows up in multiple overlapping cells.
  final Set<String> _profileInFlight = {};

  // Active Firestore cell stream subscriptions.
  final List<StreamSubscription> _cellSubs = [];

  // The geohash prefixes currently subscribed.
  List<String> _subscribedHashes = [];

  // Cached LiveSession ref + listener handle — the source of own-position +
  // session lifecycle updates.  Subscribed in didChangeDependencies, cleaned
  // up in dispose / _stopDiscovery.
  LiveSession? _liveSession;

  // Stream subscription on the current user's blockedUsers subcollection.
  // Keeps _blockedUids authoritative while Nearby is open so blocks made
  // from other screens (e.g. chat thread) propagate immediately.
  StreamSubscription<QuerySnapshot>? _blockedUidsSub;

  // UIDs of users who have blocked the current user.
  // Populated by streaming blockedBy/{myUid}/blockers.
  Set<String> _blockedByUids = {};

  // Stream subscription on blockedBy/{myUid}/blockers — the reverse index
  // written at block time so this user can know who has blocked them.
  StreamSubscription<QuerySnapshot>? _blockedBySub;

  @override
  void initState() {
    super.initState();
    // Tighter viewport so neighbouring pages clearly peek on either side
    // even though each page now stacks a hero card AND an about-me card —
    // 0.80 read as "almost full bleed" once the page got taller.
    _pageController = PageController(viewportFraction: 0.78);
    WidgetsBinding.instance.addObserver(this);
  }

  /// On app resume, force a freshness-gate pass so stale live users are
  /// evicted immediately — even if no Firestore stream event fired and the
  /// user's own position hasn't changed since being backgrounded.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final uid = _myUid;
      if (uid != null && _cellSubs.isNotEmpty) {
        debugPrint('[Nearby] app resumed — forcing freshness rebuild');
        _rebuildList(uid);
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = LiveSessionScope.of(context);

    // Attach our listener the first time we see the session, or re-attach if
    // the session instance ever changes (e.g. sign-in/sign-out swap).
    if (!identical(_liveSession, session)) {
      _liveSession?.removeListener(_onLiveSessionChanged);
      _liveSession = session;
      _liveSession!.addListener(_onLiveSessionChanged);
    }

    final isLive = session.isLive;
    if (isLive && _cellSubs.isEmpty) {
      _startDiscovery();
    } else if (!isLive && _cellSubs.isNotEmpty) {
      _stopDiscovery();
    }
  }

  /// Fires whenever [LiveSession] notifies — i.e. on every
  /// `live_sessions/{myUid}` snapshot update (position, status, etc.).
  ///
  /// Handles the position-update case here: when my own location changes,
  /// resubscribe cell streams if the geohash window has moved, otherwise
  /// rebuild the list so the Haversine distance gate is re-evaluated.
  ///
  /// Session-lifecycle transitions (active → ended/expired) are handled by
  /// [didChangeDependencies] via the InheritedNotifier rebuild path, so this
  /// callback bails early on a non-active session.
  void _onLiveSessionChanged() {
    if (!mounted) return;
    final myUid = _myUid;
    if (myUid == null || _cellSubs.isEmpty) return;

    final model = _liveSession?.currentSession;
    if (model == null || !model.isActive) return;

    final lat = model.lat;
    final lng = model.lng;
    if (lat == null || lng == null) return;
    if (lat == _myLat && lng == _myLng) return;

    _myLat = lat;
    _myLng = lng;
    debugPrint('[Nearby] position updated from LiveSession: $lat, $lng');

    final newHashes = LocationService.queryHashes(lat, lng);
    final hashesChanged = newHashes.length != _subscribedHashes.length ||
        !newHashes.toSet().containsAll(_subscribedHashes);

    if (hashesChanged) {
      debugPrint('[Nearby] moved to new cells — resubscribing');
      _cellSnapshots.clear();
      _subscribeCells(myUid, newHashes);
    } else {
      _rebuildList(myUid);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _liveSession?.removeListener(_onLiveSessionChanged);
    _stopDiscovery();
    _pageController.dispose();
    super.dispose();
  }

  // ── Discovery lifecycle ────────────────────────────────────────────────────

  Future<void> _startDiscovery() async {
    setState(() {
      _loadingDiscovery = true;
      _discoveryError = null;
      _discoveryErrorDetail = null;
      _lastCandidateCount = 0;
      _lastExclusionCounts = const {};
      _nearbyUsers = [];   // clear stale list so old cards don't flash
    });

    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) {
      setState(() => _loadingDiscovery = false);
      return;
    }
    _myUid = myUid;

    // Capture the session snapshots (radius, interestedIn, age range) from
    // the authoritative live_sessions/{uid} doc via the in-memory model.
    // These values were frozen at Go Live time and stay constant for the
    // session.
    _applySessionSnapshots();

    // Load stable profile fields (gender + age) and both block streams in
    // parallel.  Both stream methods return a Future that completes on the
    // first snapshot so initial UIDs are known before cell subscriptions open.
    await Future.wait([
      _loadMyStableProfile(myUid),
      _startBlockedUsersStream(myUid),
      _startBlockedByStream(myUid),
    ]);

    if (!mounted) return;

    // Bootstrap position.  Prefer the live_sessions doc (authoritative, and
    // the source of truth for my geohash cell) when it already carries a
    // position; fall back to a direct device-GPS read if the first session
    // write has not yet landed — otherwise we'd delay subscribing cells by
    // up to the periodic location-refresh cadence.
    double? lat = _liveSession?.currentSession?.lat;
    double? lng = _liveSession?.currentSession?.lng;

    if (lat == null || lng == null) {
      Position? pos = await LocationService.getPosition();
      if (!mounted) return;
      if (pos == null) {
        debugPrint('[Nearby] GPS attempt 1 failed — retrying in 3 s');
        await Future.delayed(const Duration(seconds: 3));
        if (!mounted) return;
        pos = await LocationService.getPosition();
        if (!mounted) return;
      }
      if (pos == null) {
        // Both attempts failed.  Read the unified permission status to pick
        // the right error state and CTA.  `requestable` lets us offer
        // "Allow Location" inline; `blockedForever` and `servicesDisabled`
        // route to system Settings; `granted` means GPS itself failed.
        final status = await LocationService.currentStatus();
        debugPrint('[Nearby] GPS failed — status=$status');
        if (!mounted) return;
        setState(() {
          _loadingDiscovery = false;
          _discoveryError = status == LocationStatus.granted
              ? _DiscoveryError.gpsFailed
              : _DiscoveryError.fromStatus(status);
        });
        return;
      }
      lat = pos.latitude;
      lng = pos.longitude;
    }

    _myLat = lat;
    _myLng = lng;

    // Subscribe to geohash cells.
    final hashes = LocationService.queryHashes(lat, lng);
    _subscribeCells(myUid, hashes);

    setState(() => _loadingDiscovery = false);
  }

  /// Copies the current session's frozen snapshots into the in-memory fields
  /// that drive Nearby's filter.  Intentional: mid-session edits to
  /// users/{uid} are NOT reflected here — they take effect at the next Go
  /// Live.  Called once at [_startDiscovery] and never again during the
  /// session's lifetime.
  void _applySessionSnapshots() {
    final session = _liveSession?.currentSession;
    if (session == null) {
      debugPrint('[Nearby] no live session snapshot available — falling back '
          'to defaults');
      return;
    }
    _effectiveRadiusMeters = session.maxDistanceMetersSnapshot
        .toDouble()
        .clamp(AppConstants.nearbyRadiusMeters, 60.0);
    _myInterestedIn = session.interestedInSnapshot;
    _myAgeRangeMin = session.ageRangeMinSnapshot;
    _myAgeRangeMax = session.ageRangeMaxSnapshot;
    debugPrint('[Nearby] session snapshots applied — '
        'interestedIn=$_myInterestedIn '
        'ageRange=$_myAgeRangeMin–$_myAgeRangeMax '
        'radius=$_effectiveRadiusMeters m');
  }

  /// Loads the current user's STABLE profile fields (gender + age) for the
  /// counterparty's mutual filter.
  ///
  /// Reads `profiles/{uid}` (canonical) and falls back to `users/{uid}` for
  /// any field that the canonical doc is missing — covers legacy accounts
  /// that pre-date the dual-write.  Discovery preferences (interestedIn,
  /// ageRange, maxDistance) are NOT read here; those come from the session
  /// snapshot, captured at Go Live time.
  Future<void> _loadMyStableProfile(String myUid) async {
    final db = FirebaseFirestore.instance;
    try {
      final results = await Future.wait([
        db.collection('profiles').doc(myUid).get(),
        db.collection('users').doc(myUid).get(),
      ]);
      final profileData = results[0].exists ? results[0].data() : null;
      final userData = results[1].exists ? results[1].data() : null;

      _myGender = (profileData?['gender'] as String?) ??
          (userData?['gender'] as String?);
      _myAge = (profileData?['age'] as num?)?.toInt() ??
          (userData?['age'] as num?)?.toInt();
      debugPrint('[Nearby] stable profile loaded — '
          'gender=$_myGender age=$_myAge '
          '(profiles=${profileData != null}, users=${userData != null})');
    } catch (e) {
      debugPrint('[Nearby] stable profile load failed (non-fatal): $e');
    }
  }

  /// Opens a live stream on users/{myUid}/blockedUsers.
  ///
  /// Returns a Future that completes when the first snapshot arrives so
  /// [_blockedUids] is populated before cell subscriptions are opened.
  /// After that, every subsequent snapshot calls [_rebuildList] so blocks
  /// made from any screen propagate into Nearby immediately.
  Future<void> _startBlockedUsersStream(String myUid) {
    final completer = Completer<void>();
    _blockedUidsSub?.cancel();
    _blockedUidsSub = FirebaseFirestore.instance
        .collection('users')
        .doc(myUid)
        .collection('blockedUsers')
        .snapshots()
        .listen(
      (snap) {
        _blockedUids = snap.docs.map((d) => d.id).toSet();
        debugPrint('[Nearby] blockedUids updated: ${_blockedUids.length}');
        if (!completer.isCompleted) {
          // Initial population — unblock _startDiscovery.
          completer.complete();
        } else if (mounted && _myUid != null && _cellSubs.isNotEmpty) {
          // Subsequent change — evict any newly blocked users immediately.
          _rebuildList(_myUid!);
        }
      },
      onError: (Object e) {
        debugPrint('[Nearby] blockedUsers stream error (non-fatal): $e');
        // Don't block discovery startup on a stream error.
        if (!completer.isCompleted) completer.complete();
      },
    );
    return completer.future;
  }

  /// Streams blockedBy/{myUid}/blockers — the reverse block index written
  /// whenever another user blocks the current user.
  ///
  /// Mirrors [_startBlockedUsersStream]: returns a Future that completes on
  /// the first snapshot so [_blockedByUids] is populated before cell
  /// subscriptions open.  Subsequent events call [_rebuildList] immediately.
  Future<void> _startBlockedByStream(String myUid) {
    final completer = Completer<void>();
    _blockedBySub?.cancel();
    _blockedBySub = FirebaseFirestore.instance
        .collection('blockedBy')
        .doc(myUid)
        .collection('blockers')
        .snapshots()
        .listen(
      (snap) {
        _blockedByUids = snap.docs.map((d) => d.id).toSet();
        debugPrint('[Nearby] blockedByUids updated: ${_blockedByUids.length}');
        if (!completer.isCompleted) {
          completer.complete();
        } else if (mounted && _myUid != null && _cellSubs.isNotEmpty) {
          _rebuildList(_myUid!);
        }
      },
      onError: (Object e) {
        debugPrint('[Nearby] blockedBy stream error (non-fatal): $e');
        if (!completer.isCompleted) completer.complete();
      },
    );
    return completer.future;
  }

  /// Opens one Firestore snapshot stream per geohash cell prefix against the
  /// `live_sessions` collection.  Each stream result completely replaces that
  /// cell's entry in [_cellSnapshots], which correctly handles users going
  /// offline (terminal docs clear their geohash, so they drop out of the
  /// prefix range query).
  ///
  /// Query shape MUST match the security rule: the rule requires
  /// `status == 'active' && visibilityState == 'discoverable'` on every
  /// cross-user read, and Firestore only accepts the listener if both
  /// conditions are proven at the query level.  Omitting either filter
  /// triggers a permission-denied error on the stream itself.
  void _subscribeCells(String myUid, List<String> hashes) {
    for (final sub in _cellSubs) {
      sub.cancel();
    }
    _cellSubs.clear();
    _subscribedHashes = hashes;

    debugPrint('[Nearby] subscribing to ${hashes.length} live_sessions cells: $hashes');

    final db = FirebaseFirestore.instance;
    for (final hash in hashes) {
      final sub = db
          .collection('live_sessions')
          .where('status', isEqualTo: 'active')
          .where('visibilityState', isEqualTo: 'discoverable')
          .where('geohash', isGreaterThanOrEqualTo: hash)
          .where('geohash', isLessThan: '$hash~')
          .snapshots()
          .listen((snap) {
        if (kDebugMode) {
          final uids = snap.docs.map((d) => d.id).toList();
          debugPrint('[Nearby/cell] hash=$hash size=${snap.docs.length} '
              'uids=$uids');
        }
        _cellSnapshots[hash] = {
          for (final doc in snap.docs) doc.id: doc.data(),
        };
        // Kick off any missing profile loads; _rebuildList is idempotent so
        // the initial pass before profiles land is safe (users without a
        // cached profile are skipped and re-evaluated once the fetch returns).
        for (final uid in snap.docs.map((d) => d.id)) {
          if (uid != myUid) _ensureProfileLoaded(uid, myUid);
        }
        if (mounted) _rebuildList(myUid);
      }, onError: (Object e) {
        _handleCellStreamError(hash, e);
      });
      _cellSubs.add(sub);
    }
  }

  /// Classify a Firestore stream error and surface it through the discovery
  /// error state so the UI stops rendering an empty carousel.
  ///
  /// Three classes are distinguished:
  ///   • `failed-precondition` — the composite index needed by the query
  ///     hasn't been deployed.  Firestore embeds a "create index" URL in the
  ///     [FirebaseException.message]; we preserve it in [_discoveryErrorDetail]
  ///     so a developer running on a real device can copy it directly.
  ///   • `permission-denied`   — the live_sessions discovery rule rejected
  ///     the listener.  Almost always means rules changed without a deploy or
  ///     the query shape no longer matches the rule's required equalities.
  ///   • anything else         — surfaced as `streamUnknown` with the raw
  ///     message attached.  Catches network drops, unauthenticated reads, etc.
  ///
  /// First error wins.  Multiple cell subscriptions can hit the same backend
  /// fault simultaneously; we don't want them ping-ponging the error UI.
  void _handleCellStreamError(String hash, Object e) {
    debugPrint('[Nearby] live_sessions cell stream error '
        '(hash=$hash): $e');
    if (!mounted) return;
    if (_discoveryError != null) return;

    final classified = _classifyStreamError(e);
    final detail = e is FirebaseException
        ? '${e.code}: ${e.message ?? '(no message)'}'
        : e.toString();
    setState(() {
      _discoveryError = classified;
      _discoveryErrorDetail = detail;
      _loadingDiscovery = false;
    });
  }

  _DiscoveryError _classifyStreamError(Object e) {
    if (e is FirebaseException) {
      switch (e.code) {
        case 'failed-precondition':
          return _DiscoveryError.streamMissingIndex;
        case 'permission-denied':
          return _DiscoveryError.streamPermissionDenied;
      }
    }
    return _DiscoveryError.streamUnknown;
  }

  /// Ensures the candidate's public profile is cached in [_profileCache].
  /// No-op if the uid is already cached or a fetch is already in flight.
  /// Triggers a [_rebuildList] once the profile lands so users that
  /// appeared before their profile was ready get re-evaluated.
  ///
  /// Read order (issued in parallel, each handled independently):
  ///   1. `profiles/{uid}` — canonical public-profile source.  Auth-readable
  ///      for any signed-in user, so this is the primary path for display
  ///      fields (firstName, age, bio, hometown, occupation, height,
  ///      lookingFor, gender, photoUrl, photoUrls).
  ///   2. `users/{uid}`    — best-effort overlay for `plan`, `status`, and
  ///      legacy backfill.  Cross-user read of users/{uid} is rule-gated on
  ///      `resource.data.isLive == true`, so it can deny transiently when a
  ///      candidate's users-mirror lags their live_sessions doc.
  ///
  /// Resilience contract — Future.wait fail-fast was the previous bug:
  ///   • profiles success + users failure → cache from profiles; log overlay
  ///     denied; candidate IS surfaced.
  ///   • profiles missing + users success → cache from users (legacy path);
  ///     candidate IS surfaced.
  ///   • both unusable → no cache; candidate stays in `profile_loading`.
  ///
  /// Profiles is the canonical source.  A users/{uid} read failure must NOT
  /// strand a candidate at `profile_loading` — that was producing the
  /// "Nearby sees the live session but the candidate never finishes loading"
  /// symptom from the debug overlay (`included=0`, `profile_loading: 1`).
  void _ensureProfileLoaded(String uid, String myUid) {
    if (_profileCache.containsKey(uid)) return;
    if (_profileInFlight.contains(uid)) return;
    _profileInFlight.add(uid);
    final db = FirebaseFirestore.instance;

    // Each future resolves to its data map (or null on miss/failure).  Wrapping
    // both in their own catchError means one source's failure can't cancel the
    // other — Future.wait is fail-fast and was the original bug.
    final profilesFuture = db
        .collection('profiles')
        .doc(uid)
        .get()
        .then<Map<String, dynamic>?>((snap) => snap.exists ? snap.data() : null)
        .catchError((Object e) {
      debugPrint('[Nearby] profiles/$uid read failed: $e');
      return null;
    });
    final usersFuture = db
        .collection('users')
        .doc(uid)
        .get()
        .then<Map<String, dynamic>?>((snap) => snap.exists ? snap.data() : null)
        .catchError((Object e) {
      // Cross-user users/{uid} reads are rule-gated on isLive==true; transient
      // mirror lag produces permission-denied here.  Surface it as a non-fatal
      // overlay failure so we can tell it apart from a true profiles miss.
      debugPrint('[Nearby] users/$uid overlay denied (non-fatal): $e');
      return null;
    });

    Future.wait([profilesFuture, usersFuture]).then((results) {
      _profileInFlight.remove(uid);
      final profileData = results[0];
      final userData = results[1];

      if (profileData == null && userData == null) {
        // Both unusable — profiles missing AND users overlay unreadable.
        // Candidate intentionally stays at profile_loading so the next
        // _ensureProfileLoaded tick (e.g. on a live_sessions snapshot) can
        // retry.  No cache write means no stale exclusion either.
        debugPrint(
            '[Nearby] no usable profile for $uid (profiles missing, users overlay denied)');
        return;
      }

      // Merge: users first so plan/status land, profiles second so canonical
      // display fields override any users mirror that might still be there.
      final merged = <String, dynamic>{
        if (userData != null) ...userData,
        if (profileData != null) ...profileData,
      };

      // ── Photo-field reconciliation ────────────────────────────────────
      // The naive spread above lets an EMPTY profiles.photoUrls (or a
      // missing primary photoUrl) erase a populated users mirror — that
      // produced the "Nearby hero rail is missing the gallery" symptom
      // for accounts that hadn't fully written through to profiles yet.
      // Pick the populated value across both sources, profile wins ties,
      // so a real gallery is never silently dropped.
      List<String> populatedUrls(dynamic raw) {
        if (raw is List) {
          return raw
              .whereType<String>()
              .where((s) => s.isNotEmpty)
              .toList(growable: false);
        }
        return const [];
      }
      String? populatedString(dynamic raw) =>
          (raw is String && raw.isNotEmpty) ? raw : null;

      final profileUrls = populatedUrls(profileData?['photoUrls']);
      final userUrls = populatedUrls(userData?['photoUrls']);
      final chosenUrls = profileUrls.isNotEmpty ? profileUrls : userUrls;
      if (chosenUrls.isNotEmpty) {
        merged['photoUrls'] = chosenUrls;
      } else {
        merged.remove('photoUrls');
      }

      // primaryPhotoUrl is the new canonical name; older readers (and the
      // _NearbyUser.fromJoin builder below) still expect 'photoUrl'.
      // Resolution order picks the first populated value across BOTH docs
      // and BOTH field names, then falls back to the gallery's first
      // entry — symmetric with the photoUrls merge above.
      final chosenPhotoUrl = populatedString(profileData?['photoUrl']) ??
          populatedString(profileData?['primaryPhotoUrl']) ??
          populatedString(userData?['photoUrl']) ??
          populatedString(userData?['primaryPhotoUrl']) ??
          (chosenUrls.isNotEmpty ? chosenUrls.first : null);
      if (chosenPhotoUrl != null) {
        merged['photoUrl'] = chosenPhotoUrl;
      } else {
        merged.remove('photoUrl');
      }

      // Distinct logging for the "profiles ok, overlay denied" path so the
      // debug overlay's `profile_loading` count vs. `included` count can be
      // reconciled to a real cause without re-running.
      if (profileData != null && userData == null) {
        debugPrint(
            '[Nearby] $uid cached from profiles only (users overlay unavailable)');
      } else if (profileData == null && userData != null) {
        debugPrint(
            '[Nearby] $uid cached from users only (profiles doc missing — legacy)');
      }

      _profileCache[uid] = merged;
      if (mounted && _cellSubs.isNotEmpty) _rebuildList(myUid);
    }).catchError((Object e) {
      // Defensive — every leaf future has its own catch, so this only fires on
      // an unexpected error in the merge step itself.
      _profileInFlight.remove(uid);
      debugPrint('[Nearby] profile merge failed for $uid (non-fatal): $e');
    });
  }

  /// Merges all cell snapshots, joins with cached user profiles, applies
  /// filters, and updates [_nearbyUsers].
  ///
  /// Data sources per candidate:
  ///   - `sess` (live_sessions/{uid}): position (lat/lng/locationUpdatedAt),
  ///     visibilityState, and the SESSION SNAPSHOTS
  ///     (interestedInSnapshot, ageRangeMinSnapshot, ageRangeMaxSnapshot) —
  ///     these are frozen at the candidate's Go Live time and are the
  ///     authoritative values for mutual filtering.  The legacy
  ///     `showMeSnapshot` key is also read as a fallback so any pre-cutover
  ///     session still in flight keeps filtering correctly until it expires
  ///     (max 1 h window).
  ///   - `prof` (users/{uid}, via _profileCache): stable identity fields
  ///     only — firstName, age, gender, bio, photoUrl, plan, status, hometown,
  ///     occupation, height, lookingFor.
  ///
  /// Mid-session edits to users/{uid}.{interestedIn, ageRangeMin/Max,
  /// maxDistanceMeters} do NOT reach this filter — neither for me (I use my
  /// own session snapshots captured at Go Live) nor for the candidate (I read
  /// their `*Snapshot` fields off their session doc).
  void _rebuildList(String myUid) {
    final lat = _myLat;
    final lng = _myLng;

    // Flatten all cells, deduplicating by uid (a user near a cell boundary
    // can appear in multiple adjacent cell streams).
    final merged = <String, Map<String, dynamic>>{};
    for (final cell in _cellSnapshots.values) {
      merged.addAll(cell);
    }

    final exclusionCounts = <String, int>{};
    final passing = <MapEntry<String, Map<String, dynamic>>>[];
    for (final entry in merged.entries) {
      final reason = _candidateExclusionReason(
        uid: entry.key,
        sess: entry.value,
        myUid: myUid,
        myLat: lat,
        myLng: lng,
      );
      if (reason == null) {
        passing.add(entry);
      } else {
        exclusionCounts.update(reason, (n) => n + 1, ifAbsent: () => 1);
      }
    }

    final users = passing
        .map((e) => _NearbyUser.fromJoin(
              uid: e.key,
              session: e.value,
              profile: _profileCache[e.key]!,
            ))
        .whereType<_NearbyUser>()
        .toList();

    // Per-rebuild summary log.  This is the primary diagnostic for
    // two-phone testing: one line per rebuild that says exactly which gate
    // dropped how many candidates.  If the total is 0 you know the cell
    // streams aren't returning anything (index/rules issue, no live peers,
    // or a geohash window mismatch).  If the total is > 0 but `included` is
    // 0, the breakdown tells you which filter is the culprit.
    debugPrint('[Nearby/rebuild] cells=${_cellSnapshots.length} '
        'candidates=${merged.length} included=${users.length} '
        'excluded=$exclusionCounts');

    // Empty-result diagnostic: when nobody is being shown, dump the
    // current user's own live_sessions state so we can prove on device
    // whether the issue is our own query-eligibility (status,
    // visibilityState, geohash) versus an actual lack of nearby peers.
    if (kDebugMode && users.isEmpty) {
      final me = _liveSession?.currentSession;
      if (me == null) {
        debugPrint('[Nearby/self] currentSession=null (not live or not '
            'hydrated yet)');
      } else {
        debugPrint('[Nearby/self] '
            'status=${liveSessionStatusName(me.status)} '
            'visibility=${liveSessionVisibilityName(me.visibilityState)} '
            'currentMeetupId=${me.currentMeetupId} '
            'geohash=${me.geohash} '
            'lat=${me.lat} lng=${me.lng} '
            'subscribedHashes=$_subscribedHashes');
      }
    }

    // Sort closest first.
    if (lat != null && lng != null) {
      users.sort((a, b) {
        final da =
            LocationService.distanceMeters(lat, lng, a.lat, a.lng);
        final db =
            LocationService.distanceMeters(lat, lng, b.lat, b.lng);
        return da.compareTo(db);
      });
    }

    setState(() {
      _nearbyUsers = users;
      _lastCandidateCount = merged.length;
      _lastExclusionCounts = exclusionCounts;
      // Carousel has _nearbyUsers.length + 1 pages (the trailing end-cap
      // sits at index _nearbyUsers.length).  If a user disappeared while
      // the controller was on the end-cap or a now-out-of-range index,
      // clamp back to the new end-cap so the controller stays in sync.
      // Skipped when _nearbyUsers is empty because the build path returns
      // _buildEmptyState in that case (no PageView mounted).
      if (_nearbyUsers.isNotEmpty &&
          _currentIndex > _nearbyUsers.length) {
        _currentIndex = _nearbyUsers.length;
        if (_pageController.hasClients) {
          _pageController.jumpToPage(_currentIndex);
        }
      }
    });
  }

  /// Returns null when the candidate passes every gate; otherwise returns a
  /// short reason code identifying which gate excluded them.  Reason codes
  /// are stable strings — they're aggregated into [_lastExclusionCounts] and
  /// printed by the per-rebuild summary log, so changing them changes the
  /// diagnostic surface.
  ///
  /// Reason codes:
  ///   `self`                       — the candidate is me
  ///   `i_blocked_them`             — in my blockedUsers list
  ///   `they_blocked_me`            — in blockedBy/{me}/blockers
  ///   `profile_loading`            — public profile not yet cached
  ///   `under_review` / `suspended` — account-status gate
  ///   `gender_mismatch_my`         — my interestedIn doesn't match their gender
  ///   `age_mismatch_my`            — they're outside my age range
  ///   `gender_mismatch_theirs`     — their interestedIn doesn't match my gender
  ///   `age_mismatch_theirs`        — I'm outside their age range
  ///   `missing_lat_lng`            — session doc has no position fields yet
  ///   `no_self_position`           — I haven't resolved my own GPS yet
  ///   `missing_location_timestamp` — session has no locationUpdatedAt
  ///   `location_stale`             — last updated > stale threshold
  ///   `out_of_range_my`            — beyond MY maxDistance snapshot
  ///   `out_of_range_theirs`        — beyond THEIR maxDistance snapshot
  String? _candidateExclusionReason({
    required String uid,
    required Map<String, dynamic> sess,
    required String myUid,
    required double? myLat,
    required double? myLng,
  }) {
    if (uid == myUid) return 'self';
    if (_blockedUids.contains(uid)) return 'i_blocked_them';
    if (_blockedByUids.contains(uid)) return 'they_blocked_me';

    final prof = _profileCache[uid];
    if (prof == null) return 'profile_loading';

    final status = (prof['status'] as String?) ?? 'active';
    if (status == 'under_review') return 'under_review';
    if (status == 'suspended') return 'suspended';

    // ── Mutual preference filtering ────────────────────────────────────
    // Both sides' values come from the SESSION snapshots, not from the
    // mutable users doc, so that a mid-session Settings edit by either
    // party cannot re-enter the running session.

    final theirGender = prof['gender'] as String? ?? '';
    final theirAge = (prof['age'] as num?)?.toInt();

    final myInterestedIn = _myInterestedIn;
    if (myInterestedIn != null &&
        myInterestedIn != 'everyone' &&
        !_genderMatchesInterestedIn(theirGender, myInterestedIn)) {
      return 'gender_mismatch_my';
    }

    if (theirAge != null &&
        (theirAge < _myAgeRangeMin || theirAge > _myAgeRangeMax)) {
      return 'age_mismatch_my';
    }

    // Their interestedIn snapshot applied to my (stable) gender.  The
    // legacy `showMeSnapshot` key is read as a fallback so any session
    // written before the cutover keeps filtering correctly until it
    // expires (max 1 h).
    final theirInterestedIn = (sess['interestedInSnapshot'] as String?) ??
        (sess['showMeSnapshot'] as String?) ??
        'everyone';
    final myGender = _myGender;
    if (myGender != null &&
        theirInterestedIn != 'everyone' &&
        !_genderMatchesInterestedIn(myGender, theirInterestedIn)) {
      return 'gender_mismatch_theirs';
    }

    final theirAgeMin = (sess['ageRangeMinSnapshot'] as num?)?.toInt() ??
        AppConstants.minAge;
    final theirAgeMax = (sess['ageRangeMaxSnapshot'] as num?)?.toInt() ?? 99;
    final myAge = _myAge;
    if (myAge != null && (myAge < theirAgeMin || myAge > theirAgeMax)) {
      return 'age_mismatch_theirs';
    }

    // ── Position + freshness (from live_sessions) ──────────────────────
    final uLat = (sess['lat'] as num?)?.toDouble();
    final uLng = (sess['lng'] as num?)?.toDouble();
    if (uLat == null || uLng == null) return 'missing_lat_lng';
    if (myLat == null || myLng == null) return 'no_self_position';

    final updatedAt = (sess['locationUpdatedAt'] as Timestamp?)?.toDate();
    if (updatedAt == null) return 'missing_location_timestamp';
    final age = DateTime.now().difference(updatedAt).inSeconds;
    if (age > AppConstants.locationStaleThresholdSeconds) {
      return 'location_stale';
    }

    // Haversine is the authoritative distance gate.  SYMMETRIC: the pair
    // must be within BOTH sides' radius snapshots, mirroring the mutual
    // gender / age filters above.  A one-sided check (only my radius)
    // produces the iPhone-sees / Android-doesn't-see asymmetry — e.g. my
    // app would surface a candidate at 25 m because my snapshot is 30 m,
    // while their app, with a 10 m snapshot, would reject me at 25 m.
    // Geohash is only the coarse bounding-box query helper.
    final distance =
        LocationService.distanceMeters(myLat, myLng, uLat, uLng);
    if (distance > _effectiveRadiusMeters) return 'out_of_range_my';

    final theirRadiusMeters =
        (sess['maxDistanceMetersSnapshot'] as num?)?.toDouble() ??
            AppConstants.nearbyRadiusMeters;
    if (distance > theirRadiusMeters) return 'out_of_range_theirs';

    return null;
  }

  void _stopDiscovery() {
    _blockedUidsSub?.cancel();
    _blockedUidsSub = null;
    _blockedBySub?.cancel();
    _blockedBySub = null;
    for (final sub in _cellSubs) {
      sub.cancel();
    }
    _cellSubs.clear();
    _cellSnapshots.clear();
    _profileCache.clear();
    _profileInFlight.clear();
    _subscribedHashes = [];
    _nearbyUsers = [];
    _blockedUids = {};
    _blockedByUids = {};
    _myInterestedIn = null;
    _myGender = null;
    _myAge = null;
    _myAgeRangeMin = AppConstants.minAge;
    _myAgeRangeMax = 99;
    _effectiveRadiusMeters = AppConstants.nearbyRadiusMeters;
    _discoveryError = null;
    _discoveryErrorDetail = null;
    _lastCandidateCount = 0;
    _lastExclusionCounts = const {};
    _myUid = null;
    _myLat = null;
    _myLng = null;
  }

  // ── Block ─────────────────────────────────────────────────────────────────

  Future<void> _blockUser(_NearbyUser user) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // Capture full pre-block state so an optimistic-UI rollback on Firestore
    // failure restores the carousel exactly as it was: list index, paging
    // controller index, blocked-uid set, and the per-cell snapshot entries
    // that the Nearby rebuild merges from.  Without these, a rule rejection
    // (e.g. rules not deployed, source not in allowlist, cross-uid mismatch)
    // would leave the UI in a half-state where the user is gone from view
    // but never actually blocked server-side.
    final previousIndex = _nearbyUsers.indexWhere((u) => u.id == user.id);
    final previousPageIndex = _currentIndex;
    final removedCellEntries = <String, Map<String, dynamic>>{};
    for (final entry in _cellSnapshots.entries) {
      final removed = entry.value.remove(user.id);
      if (removed != null) removedCellEntries[entry.key] = removed;
    }

    // Optimistic removal.
    setState(() {
      _blockedUids.add(user.id);
      _nearbyUsers.removeWhere((u) => u.id == user.id);
      if (_nearbyUsers.isNotEmpty) {
        _currentIndex = _currentIndex.clamp(0, _nearbyUsers.length - 1);
        if (_pageController.hasClients) {
          _pageController.jumpToPage(_currentIndex);
        }
      }
    });

    try {
      // Triple-write through BlocksRepository — keeps the canonical blocks/{...}
      // collection, forward index, and reverse index in lockstep.  source is
      // 'nearby' so moderation can distinguish drive-by blocks from chat blocks.
      await BlocksRepository().block(
        blockerId: uid,
        blockedId: user.id,
        source: 'nearby',
        blockedDisplayName: user.firstName,
        blockedPhotoUrl: user.photoUrl,
      );
      debugPrint('[Block] blocked ${user.id} (${user.firstName})');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${user.firstName} has been blocked.'),
            backgroundColor: AppColors.bgElevated,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } catch (e) {
      debugPrint('[Block] Firestore write failed: $e');
      // Roll back the optimistic UI so the user understands the block did
      // not land server-side.  Restore cell snapshots first so the next
      // _rebuildList tick can re-include the user; then restore the list
      // and page index in setState so the carousel snaps back to where it
      // was.
      for (final entry in removedCellEntries.entries) {
        _cellSnapshots[entry.key]?[user.id] = entry.value;
      }
      if (!mounted) return;
      setState(() {
        _blockedUids.remove(user.id);
        if (previousIndex >= 0 && previousIndex <= _nearbyUsers.length) {
          _nearbyUsers.insert(previousIndex, user);
          _currentIndex = previousPageIndex.clamp(0, _nearbyUsers.length - 1);
          if (_pageController.hasClients) {
            _pageController.jumpToPage(_currentIndex);
          }
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Couldn't block ${user.firstName}. Check your connection and try again.",
            style: AppTextStyles.bodyS.copyWith(color: Colors.white),
          ),
          backgroundColor: AppColors.bgElevated,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'Retry',
            textColor: AppColors.brandCyan,
            onPressed: () => _blockUser(user),
          ),
        ),
      );
    }
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  void _navigateSendIcebreaker(_NearbyUser user) {
    final session = LiveSessionScope.of(context);
    if (session.icebreakerCredits <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No Icebreakers left — visit the Shop to get more.',
            style: AppTextStyles.bodyS.copyWith(color: Colors.white),
          ),
          backgroundColor: AppColors.bgElevated,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: 'Shop',
            textColor: AppColors.brandCyan,
            onPressed: () => context.push(AppRoutes.shop),
          ),
        ),
      );
      return;
    }

    context.push(
      AppRoutes.sendIcebreaker,
      extra: {
        'recipientId': user.id,
        'firstName': user.firstName,
        'age': user.age,
        'photoUrl': user.photoUrl,
        'bio': user.bio,
      },
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: _buildAppBar(),
      body: SafeArea(
        top: false,
        child: LiveSessionScope.isLive(context)
            ? _buildDiscovery()
            : _buildNotLiveGate(),
      ),
    );
  }

  // ── App bar ───────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      title: Text('Nearby', style: AppTextStyles.h3),
      actions: [
        // The tune icon used to open a sibling Discovery filter sheet that
        // wrote the (now-retired) `showMe` field directly to users/{uid}.
        // Edit Profile owns these preferences end-to-end now; we deep-link
        // into its preferences section so there is one canonical surface
        // for interestedIn / age range / max distance.
        IconButton(
          icon: const Icon(Icons.tune_rounded,
              color: AppColors.textSecondary),
          onPressed: () =>
              context.push(AppRoutes.editProfile, extra: 'preferences'),
        ),
      ],
    );
  }

  // ── Discovery layout ──────────────────────────────────────────────────────

  Widget _buildDiscovery() {
    if (_loadingDiscovery) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.brandPink),
      );
    }

    if (_discoveryError != null) return _buildLocationErrorState(_discoveryError!);

    if (_nearbyUsers.isEmpty) return _buildEmptyState();

    // Each outer page owns BOTH the focus card and the about-me card so that
    // horizontal drags on the about-me area drive the between-people swipe
    // (the focus card's photo region runs its own inner PageView for that
    // user's image rail).  See NearbyFocusCard's gesture-model doc comment.
    //
    // Vertical sizing is locked via LayoutBuilder against the body's
    // available height: ~72% to the hero card, ~28% to about-me.  Combined
    // with the app bar (~10% of total screen) this lands at the target
    // 65/25/10 silhouette and is stable across phone sizes regardless of
    // about-me tag count, since SizedBox heights don't grow with content.
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableH = constraints.maxHeight;
        final heroH = availableH * 0.72;
        final aboutH = availableH * 0.28;

        // One trailing page beyond the user list is the end-cap so the
        // outer carousel still feels swipeable when there's only one
        // person nearby — and so users with a long list can naturally
        // arrive at "you're caught up" rather than dead-ending on the
        // last person.
        final pageCount = _nearbyUsers.length + 1;
        final endCapIndex = _nearbyUsers.length;

        return PageView.builder(
          controller: _pageController,
          clipBehavior: Clip.none,
          itemCount: pageCount,
          onPageChanged: (i) => setState(() => _currentIndex = i),
          itemBuilder: (context, i) {
            final isActive = i == _currentIndex;
            final pageContent = i == endCapIndex
                ? _buildEndCapPage()
                : _buildUserPage(_nearbyUsers[i], heroH, aboutH, isActive);
            // Page-level scale + opacity gives the hero card and about-me
            // (or the end-cap) a single unified inactive treatment —
            // without this the about-me card on a neighbouring (peeking)
            // page would render full-bright and break the visual page
            // boundary.
            return AnimatedScale(
              scale: isActive ? 1.0 : 0.94,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              child: AnimatedOpacity(
                opacity: isActive ? 1.0 : 0.55,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                child: pageContent,
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildUserPage(
      _NearbyUser u, double heroH, double aboutH, bool isActive) {
    return Column(
      children: [
        SizedBox(
          height: heroH,
          child: NearbyFocusCard(
            // Key by recipient so a card rebuilt for a different user
            // gets fresh State — without this the inner image-rail
            // PageController would carry the previous user's _imageIndex
            // into the new user's rail.
            key: ValueKey('focus_${u.id}'),
            recipientId: u.id,
            firstName: u.firstName,
            age: u.age,
            images: u.displayImages,
            isGold: u.isGold,
            isActive: isActive,
            onSendIcebreaker: () => _navigateSendIcebreaker(u),
            onBlock: () => _blockUser(u),
          ),
        ),
        SizedBox(
          height: aboutH,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            // Graceful overflow — a profile with many tags can exceed the
            // 28% slice; SingleChildScrollView keeps the page silhouette
            // fixed while letting the user reach the full content.
            // Vertical only, so horizontal drags still drive the outer
            // PageView.
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: NearbyAboutMeCard(
                age: u.age,
                bio: u.bio,
                hometown: u.hometown,
                occupation: u.occupation,
                height: u.height,
                lookingFor: u.lookingFor,
                interests: u.interests,
                hobbies: u.hobbies,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Trailing page in the outer Nearby carousel — communicates "you're
  /// caught up" without reading as an error state.  Surfaces a Refresh CTA
  /// (rebuilds the discovery streams) and a quieter "Edit preferences"
  /// link to the same destination as the app-bar tune button, so a user
  /// who's reached the end can re-cast the radius/age/gender net without
  /// leaving the screen.
  Widget _buildEndCapPage() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const IcebreakerLogo(size: 72, showGlow: true),
            const SizedBox(height: 24),
            Text(
              "You're caught up",
              style: AppTextStyles.h3,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'No one else nearby right now.\nCheck back soon.',
              style: AppTextStyles.bodyS.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            PillButton.primary(
              label: 'Refresh',
              onTap: _retryDiscovery,
              height: 48,
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () =>
                  context.push(AppRoutes.editProfile, extra: 'preferences'),
              child: Text(
                'Edit preferences',
                style: AppTextStyles.bodyS.copyWith(
                  color: AppColors.brandCyan,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Empty / gate states ───────────────────────────────────────────────────

  Widget _buildEmptyState() {
    final radius = _effectiveRadiusMeters.toInt();
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const IcebreakerLogo(size: 72, showGlow: true),
            const SizedBox(height: 24),
            Text(
              'No one nearby right now',
              style: AppTextStyles.h3,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Check back when you\'re out —\n'
              'users only appear within $radius metres.',
              style: AppTextStyles.bodyS,
              textAlign: TextAlign.center,
            ),
            if (kDebugMode) _buildDevDiagnostics(),
          ],
        ),
      ),
    );
  }

  /// Debug-only breakdown rendered under the "no one nearby" empty state.
  ///
  /// Tells you, on a real device, exactly which gate is dropping candidates
  /// for the current rebuild.  Stripped from release builds via [kDebugMode].
  Widget _buildDevDiagnostics() {
    final entries = _lastExclusionCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.bgInput,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Debug — last rebuild',
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'cells=${_cellSnapshots.length}  '
              'candidates=$_lastCandidateCount  '
              'included=${_nearbyUsers.length}',
              style: AppTextStyles.caption.copyWith(
                fontFamily: 'monospace',
                color: AppColors.textSecondary,
              ),
            ),
            if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'no exclusions — likely no peer matches the query',
                  style: AppTextStyles.caption.copyWith(
                    fontFamily: 'monospace',
                    color: AppColors.textMuted,
                  ),
                ),
              )
            else ...[
              const SizedBox(height: 6),
              for (final e in entries)
                Text(
                  '${e.key.padRight(28)} ${e.value}',
                  style: AppTextStyles.caption.copyWith(
                    fontFamily: 'monospace',
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
            // Self-state — surfaces the owner's session fields so a two-phone
            // test can immediately tell whether the empty result is "I'm not
            // discoverable" vs "the peer isn't discoverable" vs "we're in
            // different cells".  Pulled from the in-memory LiveSession model;
            // null when the session hasn't hydrated yet.
            const SizedBox(height: 10),
            Text(
              'My session',
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Builder(builder: (_) {
              final me = _liveSession?.currentSession;
              if (me == null) {
                return Text(
                  'session not hydrated yet',
                  style: AppTextStyles.caption.copyWith(
                    fontFamily: 'monospace',
                    color: AppColors.textMuted,
                  ),
                );
              }
              return DefaultTextStyle(
                style: AppTextStyles.caption.copyWith(
                  fontFamily: 'monospace',
                  color: AppColors.textSecondary,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('status     ${liveSessionStatusName(me.status)}'),
                    Text('visibility ${liveSessionVisibilityName(me.visibilityState)}'),
                    Text('geohash    ${me.geohash ?? '(null — gps not landed)'}'),
                    Text('meetupId   ${me.currentMeetupId ?? '(none)'}'),
                    Text('subscribed ${_subscribedHashes.length} cells'
                        '${_subscribedHashes.isEmpty ? '' : ' (e.g. ${_subscribedHashes.first})'}'),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  /// Returns true when [gender] is compatible with an [interestedIn] preference.
  ///
  /// gender values       : 'male' | 'female' | 'non_binary' | 'other'
  /// interestedIn values : 'everyone' | 'men' | 'women' | 'non_binary'
  bool _genderMatchesInterestedIn(String gender, String interestedIn) {
    if (interestedIn == 'everyone') return true;
    if (interestedIn == 'men') return gender == 'male';
    if (interestedIn == 'women') return gender == 'female';
    if (interestedIn == 'non_binary') return gender == 'non_binary';
    return true; // unrecognised value — don't filter
  }

  void _retryDiscovery() {
    _stopDiscovery();
    _startDiscovery();
  }

  /// Tapped when the error state is `permissionRequestable`: presents the
  /// OS dialog inline, then re-enters discovery.  This is the path that
  /// avoids the iOS Settings dead-end — we never bounce the user to a page
  /// that doesn't yet have a Location row.
  Future<void> _requestLocationAndRetry() async {
    final status = await LocationService.requestIfNeeded();
    if (!mounted) return;
    if (status == LocationStatus.granted) {
      _retryDiscovery();
    } else {
      // Re-render with the new status — denial may have transitioned
      // requestable → blockedForever, in which case the CTA flips to
      // "Open Settings".
      setState(() => _discoveryError = _DiscoveryError.fromStatus(status));
    }
  }

  Widget _buildLocationErrorState(_DiscoveryError error) {
    if (error.isStreamFailure) return _buildStreamErrorState(error);

    final isGpsFailure = error == _DiscoveryError.gpsFailed;
    final isRequestable = error == _DiscoveryError.permissionRequestable;
    final isServicesOff = error == _DiscoveryError.servicesDisabled;

    final title = switch (error) {
      _DiscoveryError.gpsFailed => 'Could not get your location',
      _DiscoveryError.servicesDisabled => 'Location Services are off',
      _DiscoveryError.permissionRequestable ||
      _DiscoveryError.permissionBlocked =>
        'Location access needed',
      // Stream variants short-circuit above, but the switch must be exhaustive.
      _DiscoveryError.streamMissingIndex ||
      _DiscoveryError.streamPermissionDenied ||
      _DiscoveryError.streamUnknown =>
        '',
    };

    final body = switch (error) {
      _DiscoveryError.gpsFailed =>
        'GPS timed out or is unavailable.\nTry again when you have a signal.',
      _DiscoveryError.servicesDisabled =>
        'Turn on Location Services in system\nSettings, then try again.',
      _DiscoveryError.permissionRequestable =>
        'Icebreaker needs location permission\nto show who\'s nearby.',
      _DiscoveryError.permissionBlocked =>
        'Location is blocked for Icebreaker.\nEnable it in system Settings.',
      _DiscoveryError.streamMissingIndex ||
      _DiscoveryError.streamPermissionDenied ||
      _DiscoveryError.streamUnknown =>
        '',
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isGpsFailure ? Icons.gps_off_rounded : Icons.location_off_rounded,
              color: AppColors.textMuted,
              size: 56,
            ),
            const SizedBox(height: 24),
            Text(title, style: AppTextStyles.h3, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(body, style: AppTextStyles.bodyS, textAlign: TextAlign.center),
            const SizedBox(height: 28),
            // Primary action depends on the state:
            //   • requestable    → in-app prompt (avoids the Settings dead-end)
            //   • blocked / off  → system Settings
            //   • gpsFailed      → no primary; just Retry below
            if (isRequestable) ...[
              PillButton.primary(
                label: 'Allow Location',
                icon: Icons.location_on_rounded,
                onTap: _requestLocationAndRetry,
                width: double.infinity,
                height: 48,
              ),
              const SizedBox(height: 12),
            ] else if (!isGpsFailure) ...[
              PillButton.primary(
                label: 'Open Settings',
                icon: Icons.settings_rounded,
                onTap: LocationService.openSettings,
                width: double.infinity,
                height: 48,
              ),
              const SizedBox(height: 12),
            ],
            PillButton.outlined(
              label: 'Retry',
              icon: Icons.refresh_rounded,
              onTap: _retryDiscovery,
              width: double.infinity,
              height: 48,
            ),
            if (isServicesOff) ...[
              const SizedBox(height: 12),
              Text(
                'On iPhone: Settings → Privacy & Security → Location Services.',
                style: AppTextStyles.caption,
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Dev-facing error UI for the live_sessions cell stream failure modes.
  ///
  /// This is intentionally not consumer-polished: the goal is to make the
  /// underlying Firestore fault diagnosable on a real device without needing
  /// the debugger.  It surfaces:
  ///   • a one-line plain-English title
  ///   • a one-paragraph cause + recovery hint
  ///   • the raw `code: message` string from the FirebaseException — for
  ///     `failed-precondition` this contains the Console "create index" URL
  ///   • the firebase-cli command needed to deploy from the repo
  ///   • a Retry button that re-enters discovery
  Widget _buildStreamErrorState(_DiscoveryError error) {
    final title = switch (error) {
      _DiscoveryError.streamMissingIndex => 'Discovery index missing',
      _DiscoveryError.streamPermissionDenied => 'Discovery rule rejected',
      _DiscoveryError.streamUnknown => 'Discovery query failed',
      _ => 'Discovery error',
    };

    final body = switch (error) {
      _DiscoveryError.streamMissingIndex =>
        'The live_sessions composite index is not deployed.\n'
            'Deploy `firestore.indexes.json` to recover.',
      _DiscoveryError.streamPermissionDenied =>
        'Firestore rejected the live_sessions listener.\n'
            'Check that `firestore.rules` has been deployed and the '
            'discovery rule still allows '
            '(visibilityState == "discoverable", status == "active").',
      _DiscoveryError.streamUnknown =>
        'A Firestore stream error stopped Nearby.\n'
            'See the detail line below.',
      _ => '',
    };

    final deployHint = switch (error) {
      _DiscoveryError.streamMissingIndex =>
        'firebase deploy --only firestore:indexes',
      _DiscoveryError.streamPermissionDenied =>
        'firebase deploy --only firestore:rules',
      _DiscoveryError.streamUnknown => null,
      _ => null,
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_off_rounded,
                color: AppColors.textMuted,
                size: 56,
              ),
              const SizedBox(height: 24),
              Text(title,
                  style: AppTextStyles.h3, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(body,
                  style: AppTextStyles.bodyS, textAlign: TextAlign.center),
              if (deployHint != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.bgInput,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Text(
                    deployHint,
                    style: AppTextStyles.caption.copyWith(
                      fontFamily: 'monospace',
                      color: AppColors.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
              if (_discoveryErrorDetail != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.bgInput,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Text(
                    _discoveryErrorDetail!,
                    style: AppTextStyles.caption.copyWith(
                      fontFamily: 'monospace',
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              PillButton.outlined(
                label: 'Retry',
                icon: Icons.refresh_rounded,
                onTap: _retryDiscovery,
                width: double.infinity,
                height: 48,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotLiveGate() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const IcebreakerLogo(size: 80, showGlow: true),
            const SizedBox(height: 28),
            Text(
              'Go Live to see\nwho\'s nearby',
              style: AppTextStyles.h2,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'You need an active Live session to\nbrowse people around you.',
              style: AppTextStyles.bodyS,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// _DiscoveryError
// ─────────────────────────────────────────────────────────────────────────────

/// One-to-one with the [LocationStatus] cases plus a [gpsFailed] case for
/// when permission is granted but the GPS fix itself didn't land.  Splitting
/// `permissionRequestable` from `permissionBlocked` is what lets the error
/// UI offer "Allow Location" (in-app prompt) vs "Open Settings" (system
/// recovery) — the iOS dead-end fix.
///
/// The `stream*` variants are not location-related at all — they cover
/// failures of the `live_sessions` cell streams themselves (missing index,
/// rejected rule, generic transport).  They share the same error scaffold
/// because the UX shape ("something is wrong with discovery, here's why,
/// here's how to recover") is the same; the body and CTA differ per case.
enum _DiscoveryError {
  /// Permission has not been granted but is still requestable in-app.
  /// UI: "Allow Location" primary action that calls requestIfNeeded().
  permissionRequestable,

  /// Permission has been permanently denied.  Recovery requires system
  /// Settings.  UI: "Open Settings" primary action.
  permissionBlocked,

  /// Device-wide Location Services switch is off.  Recovery requires
  /// system Settings (different page from the per-app permission row).
  servicesDisabled,

  /// Permission is granted but GPS timed out or returned null.
  /// UI: "Retry" only — no system Settings trip needed.
  gpsFailed,

  /// Firestore rejected the cell stream with `failed-precondition` —
  /// the (status, visibilityState, geohash) composite index hasn't been
  /// deployed.  The exception's message contains the create-index URL.
  streamMissingIndex,

  /// Firestore rejected the cell stream with `permission-denied` — the
  /// live_sessions discovery rule denied the listener (rules out of sync
  /// with the query shape, or rules not deployed).
  streamPermissionDenied,

  /// Any other stream error — network failure, unauthenticated read, etc.
  streamUnknown;

  static _DiscoveryError fromStatus(LocationStatus status) => switch (status) {
        LocationStatus.requestable => _DiscoveryError.permissionRequestable,
        LocationStatus.blockedForever => _DiscoveryError.permissionBlocked,
        LocationStatus.servicesDisabled => _DiscoveryError.servicesDisabled,
        LocationStatus.granted => _DiscoveryError.gpsFailed,
      };

  bool get isStreamFailure => switch (this) {
        streamMissingIndex ||
        streamPermissionDenied ||
        streamUnknown =>
          true,
        _ => false,
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// _NearbyUser
// ─────────────────────────────────────────────────────────────────────────────

class _NearbyUser {
  const _NearbyUser({
    required this.id,
    required this.firstName,
    required this.age,
    required this.bio,
    required this.photoUrl,
    required this.photoUrls,
    required this.liveSelfieUrl,
    required this.lat,
    required this.lng,
    this.hometown,
    this.occupation,
    this.height,
    this.lookingFor,
    this.interests = const [],
    this.hobbies = const [],
    this.isGold = false,
  });

  final String id;
  final String firstName;
  final int age;
  final String bio;

  /// Single primary profile photo — kept for any caller that still wants the
  /// "first photo only" projection (notifications, send-icebreaker extras).
  final String photoUrl;

  /// Ordered profile photo gallery from `profiles/{uid}.photoUrls`.  Empty
  /// list when the profile has no photos yet.  Empties are filtered out at
  /// build time.
  final List<String> photoUrls;

  /// Session-scoped Firebase Storage URL for this user's live verification
  /// selfie, when their active `live_sessions/{uid}` doc carries one.  Null
  /// for legacy session docs and for sessions whose Storage upload failed —
  /// the hero card falls back to [photoUrls] in that case.
  final String? liveSelfieUrl;

  final double lat;
  final double lng;
  final String? hometown;
  final String? occupation;
  final String? height;
  final String? lookingFor;

  /// Tag arrays sourced from the joined profile map.  Empty (not null) when
  /// the profile hasn't filled them in yet, so consumers can render
  /// unconditionally with an isEmpty gate instead of null-checking.
  final List<String> interests;
  final List<String> hobbies;

  final bool isGold;

  /// Ordered list of images to render on the Nearby hero card, deduped
  /// and stripped of empties.  Each entry is tagged with its [NearbyImageKind]
  /// so the rail can pick the right framing (live selfie → contained over a
  /// blurred backdrop, profile photo → cover) instead of treating every
  /// URL identically.
  ///
  ///   1. [liveSelfieUrl] first when present (kind=liveSelfie)
  ///   2. then each entry of [photoUrls] in profile order (kind=profilePhoto)
  ///   3. then [photoUrl] (the primary headshot) appended via dedupe — a
  ///      no-op when the gallery already contains it; surfaces the primary
  ///      when the gallery is empty (older accounts that never wrote
  ///      photoUrls) or when the primary lives outside the gallery
  ///
  /// Gallery ordering from [photoUrls] is preserved: the primary fallback
  /// is appended at the end so the curated order isn't reshuffled.
  ///
  /// Empty when the user has no live selfie, no gallery, AND no primary
  /// photo — the card falls back to its placeholder gradient.
  List<NearbyImage> get displayImages {
    final result = <NearbyImage>[];
    final seen = <String>{};
    void add(String? url, NearbyImageKind kind) {
      if (url == null) return;
      final v = url.trim();
      if (v.isEmpty) return;
      if (seen.add(v)) result.add(NearbyImage(url: v, kind: kind));
    }
    add(liveSelfieUrl, NearbyImageKind.liveSelfie);
    for (final u in photoUrls) {
      add(u, NearbyImageKind.profilePhoto);
    }
    add(photoUrl, NearbyImageKind.profilePhoto);
    return result;
  }

  /// Builds a _NearbyUser by joining a `live_sessions/{uid}` doc with the
  /// cached `users/{uid}` profile.  Returns null (and logs) if the session
  /// is missing position fields — this is the race window between the
  /// session being created (status=active) and the first GPS write landing.
  static _NearbyUser? fromJoin({
    required String uid,
    required Map<String, dynamic> session,
    required Map<String, dynamic> profile,
  }) {
    final lat = (session['lat'] as num?)?.toDouble();
    final lng = (session['lng'] as num?)?.toDouble();

    if (lat == null || lng == null) {
      debugPrint('[Nearby] skipping session $uid — position fields missing');
      return null;
    }

    // Hometown source priority:
    //   1. profiles/{uid}.hometownShort   (pre-formatted "City, ST")
    //   2. profiles/{uid}.hometown / users/{uid}.hometown   (map or string)
    // The pre-formatted short form is what the location-onboarding write
    // computes anyway; preferring it avoids re-formatting on every rebuild
    // and keeps the card identical to the canonical source.
    String? hometown;
    final hometownShort = profile['hometownShort'];
    if (hometownShort is String && hometownShort.isNotEmpty) {
      hometown = hometownShort;
    } else {
      final hometownRaw = profile['hometown'];
      if (hometownRaw is Map) {
        final city = hometownRaw['city'] as String? ?? '';
        final state = hometownRaw['stateCode'] as String? ??
            hometownRaw['state'] as String? ??
            '';
        hometown =
            [city, state].where((s) => s.isNotEmpty).join(', ');
      } else if (hometownRaw is String && hometownRaw.isNotEmpty) {
        hometown = hometownRaw;
      }
    }

    // Tag arrays land as `List<dynamic>` from Firestore; project to
    // `List<String>` and drop any non-string elements defensively.  Empty
    // list rather than null so the About Me card can render with a simple
    // isEmpty gate.
    List<String> tagList(dynamic raw) {
      if (raw is List) {
        return raw.whereType<String>().toList(growable: false);
      }
      return const [];
    }

    // photoUrls: the canonical ordered gallery written by ProfileMediaRepository.
    // Drop non-string and empty entries here so downstream consumers
    // (displayImages) don't have to defensively re-filter.
    final photoUrls = (profile['photoUrls'] is List)
        ? (profile['photoUrls'] as List)
            .whereType<String>()
            .where((s) => s.isNotEmpty)
            .toList(growable: false)
        : const <String>[];

    final rawSelfie = session['liveSelfieUrl'];
    final liveSelfieUrl =
        (rawSelfie is String && rawSelfie.isNotEmpty) ? rawSelfie : null;

    return _NearbyUser(
      id: uid,
      firstName: (profile['firstName'] as String?) ?? 'Someone',
      age: (profile['age'] as num?)?.toInt() ?? 0,
      bio: (profile['bio'] as String?) ?? '',
      photoUrl: (profile['photoUrl'] as String?) ?? '',
      photoUrls: photoUrls,
      liveSelfieUrl: liveSelfieUrl,
      lat: lat,
      lng: lng,
      hometown: hometown,
      occupation: profile['occupation'] as String?,
      height: profile['height'] as String?,
      lookingFor: profile['lookingFor'] as String?,
      interests: tagList(profile['interests']),
      hobbies: tagList(profile['hobbies']),
      isGold: (profile['plan'] as String?) == 'gold',
    );
  }
}
