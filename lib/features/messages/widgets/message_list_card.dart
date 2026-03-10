import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// A standard chat-list row for the "Chats" and "History" sections.
///
/// Chats section: shows last message preview + lastMessageAt timestamp.
/// History section: uses a muted/dimmed style to indicate concluded state.
class MessageListCard extends StatelessWidget {
  const MessageListCard({
    super.key,
    required this.otherFirstName,
    required this.otherPhotoUrl,
    required this.previewText,
    required this.timestamp,
    required this.onTap,
    this.isDimmed = false,
    this.hasUnread = false,
    this.statusIcon,
  });

  final String otherFirstName;
  final String otherPhotoUrl;
  final String previewText;
  final String timestamp;
  final VoidCallback onTap;

  /// True for History cards (ended / declined / expired).
  final bool isDimmed;

  /// Unread indicator dot.
  final bool hasUnread;

  /// Optional icon shown to the right (e.g. lock for ended, check for unlocked).
  final IconData? statusIcon;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            // Avatar
            Stack(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: AppColors.bgElevated,
                  backgroundImage: otherPhotoUrl.isNotEmpty
                      ? NetworkImage(otherPhotoUrl)
                      : null,
                  child: otherPhotoUrl.isEmpty
                      ? Text(
                          otherFirstName.isNotEmpty
                              ? otherFirstName[0].toUpperCase()
                              : '?',
                          style: AppTextStyles.h3.copyWith(
                              color: AppColors.textSecondary),
                        )
                      : null,
                ),
                if (hasUnread)
                  Positioned(
                    right: 2,
                    bottom: 2,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        gradient: AppColors.brandGradient,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: AppColors.bgBase, width: 2),
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(width: 14),

            // Name + preview
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    otherFirstName,
                    style: AppTextStyles.body.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isDimmed
                          ? AppColors.textSecondary
                          : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    previewText,
                    style: AppTextStyles.bodyS.copyWith(
                      color: isDimmed
                          ? AppColors.textMuted
                          : hasUnread
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // Timestamp + optional icon
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  timestamp,
                  style: AppTextStyles.caption.copyWith(
                    color:
                        isDimmed ? AppColors.textMuted : AppColors.textSecondary,
                  ),
                ),
                if (statusIcon != null) ...[
                  const SizedBox(height: 4),
                  Icon(
                    statusIcon,
                    size: 14,
                    color: isDimmed
                        ? AppColors.textMuted
                        : AppColors.textSecondary,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
