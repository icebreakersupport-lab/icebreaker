import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/apple_auth_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/icebreaker_logo.dart';
import '../widgets/auth_text_field.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();

  bool _isLoading = false;
  bool _isAppleLoading = false;
  bool _appleAvailable = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(() => setState(() {}));
    _emailController.addListener(() => setState(() {}));

    // Probe Apple Sign In availability so we can hide the button on
    // unsupported platforms (Android, web, desktop, sub-iOS 13) instead of
    // showing a button that errors at tap time.
    AppleAuthService.isAvailable().then((available) {
      if (!mounted) return;
      setState(() => _appleAvailable = available);
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  bool get _emailValid =>
      _emailController.text.trim().contains('@') &&
      _emailController.text.trim().contains('.');

  bool get _passwordValid => _passwordController.text.length >= 8;

  bool get _isValid => _emailValid && _passwordValid;

  Future<void> _signUp() async {
    if (!_isValid || _isLoading) return;
    _emailFocus.unfocus();
    _passwordFocus.unfocus();

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final email = _emailController.text.trim();
    // ignore: avoid_print
    print('[SignUp] ▶ STEP 1 — createUserWithEmailAndPassword for $email');

    // ── STEP 1: Firebase Auth ────────────────────────────────────────────────
    String uid;
    try {
      final credential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: _passwordController.text,
      );
      uid = credential.user!.uid;
      // ignore: avoid_print
      print('[SignUp] ✅ STEP 1 DONE — uid=$uid');
    } on FirebaseAuthException catch (e) {
      // ignore: avoid_print
      print('[SignUp] ❌ STEP 1 FirebaseAuthException'
          '\n  code:    ${e.code}'
          '\n  message: ${e.message}'
          '\n  plugin:  ${e.plugin}');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = _mapError(e.code);
      });
      return;
    } catch (e, st) {
      // ignore: avoid_print
      print('[SignUp] ❌ STEP 1 unexpected error'
          '\n  type:  ${e.runtimeType}'
          '\n  error: $e'
          '\n  stack:\n$st');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Something went wrong. Please try again.';
      });
      return;
    }

    // ── STEP 2: Firestore user doc (non-blocking — auth already succeeded) ───
    final fsPath = 'users/$uid';
    final payload = {
      'uid': uid,
      'email': email,
      'createdAt': FieldValue.serverTimestamp(),
      'profileComplete': false,
    };
    // ignore: avoid_print
    print('[SignUp] ▶ STEP 2 — writing Firestore $fsPath'
        '\n  payload: $payload');
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set(payload)
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw Exception('Firestore write timed out after 10s'),
          );
      // ignore: avoid_print
      print('[SignUp] ✅ STEP 2 DONE — Firestore $fsPath written');
    } on FirebaseException catch (e) {
      // Auth succeeded — log Firestore failure with exact code but do NOT block navigation.
      // Most common cause: Firestore Security Rules (permission-denied).
      // ignore: avoid_print
      print('[SignUp] ⚠️ STEP 2 Firestore FirebaseException (non-fatal)'
          '\n  code:    ${e.code}'
          '\n  message: ${e.message}'
          '\n  plugin:  ${e.plugin}'
          '\n  path:    $fsPath'
          '\n  FIX:     If code=permission-denied, update Firestore Security Rules:'
          '\n           allow write: if request.auth != null && request.auth.uid == userId;');
    } catch (e, st) {
      // ignore: avoid_print
      print('[SignUp] ⚠️ STEP 2 Firestore unknown error (non-fatal)'
          '\n  type:  ${e.runtimeType}'
          '\n  error: $e'
          '\n  stack:\n$st');
    }

    // ── STEP 3: Navigate to Profile Setup ────────────────────────────────────
    if (!mounted) return;
    // ignore: avoid_print
    print('[SignUp] ▶ STEP 3 — navigating to ${AppRoutes.onboardingName}');
    context.go(AppRoutes.onboardingName);
    // ignore: avoid_print
    print('[SignUp] ✅ STEP 3 DONE — navigation triggered');
  }

  /// Apple Sign In path — shorter than email/password by an entire screen
  /// AND skips the email verification step (Apple already verified).  On
  /// success we create the same users/{uid} doc the email path creates so
  /// the resume-onboarding gate finds an account to walk through.
  Future<void> _signInWithApple() async {
    if (_isAppleLoading || _isLoading) return;
    setState(() {
      _isAppleLoading = true;
      _errorMessage = null;
    });

    try {
      final user = await AppleAuthService.signIn();
      if (user == null) {
        // User canceled the native sheet — silent, no error.
        if (mounted) setState(() => _isAppleLoading = false);
        return;
      }

      // ── Ensure users/{uid} exists ────────────────────────────────────────
      // Apple sign-in may be either a brand-new account OR a returning user
      // who originally signed up via Apple.  Create the doc with merge so
      // we don't clobber existing profile data on return visits.
      final uid = user.uid;
      final payload = <String, dynamic>{
        'uid': uid,
        'createdAt': FieldValue.serverTimestamp(),
        'profileComplete': false,
      };
      if (user.email != null && user.email!.isNotEmpty) {
        payload['email'] = user.email;
      }
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .set(payload, SetOptions(merge: true))
            .timeout(const Duration(seconds: 10));
      } on FirebaseException catch (e) {
        // ignore: avoid_print
        print('[SignUp/Apple] ⚠️ Firestore write failed (non-fatal): '
            '${e.code} ${e.message}');
      } catch (e) {
        // ignore: avoid_print
        print('[SignUp/Apple] ⚠️ Firestore write failed (non-fatal): $e');
      }

      if (!mounted) return;
      // ignore: avoid_print
      print('[SignUp/Apple] ✅ proceeding to onboarding for uid=$uid');
      context.go(AppRoutes.onboardingName);
    } on FirebaseAuthException catch (e) {
      // ignore: avoid_print
      print('[SignUp/Apple] ❌ FirebaseAuthException code=${e.code}');
      if (!mounted) return;
      setState(() {
        _isAppleLoading = false;
        _errorMessage = _mapError(e.code);
      });
    } on SignInWithAppleAuthorizationException catch (e) {
      // ignore: avoid_print
      print('[SignUp/Apple] ❌ Apple authorization error: ${e.code}');
      if (!mounted) return;
      setState(() {
        _isAppleLoading = false;
        _errorMessage = 'Apple Sign In failed. Please try again.';
      });
    } catch (e, st) {
      // ignore: avoid_print
      print('[SignUp/Apple] ❌ unexpected: $e\n$st');
      if (!mounted) return;
      setState(() {
        _isAppleLoading = false;
        _errorMessage = 'Something went wrong. Please try again.';
      });
    }
  }

  String _mapError(String code) => switch (code) {
        'email-already-in-use' =>
          'An account already exists with that email.',
        'invalid-email' => 'That doesn\'t look like a valid email.',
        'weak-password' => 'Password must be at least 8 characters.',
        'operation-not-allowed' =>
          'Email sign-up is not enabled. Contact support.',
        'network-request-failed' => 'No internet connection.',
        _ => 'Something went wrong. Please try again.',
      };

  @override
  Widget build(BuildContext context) {
    final busy = _isLoading || _isAppleLoading;
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height -
                  MediaQuery.of(context).padding.top -
                  MediaQuery.of(context).padding.bottom,
            ),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 44),

                  // ── Logo ────────────────────────────────────────────────
                  const Center(
                    child: IcebreakerLogo(size: 52, showGlow: false),
                  ),
                  const SizedBox(height: 22),

                  // ── Heading ──────────────────────────────────────────────
                  Text(
                    'Create account',
                    style: AppTextStyles.h2,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Meet real people in real places.',
                    style: AppTextStyles.bodyS,
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 28),

                  // ── Apple Sign In (top of fold so most iOS users tap it
                  //                  before they even start typing) ───────
                  if (_appleAvailable) ...[
                    _AppleSignInButton(
                      onTap: _signInWithApple,
                      isLoading: _isAppleLoading,
                      enabled: !busy,
                    ),
                    const SizedBox(height: 18),
                    const _OrDivider(),
                    const SizedBox(height: 18),
                  ],

                  // ── Email ────────────────────────────────────────────────
                  AuthTextField(
                    controller: _emailController,
                    focusNode: _emailFocus,
                    label: 'EMAIL',
                    hint: 'you@example.com',
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.newUsername],
                    enabled: !busy,
                    onSubmitted: (_) =>
                        FocusScope.of(context).requestFocus(_passwordFocus),
                  ),
                  const SizedBox(height: 16),

                  // ── Password (single field — confirm dropped; tap the eye
                  //              icon in the field to verify what you typed) ─
                  AuthTextField(
                    controller: _passwordController,
                    focusNode: _passwordFocus,
                    label: 'PASSWORD',
                    hint: 'At least 8 characters',
                    isPassword: true,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.newPassword],
                    enabled: !busy,
                    onSubmitted: (_) => _signUp(),
                  ),

                  // ── Firebase error ───────────────────────────────────────
                  AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    child: _errorMessage != null
                        ? Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline_rounded,
                                    color: AppColors.danger, size: 15),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: AppTextStyles.caption
                                        .copyWith(color: AppColors.danger),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),

                  const SizedBox(height: 24),

                  // ── Create Account button ─────────────────────────────────
                  _AuthButton(
                    label: 'Create Account',
                    onTap: _signUp,
                    isLoading: _isLoading,
                    enabled: _isValid && !busy,
                  ),

                  const Spacer(),

                  // ── Navigate to Sign In ───────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.only(bottom: 28),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Already have an account? ',
                          style: AppTextStyles.bodyS,
                        ),
                        GestureDetector(
                          onTap: () => context.go(AppRoutes.signIn),
                          child: Text(
                            'Sign in',
                            style: AppTextStyles.bodyS.copyWith(
                              color: AppColors.brandPink,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Shared gradient button ───────────────────────────────────────────────────

class _AuthButton extends StatelessWidget {
  const _AuthButton({
    required this.label,
    required this.onTap,
    required this.isLoading,
    required this.enabled,
  });

  final String label;
  final VoidCallback onTap;
  final bool isLoading;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedOpacity(
        opacity: enabled ? 1.0 : 0.38,
        duration: const Duration(milliseconds: 200),
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            gradient: AppColors.brandGradient,
            borderRadius: BorderRadius.circular(28),
            boxShadow: enabled
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
          child: isLoading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: Colors.white),
                )
              : Text(label, style: AppTextStyles.buttonL),
        ),
      ),
    );
  }
}

// ─── Apple Sign In button — Human Interface Guidelines compliant ─────────────
//
// Apple requires the button to match their published spec: solid white
// background, black Apple logo + "Sign in with Apple" / "Continue with
// Apple" text, minimum 30pt tall, system font.  Don't restyle to brand
// colors — Apple rejects apps that use a non-standard Sign in with Apple
// button.

class _AppleSignInButton extends StatelessWidget {
  const _AppleSignInButton({
    required this.onTap,
    required this.isLoading,
    required this.enabled,
  });

  final VoidCallback onTap;
  final bool isLoading;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedOpacity(
        opacity: enabled ? 1.0 : 0.45,
        duration: const Duration(milliseconds: 200),
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(26),
          ),
          alignment: Alignment.center,
          child: isLoading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.black,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.apple,
                      color: Colors.black,
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Continue with Apple',
                      style: AppTextStyles.buttonL.copyWith(
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

// ─── "or" divider ────────────────────────────────────────────────────────────
//
// Separates the social-login section from the email/password form.

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Divider(color: AppColors.divider, thickness: 1, height: 1),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'or',
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
        ),
        const Expanded(
          child: Divider(color: AppColors.divider, thickness: 1, height: 1),
        ),
      ],
    );
  }
}
