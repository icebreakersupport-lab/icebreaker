import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/icebreaker_logo.dart';

/// Onboarding final step — 7-slide product walkthrough.
///
/// Each slide contains a mock panel that visually mirrors the real
/// app screen it describes, using the same color tokens, card shapes,
/// and layout patterns as the production UI.
///
/// Swipeable PageView + Next tap. Skip and "Let's Go" route to /home.
class OnboardingSlideshowScreen extends StatefulWidget {
  const OnboardingSlideshowScreen({super.key});

  @override
  State<OnboardingSlideshowScreen> createState() =>
      _OnboardingSlideshowScreenState();
}

class _OnboardingSlideshowScreenState extends State<OnboardingSlideshowScreen> {
  final _controller = PageController();
  int _current = 0;

  bool get _isLast => _current == _slides.length - 1;

  void _next() {
    if (_isLast) {
      _finish();
    } else {
      _controller.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _finish() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get();

        final photoUrls = (doc.data()?['photoUrls'] as List?)?.cast<String>() ?? [];
        if (photoUrls.isEmpty) {
          // Photo wasn't saved — go back to photo screen instead of marking
          // the profile complete without a real photo on record.
          // ignore: avoid_print
          print('[Onboarding/Slideshow] ⚠️ no photoUrls — redirecting to photo screen');
          if (!mounted) return;
          context.go(AppRoutes.onboardingPhoto);
          return;
        }

        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .set({'profileComplete': true}, SetOptions(merge: true));
        // ignore: avoid_print
        print('[Onboarding/Slideshow] ✅ profileComplete=true written for $uid');
      } on FirebaseException catch (e) {
        // ignore: avoid_print
        print('[Onboarding/Slideshow] ⚠️ Firestore error: ${e.code}');
        // Non-fatal: proceed to home. The flag will be corrected on next sign-in
        // once the photo check passes.
      }
    }
    if (!mounted) return;
    context.go(AppRoutes.home);
  }

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
            // ── Top bar ───────────────────────────────────────────────────────
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              child: Row(
                children: [
                  _DotIndicator(count: _slides.length, current: _current),
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
                            color: Colors.white.withValues(alpha: 0.42),
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
                onPageChanged: (i) => setState(() => _current = i),
                itemBuilder: (_, i) => _SlideView(data: _slides[i]),
              ),
            ),

            // ── CTA button ───────────────────────────────────────────────────
            Padding(
              padding: EdgeInsets.fromLTRB(
                24,
                12,
                24,
                MediaQuery.paddingOf(context).bottom + 24,
              ),
              child: GestureDetector(
                onTap: _next,
                child: Container(
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
// Slide data + list
// ─────────────────────────────────────────────────────────────────────────────

class _SlideData {
  const _SlideData({
    required this.index,
    required this.accentColor,
    required this.tag,
    required this.headline,
    required this.body,
  });

  final int index;
  final Color accentColor;
  final String tag;
  final String headline;
  final String body;
}

const _slides = [
  _SlideData(
    index: 0,
    accentColor: AppColors.brandPink,
    tag: 'GO LIVE',
    headline: 'Go live when you\'re ready\nto meet people.',
    body:
        'Icebreaker works in real time. Only people who are live nearby can see each other.',
  ),
  _SlideData(
    index: 1,
    accentColor: AppColors.brandPurple,
    tag: 'NEARBY',
    headline: 'See who\'s around\nyou right now.',
    body:
        'Browse people nearby who are also open to meeting in real life.',
  ),
  _SlideData(
    index: 2,
    accentColor: AppColors.brandCyan,
    tag: 'ICEBREAKER',
    headline: 'Make the first move\nwith an Icebreaker.',
    body:
        'Send a quick Icebreaker to someone you want to meet.',
  ),
  _SlideData(
    index: 3,
    accentColor: AppColors.brandPink,
    tag: 'MUTUAL INTEREST',
    headline: 'Only mutual interest\nmoves forward.',
    body:
        'If they accept, you\'ll both know the interest is real before the approach happens.',
  ),
  _SlideData(
    index: 4,
    accentColor: AppColors.brandPurple,
    tag: 'FIND EACH OTHER',
    headline: 'Find each other\nin real life.',
    body:
        'Once it\'s accepted, you\'ll get a shared screen and timer to help you meet in person.',
  ),
  _SlideData(
    index: 5,
    accentColor: AppColors.brandCyan,
    tag: 'CHAT',
    headline: 'Chat unlocks after\nyou actually meet.',
    body:
        'Icebreaker is built to get people off the screen and into real conversations first.',
  ),
  _SlideData(
    index: 6,
    accentColor: AppColors.success,
    tag: 'SAFETY',
    headline: 'Built with\nsafety in mind.',
    body:
        'Live verification, real-time intent, and shared flow help create a safer, more respectful experience.',
  ),
];

// ─────────────────────────────────────────────────────────────────────────────
// _SlideView — layout wrapper for each slide
// ─────────────────────────────────────────────────────────────────────────────

class _SlideView extends StatelessWidget {
  const _SlideView({required this.data});

  final _SlideData data;

  Widget _buildMock() => switch (data.index) {
        0 => const _GoLiveMock(),
        1 => const _NearbyMock(),
        2 => const _SendIcebreakerMock(),
        3 => const _MutualInterestMock(),
        4 => const _FindEachOtherMock(),
        5 => const _ChatUnlocksMock(),
        6 => const _SafetyMock(),
        _ => const SizedBox.shrink(),
      };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 4),

          // ── Mock panel ────────────────────────────────────────────────────
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: _buildMock(),
            ),
          ),

          const SizedBox(height: 24),

          // ── Tag ───────────────────────────────────────────────────────────
          Text(
            data.tag,
            style: AppTextStyles.overline.copyWith(
              color: data.accentColor,
              letterSpacing: 2.5,
            ),
          ),

          const SizedBox(height: 10),

          // ── Headline ──────────────────────────────────────────────────────
          Text(
            data.headline,
            style: AppTextStyles.h2.copyWith(height: 1.25),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 12),

          // ── Body ──────────────────────────────────────────────────────────
          Text(
            data.body,
            style: AppTextStyles.body.copyWith(
              color: AppColors.textSecondary,
              height: 1.6,
            ),
            textAlign: TextAlign.center,
          ),

          const Spacer(),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MOCK PANELS — each mirrors the corresponding real app screen
// ─────────────────────────────────────────────────────────────────────────────

// ── Slide 0: Go Live ─────────────────────────────────────────────────────────
// Mirrors: HomeScreen offline state (logo + GO LIVE button + stat pills)

class _GoLiveMock extends StatelessWidget {
  const _GoLiveMock();

  @override
  Widget build(BuildContext context) {
    return _MockCard(
      accentColor: AppColors.brandPink,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Mini app bar
          const _MockAppBar(
            title: 'icebreaker •',
            trailing: _MiniShopPill(),
          ),
          _divider(),

          // Stat pills row (mirrors HomeScreen _StatusPill)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: _StatPill(
                    icon: Icons.bolt_rounded,
                    label: 'SESSIONS',
                    value: '1',
                    iconColor: AppColors.brandPink,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatPill(
                    icon: Icons.ac_unit_rounded,
                    label: 'ICEBREAKERS',
                    value: '3',
                    iconColor: AppColors.brandCyan,
                  ),
                ),
              ],
            ),
          ),

          // Logo + Go Live CTA
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              children: [
                IcebreakerLogo(
                  size: 64,
                  showGlow: false,
                  ambientGlow: 0.75,
                ),
                const SizedBox(height: 14),
                // GO LIVE gradient pill
                Container(
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: AppColors.brandGradient,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.brandPink.withValues(alpha: 0.40),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.bolt_rounded,
                          color: Colors.white, size: 16),
                      const SizedBox(width: 6),
                      Text('GO LIVE',
                          style: AppTextStyles.button.copyWith(
                              letterSpacing: 1.2)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Slide 1: Nearby Discovery ─────────────────────────────────────────────────
// Mirrors: NearbyScreen — app bar + discovery card with send button

class _NearbyMock extends StatelessWidget {
  const _NearbyMock();

  @override
  Widget build(BuildContext context) {
    return _MockCard(
      accentColor: AppColors.brandPurple,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _MockAppBar(
            title: 'Nearby',
            trailing: Icon(Icons.tune_rounded,
                color: AppColors.textSecondary, size: 16),
          ),
          _divider(),

          Padding(
            padding: const EdgeInsets.all(12),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.bgElevated,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: AppColors.brandPurple.withValues(alpha: 0.30)),
              ),
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Avatar
                  _MockAvatar(
                    initial: 'A',
                    size: 52,
                    colors: [AppColors.brandPurple, AppColors.brandPink],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('Alex, 24',
                                style: AppTextStyles.body.copyWith(
                                    fontWeight: FontWeight.w700)),
                            const Spacer(),
                            Text('12m away',
                                style: AppTextStyles.caption.copyWith(
                                    color: AppColors.brandPurple)),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Up for spontaneous adventures',
                          style: AppTextStyles.bodyS,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        // Send Icebreaker button (cyan, mirrors real button)
                        Container(
                          height: 30,
                          decoration: BoxDecoration(
                            color: AppColors.brandCyan.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(
                                color:
                                    AppColors.brandCyan.withValues(alpha: 0.5),
                                width: 1),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'Send Icebreaker 🧊',
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.brandCyan,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
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

// ── Slide 2: Send Icebreaker ──────────────────────────────────────────────────
// Mirrors: SendIcebreakerScreen — dark bg, cyan-bordered input, Send button

class _SendIcebreakerMock extends StatelessWidget {
  const _SendIcebreakerMock();

  @override
  Widget build(BuildContext context) {
    return _MockCard(
      accentColor: AppColors.brandCyan,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with close icon (mirrors real screen top)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Row(
              children: [
                Icon(Icons.close_rounded,
                    color: Colors.white.withValues(alpha: 0.5), size: 18),
                const Spacer(),
                _MockAvatar(
                  initial: 'J',
                  size: 36,
                  colors: [AppColors.brandCyan, AppColors.brandPurple],
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Jordan, 26',
                        style: AppTextStyles.bodyS.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                    Text('One message · Make it count',
                        style: AppTextStyles.caption),
                  ],
                ),
                const Spacer(),
              ],
            ),
          ),

          const SizedBox(height: 10),
          _divider(),
          const SizedBox(height: 10),

          // Message input (mirrors SendIcebreakerScreen textarea)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.brandCyan.withValues(alpha: 0.45),
                  width: 1.5,
                ),
              ),
              child: Text(
                'Hey, thought I\'d break the ice with you! 🧊',
                style: AppTextStyles.bodyS
                    .copyWith(color: AppColors.textPrimary),
              ),
            ),
          ),

          const SizedBox(height: 10),

          // Cyan Send button (mirrors SendIcebreakerScreen CTA)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.brandCyan,
                borderRadius: BorderRadius.circular(20),
              ),
              alignment: Alignment.center,
              child: Text(
                'Send 🧊',
                style: AppTextStyles.button
                    .copyWith(color: AppColors.textInverse),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Slide 3: Mutual Interest ──────────────────────────────────────────────────
// Mirrors: IcebreakerReceivedScreen — gradient hero, profile pair, message, Pass/Accept

class _MutualInterestMock extends StatelessWidget {
  const _MutualInterestMock();

  @override
  Widget build(BuildContext context) {
    return _MockCard(
      accentColor: AppColors.brandPink,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // "New Icebreaker 🧊" gradient text (mirrors IcebreakerReceivedScreen hero)
            ShaderMask(
              shaderCallback: (bounds) =>
                  AppColors.brandGradient.createShader(bounds),
              child: Text(
                'New Icebreaker 🧊',
                style: AppTextStyles.h3.copyWith(color: Colors.white),
              ),
            ),
            Text(
              'Respond before time runs out.',
              style: AppTextStyles.caption,
            ),

            const SizedBox(height: 14),

            // Profile pair with heart connector (mirrors IcebreakerReceivedScreen)
            _MockProfilePair(
              leftInitial: 'A',
              rightInitial: 'J',
              connector: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppColors.brandGradient,
                ),
                child: const Icon(Icons.favorite_rounded,
                    color: Colors.white, size: 13),
              ),
            ),

            const SizedBox(height: 12),

            // Message bubble (mirrors IcebreakerReceivedScreen message card)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: AppColors.bgElevated,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.divider),
              ),
              child: Row(
                children: [
                  Text('Jordan: ',
                      style: AppTextStyles.bodyS.copyWith(
                          color: AppColors.brandCyan,
                          fontWeight: FontWeight.w600)),
                  Expanded(
                    child: Text(
                      'Hey, thought I\'d break the ice! 🧊',
                      style: AppTextStyles.bodyS,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // Pass / Accept buttons (mirrors IcebreakerReceivedScreen)
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 36,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                          color: AppColors.danger.withValues(alpha: 0.6)),
                      color: AppColors.danger.withValues(alpha: 0.07),
                    ),
                    alignment: Alignment.center,
                    child: Text('Pass',
                        style: AppTextStyles.buttonS
                            .copyWith(color: AppColors.danger)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    height: 36,
                    decoration: BoxDecoration(
                      gradient: AppColors.brandGradient,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    alignment: Alignment.center,
                    child:
                        Text('Accept 🧊', style: AppTextStyles.buttonS),
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

// ── Slide 4: Find Each Other ──────────────────────────────────────────────────
// Mirrors: MatchedScreen — colored ambient bg, profile pair, countdown, "I found them"

class _FindEachOtherMock extends StatelessWidget {
  const _FindEachOtherMock();

  static const _matchColor = AppColors.brandPurple;

  @override
  Widget build(BuildContext context) {
    return _MockCard(
      accentColor: _matchColor,
      overrideBackground: true,
      child: Stack(
        children: [
          // Ambient radial gradient background (mirrors MatchedScreen)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: RadialGradient(
                  center: Alignment.topCenter,
                  radius: 1.3,
                  colors: [
                    _matchColor.withValues(alpha: 0.22),
                    AppColors.bgBase.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Find each other! 🧊',
                  style: AppTextStyles.h3.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'You have 5 minutes to meet in person',
                  style: AppTextStyles.caption,
                ),

                const SizedBox(height: 14),

                // Profile pair with gradient line (mirrors MatchedScreen)
                _MockProfilePair(
                  leftInitial: 'A',
                  rightInitial: 'J',
                  connector: Container(
                    width: 40,
                    height: 2,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        _matchColor,
                        _matchColor.withValues(alpha: 0.3),
                      ]),
                    ),
                  ),
                  borderColor: _matchColor,
                ),

                const SizedBox(height: 12),

                // Large countdown timer (mirrors MatchedScreen timer display)
                ShaderMask(
                  shaderCallback: (b) => LinearGradient(
                    colors: [_matchColor, AppColors.brandPink],
                  ).createShader(b),
                  child: Text(
                    '5:00',
                    style: AppTextStyles.display
                        .copyWith(color: Colors.white),
                  ),
                ),
                Text('to find each other',
                    style: AppTextStyles.caption),

                const SizedBox(height: 10),

                // "I found them" button (mirrors MatchedScreen primary CTA)
                Container(
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: AppColors.brandGradient,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.brandPink.withValues(alpha: 0.35),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Text('I found them ✓',
                      style: AppTextStyles.buttonS),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Slide 5: Chat Unlocks ─────────────────────────────────────────────────────
// Mirrors: MessagesScreen — app bar, chat list entry, then two chat bubbles

class _ChatUnlocksMock extends StatelessWidget {
  const _ChatUnlocksMock();

  @override
  Widget build(BuildContext context) {
    return _MockCard(
      accentColor: AppColors.brandCyan,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _MockAppBar(title: 'Messages'),
          _divider(),

          // Unlocked chat entry (mirrors MessagesScreen MessageListCard)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                _MockAvatar(
                  initial: 'J',
                  size: 40,
                  colors: [AppColors.brandCyan, AppColors.brandPurple],
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('Jordan',
                              style: AppTextStyles.bodyS.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary)),
                          const SizedBox(width: 5),
                          Icon(Icons.lock_open_rounded,
                              size: 12, color: AppColors.success),
                        ],
                      ),
                      Text(
                        'Chat unlocked · Say something!',
                        style: AppTextStyles.caption.copyWith(
                            color: AppColors.success),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.brandPink,
                  ),
                ),
              ],
            ),
          ),

          _divider(),

          // Chat bubbles (mirrors a simple chat conversation)
          Padding(
            padding:
                const EdgeInsets.fromLTRB(12, 10, 12, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Received bubble
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 200),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.bgElevated,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(14),
                        topRight: Radius.circular(14),
                        bottomRight: Radius.circular(14),
                        bottomLeft: Radius.circular(4),
                      ),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Text('That was so fun 😊',
                        style: AppTextStyles.bodyS),
                  ),
                ),
                const SizedBox(height: 6),
                // Sent bubble
                Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 200),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: AppColors.brandGradient,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(14),
                        topRight: Radius.circular(14),
                        bottomLeft: Radius.circular(14),
                        bottomRight: Radius.circular(4),
                      ),
                    ),
                    child: Text('Right? Let\'s do this again! 🧊',
                        style: AppTextStyles.bodyS),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Slide 6: Safety & Verification ───────────────────────────────────────────
// Mirrors: LiveVerificationScreen — gradient-bordered frame, verified state

class _SafetyMock extends StatelessWidget {
  const _SafetyMock();

  @override
  Widget build(BuildContext context) {
    return _MockCard(
      accentColor: AppColors.success,
      overrideBackground: true,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF05000E),
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Gradient-bordered selfie frame (mirrors LiveVerificationScreen frame)
            Center(
              child: _GradientBorderFrame(
                size: 88,
                child: Icon(
                  Icons.check_rounded,
                  color: AppColors.success,
                  size: 36,
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Verified badge (mirrors LiveVerificationScreen verified state)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: AppColors.success.withValues(alpha: 0.45)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.verified_rounded,
                      color: AppColors.success, size: 13),
                  const SizedBox(width: 5),
                  Text('Verified',
                      style: AppTextStyles.caption.copyWith(
                          color: AppColors.success,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),

            const SizedBox(height: 14),
            _divider(),
            const SizedBox(height: 10),

            // Trust bullets
            ...[
              (Icons.bolt_rounded, 'Live verification required'),
              (Icons.location_off_rounded, 'Location never shared with others'),
              (Icons.shield_rounded, 'Safety tools always one tap away'),
            ].map(
              (item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(item.$1,
                        size: 13,
                        color: AppColors.success.withValues(alpha: 0.8)),
                    const SizedBox(width: 8),
                    Text(item.$2,
                        style: AppTextStyles.caption.copyWith(
                            color: AppColors.textSecondary)),
                  ],
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
// Shared sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

/// Base card container used by all mock panels.
/// [overrideBackground] = true means the child handles its own background
/// (for slides with ambient gradient fills).
class _MockCard extends StatelessWidget {
  const _MockCard({
    required this.accentColor,
    required this.child,
    this.overrideBackground = false,
  });

  final Color accentColor;
  final Widget child;
  final bool overrideBackground;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: overrideBackground ? null : AppColors.bgSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.30),
          width: 1,
        ),
      ),
      clipBehavior: Clip.hardEdge,
      child: child,
    );
  }
}

/// Mini top bar that echoes the app's AppBar style.
class _MockAppBar extends StatelessWidget {
  const _MockAppBar({required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          if (trailing != null) const SizedBox(width: 20),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyS.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          if (trailing != null) trailing! else const SizedBox(width: 20),
        ],
      ),
    );
  }
}

/// Gradient avatar with a single letter — used for placeholder profile photos.
class _MockAvatar extends StatelessWidget {
  const _MockAvatar({
    required this.initial,
    required this.size,
    required this.colors,
  });

  final String initial;
  final double size;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.40,
          fontFamily: 'PlusJakartaSans',
        ),
      ),
    );
  }
}

/// Two avatars side by side with a connector widget between them.
/// Used in MutualInterest (heart) and FindEachOther (gradient line) slides.
class _MockProfilePair extends StatelessWidget {
  const _MockProfilePair({
    required this.leftInitial,
    required this.rightInitial,
    required this.connector,
    this.borderColor,
  });

  final String leftInitial;
  final String rightInitial;
  final Widget connector;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    Widget avatar(String initial) {
      final colors = [AppColors.brandPink, AppColors.brandPurple];
      final inner = _MockAvatar(initial: initial, size: 40, colors: colors);
      if (borderColor == null) return inner;
      return Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
              color: borderColor!.withValues(alpha: 0.70), width: 1.5),
        ),
        child: Padding(
          padding: const EdgeInsets.all(1.5),
          child: inner,
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Column(children: [
          avatar(leftInitial),
          const SizedBox(height: 4),
          Text('You',
              style: AppTextStyles.caption
                  .copyWith(color: AppColors.textSecondary)),
        ]),
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: connector,
        ),
        Column(children: [
          avatar(rightInitial),
          const SizedBox(height: 4),
          Text('Them',
              style: AppTextStyles.caption
                  .copyWith(color: AppColors.textSecondary)),
        ]),
      ],
    );
  }
}

/// SHOP pill that mirrors the HomeScreen AppBar shop button.
class _MiniShopPill extends StatelessWidget {
  const _MiniShopPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandPink.withValues(alpha: 0.30),
            blurRadius: 6,
          ),
        ],
      ),
      child: Text(
        'SHOP',
        style: AppTextStyles.caption.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 9,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

/// Stat pill that mirrors HomeScreen _StatusPill.
class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.icon,
    required this.label,
    required this.value,
    required this.iconColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: iconColor, size: 13),
          const SizedBox(width: 5),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: AppTextStyles.overline.copyWith(fontSize: 8)),
              Text(value,
                  style: AppTextStyles.bodyS.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Gradient-bordered square frame — mirrors LiveVerificationScreen selfie frame.
class _GradientBorderFrame extends StatelessWidget {
  const _GradientBorderFrame({required this.size, required this.child});

  final double size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white,
            AppColors.brandCyan,
            AppColors.brandPurple,
            AppColors.brandPink,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandCyan.withValues(alpha: 0.20),
            blurRadius: 12,
            spreadRadius: 1,
          ),
          BoxShadow(
            color: AppColors.brandPink.withValues(alpha: 0.15),
            blurRadius: 18,
          ),
        ],
      ),
      padding: const EdgeInsets.all(2.5),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF05000E),
          borderRadius: BorderRadius.circular(size * 0.14),
        ),
        alignment: Alignment.center,
        child: child,
      ),
    );
  }
}

/// Thin 1px divider — mirrors AppColors.divider separators throughout the app.
Widget _divider() => const Divider(
      height: 1,
      thickness: 1,
      color: AppColors.divider,
    );

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
        final active = i == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.only(right: 5),
          width: active ? 20 : 6,
          height: 6,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            color: active
                ? AppColors.brandPink
                : Colors.white.withValues(alpha: 0.22),
          ),
        );
      }),
    );
  }
}
