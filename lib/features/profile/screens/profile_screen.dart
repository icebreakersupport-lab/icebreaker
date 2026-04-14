import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/state/demo_profile.dart';
import '../../../core/state/live_session.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/models/profile_completion.dart';
import '../../../shared/widgets/gradient_scaffold.dart';

/// Profile tab — shows live demo profile state persisted via [DemoProfileScope].
///
/// Layout (top → bottom):
///   AppBar (Profile title + settings icon)
///   Hero circle — main gallery photo → live selfie → placeholder
///   "XX% COMPLETE" pill
///   Name (pink) + age (cyan)
///   Location line
///   3 action buttons — Edit Profile / My Gallery / Profile Checklist
///   About Me card — bio + bullet details
///   Photos & Media strip — saved photos + video indicator

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = LiveSessionScope.of(context);
    final profile = DemoProfileScope.of(context);
    final score = ProfileCompletionScore.fromProfile(
      profile,
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
            onPressed: () => context.push(AppRoutes.settings),
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
              // Priority: main gallery photo → live selfie → placeholder
              _HeroAvatar(session: session, mainPhoto: profile.mainPhoto),

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
                    '${profile.firstName} ',
                    style: AppTextStyles.h1.copyWith(
                      color: AppColors.brandPink,
                      fontSize: 38,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  Text(
                    '(${profile.age})',
                    style: AppTextStyles.h2.copyWith(
                      color: AppColors.brandCyan,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // ── Hometown ────────────────────────────────────────────────
              if (profile.hometownDisplay.isNotEmpty)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.location_on_rounded,
                        color: AppColors.brandPink, size: 15),
                    const SizedBox(width: 4),
                    Text(
                      profile.hometownDisplay,
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
                      onTap: () => context.push(AppRoutes.editProfile),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ActionTile(
                      icon: Icons.photo_library_outlined,
                      label: 'My\nGallery',
                      color: AppColors.brandCyan,
                      onTap: () => context.push(AppRoutes.gallery),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ActionTile(
                      icon: Icons.checklist_rounded,
                      label: 'Profile\nChecklist',
                      color: AppColors.brandPurple,
                      onTap: () => context.push(AppRoutes.profileChecklist),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // ── About Me card ───────────────────────────────────────────
              _AboutCard(
                bio: profile.bio,
                age: profile.age,
                hometown: profile.hometownDisplay,
                occupation: profile.occupation,
                height: profile.height,
                lookingFor: profile.lookingFor,
              ),

              const SizedBox(height: 20),

              // ── Photos & Media ──────────────────────────────────────────
              _MediaSection(
                photos: profile.photos,
                video: profile.video,
                onManage: () => context.push(AppRoutes.gallery),
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
/// Priority for the photo: main gallery photo → live selfie → placeholder.
/// "Profile pic will appear when you go live" shown only when neither is set.
///
/// A "LIVE" pill badge overlays the bottom of the circle when live.
class _HeroAvatar extends StatelessWidget {
  const _HeroAvatar({required this.session, this.mainPhoto});
  final LiveSession session;
  final XFile? mainPhoto;

  static const double _size = 200;
  static const double _border = 3.0;

  @override
  Widget build(BuildContext context) {
    final isLive = session.isLive;
    final selfiePath = session.selfieFilePath;
    final galleryPath = mainPhoto?.path;
    // When live: always show the verification selfie (trust signal).
    // When not live: prefer the gallery main photo, fall back to selfie.

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
              child: _resolveImage(isLive, selfiePath, galleryPath),
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

  /// Chooses the correct image source for the hero circle.
  ///
  /// Live session → verification selfie always (trust/authenticity signal).
  /// Not live     → gallery main photo if present, then selfie, then placeholder.
  Widget _resolveImage(bool isLive, String? selfiePath, String? galleryPath) {
    if (isLive && selfiePath != null) {
      return Image.file(File(selfiePath), fit: BoxFit.cover);
    }
    final notLivePath = galleryPath ?? selfiePath;
    if (notLivePath != null) {
      return Image.file(File(notLivePath), fit: BoxFit.cover);
    }
    return _AvatarPlaceholder();
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

/// Bio + key profile details card. Values sourced live from [DemoProfileScope].
class _AboutCard extends StatelessWidget {
  const _AboutCard({
    required this.bio,
    required this.age,
    required this.hometown,
    required this.occupation,
    required this.height,
    required this.lookingFor,
  });

  final String bio;
  final int age;
  final String hometown;
  final String occupation;
  final String height;
  final String lookingFor;

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

          if (bio.isNotEmpty) ...[
            Text(
              bio,
              style: AppTextStyles.bodyS.copyWith(
                color: AppColors.textSecondary,
                height: 1.65,
              ),
            ),
            const SizedBox(height: 18),
          ],

          // Bullet details
          _BulletRow(icon: Icons.cake_outlined, label: '$age years old'),
          if (hometown.isNotEmpty) ...[
            const SizedBox(height: 7),
            _BulletRow(icon: Icons.location_on_outlined, label: hometown),
          ],
          if (occupation.isNotEmpty) ...[
            const SizedBox(height: 7),
            _BulletRow(icon: Icons.work_outline_rounded, label: occupation),
          ],
          if (height.isNotEmpty) ...[
            const SizedBox(height: 7),
            _BulletRow(icon: Icons.straighten_rounded, label: height),
          ],
          if (lookingFor.isNotEmpty) ...[
            const SizedBox(height: 7),
            _BulletRow(
              icon: Icons.favorite_border_rounded,
              label: lookingFor,
              color: AppColors.brandPink,
            ),
          ],
        ],
      ),
    );
  }
}

class _BulletRow extends StatelessWidget {
  const _BulletRow({
    required this.icon,
    required this.label,
    this.color,
  });
  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.brandCyan;
    return Row(
      children: [
        Icon(icon, size: 14, color: c.withValues(alpha: 0.75)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: AppTextStyles.bodyS.copyWith(color: AppColors.textPrimary),
          ),
        ),
      ],
    );
  }
}

// ── Photos & Media section ────────────────────────────────────────────────────

/// Horizontal photo strip + video indicator shown below the About Me card.
/// Only renders when at least one photo or the video is saved.
class _MediaSection extends StatelessWidget {
  const _MediaSection({
    required this.photos,
    required this.video,
    required this.onManage,
  });

  final List<XFile?> photos;
  final XFile? video;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final filled = photos.where((p) => p != null).toList();
    final hasPhotos = filled.isNotEmpty;
    final hasMedia = hasPhotos || video != null;
    final photoCount = filled.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: AppColors.brandPurple.withValues(alpha: 0.28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row — title + count badge + Manage link
          Row(
            children: [
              Text(
                'Photos & Media',
                style: AppTextStyles.h3.copyWith(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                ),
              ),
              const SizedBox(width: 8),
              // Live photo count badge
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: photoCount > 0
                      ? AppColors.success.withValues(alpha: 0.12)
                      : AppColors.bgElevated,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: photoCount > 0
                        ? AppColors.success.withValues(alpha: 0.30)
                        : AppColors.divider,
                  ),
                ),
                child: Text(
                  '$photoCount / 6',
                  style: AppTextStyles.caption.copyWith(
                    color: photoCount > 0
                        ? AppColors.success
                        : AppColors.textMuted,
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                  ),
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: onManage,
                child: Text(
                  hasMedia ? 'Manage' : 'Add',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.brandCyan,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),

          // Empty state — visible prompt when no media has been added yet.
          if (!hasMedia) ...[
            const SizedBox(height: 14),
            GestureDetector(
              onTap: onManage,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    vertical: 22, horizontal: 16),
                decoration: BoxDecoration(
                  color: AppColors.brandPurple.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.brandPurple.withValues(alpha: 0.18),
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.add_photo_alternate_rounded,
                      size: 30,
                      color: AppColors.brandPurple.withValues(alpha: 0.50),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Add your photos',
                      style: AppTextStyles.bodyS.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Up to 6 photos + optional intro video',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          // Photo thumbnail strip — tapping anywhere opens gallery.
          if (hasPhotos) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: onManage,
              child: SizedBox(
                height: 96,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: filled.length,
                  separatorBuilder: (context, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final isMain = photos.indexOf(filled[i]) == 0;
                    return _PhotoThumb(xFile: filled[i]!, isMain: isMain);
                  },
                ),
              ),
            ),
          ],

          if (video != null) ...[
            const SizedBox(height: 10),
            _VideoIndicator(fileName: video!.name),
          ],
        ],
      ),
    );
  }
}

class _PhotoThumb extends StatelessWidget {
  const _PhotoThumb({required this.xFile, required this.isMain});
  final XFile xFile;
  final bool isMain;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(
            File(xFile.path),
            width: 68,
            height: 90,
            fit: BoxFit.cover,
          ),
        ),
        if (isMain)
          Positioned(
            bottom: 4,
            left: 4,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                gradient: AppColors.brandGradient,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'MAIN',
                style: AppTextStyles.caption.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 8,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _VideoIndicator extends StatelessWidget {
  const _VideoIndicator({required this.fileName});
  final String fileName;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.brandPurple.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.brandPurple.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.videocam_rounded,
            color: AppColors.brandPurple.withValues(alpha: 0.85),
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              fileName,
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textSecondary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Icon(
            Icons.check_circle_rounded,
            color: AppColors.success,
            size: 14,
          ),
        ],
      ),
    );
  }
}
