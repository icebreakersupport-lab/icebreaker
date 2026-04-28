import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/live_session_model.dart';

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
///   locationUpdatedAt, doNotDisturb}` keep working unchanged.  Phase 2
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
  ///   • flips the `users/{uid}` mirror to `isLive: true, doNotDisturb: false`.
  ///
  /// Throws if the batch fails so the caller can roll back in-memory state.
  Future<void> startSession({
    required String uid,
    required LiveVerificationMethod verificationMethod,
    required int maxDistanceMetersSnapshot,
    required bool discoverableSnapshot,
    required String showMeSnapshot,
    required int ageRangeMinSnapshot,
    required int ageRangeMaxSnapshot,
    required int liveCreditsAtStart,
  }) async {
    final now = DateTime.now();
    final expires = now.add(const Duration(hours: 1));

    // visibilityState IS the discovery/read gate: only 'discoverable' permits
    // cross-user reads at the security-rules layer.  When the owner opts out
    // of discovery we write 'discovery_disabled' so the session is structurally
    // unreachable through Nearby — it never relies on client-side filtering.
    final initialVisibility = discoverableSnapshot
        ? LiveSessionVisibility.discoverable
        : LiveSessionVisibility.discoveryDisabled;

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
      'currentMeetupId': null,
      'visibilityState': liveSessionVisibilityName(initialVisibility),
      // Position is nulled at start; populated by [writePosition] once GPS
      // returns a fix (usually <2 s with a warm cache).
      'lat': null,
      'lng': null,
      'geohash': null,
      'locationUpdatedAt': null,
      'maxDistanceMetersSnapshot': maxDistanceMetersSnapshot,
      'discoverableSnapshot': discoverableSnapshot,
      'showMeSnapshot': showMeSnapshot,
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
      'doNotDisturb': false,
    });
    await batch.commit();
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

  /// Marks the session as ended (user tapped End Live, blocked terminal, or
  /// another non-expiry reason).  Atomically:
  ///   • flips `live_sessions/{uid}` to `status: ended`, records [reason],
  ///     clears position fields, resets visibility to discoverable, and
  ///   • flips the `users/{uid}` mirror to `isLive: false` and deletes the
  ///     mirrored position fields so Nearby / notifications stay consistent.
  Future<void> markEnded({
    required String uid,
    required LiveSessionEndedReason reason,
  }) async {
    final batch = _db.batch();
    batch.update(_liveDoc(uid), {
      'status': liveSessionStatusName(LiveSessionStatus.ended),
      'endedReason': liveSessionEndedReasonName(reason),
      'endedAt': FieldValue.serverTimestamp(),
      'visibilityState':
          liveSessionVisibilityName(LiveSessionVisibility.discoverable),
      'lat': null,
      'lng': null,
      'geohash': null,
      'locationUpdatedAt': null,
      'updatedAt': FieldValue.serverTimestamp(),
    });
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
    final batch = _db.batch();
    batch.update(_liveDoc(uid), {
      'status': liveSessionStatusName(LiveSessionStatus.expired),
      'endedReason':
          reason == null ? null : liveSessionEndedReasonName(reason),
      'endedAt': FieldValue.serverTimestamp(),
      'visibilityState':
          liveSessionVisibilityName(LiveSessionVisibility.discoverable),
      'lat': null,
      'lng': null,
      'geohash': null,
      'locationUpdatedAt': null,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.update(_userDoc(uid), {
      'isLive': false,
      'latitude': FieldValue.delete(),
      'longitude': FieldValue.delete(),
      'geohash': FieldValue.delete(),
      'locationUpdatedAt': FieldValue.delete(),
    });
    await batch.commit();
  }

  /// Phase-1 meetup visibility mirror: when Cloud Functions flip
  /// `users/{uid}.currentMeetupId`, the client reflects that change here so
  /// Nearby's visibility filter stays accurate.  Single-doc update — no
  /// batched mirror because the users mirror for this field is already being
  /// written by the Cloud Function.  Phase 2 replaces this with a direct
  /// Cloud Function write to `live_sessions/{uid}`.
  ///
  /// [discoverableSnapshot] is the value frozen onto the session at Go Live.
  /// When the user is *leaving* a meetup (currentMeetupId becomes null) we
  /// must restore the right visibility for them — `discoverable` only when
  /// they originally opted in, `discovery_disabled` otherwise.  Without this
  /// the previous implementation would have re-opened a non-discoverable
  /// session to cross-user reads on every meetup exit.
  Future<void> writeMeetupVisibility({
    required String uid,
    required String? currentMeetupId,
    required bool discoverableSnapshot,
  }) {
    final visibility = currentMeetupId != null
        ? LiveSessionVisibility.hiddenInMeetup
        : (discoverableSnapshot
            ? LiveSessionVisibility.discoverable
            : LiveSessionVisibility.discoveryDisabled);
    return _liveDoc(uid).update({
      'currentMeetupId': currentMeetupId,
      'visibilityState': liveSessionVisibilityName(visibility),
      'updatedAt': FieldValue.serverTimestamp(),
    });
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
