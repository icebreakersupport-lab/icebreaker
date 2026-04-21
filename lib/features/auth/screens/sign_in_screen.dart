import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/state/live_session.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/icebreaker_logo.dart';
import '../widgets/auth_text_field.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Rebuild on every keystroke so _isValid / button-enabled state stays current.
    _emailController.addListener(() => setState(() {}));
    _passwordController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  bool get _isValid =>
      _emailController.text.trim().contains('@') &&
      _passwordController.text.isNotEmpty;

  Future<void> _signIn() async {
    // ignore: avoid_print
    print('[SignIn] ▶ button tapped — isValid=$_isValid isLoading=$_isLoading');
    if (!_isValid || _isLoading) {
      // ignore: avoid_print
      print('[SignIn] ❌ blocked — isValid=$_isValid isLoading=$_isLoading');
      return;
    }
    _emailFocus.unfocus();
    _passwordFocus.unfocus();

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final email = _emailController.text.trim();
    // ignore: avoid_print
    print('[SignIn] ▶ STEP 1 — signInWithEmailAndPassword for $email');

    try {
      final credential =
          await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: _passwordController.text,
      );

      final uid = credential.user!.uid;
      // ignore: avoid_print
      print('[SignIn] ✅ STEP 1 DONE — signed in uid=$uid phone=${credential.user!.phoneNumber}');

      if (!mounted) return;
      // ignore: avoid_print
      print('[SignIn] ▶ STEP 2 — routing after auth');
      await _routeAfterAuth(credential.user!);
    } on FirebaseAuthException catch (e) {
      // ignore: avoid_print
      print('[SignIn] ❌ FirebaseAuthException'
          '\n  code:    ${e.code}'
          '\n  message: ${e.message}'
          '\n  plugin:  ${e.plugin}');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = _mapError(e.code);
      });
    } catch (e, st) {
      // ignore: avoid_print
      print('[SignIn] ❌ Unknown exception\n  $e\n$st');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Something went wrong. Please try again.';
      });
    }
  }

  /// Decides where to send the user after a successful sign-in.
  ///
  /// Fetches users/{uid} from Firestore:
  ///   - read error          → show inline error, stay on sign-in screen
  ///   - doc missing         → create doc with defaults, go to onboarding
  ///   - profileComplete=false → go to onboarding
  ///   - profileComplete=true  → go to home
  Future<void> _routeAfterAuth(User user) async {
    // ignore: avoid_print
    print('[SignIn] ▶ STEP 2a — fetching Firestore doc for ${user.uid}');

    // ── Read the user doc ──────────────────────────────────────────────────
    DocumentSnapshot<Map<String, dynamic>> doc;
    try {
      doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      // ignore: avoid_print
      print('[SignIn] ✅ STEP 2a DONE — exists=${doc.exists}');
    } on FirebaseException catch (e) {
      // ignore: avoid_print
      print('[SignIn] ❌ STEP 2a Firestore read failed'
          '\n  code:    ${e.code}'
          '\n  message: ${e.message}');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Could not load your profile. Please try again.';
      });
      return;
    } catch (e, st) {
      // ignore: avoid_print
      print('[SignIn] ❌ STEP 2a unknown error\n  $e\n$st');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Something went wrong. Please try again.';
      });
      return;
    }

    // ── Doc missing: create with sensible defaults, then go to onboarding ──
    if (!doc.exists) {
      // ignore: avoid_print
      print('[SignIn] ⚠️ STEP 2a — doc missing, creating with defaults');
      try {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'uid': user.uid,
          'email': user.email ?? '',
          'createdAt': FieldValue.serverTimestamp(),
          'profileComplete': false,
          'plan': 'free',
          'icebreakerCredits': AppConstants.freeIcebreakerCreditsPerSignup,
          'liveCredits': AppConstants.freeGoLiveCreditsPerSignup,
          'icebreakerCreditsResetAt': Timestamp.fromDate(
            DateTime.now().add(const Duration(hours: 24)),
          ),
        });
        // ignore: avoid_print
        print('[SignIn] ✅ STEP 2a — default doc created');
      } on FirebaseException catch (e) {
        // ignore: avoid_print
        print('[SignIn] ⚠️ STEP 2a — default doc creation failed: ${e.code}');
        // Non-fatal: proceed to onboarding so the user can still fill in
        // their profile. The doc will be written when onboarding completes.
      }
      if (!mounted) return;
      // ignore: avoid_print
      print('[SignIn] ▶ STEP 2b — doc was missing → ${AppRoutes.onboardingName}');
      context.go(AppRoutes.onboardingName);
      return;
    }

    // ── Route based on profileComplete flag ────────────────────────────────
    final data = doc.data() ?? {};
    final profileComplete = data['profileComplete'] as bool? ?? false;
    // ignore: avoid_print
    print('[SignIn] ▶ STEP 2b — profileComplete=$profileComplete');

    if (!mounted) return;

    // Hydrate credit state now that we know the widget is still mounted.
    // Fire-and-forget — navigation proceeds; the counter updates reactively.
    LiveSessionScope.of(context).hydrateCredits(user.uid);

    if (profileComplete) {
      context.go(AppRoutes.home);
    } else {
      context.go(_resumeOnboardingRoute(data));
    }
    // ignore: avoid_print
    print('[SignIn] ✅ STEP 2b DONE — navigation triggered');
  }

  /// Returns the onboarding route where the user dropped off by checking which
  /// required fields are already present in their Firestore document.
  String _resumeOnboardingRoute(Map<String, dynamic> data) {
    if (data['firstName'] == null) return AppRoutes.onboardingName;
    if (data['birthday'] == null) return AppRoutes.onboardingBirthday;
    if (data['gender'] == null) return AppRoutes.onboardingGender;
    if (data['openTo'] == null) return AppRoutes.onboardingOpenTo;
    if (data['hometown'] == null) return AppRoutes.onboardingLocation;
    // Has all text data but didn't finish — resume at photo/slideshow.
    return AppRoutes.onboardingPhoto;
  }

  String _mapError(String code) => switch (code) {
        'user-not-found' => 'No account found with that email.',
        'wrong-password' => 'Incorrect email or password.',
        'invalid-credential' => 'Incorrect email or password.',
        'invalid-email' => 'That doesn\'t look like a valid email.',
        'user-disabled' => 'This account has been disabled.',
        'too-many-requests' => 'Too many attempts. Try again later.',
        'network-request-failed' => 'No internet connection.',
        _ => 'Something went wrong. Please try again.',
      };

  @override
  Widget build(BuildContext context) {
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
                    'Sign in',
                    style: AppTextStyles.h2,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Good to have you back.',
                    style: AppTextStyles.bodyS,
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 44),

                  // ── Email ────────────────────────────────────────────────
                  AuthTextField(
                    controller: _emailController,
                    focusNode: _emailFocus,
                    label: 'EMAIL',
                    hint: 'you@example.com',
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.email],
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
                    hint: '••••••••',
                    isPassword: true,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.password],
                    enabled: !_isLoading,
                    onSubmitted: (_) => _signIn(),
                  ),

                  // ── Forgot password ──────────────────────────────────────
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        // TODO(step-auth): implement forgot password flow
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 8),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        'Forgot password?',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.brandPink,
                        ),
                      ),
                    ),
                  ),

                  // ── Error ────────────────────────────────────────────────
                  AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    child: _errorMessage != null
                        ? Padding(
                            padding: const EdgeInsets.only(bottom: 12),
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

                  const SizedBox(height: 8),

                  // ── Sign In button ───────────────────────────────────────
                  _AuthButton(
                    label: 'Sign In',
                    onTap: _signIn,
                    isLoading: _isLoading,
                    enabled: _isValid && !_isLoading,
                  ),

                  const Spacer(),

                  // ── Navigate to Sign Up ──────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.only(bottom: 28),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "Don't have an account? ",
                          style: AppTextStyles.bodyS,
                        ),
                        GestureDetector(
                          onTap: () => context.go(AppRoutes.signUp),
                          child: Text(
                            'Sign up',
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
