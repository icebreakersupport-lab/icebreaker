import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
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
  final _confirmController = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmFocus = FocusNode();

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Rebuild when confirm field changes to re-evaluate mismatch hint.
    _confirmController.addListener(() => setState(() {}));
    _passwordController.addListener(() => setState(() {}));
    _emailController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  bool get _emailValid =>
      _emailController.text.trim().contains('@') &&
      _emailController.text.trim().contains('.');

  bool get _passwordValid => _passwordController.text.length >= 8;

  bool get _passwordsMatch =>
      _confirmController.text == _passwordController.text;

  bool get _confirmNonEmpty => _confirmController.text.isNotEmpty;

  bool get _isValid => _emailValid && _passwordValid && _passwordsMatch;

  Future<void> _signUp() async {
    if (!_isValid || _isLoading) return;
    _emailFocus.unfocus();
    _passwordFocus.unfocus();
    _confirmFocus.unfocus();

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final credential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      // Create Firestore user document on first sign-up.
      final uid = credential.user!.uid;
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'uid': uid,
        'email': _emailController.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'profileComplete': false,
      });

      if (!mounted) return;
      // Always require phone verification after sign-up.
      context.go(AppRoutes.verifyPhone);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = _mapError(e.code);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
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
    // Show password mismatch hint only once confirm has content.
    final showMismatch = _confirmNonEmpty && !_passwordsMatch;

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
                  const SizedBox(height: 52),

                  // ── Logo ────────────────────────────────────────────────
                  const Center(
                    child: IcebreakerLogo(size: 56, showGlow: false),
                  ),
                  const SizedBox(height: 28),

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

                  const SizedBox(height: 40),

                  // ── Email ────────────────────────────────────────────────
                  AuthTextField(
                    controller: _emailController,
                    focusNode: _emailFocus,
                    label: 'EMAIL',
                    hint: 'you@example.com',
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.newUsername],
                    enabled: !_isLoading,
                    onSubmitted: (_) =>
                        FocusScope.of(context).requestFocus(_passwordFocus),
                  ),
                  const SizedBox(height: 16),

                  // ── Password ─────────────────────────────────────────────
                  AuthTextField(
                    controller: _passwordController,
                    focusNode: _passwordFocus,
                    label: 'PASSWORD',
                    hint: 'At least 8 characters',
                    isPassword: true,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.newPassword],
                    enabled: !_isLoading,
                    onSubmitted: (_) =>
                        FocusScope.of(context).requestFocus(_confirmFocus),
                  ),
                  const SizedBox(height: 16),

                  // ── Confirm password ─────────────────────────────────────
                  AuthTextField(
                    controller: _confirmController,
                    focusNode: _confirmFocus,
                    label: 'CONFIRM PASSWORD',
                    hint: 'Re-enter your password',
                    isPassword: true,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.newPassword],
                    enabled: !_isLoading,
                    onSubmitted: (_) => _signUp(),
                  ),

                  // ── Password mismatch hint ────────────────────────────────
                  AnimatedSize(
                    duration: const Duration(milliseconds: 180),
                    child: showMismatch
                        ? Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline_rounded,
                                    color: AppColors.warning, size: 14),
                                const SizedBox(width: 6),
                                Text(
                                  'Passwords don\'t match.',
                                  style: AppTextStyles.caption.copyWith(
                                      color: AppColors.warning),
                                ),
                              ],
                            ),
                          )
                        : const SizedBox.shrink(),
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
                    enabled: _isValid && !_isLoading,
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
