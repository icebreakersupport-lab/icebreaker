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
/// Offline state: hero logo + GO LIVE CTA + supporting copy below.
/// Live state: pulsing logo + YOU'RE LIVE badge + selfie avatar + countdown.
///
/// Live state is owned by the global [LiveSession] via [LiveSessionScope].
/// A per-second [Timer] drives the countdown — started/stopped automatically
/// by [didChangeDependencies].
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

  // ── App bar ───────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      // Subtle left icon — balanced with the right action
      leading: Padding(
        padding: const EdgeInsets.only(left: 8),
        child: IconButton(
          icon: const Icon(
            Icons.person_outline_rounded,
            color: AppColors.textMuted,
            size: 22,
          ),
          onPressed: () {
            // TODO: open own profile
          },
        ),
      ),
      // "icebreaker •" — lowercase + green live-status dot
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'icebreaker',
            style: AppTextStyles.h3.copyWith(
              letterSpacing: 0.3,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: AppColors.success,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(
            Icons.notifications_none_rounded,
            color: AppColors.textMuted,
            size: 22,
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
    return Column(
      children: [
        const Spacer(flex: 3),

        // ── Hero logo with atmospheric glow ──────────────────────────────
        // The glow here is always-on — it's part of the brand identity
        // presentation on the home screen, independent of live state.
        Stack(
          alignment: Alignment.center,
          children: [
            // Ambient radial glow behind the logo
            Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.brandPink.withValues(alpha: 0.20),
                    AppColors.brandPurple.withValues(alpha: 0.12),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
            // Logo — IcebreakerLogo's own glow only activates when live
            const IcebreakerLogo(size: 192, showGlow: false),
          ],
        ),

        const Spacer(flex: 2),

        // ── CTA section ───────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Primary CTA — tall, gradient pill, full width
              PillButton.primary(
                label: 'GO LIVE',
                onTap: _handleGoLive,
                width: double.infinity,
                height: 68,
              ),

              const SizedBox(height: 20),

              // Primary supporting copy
              Text(
                'Go Live to appear on the radar for people around you',
                style: AppTextStyles.bodyS.copyWith(
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 5),

              // Secondary supporting copy
              Text(
                'Same building, venue, or nearby social setting',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textMuted,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 20),

              // Session / quota info
              Text(
                '1 Live session available  ·  3 Icebreakers remaining',
                style: AppTextStyles.caption,
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 28),
            ],
          ),
        ),
      ],
    );
  }

  // ── Live state ────────────────────────────────────────────────────────────

  Widget _buildLiveState(LiveSession session) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          const Spacer(flex: 2),

          // Logo — heartbeat driven by LiveSession
          const IcebreakerLogo(size: 160, showGlow: true),

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
                  style: AppTextStyles.buttonS
                      .copyWith(letterSpacing: 1.2),
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
                color: AppColors.brandPink.withValues(alpha: 0.22),
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
