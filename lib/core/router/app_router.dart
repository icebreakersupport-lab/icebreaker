import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/messages/screens/icebreaker_waiting_screen.dart';
import '../../features/shell/main_shell.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/home/screens/live_verification_screen.dart';
import '../../features/nearby/screens/nearby_screen.dart';
import '../../features/nearby/screens/send_icebreaker_screen.dart';
import '../../features/messages/screens/messages_screen.dart';
import '../../features/messages/screens/chat_thread_screen.dart';
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
import '../../features/onboarding/screens/onboarding_open_to_screen.dart';
import '../../features/onboarding/screens/onboarding_location_screen.dart';
import '../../features/onboarding/screens/onboarding_orientation_screen.dart';
import '../../features/onboarding/screens/onboarding_photo_screen.dart';
import '../../features/onboarding/screens/onboarding_slideshow_screen.dart';
import '../../features/onboarding/screens/welcome_screen.dart';
import '../../features/startup/screens/app_loading_screen.dart';
import '../../features/dev/screens/design_preview_screen.dart';
import '../../features/settings/screens/blocked_users_screen.dart';
import '../../features/settings/screens/reporting_and_blocking_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../constants/app_constants.dart';
import '../state/flow_coordinator.dart';

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
  AppRoutes.splash, // '/' — branded loading screen, resolves destination itself
  AppRoutes.welcome,
  AppRoutes.signIn,
  AppRoutes.signUp,
  AppRoutes.verifyPhone,
  AppRoutes.onboardingName,
  AppRoutes.onboardingBirthday,
  AppRoutes.onboardingGender,
  AppRoutes.onboardingOpenTo,
  AppRoutes.onboardingOrientation,
  AppRoutes.onboardingLocation,
  AppRoutes.onboardingPhoto,
  AppRoutes.onboardingSlideshow,
};

// Explicit navigator split:
// - root navigator owns all full-screen routes that must cover the shell
// - shell navigator owns the 4 persistent-tab destinations only
//
// Without this, routes like /icebreaker-waiting/:id can be
// vulnerable to being presented within the shell stack, which leaves the
// bottom nav visible under screens that are meant to hard-lock the user.
final _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
final _shellNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'shell');

/// Builds the app router with a caller-supplied initial location.
///
/// Constructed once per [IcebreakerApp] instance.  Lifting initialLocation
/// out of a top-level `final` lets [BootstrapRoot] resolve the destination
/// (welcome / home / onboarding) up front and feed it directly into the
/// router, so the user never sees the [AppLoadingScreen] fallback at `/`
/// on a normal cold launch — the router opens at the resolved destination.
///
/// [flowCoordinator] drives the icebreaker/meetup flow lock.  Wired via
/// `refreshListenable` + the redirect closure: when [FlowCoordinator.targetRoute]
/// is non-null, every navigation is forced to that path until the underlying
/// state changes.  Passing it in (rather than using a top-level singleton)
/// keeps the router pure and testable.
GoRouter buildAppRouter({
  String initialLocation = AppRoutes.splash,
  required FlowCoordinator flowCoordinator,
  }) {
  return GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: initialLocation,
  debugLogDiagnostics: false,
  refreshListenable: flowCoordinator,
  redirect: (context, state) {
    final user = FirebaseAuth.instance.currentUser;
    final loc = state.matchedLocation;
    final isOnAuthRoute = _authRoutes.contains(loc);

    // Unauthenticated user on a protected screen → send to sign-in.
    // Done before the flow-coordinator check because a signed-out user
    // shouldn't have any FlowCoordinator state anyway, but if there's a
    // race between sign-out and the coordinator's auth-state listener we
    // still want auth gating to win.
    if (user == null && !isOnAuthRoute) return AppRoutes.signIn;

    // Flow-lock redirect.  When an outgoing icebreaker is pending OR the
    // user is in a finding-phase meetup, force them to the corresponding
    // screen.  The check sits before the welcome→home bounce so a forced
    // wait/match destination wins on cold start too.
    final flowTarget = flowCoordinator.targetRoute;
    if (flowTarget != null && loc != flowTarget) {
      // The wait screen lives at /icebreaker-waiting/{id}; the
      // matched screen under /meetup/matched/{id}.  Both are leaf paths,
      // not prefixes — exact-match comparison is sufficient.
      return flowTarget;
    }
    // Flow-lock RELEASE.  The redirect closure is the only authority that
    // moves users between locked screens, so it's also responsible for
    // moving them OFF a locked screen once the lock clears.  Without this
    // branch, a user whose meetup terminated (matched / no_match / expired)
    // would be stuck on the now-stale finding / talking / decision screen
    // until they manually navigated.  All four locked routes are path-
    // parameterised, so we match by prefix; the trailing slash guards
    // against a hypothetical future route that shares the prefix (e.g.
    // `/meetup/matched-something`).
    if (flowTarget == null) {
      final isOnWait = loc.startsWith('${AppRoutes.icebreakerWaiting}/');
      final isOnMatched = loc.startsWith('${AppRoutes.matched}/');
      final isOnColorMatch = loc.startsWith('${AppRoutes.colorMatch}/');
      final isOnPostMeet = loc.startsWith('${AppRoutes.postMeet}/');
      // Sender wait release goes Home — declined/expired icebreakers leave
      // the sender with no in-flight match, and Home is the natural "what
      // do I want to do next" surface. An optimistic local coordinator lock
      // is seeded before the initial navigation to /icebreaker-waiting/{id},
      // so this branch only handles genuine stale/terminal wait routes now.
      if (isOnWait) {
        return AppRoutes.home;
      }
      // Find-timer (matched) release goes Home: a confirmed user-cancel or
      // a no-find timeout on the 5-minute meet-up timer is a clean exit
      // with no in-flight match, so Home is the natural "what next" surface
      // — same shape as the sender-wait release above.
      if (isOnMatched) {
        return AppRoutes.home;
      }
      // Color-match / post-meet releases land on Home so the user comes
      // back to the central "what now" surface still Live (the live session
      // isn't ended by the meetup flow).  On mutual we_got_this the
      // conversation already exists in Messages for them to discover at
      // their own pace.
      if (isOnColorMatch || isOnPostMeet) {
        return AppRoutes.home;
      }
    }

    // Signed-in user on the welcome screen or pure-auth screens → send to home.
    // Onboarding screens are intentionally reachable by signed-in users who
    // haven't completed their profile yet.
    //
    // AppRoutes.splash is intentionally NOT in this set — the loading screen
    // resolves its own destination (home / welcome / onboarding-name) based on
    // auth + profile state, so we let it render even for signed-in users.
    const signInOnlyRoutes = {
      AppRoutes.welcome,
      AppRoutes.signIn,
      AppRoutes.signUp,
    };
    if (user != null && signInOnlyRoutes.contains(loc)) return AppRoutes.home;

    return null; // no redirect needed
  },
  routes: [
    // ── Main shell with persistent bottom nav ──────────────────────────────
    ShellRoute(
      navigatorKey: _shellNavigatorKey,
      builder: (context, state, child) => MainShell(child: child),
      routes: [
        GoRoute(
          path: AppRoutes.home,
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: HomeScreen()),
        ),
        GoRoute(
          path: AppRoutes.nearby,
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: NearbyScreen()),
        ),
        GoRoute(
          path: AppRoutes.messages,
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: MessagesScreen()),
        ),
        GoRoute(
          path: AppRoutes.profile,
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: ProfileScreen()),
        ),
      ],
    ),

    // ── Send Icebreaker (pushed over nearby) ──────────────────────────────
    GoRoute(
      path: AppRoutes.sendIcebreaker,
      parentNavigatorKey: _rootNavigatorKey,
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
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>;
        return IcebreakerReceivedScreen(
          icebreakerId: extra['icebreakerId'] as String,
          senderFirstName: extra['senderFirstName'] as String,
          senderAge: extra['senderAge'] as int,
          senderPhotoUrl: extra['senderPhotoUrl'] as String,
          myPhotoUrl: (extra['myPhotoUrl'] as String?) ?? '',
          myFirstName: (extra['myFirstName'] as String?) ?? '',
          message: extra['message'] as String,
          secondsRemaining: extra['secondsRemaining'] as int,
        );
      },
    ),

    // ── Meetup: Finding ───────────────────────────────────────────────────
    // Path-parameterised on meetupId so the FlowCoordinator redirect can
    // route into this screen with nothing more than the id from
    // users/{uid}.currentMeetupId.  The screen self-derives all rendering
    // data from the meetup doc via a Firestore stream — no extras.
    GoRoute(
      path: '${AppRoutes.matched}/:meetupId',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final meetupId = state.pathParameters['meetupId']!;
        return MatchedScreen(meetupId: meetupId);
      },
    ),

    // ── Sender wait screen (forced lock while icebreaker is pending) ──────
    GoRoute(
      path: '${AppRoutes.icebreakerWaiting}/:icebreakerId',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final icebreakerId = state.pathParameters['icebreakerId']!;
        return IcebreakerWaitingScreen(icebreakerId: icebreakerId);
      },
    ),

    // ── Meetup: In Conversation (talking phase) ───────────────────────────
    // Path-parameterised so the FlowCoordinator redirect can route into this
    // screen using only `users/{uid}.currentMeetupId`.  The screen self-
    // derives all rendering data from the meetup doc via a Firestore stream.
    GoRoute(
      path: '${AppRoutes.colorMatch}/:meetupId',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final meetupId = state.pathParameters['meetupId']!;
        return ColorMatchScreen(meetupId: meetupId);
      },
    ),

    // ── Meetup: Post Meet (decision phase) ────────────────────────────────
    GoRoute(
      path: '${AppRoutes.postMeet}/:meetupId',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final meetupId = state.pathParameters['meetupId']!;
        return PostMeetScreen(meetupId: meetupId);
      },
    ),

    // ── Splash: branded loading screen (cold launch) ──────────────────────
    // Mounted at '/'. Resolves auth + profile state and forwards to
    // welcome / home / onboarding. Replaces the previous WelcomeScreen-at-root
    // behavior so cold launches show the heartbeat brand mark instead of the
    // full welcome layout flashing in.
    GoRoute(
      path: AppRoutes.splash,
      builder: (context, state) => const AppLoadingScreen(),
    ),

    // ── Welcome (signed-out marketing entry) ──────────────────────────────
    GoRoute(
      path: AppRoutes.welcome,
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

    GoRoute(
      path: AppRoutes.onboardingOpenTo,
      builder: (context, state) => const OnboardingOpenToScreen(),
    ),

    GoRoute(
      path: AppRoutes.onboardingOrientation,
      builder: (context, state) => const OnboardingOrientationScreen(),
    ),

    GoRoute(
      path: AppRoutes.onboardingLocation,
      builder: (context, state) => const OnboardingLocationScreen(),
    ),

    GoRoute(
      path: AppRoutes.onboardingPhoto,
      builder: (context, state) => const OnboardingPhotoScreen(),
    ),

    GoRoute(
      path: AppRoutes.onboardingSlideshow,
      builder: (context, state) => const OnboardingSlideshowScreen(),
    ),

    // ── Chat thread ───────────────────────────────────────────────────────
    // Used only for unlocked conversations (Chats section).
    // Locked and history modes use Navigator.push directly.
    GoRoute(
      path: AppRoutes.chat,
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>;
        return ChatThreadScreen(
          icebreakerId: '',
          conversationId: extra['conversationId'] as String?,
          otherFirstName: (extra['otherFirstName'] as String?) ?? '',
          otherPhotoUrl: (extra['otherPhotoUrl'] as String?) ?? '',
          message: '',
          status: 'unlocked',
        );
      },
    ),

    // ── Design preview (dev only) ─────────────────────────────────────────
    // Registered only in debug builds so the route cannot be reached in
    // production via deep-link or typo'd navigation.
    if (kDebugMode)
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

    GoRoute(
      path: AppRoutes.settings,
      builder: (context, state) => const SettingsScreen(),
    ),

    GoRoute(
      path: AppRoutes.blockedUsers,
      builder: (context, state) => const BlockedUsersScreen(),
    ),

    GoRoute(
      path: AppRoutes.reportingAndBlocking,
      builder: (context, state) => const ReportingAndBlockingScreen(),
    ),
  ],
  );
}
