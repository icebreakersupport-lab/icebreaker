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
/// Dual-write is owned by [LiveSessionRepository]: every live-presence mutation
/// commits BOTH the authoritative `live_sessions/{uid}` write AND the legacy
/// `users/{uid}` mirror (`isLive`, position fields, `doNotDisturb`) in a single
/// Firestore batch, so the two stores either both land or both fail — no
/// split-brain state is possible.  Phase 2 drops the mirror once the relevant
/// Cloud Functions are cut over to read `live_sessions/{uid}` directly.
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

  /// Starts a new live session.  The authoritative `live_sessions/{uid}`
  /// write and the legacy `users/{uid}` mirror are committed atomically by
  /// the repository — if the batch fails, no server state was changed and we
  /// roll back the in-memory flip so the UI and server stay consistent.
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

    // Snapshot discovery-relevant settings so both the session doc and
    // Nearby's mutual filter can operate off the session alone, independent
    // of any mid-session Settings edits to users/{uid}.
    final snap = await _readDiscoverySnapshot(uid);

    // Remember the prior values so we can roll back if the batch fails.
    final prevIsLive = _isLive;
    final prevExpiresAt = _expiresAt;
    final prevSelfiePath = _selfieFilePath;
    final prevCredits = _liveCredits;
    final prevCurrentSession = _currentSession;

    final now = DateTime.now();
    final expires = now.add(const Duration(hours: 1));
    final initialVisibility = snap.discoverable
        ? LiveSessionVisibility.discoverable
        : LiveSessionVisibility.discoveryDisabled;

    _isLive = true;
    _expiresAt = expires;
    if (selfieFilePath != null) _selfieFilePath = selfieFilePath;
    final creditsToPersist = _liveCredits;
    if (_liveCredits > 0) _liveCredits--;

    // Optimistic synthesis: seed `_currentSession` from the values we are
    // about to commit so any listener that reads the session between the
    // optimistic flip and the first server-stream tick (notably Nearby's
    // `_applySessionSnapshots`) sees the real snapshots — not nulls or
    // defaults.  The stream replaces this with the canonical server-side
    // model within ~1 s; until then the in-memory model carries the values
    // we KNOW we are persisting in the same async frame.  Server-stamped
    // timestamps are pre-filled with `now` and reconciled on that tick.
    _currentSession = LiveSessionModel(
      uid: uid,
      status: LiveSessionStatus.active,
      endedReason: null,
      startedAt: now,
      expiresAt: expires,
      endedAt: null,
      verificationMethod: verificationMethod,
      verificationCompletedAt: now,
      currentMeetupId: null,
      visibilityState: initialVisibility,
      lat: null,
      lng: null,
      geohash: null,
      locationUpdatedAt: null,
      maxDistanceMetersSnapshot: snap.maxDistanceMeters,
      discoverableSnapshot: snap.discoverable,
      showMeSnapshot: snap.showMe,
      ageRangeMinSnapshot: snap.ageRangeMin,
      ageRangeMaxSnapshot: snap.ageRangeMax,
      liveCreditsAtStart: creditsToPersist,
      // platform is the only field we don't know locally; the canonical
      // value lands on the first stream tick.  It does not feed any
      // client-side filtering — safe to leave as 'unknown' until reconciled.
      platform: 'unknown',
      schemaVersion: kLiveSessionSchemaVersion,
      createdAt: now,
      updatedAt: now,
    );

    _scheduleExpiry();
    notifyListeners();

    try {
      await _repo.startSession(
        uid: uid,
        verificationMethod: verificationMethod,
        maxDistanceMetersSnapshot: snap.maxDistanceMeters,
        discoverableSnapshot: snap.discoverable,
        showMeSnapshot: snap.showMe,
        ageRangeMinSnapshot: snap.ageRangeMin,
        ageRangeMaxSnapshot: snap.ageRangeMax,
        liveCreditsAtStart: creditsToPersist,
      );
    } catch (e, st) {
      // Authoritative write failed — nothing landed server-side (atomic
      // batch).  Roll back the in-memory flip so the UI doesn't show a
      // "live" state that the server never acknowledged.
      debugPrint('[LiveSession] startSession failed — rolling back: $e\n$st');
      _expiryTimer?.cancel();
      _expiryTimer = null;
      _isLive = prevIsLive;
      _expiresAt = prevExpiresAt;
      _selfieFilePath = prevSelfiePath;
      _liveCredits = prevCredits;
      _currentSession = prevCurrentSession;
      notifyListeners();
      rethrow;
    }

    // Server state landed — safe to subscribe and arm the refresh loop.
    _subscribeToSession(uid);
    _subscribeToMeetupMirror(uid);
    _writePosition(uid);
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
        _writePosition(uid);
      },
    );
  }

  /// Reads the device GPS and writes the position to both `live_sessions`
  /// and the `users` mirror inside a single atomic batch (see
  /// [LiveSessionRepository.writePosition]).  A null GPS result (permission
  /// revoked, timeout, airplane mode) is treated as "skip this tick" rather
  /// than writing a half-state — the next tick re-reads.
  Future<void> _writePosition(String uid) async {
    final pos = await LocationService.getPosition();
    if (pos == null) {
      debugPrint('[LiveSession] no GPS position — skipping write');
      return;
    }
    final geohash = LocationService.encode(pos.latitude, pos.longitude);
    try {
      await _repo.writePosition(
        uid: uid,
        lat: pos.latitude,
        lng: pos.longitude,
        geohash: geohash,
      );
    } catch (e) {
      // Batch either landed fully or not at all.  Retry on the next tick.
      debugPrint('[LiveSession] writePosition batch failed (will retry): $e');
    }
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
    _writePosition(uid);
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
  /// recovery).  The repository commits the `live_sessions/{uid}` terminal
  /// write and the `users/{uid}` mirror clear in a single batch — split-brain
  /// is not possible.  On batch failure we log and leave the in-memory flip
  /// in place; the next `hydrateOnLaunch` will reconcile a stale active doc
  /// via the crash-recovery path.
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
      final Future<void> write;
      if (finalStatus == LiveSessionStatus.expired) {
        write = _repo.markExpired(uid: uid, reason: reason);
      } else {
        write = _repo.markEnded(
            uid: uid, reason: reason ?? LiveSessionEndedReason.other);
      }
      write.catchError((Object e) {
        debugPrint('[LiveSession] terminal batch failed (will be reconciled '
            'on next hydrateOnLaunch): $e');
      });
    }

    notifyListeners();
  }

  // ── live_sessions stream subscription ─────────────────────────────────────

  /// Subscribes to `live_sessions/{uid}` and reconciles in-memory presence
  /// state whenever the doc changes.  Safe to call multiple times — always
  /// cancels the previous subscription first.
  ///
  /// [notifyListeners] is called on every snapshot so downstream
  /// ChangeNotifier listeners (notably Nearby's own-position listener) observe
  /// position updates in addition to presence transitions.  Listeners that
  /// only care about transitions must dedup on their own state.
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
        }
        notifyListeners();
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
        }
        notifyListeners();
        return;
      }

      // Active — align expiry / timer with the server-side expiresAt so clock
      // skew corrections flow in automatically.
      final timingChanged =
          !_isLive || _expiresAt?.millisecondsSinceEpoch !=
              model.expiresAt.millisecondsSinceEpoch;
      _isLive = true;
      _expiresAt = model.expiresAt;
      if (timingChanged) _scheduleExpiry();
      notifyListeners();
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

      // We need the discoverableSnapshot to decide what visibilityState to
      // restore when the meetup clears.  If the session model hasn't loaded
      // yet, defer the mirror write — biasing toward strict (do nothing) is
      // safer than guessing.  The next snapshot tick will retry once the
      // model is in memory.
      final session = _currentSession;
      if (session == null) {
        debugPrint('[LiveSession] meetup mirror deferred — currentSession not '
            'loaded yet');
        return;
      }
      _lastMirroredCurrentMeetupId = newMeetupId;
      _repo
          .writeMeetupVisibility(
            uid: uid,
            currentMeetupId: newMeetupId,
            discoverableSnapshot: session.discoverableSnapshot,
          )
          .catchError((Object e) {
        // Non-fatal — the visibility transition will be retried on the next
        // users-doc snapshot tick if it failed transiently.
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
      _writePosition(uid);
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
