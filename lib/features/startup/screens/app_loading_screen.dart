import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/icebreaker_logo.dart';

/// Branded splash shown at `/` while the router is resolving the user's
/// signed-in / onboarded / live state into the real destination.  On a normal
/// cold launch the redirect runs synchronously and the user never actually
/// sees this — it's the fallback for the case where Firebase Auth or
/// Firestore is still warming up.
class AppLoadingScreen extends StatelessWidget {
  const AppLoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.bgBase,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IcebreakerLogo(size: 64),
              SizedBox(height: 28),
              SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppColors.brandPink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
