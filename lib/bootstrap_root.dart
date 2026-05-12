import 'dart:io' show Platform;

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'core/constants/app_constants.dart';
import 'core/services/ad_service.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_text_styles.dart';
import 'core/theme/app_theme.dart';
import 'firebase_options.dart';
import 'shared/widgets/icebreaker_logo.dart';

/// The single startup widget mounted before any Firebase work has happened.
///
/// Why this exists:
///   The previous startup awaited [Firebase.initializeApp] inside `main()`
///   *before* calling `runApp(...)`.  That blocked the entire Flutter
///   render path and produced the "blank dead screen" between the native
///   splash disappearing and the first Flutter frame.  Splitting the
///   work into a dedicated bootstrap widget lets Flutter paint frame 1
///   immediately while initialization runs in parallel.
///
/// Why it owns destination resolution:
///   Earlier iterations had two separate startup screens — a static
///   bootstrap shell and a pulsing [AppLoadingScreen].  The visible swap
///   between them felt segmented.  This widget collapses both into one
///   [_StartupShell] that begins static (matching the native splash) and
///   transitions to a heartbeat pulse on the very next frame, then runs
///   Firebase init + auth + Firestore profile resolution itself.  Once
///   the destination is known, the router is built with that location as
///   its [GoRouter.initialLocation], so the user lands directly on
///   welcome / home / onboarding — no intermediate placeholder route.
///
/// Logo behaviour across the launch:
///   1. Native splash → static brand logo, dark background.
///   2. Frame 1 ([_StartupShell]) → identical static logo, identical
///      geometry. Visually continuous with the native splash.
///   3. Frame 2 → heartbeat pulse begins (same widget, no swap).
///   4. Once Firebase + destination are resolved AND minimum visible
///      time has elapsed, [IcebreakerApp] takes over with the correct
///      initial route — destination route's own entrance animation
///      handles the visual transition into the app proper.
class BootstrapRoot extends StatefulWidget {
  const BootstrapRoot({super.key});

  @override
  State<BootstrapRoot> createState() => _BootstrapRootState();
}

class _BootstrapRootState extends State<BootstrapRoot> {
  /// Minimum on-screen time for the startup shell.  Tuned to give the
  /// heartbeat a moment to land — short enough that the user does not
  /// feel held back when init is fast, long enough that the pulse is
  /// not a single-frame flicker on warm starts.
  static const _minVisibleMs = 280;

  /// Resolved landing route, set once Firebase is up and auth+profile
  /// have been read.  Triggers the swap to [IcebreakerApp] in [build].
  String? _destination;

  /// Holds any Firebase init failure so the shell can surface a retry UI
  /// instead of leaving the user staring at a static logo forever.
  Object? _error;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  /// Runs the full pre-app bootstrap chain in series:
  ///   1. Firebase.initializeApp (loads google-services / plist config)
  ///   2. _resolveDestination     (auth currentUser + Firestore profile)
  ///   3. honour minimum visible time so the pulse is not a flash
  /// On any unhandled error the shell flips to the error path.
  Future<void> _bootstrap() async {
    final start = DateTime.now();
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      // Fire-and-forget AdMob + ATT init.  Personalized-ad eligibility is
      // settled before the first ad request; if the user denies tracking,
      // ads still serve but uncustomized.  Awaiting would gate the splash
      // on an OS dialog, so we let it race the destination resolution.
      // ignore: discarded_futures
      _initAds();

      final destination = await _resolveDestination();

      final elapsed = DateTime.now().difference(start).inMilliseconds;
      final remaining = _minVisibleMs - elapsed;
      if (remaining > 0) {
        await Future<void>.delayed(Duration(milliseconds: remaining));
      }
      if (!mounted) return;
      setState(() => _destination = destination);
    } catch (e, st) {
      debugPrint('[BootstrapRoot] bootstrap failed: $e\n$st');
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  /// Prompts for App Tracking Transparency on iOS (no-op elsewhere) and
  /// then initializes the AdMob SDK + preloads rewarded ads.  Failures here
  /// are swallowed — ads are best-effort and must not block app launch.
  Future<void> _initAds() async {
    try {
      if (Platform.isIOS) {
        final status =
            await AppTrackingTransparency.trackingAuthorizationStatus;
        if (status == TrackingStatus.notDetermined) {
          // Brief delay lets the splash settle before Apple's modal lands.
          await Future<void>.delayed(const Duration(milliseconds: 600));
          await AppTrackingTransparency.requestTrackingAuthorization();
        }
      }
    } catch (e) {
      debugPrint('[BootstrapRoot] ATT prompt failed: $e');
    }
    try {
      await AdService.instance.initialize();
    } catch (e) {
      debugPrint('[BootstrapRoot] AdService init failed: $e');
    }
  }

  /// Picks the post-startup route.  Mirrors what [AppLoadingScreen.
  /// _resolveDestination] used to do — running it here lets the router
  /// open directly on the correct screen instead of the user briefly
  /// seeing a loading placeholder at `/`.
  Future<String> _resolveDestination() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return AppRoutes.welcome;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final complete = doc.data()?['profileComplete'] == true;
      return complete ? AppRoutes.home : AppRoutes.onboardingName;
    } catch (e) {
      debugPrint('[BootstrapRoot] profile read failed: $e — defaulting to /home');
      // The router's redirect logic still bounces unauthenticated users
      // back to /sign-in, so /home is a safe fallback for transient
      // Firestore errors.
      return AppRoutes.home;
    }
  }

  void _retry() {
    setState(() => _error = null);
    _bootstrap();
  }

  @override
  Widget build(BuildContext context) {
    if (_destination != null) {
      // Hard cut to the real app once destination is resolved.  The
      // destination route's own entrance handles the visual transition
      // (WelcomeScreen has a 1.3 s staggered fade-in; HomeScreen and
      // onboarding screens render their own first frame with content,
      // so the user does not perceive a "missing logo" gap).
      return IcebreakerApp(initialLocation: _destination!);
    }

    return MaterialApp(
      title: 'Icebreaker',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: _StartupShell(error: _error, onRetry: _retry),
    );
  }
}

/// The branded surface shown for the entire bootstrap.
///
/// Frame 1 renders a STATIC logo so the cut from the native splash is
/// imperceptible (same image, same size, same dark background, same
/// position).  A single post-frame callback flips [_shouldPulse] to
/// true on frame 2, at which point [IcebreakerLogo]'s heartbeat starts
/// — the AnimationController begins at scale 1.0, so there is no scale
/// jump between the static and pulsing renderings.
class _StartupShell extends StatefulWidget {
  const _StartupShell({required this.error, required this.onRetry});

  final Object? error;
  final VoidCallback onRetry;

  @override
  State<_StartupShell> createState() => _StartupShellState();
}

class _StartupShellState extends State<_StartupShell> {
  bool _shouldPulse = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _shouldPulse = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: Center(
        child: widget.error == null
            ? IcebreakerLogo(
                // Sized assertively (192 logical dp) so the startup mark
                // carries the screen rather than reading as a small mark
                // floating in mostly-empty black.  Native LaunchImage assets
                // (iOS @1x/@2x/@3x and Android mipmap-*/launch_image) are
                // regenerated to match this dp at the storyboard / drawable
                // level, so the cut from native splash to Flutter frame 1
                // remains a single continuous scene.
                size: 192,
                showGlow: false,
                // Materially brighter than the previous 0.35 — pushes more
                // brand color into the surround so the wake-up reads as a
                // glowing orb, not a flat icon.  Still tame enough that the
                // very brief mismatch with the unglowed native splash
                // bitmap is imperceptible during the handoff.
                ambientGlow: 0.55,
                forcePulse: _shouldPulse,
                // Replaces the previous static→full-speed repeat with a
                // calm one-shot first beat, then the normal heartbeat.
                // See [IcebreakerLogo.startupIntro] for the curve.
                startupIntro: true,
              )
            : _BootstrapErrorBody(
                error: widget.error!,
                onRetry: widget.onRetry,
              ),
      ),
    );
  }
}

class _BootstrapErrorBody extends StatelessWidget {
  const _BootstrapErrorBody({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const IcebreakerLogo(
            size: 96,
            showGlow: false,
            ambientGlow: 0.25,
          ),
          const SizedBox(height: 28),
          Text(
            "Couldn't start Icebreaker",
            style: AppTextStyles.h3.copyWith(color: AppColors.textPrimary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Check your connection and try again.',
            style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: onRetry,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.brandPink,
              foregroundColor: AppColors.textPrimary,
              padding: const EdgeInsets.symmetric(
                horizontal: 32,
                vertical: 14,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            child: Text('Try again', style: AppTextStyles.button),
          ),
        ],
      ),
    );
  }
}
