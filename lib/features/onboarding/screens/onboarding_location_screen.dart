import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/icebreaker_logo.dart';

/// Onboarding — Step 6: Location permission gate.
///
/// This screen is non-skippable. The user must grant location permission
/// to proceed into the app. "Not Now" shows the blocked state immediately —
/// the user stays on this screen until they grant or open Settings.
///
/// States:
///   [_LocationState.initial]   — explanation + Allow / Not Now
///   [_LocationState.requesting] — OS dialog is open (brief loading)
///   [_LocationState.blocked]   — denied / restricted / "not now" tapped
///   [_LocationState.granted]   — saving + navigating forward
///
/// Non-mobile platforms (macOS, web, Linux, Windows) skip the gate and
/// advance immediately so desktop dev builds continue to work.
///
/// Firestore (users/{uid}):
///   locationPermissionGranted  bool  — written true on grant; absent otherwise
class OnboardingLocationScreen extends StatefulWidget {
  const OnboardingLocationScreen({super.key});

  @override
  State<OnboardingLocationScreen> createState() =>
      _OnboardingLocationScreenState();
}

class _OnboardingLocationScreenState extends State<OnboardingLocationScreen>
    with WidgetsBindingObserver {
  _LocationState _state = _LocationState.initial;

  // Whether "Try Again" is available (false when permanently denied / restricted).
  bool _canRetry = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Do NOT auto-check on launch — the explainer screen must always appear
    // so the user consciously grants location during onboarding.
    // _checkExistingPermission() is called only when returning from Settings
    // (see didChangeAppLifecycleState) so the blocked→granted path still works.
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Re-check permission when the user returns from Settings.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _state == _LocationState.blocked) {
      _checkExistingPermission();
    }
  }

  // ─── Permission logic ────────────────────────────────────────────────────────

  /// On non-mobile platforms skip the gate entirely.
  bool get _isMobile =>
      !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  Future<void> _checkExistingPermission() async {
    if (!_isMobile) {
      // Desktop / web: no OS prompt needed — advance directly.
      _navigateNext();
      return;
    }

    final status = await Permission.locationWhenInUse.status;
    if (status.isGranted) {
      await _handleGranted(alreadyGranted: true);
    }
    // Otherwise stay on initial state — do NOT auto-request.
    // The user must tap "Allow Location" to see the OS dialog.
  }

  Future<void> _requestPermission() async {
    if (!_isMobile) {
      _navigateNext();
      return;
    }

    setState(() => _state = _LocationState.requesting);

    final status = await Permission.locationWhenInUse.request();

    if (status.isGranted) {
      await _handleGranted();
    } else if (status.isPermanentlyDenied || status.isRestricted) {
      setState(() {
        _state = _LocationState.blocked;
        _canRetry = false;
      });
    } else {
      // Denied — can ask again next time.
      setState(() {
        _state = _LocationState.blocked;
        _canRetry = true;
      });
    }
  }

  Future<void> _handleGranted({bool alreadyGranted = false}) async {
    setState(() => _state = _LocationState.granted);

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .set({'locationPermissionGranted': true}, SetOptions(merge: true));
        // ignore: avoid_print
        print('[Onboarding/Location] ✅ locationPermissionGranted=true'
            '${alreadyGranted ? ' (was already granted)' : ''}');
      } catch (e) {
        // ignore: avoid_print
        print('[Onboarding/Location] ⚠️ Firestore write failed: $e');
        // Non-fatal: permission is granted, let the user through anyway.
      }
    }

    _navigateNext();
  }

  void _notNow() {
    // Show blocked state without triggering the OS dialog.
    // The user must use "Try Again" or "Open Settings" to proceed.
    setState(() {
      _state = _LocationState.blocked;
      _canRetry = true;
    });
  }

  void _navigateNext() {
    if (!mounted) return;
    context.go(AppRoutes.onboardingPhoto);
  }

  // ─── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: switch (_state) {
          _LocationState.initial => _InitialView(
              onAllow: _requestPermission,
              onNotNow: _notNow,
            ),
          _LocationState.requesting => const _RequestingView(),
          _LocationState.blocked => _BlockedView(
              canRetry: _canRetry,
              onTryAgain: _requestPermission,
              onOpenSettings: openAppSettings,
            ),
          _LocationState.granted => const _RequestingView(), // brief while saving
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// States
// ─────────────────────────────────────────────────────────────────────────────

enum _LocationState { initial, requesting, blocked, granted }

// ─────────────────────────────────────────────────────────────────────────────
// _InitialView
// ─────────────────────────────────────────────────────────────────────────────

class _InitialView extends StatelessWidget {
  const _InitialView({
    required this.onAllow,
    required this.onNotNow,
  });

  final VoidCallback onAllow;
  final VoidCallback onNotNow;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 52),
          const Center(child: IcebreakerLogo(size: 56, showGlow: false)),
          const SizedBox(height: 36),

          // Location icon
          Center(
            child: Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.brandPink.withValues(alpha: 0.08),
                border: Border.all(
                  color: AppColors.brandPink.withValues(alpha: 0.30),
                  width: 1.5,
                ),
              ),
              child: const Icon(
                Icons.location_on_rounded,
                color: AppColors.brandPink,
                size: 40,
              ),
            ),
          ),

          const SizedBox(height: 28),

          Text(
            'Enable Location',
            style: AppTextStyles.h2,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),

          Text(
            'Icebreaker is a real-world app. We use your location to show you people nearby in real time — so you can go live, discover matches, and find each other in person.',
            style: AppTextStyles.bodyS,
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 20),

          // Trust bullets
          ..._bullets.map(
            (text) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  const Icon(Icons.check_rounded,
                      color: AppColors.brandPink, size: 16),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(text, style: AppTextStyles.bodyS),
                  ),
                ],
              ),
            ),
          ),

          const Spacer(),

          // Allow Location
          GestureDetector(
            onTap: onAllow,
            child: Container(
              height: 56,
              decoration: BoxDecoration(
                gradient: AppColors.brandGradient,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.brandPink.withValues(alpha: 0.32),
                    blurRadius: 18,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Text('Allow Location', style: AppTextStyles.buttonL),
            ),
          ),

          const SizedBox(height: 16),

          // Not Now
          GestureDetector(
            onTap: onNotNow,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'Not Now',
                textAlign: TextAlign.center,
                style: AppTextStyles.body.withOpacity(0.45),
              ),
            ),
          ),

          const SizedBox(height: 28),
        ],
      ),
    );
  }

  static const _bullets = [
    'Only active while you\'re using the app',
    'Your location is never shared with other users',
    'You control exactly when you go live',
  ];
}

// ─────────────────────────────────────────────────────────────────────────────
// _RequestingView  (shown while OS dialog is open or while saving)
// ─────────────────────────────────────────────────────────────────────────────

class _RequestingView extends StatelessWidget {
  const _RequestingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        width: 32,
        height: 32,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: AppColors.brandPink,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _BlockedView  (denied / restricted / "Not Now" tapped)
// ─────────────────────────────────────────────────────────────────────────────

class _BlockedView extends StatelessWidget {
  const _BlockedView({
    required this.canRetry,
    required this.onTryAgain,
    required this.onOpenSettings,
  });

  final bool canRetry;
  final VoidCallback onTryAgain;
  final Future<bool> Function() onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 80),

          // Blocked icon
          Center(
            child: Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.danger.withValues(alpha: 0.08),
                border: Border.all(
                  color: AppColors.danger.withValues(alpha: 0.30),
                  width: 1.5,
                ),
              ),
              child: const Icon(
                Icons.location_off_rounded,
                color: AppColors.danger,
                size: 40,
              ),
            ),
          ),

          const SizedBox(height: 28),

          Text(
            'Location access needed',
            style: AppTextStyles.h2,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),

          Text(
            "Icebreaker uses your location to find people nearby in real time. Without it, you can't go live or discover anyone around you.",
            style: AppTextStyles.bodyS,
            textAlign: TextAlign.center,
          ),

          const Spacer(),

          // Try Again — only shown if not permanently denied
          if (canRetry) ...[
            GestureDetector(
              onTap: onTryAgain,
              child: Container(
                height: 56,
                decoration: BoxDecoration(
                  gradient: AppColors.brandGradient,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.brandPink.withValues(alpha: 0.32),
                      blurRadius: 18,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Text('Try Again', style: AppTextStyles.buttonL),
              ),
            ),
            const SizedBox(height: 14),
          ],

          // Open Settings — always shown
          GestureDetector(
            onTap: () => onOpenSettings(),
            child: Container(
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: AppColors.brandPink.withValues(alpha: 0.50),
                  width: 1.5,
                ),
                color: AppColors.brandPink.withValues(alpha: 0.06),
              ),
              alignment: Alignment.center,
              child: Text(
                'Open Settings',
                style: AppTextStyles.buttonL.copyWith(
                  color: AppColors.brandPink,
                ),
              ),
            ),
          ),

          const SizedBox(height: 28),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TextStyle helper
// ─────────────────────────────────────────────────────────────────────────────

extension _TextStyleOpacity on TextStyle {
  TextStyle withOpacity(double opacity) =>
      copyWith(color: (color ?? Colors.white).withValues(alpha: opacity));
}
