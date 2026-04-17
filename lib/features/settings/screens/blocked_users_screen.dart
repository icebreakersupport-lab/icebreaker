import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/gradient_scaffold.dart';

/// Blocked Users screen.
///
/// Streams the current user's blocked-users subcollection:
///   users/{uid}/blockedUsers/{blockedUid}
///   Fields: blockedAt (Timestamp), displayName (String), photoUrl (String)
///
/// Tapping "Unblock" deletes the document, removing the person from the list
/// immediately via the stream.
class BlockedUsersScreen extends StatelessWidget {
  const BlockedUsersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return GradientScaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text('Blocked Users', style: AppTextStyles.h3),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.textSecondary, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        top: false,
        child: uid == null
            ? const _EmptyState()
            : _BlockedList(uid: uid),
      ),
    );
  }
}

// ── Blocked list ──────────────────────────────────────────────────────────────

class _BlockedList extends StatelessWidget {
  const _BlockedList({required this.uid});
  final String uid;

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('blockedUsers')
        .orderBy('blockedAt', descending: true)
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.brandPink),
          );
        }

        if (snap.hasError) {
          return Center(
            child: Text(
              'Could not load blocked users.',
              style: AppTextStyles.bodyS.copyWith(color: AppColors.textMuted),
            ),
          );
        }

        final docs = snap.data?.docs ?? [];

        if (docs.isEmpty) return const _EmptyState();

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 48),
          itemCount: docs.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final doc = docs[i];
            final data = doc.data();
            final displayName =
                (data['displayName'] as String?) ?? 'Unknown user';
            final photoUrl = (data['photoUrl'] as String?) ?? '';
            final blockedAt =
                (data['blockedAt'] as Timestamp?)?.toDate();

            return _BlockedUserRow(
              blockedUid: doc.id,
              currentUid: uid,
              displayName: displayName,
              photoUrl: photoUrl,
              blockedAt: blockedAt,
            );
          },
        );
      },
    );
  }
}

// ── Blocked user row ──────────────────────────────────────────────────────────

class _BlockedUserRow extends StatefulWidget {
  const _BlockedUserRow({
    required this.blockedUid,
    required this.currentUid,
    required this.displayName,
    required this.photoUrl,
    required this.blockedAt,
  });

  final String blockedUid;
  final String currentUid;
  final String displayName;
  final String photoUrl;
  final DateTime? blockedAt;

  @override
  State<_BlockedUserRow> createState() => _BlockedUserRowState();
}

class _BlockedUserRowState extends State<_BlockedUserRow> {
  bool _unblocking = false;

  Future<void> _unblock() async {
    setState(() => _unblocking = true);
    try {
      final db = FirebaseFirestore.instance;
      final batch = db.batch();
      // Forward entry.
      batch.delete(
        db.collection('users').doc(widget.currentUid).collection('blockedUsers').doc(widget.blockedUid),
      );
      // Reverse entry.
      batch.delete(
        db.collection('blockedBy').doc(widget.blockedUid).collection('blockers').doc(widget.currentUid),
      );
      await batch.commit();
      // Stream update removes the row automatically — no setState needed.
    } catch (e) {
      debugPrint('[Unblock] failed: $e');
      if (mounted) {
        setState(() => _unblocking = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not unblock. Please try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Date label — "Blocked Apr 16" or similar.
    final dateLabel = widget.blockedAt != null
        ? 'Blocked ${_formatDate(widget.blockedAt!)}'
        : 'Blocked recently';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.bgElevated,
            ),
            clipBehavior: Clip.antiAlias,
            child: widget.photoUrl.isNotEmpty
                ? Image.network(
                    widget.photoUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const _AvatarPlaceholder(),
                  )
                : const _AvatarPlaceholder(),
          ),

          const SizedBox(width: 14),

          // Name + date
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.displayName,
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  dateLabel,
                  style:
                      AppTextStyles.caption.copyWith(color: AppColors.textMuted),
                ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          // Unblock button
          _unblocking
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.brandCyan,
                  ),
                )
              : GestureDetector(
                  onTap: _unblock,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: AppColors.brandCyan.withValues(alpha: 0.50)),
                      borderRadius: BorderRadius.circular(20),
                      color: AppColors.brandCyan.withValues(alpha: 0.06),
                    ),
                    child: Text(
                      'Unblock',
                      style: AppTextStyles.buttonS.copyWith(
                        color: AppColors.brandCyan,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}';
  }
}

// ── Avatar placeholder ────────────────────────────────────────────────────────

class _AvatarPlaceholder extends StatelessWidget {
  const _AvatarPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Icon(Icons.person_rounded,
        size: 22, color: AppColors.textMuted);
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.bgSurface,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.divider),
              ),
              child: const Icon(Icons.shield_outlined,
                  color: AppColors.textMuted, size: 32),
            ),
            const SizedBox(height: 20),
            Text('No blocked users',
                style: AppTextStyles.h3, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'People you block will appear here.',
              style:
                  AppTextStyles.bodyS.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
