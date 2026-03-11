import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/state/live_session.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/gradient_scaffold.dart';
import '../../../shared/widgets/pill_button.dart';
import '../../home/screens/live_verification_screen.dart';

/// Profile tab — the user's own profile view.
///
/// Shows:
///   - Current live verification selfie (large, neon glow) when available,
///     or a placeholder avatar when no selfie has been taken yet.
///   - "Redo Live Selfie" button that re-enters the verification capture flow.
///   - Name, bio, credits summary, subscription banner.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = LiveSessionScope.of(context);

    // TODO: replace with real user data from Firestore via Riverpod
    const String firstName = 'You';
    const int age = 24;
    const String bio = 'Add a bio to let people know who you are.';

    return GradientScaffold(
      appBar: _buildAppBar(context),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 28),

              // ── Hero selfie ───────────────────────────────────────────────
              _LiveSelfieHero(session: session),

              const SizedBox(height: 20),

              // ── Redo Live Selfie ──────────────────────────────────────────
              GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        const LiveVerificationScreen(isRedo: true),
                  ),
                ),
                child: Container(
                  width: double.infinity,
                  height: 52,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(26),
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
                        'Redo Live Selfie',
                        style: AppTextStyles.button.copyWith(
                          color: AppColors.brandPink,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // ── Name + age ────────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(firstName, style: AppTextStyles.h2),
                  const SizedBox(width: 8),
                  Text(
                    '$age',
                    style: AppTextStyles.h3
                        .copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // ── Bio ───────────────────────────────────────────────────────
              Text(
                bio,
                style: AppTextStyles.bodyS,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),

              const SizedBox(height: 28),

              // ── Edit Profile CTA ──────────────────────────────────────────
              PillButton.outlined(
                label: 'Edit Profile',
                onTap: () {
                  // TODO: navigate to EditProfileScreen
                },
                width: double.infinity,
                height: 50,
              ),

              const SizedBox(height: 16),

              // ── Credits summary ───────────────────────────────────────────
              _CreditsSummaryCard(),

              const SizedBox(height: 16),

              // ── Subscription banner ───────────────────────────────────────
              _SubscriptionBanner(),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      title: Text('Profile', style: AppTextStyles.h3),
      actions: [
        IconButton(
          icon: const Icon(Icons.settings_outlined,
              color: AppColors.textSecondary),
          onPressed: () {
            // TODO: open Settings
          },
        ),
      ],
    );
  }
}

// ── Live selfie hero ──────────────────────────────────────────────────────────

/// Large circular profile photo, 190px radius (2.5× the old 76px placeholder).
/// Shows the current live verification selfie when available; falls back to
/// the branded placeholder icon. Neon pink border + glow when live.
class _LiveSelfieHero extends StatelessWidget {
  const _LiveSelfieHero({required this.session});
  final LiveSession session;

  @override
  Widget build(BuildContext context) {
    final path = session.selfieFilePath;
    const radius = 95.0; // 190px diameter — 2.5× the old 76px radius

    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: AppColors.brandPink,
          width: 2.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandPink.withValues(alpha: 0.42),
            blurRadius: 48,
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
        child: path != null
            ? Image.file(File(path), fit: BoxFit.cover)
            : Container(
                color: AppColors.bgElevated,
                child: const Center(
                  child: Icon(
                    Icons.person_rounded,
                    size: 80,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
      ),
    );
  }
}

// ── Credits summary card ──────────────────────────────────────────────────────

class _CreditsSummaryCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          _CreditItem(
            icon: Icons.favorite_rounded,
            label: 'Lives',
            value: '1',
            color: AppColors.brandPink,
          ),
          const SizedBox(width: 1),
          const VerticalDivider(
              color: AppColors.divider, indent: 4, endIndent: 4),
          const SizedBox(width: 1),
          _CreditItem(
            icon: Icons.bolt_rounded,
            label: 'Icebreakers',
            value: '3',
            color: AppColors.brandCyan,
          ),
        ],
      ),
    );
  }
}

class _CreditItem extends StatelessWidget {
  const _CreditItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 6),
          Text(value,
              style: AppTextStyles.h2.copyWith(color: AppColors.textPrimary)),
          const SizedBox(height: 2),
          Text(label, style: AppTextStyles.caption),
        ],
      ),
    );
  }
}

// ── Subscription banner ───────────────────────────────────────────────────────

class _SubscriptionBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFFFD700).withValues(alpha: 0.15),
            const Color(0xFFFF8C00).withValues(alpha: 0.10),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFFFD700).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.workspace_premium_rounded,
              color: Color(0xFFFFD700), size: 32),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Upgrade to Gold',
                  style: AppTextStyles.button.copyWith(
                    color: const Color(0xFFFFD700),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Unlimited Lives · Top of carousel · \$9.99/mo',
                  style: AppTextStyles.caption,
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded,
              color: AppColors.textMuted),
        ],
      ),
    );
  }
}
