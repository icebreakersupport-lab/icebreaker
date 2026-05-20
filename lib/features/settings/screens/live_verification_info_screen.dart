import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Informational page reached from Settings → Live Verification.
///
/// Previously this row push'd `AppRoutes.liveVerify`, which let a user enter
/// the live-verification flow OUTSIDE of an active GO LIVE session — a
/// loophole that could be used to refresh the verification selfie without
/// starting a new live session.  Now the row routes here instead: read-only
/// content describing what live verification is, when it runs, and where the
/// resulting badge shows up.  The only legitimate entry point to the actual
/// live-verification flow is the GO LIVE button on Home.
class LiveVerificationInfoScreen extends StatelessWidget {
  const LiveVerificationInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        backgroundColor: AppColors.bgBase,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          color: AppColors.textPrimary,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Live Verification',
          style: AppTextStyles.h3.copyWith(color: AppColors.textPrimary),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
          children: [
            // ── Hero badge ────────────────────────────────────────────────
            Center(
              child: Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.brandCyan.withValues(alpha: 0.10),
                  border: Border.all(
                    color: AppColors.brandCyan.withValues(alpha: 0.55),
                    width: 1.4,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.brandCyan.withValues(alpha: 0.20),
                      blurRadius: 24,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.verified_rounded,
                  color: AppColors.brandCyan,
                  size: 44,
                ),
              ),
            ),
            const SizedBox(height: 18),

            Text(
              'What it is',
              style: AppTextStyles.h2.copyWith(color: AppColors.textPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),

            Text(
              'A quick selfie taken right before you Go Live. It confirms the '
              'person showing up on Nearby is the same person on the profile '
              '— not someone using stolen photos.',
              style: AppTextStyles.bodyS.copyWith(
                color: AppColors.textSecondary,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 32),

            // ── How it works ─────────────────────────────────────────────
            _SectionLabel(text: 'How it works'),
            const SizedBox(height: 12),
            const _InfoStep(
              number: '1',
              title: 'Tap GO LIVE on Home',
              body:
                  'When you start a new live session, the camera opens for a quick selfie.',
            ),
            const _InfoStep(
              number: '2',
              title: 'Snap a real-time selfie',
              body:
                  'Photo is captured live — it can\'t be uploaded from your gallery.',
            ),
            const _InfoStep(
              number: '3',
              title: 'Your verified badge appears',
              body:
                  'You\'re live and verified for the next 60 minutes. The selfie stays attached to your live session.',
            ),

            const SizedBox(height: 28),

            // ── Where you'll see it ──────────────────────────────────────
            _SectionLabel(text: "Where it shows up"),
            const SizedBox(height: 12),
            const _InfoBullet(
              icon: Icons.people_alt_outlined,
              title: 'Nearby carousel',
              body:
                  'Verified live users get a small cyan ✓ badge on their card.',
            ),
            const _InfoBullet(
              icon: Icons.person_outline_rounded,
              title: 'Your profile',
              body:
                  'Profile shows a Verified status while a live session is active.',
            ),
            const _InfoBullet(
              icon: Icons.task_alt_rounded,
              title: 'Profile checklist',
              body:
                  'Completing live verification fills the "Live Selfie Verified" row in your Profile Checklist.',
            ),

            const SizedBox(height: 28),

            // ── Footer note ──────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.bgSurface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.divider),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.lock_outline_rounded,
                    color: AppColors.brandCyan,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "Your selfie is only visible to people in your active "
                      "live session — it expires automatically when the "
                      "session ends.",
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SectionLabel — cyan small-caps section header
// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: AppTextStyles.caption.copyWith(
        color: AppColors.brandCyan,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _InfoStep — numbered explanation step (used in "How it works")
// ─────────────────────────────────────────────────────────────────────────────

class _InfoStep extends StatelessWidget {
  const _InfoStep({
    required this.number,
    required this.title,
    required this.body,
  });
  final String number;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppColors.brandGradient,
            ),
            alignment: Alignment.center,
            child: Text(
              number,
              style: AppTextStyles.caption.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.bodyS.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _InfoBullet — icon + title + body (used in "Where it shows up")
// ─────────────────────────────────────────────────────────────────────────────

class _InfoBullet extends StatelessWidget {
  const _InfoBullet({
    required this.icon,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.brandCyan.withValues(alpha: 0.10),
              border: Border.all(
                color: AppColors.brandCyan.withValues(alpha: 0.35),
              ),
            ),
            alignment: Alignment.center,
            child: Icon(
              icon,
              color: AppColors.brandCyan,
              size: 18,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.bodyS.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
