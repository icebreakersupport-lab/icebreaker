import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/countdown_timer_widget.dart';

/// A time-sensitive card for the "Active Now" section of the Messages tab.
///
/// Used for:
///   - Icebreakers with status 'sent' (incoming or outgoing)
///   - Conversations with status 'finding' | 'in_conversation' | 'post_meet'
///
/// Shows a countdown timer, participant avatars, and a status label.
class ActiveNowCard extends StatelessWidget {
  const ActiveNowCard({
    super.key,
    required this.otherFirstName,
    required this.otherPhotoUrl,
    required this.statusLabel,
    required this.secondsRemaining,
    required this.onTap,
    this.matchColor,
    this.showTimer = true,
  });

  final String otherFirstName;
  final String otherPhotoUrl;
  final String statusLabel;
  final int secondsRemaining;
  final VoidCallback onTap;

  /// Match colour used as left accent bar for post-acceptance states.
  final Color? matchColor;

  final bool showTimer;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider, width: 1),
        ),
        child: Row(
          children: [
            // Match colour accent bar
            Container(
              width: 4,
              height: 72,
              decoration: BoxDecoration(
                gradient: matchColor != null
                    ? LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          matchColor!,
                          matchColor!.withValues(alpha: 0.5),
                        ],
                      )
                    : AppColors.brandGradient,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                ),
              ),
            ),

            const SizedBox(width: 14),

            // Avatar
            _Avatar(url: otherPhotoUrl, initials: otherFirstName[0]),

            const SizedBox(width: 14),

            // Text content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(otherFirstName, style: AppTextStyles.h3),
                  const SizedBox(height: 2),
                  Text(statusLabel, style: AppTextStyles.bodyS),
                ],
              ),
            ),

            // Countdown
            if (showTimer) ...[
              CountdownTimerWidget(
                initialSeconds: secondsRemaining,
                style: AppTextStyles.button.copyWith(
                  color: AppColors.brandCyan,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
                warningThresholdSeconds: 30,
              ),
              const SizedBox(width: 16),
            ],
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, required this.initials});
  final String url;
  final String initials;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 24,
      backgroundColor: AppColors.bgElevated,
      backgroundImage: url.isNotEmpty ? NetworkImage(url) : null,
      child: url.isEmpty
          ? Text(
              initials.toUpperCase(),
              style: AppTextStyles.h3.copyWith(color: AppColors.textSecondary),
            )
          : null,
    );
  }
}
