import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/gradient_scaffold.dart';

/// Temporary development-only screen — lists every implemented screen for
/// quick visual inspection during the UI polish pass.  Currently stubbed out
/// while the underlying meetup-flow + onboarding screens have constructor
/// API changes in flight; the previous preview wiring referenced parameters
/// (matchColor, otherFirstName, findSecondsRemaining, etc.) that no longer
/// exist.  Rebuild this surface against the new APIs when the design polish
/// pass resumes.
class DesignPreviewScreen extends StatelessWidget {
  const DesignPreviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      showTopGlow: true,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.construction_outlined,
                  color: AppColors.textMuted,
                  size: 48,
                ),
                const SizedBox(height: 16),
                Text(
                  'Design preview disabled',
                  style: AppTextStyles.h2,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Re-wire this surface after the meetup-flow constructor '
                  'refactor lands.',
                  style: AppTextStyles.bodyS.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
