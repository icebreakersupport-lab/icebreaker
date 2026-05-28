import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/state/live_session.dart';

/// Shared post-authentication router for every entry point that lands the
/// user in an authenticated Firebase session — email/password sign-in,
/// email/password sign-up, and Sign in with Apple.
///
/// Resolves where the user should go after auth succeeds:
///   - Firestore read fails → returns the error message; caller shows it.
///   - users/{uid} missing  → creates a default doc, routes to onboarding.
///   - profileComplete=true → routes to home.
///   - profileComplete=false → routes to whichever onboarding step the user
///                             dropped off at (first missing required field).
///
/// Returns null on success, or a user-visible error string on failure
/// (only the Firestore read failure case — every other branch navigates
/// successfully or treats the failure as non-fatal).
Future<String?> routeAfterAuth(BuildContext context, User user) async {
  DocumentSnapshot<Map<String, dynamic>> doc;
  try {
    doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
  } on FirebaseException {
    return 'Could not load your profile. Please try again.';
  } catch (_) {
    return 'Something went wrong. Please try again.';
  }

  if (!doc.exists) {
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
    } on FirebaseException {
      // Non-fatal: proceed to onboarding so the user can still fill in
      // their profile. The doc will be written when onboarding completes.
    }
    if (!context.mounted) return null;
    context.go(AppRoutes.onboardingName);
    return null;
  }

  final data = doc.data() ?? {};
  final profileComplete = data['profileComplete'] as bool? ?? false;

  if (!context.mounted) return null;
  // Fire-and-forget — navigation proceeds; the counter updates reactively.
  LiveSessionScope.of(context).hydrateCredits(user.uid);

  if (profileComplete) {
    context.go(AppRoutes.home);
  } else {
    context.go(_resumeOnboardingRoute(data));
  }
  return null;
}

/// Returns the onboarding step where the user dropped off, by walking
/// the required fields in the order they're collected.
String _resumeOnboardingRoute(Map<String, dynamic> data) {
  if (data['firstName'] == null) return AppRoutes.onboardingName;
  if (data['birthday'] == null) return AppRoutes.onboardingBirthday;
  if (data['gender'] == null) return AppRoutes.onboardingGender;
  if (data['openTo'] == null) return AppRoutes.onboardingOpenTo;
  if (data['hometown'] == null) return AppRoutes.onboardingLocation;
  // Has all text data but didn't finish — resume at photo/slideshow.
  return AppRoutes.onboardingPhoto;
}
