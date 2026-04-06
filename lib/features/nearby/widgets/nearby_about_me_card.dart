import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Structured "About Me" card displayed below the carousel for the
/// currently focused profile.
///
/// Mirrors the profile-screen About Me card style (cyan border, two-tone
/// heading) but scoped to the fields most useful in a discovery context:
/// age, hometown, occupation, height, and dating intention.
///
/// All fields except [age] are optional — the card hides rows for absent
/// values so it stays compact when profiles are sparse.
class NearbyAboutMeCard extends StatelessWidget {
  const NearbyAboutMeCard({
    super.key,
    required this.age,
    this.hometown,
    this.occupation,
    this.height,
    this.lookingFor,
  });

  final int age;
  final String? hometown;
  final String? occupation;
  final String? height;
  final String? lookingFor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppColors.brandCyan.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // "About Me" — two-tone heading matches profile screen
          Row(
            children: [
              Text(
                'About ',
                style: AppTextStyles.h3.copyWith(color: AppColors.brandPink),
              ),
              Text(
                'Me',
                style: AppTextStyles.h3.copyWith(color: AppColors.brandCyan),
              ),
            ],
          ),

          const SizedBox(height: 14),

          _InfoRow(
            icon: Icons.cake_outlined,
            label: '$age years old',
          ),

          if (hometown != null && hometown!.isNotEmpty) ...[
            const SizedBox(height: 9),
            _InfoRow(
              icon: Icons.location_on_outlined,
              label: hometown!,
            ),
          ],

          if (occupation != null && occupation!.isNotEmpty) ...[
            const SizedBox(height: 9),
            _InfoRow(
              icon: Icons.work_outline_rounded,
              label: occupation!,
            ),
          ],

          if (height != null && height!.isNotEmpty) ...[
            const SizedBox(height: 9),
            _InfoRow(
              icon: Icons.straighten_rounded,
              label: height!,
            ),
          ],

          if (lookingFor != null && lookingFor!.isNotEmpty) ...[
            const SizedBox(height: 9),
            _InfoRow(
              icon: Icons.favorite_border_rounded,
              label: lookingFor!,
              accentColor: AppColors.brandPink,
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _InfoRow
// ─────────────────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    this.accentColor,
  });

  final IconData icon;
  final String label;

  /// Icon tint — defaults to brandCyan if not provided.
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final color = accentColor ?? AppColors.brandCyan;
    return Row(
      children: [
        Icon(icon, size: 14, color: color.withValues(alpha: 0.75)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: AppTextStyles.bodyS
                .copyWith(color: AppColors.textPrimary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
