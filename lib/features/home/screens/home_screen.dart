import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/state/live_session.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/gradient_scaffold.dart';
import '../../../shared/widgets/icebreaker_logo.dart';
import '../../../shared/widgets/pill_button.dart';
import 'live_verification_screen.dart';

/// Home tab — the "GO LIVE" entry point.
///
/// Live state is read from and written to the global [LiveSession] via
/// [LiveSessionScope]. Tapping GO LIVE navigates to [LiveVerificationScreen];
/// only after the selfie is verified does the session become active here.
///
/// A per-second [Timer] drives the live countdown display. The timer is
/// started/stopped automatically via [didChangeDependencies] when the
/// session transitions between live/offline.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Timer? _countdownTimer;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncCountdownTimer(LiveSessionScope.isLive(context));
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _syncCountdownTimer(bool isLive) {
    if (isLive && (_countdownTimer == null || !_countdownTimer!.isActive)) {
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!isLive) {
      _countdownTimer?.cancel();
      _countdownTimer = null;
    }
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  void _handleGoLive() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const LiveVerificationScreen(),
      ),
    );
  }

  void _handleEndSession() {
    LiveSessionScope.of(context).endSession();
    // TODO: call endSession() Cloud Function
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final session = LiveSessionScope.of(context);
    _syncCountdownTimer(session.isLive);

    return GradientScaffold(
      showTopGlow: true,
      appBar: _buildAppBar(),
      body: SafeArea(
        top: false,
        child: session.isLive
            ? _buildLiveState(session)
            : _buildOfflineState(),
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
          icon: const Icon(
            Icons.notifications_none_rounded,
            color: AppColors.textSecondary,
          ),
          onPressed: () {
            // TODO: open notifications
          },
        ),
      ],
    );
  }

  // ── Offline state ─────────────────────────────────────────────────────────

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
            width: double.infinity,
            height: 64,
          ),

          const SizedBox(height: 16),

          Text(
            '1 Live session available  ·  3 Icebreakers remaining',
            style: AppTextStyles.caption,
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ── Live state ────────────────────────────────────────────────────────────

  Widget _buildLiveState(LiveSession session) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          const Spacer(flex: 2),

          // Logo — heartbeat driven by LiveSession, no wrapper needed
          const IcebreakerLogo(size: 140, showGlow: true),

          const SizedBox(height: 20),

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
                  style:
                      AppTextStyles.buttonS.copyWith(letterSpacing: 1.2),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Live selfie avatar
          _buildLiveSelfieAvatar(session),

          const SizedBox(height: 16),

          Text(
            'People nearby can see you now',
            style: AppTextStyles.bodyS,
            textAlign: TextAlign.center,
          ),

          const Spacer(flex: 3),

          // Live countdown
          Text(
            'Session expires in ${_formatDuration(session.remainingDuration)}',
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

  Widget _buildLiveSelfieAvatar(LiveSession session) {
    final path = session.selfieFilePath;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.brandPink, width: 2),
            boxShadow: [
              BoxShadow(
                color: AppColors.brandPink.withValues(alpha: 0.20),
                blurRadius: 16,
                spreadRadius: 2,
              ),
            ],
          ),
          child: ClipOval(
            child: path != null
                ? Image.file(File(path), fit: BoxFit.cover)
                : const Icon(
                    Icons.person_rounded,
                    color: AppColors.textMuted,
                    size: 36,
                  ),
          ),
        ),
        const SizedBox(height: 6),
        Text('Your live photo', style: AppTextStyles.caption),
      ],
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _formatDuration(Duration d) {
    if (d <= Duration.zero) return '0:00:00';
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}
