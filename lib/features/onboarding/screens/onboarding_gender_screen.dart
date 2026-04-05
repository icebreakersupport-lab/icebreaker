import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/icebreaker_logo.dart';

/// Onboarding — Step 3: Gender.
///
/// Firestore storage (users/{uid}):
///   gender       String  — canonical value ('male' | 'female' | 'non_binary' | 'other')
///   genderCustom String? — only present when gender == 'other'; holds the user's
///                          free-text self-description
///
/// Keeping the canonical value separate from the custom label allows the
/// discovery/filtering layer to query on gender without parsing free text.
/// The custom label is for display only.
class OnboardingGenderScreen extends StatefulWidget {
  const OnboardingGenderScreen({super.key});

  @override
  State<OnboardingGenderScreen> createState() => _OnboardingGenderScreenState();
}

class _OnboardingGenderScreenState extends State<OnboardingGenderScreen> {
  Gender? _selected;

  // Self-describe text field — only active when _selected == Gender.other
  final _customController = TextEditingController();
  final _customFocus = FocusNode();

  bool _isSaving = false;
  String? _errorMessage;

  // Unicode letter check — same rule as the Name screen.
  static final _hasLetter = RegExp(r'\p{L}', unicode: true);

  static const int _customMaxLength = 40;

  @override
  void initState() {
    super.initState();
    _customController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _customController.dispose();
    _customFocus.dispose();
    super.dispose();
  }

  // ─── Validation ─────────────────────────────────────────────────────────────

  String get _customTrimmed => _customController.text.trim();

  bool get _isValid {
    if (_selected == null) return false;
    if (_selected == Gender.other) {
      return _customTrimmed.length >= 2 &&
          _customTrimmed.length <= _customMaxLength &&
          _hasLetter.hasMatch(_customTrimmed);
    }
    return true;
  }

  // ─── Option tap ─────────────────────────────────────────────────────────────

  void _onOptionTap(Gender gender) {
    setState(() {
      _selected = gender;
      _errorMessage = null;
    });
    if (gender == Gender.other) {
      // Small delay so AnimatedSize finishes before requesting focus.
      Future.delayed(const Duration(milliseconds: 220), () {
        if (mounted) _customFocus.requestFocus();
      });
    } else {
      _customFocus.unfocus();
    }
  }

  // ─── Save + advance ─────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_isValid || _isSaving) return;
    _customFocus.unfocus();

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final gender = _selected!;
    final uid = FirebaseAuth.instance.currentUser?.uid;

    // ── Firestore ─────────────────────────────────────────────────────────────
    if (uid != null) {
      try {
        final Map<String, dynamic> payload = {
          'gender': gender.firestoreValue,
        };
        if (gender == Gender.other) {
          payload['genderCustom'] = _customTrimmed;
        } else {
          // Clear any previous custom value if the user went back and changed.
          payload['genderCustom'] = FieldValue.delete();
        }

        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .set(payload, SetOptions(merge: true));
        // ignore: avoid_print
        print('[Onboarding/Gender] ✅ gender=${gender.firestoreValue}'
            '${gender == Gender.other ? ' custom="$_customTrimmed"' : ''}');
      } on FirebaseException catch (e) {
        // ignore: avoid_print
        print('[Onboarding/Gender] ❌ Firestore ${e.code}: ${e.message}');
        if (!mounted) return;
        setState(() {
          _isSaving = false;
          _errorMessage = "Couldn't save. Check your connection and try again.";
        });
        return;
      } catch (e) {
        // ignore: avoid_print
        print('[Onboarding/Gender] ❌ Unexpected: $e');
        if (!mounted) return;
        setState(() {
          _isSaving = false;
          _errorMessage = 'Something went wrong. Please try again.';
        });
        return;
      }
    }

    // ── Advance ───────────────────────────────────────────────────────────────
    if (!mounted) return;
    context.go(AppRoutes.onboardingOpenTo);
  }

  // ─── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      // false — keyboard inset handled manually via viewInsets in button padding.
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Scrollable content ───────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 52),

                    const Center(
                        child: IcebreakerLogo(size: 56, showGlow: false)),
                    const SizedBox(height: 32),

                    Text(
                      "What's your gender?",
                      style: AppTextStyles.h2,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),

                    Text(
                      'This helps us show you relevant people and build your profile.',
                      style: AppTextStyles.bodyS,
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 32),

                    // ── Options ───────────────────────────────────────────────
                    _GenderOption(
                      label: 'Woman',
                      isSelected: _selected == Gender.female,
                      onTap: () => _onOptionTap(Gender.female),
                    ),
                    const SizedBox(height: 12),
                    _GenderOption(
                      label: 'Man',
                      isSelected: _selected == Gender.male,
                      onTap: () => _onOptionTap(Gender.male),
                    ),
                    const SizedBox(height: 12),
                    _GenderOption(
                      label: 'Non-binary',
                      isSelected: _selected == Gender.nonBinary,
                      onTap: () => _onOptionTap(Gender.nonBinary),
                    ),
                    const SizedBox(height: 12),
                    _GenderOption(
                      label: 'Prefer to self-describe',
                      isSelected: _selected == Gender.other,
                      onTap: () => _onOptionTap(Gender.other),
                    ),

                    // Self-describe text field — slides in when selected
                    AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      child: _selected == Gender.other
                          ? Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: TextField(
                                controller: _customController,
                                focusNode: _customFocus,
                                textCapitalization: TextCapitalization.sentences,
                                textInputAction: TextInputAction.done,
                                maxLength: _customMaxLength,
                                enabled: !_isSaving,
                                style: AppTextStyles.body,
                                decoration: InputDecoration(
                                  hintText: 'Describe your gender',
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
                                ),
                                onSubmitted: (_) => _save(),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),

                    // Error message
                    AnimatedSize(
                      duration: const Duration(milliseconds: 180),
                      child: _errorMessage != null
                          ? Padding(
                              padding: const EdgeInsets.only(top: 12),
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

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            // ── Continue button pinned at bottom ─────────────────────────────
            // Padding includes keyboard height so the button floats above the
            // keyboard when the self-describe field is focused.
            AnimatedPadding(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              padding: EdgeInsets.fromLTRB(
                28,
                12,
                28,
                28 +
                    MediaQuery.viewInsetsOf(context).bottom +
                    MediaQuery.paddingOf(context).bottom,
              ),
              child: GestureDetector(
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
                                color: AppColors.brandPink
                                    .withValues(alpha: 0.32),
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
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _GenderOption
// ─────────────────────────────────────────────────────────────────────────────

/// Full-width tappable option card.
///
/// Selected state: brand-pink border + soft pink fill tint + check icon.
/// Unselected state: subtle divider border + dark input fill.
class _GenderOption extends StatelessWidget {
  const _GenderOption({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.brandPink.withValues(alpha: 0.10)
              : AppColors.bgInput,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.brandPink : AppColors.divider,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Text(
              label,
              style: AppTextStyles.body.copyWith(
                color: isSelected
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
                fontWeight:
                    isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            const Spacer(),
            AnimatedOpacity(
              opacity: isSelected ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 180),
              child: const Icon(
                Icons.check_circle_rounded,
                color: AppColors.brandPink,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
