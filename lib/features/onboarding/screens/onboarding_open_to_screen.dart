import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/state/demo_profile.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/icebreaker_logo.dart';

/// Onboarding — Step 4: Who you're open to meeting.
///
/// Firestore storage (users/{uid}):
///   openTo  String  — 'women' | 'men' | 'everyone'
///
/// A single canonical string is the right shape here because:
///   • Discovery queries filter on a single equality check:
///     where('gender', isEqualTo: X) — and 'everyone' means skip
///     the gender filter entirely, handled in the query layer.
///   • There is no multi-select ambiguity to model.
///
/// DemoProfile:
///   interestedIn  String  — 'Women' | 'Men' | 'Everyone'
///   Keeps the existing in-memory field that the profile/edit screens
///   already read.
class OnboardingOpenToScreen extends StatefulWidget {
  const OnboardingOpenToScreen({super.key});

  @override
  State<OnboardingOpenToScreen> createState() => _OnboardingOpenToScreenState();
}

class _OnboardingOpenToScreenState extends State<OnboardingOpenToScreen> {
  _OpenToOption? _selected;
  bool _isSaving = false;
  String? _errorMessage;

  bool get _isValid => _selected != null;

  // ─── Save + advance ─────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_isValid || _isSaving) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final option = _selected!;
    final uid = FirebaseAuth.instance.currentUser?.uid;

    // ── Firestore ─────────────────────────────────────────────────────────────
    if (uid != null) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .set({'openTo': option.firestoreValue}, SetOptions(merge: true));
        // ignore: avoid_print
        print('[Onboarding/OpenTo] ✅ openTo=${option.firestoreValue}');
      } on FirebaseException catch (e) {
        // ignore: avoid_print
        print('[Onboarding/OpenTo] ❌ Firestore ${e.code}: ${e.message}');
        if (!mounted) return;
        setState(() {
          _isSaving = false;
          _errorMessage = "Couldn't save. Check your connection and try again.";
        });
        return;
      } catch (e) {
        // ignore: avoid_print
        print('[Onboarding/OpenTo] ❌ Unexpected: $e');
        if (!mounted) return;
        setState(() {
          _isSaving = false;
          _errorMessage = 'Something went wrong. Please try again.';
        });
        return;
      }
    }

    // ── In-memory profile ─────────────────────────────────────────────────────
    if (mounted) {
      final p = DemoProfileScope.of(context);
      p.saveTextFields(
        firstName: p.firstName,
        age: p.age,
        bio: p.bio,
        occupation: p.occupation,
        height: p.height,
        lookingFor: p.lookingFor,
        interestedIn: option.displayLabel, // 'Women' | 'Men' | 'Everyone'
        ageRange: p.ageRange,
        interests: p.interests,
        hobbies: p.hobbies,
      );
    }

    // ── Advance ───────────────────────────────────────────────────────────────
    if (!mounted) return;
    // TODO: replace with AppRoutes.onboardingOrientation once that screen is built.
    context.go(AppRoutes.profile);
  }

  // ─── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 52),

              const Center(child: IcebreakerLogo(size: 56, showGlow: false)),
              const SizedBox(height: 32),

              Text(
                'Who are you open to meeting?',
                style: AppTextStyles.h2,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),

              Text(
                "We'll use this to show you people you're interested in.",
                style: AppTextStyles.bodyS,
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 32),

              // ── Options ───────────────────────────────────────────────────
              for (final option in _OpenToOption.values) ...[
                _OpenToCard(
                  option: option,
                  isSelected: _selected == option,
                  onTap: () => setState(() {
                    _selected = option;
                    _errorMessage = null;
                  }),
                ),
                if (option != _OpenToOption.values.last)
                  const SizedBox(height: 12),
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

              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _OpenToOption
// ─────────────────────────────────────────────────────────────────────────────

enum _OpenToOption {
  women,
  men,
  everyone;

  String get displayLabel => switch (this) {
        _OpenToOption.women => 'Women',
        _OpenToOption.men => 'Men',
        _OpenToOption.everyone => 'Everyone',
      };

  /// Canonical value written to Firestore and used by the discovery layer.
  String get firestoreValue => switch (this) {
        _OpenToOption.women => 'women',
        _OpenToOption.men => 'men',
        _OpenToOption.everyone => 'everyone',
      };

  /// Subtitle shown under the label on the card.
  String get subtitle => switch (this) {
        _OpenToOption.women => 'Show me women nearby',
        _OpenToOption.men => 'Show me men nearby',
        _OpenToOption.everyone => 'Show me everyone nearby',
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// _OpenToCard
// ─────────────────────────────────────────────────────────────────────────────

/// Full-width tappable card with label, subtitle, and selection indicator.
///
/// Taller than the Gender options (72px) to accommodate the subtitle line —
/// gives the screen more visual breathing room with only three choices.
class _OpenToCard extends StatelessWidget {
  const _OpenToCard({
    required this.option,
    required this.isSelected,
    required this.onTap,
  });

  final _OpenToOption option;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 72,
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
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option.displayLabel,
                    style: AppTextStyles.body.copyWith(
                      color: isSelected
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    option.subtitle,
                    style: AppTextStyles.caption.copyWith(
                      color: isSelected
                          ? AppColors.brandPink.withValues(alpha: 0.80)
                          : AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
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
