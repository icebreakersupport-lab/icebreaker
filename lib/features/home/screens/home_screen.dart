import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/state/live_session.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/gradient_scaffold.dart';
import '../../../shared/widgets/icebreaker_logo.dart';
import '../../../shared/widgets/pill_button.dart';

/// Below this width the Home screen switches to its compact layout mode.
/// 400 dp covers all small phones and narrow macOS windows.
const double _kNarrow = 400.0;

/// Home tab — the "GO LIVE" entry point.
///
/// Offline state: hero logo + GO LIVE CTA + supporting copy below.
/// Live state: pulsing logo + YOU'RE LIVE badge + selfie avatar + countdown.
///
/// Responsive behaviour (breakpoint: [_kNarrow] = 400 dp):
///   • narrow  → compact stat strip, tighter padding, shorter copy, smaller CTA
///   • normal  → two-card stat row, full padding, two-line copy, tall CTA
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
    context.push(AppRoutes.liveVerify);
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
            : _buildOfflineState(session),
      ),
    );
  }

  // ── App bar ───────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar(LiveSession session) {
    // Read width here so the SHOP button can compact on narrow screens.
    final isNarrow = MediaQuery.of(context).size.width < _kNarrow;

    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      // Profile avatar — shows live selfie when available; taps into preview.
      leading: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: Center(
          child: GestureDetector(
            onTap: () => context.go(AppRoutes.profile),
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
      // "icebreaker •" — FittedBox prevents overflow on narrow windows.
      title: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
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
      ),
      actions: [
        Padding(
          // Narrow: less outer margin and less horizontal button padding so
          // the title retains room in the AppBar center slot.
          padding: EdgeInsets.only(
            right: isNarrow ? 8 : 12,
            top: 9,
            bottom: 9,
          ),
          child: GestureDetector(
            onTap: () => context.push(AppRoutes.shop),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: isNarrow ? 10 : 16,
              ),
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
                  letterSpacing: isNarrow ? 0.8 : 1.6,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Offline state ─────────────────────────────────────────────────────────

  Widget _buildOfflineState(LiveSession session) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < _kNarrow;
        final hPad = isNarrow ? 16.0 : 32.0;

        return Column(
          children: [
            SizedBox(height: isNarrow ? 10 : 16),

            // ── Stat counters ──────────────────────────────────────────────
            // Narrow: single compact strip (both stats inline, one card).
            // Normal: two side-by-side tall cards.
            Padding(
              padding: EdgeInsets.symmetric(horizontal: hPad),
              child: isNarrow
                  ? _buildCompactStatStrip(session)
                  : _buildFullStatRow(session),
            ),

            // ── Hero logo ─────────────────────────────────────────────────
            // Expanded so it fills the remaining vertical space without
            // forcing the CTA off-screen. LayoutBuilder sizes the logo to
            // the available height, capped at 480 dp.
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  // Ambient radial glow
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
                  // Logo — sized proportionally to the available height
                  LayoutBuilder(
                    builder: (_, c) {
                      final size = c.maxHeight.clamp(80.0, 480.0);
                      return IcebreakerLogo(size: size, showGlow: false);
                    },
                  ),
                ],
              ),
            ),

            // ── CTA section ───────────────────────────────────────────────
            Padding(
              padding: EdgeInsets.fromLTRB(
                hPad, 0, hPad, isNarrow ? 14 : 20,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PillButton.primary(
                    label: 'GO LIVE',
                    onTap: _handleGoLive,
                    width: double.infinity,
                    // Narrow: slightly shorter button to save vertical space.
                    height: isNarrow ? 58 : 68,
                  ),

                  SizedBox(height: isNarrow ? 10 : 16),

                  // Primary supporting copy — condensed for narrow screens.
                  Text(
                    isNarrow
                        ? 'Go Live — appear on nearby radars'
                        : 'Go Live to appear on the radar for people around you',
                    style: AppTextStyles.bodyS.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  // Secondary copy — hidden on narrow to avoid crowding.
                  if (!isNarrow) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Same building, venue, or nearby social setting',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textMuted,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// Normal-width stat layout: two tall branded cards side by side.
  Widget _buildFullStatRow(LiveSession session) {
    return Row(
      children: [
        Expanded(
          child: _StatusPill(
            icon: Icons.bolt_rounded,
            iconColor: AppColors.brandPink,
            count: '${session.liveCredits}',
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
    );
  }

  /// Narrow-width stat layout: single slim card showing both stats inline
  /// with a divider between them — never overflows on small screens.
  Widget _buildCompactStatStrip(LiveSession session) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Expanded(
            child: _CompactStat(
              icon: Icons.bolt_rounded,
              iconColor: AppColors.brandPink,
              count: '${session.liveCredits}',
              label: 'Live Session',
            ),
          ),
          Container(
            width: 1,
            height: 22,
            color: AppColors.divider,
            margin: const EdgeInsets.symmetric(horizontal: 10),
          ),
          Expanded(
            child: _CompactStat(
              icon: Icons.ac_unit_rounded,
              iconColor: AppColors.brandCyan,
              count: '3',
              label: 'Icebreakers',
            ),
          ),
        ],
      ),
    );
  }

  // ── Live state ────────────────────────────────────────────────────────────

  Widget _buildLiveState(LiveSession session) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // All sizes derived from available height — clamp keeps them
        // reasonable on both tiny phones and large macOS windows.
        final h = constraints.maxHeight;
        final logoSz = (h * 0.20).clamp(60.0, 120.0);
        final selfSz = (h * 0.25).clamp(72.0, 150.0);
        final vSm = (h * 0.025).clamp(6.0, 14.0);
        final vMd = (h * 0.045).clamp(10.0, 28.0);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(height: vMd),

              // Logo — heartbeat driven by LiveSession
              IcebreakerLogo(size: logoSz, showGlow: true),

              SizedBox(height: vSm),

              // Live badge
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 8),
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

              SizedBox(height: vSm),

              // Live selfie avatar — size scales with available height
              _buildLiveSelfieAvatar(session, selfSz),

              SizedBox(height: vSm * 0.6),

              Text(
                'People nearby can see you now',
                style: AppTextStyles.bodyS,
                textAlign: TextAlign.center,
              ),

              SizedBox(height: vMd * 1.6),

              // Live countdown
              Text(
                'Session expires in ${_formatDuration(session.remainingDuration)}',
                style: AppTextStyles.caption,
              ),

              SizedBox(height: vSm),

              PillButton.outlined(
                label: 'End Session',
                onTap: _handleEndSession,
                width: double.infinity,
              ),

              SizedBox(height: vMd),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLiveSelfieAvatar(LiveSession session, double size) {
    final path = session.selfieFilePath;

    return GestureDetector(
      onTap: path != null ? () => _showSelfieExpanded(context, session) : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.brandPink, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: AppColors.brandPink.withValues(alpha: 0.38),
                  blurRadius: 32,
                  spreadRadius: 4,
                ),
                BoxShadow(
                  color: AppColors.brandPurple.withValues(alpha: 0.22),
                  blurRadius: 56,
                  spreadRadius: 6,
                ),
              ],
            ),
            child: ClipOval(
              child: path != null
                  ? Image.file(File(path), fit: BoxFit.cover)
                  : Icon(
                      Icons.person_rounded,
                      color: AppColors.textMuted,
                      size: (size * 0.4).clamp(24.0, 72.0),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Your live photo', style: AppTextStyles.caption),
              if (path != null) ...[
                const SizedBox(width: 5),
                Icon(
                  Icons.open_in_full_rounded,
                  size: 11,
                  color: AppColors.textMuted.withValues(alpha: 0.6),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  void _showSelfieExpanded(BuildContext context, LiveSession session) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.82),
      builder: (dialogCtx) => _SelfieExpandedDialog(
        session: session,
        onRedo: () {
          Navigator.of(dialogCtx).pop();
          context.push(AppRoutes.liveVerify, extra: true);
        },
      ),
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

// ── Selfie expanded dialog ────────────────────────────────────────────────────

/// Full-screen dark overlay showing the live selfie enlarged, with a
/// "Redo Live Selfie" button that re-enters the verification capture flow.
///
/// Tapping anywhere outside the content area (the dark scrim) also dismisses.
class _SelfieExpandedDialog extends StatelessWidget {
  const _SelfieExpandedDialog({
    required this.session,
    required this.onRedo,
  });

  final LiveSession session;
  final VoidCallback onRedo;

  @override
  Widget build(BuildContext context) {
    final path = session.selfieFilePath;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: SizedBox.expand(
        child: GestureDetector(
          // Tap the dark scrim → dismiss
          onTap: () => Navigator.of(context).pop(),
          behavior: HitTestBehavior.opaque,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // ── Large selfie circle ─────────────────────────────────────
              GestureDetector(
                // Prevent taps on the selfie itself from closing the dialog
                onTap: () {},
                child: Container(
                  width: 260,
                  height: 260,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.brandPink,
                      width: 2.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.brandPink.withValues(alpha: 0.45),
                        blurRadius: 52,
                        spreadRadius: 4,
                      ),
                      BoxShadow(
                        color: AppColors.brandPurple.withValues(alpha: 0.30),
                        blurRadius: 88,
                        spreadRadius: 8,
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: path != null
                        ? Image.file(File(path), fit: BoxFit.cover)
                        : const Icon(
                            Icons.person_rounded,
                            color: AppColors.textMuted,
                            size: 96,
                          ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ── Label ───────────────────────────────────────────────────
              Text(
                'Your live photo',
                style: AppTextStyles.bodyS.copyWith(
                  color: AppColors.textMuted,
                ),
              ),

              const SizedBox(height: 36),

              // ── Redo button ─────────────────────────────────────────────
              GestureDetector(
                onTap: onRedo,
                child: Container(
                  width: 240,
                  height: 54,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(27),
                    border: Border.all(
                      color: AppColors.brandPink.withValues(alpha: 0.60),
                    ),
                    color: AppColors.brandPink.withValues(alpha: 0.10),
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.camera_alt_rounded,
                        color: AppColors.brandPink,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Redo Live Selfie',
                        style: AppTextStyles.button.copyWith(
                          color: AppColors.brandPink,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // ── Dismiss hint ────────────────────────────────────────────
              Text(
                'Tap anywhere to close',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textMuted.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Status pill (normal width) ────────────────────────────────────────────────

/// Branded counter chip used on the Home offline state at normal widths.
/// Displays an icon badge, a bold count, and a muted label.
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

// ── Compact stat (narrow width) ───────────────────────────────────────────────

/// Single inline stat entry used inside [_buildCompactStatStrip].
/// Renders as: icon · bold count · muted label — all on one row.
class _CompactStat extends StatelessWidget {
  const _CompactStat({
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: iconColor, size: 15),
        const SizedBox(width: 5),
        Text(
          count,
          style: AppTextStyles.buttonS.copyWith(
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
            height: 1.0,
          ),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textMuted,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
