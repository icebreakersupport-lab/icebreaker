import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/icebreaker_logo.dart';

/// Profile Setup — Step 1: Enter first name.
///
/// This is the first screen after account creation. Additional steps
/// (gender, photos, bio) follow from here.
class OnboardingNameScreen extends StatefulWidget {
  const OnboardingNameScreen({super.key});

  @override
  State<OnboardingNameScreen> createState() => _OnboardingNameScreenState();
}

class _OnboardingNameScreenState extends State<OnboardingNameScreen> {
  final _nameController = TextEditingController();
  final _nameFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _nameController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  bool get _isValid =>
      _nameController.text.trim().length >= 2 &&
      _nameController.text.trim().length <= AppConstants.firstNameMaxLength;

  void _next() {
    if (!_isValid) return;
    // ignore: avoid_print
    print('[Onboarding/Name] ▶ name="${_nameController.text.trim()}" → navigating to ${AppRoutes.onboardingGender}');
    // TODO: persist name to Firestore / local state before advancing.
    context.go(AppRoutes.onboardingGender);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 52),

              const Center(child: IcebreakerLogo(size: 56, showGlow: false)),
              const SizedBox(height: 28),

              Text(
                'What\'s your first name?',
                style: AppTextStyles.h2,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'This is how you\'ll appear to others.',
                style: AppTextStyles.bodyS,
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 44),

              TextField(
                controller: _nameController,
                focusNode: _nameFocus,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                maxLength: AppConstants.firstNameMaxLength,
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
                    borderSide:
                        const BorderSide(color: AppColors.brandPink, width: 1.5),
                  ),
                  labelStyle: AppTextStyles.caption
                      .copyWith(color: AppColors.textSecondary),
                ),
                onSubmitted: (_) => _next(),
              ),

              const SizedBox(height: 32),

              GestureDetector(
                onTap: _isValid ? _next : null,
                child: AnimatedOpacity(
                  opacity: _isValid ? 1.0 : 0.38,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    height: 56,
                    decoration: BoxDecoration(
                      gradient: AppColors.brandGradient,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: _isValid
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
                    child: Text('Continue', style: AppTextStyles.buttonL),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
