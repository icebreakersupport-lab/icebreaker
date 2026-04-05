import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Onboarding — final step: feature walkthrough slideshow (7 slides).
///
/// Swipeable PageView. Tapping Next advances; tapping Skip on any slide
/// (or "Let's Go" on the last) navigates to [AppRoutes.home].
///
/// No data is saved here — this is purely educational.
class OnboardingSlideshowScreen extends StatefulWidget {
  const OnboardingSlideshowScreen({super.key});

  @override
  State<OnboardingSlideshowScreen> createState() =>
      _OnboardingSlideshowScreenState();
}

class _OnboardingSlideshowScreenState extends State<OnboardingSlideshowScreen> {
  final _controller = PageController();
  int _currentIndex = 0;

  bool get _isLast => _currentIndex == _slides.length - 1;

  void _next() {
    if (_isLast) {
      _finish();
    } else {
      _controller.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOut,
      );
    }
  }

  void _finish() => context.go(AppRoutes.home);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar: dots left, Skip right ───────────────────────────────
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Row(
                children: [
                  _DotIndicator(
                    count: _slides.length,
                    current: _currentIndex,
                  ),
                  const Spacer(),
                  if (!_isLast)
                    GestureDetector(
                      onTap: _finish,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 4),
                        child: Text(
                          'Skip',
                          style: AppTextStyles.body.copyWith(
                            color: Colors.white.withValues(alpha: 0.45),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // ── Slides ────────────────────────────────────────────────────────
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _currentIndex = i),
                itemBuilder: (context, index) =>
                    _SlideView(data: _slides[index]),
              ),
            ),

            // ── Bottom button ─────────────────────────────────────────────────
            Padding(
              padding: EdgeInsets.fromLTRB(
                28,
                16,
                28,
                MediaQuery.paddingOf(context).bottom + 28,
              ),
              child: GestureDetector(
                onTap: _next,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: AppColors.brandGradient,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.brandPink.withValues(alpha: 0.32),
                        blurRadius: 18,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Text(
                      _isLast ? "Let's Go" : 'Next',
                      key: ValueKey(_isLast),
                      style: AppTextStyles.buttonL,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Slide data
// ─────────────────────────────────────────────────────────────────────────────

class _SlideData {
  const _SlideData({
    required this.icon,
    required this.iconColor,
    required this.glowColor,
    required this.tag,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final Color iconColor;
  final Color glowColor;
  final String tag;
  final String title;
  final String body;
}

const _slides = [
  _SlideData(
    icon: Icons.wifi_tethering_rounded,
    iconColor: AppColors.brandPink,
    glowColor: AppColors.brandPink,
    tag: 'GO LIVE',
    title: 'You control when\nyou\'re discoverable.',
    body:
        'Tap Go Live when you\'re out and open to meeting someone. You appear to people nearby in real time — and go dark the moment you\'re done.',
  ),
  _SlideData(
    icon: Icons.radar_rounded,
    iconColor: AppColors.brandPurple,
    glowColor: AppColors.brandPurple,
    tag: 'NEARBY',
    title: 'Real people,\nin real places, right now.',
    body:
        'When you go live, you\'ll see other live users in the same venue, block, or neighborhood. No endless swiping — just people who are actually here.',
  ),
  _SlideData(
    icon: Icons.favorite_rounded,
    iconColor: AppColors.brandPink,
    glowColor: AppColors.brandPink,
    tag: 'ICEBREAKER',
    title: 'Show interest\nwithout the pressure.',
    body:
        'See someone you\'d like to meet? Send them an Icebreaker — a silent, private signal of interest. They won\'t know until something important happens.',
  ),
  _SlideData(
    icon: Icons.bolt_rounded,
    iconColor: AppColors.brandCyan,
    glowColor: AppColors.brandCyan,
    tag: 'MUTUAL MATCH',
    title: 'Both interested?\nYou both find out at once.',
    body:
        'If they send you an Icebreaker too, you both get notified at the same moment — mutual interest confirmed before anyone has to make an approach.',
  ),
  _SlideData(
    icon: Icons.explore_rounded,
    iconColor: AppColors.brandPurple,
    glowColor: AppColors.brandPurple,
    tag: 'FIND EACH OTHER',
    title: 'Now go say hi —\nfor real.',
    body:
        'When it\'s mutual, you\'ll get a proximity signal to help you find each other in the same space. No home address — just enough to make the approach.',
  ),
  _SlideData(
    icon: Icons.lock_open_rounded,
    iconColor: AppColors.brandPink,
    glowColor: AppColors.brandPink,
    tag: 'CHAT',
    title: 'The conversation\nstarts in person.',
    body:
        'Chat is locked until after you\'ve actually met. Once you\'ve had your real-life Icebreaker moment, messaging opens — every conversation starts with a real connection.',
  ),
  _SlideData(
    icon: Icons.verified_user_rounded,
    iconColor: AppColors.brandCyan,
    glowColor: AppColors.brandCyan,
    tag: 'SAFETY',
    title: 'Real people.\nVerified presence.',
    body:
        'Every user is verified before going live. Your location is never shared with anyone. Go dark instantly. Safety tools are always one tap away.',
  ),
];

// ─────────────────────────────────────────────────────────────────────────────
// _SlideView
// ─────────────────────────────────────────────────────────────────────────────

class _SlideView extends StatelessWidget {
  const _SlideView({required this.data});

  final _SlideData data;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Spacer(flex: 2),

          // Icon with radial glow
          _GlowIcon(
            icon: data.icon,
            iconColor: data.iconColor,
            glowColor: data.glowColor,
          ),

          const SizedBox(height: 40),

          // Tag
          Text(
            data.tag,
            style: AppTextStyles.overline.copyWith(
              color: data.iconColor,
              letterSpacing: 2.5,
            ),
          ),

          const SizedBox(height: 12),

          // Title
          Text(
            data.title,
            style: AppTextStyles.h1.copyWith(height: 1.25),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 16),

          // Body
          Text(
            data.body,
            style: AppTextStyles.body.copyWith(
              color: AppColors.textSecondary,
              height: 1.6,
            ),
            textAlign: TextAlign.center,
          ),

          const Spacer(flex: 3),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _GlowIcon
// ─────────────────────────────────────────────────────────────────────────────

class _GlowIcon extends StatelessWidget {
  const _GlowIcon({
    required this.icon,
    required this.iconColor,
    required this.glowColor,
  });

  final IconData icon;
  final Color iconColor;
  final Color glowColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      height: 140,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer glow
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  glowColor.withValues(alpha: 0.22),
                  glowColor.withValues(alpha: 0.06),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
            ),
          ),
          // Inner circle
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: glowColor.withValues(alpha: 0.10),
              border: Border.all(
                color: glowColor.withValues(alpha: 0.35),
                width: 1.5,
              ),
            ),
            child: Icon(icon, color: iconColor, size: 38),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _DotIndicator
// ─────────────────────────────────────────────────────────────────────────────

class _DotIndicator extends StatelessWidget {
  const _DotIndicator({required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(count, (i) {
        final isActive = i == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.only(right: 5),
          width: isActive ? 20 : 6,
          height: 6,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            color: isActive
                ? AppColors.brandPink
                : Colors.white.withValues(alpha: 0.25),
          ),
        );
      }),
    );
  }
}
