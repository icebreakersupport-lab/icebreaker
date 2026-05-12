import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/product_catalog.dart';
import '../../../core/services/ad_service.dart';
import '../../../core/services/billing_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/gradient_scaffold.dart';

const Duration _kAdRewardCooldown = Duration(hours: 24);

// ── File-level gradient constants ─────────────────────────────────────────────

const _kGoldGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFFFFBE3C), Color(0xFFE07000)],
);

/// Shop screen — opened from the Home screen SHOP button.
///
/// Sections:
///   1. Earn Free      — watch ads; 1 ad → 1 Icebreaker, 2 ads → 1 Live Session
///                       (still placeholder — rewarded ads ship in a later phase)
///   2. One-Time Packs — singles + multi-packs for both item types
///                       (wired to `BillingService` → store → `redeemPurchase` CF)
///   3. Subscriptions  — auto-rotating 10-second carousel (Plus / Gold)
///                       (still placeholder — subscriptions ship in a later phase)
///   4. Best Value     — featured bundle card (wired to BillingService)
class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  BillingService get _billing => BillingService.instance;

  /// Server-side ad reward state, mirrored from `users/{uid}.adProgress`.
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSub;
  DateTime? _iceLastGrantedAt;
  DateTime? _liveLastGrantedAt;
  int _liveTowardCredit = 0;
  Timer? _cooldownTicker;

  @override
  void initState() {
    super.initState();
    _billing.addListener(_onBillingChanged);
    // Cold-open guard: if products didn't finish loading at app start
    // (no network, store unavailable on first try), kick off a refresh
    // when the user actually reaches the Shop.
    if (_billing.isAvailable && _billing.products.isEmpty) {
      _billing.reloadProducts();
    }
    if (kRewardedAdsEnabled) {
      _subscribeAdProgress();
      // Rebuild once a minute so the "back in Xh Ym" countdown stays current
      // without the user pulling to refresh.
      _cooldownTicker =
          Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _billing.removeListener(_onBillingChanged);
    _userSub?.cancel();
    _cooldownTicker?.cancel();
    super.dispose();
  }

  void _subscribeAdProgress() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _userSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final data = snap.data();
      final adProgress = (data?['adProgress'] as Map?)?.cast<String, dynamic>();
      final ice = (adProgress?['icebreaker'] as Map?)?.cast<String, dynamic>();
      final live = (adProgress?['liveSession'] as Map?)?.cast<String, dynamic>();
      setState(() {
        _iceLastGrantedAt = (ice?['lastGrantedAt'] as Timestamp?)?.toDate();
        _liveLastGrantedAt = (live?['lastGrantedAt'] as Timestamp?)?.toDate();
        _liveTowardCredit = (live?['towardCredit'] as num?)?.toInt() ?? 0;
      });
    });
  }

  Duration? _cooldownRemaining(DateTime? lastGrantedAt) {
    if (lastGrantedAt == null) return null;
    final remaining =
        _kAdRewardCooldown - DateTime.now().difference(lastGrantedAt);
    return remaining.isNegative ? null : remaining;
  }

  void _onBillingChanged() {
    if (!mounted) return;
    final success = _billing.lastSuccessProductId;
    if (success != null) {
      final def = ProductCatalog.byId(success);
      final label = def?.title ?? success;
      _showSnack('$label added to your account.');
      _billing.clearLastSuccess();
    }
    final err = _billing.lastError;
    if (err != null && err.isNotEmpty) {
      _showSnack(err);
      _billing.clearLastError();
    }
    setState(() {});
  }

  void _buy(String productId) {
    if (!_billing.isAvailable) {
      _showSnack('Store is unavailable. Please try again later.');
      return;
    }
    if (_billing.products[productId] == null) {
      _showSnack('Product not loaded yet. Pull to refresh and try again.');
      return;
    }
    _billing.buy(productId);
  }

  Future<void> _onRefresh() => _billing.reloadProducts();

  Future<void> _restore() async {
    await _billing.restore();
    if (!mounted) return;
    _showSnack('Checking for past purchases…');
  }

  /// Tracks which reward type is currently mid-watch so the UI can show a
  /// spinner on the tapped card and ignore re-taps until the show resolves.
  RewardType? _watchingType;

  Future<void> _watchAdFor(RewardType type) async {
    if (_watchingType != null) return; // re-tap guard
    setState(() => _watchingType = type);
    try {
      final result = await AdService.instance.showRewarded(type);
      if (!mounted) return;
      switch (result.status) {
        case AdShowStatus.success:
          if (result.granted) {
            final label = type == RewardType.icebreaker
                ? '1 Icebreaker'
                : '1 Live Session';
            _showSnack('$label added to your account.');
          } else {
            final p = result.progress ?? 0;
            final r = result.required ?? 2;
            _showSnack('Watched $p of $r — one more ad to earn the reward.');
          }
          break;
        case AdShowStatus.dismissed:
          _showSnack('Ad closed before reward — try again to earn credit.');
          break;
        case AdShowStatus.notReady:
          _showSnack('Ad still loading. Please try again in a moment.');
          break;
        case AdShowStatus.failedToShow:
          _showSnack('Ad failed to play. Try again shortly.');
          break;
        case AdShowStatus.cooldown:
          _showSnack(
            result.errorMessage ??
                'Already claimed today — come back tomorrow.',
          );
          break;
        case AdShowStatus.error:
          _showSnack('Reward could not be granted. Please try again.');
          break;
      }
    } finally {
      if (mounted) setState(() => _watchingType = null);
    }
  }

  void _mockSubscribe(BuildContext context, String plan) {
    _showSnack('$plan subscription — billing coming soon.');
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
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

  String _priceFor(String productId) {
    final ProductDetails? details = _billing.products[productId];
    if (details != null) return details.price;
    return ProductCatalog.byId(productId)?.displayPrice ?? '';
  }

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
        actions: [
          if (_billing.isAvailable)
            TextButton(
              onPressed: _restore,
              child: Text(
                'Restore',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.brandCyan,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _onRefresh,
          color: AppColors.brandPink,
          backgroundColor: AppColors.bgSurface,
          child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
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
            if (kRewardedAdsEnabled) ...[
              const _SectionLabel('Earn Free'),
              const SizedBox(height: 12),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _EarnCard(
                        iconColor: AppColors.brandPink,
                        icon: Icons.favorite_rounded,
                        rewardLabel: 'Icebreaker',
                        adsRequired: 1,
                        currentStep: 0,
                        cooldownRemaining:
                            _cooldownRemaining(_iceLastGrantedAt),
                        isLoading: _watchingType == RewardType.icebreaker,
                        onTap: () => _watchAdFor(RewardType.icebreaker),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _EarnCard(
                        iconColor: AppColors.brandCyan,
                        icon: Icons.bolt_rounded,
                        rewardLabel: 'Live Session',
                        adsRequired: 2,
                        currentStep: _liveTowardCredit,
                        cooldownRemaining:
                            _cooldownRemaining(_liveLastGrantedAt),
                        isLoading: _watchingType == RewardType.liveSession,
                        onTap: () => _watchAdFor(RewardType.liveSession),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
            ],

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
                    iconColor: AppColors.brandPink,
                    icon: Icons.favorite_rounded,
                    title: '1 Icebreaker',
                    subtitle: 'Single use',
                    price: _priceFor(ProductCatalog.icebreakers1.productId),
                    isPurchasing: _billing.isPurchasing(
                        ProductCatalog.icebreakers1.productId),
                    onTap: () =>
                        _buy(ProductCatalog.icebreakers1.productId),
                  ),
                  const _RowDivider(),
                  _PackRow(
                    iconColor: AppColors.brandPink,
                    icon: Icons.favorite_rounded,
                    title: '5 Icebreakers',
                    subtitle: 'One-time purchase',
                    price: _priceFor(ProductCatalog.icebreakers5.productId),
                    isPurchasing: _billing.isPurchasing(
                        ProductCatalog.icebreakers5.productId),
                    onTap: () =>
                        _buy(ProductCatalog.icebreakers5.productId),
                  ),
                  const _RowDivider(),
                  _PackRow(
                    iconColor: AppColors.brandPink,
                    icon: Icons.favorite_rounded,
                    title: '10 Icebreakers',
                    subtitle: 'One-time purchase',
                    price: _priceFor(ProductCatalog.icebreakers10.productId),
                    isPurchasing: _billing.isPurchasing(
                        ProductCatalog.icebreakers10.productId),
                    onTap: () =>
                        _buy(ProductCatalog.icebreakers10.productId),
                  ),
                  // ── Group break ──────────────────────────────────────
                  const _GroupDivider(),
                  // ── Live sessions ────────────────────────────────────
                  _PackRow(
                    iconColor: AppColors.brandCyan,
                    icon: Icons.bolt_rounded,
                    title: '1 Live Session',
                    subtitle: 'Single use',
                    price: _priceFor(ProductCatalog.live1.productId),
                    isPurchasing:
                        _billing.isPurchasing(ProductCatalog.live1.productId),
                    onTap: () => _buy(ProductCatalog.live1.productId),
                  ),
                  const _RowDivider(),
                  _PackRow(
                    iconColor: AppColors.brandCyan,
                    icon: Icons.bolt_rounded,
                    title: '5 Live Sessions',
                    subtitle: 'One-time purchase',
                    price: _priceFor(ProductCatalog.live5.productId),
                    isPurchasing:
                        _billing.isPurchasing(ProductCatalog.live5.productId),
                    onTap: () => _buy(ProductCatalog.live5.productId),
                  ),
                  const _RowDivider(),
                  _PackRow(
                    iconColor: AppColors.brandCyan,
                    icon: Icons.bolt_rounded,
                    title: '10 Live Sessions',
                    subtitle: 'One-time purchase',
                    price: _priceFor(ProductCatalog.live10.productId),
                    isPurchasing:
                        _billing.isPurchasing(ProductCatalog.live10.productId),
                    onTap: () => _buy(ProductCatalog.live10.productId),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // ── Section 3: Subscriptions (auto-rotating carousel) ─────────
            if (kSubscriptionsEnabled) ...[
              const _SectionLabel('Subscriptions'),
              const SizedBox(height: 12),
              _SubscriptionCarousel(
                onSubscribe: (plan) => _mockSubscribe(context, plan),
              ),
              const SizedBox(height: 32),
            ],

            // ── Section 4: Best Value Bundle ──────────────────────────────
            const _SectionLabel('Best Value'),
            const SizedBox(height: 12),
            _BundleCard(
              price: _priceFor(ProductCatalog.bundle55.productId),
              isPurchasing:
                  _billing.isPurchasing(ProductCatalog.bundle55.productId),
              onTap: () => _buy(ProductCatalog.bundle55.productId),
            ),
          ],
        ),
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

/// Renders one rewarded-ad offer in the "Earn Free" section.
///
/// Drives three visual states off three inputs:
///   - [currentStep] — ads already watched in this 24h cycle (0..adsRequired-1).
///                     For [adsRequired]==1 this is always 0; for ==2 it lets
///                     the card show "1 of 2 watched" mid-flow.
///   - [cooldownRemaining] — non-null while the reward is locked out for the
///                     current 24h window. Renders a muted "Claimed" state
///                     with a countdown subtitle, replacing the CTA.
///   - [isLoading]   — a watch is in flight; CTA shows a spinner.
///
/// Visually the card grades down (icon + content opacity) when in cooldown
/// so the active card on the row visibly stands out.
class _EarnCard extends StatelessWidget {
  const _EarnCard({
    required this.icon,
    required this.iconColor,
    required this.rewardLabel,
    required this.adsRequired,
    required this.currentStep,
    required this.cooldownRemaining,
    required this.onTap,
    this.isLoading = false,
  });

  final IconData icon;
  final Color iconColor;

  /// Display name of the reward, e.g. "Icebreaker" / "Live Session".
  final String rewardLabel;

  /// How many ad watches are needed for one credit (1 or 2).
  final int adsRequired;

  /// Ad watches already completed in the current 24h cycle.
  final int currentStep;

  /// If non-null, the reward is on cooldown and this Duration is how long
  /// until the user can claim again.
  final Duration? cooldownRemaining;

  final VoidCallback onTap;
  final bool isLoading;

  bool get _isCooldown => cooldownRemaining != null;

  String get _statusLine {
    if (_isCooldown) return 'Available in ${_formatRemaining(cooldownRemaining!)}';
    if (adsRequired == 1) return 'Watch 1 ad · 1 per day';
    if (currentStep == 0) return 'Watch 2 ads · 1 per day';
    return '1 more ad to earn';
  }

  String get _ctaLabel {
    if (adsRequired == 1) return 'WATCH AD';
    return 'WATCH AD ${currentStep + 1} OF $adsRequired';
  }

  static String _formatRemaining(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h >= 1) return '${h}h ${m}m';
    if (m >= 1) return '${m}m';
    return '<1m';
  }

  @override
  Widget build(BuildContext context) {
    final contentOpacity = _isCooldown ? 0.55 : 1.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          Opacity(
            opacity: contentOpacity,
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: iconColor.withValues(alpha: 0.32),
                  width: 1.2,
                ),
              ),
              child: Icon(icon, color: iconColor, size: 26),
            ),
          ),

          const SizedBox(height: 10),

          Opacity(
            opacity: contentOpacity,
            child: Text(
              'Get 1 $rewardLabel',
              style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
          ),

          if (adsRequired > 1) ...[
            const SizedBox(height: 10),
            // Filled-dot progress: solid for watched, hollow for remaining.
            // Clearly communicates "this is a 2-step earn flow."
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (int i = 0; i < adsRequired; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  _StepDot(
                    filled: i < currentStep || _isCooldown,
                    color: iconColor,
                  ),
                ],
              ],
            ),
          ],

          const SizedBox(height: 8),
          Text(
            _statusLine,
            style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
            textAlign: TextAlign.center,
          ),

          const Spacer(),
          const SizedBox(height: 14),

          if (_isCooldown)
            // Muted "claimed" pill — visually distinct from the active CTA
            // so the user can tell at a glance which card is interactive.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.textMuted.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.textMuted.withValues(alpha: 0.18),
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                'CLAIMED TODAY',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
            )
          else
            GestureDetector(
              onTap: isLoading ? null : onTap,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.brandCyan
                      .withValues(alpha: isLoading ? 0.05 : 0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.brandCyan
                        .withValues(alpha: isLoading ? 0.18 : 0.35),
                  ),
                ),
                alignment: Alignment.center,
                child: isLoading
                    ? SizedBox(
                        height: 14,
                        width: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AppColors.brandCyan,
                          ),
                        ),
                      )
                    : Text(
                        _ctaLabel,
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

class _StepDot extends StatelessWidget {
  const _StepDot({required this.filled, required this.color});
  final bool filled;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: filled ? color : Colors.transparent,
          border: Border.all(
            color: color.withValues(alpha: filled ? 1.0 : 0.45),
            width: 1.5,
          ),
        ),
      );
}

// ── Pack row ──────────────────────────────────────────────────────────────────

class _PackRow extends StatelessWidget {
  const _PackRow({
    required this.iconColor,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.price,
    required this.onTap,
    this.isPurchasing = false,
  });

  final Color iconColor;
  final IconData icon;
  final String title;
  final String subtitle;
  final String price;
  final VoidCallback onTap;
  final bool isPurchasing;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isPurchasing ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // Branded icon badge — same recipe as the top earn card,
            // sized for the pack-row scale: alpha-tinted fill + tinted
            // border + accent icon centered at a 1:2 icon-to-badge ratio.
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: iconColor.withValues(alpha: 0.32),
                ),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: iconColor, size: 20),
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
                  child: isPurchasing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Text(
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
  const _BundleCard({
    required this.onTap,
    required this.price,
    this.isPurchasing = false,
  });
  final VoidCallback onTap;
  final String price;
  final bool isPurchasing;

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
                price,
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
            onTap: isPurchasing ? null : onTap,
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
              child: isPurchasing
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        valueColor: AlwaysStoppedAnimation<Color>(
                            AppColors.brandPink),
                      ),
                    )
                  : Text(
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
