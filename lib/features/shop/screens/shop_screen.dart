import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/gradient_scaffold.dart';

/// Demo-only Shop screen — opened from the Home screen SHOP button.
///
/// Three sections:
///   1. Earn Free  — watch ads for Icebreakers or Live Sessions
///   2. One-Time Packs — a la carte purchases
///   3. Best Value / Bundle — featured hero bundle
///
/// No real payment wiring. Buttons show a "coming soon" snackbar.
class ShopScreen extends StatelessWidget {
  const ShopScreen({super.key});

  void _mockPurchase(BuildContext context, String item) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$item — purchase flow coming soon.',
          style: AppTextStyles.caption.copyWith(color: Colors.white),
        ),
        backgroundColor: AppColors.bgElevated,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _mockWatch(BuildContext context, String reward) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Ad would play here → $reward (demo).',
          style: AppTextStyles.caption.copyWith(color: Colors.white),
        ),
        backgroundColor: AppColors.bgElevated,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      ),
    );
  }

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
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 56),
          children: [
            // Subheader
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 28),
              child: Text(
                'Power up your Icebreaker experience',
                style: AppTextStyles.bodyS.copyWith(
                  color: AppColors.textMuted,
                ),
                textAlign: TextAlign.center,
              ),
            ),

            // ── Section 1: Earn Free ──────────────────────────────────────
            _SectionLabel('Earn Free'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _EarnCard(
                    iconColor: AppColors.brandCyan,
                    icon: Icons.ac_unit_rounded,
                    reward: '1 Icebreaker 🧊',
                    onTap: () =>
                        _mockWatch(context, '1 Icebreaker'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _EarnCard(
                    iconColor: AppColors.brandPink,
                    icon: Icons.favorite_rounded,
                    reward: '1 Live Session',
                    onTap: () =>
                        _mockWatch(context, '1 Live Session'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 32),

            // ── Section 2: One-Time Packs ─────────────────────────────────
            _SectionLabel('One-Time Packs'),
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
                  _PackRow(
                    icon: Icons.ac_unit_rounded,
                    gradient: const LinearGradient(
                      colors: [AppColors.brandCyan, AppColors.brandPurple],
                    ),
                    title: '5 Icebreakers',
                    emoji: '🧊',
                    price: r'$2.99',
                    onTap: () =>
                        _mockPurchase(context, '5 Icebreakers'),
                  ),
                  const _RowDivider(),
                  _PackRow(
                    icon: Icons.ac_unit_rounded,
                    gradient: const LinearGradient(
                      colors: [AppColors.brandCyan, AppColors.brandPurple],
                    ),
                    title: '10 Icebreakers',
                    emoji: '🧊',
                    price: r'$4.99',
                    onTap: () =>
                        _mockPurchase(context, '10 Icebreakers'),
                  ),
                  const _RowDivider(),
                  _PackRow(
                    icon: Icons.favorite_rounded,
                    gradient: AppColors.brandGradient as LinearGradient,
                    title: '5 Live Sessions',
                    emoji: '⚡',
                    price: r'$4.99',
                    onTap: () =>
                        _mockPurchase(context, '5 Live Sessions'),
                  ),
                  const _RowDivider(),
                  _PackRow(
                    icon: Icons.favorite_rounded,
                    gradient: AppColors.brandGradient as LinearGradient,
                    title: '10 Live Sessions',
                    emoji: '⚡',
                    price: r'$8.99',
                    onTap: () =>
                        _mockPurchase(context, '10 Live Sessions'),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // ── Section 3: Best Value Bundle ──────────────────────────────
            _SectionLabel('Best Value'),
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
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(text.toUpperCase(), style: AppTextStyles.overline),
    );
  }
}

// ── Earn card ─────────────────────────────────────────────────────────────────

class _EarnCard extends StatelessWidget {
  const _EarnCard({
    required this.icon,
    required this.iconColor,
    required this.reward,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String reward;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: iconColor.withValues(alpha: 0.12),
              border: Border.all(
                color: iconColor.withValues(alpha: 0.25),
                width: 1,
              ),
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(height: 10),
          Text(
            'Watch an Ad',
            style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 3),
          Text(
            'Get $reward',
            style: AppTextStyles.caption,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
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
    required this.icon,
    required this.gradient,
    required this.title,
    required this.emoji,
    required this.price,
    required this.onTap,
  });

  final IconData icon;
  final LinearGradient gradient;
  final String title;
  final String emoji;
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
            // Icon badge
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
            // Title
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
                  Text('One-time purchase', style: AppTextStyles.caption),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Price + buy
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  price,
                  style: AppTextStyles.body
                      .copyWith(fontWeight: FontWeight.w700),
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

// ── Row divider ───────────────────────────────────────────────────────────────

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16),
      child: Divider(height: 1, color: AppColors.divider),
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
          // "BEST VALUE" badge
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.30),
              ),
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
