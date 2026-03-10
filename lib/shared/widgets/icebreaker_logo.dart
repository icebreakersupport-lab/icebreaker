import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// The Icebreaker brand logo: a heart outline with a lightning bolt inside.
///
/// Heart stroke uses a pink-to-purple-blue gradient (left → right).
/// Lightning bolt is solid neon cyan.
/// An optional radial glow can be shown behind the logo.
class IcebreakerLogo extends StatelessWidget {
  const IcebreakerLogo({
    super.key,
    this.size = 120,
    this.showGlow = true,
    this.glowRadius = 1.4,
  });

  /// Logical diameter of the bounding box.
  final double size;

  /// Whether to render a radial ambient glow behind the logo.
  final bool showGlow;

  /// Size multiplier for the glow relative to [size].
  final double glowRadius;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size * glowRadius,
      height: size * glowRadius,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Ambient glow
          if (showGlow)
            Container(
              width: size * glowRadius,
              height: size * glowRadius,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.brandPink.withValues(alpha: 0.25),
                    AppColors.brandPurple.withValues(alpha: 0.15),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),

          // Logo icon — custom painted heart + bolt
          SizedBox(
            width: size,
            height: size,
            child: CustomPaint(
              painter: _HeartBoltPainter(),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeartBoltPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // ── Heart outline (gradient stroke) ──────────────────────────────────────
    final heartPath = _buildHeartPath(w, h);

    // Gradient shader for the heart stroke
    final heartShader = const LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [AppColors.brandPink, AppColors.brandPurple],
    ).createShader(Rect.fromLTWH(0, 0, w, h));

    final heartPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.055
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..shader = heartShader;

    canvas.drawPath(heartPath, heartPaint);

    // ── Lightning bolt (solid cyan) ───────────────────────────────────────────
    final boltPath = _buildBoltPath(w, h);

    final boltPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = AppColors.brandCyan;

    canvas.drawPath(boltPath, boltPaint);
  }

  Path _buildHeartPath(double w, double h) {
    // Classic heart shape centred in the bounding box.
    // Scaled to leave ~10% padding all around.
    final p = 0.10;
    final l = w * p;
    final t = h * (p + 0.08);
    final r = w * (1 - p);
    final b = h * (1 - p);
    final midX = w * 0.5;
    final midY = h * 0.5;

    final path = Path();
    path.moveTo(midX, b);

    // Bottom-left curve
    path.cubicTo(
      l - w * 0.05, midY + h * 0.1,
      l - w * 0.05, t + h * 0.05,
      midX - w * 0.18, t,
    );

    // Top-left lobe
    path.cubicTo(
      midX - w * 0.38, t,
      midX - w * 0.38, t - h * 0.15,
      midX - w * 0.2, t - h * 0.15,
    );
    path.cubicTo(
      midX - w * 0.08, t - h * 0.15,
      midX - w * 0.02, t - h * 0.05,
      midX, t + h * 0.02,
    );

    // Top-right lobe (mirror)
    path.cubicTo(
      midX + w * 0.02, t - h * 0.05,
      midX + w * 0.08, t - h * 0.15,
      midX + w * 0.2, t - h * 0.15,
    );
    path.cubicTo(
      midX + w * 0.38, t - h * 0.15,
      midX + w * 0.38, t,
      midX + w * 0.18, t,
    );

    // Bottom-right curve
    path.cubicTo(
      r + w * 0.05, t + h * 0.05,
      r + w * 0.05, midY + h * 0.1,
      midX, b,
    );

    path.close();
    return path;
  }

  Path _buildBoltPath(double w, double h) {
    // Lightning bolt centred in the heart, pointing slightly right.
    final cx = w * 0.50;
    final cy = h * 0.52;
    final bw = w * 0.22;
    final bh = h * 0.40;

    final path = Path();
    // Top-right point
    path.moveTo(cx + bw * 0.5, cy - bh * 0.5);
    // Down to the middle-left notch
    path.lineTo(cx - bw * 0.05, cy + bh * 0.05);
    // Horizontal jut to the right at the centre
    path.lineTo(cx + bw * 0.18, cy + bh * 0.05);
    // Down to the bottom-left tip
    path.lineTo(cx - bw * 0.5, cy + bh * 0.5);
    // Back up to the middle-right
    path.lineTo(cx + bw * 0.05, cy - bh * 0.05);
    // Horizontal jut back to the left
    path.lineTo(cx - bw * 0.18, cy - bh * 0.05);
    path.close();

    return path;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
