import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/live_session_model.dart';

/// Phase-1 durable verification status written to `users/{uid}` on a
/// successful live-selfie capture.  Intentionally a single string rather than
/// a full enum — see `docs/firestore-schema-audit.md` §4 (Phase 1) for why
/// the verification schema is kept narrow in this iteration.  Future values
/// (`'phone_verified'`, `'id_verified'`) are planned but out of scope here.
const String kVerificationStatusPhotoVerified = 'photo_verified';

/// Firestore I/O for `live_sessions/{uid}` — the authoritative client-side
/// source of truth for live presence in Phase 1.
///
/// Dual-write (Phase 1):
///   Every mutation that affects live presence commits the authoritative
///   `live_sessions/{uid}` write AND the legacy `users/{uid}` mirror inside
///   a single Firestore [WriteBatch] so the two stores can never diverge.
///   The batch either fully lands or fully fails; there is no best-effort
///   half-written state to reconcile.
///
///   The mirror exists so the current Cloud Functions
///   (onIcebreakerCreated, notification gates, block paths, meetup Fns)
///   that still read `users/{uid}.{isLive, geohash, latitude, longitude,
///   locationUpdatedAt}` keep working unchanged.  Phase 2
///   deletes the mirror once those functions are cut over to read from
///   `live_sessions/{uid}` directly.
///
/// This layer is stateless — no timers, no ChangeNotifier, no in-memory
/// session state.  See `live_session.dart` for the state machine.
class LiveSessionRepository {
  LiveSessionRepository({FirebaseFirestore? db})
    : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _liveDoc(String uid) =>
      _db.collection('live_sessions').doc(uid);

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      _db.collection('users').doc(uid);

  CollectionReference<Map<String, dynamic>> _historyCollection() =>
      _db.collection('live_session_history');

  CollectionReference<Map<String, dynamic>> _verificationAttempts(String uid) =>
      _userDoc(uid).collection('verificationAttempts');

  /// One-shot read of `live_sessions/{uid}`.  Returns null when the doc is
  /// missing (user has never gone live, or the doc was cleared).
  Future<LiveSessionModel?> load(String uid) async {
    final snap = await _liveDoc(uid).get();
    if (!snap.exists) return null;
    return LiveSessionModel.fromSnapshot(snap);
  }

  /// Live stream of `live_sessions/{uid}` — drives in-memory state in
  /// `LiveSession`.  Emits null when the doc is deleted or does not exist.
  Stream<LiveSessionModel?> watch(String uid) {
    return _liveDoc(uid).snapshots().map((snap) {
      if (!snap.exists) return null;
      return LiveSessionModel.fromSnapshot(snap);
    });
  }

  /// Starts a new live session.  Atomically:
  ///   • writes a fresh full doc at `live_sessions/{uid}` (overwriting any
  ///     prior terminal doc — the uid is the primary key), and
  ///   • appends a durable `live_session_history/{auto-id}` record so every
  ///     Go Live remains queryable after the current-session doc is reused,
  ///     and
  ///   • flips the `users/{uid}` mirror to `isLive: true`,
  ///     persists the decremented live-credit balance, and stamps the durable
  ///     verification fields (`verificationStatus`, `photoVerifiedAt`,
  ///     `lastVerificationMethod`) so live verification leaves a trust signal
  ///     on the user doc that survives the session ending.
  ///
  /// After the critical batch commits, a `users/{uid}/verificationAttempts/
  /// {auto-id}` audit row is appended **best-effort**.  That write depends
  /// on a separate Firestore rule and MUST NOT block the user's go-live
  /// path — if the rule is missing or the append fails for any reason, the
  /// failure is logged and the session still succeeds.  See
  /// [_recordVerificationAttempt] for the rationale.
  ///
  /// Throws if the critical batch fails so the caller can roll back
  /// in-memory state.
  Future<void> startSession({
    required String uid,
    required LiveVerificationMethod verificationMethod,
    required int maxDistanceMetersSnapshot,
    required String interestedInSnapshot,
    required int ageRangeMinSnapshot,
    required int ageRangeMaxSnapshot,
    required int liveCreditsAtStart,
    required int remainingLiveCredits,
    String? liveSelfieUrl,
  }) async {
    final now = DateTime.now();
    final expires = now.add(const Duration(hours: 1));
    final historyRef = _historyCollection().doc();

    // visibilityState IS the discovery/read gate: only 'discoverable' permits
    // cross-user reads at the security-rules layer.  Going Live always starts
    // discoverable — there is no user-controlled opt-out.  Visibility flips to
    // hidden states only as a result of the meetup state machine.
    const initialVisibility = LiveSessionVisibility.discoverable;

    final batch = _db.batch();
    batch.set(_liveDoc(uid), {
      'uid': uid,
      'status': liveSessionStatusName(LiveSessionStatus.active),
      'endedReason': null,
      'startedAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(expires),
      'endedAt': null,
      'verificationMethod': liveVerificationMethodName(verificationMethod),
      'verificationCompletedAt': FieldValue.serverTimestamp(),
      'historyId': historyRef.id,
      'currentMeetupId': null,
      'visibilityState': liveSessionVisibilityName(initialVisibility),
      // Session-scoped Firebase Storage URL for the live verification selfie.
      // Null when the upload failed or the platform did not produce a file
      // (DEV Test Mode paths).  Cleared on terminal writes below.
      'liveSelfieUrl': liveSelfieUrl,
      // Position is nulled at start; populated by [writePosition] once GPS
      // returns a fix (usually <2 s with a warm cache).
      'lat': null,
      'lng': null,
      'geohash': null,
      'locationUpdatedAt': null,
      'maxDistanceMetersSnapshot': maxDistanceMetersSnapshot,
      'interestedInSnapshot': interestedInSnapshot,
      'ageRangeMinSnapshot': ageRangeMinSnapshot,
      'ageRangeMaxSnapshot': ageRangeMaxSnapshot,
      'liveCreditsAtStart': liveCreditsAtStart,
      'platform': _platformString,
      'schemaVersion': kLiveSessionSchemaVersion,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(historyRef, {
      'uid': uid,
      'sessionDocId': uid,
      'status': liveSessionStatusName(LiveSessionStatus.active),
      'endedReason': null,
      'startedAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(expires),
      'endedAt': null,
      'verificationMethod': liveVerificationMethodName(verificationMethod),
      'verificationCompletedAt': FieldValue.serverTimestamp(),
      'currentMeetupId': null,
      'visibilityState': liveSessionVisibilityName(initialVisibility),
      'liveSelfieUrl': liveSelfieUrl,
      'lat': null,
      'lng': null,
      'geohash': null,
      'locationUpdatedAt': null,
      'maxDistanceMetersSnapshot': maxDistanceMetersSnapshot,
      'interestedInSnapshot': interestedInSnapshot,
      'ageRangeMinSnapshot': ageRangeMinSnapshot,
      'ageRangeMaxSnapshot': ageRangeMaxSnapshot,
      'liveCreditsAtStart': liveCreditsAtStart,
      'platform': _platformString,
      'schemaVersion': kLiveSessionSchemaVersion,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.update(_userDoc(uid), {
      'isLive': true,
      // Do Not Disturb was removed (2026-05-20).  No longer auto-cleared
      // here; legacy on-disk values are simply ignored by both client and
      // server.
      'liveCredits': remainingLiveCredits,
      // Phase-1 durable verification trust signal — survives session end.
      // The `users/{uid}` write rule already permits owner writes of any
      // field, so these stay inside the critical batch with no new rule
      // dependency.
      'verificationStatus': kVerificationStatusPhotoVerified,
      'photoVerifiedAt': FieldValue.serverTimestamp(),
      'lastVerificationMethod': liveVerificationMethodName(verificationMethod),
    });
    await batch.commit();

    // Audit append — deliberately AFTER the critical batch commits, so a
    // missing/strict subcollection rule cannot brick the user's go-live.
    _recordVerificationAttempt(
      uid: uid,
      verificationMethod: verificationMethod,
      eventType: 'go_live',
    );
  }

  /// Records a redo verification (user re-captured their live selfie while
  /// already live).  Re-stamps `verificationStatus`, `photoVerifiedAt`, and
  /// `lastVerificationMethod` on `users/{uid}` (idempotent), then appends a
  /// best-effort audit row with `eventType: 'redo'`.
  ///
  /// As with [startSession], the audit append cannot block the user — a
  /// missing subcollection rule degrades the audit trail but does not break
  /// the redo flow.  `LiveSession.updateSelfie` already swaps the in-memory
  /// selfie/avatar paths regardless of this write's outcome.
  Future<void> recordPhotoVerificationRedo({
    required String uid,
    required LiveVerificationMethod verificationMethod,
  }) async {
    await _userDoc(uid).update({
      'verificationStatus': kVerificationStatusPhotoVerified,
      'photoVerifiedAt': FieldValue.serverTimestamp(),
      'lastVerificationMethod': liveVerificationMethodName(verificationMethod),
    });
    _recordVerificationAttempt(
      uid: uid,
      verificationMethod: verificationMethod,
      eventType: 'redo',
    );
  }

  /// Best-effort append to `users/{uid}/verificationAttempts/{auto-id}`.
  /// Fire-and-forget by design: the audit trail is valuable for trust /
  /// moderation work, but the user's go-live or redo flow MUST NOT fail
  /// because an audit row could not be written.  The most likely real-world
  /// failure mode is "new Firestore rule for the subcollection has not been
  /// deployed yet" → permission-denied; logging here makes that diagnosable
  /// without taking down the live session.
  void _recordVerificationAttempt({
    required String uid,
    required LiveVerificationMethod verificationMethod,
    required String eventType,
  }) {
    _verificationAttempts(uid)
        .add({
          'uid': uid,
          'kind': 'live_selfie',
          'method': liveVerificationMethodName(verificationMethod),
          'outcome': 'verified',
          'eventType': eventType,
          // live_sessions docs are keyed by uid (one active session per user),
          // so the uid alone identifies the session this attempt belongs to.
          // The `createdAt` server timestamp pins it to a specific session
          // window.
          'liveSessionId': uid,
          'createdAt': FieldValue.serverTimestamp(),
        })
        .then(
          (_) {},
          onError: (Object e) {
            debugPrint(
              '[LiveSessionRepository] verificationAttempts append failed '
              '(non-fatal — go-live / redo succeeded): $e',
            );
          },
        );
  }

  /// Writes the latest GPS position + geohash onto both the session doc
  /// (authoritative) and the users mirror in one atomic batch.
  Future<void> writePosition({
    required String uid,
    required double lat,
    required double lng,
    required String geohash,
  }) async {
    final batch = _db.batch();
    batch.update(_liveDoc(uid), {
      'lat': lat,
      'lng': lng,
      'geohash': geohash,
      'locationUpdatedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.update(_userDoc(uid), {
      'latitude': lat,
      'longitude': lng,
      'geohash': geohash,
      'locationUpdatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  /// Refresh-only heartbeat: bumps `locationUpdatedAt` on both docs without
  /// touching lat/lng/geohash.  Used when GPS is momentarily unavailable
  /// (sensor transient, iOS background throttling, services blip) so the
  /// session does not go "stale" in Nearby for what is really a missing
  /// sensor read — last-known coords stay valid until the next successful
  /// [writePosition].  Same dual-write contract as [writePosition]: the
  /// authoritative session doc and the users mirror move together in one
  /// atomic batch.
  Future<void> heartbeatPosition({required String uid}) async {
    final batch = _db.batch();
    batch.update(_liveDoc(uid), {
      'locationUpdatedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.update(_userDoc(uid), {
      'locationUpdatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  /// Marks the session as ended (user tapped End Live, blocked terminal, or
  /// another non-expiry reason).  Atomically:
  ///   • flips `live_sessions/{uid}` to `status: ended`, records [reason],
  ///     clears position fields, resets visibility to discoverable, and
  ///   • updates the durable `live_session_history/{historyId}` row for this
  ///     session so prior Go Lives remain visible after the current doc is
  ///     reused, and
  ///   • flips the `users/{uid}` mirror to `isLive: false` and deletes the
  ///     mirrored position fields so Nearby / notifications stay consistent.
  Future<void> markEnded({
    required String uid,
    required LiveSessionEndedReason reason,
  }) async {
    final liveSnap = await _liveDoc(uid).get();
    final data = liveSnap.data();
    final historyId =
        (data?['historyId'] as String?) ?? _historyCollection().doc().id;
    final batch = _db.batch();
    batch.update(_liveDoc(uid), {
      'status': liveSessionStatusName(LiveSessionStatus.ended),
      'endedReason': liveSessionEndedReasonName(reason),
      'endedAt': FieldValue.serverTimestamp(),
      'visibilityState': liveSessionVisibilityName(
        LiveSessionVisibility.discoverable,
      ),
      'liveSelfieUrl': null,
      'lat': null,
      'lng': null,
      'geohash': null,
      'locationUpdatedAt': null,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(_historyCollection().doc(historyId), {
      'uid': uid,
      'sessionDocId': uid,
      'status': liveSessionStatusName(LiveSessionStatus.ended),
      'endedReason': liveSessionEndedReasonName(reason),
      'startedAt': data?['startedAt'],
      'expiresAt': data?['expiresAt'],
      'endedAt': FieldValue.serverTimestamp(),
      'verificationMethod': data?['verificationMethod'],
      'verificationCompletedAt': data?['verificationCompletedAt'],
      'currentMeetupId': data?['currentMeetupId'],
      'visibilityState': liveSessionVisibilityName(
        LiveSessionVisibility.discoverable,
      ),
      // Keep the session selfie + last known location on the durable history
      // row even though the current live doc is cleared for privacy / reuse.
      'liveSelfieUrl': data?['liveSelfieUrl'],
      'lat': data?['lat'],
      'lng': data?['lng'],
      'geohash': data?['geohash'],
      'locationUpdatedAt': data?['locationUpdatedAt'],
      'maxDistanceMetersSnapshot': data?['maxDistanceMetersSnapshot'],
      'interestedInSnapshot': data?['interestedInSnapshot'],
      'ageRangeMinSnapshot': data?['ageRangeMinSnapshot'],
      'ageRangeMaxSnapshot': data?['ageRangeMaxSnapshot'],
      'liveCreditsAtStart': data?['liveCreditsAtStart'],
      'platform': data?['platform'] ?? _platformString,
      'schemaVersion': data?['schemaVersion'] ?? kLiveSessionSchemaVersion,
      'createdAt': data?['createdAt'] ?? FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    batch.update(_userDoc(uid), {
      'isLive': false,
      'latitude': FieldValue.delete(),
      'longitude': FieldValue.delete(),
      'geohash': FieldValue.delete(),
      'locationUpdatedAt': FieldValue.delete(),
    });
    await batch.commit();
  }

  /// Marks the session as expired — same clearing behavior as [markEnded] but
  /// with `status: 'expired'` so metrics / audit can distinguish "timer ran
  /// out" from "user action".
  ///
  /// [reason] is optional: null for a routine timer expiry, or
  /// [LiveSessionEndedReason.crashRecovered] when `hydrateOnLaunch` trips a
  /// still-active doc whose `expiresAt` is already in the past (the app was
  /// force-killed mid-session and has just relaunched past the 1 h window).
  Future<void> markExpired({
    required String uid,
    LiveSessionEndedReason? reason,
  }) async {
    final liveSnap = await _liveDoc(uid).get();
    final data = liveSnap.data();
    final historyId =
        (data?['historyId'] as String?) ?? _historyCollection().doc().id;
    final batch = _db.batch();
    batch.update(_liveDoc(uid), {
      'status': liveSessionStatusName(LiveSessionStatus.expired),
      'endedReason': reason == null ? null : liveSessionEndedReasonName(reason),
      'endedAt': FieldValue.serverTimestamp(),
      'visibilityState': liveSessionVisibilityName(
        LiveSessionVisibility.discoverable,
      ),
      'liveSelfieUrl': null,
      'lat': null,
      'lng': null,
      'geohash': null,
      'locationUpdatedAt': null,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(_historyCollection().doc(historyId), {
      'uid': uid,
      'sessionDocId': uid,
      'status': liveSessionStatusName(LiveSessionStatus.expired),
      'endedReason': reason == null ? null : liveSessionEndedReasonName(reason),
      'startedAt': data?['startedAt'],
      'expiresAt': data?['expiresAt'],
      'endedAt': FieldValue.serverTimestamp(),
      'verificationMethod': data?['verificationMethod'],
      'verificationCompletedAt': data?['verificationCompletedAt'],
      'currentMeetupId': data?['currentMeetupId'],
      'visibilityState': liveSessionVisibilityName(
        LiveSessionVisibility.discoverable,
      ),
      'liveSelfieUrl': data?['liveSelfieUrl'],
      'lat': data?['lat'],
      'lng': data?['lng'],
      'geohash': data?['geohash'],
      'locationUpdatedAt': data?['locationUpdatedAt'],
      'maxDistanceMetersSnapshot': data?['maxDistanceMetersSnapshot'],
      'interestedInSnapshot': data?['interestedInSnapshot'],
      'ageRangeMinSnapshot': data?['ageRangeMinSnapshot'],
      'ageRangeMaxSnapshot': data?['ageRangeMaxSnapshot'],
      'liveCreditsAtStart': data?['liveCreditsAtStart'],
      'platform': data?['platform'] ?? _platformString,
      'schemaVersion': data?['schemaVersion'] ?? kLiveSessionSchemaVersion,
      'createdAt': data?['createdAt'] ?? FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    batch.update(_userDoc(uid), {
      'isLive': false,
      'latitude': FieldValue.delete(),
      'longitude': FieldValue.delete(),
      'geohash': FieldValue.delete(),
      'locationUpdatedAt': FieldValue.delete(),
    });
    await batch.commit();
  }

  /// Single-doc update of just `live_sessions/{uid}.liveSelfieUrl`.  Used by
  /// the redo path so the new remote selfie reaches Nearby without a full
  /// session restart.  No `users/{uid}` mirror — `liveSelfieUrl` is session-
  /// scoped and never written to the users doc.  Also patches the durable
  /// history row for the same session so historical entries keep the final
  /// live selfie the user actually used.  Pass null to clear the field while
  /// leaving the rest of the session untouched.
  Future<void> setLiveSelfieUrl({
    required String uid,
    required String? url,
  }) async {
    final liveSnap = await _liveDoc(uid).get();
    final historyId = liveSnap.data()?['historyId'] as String?;
    final batch = _db.batch();
    batch.update(_liveDoc(uid), {
      'liveSelfieUrl': url,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (historyId != null) {
      batch.set(_historyCollection().doc(historyId), {
        'uid': uid,
        'sessionDocId': uid,
        'liveSelfieUrl': url,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    await batch.commit();
  }

  /// Phase-1 meetup visibility mirror: when Cloud Functions flip
  /// `users/{uid}.currentMeetupId`, the client reflects that change here so
  /// Nearby's visibility filter stays accurate.  Single-doc update — no
  /// batched mirror because the users mirror for this field is already being
  /// written by the Cloud Function.  Phase 2 replaces this with a direct
  /// Cloud Function write to `live_sessions/{uid}`.
  ///
  /// Entering a meetup hides the session (`hidden_in_meetup`); leaving a
  /// meetup restores `discoverable` unconditionally — going Live is always
  /// discoverable, so there is no per-user opt-out to honor on exit.
  Future<void> writeMeetupVisibility({
    required String uid,
    required String? currentMeetupId,
  }) async {
    final visibility = currentMeetupId != null
        ? LiveSessionVisibility.hiddenInMeetup
        : LiveSessionVisibility.discoverable;
    final visibilityName = liveSessionVisibilityName(visibility);
    debugPrint(
      '[LiveSessionRepo] writeMeetupVisibility uid=$uid '
      'currentMeetupId=$currentMeetupId visibility=$visibilityName',
    );
    final liveSnap = await _liveDoc(uid).get();
    final historyId = liveSnap.data()?['historyId'] as String?;
    final batch = _db.batch();
    batch.update(_liveDoc(uid), {
      'currentMeetupId': currentMeetupId,
      'visibilityState': visibilityName,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (historyId != null) {
      batch.set(_historyCollection().doc(historyId), {
        'uid': uid,
        'sessionDocId': uid,
        'currentMeetupId': currentMeetupId,
        'visibilityState': visibilityName,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    await batch.commit();
  }

  /// While a live session is already active, refreshes the mutable discovery
  /// snapshots on both the current-session doc and its durable history row.
  ///
  /// This is what lets Edit Profile / Nearby preferences take effect
  /// immediately instead of waiting until the next Go Live.
  Future<void> updateDiscoverySnapshot({
    required String uid,
    required int maxDistanceMetersSnapshot,
    required String interestedInSnapshot,
    required int ageRangeMinSnapshot,
    required int ageRangeMaxSnapshot,
  }) async {
    final liveSnap = await _liveDoc(uid).get();
    final historyId = liveSnap.data()?['historyId'] as String?;
    final batch = _db.batch();
    batch.update(_liveDoc(uid), {
      'maxDistanceMetersSnapshot': maxDistanceMetersSnapshot,
      'interestedInSnapshot': interestedInSnapshot,
      'ageRangeMinSnapshot': ageRangeMinSnapshot,
      'ageRangeMaxSnapshot': ageRangeMaxSnapshot,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (historyId != null) {
      batch.set(_historyCollection().doc(historyId), {
        'uid': uid,
        'sessionDocId': uid,
        'maxDistanceMetersSnapshot': maxDistanceMetersSnapshot,
        'interestedInSnapshot': interestedInSnapshot,
        'ageRangeMinSnapshot': ageRangeMinSnapshot,
        'ageRangeMaxSnapshot': ageRangeMaxSnapshot,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    await batch.commit();
  }
}

String get _platformString {
  if (kIsWeb) return 'web';
  try {
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
  } catch (_) {
    // dart:io Platform getters throw on unsupported platforms — fall through.
  }
  return 'unknown';
}
