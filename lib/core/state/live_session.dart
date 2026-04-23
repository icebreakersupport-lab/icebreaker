import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';

import '../constants/app_constants.dart';
import '../models/live_session_model.dart';
import '../services/live_session_repository.dart';
import '../services/location_service.dart';

/// In-memory live-presence state, backed by `live_sessions/{uid}` in Firestore.
///
/// Phase 1 dual-write: every live-presence mutation writes BOTH
///   - `live_sessions/{uid}` via [LiveSessionRepository] (new source of truth)
///   - legacy fields on `users/{uid}` (for existing Cloud Functions)
/// so rollback is safe and the notification / meetup functions keep working
/// untouched.  Phase 2 will drop the `users/{uid}` mirror.
///
/// This class still owns:
///   - the one-shot expiry timer (fires `endSession(expired)`)
///   - the 60-second location refresh timer
///   - the 24-hour icebreaker-credit reset timer + credit state
///   - a stream subscription to `live_sessions/{uid}` that reconciles
///     in-memory state whenever the doc changes (including Cloud Function
///     writes in Phase 2)
///   - a stream subscription to `users/{uid}.currentMeetupId` so meetup
///     entry/exit is mirrored into `live_sessions.visibilityState` during
///     Phase 1.
class LiveSession extends ChangeNotifier {
  LiveSession({LiveSessionRepository? repo})
      : _repo = repo ?? LiveSessionRepository();

  final LiveSessionRepository _repo;

  // ── Presence state (mirrors the Firestore doc) ─────────────────────────────

  bool _isLive = false;
  DateTime? _expiresAt;
  int _liveCredits = 1;
  String? _selfieFilePath;

  /// Full session model from the most recent snapshot, or null when there is
  /// no active/terminal doc for this user.  Exposed so UI that needs richer
  /// detail (verification method, visibility) can read it without a second
  /// query.
  LiveSessionModel? _currentSession;
  LiveSessionModel? get currentSession => _currentSession;

  // ── Timers ────────────────────────────────────────────────────────────────

  /// One-shot timer that calls `endSession(expired)` when the session expires.
  /// Always re-derived from `expiresAt` so it survives cold starts / resumes.
  Timer? _expiryTimer;

  /// Periodic timer that refreshes the user's GPS position every
  /// [AppConstants.locationUpdateIntervalSeconds] seconds while live.
  Timer? _locationTimer;

  /// One-shot timer for the 24-hour icebreaker-credit reset.  Fires
  /// [hydrateCredits] with the stored uid.
  Timer? _resetTimer;

  // ── Stream subscriptions ──────────────────────────────────────────────────

  /// Stream on `live_sessions/{uid}` — reconciles in-memory state.
  StreamSubscription<LiveSessionModel?>? _sessionSub;

  /// Stream on `users/{uid}` — used ONLY to observe `currentMeetupId`
  /// changes written by Cloud Functions, so we can mirror them into
  /// `live_sessions/{uid}.visibilityState` during Phase 1.  Remove in Phase 2
  /// when functions write visibility directly.
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _meetupMirrorSub;

  /// Last value we mirrored, so we don't re-write on every unrelated field change.
  String? _lastMirroredCurrentMeetupId;

  // ── Identity + credits ────────────────────────────────────────────────────

  /// UID of the currently signed-in user.
  String? _uid;

  int _icebreakerCredits = AppConstants.freeIcebreakerCreditsPerSignup;
  DateTime? _icebreakerCreditsResetAt;

  // ── Getters ───────────────────────────────────────────────────────────────

  bool get isLive => _isLive;
  DateTime? get expiresAt => _expiresAt;
  String? get selfieFilePath => _selfieFilePath;
  int get liveCredits => _liveCredits;
  int get icebreakerCredits => _icebreakerCredits;
  DateTime? get icebreakerCreditsResetAt => _icebreakerCreditsResetAt;

  /// Time remaining in the current session. Zero when not live or expired.
  Duration get remainingDuration {
    if (_expiresAt == null || !_isLive) return Duration.zero;
    final remaining = _expiresAt!.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  // ── Session mutators ──────────────────────────────────────────────────────

  /// Starts a new live session.  Writes to both `live_sessions/{uid}` (new
  /// source of truth) and the legacy `users/{uid}` mirror.
  ///
  /// [verificationMethod] captures which path proved identity for this
  /// session (real selfie on mobile, or one of the DEV Test Mode fallbacks).
  /// It is persisted so the session record clearly indicates what happened.
  Future<void> goLive({
    String? selfieFilePath,
    LiveVerificationMethod verificationMethod =
        LiveVerificationMethod.liveSelfie,
  }) async {
    final uid = _uid ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      debugPrint('[LiveSession] goLive: no uid — skipping');
      return;
    }

    _isLive = true;
    _expiresAt = DateTime.now().add(const Duration(hours: 1));
    if (selfieFilePath != null) _selfieFilePath = selfieFilePath;
    if (_liveCredits > 0) _liveCredits--;
    _scheduleExpiry();
    notifyListeners();

    // Snapshot discovery-relevant settings so Nearby can mutual-filter off the
    // session doc alone without a second users/{uid} read.
    final snap = await _readDiscoverySnapshot(uid);

    // 1. live_sessions/{uid} — new source of truth.
    try {
      await _repo.startSession(
        uid: uid,
        verificationMethod: verificationMethod,
        maxDistanceMetersSnapshot: snap.maxDistanceMeters,
        discoverableSnapshot: snap.discoverable,
        showMeSnapshot: snap.showMe,
        ageRangeMinSnapshot: snap.ageRangeMin,
        ageRangeMaxSnapshot: snap.ageRangeMax,
        liveCreditsAtStart: _liveCredits + 1, // pre-decrement value
      );
    } catch (e) {
      debugPrint('[LiveSession] live_sessions startSession failed: $e');
    }

    // 2. users/{uid} — legacy Phase 1 mirror for the notification Cloud Fn.
    FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .update({'isLive': true, 'doNotDisturb': false}).catchError(
      (Object e) =>
          debugPrint('[LiveSession] goLive users mirror failed: $e'),
    );

    // 3. Subscribe to the live_sessions stream going forward.
    _subscribeToSession(uid);

    // 4. Start the meetup-visibility mirror observer (Phase 1 only).
    _subscribeToMeetupMirror(uid);

    // 5. First GPS write + periodic refresh.
    _writePositionBothPlaces(uid);
    _startLocationRefresh(uid);
  }

  /// Arms a periodic timer that refreshes the GPS position every
  /// [AppConstants.locationUpdateIntervalSeconds] seconds.
  void _startLocationRefresh(String uid) {
    _locationTimer?.cancel();
    _locationTimer = Timer.periodic(
      const Duration(seconds: AppConstants.locationUpdateIntervalSeconds),
      (_) {
        debugPrint('[LiveSession] periodic location refresh');
        _writePositionBothPlaces(uid);
      },
    );
  }

  /// Reads the device GPS and writes position to BOTH live_sessions/{uid}
  /// (new) and users/{uid} (legacy mirror for Phase 1).
  Future<void> _writePositionBothPlaces(String uid) async {
    final pos = await LocationService.getPosition();
    if (pos == null) {
      debugPrint('[LiveSession] no GPS position — skipping write');
      return;
    }
    final geohash = LocationService.encode(pos.latitude, pos.longitude);

    // New: live_sessions/{uid}.
    _repo.writePosition(
      uid: uid,
      lat: pos.latitude,
      lng: pos.longitude,
      geohash: geohash,
    ).catchError((Object e) {
      debugPrint('[LiveSession] live_sessions position write failed: $e');
    });

    // Legacy mirror: users/{uid}.
    FirebaseFirestore.instance.collection('users').doc(uid).update({
      'latitude': pos.latitude,
      'longitude': pos.longitude,
      'geohash': geohash,
      'locationUpdatedAt': FieldValue.serverTimestamp(),
    }).catchError((Object e) {
      debugPrint('[LiveSession] users position mirror failed: $e');
    });
  }

  void _scheduleExpiry() {
    _expiryTimer?.cancel();
    if (_expiresAt == null) return;
    final remaining = _expiresAt!.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      _endSessionInternal(LiveSessionStatus.expired, null);
      return;
    }
    _expiryTimer = Timer(remaining, () {
      _endSessionInternal(LiveSessionStatus.expired, null);
    });
  }

  /// App-resume hook.  If a session is active: refresh GPS immediately
  /// (iOS may have throttled the periodic timer in the background) and
  /// restart the location timer with a fresh cadence.
  void onResume() {
    if (!_isLive) return;
    final uid = _uid ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    debugPrint('[LiveSession] onResume — refreshing position and restarting timer');
    _writePositionBothPlaces(uid);
    _startLocationRefresh(uid);
  }

  void updateSelfie(String path) {
    _selfieFilePath = path;
    notifyListeners();
  }

  /// Public end-session entry point — user tapped End Live.
  void endSession() {
    _endSessionInternal(LiveSessionStatus.ended, LiveSessionEndedReason.manual);
  }

  /// Shared internal end path for all reasons (manual, expired, crash
  /// recovery).  Writes both stores and tears down timers.
  void _endSessionInternal(
      LiveSessionStatus finalStatus, LiveSessionEndedReason? reason) {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _locationTimer?.cancel();
    _locationTimer = null;
    _isLive = false;
    _expiresAt = null;

    final uid = _uid ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      // 1. live_sessions/{uid} — mark terminal.
      if (finalStatus == LiveSessionStatus.expired) {
        _repo.markExpired(uid: uid).catchError((Object e) {
          debugPrint('[LiveSession] live_sessions markExpired failed: $e');
        });
      } else {
        _repo
            .markEnded(
                uid: uid, reason: reason ?? LiveSessionEndedReason.other)
            .catchError((Object e) {
          debugPrint('[LiveSession] live_sessions markEnded failed: $e');
        });
      }

      // 2. users/{uid} — legacy mirror.
      FirebaseFirestore.instance.collection('users').doc(uid).update({
        'isLive': false,
        'latitude': FieldValue.delete(),
        'longitude': FieldValue.delete(),
        'geohash': FieldValue.delete(),
        'locationUpdatedAt': FieldValue.delete(),
      }).catchError((Object e) {
        debugPrint('[LiveSession] users mirror endSession failed: $e');
      });
    }

    notifyListeners();
  }

  // ── live_sessions stream subscription ─────────────────────────────────────

  /// Subscribes to `live_sessions/{uid}` and reconciles in-memory presence
  /// state whenever the doc changes.  Safe to call multiple times — always
  /// cancels the previous subscription first.
  void _subscribeToSession(String uid) {
    _sessionSub?.cancel();
    _sessionSub = _repo.watch(uid).listen((model) {
      _currentSession = model;
      if (model == null) {
        // Doc was deleted — treat as not live.
        if (_isLive) {
          _isLive = false;
          _expiresAt = null;
          _expiryTimer?.cancel();
          _locationTimer?.cancel();
          notifyListeners();
        }
        return;
      }

      // Reconcile presence from the server-side doc.  If the function / repo
      // transitioned us to terminal, stop local timers and flip in-memory.
      if (model.status != LiveSessionStatus.active) {
        if (_isLive) {
          _isLive = false;
          _expiresAt = null;
          _expiryTimer?.cancel();
          _expiryTimer = null;
          _locationTimer?.cancel();
          _locationTimer = null;
          notifyListeners();
        }
        return;
      }

      // Active — align expiry / timer with the server-side expiresAt so clock
      // skew corrections flow in automatically.
      final changed =
          !_isLive || _expiresAt?.millisecondsSinceEpoch !=
              model.expiresAt.millisecondsSinceEpoch;
      _isLive = true;
      _expiresAt = model.expiresAt;
      if (changed) {
        _scheduleExpiry();
        notifyListeners();
      }
    }, onError: (Object e) {
      debugPrint('[LiveSession] live_sessions stream error: $e');
    });
  }

  // ── Phase-1 meetup visibility mirror ──────────────────────────────────────

  /// Watches `users/{uid}.currentMeetupId` (written by Cloud Functions on
  /// meetup create / terminal / block) and mirrors the change into
  /// `live_sessions/{uid}.{currentMeetupId, visibilityState}` so Nearby's
  /// visibility filter on the new collection stays accurate during Phase 1.
  ///
  /// Remove in Phase 2 once the Cloud Functions write directly to
  /// `live_sessions/{uid}`.
  void _subscribeToMeetupMirror(String uid) {
    _meetupMirrorSub?.cancel();
    _meetupMirrorSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((snap) {
      if (!snap.exists) return;
      final newMeetupId = snap.data()?['currentMeetupId'] as String?;
      if (newMeetupId == _lastMirroredCurrentMeetupId) return;
      _lastMirroredCurrentMeetupId = newMeetupId;
      _repo
          .writeMeetupVisibility(uid: uid, currentMeetupId: newMeetupId)
          .catchError((Object e) {
        // Non-fatal — Nearby falls back to status==active filter at the
        // very worst.
        debugPrint('[LiveSession] meetup visibility mirror failed: $e');
      });
    }, onError: (Object e) {
      debugPrint('[LiveSession] users stream error (mirror): $e');
    });
  }

  // ── Cold-start / sign-in hydration ────────────────────────────────────────

  /// Read `live_sessions/{uid}` on cold-start / sign-in and reconcile:
  ///   • If doc is missing or terminal → not live (no-op beyond subscribing
  ///     to the stream for future writes).
  ///   • If doc is active && expiresAt > now → restore in-memory state, arm
  ///     the expiry timer from the real expiresAt, start the 60 s location
  ///     refresh, and subscribe to future updates.
  ///   • If doc is active && expiresAt <= now → the previous session was
  ///     killed while backgrounded; flip to expired in both stores and clear
  ///     the users mirror so Nearby / notifications are consistent.
  ///
  /// Non-fatal — any Firestore error falls through to "not live" with a log.
  Future<void> hydrateOnLaunch(String uid) async {
    _uid = uid;
    try {
      final model = await _repo.load(uid);
      _currentSession = model;

      if (model == null) {
        debugPrint('[LiveSession] hydrateOnLaunch: no session doc');
        // Still subscribe so a subsequent goLive() or Cloud Function write
        // flows in without a new subscription call.
        _subscribeToSession(uid);
        _subscribeToMeetupMirror(uid);
        return;
      }

      if (model.status != LiveSessionStatus.active) {
        debugPrint('[LiveSession] hydrateOnLaunch: doc is terminal '
            '(${liveSessionStatusName(model.status)}) — no restore');
        _subscribeToSession(uid);
        _subscribeToMeetupMirror(uid);
        return;
      }

      final now = DateTime.now();
      if (!model.expiresAt.isAfter(now)) {
        debugPrint('[LiveSession] hydrateOnLaunch: active doc is past expiry — '
            'force-expiring (crash-recovered)');
        _endSessionInternal(
            LiveSessionStatus.expired, LiveSessionEndedReason.crashRecovered);
        _subscribeToSession(uid);
        _subscribeToMeetupMirror(uid);
        return;
      }

      // Live session is genuinely still valid — restore in-memory.
      _isLive = true;
      _expiresAt = model.expiresAt;
      _scheduleExpiry();
      _subscribeToSession(uid);
      _subscribeToMeetupMirror(uid);
      _startLocationRefresh(uid);
      // One immediate position write so geohash is fresh for Nearby.
      _writePositionBothPlaces(uid);
      notifyListeners();
      debugPrint('[LiveSession] hydrateOnLaunch: restored active session, '
          'expiresAt=${model.expiresAt}');
    } catch (e, st) {
      debugPrint('[LiveSession] hydrateOnLaunch failed (non-fatal): $e\n$st');
    }
  }

  /// Tear down all subscriptions and timers — called on sign-out.
  void clearForSignOut() {
    _sessionSub?.cancel();
    _sessionSub = null;
    _meetupMirrorSub?.cancel();
    _meetupMirrorSub = null;
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _locationTimer?.cancel();
    _locationTimer = null;
    _resetTimer?.cancel();
    _resetTimer = null;
    _isLive = false;
    _expiresAt = null;
    _selfieFilePath = null;
    _currentSession = null;
    _lastMirroredCurrentMeetupId = null;
    _uid = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _sessionSub?.cancel();
    _meetupMirrorSub?.cancel();
    _expiryTimer?.cancel();
    _locationTimer?.cancel();
    _resetTimer?.cancel();
    super.dispose();
  }

  // ── Icebreaker credit mutators ────────────────────────────────────────────

  /// Directly set the credit balance and reset window (called after a
  /// successful send transaction where Firestore is the authoritative source).
  void setCredits(int credits, DateTime? resetAt) {
    _icebreakerCredits = credits.clamp(0, 9999);
    _icebreakerCreditsResetAt = resetAt;
    if (_uid != null) _scheduleResetTimer(_uid!);
    notifyListeners();
  }

  // ── Free-credit reset + legacy crash recovery ─────────────────────────────

  /// Reads all credit fields from `users/{uid}`, applies the 24-hour free-tier
  /// reset if the window has elapsed, and schedules the next reset timer.
  ///
  /// Also performs LEGACY crash recovery on `users.isLive` — a stale `true`
  /// from a force-killed prior session is cleared here.  This remains for
  /// Phase 1 so the notification Cloud Function does not read a stale mirror.
  /// Phase 2 replaces this entirely with the live_sessions crash check in
  /// [hydrateOnLaunch].
  Future<void> hydrateCredits(String uid) async {
    _uid = uid;
    try {
      final db = FirebaseFirestore.instance;
      final snap = await db.collection('users').doc(uid).get();
      if (!snap.exists) return;

      final data = snap.data()!;
      final plan = (data['plan'] as String?) ?? 'free';
      final isFree = plan == 'free';

      final storedIcebreakers = (data['icebreakerCredits'] as num?)?.toInt();
      final storedLiveCredits = (data['liveCredits'] as num?)?.toInt();
      final storedResetAt =
          (data['icebreakerCreditsResetAt'] as Timestamp?)?.toDate();

      final now = DateTime.now();

      final windowExpired =
          isFree && (storedResetAt == null || now.isAfter(storedResetAt));

      debugPrint('[LiveSession] hydrateCredits:'
          '\n  uid=$uid  plan=$plan'
          '\n  storedIcebreakers=$storedIcebreakers'
          '\n  storedLiveCredits=$storedLiveCredits'
          '\n  storedResetAt=$storedResetAt'
          '\n  now=$now'
          '\n  windowExpired=$windowExpired');

      if (windowExpired) {
        final newResetAt = now.add(const Duration(hours: 24));
        final newIcebreakers = AppConstants.freeIcebreakerCreditsPerSignup;
        final newLiveCredits = AppConstants.freeGoLiveCreditsPerSignup;

        await db.collection('users').doc(uid).set(
          {
            'icebreakerCredits': newIcebreakers,
            'liveCredits': newLiveCredits,
            'icebreakerCreditsResetAt': Timestamp.fromDate(newResetAt),
          },
          SetOptions(merge: true),
        );

        _icebreakerCredits = newIcebreakers;
        _liveCredits = newLiveCredits;
        _icebreakerCreditsResetAt = newResetAt;
      } else {
        _icebreakerCredits =
            (storedIcebreakers ?? AppConstants.freeIcebreakerCreditsPerSignup)
                .clamp(0, 9999);
        _liveCredits =
            (storedLiveCredits ?? AppConstants.freeGoLiveCreditsPerSignup)
                .clamp(0, 9999);
        _icebreakerCreditsResetAt = storedResetAt;
      }

      // Legacy crash recovery on the users mirror — safe alongside the
      // authoritative live_sessions check in [hydrateOnLaunch].
      final storedIsLive = (data['isLive'] as bool?) ?? false;
      if (!_isLive && storedIsLive) {
        debugPrint('[LiveSession] ⚠ crash-recovery: clearing stale users.isLive');
        db.collection('users').doc(uid).update({'isLive': false}).catchError(
          (Object e) =>
              debugPrint('[LiveSession] crash-recovery mirror write failed: $e'),
        );
      }

      notifyListeners();
      _scheduleResetTimer(uid);
    } catch (e, st) {
      debugPrint('[LiveSession] ❌ hydrateCredits failed (non-fatal): $e\n$st');
    }
  }

  /// Arms a one-shot timer that fires exactly when the reset window elapses.
  void _scheduleResetTimer(String uid) {
    _resetTimer?.cancel();
    _resetTimer = null;

    if (_icebreakerCreditsResetAt == null) return;

    final remaining = _icebreakerCreditsResetAt!.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      hydrateCredits(uid);
      return;
    }

    debugPrint('[LiveSession] ⏱ reset timer scheduled in '
        '${remaining.inSeconds}s (at $_icebreakerCreditsResetAt)');

    _resetTimer = Timer(remaining, () {
      debugPrint('[LiveSession] ⏱ reset timer fired — running hydrateCredits');
      hydrateCredits(uid);
    });
  }

  // ── Discovery snapshot helper ─────────────────────────────────────────────

  Future<_DiscoverySnapshot> _readDiscoverySnapshot(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final data = doc.data() ?? const {};
      return _DiscoverySnapshot(
        maxDistanceMeters:
            ((data['maxDistanceMeters'] as num?)?.toInt() ?? 30).clamp(30, 60),
        discoverable: (data['discoverable'] as bool?) ?? true,
        showMe: (data['showMe'] as String?) ?? 'everyone',
        ageRangeMin: (data['ageRangeMin'] as num?)?.toInt() ?? 18,
        ageRangeMax: (data['ageRangeMax'] as num?)?.toInt() ?? 99,
      );
    } catch (e) {
      debugPrint('[LiveSession] discovery snapshot read failed: $e');
      return const _DiscoverySnapshot(
        maxDistanceMeters: 30,
        discoverable: true,
        showMe: 'everyone',
        ageRangeMin: 18,
        ageRangeMax: 99,
      );
    }
  }
}

class _DiscoverySnapshot {
  const _DiscoverySnapshot({
    required this.maxDistanceMeters,
    required this.discoverable,
    required this.showMe,
    required this.ageRangeMin,
    required this.ageRangeMax,
  });
  final int maxDistanceMeters;
  final bool discoverable;
  final String showMe;
  final int ageRangeMin;
  final int ageRangeMax;
}

// ── Scope ────────────────────────────────────────────────────────────────────

/// InheritedNotifier that exposes [LiveSession] to the entire widget tree.
class LiveSessionScope extends InheritedNotifier<LiveSession> {
  const LiveSessionScope({
    super.key,
    required LiveSession session,
    required super.child,
  }) : super(notifier: session);

  static LiveSession of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<LiveSessionScope>();
    assert(scope != null, 'No LiveSessionScope found in widget tree.');
    return scope!.notifier!;
  }

  static bool isLive(BuildContext context) => of(context).isLive;
}
