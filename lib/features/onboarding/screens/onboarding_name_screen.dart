import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/state/demo_profile.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/icebreaker_logo.dart';

/// Onboarding — Step 1: First name.
///
/// Saves firstName to:
///   • Firestore  users/{uid}  (merge update)
///   • DemoProfileScope        (in-memory, keeps the rest of the app in sync)
///
/// Continue is disabled until the input passes [_isValid].
/// On success navigates to the next onboarding step.
class OnboardingNameScreen extends StatefulWidget {
  const OnboardingNameScreen({super.key});

  @override
  State<OnboardingNameScreen> createState() => _OnboardingNameScreenState();
}

class _OnboardingNameScreenState extends State<OnboardingNameScreen> {
  final _nameController = TextEditingController();
  final _nameFocus = FocusNode();

  bool _isSaving = false;
  String? _errorMessage;

  // At least one Unicode letter — rejects pure-symbol / pure-number inputs.
  static final _hasLetter = RegExp(r'\p{L}', unicode: true);

  @override
  void initState() {
    super.initState();
    // Rebuild on every keystroke to keep button enabled/disabled in sync.
    _nameController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  // ─── Validation ─────────────────────────────────────────────────────────────

  String get _trimmed => _nameController.text.trim();

  bool get _isValid =>
      _trimmed.length >= 2 &&
      _trimmed.length <= AppConstants.firstNameMaxLength &&
      _hasLetter.hasMatch(_trimmed);

  // ─── Save + advance ─────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_isValid || _isSaving) return;
    _nameFocus.unfocus();

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final name = _trimmed;
    final uid = FirebaseAuth.instance.currentUser?.uid;

    // ── 1. Firestore ──────────────────────────────────────────────────────────
    if (uid != null) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .set({'firstName': name}, SetOptions(merge: true));
        // ignore: avoid_print
        print('[Onboarding/Name] ✅ Firestore users/$uid.firstName="$name"');
      } on FirebaseException catch (e) {
        // ignore: avoid_print
        print('[Onboarding/Name] ❌ Firestore ${e.code}: ${e.message}');
        if (!mounted) return;
        setState(() {
          _isSaving = false;
          _errorMessage = "Couldn't save. Check your connection and try again.";
        });
        return;
      } catch (e) {
        // ignore: avoid_print
        print('[Onboarding/Name] ❌ Unexpected: $e');
        if (!mounted) return;
        setState(() {
          _isSaving = false;
          _errorMessage = 'Something went wrong. Please try again.';
        });
        return;
      }
    }

    // ── 2. In-memory profile ──────────────────────────────────────────────────
    if (mounted) {
      final p = DemoProfileScope.of(context);
      p.saveTextFields(
        firstName: name,
        age: p.age,
        bio: p.bio,
        occupation: p.occupation,
        height: p.height,
        lookingFor: p.lookingFor,
        interestedIn: p.interestedIn,
        ageRange: p.ageRange,
        interests: p.interests,
        hobbies: p.hobbies,
      );
    }

    // ── 3. Advance ────────────────────────────────────────────────────────────
    if (!mounted) return;
    // TODO: replace with AppRoutes.onboardingBirthday once that screen is built.
    context.go(AppRoutes.profile);
  }

  // ─── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      // true so the Scaffold shrinks when the keyboard opens, keeping the
      // Continue button visible above it (the Spacer absorbs the difference).
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 52),

              // Logo — small, static, no heartbeat (user isn't live yet)
              const Center(child: IcebreakerLogo(size: 56, showGlow: false)),
              const SizedBox(height: 32),

              // Question
              Text(
                "What's your first name?",
                style: AppTextStyles.h2,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),

              // Helper
              Text(
                'This is how people will see you on Icebreaker.',
                style: AppTextStyles.bodyS,
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 40),

              // Input field
              TextField(
                controller: _nameController,
                focusNode: _nameFocus,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                maxLength: AppConstants.firstNameMaxLength,
                enabled: !_isSaving,
                style: AppTextStyles.body,
                decoration: InputDecoration(
                  labelText: 'FIRST NAME',
                  hintText: 'e.g. Alex',
                  counterText: '',
                  filled: true,
                  fillColor: AppColors.bgInput,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: AppColors.brandPink,
                      width: 1.5,
                    ),
                  ),
                  disabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  labelStyle: AppTextStyles.caption
                      .copyWith(color: AppColors.textSecondary),
                ),
                onSubmitted: (_) => _save(),
              ),

              // Inline error message
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                child: _errorMessage != null
                    ? Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.error_outline_rounded,
                              color: AppColors.danger,
                              size: 14,
                            ),
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

              // Spacer pushes the button to the bottom and shrinks when the
              // keyboard opens (resizeToAvoidBottomInset keeps it in view).
              const Spacer(),

              // Continue button
              GestureDetector(
                onTap: (_isValid && !_isSaving) ? _save : null,
                child: AnimatedOpacity(
                  opacity: (_isValid && !_isSaving) ? 1.0 : 0.38,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    height: 56,
                    decoration: BoxDecoration(
                      gradient: AppColors.brandGradient,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: _isValid
                          ? [
                              BoxShadow(
                                color:
                                    AppColors.brandPink.withValues(alpha: 0.32),
                                blurRadius: 18,
                                offset: const Offset(0, 5),
                              ),
                            ]
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: _isSaving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : Text('Continue', style: AppTextStyles.buttonL),
                  ),
                ),
              ),

              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }
}
