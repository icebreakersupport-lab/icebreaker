import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/gradient_scaffold.dart';
import '../../../shared/widgets/pill_button.dart';

/// Post-meet decision screen — the connection check.
///
/// Layout (from slide 11):
///   - "Did you feel a connection?" header
///   - Large profile photo of the other user
///   - YES / NO decision buttons (large, side-by-side)
///   - If already submitted: waiting state shown
class PostMeetScreen extends StatefulWidget {
  const PostMeetScreen({
    super.key,
    required this.meetupId,
    required this.matchColor,
    required this.otherFirstName,
    required this.otherPhotoUrl,
  });

  final String meetupId;
  final Color matchColor;
  final String otherFirstName;
  final String otherPhotoUrl;

  @override
  State<PostMeetScreen> createState() => _PostMeetScreenState();
}

class _PostMeetScreenState extends State<PostMeetScreen> {
  String? _myDecision; // 'we_got_this' | 'nice_meeting_you'
  bool _isSubmitting = false;
  bool _isWaiting = false;

  Future<void> _submit(String decision) async {
    setState(() => _isSubmitting = true);
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    setState(() {
      _isSubmitting = false;
      _myDecision = decision;
      _isWaiting = true;
    });
    if (decision == 'we_got_this') {
      // Demo: simulate the other person also saying yes, then unlock chat.
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      context.push(AppRoutes.matchConfirmed, extra: {
        'conversationId': 'demo_conv_${widget.meetupId}',
        'otherFirstName': widget.otherFirstName,
        'otherPhotoUrl': widget.otherPhotoUrl,
        'matchColor': widget.matchColor,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    // Avatar scales with screen height; clamped so it stays usable on all sizes.
    final avatarRadius = (h * 0.11).clamp(56.0, 80.0);

    // Back navigation is blocked while the user still needs to make their
    // decision (_isWaiting == false).  Once submitted (_isWaiting == true)
    // back is allowed — in a real build the screen auto-advances on the
    // server response; in the demo this prevents a dead-end.
    return PopScope(
      canPop: _isWaiting,
      child: GradientScaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const SizedBox(height: 32),

              Text(
                'Did you feel a connection?',
                style: AppTextStyles.h2,
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 8),

              Text(
                'Your answer is private.\n${widget.otherFirstName} will never see your choice.',
                style: AppTextStyles.bodyS,
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 40),

              // Profile photo (large, centred)
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      widget.matchColor,
                      widget.matchColor.withValues(alpha: 0.6),
                    ],
                  ),
                ),
                child: CircleAvatar(
                  radius: avatarRadius,
                  backgroundColor: AppColors.bgElevated,
                  backgroundImage: widget.otherPhotoUrl.isNotEmpty
                      ? NetworkImage(widget.otherPhotoUrl)
                      : null,
                  child: widget.otherPhotoUrl.isEmpty
                      ? Text(
                          widget.otherFirstName.isNotEmpty
                              ? widget.otherFirstName[0].toUpperCase()
                              : '?',
                          style: AppTextStyles.display
                              .copyWith(color: AppColors.textSecondary),
                        )
                      : null,
                ),
              ),

              const SizedBox(height: 16),

              Text(widget.otherFirstName, style: AppTextStyles.h2),

              const Spacer(),

              if (_isWaiting)
                _WaitingState(
                  decision: _myDecision!,
                  otherFirstName: widget.otherFirstName,
                  onDone: () => context.go(AppRoutes.messages),
                )
              else
                _DecisionButtons(
                  isSubmitting: _isSubmitting,
                  onYes: () => _submit('we_got_this'),
                  onNo: () => _submit('nice_meeting_you'),
                ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    ));
  }
}

class _DecisionButtons extends StatelessWidget {
  const _DecisionButtons({
    required this.isSubmitting,
    required this.onYes,
    required this.onNo,
  });

  final bool isSubmitting;
  final VoidCallback onYes;
  final VoidCallback onNo;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'Your answer is visible only to you.',
          style: AppTextStyles.caption,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: PillButton.danger(
                label: 'Nice meeting you 👋',
                onTap: isSubmitting ? null : onNo,
                height: 64,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: PillButton.success(
                label: 'We got this! 🔥',
                onTap: isSubmitting ? null : onYes,
                isLoading: isSubmitting,
                height: 64,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _WaitingState extends StatelessWidget {
  const _WaitingState({
    required this.decision,
    required this.otherFirstName,
    this.onDone,
  });

  final String decision;
  final String otherFirstName;
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    final choseYes = decision == 'we_got_this';
    return Column(
      children: [
        Icon(
          choseYes
              ? Icons.favorite_rounded
              : Icons.waving_hand_rounded,
          size: 48,
          color: choseYes ? AppColors.success : AppColors.textSecondary,
        ),
        const SizedBox(height: 16),
        Text(
          choseYes
              ? 'Waiting for $otherFirstName...'
              : 'Nice meeting $otherFirstName 👋',
          style: AppTextStyles.h3,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          choseYes
              ? 'If they feel the same, chat opens up!'
              : 'Sometimes it\'s just not the moment.',
          style: AppTextStyles.bodyS,
          textAlign: TextAlign.center,
        ),
        if (!choseYes && onDone != null) ...[
          const SizedBox(height: 24),
          PillButton.outlined(
            label: 'Back to Messages',
            onTap: onDone,
            width: double.infinity,
          ),
        ],
      ],
    );
  }
}
