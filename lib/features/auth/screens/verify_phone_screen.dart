// TODO(step-3): Build full phone verification screen.
//
// This placeholder satisfies routing so sign-up and sign-in flows compile.
// Full implementation: phone number input → verifyPhoneNumber() →
// 6-digit OTP entry → user.linkWithCredential() → /onboarding or /home.
//
// For now: "Continue to app" skips phone verification so the auth foundation
// can be tested end-to-end.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/icebreaker_logo.dart';

class VerifyPhoneScreen extends StatelessWidget {
  const VerifyPhoneScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const IcebreakerLogo(size: 56, showGlow: false),
                const SizedBox(height: 28),
                Text(
                  'Verify your phone',
                  style: AppTextStyles.h2,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Phone verification coming soon.\nTap below to continue into the app.',
                  style: AppTextStyles.bodyS,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),
                GestureDetector(
                  onTap: () => context.go(AppRoutes.home),
                  child: Container(
                    height: 56,
                    decoration: BoxDecoration(
                      gradient: AppColors.brandGradient,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.brandPink.withValues(alpha: 0.32),
                          blurRadius: 18,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Text('Continue to app', style: AppTextStyles.buttonL),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
