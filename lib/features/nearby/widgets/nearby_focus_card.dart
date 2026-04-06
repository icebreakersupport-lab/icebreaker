import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/pill_button.dart';

/// The hero profile card shown in the Nearby discovery carousel.
///
/// Layout (inside a Stack):
///   - Full-bleed portrait photo
///   - Gradient border ring (pink → purple → cyan) with outer glow
///   - Deep bottom scrim
///   - Optional chat-bubble opener mid-card
///   - Name + age + bio + distance/hometown pills at bottom
///   - "Send Icebreaker 🧊" CTA integrated at the card bottom
///
/// [isActive] controls scale (1.0 vs 0.94) and glow intensity so the
/// centred card stands out from the partially visible neighbours.
class NearbyFocusCard extends StatelessWidget {
  const NearbyFocusCard({
    super.key,
    required this.firstName,
    required this.age,
    required this.bio,
    required this.photoUrl,
    this.distanceMeters,
    this.hometown,
    this.opener,
    this.isGold = false,
    this.isActive = true,
    required this.onSendIcebreaker,
  });

  final String firstName;
  final int age;
  final String bio;
  final String photoUrl;
  final double? distanceMeters;
  final String? hometown;

  /// Short conversation starter shown as a floating chat bubble on the card.
  final String? opener;

  final bool isGold;

  /// True when this card is the centred, focused card in the carousel.
  final bool isActive;

  final VoidCallback onSendIcebreaker;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Vertical breathing room lets the glow shadow render unclipped.
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      child: AnimatedScale(
        scale: isActive ? 1.0 : 0.94,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: isActive ? 1.0 : 0.60,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          child: _GlowBorderShell(
            isActive: isActive,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // ── Photo ─────────────────────────────────────────────────────
                _Photo(url: photoUrl),

                // ── Bottom scrim ──────────────────────────────────────────────
                const _BottomScrim(),

                // ── Chat bubble ───────────────────────────────────────────────
                if (opener != null && opener!.isNotEmpty)
                  Positioned(
                    left: 18,
                    right: 18,
                    bottom: 148,
                    child: _ChatBubble(text: opener!),
                  ),

                // ── Gold badge ────────────────────────────────────────────────
                if (isGold)
                  const Positioned(
                    top: 16,
                    right: 16,
                    child: _GoldBadge(),
                  ),

                // ── Bottom overlay: name / bio / pills / button ────────────────
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 18,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Name + age row
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Flexible(
                            child: Text(
                              firstName,
                              style: AppTextStyles.h1.copyWith(
                                fontSize: 36,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.8,
                                shadows: const [
                                  Shadow(color: Colors.black87, blurRadius: 10),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 5),
                            child: Text(
                              '$age',
                              style: AppTextStyles.h3.copyWith(
                                color: AppColors.textSecondary,
                                shadows: const [
                                  Shadow(
                                      color: Colors.black87, blurRadius: 6),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),

                      // Bio
                      if (bio.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          bio,
                          style: AppTextStyles.bodyS.copyWith(
                            color: Colors.white70,
                            shadows: const [
                              Shadow(color: Colors.black87, blurRadius: 6),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],

                      // Distance + hometown pills
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (distanceMeters != null) ...[
                            _DistancePill(meters: distanceMeters!),
                            const SizedBox(width: 6),
                          ],
                          if (hometown != null && hometown!.isNotEmpty)
                            _HometownPill(label: hometown!),
                        ],
                      ),

                      const SizedBox(height: 14),

                      // CTA button
                      PillButton.primary(
                        label: 'Send Icebreaker 🧊',
                        onTap: onSendIcebreaker,
                        width: double.infinity,
                        height: 52,
                      ),
                    ],
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

// ─────────────────────────────────────────────────────────────────────────────
// _GlowBorderShell
// ─────────────────────────────────────────────────────────────────────────────

/// Outer container that renders the gradient border ring and neon glow.
///
/// Technique: gradient Container (2.5 pt) → padding → ClipRRect (child).
/// The outer boxShadow layers create the soft neon glow.
class _GlowBorderShell extends StatelessWidget {
  const _GlowBorderShell({required this.isActive, required this.child});

  final bool isActive;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.brandPink,
            AppColors.brandPurple,
            AppColors.brandCyan,
          ],
          stops: [0.0, 0.55, 1.0],
        ),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: AppColors.brandPink.withValues(alpha: 0.45),
                  blurRadius: 30,
                  spreadRadius: 2,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: AppColors.brandPurple.withValues(alpha: 0.30),
                  blurRadius: 52,
                  spreadRadius: 0,
                  offset: const Offset(0, 14),
                ),
              ]
            : [
                BoxShadow(
                  color: AppColors.brandPink.withValues(alpha: 0.08),
                  blurRadius: 12,
                  spreadRadius: 0,
                ),
              ],
      ),
      padding: const EdgeInsets.all(2.5),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: child,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _Photo
// ─────────────────────────────────────────────────────────────────────────────

class _Photo extends StatelessWidget {
  const _Photo({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    if (url.isNotEmpty) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : const _PhotoPlaceholder(),
        errorBuilder: (context, error, stackTrace) => const _PhotoPlaceholder(),
      );
    }
    return const _PhotoPlaceholder();
  }
}

class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.bgSurface, AppColors.bgElevated],
        ),
      ),
      child: const Center(
        child: Icon(Icons.person_rounded, size: 72, color: AppColors.textMuted),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _BottomScrim
// ─────────────────────────────────────────────────────────────────────────────

class _BottomScrim extends StatelessWidget {
  const _BottomScrim();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0.30, 0.62, 1.0],
          colors: [
            Colors.transparent,
            Color(0xBB000000),
            Color(0xF2000000),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ChatBubble
// ─────────────────────────────────────────────────────────────────────────────

/// Speech-bubble showing the user's opener or a bio snippet.
class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(18),
          topRight: Radius.circular(18),
          bottomRight: Radius.circular(18),
          bottomLeft: Radius.circular(5), // speech tail
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.14),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('💬 ',
              style: TextStyle(fontSize: 13, height: 1.4)),
          Flexible(
            child: Text(
              text,
              style: AppTextStyles.bodyS.copyWith(
                color: Colors.white.withValues(alpha: 0.88),
                height: 1.35,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _GoldBadge
// ─────────────────────────────────────────────────────────────────────────────

class _GoldBadge extends StatelessWidget {
  const _GoldBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFFFD700),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFD700).withValues(alpha: 0.40),
            blurRadius: 10,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Text(
        'GOLD',
        style: AppTextStyles.caption.copyWith(
          color: Colors.black,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.9,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pills
// ─────────────────────────────────────────────────────────────────────────────

class _DistancePill extends StatelessWidget {
  const _DistancePill({required this.meters});
  final double meters;

  @override
  Widget build(BuildContext context) {
    final label = meters < 1000
        ? '${meters.round()}m away'
        : '${(meters / 1000).toStringAsFixed(1)}km away';
    return _Pill(label: label);
  }
}

class _HometownPill extends StatelessWidget {
  const _HometownPill({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return _Pill(label: 'From $label', icon: Icons.location_on_rounded);
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, this.icon});
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: Colors.white70),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: AppTextStyles.caption.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}
