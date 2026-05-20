import 'package:cloud_firestore/cloud_firestore.dart';

/// Persistence boundary for the canonical public profile document.
///
/// `profiles/{uid}` is the display surface — what other users see on the
/// nearby card, the about-me card, and the profile screen.  It mirrors a
/// curated subset of the (private) `users/{uid}` document while leaving the
/// account / trust / live / settings / credit fields exclusively on
/// `users/{uid}`.
///
/// This split is intentional:
///
///   `users/{uid}`     account state, FCM token, credits, plan, isLive,
///                     ageRange, location settings, blocked subcollections,
///                     verification attempts, etc.  Read by
///                     the Nearby discovery rule when isLive==true; otherwise
///                     owner-only.
///
///   `profiles/{uid}`  display-only fields — firstName, age, bio, opener,
///                     hometown, occupation, height, lookingFor, gender,
///                     orientation, openTo, interests, hobbies, photoUrls,
///                     primaryPhotoUrl, profileComplete, updatedAt.  Readable
///                     by any authenticated user; writable by the owner.
///
/// Onboarding and edit-profile flows write to BOTH docs during the transition
/// (dual-write) so existing readers that still hit `users/{uid}` keep
/// working.  Once every reader has been migrated to `profiles/{uid}`, the
/// dual-writes can be retired in a follow-up.
///
/// All writes use `set(..., merge: true)` so each call only touches the
/// fields it cares about — concurrent writes from different onboarding steps
/// (name, gender, location, photos) compose correctly.
class ProfileRepository {
  ProfileRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _ref(String uid) =>
      _firestore.collection('profiles').doc(uid);

  /// Generic merge-write.  Convenient for the onboarding screens which each
  /// own one or two fields and don't need a typed helper.  Always stamps
  /// `updatedAt` so consumers can sort/cache by recency.
  Future<void> setFields(String uid, Map<String, dynamic> fields) async {
    final payload = <String, dynamic>{
      ...fields,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    await _ref(uid).set(payload, SetOptions(merge: true));
  }

  /// Writes the editable profile bundle in one go (Edit Profile screen).
  /// Mirrors what `UserProfile.saveTextFields` writes locally so the public
  /// surface stays in sync with the in-memory state on every Save tap.
  Future<void> saveEditableFields({
    required String uid,
    required String firstName,
    required int age,
    required String bio,
    required String occupation,
    required String height,
    required String lookingFor,
    required String interestedIn,
    required double ageRangeMin,
    required double ageRangeMax,
    required Set<String> interests,
    required Set<String> hobbies,
  }) async {
    await setFields(uid, {
      'firstName': firstName,
      'age': age,
      'bio': bio,
      'occupation': occupation,
      'height': height,
      'lookingFor': lookingFor,
      'interestedIn': interestedIn,
      'ageRangeMin': ageRangeMin,
      'ageRangeMax': ageRangeMax,
      'interests': interests.toList(),
      'hobbies': hobbies.toList(),
    });
  }

  /// Mirror of the photoUrls / primaryPhotoUrl fields written elsewhere by
  /// `ProfileMediaRepository.writeOrderedUrls`.  Trims trailing empties to
  /// keep the array length honest, and derives the main photo URL from
  /// slot 0.
  Future<void> writePhotoUrls({
    required String uid,
    required List<String> urls,
  }) async {
    final trimmed = List<String>.from(urls);
    while (trimmed.isNotEmpty && trimmed.last.isEmpty) {
      trimmed.removeLast();
    }
    final primary =
        trimmed.isNotEmpty && trimmed.first.isNotEmpty ? trimmed.first : null;
    await setFields(uid, {
      'photoUrls': trimmed,
      'primaryPhotoUrl': primary,
    });
  }

  // ── Read API ────────────────────────────────────────────────────────────────
  //
  // Discovery, profile screen, and any other consumer of public profile data
  // reads through these helpers rather than touching `users/{uid}` directly.
  // The raw map shape is preserved (no typed model) so existing call sites
  // can swap the source with minimal churn — a single-line `.collection`
  // change rather than a full model rewrite.

  /// One-shot read of `profiles/{uid}`.  Returns null when the doc doesn't
  /// exist (a legacy account that pre-dates the dual-write).  Callers
  /// commonly fall back to `users/{uid}` in that case.
  Future<Map<String, dynamic>?> fetch(String uid) async {
    final snap = await _ref(uid).get();
    if (!snap.exists) return null;
    return snap.data();
  }

  /// Live stream of `profiles/{uid}`.  Used by the user's own profile screen
  /// so the in-memory state stays in sync with edits made from another
  /// device or background flow.  Emits null when the doc is missing.
  Stream<Map<String, dynamic>?> watch(String uid) {
    return _ref(uid)
        .snapshots()
        .map((snap) => snap.exists ? snap.data() : null);
  }

  /// Curated whitelist of public-profile fields.  Used by [ensureExists] to
  /// project a `users/{uid}` snapshot down to the canonical profiles shape
  /// without leaking private fields (email, fcmToken, plan, credits, isLive
  /// position data, settings, etc.) into the public read surface.
  static const Set<String> _publicProfileKeys = {
    'firstName',
    'age',
    'bio',
    'opener',
    'hometown',
    'hometownDisplay',
    'hometownShort',
    'occupation',
    'height',
    'lookingFor',
    'interestedIn',
    'ageRangeMin',
    'ageRangeMax',
    'gender',
    'orientation',
    'openTo',
    'interests',
    'hobbies',
    'photoUrls',
    'primaryPhotoUrl',
    'photoUrl',
    'profileComplete',
  };

  /// Materialises `profiles/{uid}` from the supplied [fallback] map (typically
  /// a `users/{uid}` snapshot) when the canonical doc is missing.  Idempotent:
  /// if the doc already exists, this is a no-op and returns false.
  ///
  /// The fallback is filtered through [_publicProfileKeys] so private fields
  /// can't leak into the public surface even if the caller hands in a full
  /// `users/{uid}` data map.  Empty maps simply seed an `updatedAt`-only
  /// document so the collection is observable in the Firebase console as
  /// soon as a user signs in, even before any field has been written.
  ///
  /// Returns true when a write actually occurred, false when the doc was
  /// already present.
  Future<bool> ensureExists(
    String uid, {
    Map<String, dynamic>? fallback,
  }) async {
    final existing = await _ref(uid).get();
    if (existing.exists) return false;

    final payload = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (fallback != null) {
      for (final key in _publicProfileKeys) {
        final value = fallback[key];
        if (value == null) continue;
        payload[key] = value;
      }
    }
    await _ref(uid).set(payload, SetOptions(merge: true));
    return true;
  }
}
