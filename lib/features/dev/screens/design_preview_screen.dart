import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/gradient_scaffold.dart';
import '../../../shared/widgets/icebreaker_logo.dart';
import '../../home/screens/home_screen.dart';
import '../../nearby/screens/nearby_screen.dart';
import '../../nearby/screens/send_icebreaker_screen.dart';
import '../../messages/screens/messages_screen.dart';
import '../../profile/screens/profile_screen.dart';
import '../../meetup/screens/icebreaker_received_screen.dart';
import '../../meetup/screens/matched_screen.dart';
import '../../meetup/screens/color_match_screen.dart';
import '../../meetup/screens/post_meet_screen.dart';
import '../../meetup/screens/match_confirmed_screen.dart';
import '../../onboarding/screens/onboarding_photo_screen.dart';
import '../../onboarding/screens/onboarding_slideshow_screen.dart';

/// Temporary development-only screen — lists every implemented screen
/// for quick visual inspection during the UI polish pass.
///
/// Remove this screen and its route (/preview) before shipping.
class DesignPreviewScreen extends StatelessWidget {
  const DesignPreviewScreen({super.key});

  // Warm orange used for meetup-flow mock data so match-colour glows are visible.
  static const Color _mockColor = Color(0xFFFF6B35);

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      showTopGlow: true,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 48),
          children: [
            _buildHeader(),
            const SizedBox(height: 32),
            _buildSection(
              title: 'Onboarding Flow',
              items: [
                _Item(
                  label: 'Name',
                  icon: Icons.badge_outlined,
                  onTap: (ctx) => ctx.go(AppRoutes.onboardingName),
                ),
                _Item(
                  label: 'Birthday',
                  icon: Icons.cake_outlined,
                  onTap: (ctx) => ctx.go(AppRoutes.onboardingBirthday),
                ),
                _Item(
                  label: 'Gender',
                  icon: Icons.people_outline_rounded,
                  onTap: (ctx) => ctx.go(AppRoutes.onboardingGender),
                ),
                _Item(
                  label: 'Open To',
                  icon: Icons.favorite_border_rounded,
                  onTap: (ctx) => ctx.go(AppRoutes.onboardingOpenTo),
                ),
                _Item(
                  label: 'Orientation',
                  icon: Icons.tune_rounded,
                  onTap: (ctx) => ctx.go(AppRoutes.onboardingOrientation),
                ),
                _Item(
                  label: 'Location',
                  icon: Icons.location_on_outlined,
                  onTap: (ctx) => ctx.go(AppRoutes.onboardingLocation),
                ),
                _Item(
                  label: 'First Photo',
                  icon: Icons.add_a_photo_outlined,
                  onTap: (ctx) => _push(ctx, const OnboardingPhotoScreen()),
                ),
                _Item(
                  label: 'Slideshow',
                  icon: Icons.slideshow_rounded,
                  onTap: (ctx) => _push(ctx, const OnboardingSlideshowScreen()),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildSection(
              title: 'Shell Tabs',
              items: [
                _Item(
                  label: 'Home',
                  icon: Icons.home_rounded,
                  onTap: (ctx) => _push(ctx, const HomeScreen()),
                ),
                _Item(
                  label: 'Nearby',
                  icon: Icons.explore_rounded,
                  onTap: (ctx) => _push(ctx, const NearbyScreen()),
                ),
                _Item(
                  label: 'Messages',
                  icon: Icons.chat_bubble_outline_rounded,
                  onTap: (ctx) => _push(ctx, const MessagesScreen()),
                ),
                _Item(
                  label: 'Profile',
                  icon: Icons.person_outline_rounded,
                  onTap: (ctx) => _push(ctx, const ProfileScreen()),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildSection(
              title: 'Icebreaker Flow',
              items: [
                _Item(
                  label: 'Send Icebreaker',
                  icon: Icons.send_rounded,
                  onTap: (ctx) => _push(
                    ctx,
                    const SendIcebreakerScreen(
                      recipientId: 'preview_user_1',
                      recipientFirstName: 'Jordan',
                      recipientAge: 24,
                      recipientPhotoUrl: '',
                      recipientBio: 'Enjoys podcasts, brunch and hiking',
                    ),
                  ),
                ),
                _Item(
                  label: 'Icebreaker Received',
                  icon: Icons.notifications_rounded,
                  onTap: (ctx) => _push(
                    ctx,
                    const IcebreakerReceivedScreen(
                      icebreakerId: 'preview_ib_1',
                      senderFirstName: 'Alex',
                      senderAge: 22,
                      senderPhotoUrl: '',
                      myPhotoUrl: '',
                      myFirstName: 'You',
                      message:
                          'Hey! I noticed you earlier — great book choice. Want to grab a coffee?',
                      secondsRemaining: 295,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildSection(
              title: 'Meetup Flow',
              items: [
                _Item(
                  label: 'Matched — Finding',
                  icon: Icons.location_searching_rounded,
                  onTap: (ctx) => _push(
                    ctx,
                    const MatchedScreen(
                      meetupId: 'preview_meetup_1',
                      matchColor: _mockColor,
                      otherFirstName: 'Jordan',
                      otherPhotoUrl: '',
                      myFirstName: 'You',
                      myPhotoUrl: '',
                      findSecondsRemaining: 299,
                    ),
                  ),
                ),
                _Item(
                  label: 'Color Match — In Convo',
                  icon: Icons.palette_rounded,
                  onTap: (ctx) => _push(
                    ctx,
                    const ColorMatchScreen(
                      meetupId: 'preview_meetup_1',
                      matchColor: _mockColor,
                      otherFirstName: 'Jordan',
                      otherPhotoUrl: '',
                      myFirstName: 'You',
                      myPhotoUrl: '',
                      conversationSecondsRemaining: 599,
                    ),
                  ),
                ),
                _Item(
                  label: 'Post Meet — Connection?',
                  icon: Icons.favorite_outline_rounded,
                  onTap: (ctx) => _push(
                    ctx,
                    const PostMeetScreen(
                      meetupId: 'preview_meetup_1',
                      matchColor: _mockColor,
                      otherFirstName: 'Jordan',
                      otherPhotoUrl: '',
                    ),
                  ),
                ),
                _Item(
                  label: 'Match Confirmed — Chat Open',
                  icon: Icons.check_circle_outline_rounded,
                  onTap: (ctx) => _push(
                    ctx,
                    const MatchConfirmedScreen(
                      conversationId: 'preview_conv_1',
                      otherFirstName: 'Jordan',
                      otherPhotoUrl: '',
                      matchColor: _mockColor,
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

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const IcebreakerLogo(size: 52, showGlow: true),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Icebreaker', style: AppTextStyles.h2),
                  Text(
                    'Design Preview',
                    style: AppTextStyles.bodyS.copyWith(
                      color: AppColors.brandCyan,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.warning.withValues(alpha: 0.30),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: AppColors.warning,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                'Dev only — remove before launch',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.warning,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSection({
    required String title,
    required List<_Item> items,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(title.toUpperCase(), style: AppTextStyles.overline),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.bgSurface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.divider),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (int i = 0; i < items.length; i++) ...[
                _PreviewRow(item: items[i]),
                if (i < items.length - 1)
                  const Divider(
                    height: 1,
                    indent: 66,
                    endIndent: 0,
                    color: AppColors.divider,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Item {
  const _Item({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final void Function(BuildContext) onTap;
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.item});

  final _Item item;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => item.onTap(context),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: AppColors.brandGradient,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(item.icon, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                item.label,
                style: AppTextStyles.body.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textMuted,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
