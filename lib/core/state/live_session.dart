import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';

import '../constants/app_constants.dart';
import '../models/live_session_model.dart';
import '../services/live_session_media_repository.dart';
import '../services/live_session_repository.dart';
import '../services/location_service.dart';
import 'user_profile.dart';

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
  LiveSession({
    LiveSessionRepository? repo,
    LiveSessionMediaRepository? mediaRepo,
  })  : _repo = repo ?? LiveSessionRepository(),
        _mediaRepo = mediaRepo ?? LiveSessionMediaRepository();

  final LiveSessionRepository _repo;
  final LiveSessionMediaRepository _mediaRepo;

  // ── Presence state (mirrors the Firestore doc) ─────────────────────────────

  bool _isLive = false;
  DateTime? _expiresAt;
  int _liveCredits = 1;
  String? _selfieFilePath;

  /// Local-only path to a square crop of [_selfieFilePath], derived once at
  /// capture time so circular avatar surfaces can fully fill the circle with
  /// `BoxFit.cover` without re-cropping the raw portrait at every render.
  /// Null until the cropper writes the file (or if derivation failed — the
  /// UI then falls back to the raw selfie with `contain` + letterbox).
  String? _avatarFilePath;

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

  /// Bootstrap retry timer: fires every
  /// [_initialPositionRetryInterval] seconds until the very first
  /// successful position write lands.  Without this, a missed first GPS
  /// read (cold cache, services blip, iOS first-fix latency) would leave
  /// the just-started session at `geohash == null` for the full
  /// 60 s periodic-tick window — and Nearby's cell query filters by
  /// `where('geohash', >=, prefix)`, so a null-geohash session is
  /// invisible to peers regardless of `status='active'` or
  /// `visibilityState='discoverable'`.  Cancelled the moment a real
  /// position lands and on every session-end / hydrate path.
  Timer? _initialPositionRetryTimer;

  /// True once the current session has had at least one real position
  /// write (lat/lng/geohash all populated server-side).  Drives the
  /// branch in [_writePosition] between bootstrap-aggressive retries
  /// and the post-bootstrap heartbeat-on-null behaviour.  Reset to
  /// false at every session start.
  bool _hasWrittenInitialPosition = false;

  /// One-shot timer for the 24-hour icebreaker-credit reset.  Fires
  /// [hydrateCredits] with the stored uid.
  Timer? _resetTimer;

  static const Duration _initialPositionRetryInterval =
      Duration(seconds: 5);

  // ── Stream subscriptions ──────────────────────────────────────────────────

  /// Stream on `live_sessions/{uid}` — reconciles in-memory state.
  StreamSubscription<LiveSessionModel?>? _sessionSub;

  /// Stream on `users/{uid}` — used ONLY to observe `currentMeetupId`
  /// changes written by Cloud Functions, so we can mirror them into
  /// `live_sessions/{uid}.visibilityState` during Phase 1.  Remove in Phase 2
  /// when functions write visibility directly.
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _meetupMirrorSub;

  /// Stream on `meetups/{currentMeetupId}` — armed only while
  /// `users/{uid}.currentMeetupId` is non-null.  We use the meetup's actual
  /// status (not just the presence of an id) to decide visibility, so a
  /// stranded `users.currentMeetupId` (CF crash, missed deploy, expired retry
  /// budget after a terminal transition) cannot leave the session invisible
  /// to Nearby forever.  Terminal status → write discoverable AND attempt a
  /// self-heal clear of `users.currentMeetupId`; active status → hidden.
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _meetupStatusSub;

  /// Meetup ids we've already attempted to self-heal in this LiveSession
  /// instance.  One attempt per zombie per process — if the write fails we
  /// log and stop, since the next sign-in or process restart re-arms the set.
  final Set<String> _meetupSelfHealAttempted = <String>{};

  /// Statuses that release the user from the in-meetup lock.  Mirrors the
  /// server-side `TERMINAL_MEETUP_STATUSES` set in functions/src/index.ts —
  /// keep both in sync.  The mirror collapses any of these to
  /// `visibilityState=discoverable`, so a successful match no longer leaves
  /// the participants invisible to each other in Nearby.
  static const _terminalMeetupStatuses = <String>{
    'matched',
    'ended',
    'no_match',
    'expired_finding',
    'cancelled_finding',
    'cancelled_talking',
  };

  /// Last value we mirrored, so we don't re-write on every unrelated field change.
  String? _lastMirroredCurrentMeetupId;

  /// Last meetup status we wrote visibility against.  Tracked so a
  /// `talking → matched` transition immediately flips visibility back to
  /// `discoverable` even when `users.currentMeetupId` hasn't been cleared yet.
  String? _lastMirroredMeetupStatus;

  /// False until the very first emission of [_subscribeToMeetupMirror] has
  /// produced a successful `writeMeetupVisibility`.  Forces ONE unconditional
  /// reconciliation write per fresh subscription so a session whose
  /// `live_sessions.visibilityState` was stranded at `hidden_in_meetup` by
  /// an offline cleanup window is realigned with whatever
  /// `users.currentMeetupId` currently says — even when the in-memory cache
  /// (`prev`) and the snapshot value happen to match (`null == null`), which
  /// the equality short-circuit on subsequent ticks would otherwise skip
  /// forever, leaving the session permanently invisible to Nearby.
  bool _mirrorBootstrapped = false;

  // ── Identity + credits ────────────────────────────────────────────────────

  /// UID of the currently signed-in user.
  String? _uid;

  int _icebreakerCredits = AppConstants.freeIcebreakerCreditsPerSignup;
  DateTime? _icebreakerCreditsResetAt;

  // ── Getters ───────────────────────────────────────────────────────────────

  bool get isLive => _isLive;
  DateTime? get expiresAt => _expiresAt;
  String? get selfieFilePath => _selfieFilePath;
  String? get avatarFilePath => _avatarFilePath;
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
    String? avatarFilePath,
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

    // Upload the captured selfie to Firebase Storage so Nearby's hero card
    // can render it for other users.  Best-effort: if the upload fails, the
    // user still goes live — the hero card just falls back to their profile
    // photos.  Web doesn't reach this path (selfie capture is mobile-only),
    // and the test-mode paths still produce a local file we can upload.
    String? liveSelfieUrl;
    if (selfieFilePath != null && !kIsWeb) {
      try {
        final file = File(selfieFilePath);
        if (await file.exists()) {
          liveSelfieUrl = await _mediaRepo.uploadLiveSelfie(
            uid: uid,
            file: file,
          );
          debugPrint('[LiveSession] selfie uploaded → $liveSelfieUrl');
        } else {
          debugPrint('[LiveSession] selfie file missing — skipping upload');
        }
      } catch (e) {
        // Non-fatal: proceed to session write with liveSelfieUrl: null.
        debugPrint('[LiveSession] selfie upload failed (non-fatal): $e');
      }
    }

    // Remember the prior values so we can roll back if the batch fails.
    final prevIsLive = _isLive;
    final prevExpiresAt = _expiresAt;
    final prevSelfiePath = _selfieFilePath;
    final prevAvatarPath = _avatarFilePath;
    final prevCredits = _liveCredits;
    final prevCurrentSession = _currentSession;

    final now = DateTime.now();
    final expires = now.add(const Duration(hours: 1));
    // Going Live is always discoverable — no user-controlled opt-out.
    const initialVisibility = LiveSessionVisibility.discoverable;

    _isLive = true;
    _expiresAt = expires;
    if (selfieFilePath != null) _selfieFilePath = selfieFilePath;
    if (avatarFilePath != null) _avatarFilePath = avatarFilePath;
    final creditsToPersist = _liveCredits;
    if (_liveCredits > 0) _liveCredits--;
    final remainingCredits = _liveCredits;

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
      liveSelfieUrl: liveSelfieUrl,
      lat: null,
      lng: null,
      geohash: null,
      locationUpdatedAt: null,
      maxDistanceMetersSnapshot: snap.maxDistanceMeters,
      interestedInSnapshot: snap.interestedIn,
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
        interestedInSnapshot: snap.interestedIn,
        ageRangeMinSnapshot: snap.ageRangeMin,
        ageRangeMaxSnapshot: snap.ageRangeMax,
        liveCreditsAtStart: creditsToPersist,
        remainingLiveCredits: remainingCredits,
        liveSelfieUrl: liveSelfieUrl,
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
      _avatarFilePath = prevAvatarPath;
      _liveCredits = prevCredits;
      _currentSession = prevCurrentSession;
      notifyListeners();
      rethrow;
    }

    // Server state landed — safe to subscribe and arm the refresh loop.
    // Reset the bootstrap-window flags so the very first _writePosition
    // call after Go Live is treated as bootstrap (aggressive 5 s retry
    // until first real geohash lands).
    _hasWrittenInitialPosition = false;
    _initialPositionRetryTimer?.cancel();
    _initialPositionRetryTimer = null;

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
  /// [LiveSessionRepository.writePosition]).
  ///
  /// On null GPS (permission revoked, timeout, iOS background throttling,
  /// momentary services blip) we do NOT skip silently — that lets
  /// `locationUpdatedAt` go stale and Nearby drops the user as
  /// `location_stale` even though they're still live.  Instead we issue a
  /// freshness-only heartbeat: the last-known coords stay as they were,
  /// and only the timestamps refresh.  The next tick re-reads GPS; the
  /// next successful read overwrites coords + timestamp together.
  ///
  /// Bootstrap caveat: until the very first successful write lands,
  /// `geohash` on the session doc is null and the doc is invisible to
  /// Nearby's cell query (`where('geohash', >=, prefix)` excludes null
  /// fields).  If the first GPS read returns null, we don't want to wait
  /// the full 60 s periodic-tick window — we schedule a 5 s retry until
  /// the first real position lands, then drop back to the standard
  /// periodic + heartbeat behaviour.
  Future<void> _writePosition(String uid) async {
    final pos = await LocationService.getPosition();
    if (pos == null) {
      debugPrint('[LiveSession] no GPS — heartbeating freshness only');
      try {
        await _repo.heartbeatPosition(uid: uid);
      } catch (e) {
        debugPrint('[LiveSession] heartbeat failed (will retry): $e');
      }
      // Pre-bootstrap: heartbeat alone leaves geohash=null and the session
      // query-invisible.  Retry aggressively until we get a real first fix.
      if (!_hasWrittenInitialPosition && _isLive) {
        _scheduleInitialPositionRetry(uid);
      }
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
      if (!_hasWrittenInitialPosition) {
        _hasWrittenInitialPosition = true;
        _initialPositionRetryTimer?.cancel();
        _initialPositionRetryTimer = null;
        debugPrint('[LiveSession] first position landed — bootstrap retry off');
      }
    } catch (e) {
      // Batch either landed fully or not at all.  Retry on the next tick.
      debugPrint('[LiveSession] writePosition batch failed (will retry): $e');
      if (!_hasWrittenInitialPosition && _isLive) {
        _scheduleInitialPositionRetry(uid);
      }
    }
  }

  /// Arms (or re-arms) a single-shot timer that re-attempts
  /// [_writePosition] in [_initialPositionRetryInterval].  Used only
  /// during the bootstrap window — once the first real position lands,
  /// the timer is cancelled and not re-armed.
  void _scheduleInitialPositionRetry(String uid) {
    _initialPositionRetryTimer?.cancel();
    _initialPositionRetryTimer = Timer(_initialPositionRetryInterval, () {
      if (!_isLive || _hasWrittenInitialPosition) return;
      debugPrint('[LiveSession] bootstrap retry — attempting position write');
      _writePosition(uid);
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
    _writePosition(uid);
    _startLocationRefresh(uid);
  }

  /// Redo verification — user re-captured their live selfie while already
  /// live.  Updates the in-memory selfie/avatar paths AND fires authoritative
  /// durable writes through the repository so the verification status,
  /// timestamp, audit trail, AND the session-scoped `liveSelfieUrl` (which
  /// drives Nearby's hero image rail for other users) reflect the redo.
  /// All Firestore / Storage work is fire-and-forget here: redo never affects
  /// the live presence state itself, so a transient failure logs and the user
  /// keeps running on the previous remote record.
  void updateSelfie(
    String path, {
    String? avatarPath,
    LiveVerificationMethod verificationMethod =
        LiveVerificationMethod.liveSelfie,
  }) {
    _selfieFilePath = path;
    _avatarFilePath = avatarPath;
    notifyListeners();

    final uid = _uid ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      debugPrint('[LiveSession] updateSelfie: no uid — skipping redo write');
      return;
    }
    _repo
        .recordPhotoVerificationRedo(
          uid: uid,
          verificationMethod: verificationMethod,
        )
        .catchError((Object e) {
      debugPrint('[LiveSession] redo verification write failed: $e');
    });

    // Refresh the remote live selfie so other users see the new capture in
    // Nearby.  Reuses the same upload helper as goLive(), then patches just
    // `liveSelfieUrl` on the active session doc — single field update, no
    // users mirror, no presence-state implications.  Wrapped in an async
    // closure so the surrounding method stays synchronous (callers don't
    // await redos) and any failure is contained.
    _refreshRemoteLiveSelfie(uid: uid, path: path);
  }

  /// Best-effort: upload [path] to Firebase Storage and patch
  /// `live_sessions/{uid}.liveSelfieUrl` to the resulting URL.  Non-fatal —
  /// a failure leaves the prior remote URL in place; the local redo has
  /// already succeeded by the time this runs.
  void _refreshRemoteLiveSelfie({
    required String uid,
    required String path,
  }) {
    if (kIsWeb) return;
    Future<void>(() async {
      try {
        final file = File(path);
        if (!await file.exists()) {
          debugPrint(
              '[LiveSession] redo selfie file missing — skipping remote refresh');
          return;
        }
        final url = await _mediaRepo.uploadLiveSelfie(uid: uid, file: file);
        await _repo.setLiveSelfieUrl(uid: uid, url: url);
        debugPrint('[LiveSession] redo selfie uploaded → $url');
      } catch (e) {
        debugPrint(
            '[LiveSession] redo remote selfie refresh failed (non-fatal): $e');
      }
    });
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
    _initialPositionRetryTimer?.cancel();
    _initialPositionRetryTimer = null;
    _hasWrittenInitialPosition = false;
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
          _initialPositionRetryTimer?.cancel();
          _initialPositionRetryTimer = null;
          _hasWrittenInitialPosition = false;
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
          _initialPositionRetryTimer?.cancel();
          _initialPositionRetryTimer = null;
          _hasWrittenInitialPosition = false;
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
  /// meetup create / terminal / block) AND the referenced meetup doc's
  /// status, then mirrors the resulting visibility into
  /// `live_sessions/{uid}.{currentMeetupId, visibilityState}` so Nearby's
  /// visibility filter on the new collection stays accurate during Phase 1.
  ///
  /// Visibility is decided from the *meetup status*, not just the presence
  /// of `currentMeetupId`.  A successful match (or any other terminal
  /// status) collapses straight to `discoverable`, even when
  /// `onMeetupTerminal` hasn't yet cleared the user-doc field — this
  /// prevents a stranded mirror after CF crashes / missed deploys / expired
  /// retry budget from leaving matched users invisible to Nearby.  The
  /// mirror also attempts a self-heal write to clear
  /// `users.currentMeetupId` when it observes a zombie state, but the
  /// visibility flip does NOT depend on that write succeeding.
  ///
  /// Remove in Phase 2 once the Cloud Functions write directly to
  /// `live_sessions/{uid}`.
  void _subscribeToMeetupMirror(String uid) {
    _meetupMirrorSub?.cancel();
    _meetupStatusSub?.cancel();
    _meetupStatusSub = null;
    _lastMirroredMeetupStatus = null;
    // Reset bootstrap so the first emission of this fresh subscription
    // forces an unconditional reconciliation write — see comment on
    // [_mirrorBootstrapped] for why.
    _mirrorBootstrapped = false;
    _meetupMirrorSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((snap) {
      if (!snap.exists) return;
      final newMeetupId = snap.data()?['currentMeetupId'] as String?;
      _onCurrentMeetupIdTick(uid: uid, newMeetupId: newMeetupId);
    }, onError: (Object e) {
      debugPrint('[LiveSession] users stream error (mirror): $e');
    });
  }

  /// Reacts to a `users.currentMeetupId` change (or first emission).  Sets
  /// up a meetup-doc subscription when the field is non-null so visibility
  /// can track the actual meetup status; tears that subscription down and
  /// writes `discoverable` when the field is null.
  void _onCurrentMeetupIdTick({
    required String uid,
    required String? newMeetupId,
  }) {
    final prev = _lastMirroredCurrentMeetupId;
    final idChanged = newMeetupId != prev;
    if (!_mirrorBootstrapped || idChanged) {
      debugPrint('[LiveSession/mirror] users.currentMeetupId tick: '
          'prev=$prev new=$newMeetupId bootstrapped=$_mirrorBootstrapped');
    }

    if (idChanged) {
      _meetupStatusSub?.cancel();
      _meetupStatusSub = null;
      _lastMirroredMeetupStatus = null;
    }

    if (newMeetupId == null) {
      // No active meetup → unconditionally discoverable.
      if (_mirrorBootstrapped && newMeetupId == prev) return;
      _writeMirroredVisibility(
        uid: uid,
        currentMeetupId: null,
        meetupStatus: null,
      );
      return;
    }

    // Subscribe to the meetup doc so visibility tracks status, not just the
    // presence of an id.  `_meetupStatusSub` is null when either we just
    // (re)attached to a different meetup id or we never had one — both
    // cases need a fresh subscription.
    _meetupStatusSub ??= FirebaseFirestore.instance
        .collection('meetups')
        .doc(newMeetupId)
        .snapshots()
        .listen((mSnap) {
      final status = mSnap.data()?['status'] as String?;
      _onMeetupStatusTick(
        uid: uid,
        meetupId: newMeetupId,
        status: status,
        exists: mSnap.exists,
      );
    }, onError: (Object e) {
      debugPrint('[LiveSession/mirror] meetup-status stream error '
          '(meetupId=$newMeetupId): $e');
    });
  }

  void _onMeetupStatusTick({
    required String uid,
    required String meetupId,
    required String? status,
    required bool exists,
  }) {
    // Defensive: a freshly-created meetup may briefly look "missing"
    // between the user-doc write and the meetup-doc write propagating to
    // this listener.  Treat absence as a no-op (don't flip visibility),
    // not as terminal — the meetup status path will re-fire the moment
    // the doc lands.
    if (!exists) return;

    final isTerminal =
        status != null && _terminalMeetupStatuses.contains(status);
    final visibilityCurrentMeetupId = isTerminal ? null : meetupId;

    final prevId = _lastMirroredCurrentMeetupId;
    final prevStatus = _lastMirroredMeetupStatus;
    final idChanged = visibilityCurrentMeetupId != prevId;
    final statusChanged = status != prevStatus;
    if (_mirrorBootstrapped && !idChanged && !statusChanged) return;

    debugPrint('[LiveSession/mirror] meetup-status tick: meetupId=$meetupId '
        'status=$status terminal=$isTerminal '
        'visibilityCurrentMeetupId=$visibilityCurrentMeetupId');

    _writeMirroredVisibility(
      uid: uid,
      currentMeetupId: visibilityCurrentMeetupId,
      meetupStatus: status,
    );

    // Best-effort self-heal: when the meetup is in a terminal status but
    // `users.currentMeetupId` still points at it, clear that field once
    // per process so future cold-starts converge without relying on this
    // status subscription.  Visibility has already been flipped above —
    // the heal is purely cleanup, not load-bearing.
    if (isTerminal && _meetupSelfHealAttempted.add(meetupId)) {
      unawaited(_selfHealClearStrandedCurrentMeetupId(
        uid: uid,
        meetupId: meetupId,
        status: status,
      ));
    }
  }

  void _writeMirroredVisibility({
    required String uid,
    required String? currentMeetupId,
    required String? meetupStatus,
  }) {
    // Do NOT advance the cache before the write succeeds.  Leaving
    // `_lastMirroredCurrentMeetupId == prev` means the next snapshot tick
    // sees inequality and re-fires the write — that is the retry path.
    _repo
        .writeMeetupVisibility(
          uid: uid,
          currentMeetupId: currentMeetupId,
        )
        .then((_) {
      _lastMirroredCurrentMeetupId = currentMeetupId;
      _lastMirroredMeetupStatus = meetupStatus;
      _mirrorBootstrapped = true;
      debugPrint('[LiveSession/mirror] writeMeetupVisibility OK '
          '(currentMeetupId=$currentMeetupId status=$meetupStatus)');
    }).catchError((Object e) {
      debugPrint('[LiveSession/mirror] writeMeetupVisibility FAILED '
          '(currentMeetupId=$currentMeetupId status=$meetupStatus): $e — '
          'will retry on next tick');
    });
  }

  Future<void> _selfHealClearStrandedCurrentMeetupId({
    required String uid,
    required String meetupId,
    required String? status,
  }) async {
    debugPrint('[LiveSession/mirror] self-heal clearing stranded '
        'users.currentMeetupId=$meetupId (status=$status)');
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'currentMeetupId': FieldValue.delete(),
      });
      debugPrint('[LiveSession/mirror] self-heal write OK '
          '(currentMeetupId=$meetupId)');
    } catch (e) {
      debugPrint('[LiveSession/mirror] self-heal write FAILED '
          '(currentMeetupId=$meetupId): $e');
    }
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
      // Treat hydrate the same as a fresh start for the bootstrap retry:
      // even if the doc carries an old geohash, a hydrated session that
      // can't get a first GPS read on resume must keep retrying instead
      // of waiting 60 s for the next periodic tick.
      _hasWrittenInitialPosition = false;
      _initialPositionRetryTimer?.cancel();
      _initialPositionRetryTimer = null;
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
    _meetupStatusSub?.cancel();
    _meetupStatusSub = null;
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _locationTimer?.cancel();
    _locationTimer = null;
    _initialPositionRetryTimer?.cancel();
    _initialPositionRetryTimer = null;
    _hasWrittenInitialPosition = false;
    _resetTimer?.cancel();
    _resetTimer = null;
    _isLive = false;
    _expiresAt = null;
    _selfieFilePath = null;
    _avatarFilePath = null;
    _currentSession = null;
    _lastMirroredCurrentMeetupId = null;
    _lastMirroredMeetupStatus = null;
    _mirrorBootstrapped = false;
    _meetupSelfHealAttempted.clear();
    _uid = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _sessionSub?.cancel();
    _meetupMirrorSub?.cancel();
    _meetupStatusSub?.cancel();
    _expiryTimer?.cancel();
    _locationTimer?.cancel();
    _initialPositionRetryTimer?.cancel();
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

  /// Reads the discovery snapshot used to freeze the live session at Go Live.
  ///
  /// Source-of-truth model:
  ///   • PUBLIC preferences (`interestedIn`, `ageRangeMin`, `ageRangeMax`) come
  ///     from `profiles/{uid}` first.  Legacy accounts whose profiles doc
  ///     hasn't been backfilled yet fall back to `users/{uid}`, where the
  ///     same fields lived prior to the cutover.
  ///   • PRIVATE discovery controls (`maxDistanceMeters`) ALWAYS come from
  ///     `users/{uid}` — they are not on the public profile by design.
  ///
  /// `interestedIn` value is normalised through
  /// [UserProfile.interestedInToCanonical] so the snapshot is canonical
  /// lowercase regardless of which legacy field name (interestedIn / showMe /
  /// openTo) or casing the source doc carried.  A read failure on either doc
  /// produces the documented defaults rather than aborting Go Live.
  Future<_DiscoverySnapshot> _readDiscoverySnapshot(String uid) async {
    try {
      final db = FirebaseFirestore.instance;
      final results = await Future.wait([
        db.collection('profiles').doc(uid).get(),
        db.collection('users').doc(uid).get(),
      ]);
      final profileData = results[0].data() ?? const {};
      final userData = results[1].data() ?? const {};

      String pickInterestedIn() {
        // Prefer canonical `interestedIn` on profiles, then on users; fall
        // through to the older `showMe` (Settings) and `openTo` (onboarding)
        // keys for accounts that never wrote the canonical field.
        for (final candidate in [
          profileData['interestedIn'],
          userData['interestedIn'],
          userData['showMe'],
          userData['openTo'],
        ]) {
          if (candidate is String && candidate.isNotEmpty) {
            return UserProfile.interestedInToCanonical(candidate);
          }
        }
        return 'everyone';
      }

      int pickInt(String key, int fallback) {
        final p = profileData[key];
        if (p is num) return p.toInt();
        final u = userData[key];
        if (u is num) return u.toInt();
        return fallback;
      }

      return _DiscoverySnapshot(
        maxDistanceMeters:
            ((userData['maxDistanceMeters'] as num?)?.toInt() ?? 30)
                .clamp(30, 60),
        interestedIn: pickInterestedIn(),
        ageRangeMin: pickInt('ageRangeMin', 18),
        ageRangeMax: pickInt('ageRangeMax', 99),
      );
    } catch (e) {
      debugPrint('[LiveSession] discovery snapshot read failed: $e');
      return const _DiscoverySnapshot(
        maxDistanceMeters: 30,
        interestedIn: 'everyone',
        ageRangeMin: 18,
        ageRangeMax: 99,
      );
    }
  }
}

class _DiscoverySnapshot {
  const _DiscoverySnapshot({
    required this.maxDistanceMeters,
    required this.interestedIn,
    required this.ageRangeMin,
    required this.ageRangeMax,
  });
  final int maxDistanceMeters;
  final String interestedIn;
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
