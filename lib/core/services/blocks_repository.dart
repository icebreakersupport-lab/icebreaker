import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

/// Streams the union of users I've blocked and users who have blocked me,
/// so Nearby can filter both directions out of its discovery feed in a
/// single client-side check.
///
/// Two-collection model:
///   users/{myUid}/blockedUsers/{theirUid} — I blocked them.
///   users/{myUid}/blockedBy/{theirUid}    — they blocked me.
///
/// Both subcollections are written by the Cloud Functions on a block event
/// (`onUserBlocked` writes both sides of the mirror so neither user can
/// continue seeing the other regardless of which client initiated the
/// block).  This repository just provides a coalesced stream — it doesn't
/// write, doesn't mediate the block itself.
class BlocksRepository {
  BlocksRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// Emits a `Set<String>` containing every uid that should be hidden from
  /// [myUid]'s Nearby feed at any given moment.  Updates whenever either
  /// the blockedUsers or blockedBy subcollection changes.
  ///
  /// Empties the set if [myUid] is empty.
  Stream<Set<String>> blockedUidsStream(String myUid) {
    if (myUid.isEmpty) return Stream.value(<String>{});

    final blockedRef =
        _db.collection('users').doc(myUid).collection('blockedUsers');
    final blockedByRef =
        _db.collection('users').doc(myUid).collection('blockedBy');

    Set<String> blocked = <String>{};
    Set<String> blockedBy = <String>{};

    late final StreamController<Set<String>> controller;
    StreamSubscription? blockedSub;
    StreamSubscription? blockedBySub;

    void emit() {
      controller.add(<String>{...blocked, ...blockedBy});
    }

    controller = StreamController<Set<String>>(
      onListen: () {
        blockedSub = blockedRef.snapshots().listen((snap) {
          blocked = snap.docs.map((d) => d.id).toSet();
          emit();
        });
        blockedBySub = blockedByRef.snapshots().listen((snap) {
          blockedBy = snap.docs.map((d) => d.id).toSet();
          emit();
        });
      },
      onCancel: () async {
        await blockedSub?.cancel();
        await blockedBySub?.cancel();
      },
    );

    return controller.stream;
  }

  /// Records a block by [blockerId] against [blockedId].  Writes both indices
  /// of the mirror in a single batch:
  ///   users/{blockerId}/blockedUsers/{blockedId}   — "I blocked them"
  ///   users/{blockedId}/blockedBy/{blockerId}      — "they blocked me"
  ///
  /// The Cloud Function `onUserBlocked` triggers off the first write and
  /// archives any shared conversations; we write the second index from the
  /// client so reverse-lookups (Nearby filter on `blockedBy`) work
  /// immediately, before the CF has had a chance to run.
  Future<void> block({
    required String blockerId,
    required String blockedId,
    required String source,
    String? blockedDisplayName,
    String? blockedPhotoUrl,
    String? conversationId,
  }) async {
    final batch = _db.batch();
    final blockedAt = FieldValue.serverTimestamp();

    final forwardRef = _db
        .collection('users')
        .doc(blockerId)
        .collection('blockedUsers')
        .doc(blockedId);
    final reverseRef = _db
        .collection('users')
        .doc(blockedId)
        .collection('blockedBy')
        .doc(blockerId);

    final forwardPayload = <String, dynamic>{
      'blockedAt': blockedAt,
      'source': source,
      if (blockedDisplayName != null) 'displayName': blockedDisplayName,
      if (blockedPhotoUrl != null) 'photoUrl': blockedPhotoUrl,
      // Captured when the block originates from a chat thread so the
      // moderation/CF side can locate the offending conversation later.
      if (conversationId != null) 'conversationId': conversationId,
    };
    // ignore_for_file: use_null_aware_elements
    final reversePayload = <String, dynamic>{
      'blockedAt': blockedAt,
      'source': source,
      if (conversationId != null) 'conversationId': conversationId,
    };

    batch.set(forwardRef, forwardPayload, SetOptions(merge: true));
    batch.set(reverseRef, reversePayload, SetOptions(merge: true));
    await batch.commit();
  }
}
