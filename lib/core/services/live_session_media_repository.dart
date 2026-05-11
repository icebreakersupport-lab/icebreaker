import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

/// Storage I/O for live verification selfies.  Each session can upload
/// multiple times (initial verification + up to 3 redos per Q3) — every
/// upload lands at a unique path so prior URLs stay resolvable until the
/// new write hits `live_sessions/{uid}.liveSelfieUrl` (see
/// [LiveSessionRepository.setLiveSelfieUrl]).
///
/// Storage layout:
///   users/{uid}/live_selfies/{millis}.jpg
///
/// The on-device file is short-lived (system temp); this repository is the
/// authoritative path that materialises the selfie at a stable URL other
/// users can read from Nearby.
class LiveSessionMediaRepository {
  LiveSessionMediaRepository({FirebaseStorage? storage})
      : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseStorage _storage;

  /// Uploads [file] (the captured selfie) and returns its download URL.
  Future<String> uploadLiveSelfie({
    required String uid,
    required File file,
  }) async {
    final filename = 'live_selfie_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final ref = _storage.ref('users/$uid/live_selfies/$filename');
    final metadata = SettableMetadata(contentType: 'image/jpeg');
    final task = await ref.putFile(file, metadata);
    final url = await task.ref.getDownloadURL();
    debugPrint('[LiveSessionMediaRepository] uploaded $filename → $url');
    return url;
  }
}
