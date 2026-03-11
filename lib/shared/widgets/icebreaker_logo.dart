import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// The Icebreaker brand logo rendered from the real logo asset.
///
/// A subtle heartbeat pulse animation scales the logo: 1.0 → 1.08 → 1.0 →
/// 1.05 → 1.0 to mimic a natural heartbeat rhythm.
/// An optional radial glow is rendered behind the image.
class IcebreakerLogo extends StatefulWidget {
  const IcebreakerLogo({
    super.key,
    this.size = 120,
    this.showGlow = true,
    this.glowRadius = 1.4,
    this.animate = true,
  });

  /// Logical diameter of the bounding box.
  final double size;

  /// Whether to render a radial ambient glow behind the logo.
  final bool showGlow;

  /// Size multiplier for the glow relative to [size].
  final double glowRadius;

  /// Whether to run the heartbeat pulse animation.
  final bool animate;

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
      duration: const Duration(milliseconds: 1200),
    );

    // Heartbeat curve: rest → beat1 → rest → beat2 → rest
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.08)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 15,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.08, end: 1.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 15,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.05)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 12,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.05, end: 1.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 12,
      ),
      // Pause at rest before next beat
      TweenSequenceItem(
        tween: ConstantTween(1.0),
        weight: 46,
      ),
    ]).animate(_controller);

    if (widget.animate) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(IcebreakerLogo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.animate && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final glowSize = widget.size * widget.glowRadius;

    return SizedBox(
      width: glowSize,
      height: glowSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Ambient glow
          if (widget.showGlow)
            Container(
              width: glowSize,
              height: glowSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.brandPink.withValues(alpha: 0.20),
                    AppColors.brandPurple.withValues(alpha: 0.12),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),

          // Pulsing logo image
          AnimatedBuilder(
            animation: _scale,
            builder: (context, child) => Transform.scale(
              scale: _scale.value,
              child: child,
            ),
            child: SizedBox(
              width: widget.size,
              height: widget.size,
              child: Image.asset(
                'assets/images/logo.png',
                fit: BoxFit.contain,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
