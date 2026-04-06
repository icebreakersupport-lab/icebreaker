import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/state/demo_profile.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/icebreaker_logo.dart';

/// Onboarding — Step 6: Location permission + hometown collection.
///
/// Two responsibilities on one screen:
///   1. Explain why location is needed and request iOS/Android permission.
///   2. Collect city + state ("Where are you from?") for the public profile.
///
/// The Continue button ("Allow Location") is disabled until:
///   - city/town field is non-empty
///   - state field is non-empty
///
/// On tap:
///   - Validates fields; shows inline errors if blank.
///   - Requests OS location permission (or proceeds silently if already granted).
///   - Saves hometown to DemoProfile and Firestore users/{uid}.hometown.
///   - Saves locationPermissionGranted=true to Firestore on grant.
///   - Navigates to the first-photo screen.
///
/// Non-mobile platforms (macOS, web, Linux, Windows) skip the OS prompt
/// but still collect city/state.
///
/// Firestore schema written:
///   users/{uid}.hometown.city       String
///   users/{uid}.hometown.state      String   (full name, e.g. "Arizona")
///   users/{uid}.hometown.stateCode  String   (2-letter code, e.g. "AZ")
///   users/{uid}.locationPermissionGranted  bool
class OnboardingLocationScreen extends StatefulWidget {
  const OnboardingLocationScreen({super.key});

  @override
  State<OnboardingLocationScreen> createState() =>
      _OnboardingLocationScreenState();
}

class _OnboardingLocationScreenState extends State<OnboardingLocationScreen>
    with WidgetsBindingObserver {
  _LocationState _state = _LocationState.initial;
  bool _canRetry = true;

  // ── Hometown form ────────────────────────────────────────────────────────────
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  bool _showFieldErrors = false;

  bool get _fieldsValid =>
      _cityController.text.trim().isNotEmpty &&
      _stateController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Do NOT auto-check permission on launch — the explainer must always show
    // so the user consciously acts. _checkExistingPermission is only called
    // when returning from Settings (see didChangeAppLifecycleState).
  }

  @override
  void dispose() {
    _cityController.dispose();
    _stateController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Re-check when the user returns from Settings while in blocked state.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _state == _LocationState.blocked) {
      _checkExistingPermission();
    }
  }

  // ── Permission logic ──────────────────────────────────────────────────────────

  bool get _isMobile => !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  /// Only called when returning from Settings. If permission is now granted,
  /// save and advance; otherwise stay on the blocked view.
  Future<void> _checkExistingPermission() async {
    if (!_isMobile) {
      await _saveAndAdvance();
      return;
    }
    final status = await Permission.locationWhenInUse.status;
    if (status.isGranted) {
      await _handleGranted(alreadyGranted: true);
    }
  }

  /// Called when the user taps "Allow Location".
  Future<void> _requestPermission() async {
    // Validate hometown fields before doing anything.
    if (!_fieldsValid) {
      setState(() => _showFieldErrors = true);
      return;
    }

    if (!_isMobile) {
      await _saveAndAdvance();
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
      setState(() {
        _state = _LocationState.blocked;
        _canRetry = true;
      });
    }
  }

  Future<void> _handleGranted({bool alreadyGranted = false}) async {
    setState(() => _state = _LocationState.granted);

    // Save hometown + permission flag in one merge write.
    await _saveAndAdvance(grantedPermission: true, alreadyGranted: alreadyGranted);
  }

  Future<void> _saveAndAdvance({
    bool grantedPermission = false,
    bool alreadyGranted = false,
  }) async {
    final city = _cityController.text.trim();
    final state = _stateController.text.trim();
    final stateCode = DemoProfile.abbreviateState(state);

    // ── In-memory profile ──────────────────────────────────────────────────────
    if (mounted) {
      DemoProfileScope.of(context).setHometown(city, state);
    }

    // ── Firestore ──────────────────────────────────────────────────────────────
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final data = <String, dynamic>{
        if (city.isNotEmpty || state.isNotEmpty)
          'hometown': {
            'city': city,
            'state': state,
            'stateCode': stateCode,
          },
        if (grantedPermission) 'locationPermissionGranted': true,
      };
      if (data.isNotEmpty) {
        try {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .set(data, SetOptions(merge: true));
          // ignore: avoid_print
          print('[Onboarding/Location] ✅ saved hometown=$city,$state'
              '${grantedPermission ? ' locationPermissionGranted=true${alreadyGranted ? ' (was already granted)' : ''}' : ''}');
        } catch (e) {
          // ignore: avoid_print
          print('[Onboarding/Location] ⚠️ Firestore write failed: $e');
        }
      }
    }

    _navigateNext();
  }

  void _notNow() {
    setState(() {
      _state = _LocationState.blocked;
      _canRetry = true;
    });
  }

  void _navigateNext() {
    if (!mounted) return;
    context.go(AppRoutes.onboardingPhoto);
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: switch (_state) {
          _LocationState.initial => _InitialView(
              cityController: _cityController,
              stateController: _stateController,
              showFieldErrors: _showFieldErrors,
              onFieldChanged: () => setState(() {}),
              onAllow: _requestPermission,
              onNotNow: _notNow,
            ),
          _LocationState.requesting => const _LoadingView(),
          _LocationState.blocked => _BlockedView(
              canRetry: _canRetry,
              onTryAgain: _requestPermission,
              onOpenSettings: openAppSettings,
            ),
          _LocationState.granted => const _LoadingView(),
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
    required this.cityController,
    required this.stateController,
    required this.showFieldErrors,
    required this.onFieldChanged,
    required this.onAllow,
    required this.onNotNow,
  });

  final TextEditingController cityController;
  final TextEditingController stateController;
  final bool showFieldErrors;
  final VoidCallback onFieldChanged;
  final VoidCallback onAllow;
  final VoidCallback onNotNow;

  bool get _fieldsValid =>
      cityController.text.trim().isNotEmpty &&
      stateController.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 40),

          const Center(child: IcebreakerLogo(size: 52, showGlow: false)),
          const SizedBox(height: 28),

          // ── Location permission section ──────────────────────────────────
          Center(
            child: Container(
              width: 76,
              height: 76,
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
                size: 36,
              ),
            ),
          ),

          const SizedBox(height: 20),

          Text(
            'Enable Location',
            style: AppTextStyles.h2,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),

          Text(
            'Icebreaker uses your location to show people nearby when you\'re live.',
            style: AppTextStyles.bodyS,
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 16),

          // Trust bullets
          ..._locationBullets.map(
            (text) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.check_rounded,
                      color: AppColors.brandPink, size: 15),
                  const SizedBox(width: 10),
                  Expanded(child: Text(text, style: AppTextStyles.bodyS)),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ── Divider ──────────────────────────────────────────────────────
          Container(
            height: 1,
            color: AppColors.divider,
          ),

          const SizedBox(height: 24),

          // ── Hometown section ─────────────────────────────────────────────
          Text(
            'Where are you from?',
            style: AppTextStyles.h3,
          ),
          const SizedBox(height: 16),

          // City field
          _HometownField(
            controller: cityController,
            label: 'City / Town',
            hint: 'e.g. Scottsdale',
            showError: showFieldErrors && cityController.text.trim().isEmpty,
            errorText: 'City is required',
            onChanged: (_) => onFieldChanged(),
            textInputAction: TextInputAction.next,
          ),

          const SizedBox(height: 10),

          // State field
          _HometownField(
            controller: stateController,
            label: 'State',
            hint: 'e.g. Arizona',
            showError: showFieldErrors && stateController.text.trim().isEmpty,
            errorText: 'State is required',
            onChanged: (_) => onFieldChanged(),
            textInputAction: TextInputAction.done,
          ),

          const SizedBox(height: 10),

          // Privacy helper
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(Icons.info_outline_rounded,
                    size: 13, color: AppColors.textMuted),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'This appears on your profile. Your exact location is never shown to other users.',
                  style: AppTextStyles.caption,
                ),
              ),
            ],
          ),

          const SizedBox(height: 32),

          // ── Allow Location button ─────────────────────────────────────────
          GestureDetector(
            onTap: onAllow,
            child: AnimatedOpacity(
              opacity: _fieldsValid ? 1.0 : 0.50,
              duration: const Duration(milliseconds: 180),
              child: Container(
                height: 56,
                decoration: BoxDecoration(
                  gradient: AppColors.brandGradient,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: _fieldsValid
                      ? [
                          BoxShadow(
                            color: AppColors.brandPink.withValues(alpha: 0.32),
                            blurRadius: 18,
                            offset: const Offset(0, 5),
                          ),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: Text('Allow Location', style: AppTextStyles.buttonL),
              ),
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
                style: AppTextStyles.body
                    .copyWith(color: AppColors.textPrimary.withValues(alpha: 0.40)),
              ),
            ),
          ),

          const SizedBox(height: 28),
        ],
      ),
    );
  }

  static const _locationBullets = [
    'Only active while you\'re using the app',
    'Your location is never shared with other users',
    'You control exactly when you go live',
  ];
}

// ─────────────────────────────────────────────────────────────────────────────
// _HometownField
// ─────────────────────────────────────────────────────────────────────────────

class _HometownField extends StatelessWidget {
  const _HometownField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.showError,
    required this.errorText,
    required this.onChanged,
    required this.textInputAction,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final bool showError;
  final String errorText;
  final ValueChanged<String> onChanged;
  final TextInputAction textInputAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: AppColors.bgSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: showError
                  ? AppColors.danger
                  : AppColors.divider,
              width: showError ? 1.5 : 1.0,
            ),
          ),
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            textInputAction: textInputAction,
            textCapitalization: TextCapitalization.words,
            style: AppTextStyles.body.copyWith(color: AppColors.textPrimary),
            decoration: InputDecoration(
              labelText: label,
              labelStyle: AppTextStyles.bodyS
                  .copyWith(color: AppColors.textSecondary),
              hintText: hint,
              hintStyle: AppTextStyles.bodyS
                  .copyWith(color: AppColors.textMuted),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 14),
              border: InputBorder.none,
            ),
          ),
        ),
        if (showError) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              errorText,
              style: AppTextStyles.caption
                  .copyWith(color: AppColors.danger),
            ),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _LoadingView  (requesting or saving)
// ─────────────────────────────────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  const _LoadingView();

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
