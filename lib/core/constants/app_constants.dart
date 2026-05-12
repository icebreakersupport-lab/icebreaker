/// App-wide constants: enums, string keys, durations, limits.
/// Mirrors the values locked in the Revision 4 Final architecture spec.
abstract final class AppConstants {
  // ─── Session ──────────────────────────────────────────────────────────────

  /// Total live session duration in seconds.
  static const int sessionDurationSeconds = 3600;

  /// Session warning notification sent at this many seconds remaining.
  static const int sessionWarningSeconds = 600;

  /// Discoverability grace for a live user's last known location.
  ///
  /// Mobile OSes can suspend timers and GPS reads when the app backgrounds,
  /// especially on iPhone.  Nearby therefore treats the last successful live
  /// position as pinned for the full live-session window instead of dropping
  /// the user after a couple of minutes with a false "offline" result.
  ///
  /// Once the session actually ends, the session doc is terminalized and the
  /// position fields are cleared, so the user still disappears immediately at
  /// the real session boundary.
  static const int locationStaleThresholdSeconds = sessionDurationSeconds;

  // ─── Icebreaker ───────────────────────────────────────────────────────────

  static const int icebreakerTtlSeconds = 300;
  static const int icebreakerWarningSeconds = 60;
  static const int icebreakerMessageMaxLength = 200;

  // ─── Meetup ───────────────────────────────────────────────────────────────

  static const int findTimerSeconds = 300;
  static const int conversationTimerSeconds = 600;

  // ─── Profile ──────────────────────────────────────────────────────────────

  static const int firstNameMaxLength = 30;
  static const int bioMaxLength = 150;
  static const int photosMin = 1;
  static const int photosMax = 9;
  static const int minAge = 18;

  // ─── Discovery ────────────────────────────────────────────────────────────

  static const double nearbyRadiusMeters = 30.0;
  static const int locationUpdateIntervalSeconds = 60;

  // ─── Credits ──────────────────────────────────────────────────────────────

  static const int freeGoLiveCreditsPerSignup = 1;
  static const int freeIcebreakerCreditsPerSignup = 3;
  static const int adWatchLimitPerDay = 2;
}

// ─── Route paths ──────────────────────────────────────────────────────────────

abstract final class AppRoutes {
  /// Branded loading screen ('/'). Shown on every cold launch; resolves to
  /// welcome / home / onboarding depending on auth + profile state.
  static const String splash = '/';
  static const String welcome = '/welcome';
  static const String signIn = '/sign-in';
  static const String signUp = '/sign-up';
  static const String verifyPhone = '/verify-phone';
  static const String onboardingName = '/onboarding/name';
  static const String onboardingBirthday = '/onboarding/birthday';
  static const String onboardingGender = '/onboarding/gender';
  static const String onboardingOpenTo = '/onboarding/open-to';
  static const String onboardingOrientation = '/onboarding/orientation';
  static const String onboardingLocation = '/onboarding/location';
  static const String onboardingPhoto = '/onboarding/photo';
  static const String onboardingSlideshow = '/onboarding/slideshow';
  static const String onboardingPhotos = '/onboarding/photos';
  static const String onboardingBio = '/onboarding/bio';

  // Main shell (bottom nav)
  static const String home = '/home';
  static const String nearby = '/nearby';
  static const String messages = '/messages';
  static const String profile = '/profile';

  // Nested routes
  static const String sendIcebreaker = '/nearby/send-icebreaker';
  static const String icebreakerReceived = '/icebreaker-received';
  /// Sender's forced wait screen — full route is `/icebreaker-waiting/:id`.
  /// Concatenate with `/{icebreakerId}` to push.  Owned by the FlowCoordinator
  /// redirect: any screen the sender tries to navigate to while their
  /// outgoing icebreaker is still 'sent' bounces back here.
  static const String icebreakerWaiting = '/icebreaker-waiting';
  /// Meetup finding screen — full route is `/meetup/matched/:meetupId`.
  /// Concatenate with `/{meetupId}` to push.  Owned by FlowCoordinator
  /// redirect: any participant with `currentMeetupId` set + status==finding
  /// is bounced back here.
  static const String matched = '/meetup/matched';
  static const String colorMatch = '/meetup/color-match';
  static const String postMeet = '/meetup/post-meet';
  static const String matchConfirmed = '/meetup/confirmed';
  static const String chat = '/messages/chat';

  // Sub-screens (pushed over shell; no bottom nav)
  static const String shop = '/home/shop';
  static const String liveVerify = '/home/verify';
  static const String editProfile = '/profile/edit';
  static const String gallery = '/profile/gallery';
  static const String profileChecklist = '/profile/checklist';
  static const String settings = '/profile/settings';
  static const String blockedUsers = '/profile/settings/blocked-users';
  static const String reportingAndBlocking =
      '/profile/settings/reporting-and-blocking';
}

// ─── Gender / Orientation enums ───────────────────────────────────────────────

enum Gender { male, female, nonBinary, other }

extension GenderLabel on Gender {
  String get label => switch (this) {
    Gender.male => 'Man',
    Gender.female => 'Woman',
    Gender.nonBinary => 'Non-binary',
    Gender.other => 'Other',
  };

  String get firestoreValue => switch (this) {
    Gender.male => 'male',
    Gender.female => 'female',
    Gender.nonBinary => 'non_binary',
    Gender.other => 'other',
  };
}

enum Orientation { straight, gay, lesbian, bisexual, pansexual, other }

extension OrientationLabel on Orientation {
  String get label => switch (this) {
    Orientation.straight => 'Straight',
    Orientation.gay => 'Gay',
    Orientation.lesbian => 'Lesbian',
    Orientation.bisexual => 'Bisexual',
    Orientation.pansexual => 'Pansexual',
    Orientation.other => 'Other',
  };
}

// ─── Subscription tiers ───────────────────────────────────────────────────────

enum SubscriptionTier { free, plus, gold }

extension SubscriptionLabel on SubscriptionTier {
  bool get isGold => this == SubscriptionTier.gold;
  bool get isPlus => this == SubscriptionTier.plus;
}

// ─── Shop feature flags ───────────────────────────────────────────────────────
//
// Subscriptions and rewarded ads are not shippable for v1 — the Shop UI has
// placeholder buttons (snackbar "coming soon") that App Store review flags
// under "buttons that don't do what they imply."  Flipping these flags to
// true re-enables the sections once the real billing / ads SDK is wired.
const bool kSubscriptionsEnabled = false;
const bool kRewardedAdsEnabled = false;
