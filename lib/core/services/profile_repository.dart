import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Reads and writes the public-facing `profiles/{uid}` mirror.
///
/// Two-collection model:
///   - `users/{uid}` is the private source of truth (auth-bound fields, credits,
///     settings, internal flags).
///   - `profiles/{uid}` is the public surface that other users read via Nearby
///     / Messages / chat-thread headers.  It mirrors only the fields needed
///     for display + filtering.
///
/// All callers write through this repository so the field set stays consistent
/// — onboarding screens, the edit-profile screen, and the gallery all funnel
/// here.
class ProfileRepository {
  ProfileRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _ref(String uid) =>
      _db.collection('profiles').doc(uid);

  /// Returns the current public profile snapshot, or null if the document
  /// doesn't exist yet.  Used by app boot to hydrate UserProfile.
  Future<Map<String, dynamic>?> fetch(String uid) async {
    final snap = await _ref(uid).get();
    if (!snap.exists) return null;
    return snap.data();
  }

  /// Creates `profiles/{uid}` from a fallback payload if it's missing.  Used
  /// during the auth-listener bootstrap when a legacy user has a populated
  /// `users/{uid}` but no profile mirror yet.  Returns true if a new document
  /// was written, false if the profile already existed.
  Future<bool> ensureExists(
    String uid, {
    required Map<String, dynamic> fallback,
  }) async {
    final ref = _ref(uid);
    final snap = await ref.get();
    if (snap.exists) return false;

    final seed = <String, dynamic>{
      ..._publicFieldsFromUsers(fallback),
      'createdAt': FieldValue.serverTimestamp(),
    };
    await ref.set(seed);
    debugPrint('[ProfileRepository] materialised profiles/$uid');
    return true;
  }

  /// Merge-writes [fields] into `profiles/{uid}`.  Callers pass exactly the
  /// shape they want persisted (no implicit mirroring), so this is a thin
  /// wrapper over Firestore — the value is centralising error-logging and the
  /// merge flag.
  Future<void> setFields(String uid, Map<String, dynamic> fields) async {
    if (fields.isEmpty) return;
    await _ref(uid).set(fields, SetOptions(merge: true));
  }

  /// Convenience write used by EditProfileScreen.  Sets the full editable
  /// field set in one merge call so the public profile updates atomically.
  /// `null` values are skipped so callers can pass through unmodified.
  Future<void> saveEditableFields({
    required String uid,
    String? firstName,
    int? age,
    String? bio,
    String? occupation,
    String? height,
    String? lookingFor,
    String? interestedIn,
    num? ageRangeMin,
    num? ageRangeMax,
    Iterable<String>? interests,
    Iterable<String>? hobbies,
  }) async {
    final payload = <String, dynamic>{
      if (firstName != null) 'firstName': firstName,
      if (age != null) 'age': age,
      if (bio != null) 'bio': bio,
      if (occupation != null) 'occupation': occupation,
      if (height != null) 'height': height,
      if (lookingFor != null) 'lookingFor': lookingFor,
      if (interestedIn != null) 'interestedIn': interestedIn,
      if (ageRangeMin != null) 'ageRangeMin': ageRangeMin.toInt(),
      if (ageRangeMax != null) 'ageRangeMax': ageRangeMax.toInt(),
      if (interests != null) 'interests': interests.toList(),
      if (hobbies != null) 'hobbies': hobbies.toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    // ignore_for_file: use_null_aware_elements
    await setFields(uid, payload);
  }

  /// Filters a raw `users/{uid}` payload down to the subset that's safe and
  /// useful to mirror to `profiles/{uid}`.  Excludes credits, auth, settings,
  /// and any field that would expose private state.
  Map<String, dynamic> _publicFieldsFromUsers(Map<String, dynamic> users) {
    const allowedKeys = {
      'firstName',
      'age',
      'bio',
      'occupation',
      'height',
      'gender',
      'orientation',
      'lookingFor',
      'interestedIn',
      'interests',
      'hobbies',
      'photoUrls',
      'avatarUrl',
      'selfieUrl',
      'hometown',
      'hometownDisplay',
      'hometownShort',
      'ageRangeMin',
      'ageRangeMax',
    };
    return {
      for (final key in allowedKeys)
        if (users.containsKey(key)) key: users[key],
    };
  }
}
