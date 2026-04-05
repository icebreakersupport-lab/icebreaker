/// App-wide constants: enums, string keys, durations, limits.
/// Mirrors the values locked in the Revision 4 Final architecture spec.
abstract final class AppConstants {
  // ─── Session ──────────────────────────────────────────────────────────────

  /// Total live session duration in seconds.
  static const int sessionDurationSeconds = 3600;

  /// Session warning notification sent at this many seconds remaining.
  static const int sessionWarningSeconds = 600;

  /// Stale-location threshold: user becomes undiscoverable if no update.
  static const int locationStaleThresholdSeconds = 120;

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
  static const String splash = '/';
  static const String signIn = '/sign-in';
  static const String signUp = '/sign-up';
  static const String verifyPhone = '/verify-phone';
  static const String onboardingName = '/onboarding/name';
  static const String onboardingBirthday = '/onboarding/birthday';
  static const String onboardingGender = '/onboarding/gender';
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
