import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/gradient_scaffold.dart';
import '../../../shared/widgets/icebreaker_logo.dart';
import '../../../shared/widgets/pill_button.dart';

/// Chat unlocked — both users chose "We Got This".
///
/// Layout (from slide 12):
///   - "It's a match!" hero text with glowing logo
///   - Subtext about continuing in the app
///   - "Start chatting" / "Done" CTA
class MatchConfirmedScreen extends StatelessWidget {
  const MatchConfirmedScreen({
    super.key,
    required this.conversationId,
    required this.otherFirstName,
    required this.otherPhotoUrl,
    required this.matchColor,
  });

  final String conversationId;
  final String otherFirstName;
  final String otherPhotoUrl;
  final Color matchColor;

  @override
  Widget build(BuildContext context) {
    // Back navigation blocked — this is the terminal success screen.
    // Going back to PostMeetScreen after a mutual match makes no sense.
    // "Start Chatting" and "Done" are the intended exits.
    return PopScope(
      canPop: false,
      child: GradientScaffold(
        showTopGlow: true,
      body: Stack(
        children: [
          // Match colour ambient
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 1.2,
                  colors: [
                    matchColor.withValues(alpha: 0.30),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  const Spacer(flex: 2),

                  const IcebreakerLogo(size: 100, showGlow: true),

                  const SizedBox(height: 32),

                  ShaderMask(
                    shaderCallback: (bounds) =>
                        AppColors.brandGradient.createShader(bounds),
                    child: Text(
                      "It's a match!",
                      style: AppTextStyles.h1.copyWith(
                        fontSize: 40,
                        color: Colors.white, // masked by shader
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  Text(
                    'You and $otherFirstName both felt the connection.\nChat is now open — keep it going!',
                    style: AppTextStyles.bodyL,
                    textAlign: TextAlign.center,
                  ),

                  const Spacer(flex: 3),

                  PillButton.primary(
                    label: 'Start Chatting 💬',
                    onTap: () {
                      // TODO: navigate to ChatScreen with conversationId
                    },
                    width: double.infinity,
                    height: 60,
                  ),

                  const SizedBox(height: 16),

                  PillButton.outlined(
                    label: 'Done',
                    onTap: () {
                      // TODO: navigate back to Messages tab
                    },
                    width: double.infinity,
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    ));
  }
}
