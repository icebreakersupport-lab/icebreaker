import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/state/live_session.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/gradient_scaffold.dart';
import '../../../shared/widgets/icebreaker_logo.dart';
import '../../../shared/widgets/pill_button.dart';
import '../../profile/screens/profile_screen.dart';
import '../../shop/screens/shop_screen.dart';
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
      appBar: _buildAppBar(session),
      body: SafeArea(
        top: false,
        child: session.isLive
            ? _buildLiveState(session)
            : _buildOfflineState(),
      ),
    );
  }

  // ── App bar ───────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar(LiveSession session) {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      // Profile avatar — shows live selfie when available; taps into preview.
      leading: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: Center(
          child: GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ProfileScreen(),
              ),
            ),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: session.isLive
                      ? AppColors.brandPink
                      : AppColors.textMuted.withValues(alpha: 0.35),
                  width: session.isLive ? 2.0 : 1.0,
                ),
                boxShadow: session.isLive
                    ? [
                        BoxShadow(
                          color: AppColors.brandPink.withValues(alpha: 0.30),
                          blurRadius: 12,
                          spreadRadius: 0,
                        ),
                      ]
                    : null,
              ),
              child: ClipOval(
                child: session.selfieFilePath != null
                    ? Image.file(
                        File(session.selfieFilePath!),
                        fit: BoxFit.cover,
                        width: 36,
                        height: 36,
                      )
                    : const Center(
                        child: Icon(
                          Icons.person_outline_rounded,
                          color: AppColors.textMuted,
                          size: 20,
                        ),
                      ),
              ),
            ),
          ),
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
        Padding(
          padding: const EdgeInsets.only(right: 12, top: 9, bottom: 9),
          child: GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ShopScreen(),
              ),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                gradient: AppColors.brandGradient,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.brandPink.withValues(alpha: 0.38),
                    blurRadius: 12,
                    spreadRadius: 0,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                'SHOP',
                style: AppTextStyles.caption.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.6,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Offline state ─────────────────────────────────────────────────────────

  Widget _buildOfflineState() {
    return Column(
      children: [
        const SizedBox(height: 16),

        // ── Status counters — between header and hero logo ─────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Row(
            children: [
              Expanded(
                child: _StatusPill(
                  icon: Icons.bolt_rounded,
                  iconColor: AppColors.brandPink,
                  count: '1',
                  label: 'Live Session',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatusPill(
                  icon: Icons.ac_unit_rounded,
                  iconColor: AppColors.brandCyan,
                  count: '3',
                  label: 'Icebreakers',
                ),
              ),
            ],
          ),
        ),

        // ── Hero logo — Expanded so it takes all remaining vertical space
        // between the status row and the CTA, never forcing an overflow.
        // LayoutBuilder sizes the logo up to 480px based on actual height.
        Expanded(
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // Ambient radial glow — Positioned so it doesn't affect layout
              Positioned(
                left: -80,
                right: -80,
                top: -80,
                bottom: -80,
                child: Container(
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
              ),
              // Logo — sized to available height, capped at 480px
              LayoutBuilder(
                builder: (_, constraints) {
                  final size = constraints.maxHeight.clamp(100.0, 480.0);
                  return IcebreakerLogo(size: size, showGlow: false);
                },
              ),
            ],
          ),
        ),

        // ── CTA section ───────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 20),
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

              const SizedBox(height: 16),

              // Primary supporting copy
              Text(
                'Go Live to appear on the radar for people around you',
                style: AppTextStyles.bodyS.copyWith(
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 4),

              // Secondary supporting copy
              Text(
                'Same building, venue, or nearby social setting',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textMuted,
                ),
                textAlign: TextAlign.center,
              ),
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

// ── Status pill ───────────────────────────────────────────────────────────────

/// Branded counter chip used on the Home offline state.
/// Displays an icon, a bold count, and a muted label — styled with a dark
/// surface, a soft colored border, and a matching neon glow shadow.
class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.icon,
    required this.iconColor,
    required this.count,
    required this.label,
  });

  final IconData icon;
  final Color iconColor;
  final String count;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: iconColor.withValues(alpha: 0.28),
        ),
        boxShadow: [
          BoxShadow(
            color: iconColor.withValues(alpha: 0.14),
            blurRadius: 20,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Row(
        children: [
          // Icon badge
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: iconColor.withValues(alpha: 0.22),
              ),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 10),
          // Count + label
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                count,
                style: AppTextStyles.h3.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
              Text(
                label,
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
