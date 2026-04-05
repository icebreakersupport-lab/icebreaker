import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/pill_button.dart';

/// First screen the user sees on every cold launch (unauthenticated).
///
/// Layout (top → bottom):
///   Spacer(2) → [_PulsingLogo] → wordmark → tagline → Spacer(3)
///   → CTA buttons → legal footer
///
/// Entrance: logo, wordmark, tagline, and buttons each fade in with a
/// brief stagger so the screen feels composed rather than dumped at once.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance;

  // Per-element entrance fade intervals
  late final Animation<double> _logoFade;
  late final Animation<double> _logoEntryScale;
  late final Animation<double> _wordmarkFade;
  late final Animation<double> _taglineFade;
  late final Animation<double> _buttonsFade;

  @override
  void initState() {
    super.initState();

    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    );

    _logoFade = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.00, 0.45, curve: Curves.easeOut),
    );

    _logoEntryScale = Tween<double>(begin: 0.80, end: 1.0).animate(
      CurvedAnimation(
        parent: _entrance,
        curve: const Interval(0.00, 0.50, curve: Curves.easeOutCubic),
      ),
    );

    _wordmarkFade = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.28, 0.62, curve: Curves.easeOut),
    );

    _taglineFade = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.42, 0.72, curve: Curves.easeOut),
    );

    _buttonsFade = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.60, 1.00, curve: Curves.easeOut),
    );

    _entrance.forward();
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Ambient glow blobs (static, purely decorative) ──────────────
          _AmbientGlow(screenSize: size),

          // ── Main content ─────────────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Spacer(flex: 2),

                  // Logo — entrance scale/fade + continuous heartbeat inside
                  AnimatedBuilder(
                    animation: _entrance,
                    builder: (context, child) => FadeTransition(
                      opacity: _logoFade,
                      child: Transform.scale(
                        scale: _logoEntryScale.value,
                        child: child,
                      ),
                    ),
                    child: const _PulsingLogo(size: 148),
                  ),

                  const SizedBox(height: 28),

                  // ICEBREAKER wordmark — gradient text
                  FadeTransition(
                    opacity: _wordmarkFade,
                    child: ShaderMask(
                      shaderCallback: (bounds) =>
                          AppColors.brandGradient.createShader(bounds),
                      child: Text(
                        'ICEBREAKER',
                        style: AppTextStyles.displayLabel.copyWith(
                          color: Colors.white,
                          fontSize: 34,
                          letterSpacing: 7,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Tagline
                  FadeTransition(
                    opacity: _taglineFade,
                    child: Text(
                      'Real places. Real people.',
                      style: AppTextStyles.bodyL.copyWith(
                        color: Colors.white.withValues(alpha: 0.62),
                        fontWeight: FontWeight.w300,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),

                  const Spacer(flex: 3),

                  // CTA block — all fades in together
                  FadeTransition(
                    opacity: _buttonsFade,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Primary CTA
                        PillButton.primary(
                          label: 'Get Started',
                          onTap: () => context.go(AppRoutes.signUp),
                          width: double.infinity,
                        ),

                        const SizedBox(height: 20),

                        // Secondary CTA
                        GestureDetector(
                          onTap: () => context.go(AppRoutes.signIn),
                          behavior: HitTestBehavior.opaque,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Text(
                              'I already have an account',
                              style: AppTextStyles.body.copyWith(
                                color: Colors.white.withValues(alpha: 0.52),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 30),

                        // Legal footer
                        const _LegalFooter(),

                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _PulsingLogo
// ─────────────────────────────────────────────────────────────────────────────

/// Logo mark with an always-on heartbeat animation.
///
/// Independent of [LiveSession] state — this is the welcome screen,
/// the user isn't live yet. Animation runs immediately on mount.
///
/// Beat sequence: 1.0 → 1.08 → 1.0 → 1.05 → 1.0 → rest (56% idle)
/// Total period: 1 400 ms
///
/// The radial glow pulses in sync with beat 1 only, giving the impression
/// of light being emitted on the first beat.
class _PulsingLogo extends StatefulWidget {
  const _PulsingLogo({required this.size});

  final double size;

  @override
  State<_PulsingLogo> createState() => _PulsingLogoState();
}

class _PulsingLogoState extends State<_PulsingLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _heartbeat;
  late final Animation<double> _scale;
  late final Animation<double> _glowPulse;

  @override
  void initState() {
    super.initState();

    _heartbeat = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();

    // Two-beat heartbeat: beat1 (+8%), small gap, beat2 (+5%), long rest.
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.08)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 10,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.08, end: 1.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 9,
      ),
      TweenSequenceItem(
        tween: ConstantTween(1.0),
        weight: 4,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.05)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 8,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.05, end: 1.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 7,
      ),
      TweenSequenceItem(
        tween: ConstantTween(1.0),
        weight: 62,
      ),
    ]).animate(_heartbeat);

    // Glow blooms only on beat 1 (first ~13% of the cycle), then fades.
    _glowPulse = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 0.7)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 10,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.7, end: 0.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 9,
      ),
      TweenSequenceItem(
        tween: ConstantTween(0.0),
        weight: 81,
      ),
    ]).animate(_heartbeat);
  }

  @override
  void dispose() {
    _heartbeat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final glowSize = widget.size * 1.9;

    return AnimatedBuilder(
      animation: _heartbeat,
      builder: (context, _) {
        return SizedBox(
          width: glowSize,
          height: glowSize,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Permanent soft ambient glow (always present)
              Container(
                width: glowSize,
                height: glowSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.brandPink.withValues(alpha: 0.13),
                      AppColors.brandPurple.withValues(alpha: 0.08),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.50, 1.0],
                  ),
                ),
              ),

              // Dynamic glow — blooms with beat 1
              Container(
                width: glowSize,
                height: glowSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.brandPink
                          .withValues(alpha: _glowPulse.value * 0.48),
                      AppColors.brandPurple
                          .withValues(alpha: _glowPulse.value * 0.28),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.50, 1.0],
                  ),
                ),
              ),

              // Logo — scales with heartbeat, black bg masked via luminance filter
              Transform.scale(
                scale: _scale.value,
                child: SizedBox(
                  width: widget.size,
                  height: widget.size,
                  child: ColorFiltered(
                    // Black background → transparent; neon strokes → opaque.
                    colorFilter: const ColorFilter.matrix([
                      1, 0, 0, 0, 0,
                      0, 1, 0, 0, 0,
                      0, 0, 1, 0, 0,
                      0.299, 0.587, 0.114, 0, 0,
                    ]),
                    child: Image.asset(
                      'assets/images/logo.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _AmbientGlow
// ─────────────────────────────────────────────────────────────────────────────

/// Three static radial glow blobs placed behind all content.
/// Pink upper-left, purple mid-right, cyan lower-center.
/// Intentionally low opacity — barely-there colour wash, not a spotlight.
class _AmbientGlow extends StatelessWidget {
  const _AmbientGlow({required this.screenSize});

  final Size screenSize;

  @override
  Widget build(BuildContext context) {
    return SizedBox.fromSize(
      size: screenSize,
      child: Stack(
        children: [
          // Neon pink — upper-left of center
          Positioned(
            left: screenSize.width * 0.05,
            top: screenSize.height * 0.15,
            child: _GlowBlob(
              color: AppColors.brandPink,
              radius: screenSize.width * 0.60,
              opacity: 0.11,
            ),
          ),
          // Electric purple — mid-right
          Positioned(
            right: -screenSize.width * 0.05,
            top: screenSize.height * 0.28,
            child: _GlowBlob(
              color: AppColors.brandPurple,
              radius: screenSize.width * 0.55,
              opacity: 0.09,
            ),
          ),
          // Cyan — lower center
          Positioned(
            left: screenSize.width * 0.18,
            bottom: screenSize.height * 0.12,
            child: _GlowBlob(
              color: AppColors.brandCyan,
              radius: screenSize.width * 0.38,
              opacity: 0.06,
            ),
          ),
        ],
      ),
    );
  }
}

class _GlowBlob extends StatelessWidget {
  const _GlowBlob({
    required this.color,
    required this.radius,
    required this.opacity,
  });

  final Color color;
  final double radius;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: radius,
      height: radius,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withValues(alpha: opacity),
            Colors.transparent,
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _LegalFooter
// ─────────────────────────────────────────────────────────────────────────────

class _LegalFooter extends StatelessWidget {
  const _LegalFooter();

  @override
  Widget build(BuildContext context) {
    final base = AppTextStyles.caption.copyWith(
      color: Colors.white.withValues(alpha: 0.28),
      height: 1.6,
    );
    final link = base.copyWith(
      color: Colors.white.withValues(alpha: 0.44),
      decoration: TextDecoration.underline,
      decorationColor: Colors.white.withValues(alpha: 0.28),
    );

    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        style: base,
        children: [
          const TextSpan(text: 'By continuing you agree to our '),
          TextSpan(text: 'Terms', style: link),
          const TextSpan(text: ' and '),
          TextSpan(text: 'Privacy Policy', style: link),
        ],
      ),
    );
  }
}
