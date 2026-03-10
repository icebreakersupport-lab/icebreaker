import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/pill_button.dart';
import '../../../core/constants/app_constants.dart';

/// Send Icebreaker screen.
///
/// Layout (from slide 8):
///   - Full-screen recipient photo with dark gradient overlay
///   - "One message" label at top (centred)
///   - "The worst they can say is no." hint text
///   - Message input field (constrained to [AppConstants.icebreakerMessageMaxLength])
///   - Cyan "Send" pill button at bottom
class SendIcebreakerScreen extends StatefulWidget {
  const SendIcebreakerScreen({
    super.key,
    required this.recipientId,
    required this.recipientFirstName,
    required this.recipientAge,
    required this.recipientPhotoUrl,
    required this.recipientBio,
  });

  final String recipientId;
  final String recipientFirstName;
  final int recipientAge;
  final String recipientPhotoUrl;
  final String recipientBio;

  @override
  State<SendIcebreakerScreen> createState() => _SendIcebreakerScreenState();
}

class _SendIcebreakerScreenState extends State<SendIcebreakerScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _isSending = false;

  int get _charsRemaining =>
      AppConstants.icebreakerMessageMaxLength - _controller.text.length;

  bool get _canSend =>
      _controller.text.trim().isNotEmpty && !_isSending;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
    // Auto-focus keyboard
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _focusNode.requestFocus(),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _handleSend() async {
    if (!_canSend) return;
    setState(() => _isSending = true);
    // TODO: call sendIcebreaker() Cloud Function with message
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    setState(() => _isSending = false);
    Navigator.of(context).pop();
    // TODO: show confirmation snack / navigate to Messages
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          // ── Background photo ──────────────────────────────────────────────
          Positioned.fill(
            child: widget.recipientPhotoUrl.isNotEmpty
                ? Image.network(
                    widget.recipientPhotoUrl,
                    fit: BoxFit.cover,
                  )
                : Container(
                    color: AppColors.bgSurface,
                    child: const Icon(Icons.person_rounded,
                        size: 120, color: AppColors.textMuted),
                  ),
          ),

          // Full overlay gradient (top: light, bottom: heavier)
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x66000000),
                    Color(0xDD000000),
                  ],
                  stops: [0.0, 0.6],
                ),
              ),
            ),
          ),

          // ── Content ───────────────────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),

                  // Recipient name + age
                  Center(
                    child: Column(
                      children: [
                        Text(
                          widget.recipientFirstName,
                          style: AppTextStyles.h1,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'One message · The worst they can say is no.',
                          style: AppTextStyles.bodyS,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),

                  const Spacer(),

                  // Message input
                  _MessageInputField(
                    controller: _controller,
                    focusNode: _focusNode,
                    maxLength: AppConstants.icebreakerMessageMaxLength,
                    charsRemaining: _charsRemaining,
                  ),

                  const SizedBox(height: 16),

                  // Send button
                  PillButton.cyan(
                    label: 'Send 🧊',
                    onTap: _canSend ? _handleSend : null,
                    isLoading: _isSending,
                    width: double.infinity,
                    height: 56,
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageInputField extends StatelessWidget {
  const _MessageInputField({
    required this.controller,
    required this.focusNode,
    required this.maxLength,
    required this.charsRemaining,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final int maxLength;
  final int charsRemaining;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.brandCyan.withValues(alpha: 0.4),
              width: 1,
            ),
          ),
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            maxLines: 4,
            minLines: 2,
            maxLength: maxLength,
            buildCounter: (_, {required currentLength, required isFocused, maxLength}) =>
                null, // Hide default counter — we show our own
            style: AppTextStyles.body,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'Say something genuine...',
              hintStyle:
                  AppTextStyles.body.copyWith(color: AppColors.textMuted),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '$charsRemaining',
          style: AppTextStyles.caption.copyWith(
            color: charsRemaining < 20
                ? AppColors.warning
                : AppColors.textMuted,
          ),
        ),
      ],
    );
  }
}
