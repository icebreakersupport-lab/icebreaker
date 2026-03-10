import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/pill_button.dart';

/// A single profile card in the Nearby carousel.
///
/// Layout (from slide 7):
///   - Full-bleed photo with rounded corners
///   - Bottom gradient scrim (transparent → black)
///   - Name + distance/tag pill overlay on the photo
///   - Bio text + Send Icebreaker button below the photo
///
/// The card occupies most of the screen height (hero photo layout).
class CarouselCard extends StatelessWidget {
  const CarouselCard({
    super.key,
    required this.firstName,
    required this.age,
    required this.bio,
    required this.photoUrl,
    this.selfieUrl,
    this.distanceMeters,
    this.isGold = false,
    required this.onSendIcebreaker,
  });

  final String firstName;
  final int age;
  final String bio;
  final String photoUrl;
  final String? selfieUrl;
  final double? distanceMeters;
  final bool isGold;
  final VoidCallback onSendIcebreaker;

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    final cardH = screenH * 0.62;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Photo card ────────────────────────────────────────────────────
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Stack(
              children: [
                // Photo
                SizedBox(
                  width: double.infinity,
                  height: cardH,
                  child: photoUrl.isNotEmpty
                      ? Image.network(
                          photoUrl,
                          fit: BoxFit.cover,
                          loadingBuilder: (_, child, progress) =>
                              progress == null
                                  ? child
                                  : _PhotoPlaceholder(height: cardH),
                          errorBuilder: (context, error, stackTrace) =>
                              _PhotoPlaceholder(height: cardH),
                        )
                      : _PhotoPlaceholder(height: cardH),
                ),

                // Bottom scrim
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    height: cardH * 0.45,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          AppColors.photoScrim,
                        ],
                      ),
                    ),
                  ),
                ),

                // Name + age overlay (bottom-left)
                Positioned(
                  left: 20,
                  bottom: 20,
                  right: 80,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            firstName,
                            style: AppTextStyles.h1,
                          ),
                          const SizedBox(width: 8),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              '$age',
                              style: AppTextStyles.h3.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (distanceMeters != null) ...[
                        const SizedBox(height: 4),
                        _DistancePill(meters: distanceMeters!),
                      ],
                    ],
                  ),
                ),

                // Gold badge (top-right)
                if (isGold)
                  Positioned(
                    top: 16,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFD700),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'GOLD',
                        style: AppTextStyles.caption.copyWith(
                          color: Colors.black,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Bio + CTA ─────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (bio.isNotEmpty) ...[
                  Text(
                    bio,
                    style: AppTextStyles.bodyS,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 16),
                ],

                PillButton.primary(
                  label: 'Send Icebreaker 🧊',
                  onTap: onSendIcebreaker,
                  width: double.infinity,
                  height: 56,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DistancePill extends StatelessWidget {
  const _DistancePill({required this.meters});
  final double meters;

  @override
  Widget build(BuildContext context) {
    final label = meters < 1000
        ? '${meters.round()}m away'
        : '${(meters / 1000).toStringAsFixed(1)}km away';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24, width: 0.5),
      ),
      child: Text(label, style: AppTextStyles.caption),
    );
  }
}

class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder({required this.height});
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: height,
      color: AppColors.bgSurface,
      child: const Center(
        child: Icon(Icons.person_rounded, size: 80, color: AppColors.textMuted),
      ),
    );
  }
}
