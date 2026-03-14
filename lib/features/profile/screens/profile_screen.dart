import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/state/live_session.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/models/profile_completion.dart';
import '../../../shared/widgets/gradient_scaffold.dart';
import 'edit_profile_screen.dart';
import 'gallery_screen.dart';
import 'profile_checklist_screen.dart';

/// Profile tab — redesigned to match reference layout.
///
/// Layout (top → bottom):
///   AppBar (Profile title + settings icon)
///   Hero circle — live selfie when live, placeholder when offline
///   "XX% COMPLETE" pill (dynamic, from ProfileCompletionScore)
///   Name (pink) + age (cyan) in large type
///   Location line
///   3 action buttons — Edit Profile / My Gallery / Profile Checklist
///   About Me card — bio + bullet details
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  // TODO: replace with real user data from Firestore via Riverpod
  static const String _firstName = 'You';
  static const int _age = 24;
  static const String _location = 'San Francisco, CA';
  static const String _occupation = 'Product Designer';
  static const String _bio =
      "I'm an adventurous soul who loves exploring new places, "
      "trying new foods, and meeting interesting people. "
      "Let's embark on an exciting journey together!";

  @override
  Widget build(BuildContext context) {
    final session = LiveSessionScope.of(context);
    final score = ProfileCompletionScore.demo(
      hasLiveSelfie: session.selfieFilePath != null,
    );

    return GradientScaffold(
      appBar: AppBar(
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
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 28),

              // ── Hero profile circle ─────────────────────────────────────
              _HeroAvatar(session: session),

              const SizedBox(height: 18),

              // ── Completeness pill ───────────────────────────────────────
              _CompletenessChip(percent: score.percentage),

              const SizedBox(height: 22),

              // ── Name + age ──────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '$_firstName ',
                    style: AppTextStyles.h1.copyWith(
                      color: AppColors.brandPink,
                      fontSize: 38,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  Text(
                    '($_age)',
                    style: AppTextStyles.h2.copyWith(
                      color: AppColors.brandCyan,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // ── Location ────────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.location_on_rounded,
                      color: AppColors.brandPink, size: 15),
                  const SizedBox(width: 4),
                  Text(
                    _location,
                    style: AppTextStyles.bodyS
                        .copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),

              const SizedBox(height: 26),

              // ── Action buttons ──────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: _ActionTile(
                      icon: Icons.edit_rounded,
                      label: 'Edit\nProfile',
                      color: AppColors.brandPink,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const EditProfileScreen(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ActionTile(
                      icon: Icons.photo_library_outlined,
                      label: 'My\nGallery',
                      color: AppColors.brandCyan,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const GalleryScreen(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ActionTile(
                      icon: Icons.checklist_rounded,
                      label: 'Profile\nChecklist',
                      color: AppColors.brandPurple,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              ProfileChecklistScreen(score: score),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // ── About Me card ───────────────────────────────────────────
              _AboutCard(
                bio: _bio,
                age: _age,
                location: _location,
                occupation: _occupation,
              ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Hero avatar ───────────────────────────────────────────────────────────────

/// Large circular profile photo with pink→purple gradient ring.
///
/// When the user is live and has a selfie path: shows the verification photo.
/// When offline (or no selfie yet): shows a placeholder with copy
/// "Profile pic will appear when you go live".
///
/// A "LIVE" pill badge overlays the bottom of the circle when live.
class _HeroAvatar extends StatelessWidget {
  const _HeroAvatar({required this.session});
  final LiveSession session;

  static const double _size = 200;
  static const double _border = 3.0;

  @override
  Widget build(BuildContext context) {
    final path = session.selfieFilePath;
    final isLive = session.isLive;

    return Stack(
      alignment: Alignment.bottomCenter,
      clipBehavior: Clip.none,
      children: [
        // Ambient outer glow
        Positioned(
          left: -24,
          right: -24,
          top: -24,
          bottom: -24,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppColors.brandPink.withValues(alpha: 0.20),
                  AppColors.brandPurple.withValues(alpha: 0.12),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
            ),
          ),
        ),

        // Gradient ring + clipped photo
        Container(
          width: _size,
          height: _size,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.brandPink, AppColors.brandPurple],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(_border),
            child: ClipOval(
              child: path != null
                  ? Image.file(File(path), fit: BoxFit.cover)
                  : _AvatarPlaceholder(),
            ),
          ),
        ),

        // LIVE badge — overlays bottom edge when live
        if (isLive)
          Positioned(
            bottom: -10,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                gradient: AppColors.brandGradient,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.brandPink.withValues(alpha: 0.40),
                    blurRadius: 12,
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'LIVE',
                    style: AppTextStyles.caption.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _AvatarPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bgElevated,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.person_rounded,
            size: 60,
            color: AppColors.textMuted.withValues(alpha: 0.45),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Profile pic will appear\nwhen you go live',
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textMuted,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Completeness chip ─────────────────────────────────────────────────────────

class _CompletenessChip extends StatelessWidget {
  const _CompletenessChip({required this.percent});
  final int percent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider),
      ),
      child: Text(
        '$percent% COMPLETE',
        style: AppTextStyles.caption.copyWith(
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.6,
        ),
      ),
    );
  }
}

// ── Action tile ───────────────────────────────────────────────────────────────

/// Tall rounded card with centered icon + two-line label.
/// Border and icon tinted with the tile's accent color.
class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.40)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 8),
            Text(
              label,
              style: AppTextStyles.buttonS.copyWith(
                color: color,
                height: 1.3,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── About Me card ─────────────────────────────────────────────────────────────

/// Bio + key profile details card.
/// Cyan border, two-tone "About Me" heading (pink + cyan).
class _AboutCard extends StatelessWidget {
  const _AboutCard({
    required this.bio,
    required this.age,
    required this.location,
    required this.occupation,
  });

  final String bio;
  final int age;
  final String location;
  final String occupation;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: AppColors.brandCyan.withValues(alpha: 0.30),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // "About Me" — two-tone heading
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

          // Bio
          Text(
            bio,
            style: AppTextStyles.bodyS.copyWith(
              color: AppColors.textSecondary,
              height: 1.65,
            ),
          ),

          const SizedBox(height: 18),

          // Bullet details
          _BulletRow(label: '$age years old'),
          const SizedBox(height: 7),
          _BulletRow(label: location),
          const SizedBox(height: 7),
          _BulletRow(label: occupation),
        ],
      ),
    );
  }
}

class _BulletRow extends StatelessWidget {
  const _BulletRow({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
            color: AppColors.brandCyan,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: AppTextStyles.bodyS.copyWith(color: AppColors.textPrimary),
        ),
      ],
    );
  }
}
