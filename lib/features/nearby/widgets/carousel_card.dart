import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/pill_button.dart';

/// Single profile card shown in the Nearby horizontal carousel.
///
/// Design: image-forward, full-bleed photo with a deep bottom gradient scrim.
/// All profile info and the CTA are overlaid inside the card.
/// A neon pink → purple gradient border + ambient glow creates a premium feel.
///
/// The card fills its parent — callers should size it via Padding or a
/// SizedBox (typically a PageView page with a small vertical inset).
class CarouselCard extends StatelessWidget {
  const CarouselCard({
    super.key,
    required this.firstName,
    required this.age,
    required this.bio,
    required this.photoUrl,
    this.distanceMeters,
    this.isGold = false,
    this.isLiveNow = false,
    this.interests = const [],
    required this.onSendIcebreaker,
    this.onTap,
  });

  final String firstName;
  final int age;
  final String bio;
  final String photoUrl;

  /// Distance from the viewer in metres.
  final double? distanceMeters;

  /// Show the gold member badge.
  final bool isGold;

  /// Show the "LIVE" badge (user is currently in an active session).
  final bool isLiveNow;

  /// Up to 3 short vibe / interest tags (e.g. 'Coffee', 'Hiking').
  final List<String> interests;

  /// Fired when the "Send Icebreaker" CTA is tapped.
  final VoidCallback onSendIcebreaker;

  /// Fired when the card body (outside the CTA) is tapped.
  final VoidCallback? onTap;

  // ─── Tag accent colours (cycled per-tag index) ───────────────────────────
  static const List<Color> _tagColors = [
    AppColors.brandPink,
    AppColors.brandCyan,
    AppColors.brandPurple,
  ];

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        // Gradient border: outer container carries the gradient; the 1.5 px
        // padding exposes it as a thin strip around the inner ClipRRect.
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.brandPink, AppColors.brandPurple],
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.brandPink.withValues(alpha: 0.30),
              blurRadius: 28,
              spreadRadius: 0,
              offset: const Offset(0, 6),
            ),
            BoxShadow(
              color: AppColors.brandPurple.withValues(alpha: 0.20),
              blurRadius: 44,
              spreadRadius: 4,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        padding: const EdgeInsets.all(1.5),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26.5),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ── Photo ────────────────────────────────────────────────────
              _buildPhoto(),

              // ── Bottom gradient scrim ─────────────────────────────────────
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  height: 340,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0xF4000000)],
                      stops: [0.0, 1.0],
                    ),
                  ),
                ),
              ),

              // ── Top badges ────────────────────────────────────────────────
              Positioned(
                top: 16,
                left: 16,
                right: 16,
                child: Row(
                  children: [
                    if (isLiveNow) const _LiveBadge(),
                    const Spacer(),
                    if (isGold) const _GoldBadge(),
                  ],
                ),
              ),

              // ── Bottom content overlay ─────────────────────────────────────
              Positioned(
                left: 20,
                right: 20,
                bottom: 22,
                child: _buildBottomContent(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhoto() {
    if (photoUrl.isNotEmpty) {
      return Image.network(
        photoUrl,
        fit: BoxFit.cover,
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : const _PhotoPlaceholder(),
        errorBuilder: (_, __, ___) => const _PhotoPlaceholder(),
      );
    }
    return const _PhotoPlaceholder();
  }

  Widget _buildBottomContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Name + age + distance row
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(firstName, style: AppTextStyles.h1),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                '$age',
                style: AppTextStyles.h3.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            if (distanceMeters != null) ...[
              const Spacer(),
              _DistancePill(meters: distanceMeters!),
            ],
          ],
        ),

        // One-liner bio
        if (bio.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            bio,
            style: AppTextStyles.bodyS.copyWith(
              color: Colors.white.withValues(alpha: 0.78),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],

        // Vibe / interest tags
        if (interests.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < interests.take(3).length; i++)
                _TagPill(
                  label: interests[i],
                  color: _tagColors[i % _tagColors.length],
                ),
            ],
          ),
        ],

        const SizedBox(height: 16),

        // CTA — Flutter's gesture arena ensures this tap does NOT bubble
        // to the card's outer onTap.
        PillButton.primary(
          label: 'Send Icebreaker',
          icon: Icons.ac_unit_rounded,
          onTap: onSendIcebreaker,
          width: double.infinity,
          height: 50,
        ),
      ],
    );
  }
}

// ─── Supporting widgets ──────────────────────────────────────────────────────

class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1C0030), Color(0xFF0D001A)],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.person_rounded,
          size: 100,
          color: AppColors.textMuted.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.brandPink,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandPink.withValues(alpha: 0.55),
            blurRadius: 10,
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
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _GoldBadge extends StatelessWidget {
  const _GoldBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFFFD700),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFD700).withValues(alpha: 0.40),
            blurRadius: 8,
          ),
        ],
      ),
      child: Text(
        'GOLD',
        style: AppTextStyles.caption.copyWith(
          color: Colors.black,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.50),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.18),
          width: 0.5,
        ),
      ),
      child: Text(
        label,
        style: AppTextStyles.caption.copyWith(
          color: Colors.white.withValues(alpha: 0.85),
        ),
      ),
    );
  }
}

class _TagPill extends StatelessWidget {
  const _TagPill({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: color.withValues(alpha: 0.38),
          width: 0.5,
        ),
      ),
      child: Text(
        label,
        style: AppTextStyles.caption.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
