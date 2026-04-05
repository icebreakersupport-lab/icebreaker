import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/icebreaker_logo.dart';

/// Onboarding — Step 5: Orientation (optional).
///
/// This screen is skippable. Skipping writes nothing to Firestore —
/// the field is simply absent on the user document until they set it.
///
/// Firestore storage (users/{uid}):
///   orientation       String?  — canonical value (see [_OrientationOption.firestoreValue])
///                                absent when skipped; present otherwise
///   orientationCustom String?  — only present when orientation == 'other';
///                                holds the user's free-text self-description
///
/// A local _OrientationOption enum is used instead of the shared
/// Orientation enum in app_constants.dart to avoid touching code that
/// the rest of the app (profile, edit-profile) already reads.
class OnboardingOrientationScreen extends StatefulWidget {
  const OnboardingOrientationScreen({super.key});

  @override
  State<OnboardingOrientationScreen> createState() =>
      _OnboardingOrientationScreenState();
}

class _OnboardingOrientationScreenState
    extends State<OnboardingOrientationScreen> {
  _OrientationOption? _selected;

  final _customController = TextEditingController();
  final _customFocus = FocusNode();
  final _scrollController = ScrollController();

  bool _isSaving = false;
  String? _errorMessage;

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
    _scrollController.dispose();
    super.dispose();
  }

  // ─── Validation ─────────────────────────────────────────────────────────────

  String get _customTrimmed => _customController.text.trim();

  bool get _isValid {
    if (_selected == null) return false;
    if (_selected == _OrientationOption.selfDescribe) {
      return _customTrimmed.length >= 2 &&
          _customTrimmed.length <= _customMaxLength &&
          _hasLetter.hasMatch(_customTrimmed);
    }
    return true;
  }

  // ─── Option tap ─────────────────────────────────────────────────────────────

  void _onOptionTap(_OrientationOption option) {
    setState(() {
      _selected = option;
      _errorMessage = null;
    });
    if (option == _OrientationOption.selfDescribe) {
      // Wait for AnimatedSize + scroll to settle, then focus + scroll to bottom.
      Future.delayed(const Duration(milliseconds: 240), () {
        if (!mounted) return;
        _customFocus.requestFocus();
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } else {
      _customFocus.unfocus();
    }
  }

  // ─── Navigate (shared by Continue and Skip) ──────────────────────────────

  void _navigateNext() {
    if (!mounted) return;
    context.go(AppRoutes.onboardingLocation);
  }

  // ─── Save + advance ─────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_isValid || _isSaving) return;
    _customFocus.unfocus();

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final option = _selected!;
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid != null) {
      try {
        final Map<String, dynamic> payload = {
          'orientation': option.firestoreValue,
        };
        if (option == _OrientationOption.selfDescribe) {
          payload['orientationCustom'] = _customTrimmed;
        } else {
          payload['orientationCustom'] = FieldValue.delete();
        }

        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .set(payload, SetOptions(merge: true));
        // ignore: avoid_print
        print('[Onboarding/Orientation] ✅ orientation=${option.firestoreValue}'
            '${option == _OrientationOption.selfDescribe ? ' custom="$_customTrimmed"' : ''}');
      } on FirebaseException catch (e) {
        // ignore: avoid_print
        print('[Onboarding/Orientation] ❌ Firestore ${e.code}: ${e.message}');
        if (!mounted) return;
        setState(() {
          _isSaving = false;
          _errorMessage = "Couldn't save. Check your connection and try again.";
        });
        return;
      } catch (e) {
        // ignore: avoid_print
        print('[Onboarding/Orientation] ❌ Unexpected: $e');
        if (!mounted) return;
        setState(() {
          _isSaving = false;
          _errorMessage = 'Something went wrong. Please try again.';
        });
        return;
      }
    }

    _navigateNext();
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
                controller: _scrollController,
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
                      'How do you identify?',
                      style: AppTextStyles.h2,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),

                    Text(
                      'Optional — this can help make your profile more personal.',
                      style: AppTextStyles.bodyS,
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 32),

                    // ── Option list ───────────────────────────────────────────
                    for (final option in _OrientationOption.values) ...[
                      _OrientationOptionCard(
                        label: option.displayLabel,
                        isSelected: _selected == option,
                        onTap: () => _onOptionTap(option),
                      ),
                      if (option != _OrientationOption.values.last)
                        const SizedBox(height: 10),
                    ],

                    // Self-describe text field
                    AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      child: _selected == _OrientationOption.selfDescribe
                          ? Padding(
                              padding: const EdgeInsets.only(top: 14),
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
                                  hintText: 'Describe your orientation',
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

                    // Error
                    AnimatedSize(
                      duration: const Duration(milliseconds: 180),
                      child: _errorMessage != null
                          ? Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Row(
                                children: [
                                  const Icon(Icons.error_outline_rounded,
                                      color: AppColors.danger, size: 14),
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

            // ── Bottom action area ────────────────────────────────────────────
            AnimatedPadding(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              padding: EdgeInsets.fromLTRB(
                28,
                12,
                28,
                20 +
                    MediaQuery.viewInsetsOf(context).bottom +
                    MediaQuery.paddingOf(context).bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Continue
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

                  const SizedBox(height: 14),

                  // Skip
                  GestureDetector(
                    onTap: _isSaving ? null : _navigateNext,
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        'Skip',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.body.copyWith(
                          color: Colors.white.withValues(alpha: 0.45),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _OrientationOption
// ─────────────────────────────────────────────────────────────────────────────

/// Local enum for the orientation picker.
///
/// Kept local to avoid modifying the shared Orientation enum in
/// app_constants.dart, which the profile/edit-profile screens already read.
enum _OrientationOption {
  straight,
  gay,
  lesbian,
  bisexual,
  pansexual,
  asexual,
  queer,
  selfDescribe;

  String get displayLabel => switch (this) {
        _OrientationOption.straight => 'Straight',
        _OrientationOption.gay => 'Gay',
        _OrientationOption.lesbian => 'Lesbian',
        _OrientationOption.bisexual => 'Bisexual',
        _OrientationOption.pansexual => 'Pansexual',
        _OrientationOption.asexual => 'Asexual',
        _OrientationOption.queer => 'Queer',
        _OrientationOption.selfDescribe => 'Prefer to self-describe',
      };

  String get firestoreValue => switch (this) {
        _OrientationOption.straight => 'straight',
        _OrientationOption.gay => 'gay',
        _OrientationOption.lesbian => 'lesbian',
        _OrientationOption.bisexual => 'bisexual',
        _OrientationOption.pansexual => 'pansexual',
        _OrientationOption.asexual => 'asexual',
        _OrientationOption.queer => 'queer',
        _OrientationOption.selfDescribe => 'other',
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// _OrientationOptionCard
// ─────────────────────────────────────────────────────────────────────────────

class _OrientationOptionCard extends StatelessWidget {
  const _OrientationOptionCard({
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
        height: 52,
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
