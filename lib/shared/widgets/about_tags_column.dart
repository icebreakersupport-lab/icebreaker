import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

/// Right-hand column on the profile card that lists Interests + Hobbies as
/// chip rows.  The parent profile body collapses the two-column layout when
/// [hasAnyTags] is false, so callers read this getter before deciding whether
/// to render a row layout or just the facts column.
class AboutTagsColumn extends StatelessWidget {
  const AboutTagsColumn({
    super.key,
    required this.interests,
    required this.hobbies,
  });

  final List<String> interests;
  final List<String> hobbies;

  /// True if either list has at least one tag.  Cheap to call repeatedly —
  /// the build method itself is gated on this.
  bool get hasAnyTags => interests.isNotEmpty || hobbies.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (!hasAnyTags) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (interests.isNotEmpty)
          _TagSection(
            icon: Icons.favorite_outline_rounded,
            label: 'Interests',
            tags: interests,
          ),
        if (interests.isNotEmpty && hobbies.isNotEmpty)
          const SizedBox(height: 12),
        if (hobbies.isNotEmpty)
          _TagSection(
            icon: Icons.sports_esports_outlined,
            label: 'Hobbies',
            tags: hobbies,
          ),
      ],
    );
  }
}

class _TagSection extends StatelessWidget {
  const _TagSection({
    required this.icon,
    required this.label,
    required this.tags,
  });

  final IconData icon;
  final String label;
  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 12, color: AppColors.textSecondary),
            const SizedBox(width: 4),
            Text(
              label,
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textSecondary,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final tag in tags) _TagChip(label: tag),
          ],
        ),
      ],
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.divider,
          width: 1,
        ),
      ),
      child: Text(
        label,
        style: AppTextStyles.caption.copyWith(
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}
