import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/state/demo_profile.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/icebreaker_logo.dart';

/// Onboarding — Step 2: Birthday.
///
/// Uses an inline CupertinoDatePicker bounded to [minAge] years ago so
/// the picker physically prevents underage selection — no post-validation
/// error message needed.
///
/// Saves to:
///   • Firestore  users/{uid}.birthday  (Timestamp — source of truth)
///   • DemoProfileScope.age             (int, derived in-memory for the app)
///
/// Age is NOT written to Firestore because it becomes stale; it is always
/// derived at read time from birthday.
///
/// Continue stays disabled until the user scrolls the picker at least once,
/// ensuring an intentional selection rather than accepting the seeded default.
class OnboardingBirthdayScreen extends StatefulWidget {
  const OnboardingBirthdayScreen({super.key});

  @override
  State<OnboardingBirthdayScreen> createState() =>
      _OnboardingBirthdayScreenState();
}

class _OnboardingBirthdayScreenState extends State<OnboardingBirthdayScreen> {
  // Picker bounds — computed once in initState so they stay stable.
  late final DateTime _minDate;
  late final DateTime _maxDate;
  late final DateTime _initialDate;

  // Tracks what the picker is currently showing.
  late DateTime _selectedDate;

  // True once the user has scrolled the picker at least one tick.
  bool _hasPicked = false;

  bool _isSaving = false;
  String? _errorMessage;

  // ─── Init ───────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    final now = DateTime.now();

    _minDate = DateTime(now.year - 100, 1, 1);

    // Maximum date: exactly [minAge] years ago today.
    // Clamped so it's always a real calendar date (e.g., Feb 28 on non-leap years).
    final maxYear = now.year - AppConstants.minAge;
    final maxDays = DateUtils.getDaysInMonth(maxYear, now.month);
    final clampedDay = now.day > maxDays ? maxDays : now.day;
    _maxDate = DateTime(maxYear, now.month, clampedDay);

    // Seed the picker at 25 years ago — a neutral, clearly valid default.
    final initYear = now.year - 25;
    final initDays = DateUtils.getDaysInMonth(initYear, now.month);
    final initDay = now.day > initDays ? initDays : now.day;
    _initialDate = DateTime(initYear, now.month, initDay);
    _selectedDate = _initialDate;
  }

  // ─── Helpers ────────────────────────────────────────────────────────────────

  /// Calculates completed years between [birthday] and today.
  /// Handles the edge case where today IS the birthday (age counts as complete).
  int _computeAge(DateTime birthday) {
    final today = DateTime.now();
    int age = today.year - birthday.year;
    if (today.month < birthday.month ||
        (today.month == birthday.month && today.day < birthday.day)) {
      age--;
    }
    return age;
  }

  // ─── Save + advance ─────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_hasPicked || _isSaving) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final birthday = _selectedDate;
    final age = _computeAge(birthday);
    final uid = FirebaseAuth.instance.currentUser?.uid;

    // ── 1. Firestore ──────────────────────────────────────────────────────────
    if (uid != null) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .set(
              {'birthday': Timestamp.fromDate(birthday)},
              SetOptions(merge: true),
            );
        // ignore: avoid_print
        print('[Onboarding/Birthday] ✅ Firestore users/$uid.birthday=$birthday');
      } on FirebaseException catch (e) {
        // ignore: avoid_print
        print('[Onboarding/Birthday] ❌ Firestore ${e.code}: ${e.message}');
        if (!mounted) return;
        setState(() {
          _isSaving = false;
          _errorMessage = "Couldn't save. Check your connection and try again.";
        });
        return;
      } catch (e) {
        // ignore: avoid_print
        print('[Onboarding/Birthday] ❌ Unexpected: $e');
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
        firstName: p.firstName,
        age: age, // derived from birthday — the only thing changing here
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
    // ignore: avoid_print
    print('[Onboarding/Birthday] ✅ age=$age → advancing');
    // TODO: replace with AppRoutes.onboardingGender once that screen is built.
    context.go(AppRoutes.profile);
  }

  // ─── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final age = _computeAge(_selectedDate);

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

              // Logo
              const Center(child: IcebreakerLogo(size: 56, showGlow: false)),
              const SizedBox(height: 32),

              // Question
              Text(
                "When's your birthday?",
                style: AppTextStyles.h2,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),

              // Helper
              Text(
                'You need to be ${AppConstants.minAge} or older to use Icebreaker.',
                style: AppTextStyles.bodyS,
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 36),

              // ── Date picker ───────────────────────────────────────────────
              _DatePickerCard(
                initialDate: _initialDate,
                minDate: _minDate,
                maxDate: _maxDate,
                onChanged: (date) {
                  setState(() {
                    _selectedDate = date;
                    _hasPicked = true;
                  });
                },
              ),

              const SizedBox(height: 16),

              // Age confirmation — fades in after user picks
              AnimatedOpacity(
                opacity: _hasPicked ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                child: Text(
                  'Age $age',
                  style: AppTextStyles.h3.copyWith(color: AppColors.brandPink),
                  textAlign: TextAlign.center,
                ),
              ),

              // Error message
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                child: _errorMessage != null
                    ? Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
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
                                textAlign: TextAlign.center,
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
                onTap: (_hasPicked && !_isSaving) ? _save : null,
                child: AnimatedOpacity(
                  opacity: (_hasPicked && !_isSaving) ? 1.0 : 0.38,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    height: 56,
                    decoration: BoxDecoration(
                      gradient: AppColors.brandGradient,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: _hasPicked
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
// _DatePickerCard
// ─────────────────────────────────────────────────────────────────────────────

/// Styled container wrapping an inline [CupertinoDatePicker].
///
/// Dark surface card with a pink top-border accent strip.
/// The picker is bounded so the user cannot select an underage date.
class _DatePickerCard extends StatelessWidget {
  const _DatePickerCard({
    required this.initialDate,
    required this.minDate,
    required this.maxDate,
    required this.onChanged,
  });

  final DateTime initialDate;
  final DateTime minDate;
  final DateTime maxDate;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 220,
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border(
          top: BorderSide(
            color: AppColors.brandPink.withValues(alpha: 0.5),
            width: 1.5,
          ),
        ),
      ),
      // CupertinoTheme applies the dark palette and font to the picker wheel.
      child: CupertinoTheme(
        data: CupertinoThemeData(
          brightness: Brightness.dark,
          textTheme: CupertinoTextThemeData(
            dateTimePickerTextStyle: AppTextStyles.body.copyWith(
              fontSize: 20,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        child: CupertinoDatePicker(
          mode: CupertinoDatePickerMode.date,
          initialDateTime: initialDate,
          minimumDate: minDate,
          maximumDate: maxDate,
          // Show years within a sensible window in the wheel
          minimumYear: minDate.year,
          maximumYear: maxDate.year,
          onDateTimeChanged: onChanged,
        ),
      ),
    );
  }
}
