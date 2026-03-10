import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Section header for the Messages tab (Active Now / Chats / History).
/// Rendered as an allcaps overline with a subtle divider.
class MessagesSectionHeader extends StatelessWidget {
  const MessagesSectionHeader({
    super.key,
    required this.title,
    this.badge,
  });

  final String title;

  /// Optional count badge (e.g. "2" for 2 active items).
  final int? badge;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Row(
        children: [
          Text(title.toUpperCase(), style: AppTextStyles.overline),
          if (badge != null && badge! > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                gradient: AppColors.brandGradient,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$badge',
                style: AppTextStyles.caption.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
