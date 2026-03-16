import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/countdown_timer_widget.dart';
import '../../../shared/widgets/gradient_scaffold.dart';
import '../../../shared/widgets/pill_button.dart';

/// "Finding" state screen — both users need to physically find each other.
///
/// Layout (from slide 9 / Matched state):
///   - Match colour ambient background
///   - "Find each other!" hero text
///   - Both profile photo circles
///   - 5:00 countdown (find timer)
///   - "I found them" confirmation swipe / button
class MatchedScreen extends StatefulWidget {
  const MatchedScreen({
    super.key,
    required this.meetupId,
    required this.matchColor,
    required this.otherFirstName,
    required this.otherPhotoUrl,
    required this.myFirstName,
    required this.myPhotoUrl,
    required this.findSecondsRemaining,
  });

  final String meetupId;
  final Color matchColor;
  final String otherFirstName;
  final String otherPhotoUrl;
  final String myFirstName;
  final String myPhotoUrl;
  final int findSecondsRemaining;

  @override
  State<MatchedScreen> createState() => _MatchedScreenState();
}

class _MatchedScreenState extends State<MatchedScreen> {
  bool _confirmed = false;
  bool _isConfirming = false;

  Future<void> _handleConfirm() async {
    setState(() => _isConfirming = true);
    // TODO: call confirmMeeting() Cloud Function
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    setState(() {
      _isConfirming = false;
      _confirmed = true;
    });
    // TODO: if both confirmed → navigate to ColorMatchScreen
  }

  @override
  Widget build(BuildContext context) {
    // Back navigation blocked — the find timer and "I found them" button
    // are the only intended exits from this active-flow screen.
    return PopScope(
      canPop: false,
      child: GradientScaffold(
        showTopGlow: false,
      body: Stack(
        children: [
          // Match colour ambient glow
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.topCenter,
                  radius: 1.2,
                  colors: [
                    widget.matchColor.withValues(alpha: 0.35),
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
                  const SizedBox(height: 32),

                  Text(
                    'Find each other! 🧊',
                    style: AppTextStyles.h1,
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 8),

                  Text(
                    'You have 5 minutes to meet in person.',
                    style: AppTextStyles.bodyS,
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 40),

                  // Profile pair with match colour
                  _MatchPhotoPair(
                    leftUrl: widget.myPhotoUrl,
                    leftName: widget.myFirstName,
                    rightUrl: widget.otherPhotoUrl,
                    rightName: widget.otherFirstName,
                    matchColor: widget.matchColor,
                  ),

                  const Spacer(),

                  // Large countdown
                  CountdownTimerWidget(
                    initialSeconds: widget.findSecondsRemaining,
                    onExpired: () {
                      // TODO: handle find expiry on client
                    },
                  ),

                  const SizedBox(height: 8),
                  Text('to find each other', style: AppTextStyles.bodyS),

                  const SizedBox(height: 40),

                  // Confirm button
                  if (_confirmed)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: AppColors.success.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.check_circle_rounded,
                              color: AppColors.success, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Confirmed! Waiting for ${widget.otherFirstName}...',
                            style: AppTextStyles.bodyS.copyWith(
                                color: AppColors.success),
                          ),
                        ],
                      ),
                    )
                  else
                    PillButton.primary(
                      label: 'I found ${widget.otherFirstName}! 👋',
                      onTap: _handleConfirm,
                      isLoading: _isConfirming,
                      width: double.infinity,
                      height: 60,
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
    return LayoutBuilder(
      builder: (context, constraints) {
        // 2 circles (padding:4 each side) + line(56) + gaps(16+16)
        // Available = 4*(radius+4) + 88 → radius = (available-88)/4 - 4
        final radius = ((constraints.maxWidth - 88) / 4 - 4).clamp(36.0, 56.0);
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _PhotoCircle(url: leftUrl, name: leftName, matchColor: matchColor, radius: radius),
            const SizedBox(width: 16),
            Container(
              width: 56,
              height: 4,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [matchColor, matchColor.withValues(alpha: 0.4)],
                ),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 16),
            _PhotoCircle(url: rightUrl, name: rightName, matchColor: matchColor, radius: radius),
          ],
        );
      },
    );
  }
}

class _PhotoCircle extends StatelessWidget {
  const _PhotoCircle({
    required this.url,
    required this.name,
    required this.matchColor,
    this.radius = 56,
  });

  final String url;
  final String name;
  final Color matchColor;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [matchColor, matchColor.withValues(alpha: 0.6)],
            ),
          ),
          child: CircleAvatar(
            radius: radius,
            backgroundColor: AppColors.bgElevated,
            backgroundImage: url.isNotEmpty ? NetworkImage(url) : null,
            child: url.isEmpty
                ? Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: AppTextStyles.h2.copyWith(
                        color: AppColors.textSecondary),
                  )
                : null,
          ),
        ),
        const SizedBox(height: 8),
        Text(name, style: AppTextStyles.bodyS),
      ],
    );
  }
}
