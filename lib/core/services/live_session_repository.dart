import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/live_session_model.dart';

/// Firestore I/O for `live_sessions/{uid}`.
///
/// Phase 1 strategy is dual-write:
///   - This repository writes `live_sessions/{uid}` as the authoritative
///     source of truth for the client.
///   - The caller ALSO mirror-writes `users/{uid}.{isLive, geohash, latitude,
///     longitude, locationUpdatedAt, doNotDisturb}` so the existing Cloud
///     Functions (which read those fields on `users/{uid}`) keep working
///     unchanged.  Phase 2 removes that mirror once the functions are updated.
///
/// No timers, no in-memory state, no ChangeNotifier — this layer is stateless.
class LiveSessionRepository {
  LiveSessionRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      _db.collection('live_sessions').doc(uid);

  /// One-shot read of `live_sessions/{uid}`.  Returns null when the doc is
  /// missing (user has never gone live, or the doc was cleared).
  Future<LiveSessionModel?> load(String uid) async {
    final snap = await _doc(uid).get();
    if (!snap.exists) return null;
    return LiveSessionModel.fromSnapshot(snap);
  }

  /// Live stream of `live_sessions/{uid}` — drives in-memory state in
  /// `LiveSession`.  Emits null when the doc is deleted or does not exist.
  Stream<LiveSessionModel?> watch(String uid) {
    return _doc(uid).snapshots().map((snap) {
      if (!snap.exists) return null;
      return LiveSessionModel.fromSnapshot(snap);
    });
  }

  /// Creates (or overwrites) the session doc when a user goes live.
  ///
  /// Writes a full, self-contained document — not a merge — because a new
  /// session must not inherit stale fields from a prior terminal doc (e.g.
  /// [endedAt] / [endedReason]).  The doc ID is the uid, so this implicitly
  /// replaces any previous session record.
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

    await _doc(uid).set({
      'uid': uid,
      'status': liveSessionStatusName(LiveSessionStatus.active),
      'endedReason': null,
      'startedAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(expires),
      'endedAt': null,
      'verificationMethod': liveVerificationMethodName(verificationMethod),
      'verificationCompletedAt': FieldValue.serverTimestamp(),
      'currentMeetupId': null,
      'visibilityState':
          liveSessionVisibilityName(LiveSessionVisibility.discoverable),
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
  }

  /// Writes the latest GPS position + geohash onto the live session doc.
  /// Called by the 60-second location timer while a session is active, and
  /// once on app resume.  No-op if [uid]'s doc does not exist.
  Future<void> writePosition({
    required String uid,
    required double lat,
    required double lng,
    required String geohash,
  }) {
    return _doc(uid).update({
      'lat': lat,
      'lng': lng,
      'geohash': geohash,
      'locationUpdatedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Marks the session as ended (user tapped End Live, or another terminal
  /// non-expiry reason).  Clears location fields so a terminal doc cannot be
  /// queried as a valid Nearby candidate by a future client bug.
  Future<void> markEnded({
    required String uid,
    required LiveSessionEndedReason reason,
  }) {
    return _doc(uid).update({
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
  }

  /// Marks the session as expired — the 1-hour clock ran out.  Same clearing
  /// behavior as [markEnded] but with the `expired` status so metrics / audit
  /// can distinguish "timer" from "user action".
  Future<void> markExpired({required String uid}) {
    return _doc(uid).update({
      'status': liveSessionStatusName(LiveSessionStatus.expired),
      'endedReason': null,
      'endedAt': FieldValue.serverTimestamp(),
      'visibilityState':
          liveSessionVisibilityName(LiveSessionVisibility.discoverable),
      'lat': null,
      'lng': null,
      'geohash': null,
      'locationUpdatedAt': null,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Phase-1 visibility mirror: when `users/{uid}.currentMeetupId` changes,
  /// reflect that into the live session so Nearby's visibility filter on the
  /// new collection stays accurate.  Phase 2 replaces this with a direct
  /// Cloud Function write.
  Future<void> writeMeetupVisibility({
    required String uid,
    required String? currentMeetupId,
  }) {
    return _doc(uid).update({
      'currentMeetupId': currentMeetupId,
      'visibilityState': liveSessionVisibilityName(
        currentMeetupId == null
            ? LiveSessionVisibility.discoverable
            : LiveSessionVisibility.hiddenInMeetup,
      ),
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
