import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/profile_repository.dart';
import '../../../core/state/user_profile.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/icebreaker_logo.dart';

/// Onboarding — Step 3: Gender + who you're open to meeting.
///
/// Combines what used to be two separate screens (Gender and Open To) into
/// one — both are single-tap selections that together define the orientation
/// gate the Nearby carousel runs.  The standalone Open To screen file still
/// exists as a fallback (e.g. for accounts mid-flow under the prior code
/// path) but the new flow writes both values from here.
///
/// Firestore storage (users/{uid} + profiles/{uid}):
///   gender         String  — 'male' | 'female' | 'non_binary' | 'other'
///   genderCustom   String? — only when gender == 'other'
///   interestedIn   String  — 'women' | 'men' | 'non_binary' | 'everyone'
///
/// `openTo` is intentionally NOT written — that's a legacy field name.  The
/// sign-in resume gate now checks `interestedIn` instead.
class OnboardingGenderScreen extends StatefulWidget {
  const OnboardingGenderScreen({super.key});

  @override
  State<OnboardingGenderScreen> createState() => _OnboardingGenderScreenState();
}

class _OnboardingGenderScreenState extends State<OnboardingGenderScreen> {
  Gender? _selectedGender;
  _OpenToOption? _selectedOpenTo;

  // Self-describe text field — only active when gender == Gender.other
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
    if (_selectedGender == null || _selectedOpenTo == null) return false;
    if (_selectedGender == Gender.other) {
      return _customTrimmed.length >= 2 &&
          _customTrimmed.length <= _customMaxLength &&
          _hasLetter.hasMatch(_customTrimmed);
    }
    return true;
  }

  // ─── Option taps ───────────────────────────────────────────────────────────

  void _onGenderTap(Gender gender) {
    setState(() {
      _selectedGender = gender;
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

  void _onOpenToTap(_OpenToOption option) {
    setState(() {
      _selectedOpenTo = option;
      _errorMessage = null;
    });
  }

  // ─── Save + advance ─────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_isValid || _isSaving) return;
    _customFocus.unfocus();

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final gender = _selectedGender!;
    final openTo = _selectedOpenTo!;
    final uid = FirebaseAuth.instance.currentUser?.uid;

    // ── Firestore ─────────────────────────────────────────────────────────────
    if (uid != null) {
      try {
        final Map<String, dynamic> userPayload = {
          'gender': gender.firestoreValue,
          'interestedIn': openTo.firestoreValue,
        };
        if (gender == Gender.other) {
          userPayload['genderCustom'] = _customTrimmed;
        } else {
          // Clear any previous custom value if the user went back and changed.
          userPayload['genderCustom'] = FieldValue.delete();
        }

        // Dual-write to users/{uid} (legacy/private surface) and profiles/{uid}
        // (canonical public surface). Both stores must carry interestedIn and
        // gender because the Nearby filter reads from both as a fallback chain.
        await Future.wait([
          FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .set(userPayload, SetOptions(merge: true)),
          ProfileRepository().setFields(uid, {
            'gender': gender.firestoreValue,
            'interestedIn': openTo.firestoreValue,
            if (gender == Gender.other) 'genderCustom': _customTrimmed,
          }),
        ]);
        // ignore: avoid_print
        print('[Onboarding/Gender] ✅ gender=${gender.firestoreValue} '
            'interestedIn=${openTo.firestoreValue}'
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

    // ── In-memory profile mirror ──────────────────────────────────────────────
    if (mounted) {
      final p = UserProfileScope.of(context);
      p.saveTextFields(
        firstName: p.firstName,
        age: p.age,
        bio: p.bio,
        occupation: p.occupation,
        height: p.height,
        lookingFor: p.lookingFor,
        interestedIn: openTo.firestoreValue,
        ageRange: p.ageRange,
        interests: p.interests,
        hobbies: p.hobbies,
        maxDistanceMeters: p.maxDistanceMeters,
      );
    }

    // ── Advance — skip the standalone Open To screen AND the now-removed
    //              Orientation screen, jump straight to Location.
    if (!mounted) return;
    context.go(AppRoutes.onboardingLocation);
  }

  // ─── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
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
                    const SizedBox(height: 44),

                    const Center(
                        child: IcebreakerLogo(size: 52, showGlow: false)),
                    const SizedBox(height: 24),

                    Text(
                      'About you',
                      style: AppTextStyles.h2,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),

                    Text(
                      'Both help us show you the right people nearby.',
                      style: AppTextStyles.bodyS,
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 28),

                    // ── Gender section ────────────────────────────────────────
                    _SectionLabel(text: "I'm a"),
                    const SizedBox(height: 10),

                    _PickerOption(
                      label: 'Woman',
                      isSelected: _selectedGender == Gender.female,
                      onTap: () => _onGenderTap(Gender.female),
                    ),
                    const SizedBox(height: 8),
                    _PickerOption(
                      label: 'Man',
                      isSelected: _selectedGender == Gender.male,
                      onTap: () => _onGenderTap(Gender.male),
                    ),
                    const SizedBox(height: 8),
                    _PickerOption(
                      label: 'Non-binary',
                      isSelected: _selectedGender == Gender.nonBinary,
                      onTap: () => _onGenderTap(Gender.nonBinary),
                    ),
                    const SizedBox(height: 8),
                    _PickerOption(
                      label: 'Prefer to self-describe',
                      isSelected: _selectedGender == Gender.other,
                      onTap: () => _onGenderTap(Gender.other),
                    ),

                    // Self-describe text field — slides in when selected
                    AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      child: _selectedGender == Gender.other
                          ? Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: TextField(
                                controller: _customController,
                                focusNode: _customFocus,
                                textCapitalization:
                                    TextCapitalization.sentences,
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
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),

                    const SizedBox(height: 24),

                    // ── Interested in section ─────────────────────────────────
                    _SectionLabel(text: 'Interested in meeting'),
                    const SizedBox(height: 10),

                    for (final option in _OpenToOption.values) ...[
                      _PickerOption(
                        label: option.displayLabel,
                        isSelected: _selectedOpenTo == option,
                        onTap: () => _onOpenToTap(option),
                      ),
                      if (option != _OpenToOption.values.last)
                        const SizedBox(height: 8),
                    ],

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
// Section label
// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTextStyles.caption.copyWith(
        color: AppColors.brandCyan,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _PickerOption — shared option card used by both pickers on this screen
// ─────────────────────────────────────────────────────────────────────────────

/// Compact tappable option card (48px tall — smaller than the single-purpose
/// gender screen's 56px row so both pickers fit comfortably on one screen).
///
/// Selected state: brand-pink border + soft pink fill tint + check icon.
/// Unselected state: subtle divider border + dark input fill.
class _PickerOption extends StatelessWidget {
  const _PickerOption({
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
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 18),
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
                size: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _OpenToOption — canonical preference values for the Interested-In picker.
//
// Mirrors the standalone OnboardingOpenToScreen's options exactly so the
// two paths produce identical Firestore writes.  Non-binary is included for
// parity with Edit Profile.
// ─────────────────────────────────────────────────────────────────────────────

enum _OpenToOption {
  women,
  men,
  nonBinary,
  everyone;

  String get displayLabel => switch (this) {
        _OpenToOption.women => 'Women',
        _OpenToOption.men => 'Men',
        _OpenToOption.nonBinary => 'Non-binary',
        _OpenToOption.everyone => 'Everyone',
      };

  String get firestoreValue => switch (this) {
        _OpenToOption.women => 'women',
        _OpenToOption.men => 'men',
        _OpenToOption.nonBinary => 'non_binary',
        _OpenToOption.everyone => 'everyone',
      };
}
