import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/shell/main_shell.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/home/screens/live_verification_screen.dart';
import '../../features/nearby/screens/nearby_screen.dart';
import '../../features/nearby/screens/send_icebreaker_screen.dart';
import '../../features/messages/screens/messages_screen.dart';
import '../../features/meetup/screens/icebreaker_received_screen.dart';
import '../../features/meetup/screens/matched_screen.dart';
import '../../features/meetup/screens/color_match_screen.dart';
import '../../features/meetup/screens/post_meet_screen.dart';
import '../../features/meetup/screens/match_confirmed_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/profile/screens/edit_profile_screen.dart';
import '../../features/profile/screens/gallery_screen.dart';
import '../../features/profile/screens/profile_checklist_screen.dart';
import '../../features/shop/screens/shop_screen.dart';
import '../../features/auth/screens/sign_in_screen.dart';
import '../../features/auth/screens/sign_up_screen.dart';
import '../../features/auth/screens/verify_phone_screen.dart';
import '../../features/onboarding/screens/onboarding_birthday_screen.dart';
import '../../features/onboarding/screens/onboarding_gender_screen.dart';
import '../../features/onboarding/screens/onboarding_name_screen.dart';
import '../../features/onboarding/screens/welcome_screen.dart';
import '../../features/dev/screens/design_preview_screen.dart';
import '../constants/app_constants.dart';

/// Icebreaker app router using go_router.
///
/// Navigation architecture:
///   / → MainShell (4-tab bottom nav)
///     /home
///     /nearby
///     /messages
///     /profile
///   Pushed on top of shell (full-screen):
///     /nearby/send-icebreaker
///     /icebreaker-received
///     /meetup/matched
///     /meetup/color-match
///     /meetup/post-meet
///     /meetup/confirmed
// Routes that unauthenticated users may visit, AND that signed-in users who
// are still setting up their profile may also visit without being bounced home.
const _authRoutes = {
  AppRoutes.splash,            // '/' — welcome screen
  AppRoutes.signIn,
  AppRoutes.signUp,
  AppRoutes.verifyPhone,
  AppRoutes.onboardingName,
  AppRoutes.onboardingBirthday,
  AppRoutes.onboardingGender,
};

final GoRouter appRouter = GoRouter(
  initialLocation: AppRoutes.splash,
  debugLogDiagnostics: false,
  redirect: (context, state) {
    final user = FirebaseAuth.instance.currentUser;
    final loc = state.matchedLocation;
    final isOnAuthRoute = _authRoutes.contains(loc);

    // Signed-in user on the welcome screen or pure-auth screens → send to profile.
    // Onboarding screens are intentionally reachable by signed-in users who
    // haven't completed their profile yet.
    const signInOnlyRoutes = {AppRoutes.splash, AppRoutes.signIn, AppRoutes.signUp};
    if (user != null && signInOnlyRoutes.contains(loc)) return AppRoutes.profile;

    // Unauthenticated user on a protected screen → send to sign-in.
    if (user == null && !isOnAuthRoute) return AppRoutes.signIn;

    return null; // no redirect needed
  },
  routes: [
    // ── Main shell with persistent bottom nav ──────────────────────────────
    ShellRoute(
      builder: (context, state, child) => MainShell(child: child),
      routes: [
        GoRoute(
          path: AppRoutes.home,
          pageBuilder: (context, state) => const NoTransitionPage(
            child: HomeScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutes.nearby,
          pageBuilder: (context, state) => const NoTransitionPage(
            child: NearbyScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutes.messages,
          pageBuilder: (context, state) => const NoTransitionPage(
            child: MessagesScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutes.profile,
          pageBuilder: (context, state) => const NoTransitionPage(
            child: ProfileScreen(),
          ),
        ),
      ],
    ),

    // ── Send Icebreaker (pushed over nearby) ──────────────────────────────
    GoRoute(
      path: AppRoutes.sendIcebreaker,
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>;
        return SendIcebreakerScreen(
          recipientId: extra['recipientId'] as String,
          recipientFirstName: extra['firstName'] as String,
          recipientAge: extra['age'] as int,
          recipientPhotoUrl: extra['photoUrl'] as String,
          recipientBio: extra['bio'] as String,
        );
      },
    ),

    // ── Icebreaker received ────────────────────────────────────────────────
    GoRoute(
      path: AppRoutes.icebreakerReceived,
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>;
        return IcebreakerReceivedScreen(
          icebreakerId: extra['icebreakerId'] as String,
          senderFirstName: extra['senderFirstName'] as String,
          senderAge: extra['senderAge'] as int,
          senderPhotoUrl: extra['senderPhotoUrl'] as String,
          myPhotoUrl: extra['myPhotoUrl'] as String,
          myFirstName: extra['myFirstName'] as String,
          message: extra['message'] as String,
          secondsRemaining: extra['secondsRemaining'] as int,
        );
      },
    ),

    // ── Meetup: Finding ───────────────────────────────────────────────────
    GoRoute(
      path: AppRoutes.matched,
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>;
        return MatchedScreen(
          meetupId: extra['meetupId'] as String,
          matchColor: extra['matchColor'] as Color,
          otherFirstName: extra['otherFirstName'] as String,
          otherPhotoUrl: extra['otherPhotoUrl'] as String,
          myFirstName: extra['myFirstName'] as String,
          myPhotoUrl: extra['myPhotoUrl'] as String,
          findSecondsRemaining: extra['findSecondsRemaining'] as int,
        );
      },
    ),

    // ── Meetup: In Conversation ───────────────────────────────────────────
    GoRoute(
      path: AppRoutes.colorMatch,
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>;
        return ColorMatchScreen(
          meetupId: extra['meetupId'] as String,
          matchColor: extra['matchColor'] as Color,
          otherFirstName: extra['otherFirstName'] as String,
          otherPhotoUrl: extra['otherPhotoUrl'] as String,
          myFirstName: extra['myFirstName'] as String,
          myPhotoUrl: extra['myPhotoUrl'] as String,
          conversationSecondsRemaining:
              extra['conversationSecondsRemaining'] as int,
        );
      },
    ),

    // ── Meetup: Post Meet ─────────────────────────────────────────────────
    GoRoute(
      path: AppRoutes.postMeet,
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>;
        return PostMeetScreen(
          meetupId: extra['meetupId'] as String,
          matchColor: extra['matchColor'] as Color,
          otherFirstName: extra['otherFirstName'] as String,
          otherPhotoUrl: extra['otherPhotoUrl'] as String,
        );
      },
    ),

    // ── Welcome (cold launch) ─────────────────────────────────────────────
    GoRoute(
      path: AppRoutes.splash,
      builder: (context, state) => const WelcomeScreen(),
    ),

    // ── Auth ──────────────────────────────────────────────────────────────
    GoRoute(
      path: AppRoutes.signIn,
      builder: (context, state) => const SignInScreen(),
    ),

    GoRoute(
      path: AppRoutes.signUp,
      builder: (context, state) => const SignUpScreen(),
    ),

    GoRoute(
      path: AppRoutes.verifyPhone,
      builder: (context, state) => const VerifyPhoneScreen(),
    ),

    GoRoute(
      path: AppRoutes.onboardingName,
      builder: (context, state) => const OnboardingNameScreen(),
    ),

    GoRoute(
      path: AppRoutes.onboardingBirthday,
      builder: (context, state) => const OnboardingBirthdayScreen(),
    ),

    GoRoute(
      path: AppRoutes.onboardingGender,
      builder: (context, state) => const OnboardingGenderScreen(),
    ),

    // ── Design preview (dev only) ─────────────────────────────────────────
    GoRoute(
      path: '/preview',
      builder: (context, state) => const DesignPreviewScreen(),
    ),

    // ── Meetup: Chat Unlocked ─────────────────────────────────────────────
    GoRoute(
      path: AppRoutes.matchConfirmed,
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>;
        return MatchConfirmedScreen(
          conversationId: extra['conversationId'] as String,
          otherFirstName: extra['otherFirstName'] as String,
          otherPhotoUrl: extra['otherPhotoUrl'] as String,
          matchColor: extra['matchColor'] as Color,
        );
      },
    ),

    // ── Sub-screens (pushed over shell; no persistent bottom nav) ─────────

    GoRoute(
      path: AppRoutes.shop,
      builder: (context, state) => const ShopScreen(),
    ),

    GoRoute(
      path: AppRoutes.liveVerify,
      builder: (context, state) {
        final isRedo = state.extra as bool? ?? false;
        return LiveVerificationScreen(isRedo: isRedo);
      },
    ),

    GoRoute(
      path: AppRoutes.editProfile,
      builder: (context, state) {
        final initialSection = state.extra as String?;
        return EditProfileScreen(initialSection: initialSection);
      },
    ),

    GoRoute(
      path: AppRoutes.gallery,
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        final scrollToVideo = extra?['scrollToVideo'] as bool? ?? false;
        return GalleryScreen(scrollToVideo: scrollToVideo);
      },
    ),

    GoRoute(
      path: AppRoutes.profileChecklist,
      builder: (context, state) => const ProfileChecklistScreen(),
    ),
  ],
);
