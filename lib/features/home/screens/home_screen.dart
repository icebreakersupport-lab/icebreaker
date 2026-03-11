import 'package:flutter/material.dart';
import '../../../core/state/live_session.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/gradient_scaffold.dart';
import '../../../shared/widgets/icebreaker_logo.dart';
import '../../../shared/widgets/pill_button.dart';

/// Home tab — the "GO LIVE" entry point.
///
/// Live state is read from and written to the global [LiveSession] via
/// [LiveSessionScope]. No local isLive flag — the logo and UI rebuild
/// automatically when the session changes.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isLoading = false;

  Future<void> _handleGoLive() async {
    setState(() => _isLoading = true);
    // TODO: call goLive() Cloud Function + navigate to selfie capture
    await Future.delayed(const Duration(milliseconds: 500));
    setState(() => _isLoading = false);
    if (mounted) LiveSessionScope.of(context).setLive(true);
  }

  void _handleEndSession() {
    LiveSessionScope.of(context).setLive(false);
    // TODO: call endSession() Cloud Function
  }

  @override
  Widget build(BuildContext context) {
    final isLive = LiveSessionScope.isLive(context);

    return GradientScaffold(
      showTopGlow: true,
      appBar: _buildAppBar(),
      body: SafeArea(
        top: false,
        child: isLive ? _buildLiveState() : _buildOfflineState(),
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

          const IcebreakerLogo(size: 140, showGlow: true),

          const SizedBox(height: 32),

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

          PillButton.primary(
            label: 'GO LIVE',
            onTap: _handleGoLive,
            isLoading: _isLoading,
            width: double.infinity,
            height: 64,
          ),

          const SizedBox(height: 16),

          Text(
            '1 Live session available · 3 Icebreakers remaining',
            style: AppTextStyles.caption,
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 16),
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

          // Logo — animation is driven by global LiveSession, no wrapper needed.
          const IcebreakerLogo(size: 140, showGlow: true),

          const SizedBox(height: 24),

          // Live badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
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

          Text(
            'Session expires in 59:59',
            style: AppTextStyles.caption,
          ),

          const SizedBox(height: 20),

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
