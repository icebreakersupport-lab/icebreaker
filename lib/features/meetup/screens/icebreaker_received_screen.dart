import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/countdown_timer_widget.dart';
import '../../../shared/widgets/gradient_scaffold.dart';
import '../../../shared/widgets/pill_button.dart';
import '../../../core/constants/app_constants.dart';

/// Screen shown to the recipient when an icebreaker is received.
///
/// Layout (from slide 9):
///   - "MATCHED!" hero text
///   - Two circular profile photos (sender | recipient)
///   - Sender's icebreaker message
///   - Countdown timer (5:00)
///   - Accept / Decline buttons
class IcebreakerReceivedScreen extends StatefulWidget {
  const IcebreakerReceivedScreen({
    super.key,
    required this.icebreakerId,
    required this.senderFirstName,
    required this.senderAge,
    required this.senderPhotoUrl,
    required this.myPhotoUrl,
    required this.myFirstName,
    required this.message,
    required this.secondsRemaining,
  });

  final String icebreakerId;
  final String senderFirstName;
  final int senderAge;
  final String senderPhotoUrl;
  final String myPhotoUrl;
  final String myFirstName;
  final String message;
  final int secondsRemaining;

  @override
  State<IcebreakerReceivedScreen> createState() =>
      _IcebreakerReceivedScreenState();
}

class _IcebreakerReceivedScreenState
    extends State<IcebreakerReceivedScreen> {
  bool _isResponding = false;

  Future<void> _respond(bool accept) async {
    setState(() => _isResponding = true);
    // TODO: call respondToIcebreaker() Cloud Function
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    setState(() => _isResponding = false);

    if (accept) {
      // TODO: navigate to MatchedScreen with conversationId + meetupId
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      showTopGlow: true,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const SizedBox(height: 24),

              // ── MATCHED! label ───────────────────────────────────────────
              ShaderMask(
                shaderCallback: (bounds) =>
                    AppColors.brandGradient.createShader(bounds),
                child: Text(
                  'MATCHED!',
                  style: AppTextStyles.displayLabel.copyWith(
                    fontSize: 44,
                    letterSpacing: 2.5,
                    color: Colors.white, // masked by shader
                  ),
                ),
              ),

              const SizedBox(height: 8),
              Text(
                'You caught each other\'s eye',
                style: AppTextStyles.bodyS,
              ),

              const SizedBox(height: 36),

              // ── Profile photo pair ───────────────────────────────────────
              _ProfilePhotoPair(
                leftPhotoUrl: widget.senderPhotoUrl,
                leftName: widget.senderFirstName,
                rightPhotoUrl: widget.myPhotoUrl,
                rightName: widget.myFirstName,
              ),

              const SizedBox(height: 28),

              // ── Message bubble ───────────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.bgSurface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.senderFirstName,
                      style: AppTextStyles.buttonS.copyWith(
                          color: AppColors.brandCyan),
                    ),
                    const SizedBox(height: 6),
                    Text(widget.message, style: AppTextStyles.bodyL),
                  ],
                ),
              ),

              const Spacer(),

              // ── Countdown ────────────────────────────────────────────────
              CountdownTimerWidget(
                initialSeconds: widget.secondsRemaining,
                onExpired: () => Navigator.of(context).pop(),
                warningThresholdSeconds: AppConstants.icebreakerWarningSeconds,
              ),

              const SizedBox(height: 6),
              Text('to respond', style: AppTextStyles.bodyS),

              const SizedBox(height: 32),

              // ── Actions ──────────────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: PillButton.danger(
                      label: 'Pass',
                      onTap: _isResponding ? null : () => _respond(false),
                      height: 60,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: PillButton.primary(
                      label: 'Accept 🧊',
                      onTap: _isResponding ? null : () => _respond(true),
                      isLoading: _isResponding,
                      height: 60,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfilePhotoPair extends StatelessWidget {
  const _ProfilePhotoPair({
    required this.leftPhotoUrl,
    required this.leftName,
    required this.rightPhotoUrl,
    required this.rightName,
  });

  final String leftPhotoUrl;
  final String leftName;
  final String rightPhotoUrl;
  final String rightName;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        _CirclePhoto(url: leftPhotoUrl, name: leftName),
        const SizedBox(width: 8),
        // Heart connector (centred between the two photos)
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            gradient: AppColors.brandGradient,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.bgBase, width: 2),
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.favorite_rounded, size: 16, color: Colors.white),
        ),
        const SizedBox(width: 8),
        _CirclePhoto(url: rightPhotoUrl, name: rightName),
      ],
    );
  }
}

class _CirclePhoto extends StatelessWidget {
  const _CirclePhoto({required this.url, required this.name});
  final String url;
  final String name;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: AppColors.brandGradient,
          ),
          child: CircleAvatar(
            radius: 58,
            backgroundColor: AppColors.bgElevated,
            backgroundImage: url.isNotEmpty ? NetworkImage(url) : null,
            child: url.isEmpty
                ? Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: AppTextStyles.h1.copyWith(
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
