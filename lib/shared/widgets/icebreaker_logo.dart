import 'package:flutter/material.dart';
import '../../core/state/live_session.dart';
import '../../core/theme/app_colors.dart';

/// The Icebreaker brand logo, rendered from the real brand asset.
///
/// Animation is driven entirely by the global [LiveSession] state:
///   - Not live → logo is completely still.
///   - Live     → a subtle heartbeat pulse runs (1.0 → 1.07 → 1.0 → 1.04 → 1.0).
///
/// The PNG's black background is masked out via a luminance-to-alpha
/// [ColorFilter] so the logo composites cleanly over any background.
class IcebreakerLogo extends StatefulWidget {
  const IcebreakerLogo({
    super.key,
    this.size = 120,
    this.showGlow = true,
    this.glowRadius = 1.4,
    this.ambientGlow = 0.0,
  });

  /// Logical diameter of the bounding box.
  final double size;

  /// Whether to render a radial ambient glow behind the logo when live.
  final bool showGlow;

  /// Size multiplier for the glow relative to [size].
  final double glowRadius;

  /// Opacity (0.0–1.0) of a permanent soft glow rendered regardless of live
  /// state. Use this in the AppBar where the logo should always feel vivid.
  /// Stacks with [showGlow] when live — does not replace it.
  final double ambientGlow;

  @override
  State<IcebreakerLogo> createState() => _IcebreakerLogoState();
}

class _IcebreakerLogoState extends State<IcebreakerLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    // Heartbeat: two beats followed by a rest.
    // Kept subtle — peak only +7% and +4%.
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.07)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 12,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.07, end: 1.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 12,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.04)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 10,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.04, end: 1.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 10,
      ),
      // Rest between beats — logo sits still
      TweenSequenceItem(
        tween: ConstantTween(1.0),
        weight: 56,
      ),
    ]).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _syncAnimation(bool isLive) {
    if (isLive && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!isLive && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Subscribe to live state — rebuilds (and syncs animation) on change.
    final isLive = LiveSessionScope.isLive(context);
    _syncAnimation(isLive);

    final glowSize = widget.size * widget.glowRadius;

    return SizedBox(
      width: glowSize,
      height: glowSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Permanent ambient glow — rendered when ambientGlow > 0,
          // regardless of live state. Keeps the logo vivid in the AppBar.
          if (widget.ambientGlow > 0)
            Container(
              width: glowSize,
              height: glowSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.brandPink
                        .withValues(alpha: widget.ambientGlow * 0.45),
                    AppColors.brandPurple
                        .withValues(alpha: widget.ambientGlow * 0.30),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.55, 1.0],
                ),
              ),
            ),

          // Live-state glow — additional signal when the user is active.
          if (widget.showGlow && isLive)
            Container(
              width: glowSize,
              height: glowSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.brandPink.withValues(alpha: 0.18),
                    AppColors.brandPurple.withValues(alpha: 0.10),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),

          // Logo image — luminance-to-alpha filter removes the black background
          // so the neon strokes composite cleanly over any surface.
          AnimatedBuilder(
            animation: _scale,
            builder: (context, child) => Transform.scale(
              scale: _scale.value,
              child: child,
            ),
            child: SizedBox(
              width: widget.size,
              height: widget.size,
              child: ColorFiltered(
                // Set alpha = luminance: black → transparent, neon → opaque.
                colorFilter: const ColorFilter.matrix([
                  1, 0, 0, 0, 0, //
                  0, 1, 0, 0, 0, //
                  0, 0, 1, 0, 0, //
                  0.299, 0.587, 0.114, 0, 0, //
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
  }
}
