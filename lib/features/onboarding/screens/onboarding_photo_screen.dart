import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/state/demo_profile.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/icebreaker_logo.dart';

/// Onboarding — Step 7: First profile photo (required).
///
/// Lets the user pick one photo from their library or take a new one.
/// Continue is disabled until a photo is selected.
///
/// Storage model (in-memory):
///   Calls DemoProfileScope.setPhoto(0, xFile) — consistent with how
///   GalleryScreen and EditProfileScreen set photos.
///
/// Firebase Storage upload is intentionally deferred.
/// To wire it up, implement [_uploadPhoto] below and call it from [_continue].
/// The XFile path is already available at that point.
class OnboardingPhotoScreen extends StatefulWidget {
  const OnboardingPhotoScreen({super.key});

  @override
  State<OnboardingPhotoScreen> createState() => _OnboardingPhotoScreenState();
}

class _OnboardingPhotoScreenState extends State<OnboardingPhotoScreen> {
  final _picker = ImagePicker();

  XFile? _photo;
  bool _isContinuing = false;

  bool get _hasPhoto => _photo != null;

  // ─── Photo picking ───────────────────────────────────────────────────────────

  // Returns the chosen source from the sheet AFTER the sheet is fully dismissed,
  // so the iOS ViewController stack is clear before image_picker presents its UI.
  Future<void> _showPickerSheet() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textMuted,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            _SheetOption(
              icon: Icons.photo_library_rounded,
              label: 'Choose from Library',
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            _SheetOption(
              icon: Icons.camera_alt_rounded,
              label: 'Take a Photo',
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );

    // Sheet is now fully dismissed — safe to present the picker.
    if (source != null && mounted) {
      await _pick(source);
    }
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 1080,
        maxHeight: 1080,
        imageQuality: 90,
      );
      if (picked != null && mounted) {
        setState(() => _photo = picked);
      }
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('[Onboarding/Photo] ❌ picker PlatformException: ${e.code} — ${e.message}');
      if (!mounted) return;
      final msg = switch (e.code) {
        'camera_access_denied' =>
          'Camera access is off. Go to Settings → Icebreaker → Camera to enable it.',
        'photo_access_denied' =>
          'Photo library access is off. Go to Settings → Icebreaker → Photos to enable it.',
        'invalid_source' || 'source_unavailable' =>
          'Camera is not available on this device.',
        _ => source == ImageSource.camera
            ? 'Camera is not available on this device.'
            : 'Could not open your photo library. Please try again.',
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg, style: AppTextStyles.bodyS),
          backgroundColor: AppColors.bgSurface,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      // ignore: avoid_print
      print('[Onboarding/Photo] ❌ picker error: $e');
    }
  }

  // ─── Continue ────────────────────────────────────────────────────────────────

  Future<void> _continue() async {
    if (!_hasPhoto || _isContinuing) return;
    setState(() => _isContinuing = true);

    // ── 1. In-memory profile ──────────────────────────────────────────────────
    DemoProfileScope.of(context).setPhoto(0, _photo);

    // ── 2. Firebase Storage upload (TODO) ─────────────────────────────────────
    // Implement _uploadPhoto() here when ready.
    // final downloadUrl = await _uploadPhoto(_photo!);
    // Then write downloadUrl to Firestore users/{uid}.photoUrls[0].

    // ── 3. Advance to slideshow / feature walkthrough ─────────────────────────
    if (!mounted) return;
    context.go(AppRoutes.onboardingSlideshow);
  }

  // ─── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 52),

              const Center(child: IcebreakerLogo(size: 56, showGlow: false)),
              const SizedBox(height: 32),

              Text(
                'Add your first photo',
                style: AppTextStyles.h2,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),

              Text(
                'Use a clear photo so people can recognize you when it\'s time to break the ice.',
                style: AppTextStyles.bodyS,
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 32),

              // ── Photo card ────────────────────────────────────────────────
              Expanded(
                child: _PhotoCard(
                  photo: _photo,
                  onTap: _showPickerSheet,
                ),
              ),

              const SizedBox(height: 16),

              // Helper tips
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.info_outline_rounded,
                      size: 13, color: AppColors.textMuted),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Clear face photo recommended · No sunglasses or group shots',
                      style: AppTextStyles.caption,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 28),

              // ── Continue ──────────────────────────────────────────────────
              GestureDetector(
                onTap: (_hasPhoto && !_isContinuing) ? _continue : null,
                child: AnimatedOpacity(
                  opacity: (_hasPhoto && !_isContinuing) ? 1.0 : 0.38,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    height: 56,
                    decoration: BoxDecoration(
                      gradient: AppColors.brandGradient,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: _hasPhoto
                          ? [
                              BoxShadow(
                                color: AppColors.brandPink
                                    .withValues(alpha: 0.32),
                                blurRadius: 18,
                                offset: const Offset(0, 5),
                              ),
                            ]
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: _isContinuing
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : Text('Continue', style: AppTextStyles.buttonL),
                  ),
                ),
              ),

              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _PhotoCard
// ─────────────────────────────────────────────────────────────────────────────

/// Tappable square card that shows either an empty placeholder or the
/// selected photo preview. Tapping always re-opens the picker sheet.
class _PhotoCard extends StatelessWidget {
  const _PhotoCard({
    required this.photo,
    required this.onTap,
  });

  final XFile? photo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: photo != null
                ? AppColors.brandPink.withValues(alpha: 0.50)
                : AppColors.divider,
            width: photo != null ? 1.5 : 1.0,
          ),
        ),
        clipBehavior: Clip.hardEdge,
        child: photo != null ? _Preview(photo: photo!) : const _Placeholder(),
      ),
    );
  }
}

// ─── Empty state ─────────────────────────────────────────────────────────────

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                AppColors.brandPink.withValues(alpha: 0.18),
                AppColors.brandPurple.withValues(alpha: 0.08),
                Colors.transparent,
              ],
            ),
          ),
          child: const Icon(
            Icons.add_a_photo_rounded,
            color: AppColors.brandPink,
            size: 32,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Tap to add your photo',
          style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 6),
        Text(
          'Library or camera',
          style: AppTextStyles.bodyS,
        ),
      ],
    );
  }
}

// ─── Photo preview ────────────────────────────────────────────────────────────

class _Preview extends StatelessWidget {
  const _Preview({required this.photo});

  final XFile photo;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.file(
          File(photo.path),
          fit: BoxFit.cover,
        ),
        // Change-photo badge — bottom-right corner
        Positioned(
          right: 14,
          bottom: 14,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.20),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.edit_rounded,
                    color: Colors.white, size: 13),
                const SizedBox(width: 5),
                Text(
                  'Change',
                  style: AppTextStyles.caption.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
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

// ─────────────────────────────────────────────────────────────────────────────
// _SheetOption
// ─────────────────────────────────────────────────────────────────────────────

class _SheetOption extends StatelessWidget {
  const _SheetOption({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Row(
          children: [
            Icon(icon, color: AppColors.brandPink, size: 22),
            const SizedBox(width: 16),
            Text(label, style: AppTextStyles.body),
          ],
        ),
      ),
    );
  }
}
