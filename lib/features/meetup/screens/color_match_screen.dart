import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/countdown_timer_widget.dart';
import '../../../shared/widgets/gradient_scaffold.dart';

/// "In Conversation" state — both users found each other; the 10-min
/// conversation timer is running.
///
/// Layout (from slide 10):
///   - Large countdown timer centre-screen ("4:59")
///   - "COLOR MATCH!" label above the timer
///   - Both profile photo circles with match colour ring
///   - "You're together — make it count!" subtext
///   - Match colour ambient background fill
class ColorMatchScreen extends StatefulWidget {
  const ColorMatchScreen({
    super.key,
    required this.meetupId,
    required this.matchColor,
    required this.otherFirstName,
    required this.otherPhotoUrl,
    required this.myFirstName,
    required this.myPhotoUrl,
    required this.conversationSecondsRemaining,
  });

  final String meetupId;
  final Color matchColor;
  final String otherFirstName;
  final String otherPhotoUrl;
  final String myFirstName;
  final String myPhotoUrl;
  final int conversationSecondsRemaining;

  @override
  State<ColorMatchScreen> createState() => _ColorMatchScreenState();
}

class _ColorMatchScreenState extends State<ColorMatchScreen> {
  @override
  Widget build(BuildContext context) {
    // Back navigation blocked — the conversation timer is active.
    // The screen advances forward when the timer expires.
    return PopScope(
      canPop: false,
      child: GradientScaffold(
        body: Stack(
          children: [
            // Match colour ambient fill (radial from top)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.topCenter,
                    radius: 1.4,
                    colors: [
                      widget.matchColor.withValues(alpha: 0.45),
                      widget.matchColor.withValues(alpha: 0.15),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              ),
            ),

            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  children: [
                    const SizedBox(height: 24),

                    // Profile pair
                    _MatchPhotoPair(
                      leftUrl: widget.myPhotoUrl,
                      leftName: widget.myFirstName,
                      rightUrl: widget.otherPhotoUrl,
                      rightName: widget.otherFirstName,
                      matchColor: widget.matchColor,
                    ),

                    const Spacer(),

                    // COLOR MATCH! label — FittedBox prevents overflow on
                    // narrow screens where fontSize: 40 is too wide.
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'COLOR MATCH!',
                        style: AppTextStyles.displayLabel.copyWith(
                          fontSize: 40,
                          letterSpacing: 2.0,
                          foreground: Paint()
                            ..shader = AppColors.brandGradient.createShader(
                              const Rect.fromLTWH(0, 0, 360, 60),
                            ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Large countdown — the hero element
                    CountdownTimerWidget(
                      initialSeconds: widget.conversationSecondsRemaining,
                      onExpired: () {
                        if (!mounted) return;
                        context.push(AppRoutes.postMeet, extra: {
                          'meetupId': widget.meetupId,
                          'matchColor': widget.matchColor,
                          'otherFirstName': widget.otherFirstName,
                          'otherPhotoUrl': widget.otherPhotoUrl,
                        });
                      },
                    ),

                    const SizedBox(height: 12),

                    Text(
                      "You're together — make it count!",
                      style: AppTextStyles.bodyS,
                      textAlign: TextAlign.center,
                    ),

                    const Spacer(),

                    // Match colour swatch pill
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        color: widget.matchColor.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: widget.matchColor.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: widget.matchColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Your match colour',
                            style: AppTextStyles.bodyS
                                .copyWith(color: widget.matchColor),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),

            // Close button — exits back to Messages without completing the flow.
            Positioned(
              top: 0,
              right: 0,
              child: SafeArea(
                child: IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  onPressed: () => context.go(AppRoutes.messages),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MatchPhotoPair extends StatelessWidget {
  const _MatchPhotoPair({
    required this.leftUrl,
    required this.leftName,
    required this.rightUrl,
    required this.rightName,
    required this.matchColor,
  });

  final String leftUrl;
  final String leftName;
  final String rightUrl;
  final String rightName;
  final Color matchColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _RingedPhoto(url: leftUrl, name: leftName, matchColor: matchColor),
        const SizedBox(width: 20),
        _RingedPhoto(url: rightUrl, name: rightName, matchColor: matchColor),
      ],
    );
  }
}

class _RingedPhoto extends StatelessWidget {
  const _RingedPhoto({
    required this.url,
    required this.name,
    required this.matchColor,
  });

  final String url;
  final String name;
  final Color matchColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: matchColor,
          ),
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.bgBase,
            ),
            child: CircleAvatar(
              radius: 50,
              backgroundColor: AppColors.bgElevated,
              backgroundImage: url.isNotEmpty ? NetworkImage(url) : null,
              child: url.isEmpty
                  ? Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: AppTextStyles.h2
                          .copyWith(color: AppColors.textSecondary),
                    )
                  : null,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(name, style: AppTextStyles.bodyS),
      ],
    );
  }
}
