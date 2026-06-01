import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

/// Owns gallery uploads + the ordered `photoUrls` list that the public profile
/// reads.  Two write surfaces:
///   - [uploadPhoto] pushes a local file to Storage and returns its download
///     URL.
///   - [writeOrderedUrls] persists the canonical list back to both
///     `users/{uid}.photoUrls` (the private source) and `profiles/{uid}`
///     (the public mirror).
class ProfileMediaRepository {
  ProfileMediaRepository({
    FirebaseStorage? storage,
    FirebaseFirestore? firestore,
  })  : _storage = storage ?? FirebaseStorage.instance,
        _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseStorage _storage;
  final FirebaseFirestore _db;

  /// Uploads [file] to `users/{uid}/photos/{timestamp}.jpg` in Storage and
  /// returns the public download URL.  Caller is responsible for adding the
  /// URL to the ordered list via [writeOrderedUrls].
  Future<String> uploadPhoto({
    required String uid,
    required File file,
  }) async {
    final filename = '${DateTime.now().millisecondsSinceEpoch}.jpg';
    final ref = _storage.ref('users/$uid/photos/$filename');
    final metadata = SettableMetadata(contentType: 'image/jpeg');
    final task = await ref.putFile(file, metadata);
    final url = await task.ref.getDownloadURL();
    debugPrint('[ProfileMediaRepository] uploaded $filename → $url');
    return url;
  }

  /// Writes the [urls] list to both `users/{uid}.photoUrls` (the source of
  /// truth) and `profiles/{uid}.photoUrls` (the public mirror) in a single
  /// batch.  Callers serialise their writes externally so the LAST batch to
  /// commit wins — this method does not arbitrate between concurrent writers.
  Future<void> writeOrderedUrls({
    required String uid,
    required List<String> urls,
  }) async {
    final batch = _db.batch();
    final usersRef = _db.collection('users').doc(uid);
    final profilesRef = _db.collection('profiles').doc(uid);
    final payload = <String, dynamic>{
      'photoUrls': urls,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    batch.set(usersRef, payload, SetOptions(merge: true));
    batch.set(profilesRef, payload, SetOptions(merge: true));
    await batch.commit();
  }
}
