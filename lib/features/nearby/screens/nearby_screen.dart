import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/gradient_scaffold.dart';
import '../../../shared/widgets/icebreaker_logo.dart';
import '../widgets/carousel_card.dart';

/// Nearby tab — the discovery carousel.
///
/// Layout (from slide 7):
///   - List of CarouselCards scrollable vertically (page-snap feel)
///   - Empty state when not live or no nearby users
///   - "Not live" gate: prompt user to go live first
class NearbyScreen extends StatefulWidget {
  const NearbyScreen({super.key});

  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends State<NearbyScreen> {
  // TODO: replace with real state from Firestore via Riverpod
  final bool _isLive = true;
  final List<_MockUser> _nearbyUsers = [
    _MockUser(
      id: '1',
      firstName: 'Jordan',
      age: 24,
      bio: 'Enjoys podcasts, brunch and hiking',
      photoUrl: '',
      distanceMeters: 14,
    ),
    _MockUser(
      id: '2',
      firstName: 'Alex',
      age: 22,
      bio: 'Loves coffee shops and live music',
      photoUrl: '',
      distanceMeters: 22,
      isGold: true,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: _buildAppBar(),
      body: SafeArea(
        top: false,
        child: _isLive ? _buildCarousel() : _buildNotLiveState(),
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

  Widget _buildCarousel() {
    if (_nearbyUsers.isEmpty) {
      return _buildEmptyState();
    }

    return ListView.separated(
      padding: const EdgeInsets.only(top: 8, bottom: 32),
      itemCount: _nearbyUsers.length,
      separatorBuilder: (context, index) => const SizedBox(height: 32),
      itemBuilder: (context, i) {
        final u = _nearbyUsers[i];
        return CarouselCard(
          firstName: u.firstName,
          age: u.age,
          bio: u.bio,
          photoUrl: u.photoUrl,
          distanceMeters: u.distanceMeters,
          isGold: u.isGold,
          onSendIcebreaker: () => _navigateSendIcebreaker(u),
        );
      },
    );
  }

  void _navigateSendIcebreaker(_MockUser user) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _SendIcebreakerPlaceholder(recipientName: user.firstName),
      ),
    );
  }

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

// Temporary placeholder until SendIcebreakerScreen is wired via go_router
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

class _MockUser {
  const _MockUser({
    required this.id,
    required this.firstName,
    required this.age,
    required this.bio,
    required this.photoUrl,
    required this.distanceMeters,
    this.isGold = false,
  });
  final String id;
  final String firstName;
  final int age;
  final String bio;
  final String photoUrl;
  final double distanceMeters;
  final bool isGold;
}
