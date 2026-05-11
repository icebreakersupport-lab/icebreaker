import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/profile_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/icebreaker_logo.dart';

/// Onboarding final step — 9-slide animated product walkthrough.
///
/// Each slide contains a mock panel that visually mirrors the real
/// app screen it describes, using the same color tokens, card shapes,
/// layout patterns, and (where it matters) live motion that the
/// production UI uses — countdowns count down, messages type
/// themselves, the heart pulses, the meetup color cycles.
///
/// Per-slide animation lifecycle: each animated mock is a
/// StatefulWidget that takes an [isActive] boolean.  When the page
/// scrolls a slide into view, that slide flips `isActive=true` and
/// the mock's internal AnimationController forwards/repeats.  When
/// scrolled away, the controller resets so the animation replays
/// fresh the next time the user lands on it.
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
        duration: const Duration(milliseconds: 320),
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

        // Dual-write profileComplete on both users/{uid} (read by BootstrapRoot
        // for the post-launch destination) and profiles/{uid} (canonical
        // public surface).
        await Future.wait([
          FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .set({'profileComplete': true}, SetOptions(merge: true)),
          ProfileRepository().setFields(uid, {'profileComplete': true}),
        ]);
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
                itemBuilder: (_, i) => _SlideView(
                  data: _slides[i],
                  isActive: i == _current,
                ),
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
    tag: 'THE PROBLEM',
    headline: 'Stop swiping.\nStart meeting.',
    body:
        'Dating apps trained us to scroll forever. Icebreaker is built for the opposite — meeting people who are actually near you, actually live, actually open.',
  ),
  _SlideData(
    index: 1,
    accentColor: AppColors.brandPink,
    tag: 'GO LIVE',
    headline: 'Go live where\nyou already are.',
    body:
        'Tap Go Live for 60 minutes so others nearby know you\'re open to meeting. The room is live.',
  ),
  _SlideData(
    index: 2,
    accentColor: AppColors.brandPurple,
    tag: 'NEARBY',
    headline: 'See who\'s around\nyou right now.',
    body:
        'Only live people, only nearby. No endless profiles. No matches from across the country.',
  ),
  _SlideData(
    index: 3,
    accentColor: AppColors.brandCyan,
    tag: 'ICEBREAKER',
    headline: 'Send one icebreaker.\nMake it count.',
    body:
        'One short message. If they accept, you both move into the meetup flow together.',
  ),
  _SlideData(
    index: 4,
    accentColor: AppColors.brandPurple,
    tag: 'COLOR MATCH',
    headline: 'Find your color.\nFind your person.',
    body:
        'Once they accept, you both get a shared color so you can spot each other in the room without a single awkward guess.',
  ),
  _SlideData(
    index: 5,
    accentColor: AppColors.brandPink,
    tag: 'FIND EACH OTHER',
    headline: 'Real chemistry happens\nin person.',
    body:
        'You have 5 minutes to meet face to face. No DMs, no filters — just walk over and say hello.',
  ),
  _SlideData(
    index: 6,
    accentColor: AppColors.success,
    tag: 'TALK FIRST',
    headline: 'Chat unlocks\nafter chemistry.',
    body:
        'You get 10 minutes to talk in person. Chat only opens if you both want to keep going. No ghosting. No purgatory.',
  ),
  _SlideData(
    index: 7,
    accentColor: AppColors.success,
    tag: 'SAFETY',
    headline: 'A safer way\nto say hello.',
    body:
        'Mutual interest before contact. Live verification. Block, report, and Do Not Disturb always one tap away.',
  ),
  _SlideData(
    index: 8,
    accentColor: AppColors.brandPink,
    tag: "LET'S GO",
    headline: 'Break the ice.',
    body:
        'Less scrolling. More sparks. Go live when you\'re ready to meet someone in real life.',
  ),
];

// ─────────────────────────────────────────────────────────────────────────────
// _SlideView — layout wrapper for each slide
// ─────────────────────────────────────────────────────────────────────────────

class _SlideView extends StatelessWidget {
  const _SlideView({required this.data, required this.isActive});

  final _SlideData data;
  final bool isActive;

  Widget _buildMock() => switch (data.index) {
        0 => _ProblemMock(isActive: isActive),
        1 => _GoLiveMock(isActive: isActive),
        2 => _NearbyMock(isActive: isActive),
        3 => _SendIcebreakerMock(isActive: isActive),
        4 => _ColorMatchMock(isActive: isActive),
        5 => _FindEachOtherMock(isActive: isActive),
        6 => _TalkFirstMock(isActive: isActive),
        7 => _SafetyMock(isActive: isActive),
        8 => _FinaleMock(isActive: isActive),
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
// MOCK PANELS — each mirrors the corresponding real app screen + animates
// ─────────────────────────────────────────────────────────────────────────────

// ── Slide 0: The Problem ─────────────────────────────────────────────────────
// "Stop swiping. Start meeting." — three swipe-cards stack, the top one
// flicks off-screen to the left, the next slides up, then the brand heart
// fades in centered with a glow — visualises the *replacement* of swipe
// behaviour with presence.

class _ProblemMock extends StatefulWidget {
  const _ProblemMock({required this.isActive});

  final bool isActive;

  @override
  State<_ProblemMock> createState() => _ProblemMockState();
}

class _ProblemMockState extends State<_ProblemMock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    if (widget.isActive) _ctrl.forward();
  }

  @override
  void didUpdateWidget(covariant _ProblemMock old) {
    super.didUpdateWidget(old);
    if (widget.isActive && !old.isActive) {
      _ctrl
        ..reset()
        ..forward();
    } else if (!widget.isActive && old.isActive) {
      _ctrl.reset();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _MockCard(
      accentColor: AppColors.brandPink,
      overrideBackground: true,
      child: SizedBox(
        height: 280,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, _) {
            // Three phases over t∈[0,1]:
            //   0.00–0.35: swipe-card flicks off
            //   0.35–0.70: card stack collapses, heart starts fading in
            //   0.70–1.00: heart sits centered with a slow glow pulse
            final t = _ctrl.value;
            final swipeT = (t / 0.35).clamp(0.0, 1.0);
            final heartIn = ((t - 0.35) / 0.35).clamp(0.0, 1.0);
            final pulse = ((t - 0.70) / 0.30).clamp(0.0, 1.0);

            return Stack(
              alignment: Alignment.center,
              children: [
                // Bottom card (peeks)
                Transform.translate(
                  offset: Offset(0, 14 - 8 * heartIn),
                  child: Opacity(
                    opacity: (1 - heartIn) * 0.45,
                    child: _SwipeCardShell(
                      colors: [
                        AppColors.brandCyan.withValues(alpha: 0.25),
                        AppColors.brandPurple.withValues(alpha: 0.25),
                      ],
                      width: 180,
                      height: 230,
                    ),
                  ),
                ),
                // Middle card (peeks more)
                Transform.translate(
                  offset: Offset(0, 7 - 5 * heartIn),
                  child: Opacity(
                    opacity: (1 - heartIn) * 0.7,
                    child: _SwipeCardShell(
                      colors: [
                        AppColors.brandPurple.withValues(alpha: 0.35),
                        AppColors.brandPink.withValues(alpha: 0.35),
                      ],
                      width: 195,
                      height: 240,
                    ),
                  ),
                ),
                // Top card — flicks off-screen left + rotates as it goes
                Transform.translate(
                  offset: Offset(-220 * Curves.easeIn.transform(swipeT), 0),
                  child: Transform.rotate(
                    angle: -0.35 * swipeT,
                    child: Opacity(
                      opacity: 1 - swipeT,
                      child: _SwipeCardShell(
                        colors: [
                          AppColors.brandPink.withValues(alpha: 0.85),
                          AppColors.brandPurple.withValues(alpha: 0.85),
                        ],
                        width: 210,
                        height: 250,
                        showCross: swipeT > 0.15,
                      ),
                    ),
                  ),
                ),
                // Replacement: the brand heart fades in centered
                Opacity(
                  opacity: heartIn,
                  child: Transform.scale(
                    scale: 0.85 + 0.15 * heartIn,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: AppColors.brandGradient,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.brandPink.withValues(
                                alpha: 0.40 + 0.25 * pulse),
                            blurRadius: 32 + 18 * pulse,
                            spreadRadius: 2 + 4 * pulse,
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.favorite_rounded,
                        color: Colors.white,
                        size: 56,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Card-shaped placeholder used by _ProblemMock to depict a "swipe app" card
/// without showing any real user photo (we don't want to imply any specific
/// competitor or sample a real face).
class _SwipeCardShell extends StatelessWidget {
  const _SwipeCardShell({
    required this.colors,
    required this.width,
    required this.height,
    this.showCross = false,
  });

  final List<Color> colors;
  final double width;
  final double height;
  final bool showCross;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      alignment: Alignment.center,
      child: showCross
          ? Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: 0.25),
                border:
                    Border.all(color: AppColors.danger.withValues(alpha: 0.85)),
              ),
              child: const Icon(Icons.close_rounded,
                  color: AppColors.danger, size: 28),
            )
          : null,
    );
  }
}

// ── Slide 1: Go Live ─────────────────────────────────────────────────────────
// Mirrors HomeScreen offline state.  Animation: the heart logo runs the
// real heartbeat pulse (forcePulse=true bypasses LiveSessionScope), the
// GO LIVE pill gets a slow gradient shimmer to read as "active and
// pressable", and a small "+1 SESSION" counter pops once near the end
// to imply that tapping starts a session.

class _GoLiveMock extends StatefulWidget {
  const _GoLiveMock({required this.isActive});

  final bool isActive;

  @override
  State<_GoLiveMock> createState() => _GoLiveMockState();
}

class _GoLiveMockState extends State<_GoLiveMock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    if (widget.isActive) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(covariant _GoLiveMock old) {
    super.didUpdateWidget(old);
    if (widget.isActive && !old.isActive) {
      _ctrl.repeat();
    } else if (!widget.isActive && old.isActive) {
      _ctrl.stop();
      _ctrl.value = 0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _MockCard(
      accentColor: AppColors.brandPink,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Mini app bar with green live dot, mirroring HomeScreen
          const _MockAppBar(
            title: 'icebreaker •',
            trailing: _MiniShopPill(),
          ),
          _divider(),

          // Stat pills row — mirrors HomeScreen _StatusPill
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: _StatPill(
                    icon: Icons.favorite_rounded,
                    label: 'ICEBREAKERS',
                    value: '3',
                    iconColor: AppColors.brandPink,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatPill(
                    icon: Icons.bolt_rounded,
                    label: 'SESSIONS',
                    value: '1',
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
                // Real brand logo running its real heartbeat — forcePulse
                // bypasses the LiveSessionScope check, so it pulses inside
                // onboarding even though the user hasn't gone live yet.
                IcebreakerLogo(
                  size: 76,
                  showGlow: true,
                  ambientGlow: 0.75,
                  forcePulse: widget.isActive,
                ),
                const SizedBox(height: 14),
                // GO LIVE gradient pill with a slow shimmer band sliding
                // across it to read as "tappable, alive".
                AnimatedBuilder(
                  animation: _ctrl,
                  builder: (_, _) {
                    return Container(
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
                      clipBehavior: Clip.hardEdge,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Shimmer band
                          Positioned(
                            left: -80 + 320 * _ctrl.value,
                            top: 0,
                            bottom: 0,
                            width: 80,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                  colors: [
                                    Colors.white.withValues(alpha: 0),
                                    Colors.white.withValues(alpha: 0.28),
                                    Colors.white.withValues(alpha: 0),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.bolt_rounded,
                                  color: Colors.white, size: 16),
                              const SizedBox(width: 6),
                              Text('GO LIVE',
                                  style: AppTextStyles.button
                                      .copyWith(letterSpacing: 1.2)),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Slide 2: Nearby Discovery ─────────────────────────────────────────────────
// Mirrors NearbyScreen.  Animation: three discovery cards slide up from the
// bottom in stagger, each fading in as it reaches its resting position —
// the "the room filled in around me" feel.

class _NearbyMock extends StatefulWidget {
  const _NearbyMock({required this.isActive});

  final bool isActive;

  @override
  State<_NearbyMock> createState() => _NearbyMockState();
}

class _NearbyMockState extends State<_NearbyMock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    if (widget.isActive) _ctrl.forward();
  }

  @override
  void didUpdateWidget(covariant _NearbyMock old) {
    super.didUpdateWidget(old);
    if (widget.isActive && !old.isActive) {
      _ctrl
        ..reset()
        ..forward();
    } else if (!widget.isActive && old.isActive) {
      _ctrl.reset();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Per-card stagger.  Card 0 plays from t=0.00→0.45, card 1 from
  /// 0.20→0.65, card 2 from 0.40→0.85.  Each card's local progress is
  /// fed through Curves.easeOut so it lands soft rather than mechanical.
  double _cardT(int i) {
    final start = i * 0.20;
    final end = start + 0.45;
    return ((_ctrl.value - start) / (end - start)).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final cards = [
      ('A', 'Alex, 24', '12m away', 'Up for spontaneous adventures'),
      ('J', 'Jordan, 26', '24m away', 'Coffee and good music'),
      ('S', 'Sam, 23', '38m away', 'Loves trivia nights'),
    ];

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
            padding: const EdgeInsets.all(10),
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (_, _) {
                return Column(
                  children: List.generate(cards.length, (i) {
                    final c = cards[i];
                    final t = Curves.easeOut.transform(_cardT(i));
                    return Opacity(
                      opacity: t,
                      child: Transform.translate(
                        offset: Offset(0, 24 * (1 - t)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: _NearbyCardRow(
                            initial: c.$1,
                            nameAge: c.$2,
                            distance: c.$3,
                            bio: c.$4,
                          ),
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _NearbyCardRow extends StatelessWidget {
  const _NearbyCardRow({
    required this.initial,
    required this.nameAge,
    required this.distance,
    required this.bio,
  });

  final String initial;
  final String nameAge;
  final String distance;
  final String bio;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: AppColors.brandPurple.withValues(alpha: 0.30)),
      ),
      padding: const EdgeInsets.all(10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MockAvatar(
            initial: initial,
            size: 42,
            colors: const [AppColors.brandPurple, AppColors.brandPink],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(nameAge,
                        style: AppTextStyles.bodyS.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                    const Spacer(),
                    Text(distance,
                        style: AppTextStyles.caption
                            .copyWith(color: AppColors.brandPurple)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(bio,
                    style: AppTextStyles.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                Container(
                  height: 26,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: AppColors.brandCyan.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(
                        color: AppColors.brandCyan.withValues(alpha: 0.5),
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
    );
  }
}

// ── Slide 3: Send Icebreaker ──────────────────────────────────────────────────
// Mirrors SendIcebreakerScreen.  Animation: the message types itself
// (typewriter), the Send button pulses once the message is complete,
// then a small "✓ Delivered" badge fades in below.

class _SendIcebreakerMock extends StatefulWidget {
  const _SendIcebreakerMock({required this.isActive});

  final bool isActive;

  @override
  State<_SendIcebreakerMock> createState() => _SendIcebreakerMockState();
}

class _SendIcebreakerMockState extends State<_SendIcebreakerMock>
    with SingleTickerProviderStateMixin {
  static const _full = "Hey, thought I'd break the ice with you! 🧊";
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );
    if (widget.isActive) _ctrl.forward();
  }

  @override
  void didUpdateWidget(covariant _SendIcebreakerMock old) {
    super.didUpdateWidget(old);
    if (widget.isActive && !old.isActive) {
      _ctrl
        ..reset()
        ..forward();
    } else if (!widget.isActive && old.isActive) {
      _ctrl.reset();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _MockCard(
      accentColor: AppColors.brandCyan,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, _) {
          // Phases:
          //   0.00–0.65: typewriter typing
          //   0.65–0.80: send button pulse
          //   0.80–1.00: delivered badge fade-in
          final t = _ctrl.value;
          final typeT = (t / 0.65).clamp(0.0, 1.0);
          final pulseT = ((t - 0.65) / 0.15).clamp(0.0, 1.0);
          final deliveredT = ((t - 0.80) / 0.20).clamp(0.0, 1.0);

          final shown = (_full.length * typeT).round();
          final text = _full.substring(0, shown);
          final showCursor = typeT < 1.0 && (t * 8).floor().isEven;

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
                      colors: const [AppColors.brandCyan, AppColors.brandPurple],
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

              // Message input (typewriter)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Container(
                  height: 64,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.brandCyan.withValues(alpha: 0.45),
                      width: 1.5,
                    ),
                  ),
                  alignment: Alignment.centerLeft,
                  child: RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: text,
                          style: AppTextStyles.bodyS
                              .copyWith(color: AppColors.textPrimary),
                        ),
                        if (showCursor)
                          TextSpan(
                            text: '▍',
                            style: AppTextStyles.bodyS.copyWith(
                              color: AppColors.brandCyan,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // Cyan Send button with pulse
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                child: Transform.scale(
                  scale: 1.0 + 0.08 * math.sin(pulseT * math.pi),
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.brandCyan,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.brandCyan
                              .withValues(alpha: 0.25 + 0.40 * pulseT),
                          blurRadius: 12 + 12 * pulseT,
                          spreadRadius: pulseT * 2,
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Send 🧊',
                      style: AppTextStyles.button
                          .copyWith(color: AppColors.textInverse),
                    ),
                  ),
                ),
              ),

              // Delivered confirmation
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Opacity(
                  opacity: deliveredT,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppColors.success.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_rounded,
                            size: 12, color: AppColors.success),
                        const SizedBox(width: 4),
                        Text('Delivered',
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.success,
                              fontWeight: FontWeight.w700,
                            )),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Slide 4: Color Match (NEW) ────────────────────────────────────────────────
// Mirrors ColorMatchScreen's "shared match color" concept.  Animation:
// two avatars hover side by side; the rings cycle through the brand
// palette, then both lock onto the same color simultaneously while a
// "COLOR MATCH!" label fades in centered above them.

class _ColorMatchMock extends StatefulWidget {
  const _ColorMatchMock({required this.isActive});

  final bool isActive;

  @override
  State<_ColorMatchMock> createState() => _ColorMatchMockState();
}

class _ColorMatchMockState extends State<_ColorMatchMock>
    with SingleTickerProviderStateMixin {
  static const _palette = [
    AppColors.brandPink,
    AppColors.brandCyan,
    AppColors.brandPurple,
    AppColors.warning,
    AppColors.success,
  ];
  // The color they "land on" — picked once per cycle.  Same color on
  // both sides is the whole point of the slide.
  static const Color _lockColor = AppColors.brandPink;

  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3400),
    );
    if (widget.isActive) _ctrl.forward();
  }

  @override
  void didUpdateWidget(covariant _ColorMatchMock old) {
    super.didUpdateWidget(old);
    if (widget.isActive && !old.isActive) {
      _ctrl
        ..reset()
        ..forward();
    } else if (!widget.isActive && old.isActive) {
      _ctrl.reset();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Color _ringColor(double t) {
    // For t < 0.70 we cycle quickly through the palette.  At t >= 0.70
    // we lock onto _lockColor — the visual "found a shared color".
    if (t >= 0.70) return _lockColor;
    final idx = (t * _palette.length * 4).floor() % _palette.length;
    return _palette[idx];
  }

  @override
  Widget build(BuildContext context) {
    return _MockCard(
      accentColor: AppColors.brandPurple,
      overrideBackground: true,
      child: SizedBox(
        height: 270,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, _) {
            final t = _ctrl.value;
            final lockT = ((t - 0.70) / 0.30).clamp(0.0, 1.0);
            final ringColor = _ringColor(t);

            return Stack(
              children: [
                // Ambient color wash from the lock color
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: RadialGradient(
                        center: Alignment.center,
                        radius: 1.2,
                        colors: [
                          ringColor.withValues(alpha: 0.18 + 0.18 * lockT),
                          AppColors.bgBase,
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
                  child: Column(
                    children: [
                      // COLOR MATCH! label appears at lock time
                      Opacity(
                        opacity: lockT,
                        child: Transform.translate(
                          offset: Offset(0, 6 * (1 - lockT)),
                          child: ShaderMask(
                            shaderCallback: (b) => LinearGradient(
                              colors: [ringColor, AppColors.brandPink],
                            ).createShader(b),
                            child: Text(
                              'COLOR MATCH!',
                              style: AppTextStyles.h3.copyWith(
                                color: Colors.white,
                                letterSpacing: 2.0,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Two avatars side by side, both ringed in the
                      // currently-cycling (or locked) color.
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _RingedAvatar(
                              initial: 'A',
                              ringColor: ringColor,
                              pulse: lockT,
                            ),
                            _RingedAvatar(
                              initial: 'J',
                              ringColor: ringColor,
                              pulse: lockT,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        lockT > 0.5
                            ? 'Look for $_colorNameFor at the bar'
                            : 'Cycling through colors…',
                        style: AppTextStyles.caption,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // _lockColor is brandPink — name it for the caption line.
  String get _colorNameFor => 'pink';
}

class _RingedAvatar extends StatelessWidget {
  const _RingedAvatar({
    required this.initial,
    required this.ringColor,
    required this.pulse,
  });

  final String initial;
  final Color ringColor;
  // 0..1 — controls a small post-lock breath
  final double pulse;

  @override
  Widget build(BuildContext context) {
    final scale = 1.0 + 0.05 * math.sin(pulse * math.pi);
    return Transform.scale(
      scale: scale,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [ringColor, ringColor.withValues(alpha: 0.5)],
          ),
          boxShadow: [
            BoxShadow(
              color: ringColor.withValues(alpha: 0.45 * pulse),
              blurRadius: 18,
              spreadRadius: 1 + 2 * pulse,
            ),
          ],
        ),
        child: _MockAvatar(
          initial: initial,
          size: 64,
          colors: const [AppColors.brandPink, AppColors.brandPurple],
        ),
      ),
    );
  }
}

// ── Slide 5: Find Each Other ──────────────────────────────────────────────────
// Mirrors MatchedScreen.  Animation: the 5:00 countdown actually ticks
// down on the second, and the photo pair "pulses" gently in the lock
// color while the timer runs.

class _FindEachOtherMock extends StatefulWidget {
  const _FindEachOtherMock({required this.isActive});

  final bool isActive;

  @override
  State<_FindEachOtherMock> createState() => _FindEachOtherMockState();
}

class _FindEachOtherMockState extends State<_FindEachOtherMock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    // 4 seconds of motion → fake clock counts from 5:00 down by 4s.
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    );
    if (widget.isActive) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(covariant _FindEachOtherMock old) {
    super.didUpdateWidget(old);
    if (widget.isActive && !old.isActive) {
      _ctrl.repeat();
    } else if (!widget.isActive && old.isActive) {
      _ctrl.stop();
      _ctrl.value = 0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _timeFor(double t) {
    // Counts from 5:00 down 4s over the cycle, then snaps back.
    final totalSeconds = 300 - (t * 4).floor();
    final mm = (totalSeconds ~/ 60).toString();
    final ss = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    const matchColor = AppColors.brandPink;
    return _MockCard(
      accentColor: matchColor,
      overrideBackground: true,
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: RadialGradient(
                  center: Alignment.topCenter,
                  radius: 1.3,
                  colors: [
                    matchColor.withValues(alpha: 0.22),
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
                  '5 minutes to meet in person',
                  style: AppTextStyles.caption,
                ),

                const SizedBox(height: 12),

                AnimatedBuilder(
                  animation: _ctrl,
                  builder: (_, _) {
                    final pulse = 1.0 + 0.04 * math.sin(_ctrl.value * math.pi * 2);
                    return Transform.scale(
                      scale: pulse,
                      child: _MockProfilePair(
                        leftInitial: 'A',
                        rightInitial: 'J',
                        borderColor: matchColor,
                        connector: Container(
                          width: 40,
                          height: 2,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [
                              matchColor,
                              matchColor.withValues(alpha: 0.3),
                            ]),
                          ),
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 12),

                // Live ticking countdown
                AnimatedBuilder(
                  animation: _ctrl,
                  builder: (_, _) {
                    return ShaderMask(
                      shaderCallback: (b) => const LinearGradient(
                        colors: [matchColor, AppColors.brandPurple],
                      ).createShader(b),
                      child: Text(
                        _timeFor(_ctrl.value),
                        style: AppTextStyles.h1.copyWith(
                          color: Colors.white,
                          fontSize: 36,
                          letterSpacing: 2,
                        ),
                      ),
                    );
                  },
                ),
                Text('to find each other', style: AppTextStyles.caption),

                const SizedBox(height: 10),

                // Swipe-to-confirm pill (static visual, mirrors real screen)
                Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(19),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.18)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                        child: Icon(Icons.chevron_right_rounded,
                            color: matchColor, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Text('Swipe — I found Jordan',
                          style: AppTextStyles.caption.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          )),
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

// ── Slide 6: Talk First (NEW) ─────────────────────────────────────────────────
// Mirrors ColorMatchScreen's talking phase + the post-meet decision +
// the moment chat unlocks.  Animation:
//   1. 10:00 timer ticks down (showing "talk timer running")
//   2. A "How did it go?" overlay slides up at the end
//   3. A lock icon flips to unlocked and a chat bubble appears, communicating
//      "chat opens only after both say yes"

class _TalkFirstMock extends StatefulWidget {
  const _TalkFirstMock({required this.isActive});

  final bool isActive;

  @override
  State<_TalkFirstMock> createState() => _TalkFirstMockState();
}

class _TalkFirstMockState extends State<_TalkFirstMock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
    );
    if (widget.isActive) _ctrl.forward();
  }

  @override
  void didUpdateWidget(covariant _TalkFirstMock old) {
    super.didUpdateWidget(old);
    if (widget.isActive && !old.isActive) {
      _ctrl
        ..reset()
        ..forward();
    } else if (!widget.isActive && old.isActive) {
      _ctrl.reset();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _MockCard(
      accentColor: AppColors.success,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, _) {
          // Phases:
          //   0.00–0.45: talk timer counts down from 10:00 visibly
          //   0.45–0.65: "Stay in touch?" overlay slides up
          //   0.65–1.00: lock unlocks + chat bubble fades in
          final t = _ctrl.value;
          final timerT = (t / 0.45).clamp(0.0, 1.0);
          final overlayT = ((t - 0.45) / 0.20).clamp(0.0, 1.0);
          final chatT = ((t - 0.65) / 0.35).clamp(0.0, 1.0);

          final secondsLeft = (600 - 8 * (timerT * 60)).round();
          final mm = (secondsLeft ~/ 60).toString();
          final ss = (secondsLeft % 60).toString().padLeft(2, '0');

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _MockAppBar(title: "You're talking 💬"),
              _divider(),

              // Talk timer + profile pair
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    _MockProfilePair(
                      leftInitial: 'A',
                      rightInitial: 'J',
                      borderColor: AppColors.success,
                      connector: Container(
                        width: 50,
                        alignment: Alignment.center,
                        child: ShaderMask(
                          shaderCallback: (b) => LinearGradient(
                            colors: [
                              AppColors.success,
                              AppColors.brandCyan,
                            ],
                          ).createShader(b),
                          child: Text(
                            '$mm:$ss',
                            style: AppTextStyles.h3.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Decision overlay slides up over the bottom half
                    if (overlayT > 0)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: -20 + 40 * overlayT,
                        child: Opacity(
                          opacity: overlayT,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.22),
                              ),
                            ),
                            child: Row(
                              children: [
                                Text('Stay in touch?',
                                    style: AppTextStyles.bodyS.copyWith(
                                        fontWeight: FontWeight.w700)),
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.success
                                        .withValues(alpha: 0.20),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text('Yes 💚',
                                      style: AppTextStyles.caption.copyWith(
                                        color: AppColors.success,
                                        fontWeight: FontWeight.w700,
                                      )),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              _divider(),

              // Chat-unlock row + first message
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        // Lock → unlock transition
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: chatT > 0.3
                                ? AppColors.success.withValues(alpha: 0.18)
                                : Colors.white.withValues(alpha: 0.08),
                            border: Border.all(
                              color: chatT > 0.3
                                  ? AppColors.success
                                  : AppColors.textMuted,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            chatT > 0.3
                                ? Icons.lock_open_rounded
                                : Icons.lock_rounded,
                            size: 12,
                            color: chatT > 0.3
                                ? AppColors.success
                                : AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          chatT > 0.3
                              ? 'Chat unlocked'
                              : 'Chat is locked',
                          style: AppTextStyles.caption.copyWith(
                            color: chatT > 0.3
                                ? AppColors.success
                                : AppColors.textMuted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // First chat bubble fades in once unlocked
                    Opacity(
                      opacity: chatT.clamp(0.0, 1.0),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 220),
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
                          child: Text("That was so fun 😊",
                              style: AppTextStyles.bodyS),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Slide 7: Safety ──────────────────────────────────────────────────────────
// Mirrors LiveVerificationScreen + Settings safety controls.  Animation:
// Verified frame fades in first, then three trust bullets check in one
// at a time.

class _SafetyMock extends StatefulWidget {
  const _SafetyMock({required this.isActive});

  final bool isActive;

  @override
  State<_SafetyMock> createState() => _SafetyMockState();
}

class _SafetyMockState extends State<_SafetyMock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  static const _bullets = [
    (Icons.bolt_rounded, 'Live verification required'),
    (Icons.handshake_rounded, 'Mutual consent before contact'),
    (Icons.shield_rounded, 'Block & report always one tap away'),
  ];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    if (widget.isActive) _ctrl.forward();
  }

  @override
  void didUpdateWidget(covariant _SafetyMock old) {
    super.didUpdateWidget(old);
    if (widget.isActive && !old.isActive) {
      _ctrl
        ..reset()
        ..forward();
    } else if (!widget.isActive && old.isActive) {
      _ctrl.reset();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  double _bulletT(int i) {
    // First bullet starts at t=0.40, each subsequent +0.15
    final start = 0.40 + i * 0.15;
    final end = start + 0.20;
    return ((_ctrl.value - start) / (end - start)).clamp(0.0, 1.0);
  }

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
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, _) {
            final frameT = (_ctrl.value / 0.40).clamp(0.0, 1.0);
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Opacity(
                  opacity: frameT,
                  child: Transform.scale(
                    scale: 0.9 + 0.1 * frameT,
                    child: Center(
                      child: _GradientBorderFrame(
                        size: 88,
                        child: Icon(
                          Icons.check_rounded,
                          color: AppColors.success,
                          size: 36,
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                Opacity(
                  opacity: frameT,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 5),
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
                ),

                const SizedBox(height: 14),
                _divider(),
                const SizedBox(height: 10),

                // Trust bullets check in one at a time
                ...List.generate(_bullets.length, (i) {
                  final t = _bulletT(i);
                  final item = _bullets[i];
                  return Opacity(
                    opacity: t,
                    child: Transform.translate(
                      offset: Offset(-10 * (1 - t), 0),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Icon(
                              t > 0.6
                                  ? Icons.check_circle_rounded
                                  : item.$1,
                              size: 14,
                              color: AppColors.success
                                  .withValues(alpha: 0.85),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                item.$2,
                                style: AppTextStyles.caption.copyWith(
                                    color: AppColors.textSecondary),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ── Slide 8: Finale / Let's Go ───────────────────────────────────────────────
// Closing CTA.  Animation: the brand heart logo runs the real pulse with
// a soft expanding ring of color behind it — the "we're open for
// business" beat.

class _FinaleMock extends StatefulWidget {
  const _FinaleMock({required this.isActive});

  final bool isActive;

  @override
  State<_FinaleMock> createState() => _FinaleMockState();
}

class _FinaleMockState extends State<_FinaleMock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );
    if (widget.isActive) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(covariant _FinaleMock old) {
    super.didUpdateWidget(old);
    if (widget.isActive && !old.isActive) {
      _ctrl.repeat();
    } else if (!widget.isActive && old.isActive) {
      _ctrl.stop();
      _ctrl.value = 0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _MockCard(
      accentColor: AppColors.brandPink,
      overrideBackground: true,
      child: SizedBox(
        height: 260,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, _) {
            final t = _ctrl.value;
            return Stack(
              alignment: Alignment.center,
              children: [
                // Expanding ring (single ring slowly fades out as it grows)
                ...List.generate(2, (i) {
                  final phase = (t + i * 0.5) % 1.0;
                  final size = 90 + 130 * phase;
                  final opacity = (1 - phase) * 0.5;
                  return Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.brandPink.withValues(alpha: opacity),
                        width: 1.5,
                      ),
                    ),
                  );
                }),
                // The logo running its real heartbeat
                IcebreakerLogo(
                  size: 120,
                  showGlow: true,
                  ambientGlow: 0.85,
                  forcePulse: widget.isActive,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

/// Base card container used by all mock panels.
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
      const colors = [AppColors.brandPink, AppColors.brandPurple];
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
