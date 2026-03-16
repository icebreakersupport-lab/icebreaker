import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/gradient_scaffold.dart';

// ── File-level gradient constants ─────────────────────────────────────────────

const _kIceGradient = LinearGradient(
  colors: [AppColors.brandCyan, AppColors.brandPurple],
);

const _kSessionGradient = LinearGradient(
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
  colors: [AppColors.brandPink, AppColors.brandPurple],
);

const _kGoldGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFFFFBE3C), Color(0xFFE07000)],
);

/// Demo-only Shop screen — opened from the Home screen SHOP button.
///
/// Sections:
///   1. Earn Free      — watch ads; 2 ads → 1 Icebreaker, 1 ad → 1 Live Session
///   2. One-Time Packs — singles + multi-packs for both item types
///   3. Subscriptions  — auto-rotating 10-second carousel (Plus / Gold)
///   4. Best Value     — featured bundle card
///
/// No real payment wiring. All CTAs show a floating demo snackbar.
class ShopScreen extends StatelessWidget {
  const ShopScreen({super.key});

  // ── Snackbar helpers ────────────────────────────────────────────────────

  void _mockPurchase(BuildContext context, String item) {
    ScaffoldMessenger.of(context).showSnackBar(_snack(
      '$item — purchase flow coming soon.',
    ));
  }

  void _mockWatch(BuildContext context, String reward) {
    ScaffoldMessenger.of(context).showSnackBar(_snack(
      'Ad would play here → $reward (demo).',
    ));
  }

  void _mockSubscribe(BuildContext context, String plan) {
    ScaffoldMessenger.of(context).showSnackBar(_snack(
      '$plan subscription — billing coming soon.',
    ));
  }

  SnackBar _snack(String message) => SnackBar(
        content: Text(
          message,
          style: AppTextStyles.caption.copyWith(color: Colors.white),
        ),
        backgroundColor: AppColors.bgElevated,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      );

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      showTopGlow: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: AppColors.textSecondary,
            size: 20,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Shop', style: AppTextStyles.h3),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 60),
          children: [
            // Subheader
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 28),
              child: Text(
                'Power up your Icebreaker experience',
                style:
                    AppTextStyles.bodyS.copyWith(color: AppColors.textMuted),
                textAlign: TextAlign.center,
              ),
            ),

            // ── Section 1: Earn Free ──────────────────────────────────────
            const _SectionLabel('Earn Free'),
            const SizedBox(height: 12),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Icebreaker earn — 2 ads required
                  Expanded(
                    child: _EarnCard(
                      iconColor: AppColors.brandCyan,
                      icon: Icons.ac_unit_rounded,
                      reward: '1 Icebreaker 🧊',
                      adsRequired: 2,
                      onTap: () => _mockWatch(context, '1 Icebreaker'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Live session earn — 1 ad
                  Expanded(
                    child: _EarnCard(
                      iconColor: AppColors.brandPink,
                      icon: Icons.favorite_rounded,
                      reward: '1 Live Session',
                      adsRequired: 1,
                      onTap: () => _mockWatch(context, '1 Live Session'),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // ── Section 2: One-Time Packs ─────────────────────────────────
            const _SectionLabel('One-Time Packs'),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: AppColors.bgSurface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.divider),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  // ── Icebreakers ──────────────────────────────────────
                  _PackRow(
                    gradient: _kIceGradient,
                    emoji: '🧊',
                    title: '1 Icebreaker',
                    subtitle: 'Single use',
                    price: r'$0.99',
                    onTap: () => _mockPurchase(context, '1 Icebreaker'),
                  ),
                  const _RowDivider(),
                  _PackRow(
                    gradient: _kIceGradient,
                    emoji: '🧊',
                    title: '5 Icebreakers',
                    subtitle: 'One-time purchase',
                    price: r'$2.99',
                    onTap: () => _mockPurchase(context, '5 Icebreakers'),
                  ),
                  const _RowDivider(),
                  _PackRow(
                    gradient: _kIceGradient,
                    emoji: '🧊',
                    title: '10 Icebreakers',
                    subtitle: 'One-time purchase',
                    price: r'$4.99',
                    onTap: () => _mockPurchase(context, '10 Icebreakers'),
                  ),
                  // ── Group break ──────────────────────────────────────
                  const _GroupDivider(),
                  // ── Live sessions ────────────────────────────────────
                  _PackRow(
                    gradient: _kSessionGradient,
                    emoji: '⚡',
                    title: '1 Live Session',
                    subtitle: 'Single use',
                    price: r'$0.99',
                    onTap: () => _mockPurchase(context, '1 Live Session'),
                  ),
                  const _RowDivider(),
                  _PackRow(
                    gradient: _kSessionGradient,
                    emoji: '⚡',
                    title: '5 Live Sessions',
                    subtitle: 'One-time purchase',
                    price: r'$4.99',
                    onTap: () => _mockPurchase(context, '5 Live Sessions'),
                  ),
                  const _RowDivider(),
                  _PackRow(
                    gradient: _kSessionGradient,
                    emoji: '⚡',
                    title: '10 Live Sessions',
                    subtitle: 'One-time purchase',
                    price: r'$8.99',
                    onTap: () => _mockPurchase(context, '10 Live Sessions'),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // ── Section 3: Subscriptions (auto-rotating carousel) ─────────
            const _SectionLabel('Subscriptions'),
            const SizedBox(height: 12),
            _SubscriptionCarousel(
              onSubscribe: (plan) => _mockSubscribe(context, plan),
            ),

            const SizedBox(height: 32),

            // ── Section 4: Best Value Bundle ──────────────────────────────
            const _SectionLabel('Best Value'),
            const SizedBox(height: 12),
            _BundleCard(
              onTap: () => _mockPurchase(
                  context, '5 Icebreakers + 5 Live Sessions'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Section label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text(text.toUpperCase(), style: AppTextStyles.overline),
      );
}

// ── Earn card ─────────────────────────────────────────────────────────────────

/// [adsRequired] controls the number of ad-step dots shown and the title copy.
/// When 2, the card clearly communicates that 2 separate ads are required.
class _EarnCard extends StatelessWidget {
  const _EarnCard({
    required this.icon,
    required this.iconColor,
    required this.reward,
    required this.adsRequired,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String reward;
  final int adsRequired;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final titleText =
        adsRequired > 1 ? 'Watch $adsRequired Ads' : 'Watch an Ad';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          // Icon circle
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: iconColor.withValues(alpha: 0.12),
              border: Border.all(
                color: iconColor.withValues(alpha: 0.25),
              ),
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),

          const SizedBox(height: 10),

          // Title — "Watch an Ad" or "Watch 2 Ads"
          Text(
            titleText,
            style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 3),

          // Reward label
          Text(
            'Get $reward',
            style: AppTextStyles.caption,
            textAlign: TextAlign.center,
          ),

          // Ad-step dots — only shown when > 1 ad required
          if (adsRequired > 1) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (int i = 0; i < adsRequired; i++) ...[
                  if (i > 0) const SizedBox(width: 5),
                  Icon(
                    Icons.play_circle_filled_rounded,
                    size: 14,
                    color: AppColors.brandCyan
                        .withValues(alpha: i == 0 ? 0.85 : 0.45),
                  ),
                ],
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    '$adsRequired ads required',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textMuted,
                      fontSize: 10,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],

          const Spacer(),
          const SizedBox(height: 14),

          // WATCH button
          GestureDetector(
            onTap: onTap,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.brandCyan.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.brandCyan.withValues(alpha: 0.35),
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                'WATCH',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.brandCyan,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Pack row ──────────────────────────────────────────────────────────────────

class _PackRow extends StatelessWidget {
  const _PackRow({
    required this.gradient,
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.price,
    required this.onTap,
  });

  final LinearGradient gradient;
  final String emoji;
  final String title;
  final String subtitle;
  final String price;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // Emoji badge
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: gradient,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Text(emoji, style: const TextStyle(fontSize: 18)),
            ),
            const SizedBox(width: 14),
            // Title + subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTextStyles.body
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle, style: AppTextStyles.caption),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Price + BUY pill
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  price,
                  style:
                      AppTextStyles.body.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 5),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: AppColors.brandGradient,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'BUY',
                    style: AppTextStyles.caption.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Row dividers ──────────────────────────────────────────────────────────────

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Divider(height: 1, color: AppColors.divider),
      );
}

/// Heavier divider between item-type groups inside the packs card.
class _GroupDivider extends StatelessWidget {
  const _GroupDivider();

  @override
  Widget build(BuildContext context) => Container(
        height: 1,
        margin: const EdgeInsets.symmetric(vertical: 4),
        color: AppColors.navBorder,
      );
}

// ── Subscription carousel ─────────────────────────────────────────────────────

/// Auto-rotates between Plus and Gold plan cards every 10 seconds.
/// Manual swipes reset the timer so the next auto-advance is always
/// 10 seconds after the last interaction.
class _SubscriptionCarousel extends StatefulWidget {
  const _SubscriptionCarousel({required this.onSubscribe});

  final void Function(String plan) onSubscribe;

  @override
  State<_SubscriptionCarousel> createState() =>
      _SubscriptionCarouselState();
}

class _SubscriptionCarouselState extends State<_SubscriptionCarousel> {
  late final PageController _pageController;
  Timer? _timer;
  int _currentPage = 0;

  static const int _pageCount = 2;
  static const Duration _autoAdvance = Duration(seconds: 10);

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_autoAdvance, (_) {
      if (!mounted) return;
      final next = (_currentPage + 1) % _pageCount;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
      );
    });
  }

  void _onPageChanged(int page) {
    setState(() => _currentPage = page);
    // Reset timer so auto-advance is always 10 s after last interaction.
    _startTimer();
  }

  @override
  Widget build(BuildContext context) {
    final carouselH = (MediaQuery.of(context).size.height * 0.32)
        .clamp(244.0, 290.0);
    return Column(
      children: [
        SizedBox(
          height: carouselH,
          child: PageView(
            controller: _pageController,
            onPageChanged: _onPageChanged,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: _PlusPlanCard(
                  onTap: () => widget.onSubscribe('Plus'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: _GoldPlanCard(
                  onTap: () => widget.onSubscribe('Gold'),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // Page indicator
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_pageCount, (i) {
            final active = i == _currentPage;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: active ? 20 : 6,
              height: 6,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                color: active
                    ? AppColors.brandPink
                    : AppColors.textMuted.withValues(alpha: 0.4),
              ),
            );
          }),
        ),
      ],
    );
  }
}

// ── Plus plan card ────────────────────────────────────────────────────────────

class _PlusPlanCard extends StatelessWidget {
  const _PlusPlanCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: AppColors.brandPurple.withValues(alpha: 0.50),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandPurple.withValues(alpha: 0.18),
            blurRadius: 24,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Plus', style: AppTextStyles.h2),
                    const SizedBox(height: 2),
                    Text(
                      r'$4.99 / month · 10 Icebreakers/day',
                      style: AppTextStyles.bodyS.copyWith(
                        color: AppColors.brandCyan,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.brandPurple.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.brandPurple.withValues(alpha: 0.35),
                  ),
                ),
                child: Text(
                  'PLUS',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.brandPurple,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Features
          _Feature('Unlimited Go Live'),
          const SizedBox(height: 6),
          _Feature('10 Icebreakers per day'),

          const Spacer(),

          // CTA
          GestureDetector(
            onTap: onTap,
            child: Container(
              width: double.infinity,
              height: 44,
              decoration: BoxDecoration(
                gradient: AppColors.brandGradient,
                borderRadius: BorderRadius.circular(22),
              ),
              alignment: Alignment.center,
              child: Text(
                'Subscribe',
                style: AppTextStyles.button.copyWith(
                  color: Colors.white,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Gold plan card ────────────────────────────────────────────────────────────

class _GoldPlanCard extends StatelessWidget {
  const _GoldPlanCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: _kGoldGradient,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFBE3C).withValues(alpha: 0.38),
            blurRadius: 28,
            spreadRadius: 0,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: const Color(0xFFE07000).withValues(alpha: 0.22),
            blurRadius: 48,
            spreadRadius: 4,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Gold', style: AppTextStyles.h2),
                    const SizedBox(height: 2),
                    Text(
                      r'$9.99 / month',
                      style: AppTextStyles.bodyS.copyWith(
                        color: Colors.white.withValues(alpha: 0.80),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.35),
                  ),
                ),
                child: Text(
                  'MOST POPULAR',
                  style: AppTextStyles.caption.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Features
          _Feature('Unlimited Go Live', bright: true),
          const SizedBox(height: 6),
          _Feature('Unlimited Icebreakers', bright: true),
          const SizedBox(height: 6),
          _Feature('Priority in Explore carousel', bright: true),

          const Spacer(),

          // CTA
          GestureDetector(
            onTap: onTap,
            child: Container(
              width: double.infinity,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                'Go Gold',
                style: AppTextStyles.button.copyWith(
                  color: const Color(0xFFE07000),
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Feature row ───────────────────────────────────────────────────────────────

class _Feature extends StatelessWidget {
  const _Feature(this.text, {this.bright = false});
  final String text;
  final bool bright;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          Icons.check_rounded,
          size: 15,
          color: bright
              ? Colors.white.withValues(alpha: 0.90)
              : AppColors.success,
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            style: AppTextStyles.bodyS.copyWith(
              color: bright
                  ? Colors.white.withValues(alpha: 0.85)
                  : AppColors.textSecondary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ── Bundle card ───────────────────────────────────────────────────────────────

class _BundleCard extends StatelessWidget {
  const _BundleCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: AppColors.brandGradientDiagonal,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandPink.withValues(alpha: 0.40),
            blurRadius: 28,
            spreadRadius: 0,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: AppColors.brandPurple.withValues(alpha: 0.30),
            blurRadius: 48,
            spreadRadius: 4,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: Colors.white.withValues(alpha: 0.30)),
            ),
            child: Text(
              'BEST VALUE',
              style: AppTextStyles.caption.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
              ),
            ),
          ),

          const SizedBox(height: 16),

          Text(
            '5 Icebreakers + 5 Live Sessions',
            style: AppTextStyles.h2.copyWith(height: 1.25),
          ),

          const SizedBox(height: 6),

          Text(
            'Everything you need to break the ice.',
            style: AppTextStyles.bodyS.copyWith(
              color: Colors.white.withValues(alpha: 0.72),
            ),
          ),

          const SizedBox(height: 22),

          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                r'$6.99',
                style: AppTextStyles.h1.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'one-time',
                style: AppTextStyles.caption.copyWith(
                  color: Colors.white.withValues(alpha: 0.65),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          GestureDetector(
            onTap: onTap,
            child: Container(
              width: double.infinity,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(26),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                'GET THE BUNDLE',
                style: AppTextStyles.buttonL.copyWith(
                  color: AppColors.brandPink,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
