import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/gradient_scaffold.dart';
import '../../../shared/widgets/pill_button.dart';

/// Profile tab — the user's own profile view.
///
/// Shows:
///   - Large selfie / profile photo
///   - Name, age, bio
///   - Photo grid (from public_profiles.photos)
///   - Edit, Settings, Subscription CTAs
///
/// Full profile editing happens on EditProfileScreen (pushed from here).
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // TODO: replace with real user data from Firestore via Riverpod
    const String firstName = 'You';
    const int age = 24;
    const String bio = 'Add a bio to let people know who you are.';
    const String photoUrl = '';

    return GradientScaffold(
      appBar: _buildAppBar(context),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),

              // ── Hero photo ────────────────────────────────────────────────
              Center(
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 64,
                      backgroundColor: AppColors.bgElevated,
                      backgroundImage: photoUrl.isNotEmpty
                          ? NetworkImage(photoUrl)
                          : null,
                      child: photoUrl.isEmpty
                          ? const Icon(
                              Icons.person_rounded,
                              size: 72,
                              color: AppColors.textMuted,
                            )
                          : null,
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: GestureDetector(
                        onTap: () {
                          // TODO: open photo picker
                        },
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: const BoxDecoration(
                            gradient: AppColors.brandGradient,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.add_photo_alternate_outlined,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ── Name + age ────────────────────────────────────────────────
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(firstName, style: AppTextStyles.h2),
                    const SizedBox(width: 8),
                    Text('$age',
                        style: AppTextStyles.h3
                            .copyWith(color: AppColors.textSecondary)),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // ── Bio ───────────────────────────────────────────────────────
              Center(
                child: Text(
                  bio,
                  style: AppTextStyles.bodyS,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
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
