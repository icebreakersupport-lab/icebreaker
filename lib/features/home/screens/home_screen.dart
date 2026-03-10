import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/gradient_scaffold.dart';
import '../../../shared/widgets/icebreaker_logo.dart';
import '../../../shared/widgets/pill_button.dart';

/// Home tab — the "GO LIVE" entry point.
///
/// Layout (from slide 5):
///   - Very dark purple-black background with a subtle top radial glow
///   - "Icebreaker" app name header (centred)
///   - Hero logo (heart + lightning, gradient + glow) centred in the body
///   - "GO LIVE" pill button below the logo (full-width, padded)
///   - Optional session-active state (shown when user is already live)
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isLive = false;
  bool _isLoading = false;

  Future<void> _handleGoLive() async {
    setState(() => _isLoading = true);
    // TODO: call goLive() Cloud Function + navigate to selfie capture
    await Future.delayed(const Duration(milliseconds: 500));
    setState(() {
      _isLoading = false;
      _isLive = true;
    });
  }

  void _handleEndSession() {
    setState(() => _isLive = false);
    // TODO: call endSession() Cloud Function
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      showTopGlow: true,
      appBar: _buildAppBar(),
      body: SafeArea(
        top: false,
        child: _isLive ? _buildLiveState() : _buildOfflineState(),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      title: Text(
        'Icebreaker',
        style: AppTextStyles.h3.copyWith(
          letterSpacing: 0.5,
          color: AppColors.textPrimary,
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.notifications_none_rounded,
              color: AppColors.textSecondary),
          onPressed: () {
            // TODO: open notifications
          },
        ),
      ],
    );
  }

  Widget _buildOfflineState() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          const Spacer(flex: 2),

          // Logo
          const IcebreakerLogo(size: 140, showGlow: true),

          const SizedBox(height: 32),

          // Headline
          Text(
            'Ready to meet\nsomeone nearby?',
            style: AppTextStyles.h1.copyWith(height: 1.2),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 12),

          Text(
            'Go Live to appear on the map for people\naround you — up to 30 metres away.',
            style: AppTextStyles.bodyS,
            textAlign: TextAlign.center,
          ),

          const Spacer(flex: 3),

          // GO LIVE button
          PillButton.primary(
            label: 'GO LIVE',
            onTap: _handleGoLive,
            isLoading: _isLoading,
            width: double.infinity,
            height: 64,
          ),

          const SizedBox(height: 16),

          // Session info hint
          Text(
            '1 Live session available · 3 Icebreakers remaining',
            style: AppTextStyles.caption,
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildLiveState() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          const Spacer(flex: 2),

          // Pulsing logo when live
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.92, end: 1.08),
            duration: const Duration(milliseconds: 1200),
            builder: (context, scale, child) {
              return Transform.scale(scale: scale, child: child);
            },
            onEnd: () => setState(() {}),
            child: const IcebreakerLogo(size: 140, showGlow: true),
          ),

          const SizedBox(height: 24),

          // Live badge
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              gradient: AppColors.brandGradient,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  "YOU'RE LIVE",
                  style: AppTextStyles.buttonS.copyWith(letterSpacing: 1.2),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          Text(
            'People nearby can see you now',
            style: AppTextStyles.bodyS,
            textAlign: TextAlign.center,
          ),

          const Spacer(flex: 3),

          // Session timer (placeholder — will use CountdownTimerWidget + real expiry)
          Text(
            'Session expires in 59:59',
            style: AppTextStyles.caption,
          ),

          const SizedBox(height: 20),

          // End session
          PillButton.outlined(
            label: 'End Session',
            onTap: _handleEndSession,
            width: double.infinity,
          ),

          const SizedBox(height: 16),

          PillButton.primary(
            label: 'Renew Session',
            onTap: () {
              // TODO: renewSession() Cloud Function
            },
            width: double.infinity,
            height: 64,
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
