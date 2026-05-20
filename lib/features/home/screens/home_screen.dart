import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/location_service.dart';
import '../../../core/state/live_session.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/gradient_scaffold.dart';
import '../../../shared/widgets/icebreaker_logo.dart';
import '../../../shared/widgets/live_selfie_circle_image.dart';
import '../../../shared/widgets/pill_button.dart';

/// Below this width the Home screen switches to its compact layout mode.
/// 400 dp covers all small phones and narrow macOS windows.
const double _kNarrow = 400.0;

/// How long after account creation a user may Go Live without having
/// verified their email.  After this window, the verification sheet
/// gate at [_handleGoLive] kicks in.  Product call: testers reported
/// the email-link redirect kicked them out of the app and was the
/// single biggest first-session drop-off.
const Duration _kVerificationGracePeriod = Duration(hours: 24);

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

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver {
  Timer? _countdownTimer;
  LiveSession? _listenedSession;
  int? _lastSeenIcebreakerCredits;
  int? _lastSeenLiveCredits;
  int _icebreakerBurstTick = 0;
  int _liveBurstTick = 0;
  int _icebreakerBurstAmount = 0;
  int _liveBurstAmount = 0;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncCountdownTimer(LiveSessionScope.isLive(context));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _listenedSession?.removeListener(_handleCreditChangeToast);
    _countdownTimer?.cancel();
    super.dispose();
  }

  /// On every app-foreground event: reload the Firebase Auth user so that
  /// [emailVerified] reflects any verification the user completed outside the
  /// app (e.g. clicking the link in their inbox), then rebuild.
  ///
  /// Without this, [_handleGoLive] would see the stale cached value and show
  /// the verification gate even though the user has already verified.
  /// [app.dart] fires the same reload but with no setState on this widget,
  /// so this observer closes that gap.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _reloadAuthUser();
    }
  }

  Future<void> _reloadAuthUser() async {
    try {
      await FirebaseAuth.instance.currentUser?.reload();
      debugPrint('[Home] auth user reloaded on resume — '
          'emailVerified=${FirebaseAuth.instance.currentUser?.emailVerified}');
    } catch (e) {
      debugPrint('[Home] auth reload on resume failed (non-fatal): $e');
    }
    if (mounted) setState(() {});
  }

  void _syncCountdownTimer(bool isLive) {
    if (isLive && (_countdownTimer == null || !_countdownTimer!.isActive)) {
      // Ticks every second only to refresh the countdown display.
      // Actual expiry is handled by LiveSession._expiryTimer which survives
      // all tab navigation.
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!isLive) {
      _countdownTimer?.cancel();
      _countdownTimer = null;
    }
  }

  void _wireCreditToastListener(LiveSession session) {
    if (identical(_listenedSession, session)) return;
    _listenedSession?.removeListener(_handleCreditChangeToast);
    _listenedSession = session;
    _lastSeenIcebreakerCredits = session.icebreakerCredits;
    _lastSeenLiveCredits = session.liveCredits;
    session.addListener(_handleCreditChangeToast);
  }

  void _handleCreditChangeToast() {
    final session = _listenedSession;
    if (session == null || !mounted) return;

    final previousIcebreakers = _lastSeenIcebreakerCredits;
    final previousLive = _lastSeenLiveCredits;
    final currentIcebreakers = session.icebreakerCredits;
    final currentLive = session.liveCredits;

    _lastSeenIcebreakerCredits = currentIcebreakers;
    _lastSeenLiveCredits = currentLive;

    if (previousIcebreakers == null || previousLive == null) return;

    final gainedIcebreakers = currentIcebreakers - previousIcebreakers;
    final gainedLive = currentLive - previousLive;
    if (gainedIcebreakers <= 0 && gainedLive <= 0) return;

    setState(() {
      if (gainedIcebreakers > 0) {
        _icebreakerBurstTick++;
        _icebreakerBurstAmount = gainedIcebreakers;
      }
      if (gainedLive > 0) {
        _liveBurstTick++;
        _liveBurstAmount = gainedLive;
      }
    });
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _handleGoLive() async {
    var user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showVerificationRequiredSheet();
      return;
    }

    // Captured from the Gate 1 read and consumed in Gate 3's grace-period
    // calculation.  Default to "old account" if the read fails or the field
    // is missing — that fails CLOSED on the verification gate (better than
    // silently letting unverified users live forever).
    DateTime? accountCreatedAt;

    // ── Gate 1: profile complete ───────────────────────────────────────────
    // One Firestore read confirms onboarding finished and first photo saved.
    // We do this first so a brand-new user who hasn't finished onboarding
    // gets a clear path to fix it rather than hitting a cryptic location error.
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = doc.data();
      final profileComplete = (data?['profileComplete'] as bool?) ?? false;
      // Capture createdAt from the same read so we don't pay a second
      // round-trip in Gate 3.
      final createdAtTs = data?['createdAt'];
      if (createdAtTs is Timestamp) {
        accountCreatedAt = createdAtTs.toDate();
      }
      if (!profileComplete) {
        if (!mounted) return;
        context.push(AppRoutes.profileChecklist);
        return;
      }
    } catch (e) {
      debugPrint('[Home] profileComplete check failed (non-fatal): $e');
      // Don't block the user on a network error — fall through.
    }

    // ── Gate 2: location permission ────────────────────────────────────────
    // Discovery writes GPS to Firestore — Go Live makes no sense without it.
    //
    // requestIfNeeded() prompts the OS dialog when the state is requestable
    // and is a no-op otherwise.  This is what removes the iOS dead-end:
    // before, a brand-new install with `denied` (never asked) would punt to
    // system Settings, where the Location row doesn't yet exist.  Now the
    // very first tap triggers the OS prompt itself, and the sheet only
    // appears for genuinely terminal states.
    final locStatus = await LocationService.requestIfNeeded();
    if (locStatus != LocationStatus.granted) {
      if (!mounted) return;
      _showLocationRequiredSheet(locStatus);
      return;
    }

    // ── Gate 3: email OR phone verified — with 24h grace period ──────────
    // Product call (2026-05-20): testers reported the verification-required
    // sheet as a major drop-off because tapping the verification link kicks
    // them out of the app.  New rule: a brand-new account gets 24 h to
    // explore + Go Live BEFORE the verification gate kicks in.  After 24 h,
    // an unverified user hits the existing sheet.  This is a soft-gate —
    // they're nudged via the [_unverifiedGracePeriodHint] banner below the
    // GO LIVE button (see [build]) so they know the deadline.
    //
    // Reload first so a link clicked in the email client is reflected
    // immediately, regardless of which path Gate 3 takes.
    if (!user.emailVerified) {
      try {
        await user.reload();
      } catch (e) {
        debugPrint('[Home] auth reload before go-live failed (non-fatal): $e');
      }
      if (!mounted) return;
      user = FirebaseAuth.instance.currentUser;
    }
    if (user == null) {
      _showVerificationRequiredSheet();
      return;
    }
    final phoneVerified = user.phoneNumber?.isNotEmpty ?? false;
    final emailOrPhoneVerified = user.emailVerified || phoneVerified;
    if (!emailOrPhoneVerified) {
      final inGracePeriod = accountCreatedAt != null &&
          DateTime.now().difference(accountCreatedAt) <
              _kVerificationGracePeriod;
      if (!inGracePeriod) {
        debugPrint('[Home] verification gate enforced — '
            'createdAt=$accountCreatedAt grace expired');
        _showVerificationRequiredSheet();
        return;
      }
      debugPrint('[Home] verification gate skipped — '
          'createdAt=$accountCreatedAt within 24h grace period');
    }

    // ── Gate 4: live credits ───────────────────────────────────────────────
    if (!mounted) return;
    final session = LiveSessionScope.of(context);
    if (session.liveCredits <= 0) {
      context.push(AppRoutes.shop);
      return;
    }

    context.push(AppRoutes.liveVerify);
  }

  /// Sheet content branches on the [LocationStatus] returned by
  /// [LocationService.requestIfNeeded].  Three distinct UI paths:
  ///
  ///   • [LocationStatus.requestable]    — should not occur in practice, since
  ///                                       requestIfNeeded would have prompted
  ///                                       and resolved.  We still handle it:
  ///                                       offer "Allow Location" which
  ///                                       re-enters the same flow.
  ///   • [LocationStatus.blockedForever] — only reachable via system Settings
  ///                                       (the Location row exists by now,
  ///                                       since the OS prompt has happened
  ///                                       at least once in the past).
  ///   • [LocationStatus.servicesDisabled] — device-wide switch is off.  Open
  ///                                       Settings deep-links to the app's
  ///                                       page; copy points the user at the
  ///                                       global toggle.
  void _showLocationRequiredSheet(LocationStatus status) {
    final canRequest = status == LocationStatus.requestable;
    final servicesOff = status == LocationStatus.servicesDisabled;

    final body = switch (status) {
      LocationStatus.requestable =>
        'Icebreaker needs location permission to show you to nearby people while you\'re live.',
      LocationStatus.blockedForever =>
        'Location is blocked for Icebreaker. Open Settings to enable it, then try again.',
      LocationStatus.servicesDisabled =>
        'Location Services are turned off on this device. Turn them on in Settings → Privacy & Security → Location Services, then try again.',
      LocationStatus.granted => '', // unreachable — caller filters this case
    };

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Icon(
              servicesOff
                  ? Icons.gps_off_rounded
                  : Icons.location_off_rounded,
              color: AppColors.brandCyan,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              servicesOff
                  ? 'Location Services are off'
                  : 'Location access needed',
              style: AppTextStyles.h3,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              body,
              style: AppTextStyles.bodyS
                  .copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            if (canRequest)
              PillButton.primary(
                label: 'Allow Location',
                icon: Icons.location_on_rounded,
                width: double.infinity,
                height: 52,
                onTap: () async {
                  Navigator.of(sheetCtx).pop();
                  // Re-enter the gate.  requestIfNeeded() will prompt; if the
                  // user grants, _handleGoLive flows through the rest of the
                  // gates; if they deny again we land back here.
                  await _handleGoLive();
                },
              )
            else
              PillButton.primary(
                label: 'Open Settings',
                icon: Icons.settings_rounded,
                width: double.infinity,
                height: 52,
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  LocationService.openSettings();
                },
              ),
            const SizedBox(height: 12),
            PillButton.outlined(
              label: 'Not now',
              width: double.infinity,
              height: 52,
              onTap: () => Navigator.of(sheetCtx).pop(),
            ),
          ],
        ),
      ),
    );
  }

  /// Bottom sheet shown when the user taps GO LIVE without a verified email.
  /// Explains the requirement and offers a direct path to Settings to send
  /// the verification email.
  void _showVerificationRequiredSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        // Local state for the "I've verified" in-progress indicator.
        var checking = false;
        return StatefulBuilder(
          builder: (_, setSheetState) => Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Icon(
                  Icons.mark_email_unread_outlined,
                  color: AppColors.brandCyan,
                  size: 48,
                ),
                const SizedBox(height: 16),
                Text(
                  'Verify your email to go Live',
                  style: AppTextStyles.h3,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'A verified email is required before starting a Live session. '
                  'Check your inbox for a verification link, or send one from Settings.',
                  style: AppTextStyles.bodyS
                      .copyWith(color: AppColors.textSecondary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                PillButton.primary(
                  label: 'Go to Settings',
                  width: double.infinity,
                  height: 52,
                  onTap: () {
                    Navigator.of(sheetCtx).pop();
                    context.push(AppRoutes.settings);
                  },
                ),
                const SizedBox(height: 12),
                // "I've already verified" path — reloads auth state and
                // proceeds to Go Live if verified, or shows a clear message
                // if the email link hasn't been clicked yet.
                PillButton.outlined(
                  label: checking ? 'Checking…' : 'I\'ve verified — check now',
                  icon: checking ? null : Icons.refresh_rounded,
                  width: double.infinity,
                  height: 52,
                  onTap: checking
                      ? null
                      : () async {
                          setSheetState(() => checking = true);
                          // Capture navigators/messengers before the async gap.
                          final sheetNav = Navigator.of(sheetCtx);
                          final messenger =
                              ScaffoldMessenger.of(context);
                          try {
                            await FirebaseAuth.instance.currentUser?.reload();
                          } catch (e) {
                            debugPrint(
                                '[Home] reload in sheet failed (non-fatal): $e');
                          }
                          if (!mounted) return;
                          final verified = FirebaseAuth.instance.currentUser
                                  ?.emailVerified ??
                              false;
                          sheetNav.pop();
                          if (verified) {
                            // Email is now verified — proceed to Go Live.
                            _handleGoLive();
                          } else {
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Email not yet verified. Open the link in your inbox, then try again.',
                                ),
                              ),
                            );
                          }
                        },
                ),
              ],
            ),
          ),
        );
      },
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
    _wireCreditToastListener(session);
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
      // Icebreaker logo in top-left — static when offline, heartbeat when live.
      // Profile is still accessible via the bottom nav tab.
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
                            AppColors.brandCyan.withValues(alpha: 0.10),
                            AppColors.brandPink.withValues(alpha: 0.22),
                            AppColors.brandPurple.withValues(alpha: 0.14),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.30, 0.60, 1.0],
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
                        ? 'Go Live — stay visible until you end it'
                        : 'Go Live to appear on the radar until you end it or the timer expires',
                    style: AppTextStyles.bodyS.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  // Secondary copy — hidden on narrow to avoid crowding.
                  if (!isNarrow) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Nearby people see your live session from your last active location while the timer is running',
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
            burstAmount: _icebreakerBurstAmount,
            burstKind: _CreditBurstKind.heart,
            burstTick: _icebreakerBurstTick,
            icon: Icons.favorite_rounded,
            iconColor: AppColors.brandPink,
            count: '${session.icebreakerCredits}',
            label: 'Icebreakers',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatusPill(
            burstAmount: _liveBurstAmount,
            burstKind: _CreditBurstKind.bolt,
            burstTick: _liveBurstTick,
            icon: Icons.bolt_rounded,
            iconColor: AppColors.brandCyan,
            count: '${session.liveCredits}',
            label: 'Live Session',
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
              burstAmount: _icebreakerBurstAmount,
              burstKind: _CreditBurstKind.heart,
              burstTick: _icebreakerBurstTick,
              icon: Icons.favorite_rounded,
              iconColor: AppColors.brandPink,
              count: '${session.icebreakerCredits}',
              label: 'Icebreakers',
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
              burstAmount: _liveBurstAmount,
              burstKind: _CreditBurstKind.bolt,
              burstTick: _liveBurstTick,
              icon: Icons.bolt_rounded,
              iconColor: AppColors.brandCyan,
              count: '${session.liveCredits}',
              label: 'Live Session',
            ),
          ),
        ],
      ),
    );
  }

  // ── Live state ────────────────────────────────────────────────────────────

  /// Premium live-dashboard layout.
  ///
  /// The Icebreaker logo lives in the AppBar (pulsing) so the body is freed
  /// up for content. Top-to-bottom:
  ///
  ///   1. Branded countdown card    (SESSION TIME + gradient timer)
  ///   2. Stat strip                (Icebreakers | Live Sessions)
  ///   3. [flexible] selfie avatar  (visual hero of the live screen)
  ///   4. YOU'RE LIVE badge         (status label beneath the selfie)
  ///   5. End Session button        (compact, centred)
  Widget _buildLiveState(LiveSession session) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight;
        // All sizes proportional to available height — overflow-free from
        // ~380dp phones to wide macOS windows.
        //
        // Budget breakdown (h ≈ 450dp on an iPhone SE):
        //   Fixed non-Expanded: card + strip + button + gaps  ≈ 155dp
        //   Expanded (selfie + badge)                         ≈ 295dp
        final selfSz = (h * 0.22).clamp(80.0, 148.0);
        final timerFontSize = (h * 0.050).clamp(18.0, 26.0);
        final vSm = (h * 0.018).clamp(4.0, 10.0);
        final vMd = (h * 0.030).clamp(6.0, 14.0);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(height: vSm),

              // ── 1. Branded countdown card ──────────────────────────────
              _CountdownCard(
                duration: session.remainingDuration,
                timerFontSize: timerFontSize,
              ),

              SizedBox(height: vMd),

              // ── 2. Stat strip ──────────────────────────────────────────
              _LiveStatStrip(
                icebreakerBurstAmount: _icebreakerBurstAmount,
                icebreakerBurstTick: _icebreakerBurstTick,
                liveBurstAmount: _liveBurstAmount,
                liveBurstTick: _liveBurstTick,
                session: session,
              ),

              // ── 3 & 4. Selfie + badge (fills remaining space) ──────────
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildLiveSelfieAvatar(session, selfSz),
                    SizedBox(height: vSm),

                    // ── 4. YOU'RE LIVE badge below the selfie ──────────
                    const _LiveBadge(),
                  ],
                ),
              ),

              // ── 5. End Session ─────────────────────────────────────────
              PillButton.outlined(
                label: 'End Session',
                onTap: _handleEndSession,
                width: 200,
                height: 40,
              ),

              SizedBox(height: vMd),
            ],
          ),
        );
      },
    );
  }

  /// Live selfie avatar — tappable to expand.
  /// Label intentionally omitted; the selfie context is clear from the layout.
  Widget _buildLiveSelfieAvatar(LiveSession session, double size) {
    final path = session.selfieFilePath;

    return GestureDetector(
      onTap: path != null ? () => _showSelfieExpanded(context, session) : null,
      child: Container(
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
              ? LiveSelfieCircleImage(
                  selfiePath: path,
                  avatarPath: session.avatarFilePath,
                )
              : Icon(
                  Icons.person_rounded,
                  color: AppColors.textMuted,
                  size: (size * 0.4).clamp(24.0, 72.0),
                ),
        ),
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

}

enum _CreditBurstKind { heart, bolt }

class _CreditBurst extends StatelessWidget {
  const _CreditBurst({
    required this.burstAmount,
    required this.burstKind,
    required this.burstTick,
    required this.child,
    required this.color,
    this.compact = false,
  });

  final int burstAmount;
  final _CreditBurstKind burstKind;
  final int burstTick;
  final Widget child;
  final Color color;
  final bool compact;

  IconData get _icon =>
      burstKind == _CreditBurstKind.heart
          ? Icons.favorite_rounded
          : Icons.bolt_rounded;

  @override
  Widget build(BuildContext context) {
    if (burstTick == 0 || burstAmount <= 0) return child;

    return TweenAnimationBuilder<double>(
      key: ValueKey('${burstKind.name}-$burstTick'),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 950),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        final lift = compact ? 18.0 : 26.0;
        final iconSize = compact ? 16.0 : 20.0;
        final pillScale = 1 + math.sin(value * math.pi) * 0.045;
        final fadeOut = (1 - value).clamp(0.0, 1.0);
        final glow = math.sin(value * math.pi).clamp(0.0, 1.0);
        final horizontalOffset = compact ? 8.0 : 12.0;
        final verticalStart = compact ? -2.0 : 2.0;
        final badgeFont = compact ? 10.0 : 11.0;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Transform.scale(
              scale: pillScale,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.12 + (glow * 0.16)),
                      blurRadius: compact ? 12 : 18,
                      spreadRadius: glow * 2,
                    ),
                  ],
                ),
                child: child,
              ),
            ),
            Positioned(
              right: horizontalOffset,
              top: verticalStart - (value * lift),
              child: IgnorePointer(
                child: Opacity(
                  opacity: fadeOut,
                  child: Transform.rotate(
                    angle: burstKind == _CreditBurstKind.bolt
                        ? (1 - value) * 0.28
                        : 0,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: EdgeInsets.all(compact ? 4 : 5),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.16),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: color.withValues(alpha: 0.30),
                            ),
                          ),
                          child: Icon(_icon, color: color, size: iconSize),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: compact ? 5 : 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.bgSurface.withValues(alpha: 0.96),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: color.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Text(
                            '+$burstAmount',
                            style: AppTextStyles.caption.copyWith(
                              color: color,
                              fontSize: badgeFont,
                              fontWeight: FontWeight.w800,
                              height: 1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Live badge ────────────────────────────────────────────────────────────────

/// Gradient pill showing "YOU'RE LIVE" with a pulsing-white status dot.
class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandPink.withValues(alpha: 0.32),
            blurRadius: 12,
            spreadRadius: 0,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            "YOU'RE LIVE",
            style: AppTextStyles.caption.copyWith(
              color: Colors.white,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Countdown card ────────────────────────────────────────────────────────────

/// Branded session-time card — the centrepiece of the live status header.
///
/// Shows: "SESSION TIME" overline · large gradient countdown · "remaining" label.
/// Pink border + glow makes it feel like an active, important system readout.
class _CountdownCard extends StatelessWidget {
  const _CountdownCard({
    required this.duration,
    required this.timerFontSize,
  });
  final Duration duration;
  final double timerFontSize;

  String _format(Duration d) {
    if (d <= Duration.zero) return '0:00:00';
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.brandPink.withValues(alpha: 0.38),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandPink.withValues(alpha: 0.12),
            blurRadius: 20,
            spreadRadius: 0,
          ),
          BoxShadow(
            color: AppColors.brandPurple.withValues(alpha: 0.08),
            blurRadius: 32,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            'SESSION  ',
            style: AppTextStyles.overline.copyWith(
              color: AppColors.textMuted,
              letterSpacing: 1.2,
            ),
          ),
          ShaderMask(
            shaderCallback: (bounds) =>
                AppColors.brandGradient.createShader(bounds),
            blendMode: BlendMode.srcIn,
            child: Text(
              _format(duration),
              style: AppTextStyles.h1.copyWith(
                fontSize: timerFontSize,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.0,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Live stat strip ───────────────────────────────────────────────────────────

/// Compact two-stat strip shown on the live-state Home screen.
/// Mirrors the offline compact strip but is always shown (never switches
/// to the tall two-card layout) since screen real estate is tighter.
class _LiveStatStrip extends StatelessWidget {
  const _LiveStatStrip({
    required this.icebreakerBurstAmount,
    required this.icebreakerBurstTick,
    required this.liveBurstAmount,
    required this.liveBurstTick,
    required this.session,
  });

  final int icebreakerBurstAmount;
  final int icebreakerBurstTick;
  final int liveBurstAmount;
  final int liveBurstTick;
  final LiveSession session;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Expanded(
            child: _CompactStat(
              burstAmount: icebreakerBurstAmount,
              burstKind: _CreditBurstKind.heart,
              burstTick: icebreakerBurstTick,
              icon: Icons.favorite_rounded,
              iconColor: AppColors.brandPink,
              count: '${session.icebreakerCredits}',
              label: 'Icebreakers',
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
              burstAmount: liveBurstAmount,
              burstKind: _CreditBurstKind.bolt,
              burstTick: liveBurstTick,
              icon: Icons.bolt_rounded,
              iconColor: AppColors.brandCyan,
              count: '${session.liveCredits}',
              label: 'Live Sessions',
            ),
          ),
        ],
      ),
    );
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
                        ? LiveSelfieCircleImage(
                            selfiePath: path,
                            avatarPath: session.avatarFilePath,
                          )
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
    required this.burstAmount,
    required this.burstKind,
    required this.burstTick,
    required this.icon,
    required this.iconColor,
    required this.count,
    required this.label,
  });

  final int burstAmount;
  final _CreditBurstKind burstKind;
  final int burstTick;
  final IconData icon;
  final Color iconColor;
  final String count;
  final String label;

  @override
  Widget build(BuildContext context) {
    return _CreditBurst(
      burstAmount: burstAmount,
      burstKind: burstKind,
      burstTick: burstTick,
      color: iconColor,
      child: Container(
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
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(scale: animation, child: child),
                    );
                  },
                  child: Text(
                    count,
                    key: ValueKey(count),
                    style: AppTextStyles.h3.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
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
      ),
    );
  }
}

// ── Compact stat (narrow width) ───────────────────────────────────────────────

/// Single inline stat entry used inside [_buildCompactStatStrip].
/// Renders as: icon · bold count · muted label — all on one row.
class _CompactStat extends StatelessWidget {
  const _CompactStat({
    required this.burstAmount,
    required this.burstKind,
    required this.burstTick,
    required this.icon,
    required this.iconColor,
    required this.count,
    required this.label,
  });

  final int burstAmount;
  final _CreditBurstKind burstKind;
  final int burstTick;
  final IconData icon;
  final Color iconColor;
  final String count;
  final String label;

  @override
  Widget build(BuildContext context) {
    return _CreditBurst(
      burstAmount: burstAmount,
      burstKind: burstKind,
      burstTick: burstTick,
      color: iconColor,
      compact: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: iconColor, size: 15),
          const SizedBox(width: 5),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: ScaleTransition(scale: animation, child: child),
              );
            },
            child: Text(
              count,
              key: ValueKey(count),
              style: AppTextStyles.buttonS.copyWith(
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                height: 1.0,
              ),
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
      ),
    );
  }
}
