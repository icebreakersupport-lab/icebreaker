import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/state/live_session.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import 'live_verification_screen.dart';

/// Full-screen expanded view of the user's current live selfie.
///
/// Reads [selfieFilePath] directly from [LiveSessionScope] so it rebuilds
/// automatically after the user completes a redo capture.
///
/// Actions:
///   • Close (×) — pops back to Home
///   • Redo Picture — pushes [LiveVerificationScreen] with [isRedo: true];
///     on return the updated selfie is shown immediately.
class SelfiePreviewScreen extends StatelessWidget {
  const SelfiePreviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = LiveSessionScope.of(context);
    final path = session.selfieFilePath;

    return Scaffold(
      backgroundColor: const Color(0xFF05000E),
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  // Close
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        color: AppColors.textSecondary,
                        size: 18,
                      ),
                    ),
                  ),
                  // Title
                  Expanded(
                    child: Text(
                      'Live Photo',
                      style: AppTextStyles.h3,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  // Balance spacer
                  const SizedBox(width: 40),
                ],
              ),
            ),

            const Spacer(),

            // ── Selfie circle ─────────────────────────────────────────────
            if (path != null)
              Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.brandPink,
                    width: 2.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.brandPink.withValues(alpha: 0.42),
                      blurRadius: 44,
                      spreadRadius: 4,
                    ),
                    BoxShadow(
                      color: AppColors.brandPurple.withValues(alpha: 0.28),
                      blurRadius: 80,
                      spreadRadius: 8,
                    ),
                  ],
                ),
                child: ClipOval(
                  child: Image.file(File(path), fit: BoxFit.cover),
                ),
              ),

            const SizedBox(height: 20),

            // ── Live badge ────────────────────────────────────────────────
            if (session.isLive)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                decoration: BoxDecoration(
                  gradient: AppColors.brandGradient,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      "YOU'RE LIVE",
                      style: AppTextStyles.caption.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 10),

            Text(
              'Your live selfie',
              style: AppTextStyles.bodyS.copyWith(
                color: AppColors.textMuted,
              ),
            ),

            const Spacer(),

            // ── Redo button ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 32),
              child: GestureDetector(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          const LiveVerificationScreen(isRedo: true),
                    ),
                  );
                },
                child: Container(
                  width: double.infinity,
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: AppColors.brandPink.withValues(alpha: 0.55),
                    ),
                    color: AppColors.brandPink.withValues(alpha: 0.08),
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.camera_alt_rounded,
                        color: AppColors.brandPink,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Redo Picture',
                        style: AppTextStyles.button.copyWith(
                          color: AppColors.brandPink,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
