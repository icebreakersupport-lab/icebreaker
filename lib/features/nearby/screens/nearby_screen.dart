import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/state/live_session.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/gradient_scaffold.dart';
import '../../../shared/widgets/icebreaker_logo.dart';
import '../widgets/nearby_focus_card.dart';
import '../widgets/nearby_about_me_card.dart';

/// Nearby tab — horizontal discovery carousel.
///
/// Layout (when live + users present):
///   ┌─────────────────────────────────────────────┐
///   │  AppBar  (Nearby title + filter icon)       │
///   │─────────────────────────────────────────────│
///   │                                             │
///   │  [card]  [FOCUSED CARD]  [card]   ← 80% vp │
///   │                                             │
///   │─────────────────────────────────────────────│
///   │  About Me card  (updates on swipe)          │
///   └─────────────────────────────────────────────┘
///
/// PageView uses viewportFraction: 0.80 so ~10% of each adjacent card
/// is visible on both sides, giving a clear depth/carousel feel.
/// onPageChanged drives the About Me panel update.
///
/// When not live: "Go Live" gate is shown.
/// When live but empty: empty-state prompt.
class NearbyScreen extends StatefulWidget {
  const NearbyScreen({super.key});

  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends State<NearbyScreen> {
  late final PageController _pageController;
  int _currentIndex = 0;

  // TODO: replace with real Firestore state
  final List<_MockUser> _nearbyUsers = const [
    _MockUser(
      id: '1',
      firstName: 'Jordan',
      age: 24,
      bio: 'Podcasts, brunch, and long hikes',
      photoUrl: '',
      distanceMeters: 14,
      hometown: 'Denver, CO',
      occupation: 'Product Designer',
      height: "5'9\"",
      lookingFor: 'Casual dating',
      opener: 'Best hidden gem restaurant in the city?',
    ),
    _MockUser(
      id: '2',
      firstName: 'Alex',
      age: 22,
      bio: 'Coffee shops, live music, and spontaneous road trips',
      photoUrl: '',
      distanceMeters: 22,
      hometown: 'Austin, TX',
      occupation: 'Startup Founder',
      height: "6'1\"",
      isGold: true,
      lookingFor: 'Open to anything',
      opener: 'Morning person or night owl?',
    ),
    _MockUser(
      id: '3',
      firstName: 'Sam',
      age: 26,
      bio: 'Weekend hiker, bookworm, amateur chef',
      photoUrl: '',
      distanceMeters: 8,
      hometown: 'Chicago, IL',
      occupation: 'Photographer',
      height: "5'7\"",
      lookingFor: 'Something serious',
      opener: "What's on your reading list right now?",
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.80);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: _buildAppBar(),
      body: SafeArea(
        top: false,
        child: LiveSessionScope.isLive(context)
            ? _buildDiscovery()
            : _buildNotLiveGate(),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      title: Text('Nearby', style: AppTextStyles.h3),
      actions: [
        IconButton(
          icon: const Icon(Icons.tune_rounded, color: AppColors.textSecondary),
          onPressed: () {
            // TODO: open preference filter sheet
          },
        ),
      ],
    );
  }

  // ── Discovery layout ──────────────────────────────────────────────────────

  Widget _buildDiscovery() {
    if (_nearbyUsers.isEmpty) return _buildEmptyState();

    return LayoutBuilder(
      builder: (context, constraints) {
        // Give 62% of body height to the card carousel.
        // The remaining space holds the About Me panel.
        final cardAreaHeight = constraints.maxHeight * 0.62;

        return Column(
          children: [
            // ── Carousel ────────────────────────────────────────────────────
            SizedBox(
              height: cardAreaHeight,
              // Clip.none lets the active card's glow shadow overflow the
              // PageView bounds instead of being cut off.
              child: PageView.builder(
                controller: _pageController,
                clipBehavior: Clip.none,
                itemCount: _nearbyUsers.length,
                onPageChanged: (i) => setState(() => _currentIndex = i),
                itemBuilder: (context, i) {
                  final u = _nearbyUsers[i];
                  return NearbyFocusCard(
                    firstName: u.firstName,
                    age: u.age,
                    bio: u.bio,
                    photoUrl: u.photoUrl,
                    distanceMeters: u.distanceMeters,
                    hometown: u.hometown,
                    opener: u.opener,
                    isGold: u.isGold,
                    isActive: i == _currentIndex,
                    onSendIcebreaker: () => _navigateSendIcebreaker(u),
                  );
                },
              ),
            ),

            // ── About Me panel ───────────────────────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.06),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: NearbyAboutMeCard(
                    key: ValueKey(_currentIndex),
                    age: _nearbyUsers[_currentIndex].age,
                    hometown: _nearbyUsers[_currentIndex].hometown,
                    occupation: _nearbyUsers[_currentIndex].occupation,
                    height: _nearbyUsers[_currentIndex].height,
                    lookingFor: _nearbyUsers[_currentIndex].lookingFor,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  void _navigateSendIcebreaker(_MockUser user) {
    context.push(
      AppRoutes.sendIcebreaker,
      extra: {
        'recipientId': user.id,
        'firstName': user.firstName,
        'age': user.age,
        'photoUrl': user.photoUrl,
        'bio': user.bio,
      },
    );
  }

  // ── Empty / gate states ───────────────────────────────────────────────────

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const IcebreakerLogo(size: 72, showGlow: true),
            const SizedBox(height: 24),
            Text(
              'No one nearby right now',
              style: AppTextStyles.h3,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Check back when you\'re out —\nusers only appear within 30 metres.',
              style: AppTextStyles.bodyS,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotLiveGate() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const IcebreakerLogo(size: 80, showGlow: true),
            const SizedBox(height: 28),
            Text(
              'Go Live to see\nwho\'s nearby',
              style: AppTextStyles.h2,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'You need an active Live session to\nbrowse people around you.',
              style: AppTextStyles.bodyS,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _MockUser
// ─────────────────────────────────────────────────────────────────────────────

class _MockUser {
  const _MockUser({
    required this.id,
    required this.firstName,
    required this.age,
    required this.bio,
    required this.photoUrl,
    required this.distanceMeters,
    this.hometown,
    this.occupation,
    this.height,
    this.isGold = false,
    this.lookingFor,
    this.opener,
  });

  final String id;
  final String firstName;
  final int age;
  final String bio;
  final String photoUrl;
  final double distanceMeters;
  final String? hometown;
  final String? occupation;
  final String? height;
  final bool isGold;
  final String? lookingFor;
  final String? opener;
}
