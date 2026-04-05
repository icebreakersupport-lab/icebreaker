import 'package:flutter/material.dart';
import '../../../core/state/live_session.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/gradient_scaffold.dart';
import '../../../shared/widgets/icebreaker_logo.dart';
import '../widgets/carousel_card.dart';

/// Nearby tab — horizontal profile discovery carousel.
///
/// Layout:
///   - One card centered in focus; adjacent cards peek from left/right
///   - PageView with smooth snap behaviour (viewportFraction: 0.88)
///   - Scale animation: focused card = 1.0×, adjacent = ~0.93×
///   - Page-dot indicator row below the carousel
///   - Empty / not-live gate states when there are no cards to show
class NearbyScreen extends StatefulWidget {
  const NearbyScreen({super.key});

  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends State<NearbyScreen> {
  late final PageController _pageController;
  int _currentPage = 0;

  // TODO: replace with real Firestore / Riverpod state.
  // Assumptions about the data model:
  //   • firstName, age, bio, photoUrl, distanceMeters — already in use
  //   • interests  — new: 2–3 short vibe tags (e.g. 'Coffee', 'Hiking')
  //   • isLiveNow  — new: true when the nearby user has an active Live session
  //   • isGold     — existing gold-member flag
  final List<_MockUser> _nearbyUsers = [
    _MockUser(
      id: '1',
      firstName: 'Jordan',
      age: 24,
      bio: 'Podcasts, brunch & mountain hikes ⛰️',
      photoUrl: '',
      distanceMeters: 14,
      isLiveNow: true,
      interests: ['Hiking', 'Coffee', 'Podcasts'],
    ),
    _MockUser(
      id: '2',
      firstName: 'Alex',
      age: 22,
      bio: 'Vinyl records, espresso, bad movies',
      photoUrl: '',
      distanceMeters: 22,
      isGold: true,
      interests: ['Music', 'Film', 'Coffee'],
    ),
    _MockUser(
      id: '3',
      firstName: 'Maya',
      age: 26,
      bio: 'Artist + yoga teacher, making things ✨',
      photoUrl: '',
      distanceMeters: 45,
      interests: ['Art', 'Yoga', 'Travel'],
    ),
    _MockUser(
      id: '4',
      firstName: 'Kai',
      age: 23,
      bio: 'Skater, chef, chronic overthinker',
      photoUrl: '',
      distanceMeters: 87,
      isGold: true,
      isLiveNow: true,
      interests: ['Skating', 'Food', 'Music'],
    ),
    _MockUser(
      id: '5',
      firstName: 'Sam',
      age: 25,
      bio: 'Dog dad 🐕 · into the weird stuff',
      photoUrl: '',
      distanceMeters: 130,
      interests: ['Dogs', 'Gaming', 'Travel'],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.88);
    _pageController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _pageController.removeListener(_onScroll);
    _pageController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final page = (_pageController.page ?? 0.0).round();
    if (page != _currentPage) setState(() => _currentPage = page);
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: _buildAppBar(),
      body: SafeArea(
        top: false,
        child: LiveSessionScope.isLive(context)
            ? _buildCarousel()
            : _buildNotLiveState(),
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

  // ─── Carousel ─────────────────────────────────────────────────────────────

  Widget _buildCarousel() {
    if (_nearbyUsers.isEmpty) return _buildEmptyState();

    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            itemCount: _nearbyUsers.length,
            itemBuilder: (context, i) => _buildPageItem(i),
          ),
        ),
        _buildPageDots(),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildPageItem(int index) {
    final u = _nearbyUsers[index];

    return AnimatedBuilder(
      animation: _pageController,
      builder: (context, child) {
        double scale = 1.0;
        if (_pageController.hasClients &&
            _pageController.position.haveDimensions) {
          final delta =
              (_pageController.page! - index).abs().clamp(0.0, 1.0);
          scale = 1.0 - (delta * 0.07);
        }
        return Transform.scale(
          scale: scale,
          alignment: Alignment.center,
          child: child,
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        child: CarouselCard(
          firstName: u.firstName,
          age: u.age,
          bio: u.bio,
          photoUrl: u.photoUrl,
          distanceMeters: u.distanceMeters,
          isGold: u.isGold,
          isLiveNow: u.isLiveNow,
          interests: u.interests,
          onSendIcebreaker: () => _navigateSendIcebreaker(u),
          onTap: () => _openProfile(u),
        ),
      ),
    );
  }

  // ─── Page dots ────────────────────────────────────────────────────────────

  Widget _buildPageDots() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(_nearbyUsers.length, (i) {
          final isActive = i == _currentPage;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeInOut,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: isActive ? 22.0 : 6.0,
            height: 6,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              color: isActive ? AppColors.brandPink : AppColors.textMuted,
            ),
          );
        }),
      ),
    );
  }

  // ─── Navigation ───────────────────────────────────────────────────────────

  void _navigateSendIcebreaker(_MockUser user) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _SendIcebreakerPlaceholder(recipientName: user.firstName),
      ),
    );
  }

  void _openProfile(_MockUser user) {
    // TODO: navigate to full nearby-user profile screen
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("${user.firstName}'s profile — coming soon"),
        backgroundColor: AppColors.bgElevated,
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ─── Empty / gate states ──────────────────────────────────────────────────

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
              'Check back when you\'re out — users\nonly appear within 30 metres.',
              style: AppTextStyles.bodyS,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotLiveState() {
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
              'You need an active Live session to browse\npeople around you.',
              style: AppTextStyles.bodyS,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Placeholder screen ───────────────────────────────────────────────────────

class _SendIcebreakerPlaceholder extends StatelessWidget {
  const _SendIcebreakerPlaceholder({required this.recipientName});
  final String recipientName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(recipientName, style: AppTextStyles.h3),
      ),
      body: const Center(
        child: Text('SendIcebreakerScreen — coming soon'),
      ),
    );
  }
}

// ─── Data model ───────────────────────────────────────────────────────────────

class _MockUser {
  const _MockUser({
    required this.id,
    required this.firstName,
    required this.age,
    required this.bio,
    required this.photoUrl,
    required this.distanceMeters,
    this.isGold = false,
    this.isLiveNow = false,
    this.interests = const [],
  });

  final String id;
  final String firstName;
  final int age;
  final String bio;
  final String photoUrl;
  final double distanceMeters;
  final bool isGold;
  final bool isLiveNow;
  final List<String> interests;
}
