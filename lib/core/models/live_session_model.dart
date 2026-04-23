import 'package:cloud_firestore/cloud_firestore.dart';

/// Canonical live-session status.
///
/// Intentionally small — detail about *why* a session ended lives in
/// [LiveSessionEndedReason] rather than being encoded into more status values.
enum LiveSessionStatus { active, ended, expired }

/// Optional detail on why a session terminated.  Only meaningful when
/// [LiveSessionModel.status] is [LiveSessionStatus.ended].
enum LiveSessionEndedReason { manual, blocked, crashRecovered, other }

/// Who can currently see this session in Nearby.
///
/// `discoverable`      — appears in Nearby cell queries.
/// `hidden_in_meetup`  — the owner is currently in a meetup; hidden from Nearby
///                       but the session is still technically active.
/// `continued_private` — the meetup concluded with we_got_this; the owner stays
///                       hidden from Nearby because they are now chatting with
///                       that match.  Written by a Cloud Function in Phase 2;
///                       in Phase 1 the client uses `hidden_in_meetup` for both
///                       of these states (both hide from Nearby identically).
enum LiveSessionVisibility { discoverable, hiddenInMeetup, continuedPrivate }

/// Which verification path produced this session.
///
/// `liveSelfie`              — real front-camera capture on iOS/Android.
/// `testModeProfilePhoto`    — DEV Test Mode on non-mobile: used the primary
///                             profile photo.  Never reachable in release.
/// `testModeDemo`            — DEV demo selfie (colored circle).  Never
///                             reachable in release.
enum LiveVerificationMethod { liveSelfie, testModeProfilePhoto, testModeDemo }

/// Current schema version for `live_sessions/{uid}`.  Bump when the shape
/// changes in a way clients need to branch on; for Phase 1 this is `1`.
const int kLiveSessionSchemaVersion = 1;

/// Data class for a single document in `live_sessions/{uid}`.
///
/// Owns pure serialization only — no Firestore calls, no ChangeNotifier,
/// no timers.  See `live_session_repository.dart` for writes and
/// `live_session.dart` for the in-memory state machine.
class LiveSessionModel {
  const LiveSessionModel({
    required this.uid,
    required this.status,
    this.endedReason,
    required this.startedAt,
    required this.expiresAt,
    this.endedAt,
    required this.verificationMethod,
    required this.verificationCompletedAt,
    this.currentMeetupId,
    required this.visibilityState,
    this.lat,
    this.lng,
    this.geohash,
    this.locationUpdatedAt,
    required this.maxDistanceMetersSnapshot,
    required this.discoverableSnapshot,
    required this.showMeSnapshot,
    required this.ageRangeMinSnapshot,
    required this.ageRangeMaxSnapshot,
    required this.liveCreditsAtStart,
    required this.platform,
    required this.schemaVersion,
    required this.createdAt,
    required this.updatedAt,
  });

  final String uid;
  final LiveSessionStatus status;
  final LiveSessionEndedReason? endedReason;
  final DateTime startedAt;
  final DateTime expiresAt;
  final DateTime? endedAt;
  final LiveVerificationMethod verificationMethod;
  final DateTime verificationCompletedAt;
  final String? currentMeetupId;
  final LiveSessionVisibility visibilityState;
  final double? lat;
  final double? lng;
  final String? geohash;
  final DateTime? locationUpdatedAt;
  final int maxDistanceMetersSnapshot;
  final bool discoverableSnapshot;
  final String showMeSnapshot;
  final int ageRangeMinSnapshot;
  final int ageRangeMaxSnapshot;
  final int liveCreditsAtStart;
  final String platform;
  final int schemaVersion;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isActive => status == LiveSessionStatus.active;
  bool get isDiscoverable =>
      status == LiveSessionStatus.active &&
      visibilityState == LiveSessionVisibility.discoverable;

  /// Remaining session duration, clamped to non-negative and capped at 1h to
  /// absorb client-vs-server clock skew.
  Duration remainingFrom(DateTime now) {
    if (!isActive) return Duration.zero;
    final raw = expiresAt.difference(now);
    if (raw.isNegative) return Duration.zero;
    const cap = Duration(hours: 1);
    return raw > cap ? cap : raw;
  }

  factory LiveSessionModel.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> snap) {
    final d = snap.data()!;
    return LiveSessionModel(
      uid: snap.id,
      status: _parseStatus(d['status'] as String?),
      endedReason: _parseEndedReason(d['endedReason'] as String?),
      startedAt: _ts(d['startedAt']),
      expiresAt: _ts(d['expiresAt']),
      endedAt: _tsOrNull(d['endedAt']),
      verificationMethod: _parseVerif(d['verificationMethod'] as String?),
      verificationCompletedAt: _ts(d['verificationCompletedAt']),
      currentMeetupId: d['currentMeetupId'] as String?,
      visibilityState: _parseVisibility(d['visibilityState'] as String?),
      lat: (d['lat'] as num?)?.toDouble(),
      lng: (d['lng'] as num?)?.toDouble(),
      geohash: d['geohash'] as String?,
      locationUpdatedAt: _tsOrNull(d['locationUpdatedAt']),
      maxDistanceMetersSnapshot:
          (d['maxDistanceMetersSnapshot'] as num?)?.toInt() ?? 30,
      discoverableSnapshot: (d['discoverableSnapshot'] as bool?) ?? true,
      showMeSnapshot: (d['showMeSnapshot'] as String?) ?? 'everyone',
      ageRangeMinSnapshot: (d['ageRangeMinSnapshot'] as num?)?.toInt() ?? 18,
      ageRangeMaxSnapshot: (d['ageRangeMaxSnapshot'] as num?)?.toInt() ?? 99,
      liveCreditsAtStart: (d['liveCreditsAtStart'] as num?)?.toInt() ?? 0,
      platform: (d['platform'] as String?) ?? 'unknown',
      schemaVersion: (d['schemaVersion'] as num?)?.toInt() ?? 1,
      createdAt: _ts(d['createdAt']),
      updatedAt: _ts(d['updatedAt']),
    );
  }

  static LiveSessionStatus _parseStatus(String? s) {
    switch (s) {
      case 'active':
        return LiveSessionStatus.active;
      case 'expired':
        return LiveSessionStatus.expired;
      case 'ended':
      default:
        return LiveSessionStatus.ended;
    }
  }

  static LiveSessionEndedReason? _parseEndedReason(String? s) {
    switch (s) {
      case 'manual':
        return LiveSessionEndedReason.manual;
      case 'blocked':
        return LiveSessionEndedReason.blocked;
      case 'crash_recovered':
        return LiveSessionEndedReason.crashRecovered;
      case 'other':
        return LiveSessionEndedReason.other;
      default:
        return null;
    }
  }

  static LiveVerificationMethod _parseVerif(String? s) {
    switch (s) {
      case 'test_mode_profile_photo':
        return LiveVerificationMethod.testModeProfilePhoto;
      case 'test_mode_demo':
        return LiveVerificationMethod.testModeDemo;
      case 'live_selfie':
      default:
        return LiveVerificationMethod.liveSelfie;
    }
  }

  static LiveSessionVisibility _parseVisibility(String? s) {
    switch (s) {
      case 'hidden_in_meetup':
        return LiveSessionVisibility.hiddenInMeetup;
      case 'continued_private':
        return LiveSessionVisibility.continuedPrivate;
      case 'discoverable':
      default:
        return LiveSessionVisibility.discoverable;
    }
  }

  static DateTime _ts(Object? v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  static DateTime? _tsOrNull(Object? v) {
    if (v == null) return null;
    return _ts(v);
  }
}

// ── String codecs ─────────────────────────────────────────────────────────────

String liveSessionStatusName(LiveSessionStatus s) => switch (s) {
      LiveSessionStatus.active => 'active',
      LiveSessionStatus.ended => 'ended',
      LiveSessionStatus.expired => 'expired',
    };

String liveSessionEndedReasonName(LiveSessionEndedReason r) => switch (r) {
      LiveSessionEndedReason.manual => 'manual',
      LiveSessionEndedReason.blocked => 'blocked',
      LiveSessionEndedReason.crashRecovered => 'crash_recovered',
      LiveSessionEndedReason.other => 'other',
    };

String liveVerificationMethodName(LiveVerificationMethod m) => switch (m) {
      LiveVerificationMethod.liveSelfie => 'live_selfie',
      LiveVerificationMethod.testModeProfilePhoto => 'test_mode_profile_photo',
      LiveVerificationMethod.testModeDemo => 'test_mode_demo',
    };

String liveSessionVisibilityName(LiveSessionVisibility v) => switch (v) {
      LiveSessionVisibility.discoverable => 'discoverable',
      LiveSessionVisibility.hiddenInMeetup => 'hidden_in_meetup',
      LiveSessionVisibility.continuedPrivate => 'continued_private',
    };
