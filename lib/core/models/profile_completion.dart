// Profile completion scoring system.
//
// Weights (total = 100 pts):
//   Basics       30 pts  — name/age, location, email, preferences
//   Media        25 pts  — first photo, 3+ photos, video
//   Personality  25 pts  — bio, interests, hobbies
//   Verification 20 pts  — phone, live selfie
//
// Adding a new item: give it a unique [id], a [points] value, and a
// [category]. The percentage recalculates automatically from the sum.

import '../state/demo_profile.dart';

// ── Category ──────────────────────────────────────────────────────────────────

enum ProfileCompletionCategory { basics, media, personality, verification }

extension ProfileCompletionCategoryX on ProfileCompletionCategory {
  String get label => switch (this) {
        ProfileCompletionCategory.basics => 'Account Basics',
        ProfileCompletionCategory.media => 'Photos & Media',
        ProfileCompletionCategory.personality => 'Personality',
        ProfileCompletionCategory.verification => 'Verification',
      };
}

// ── Item ──────────────────────────────────────────────────────────────────────

class ProfileCompletionItem {
  const ProfileCompletionItem({
    required this.id,
    required this.title,
    required this.description,
    required this.points,
    required this.category,
    required this.isComplete,
    this.hint = '',
  });

  /// Unique stable identifier (used for future Firestore mapping).
  final String id;

  /// Short display label — e.g. "Profile Photo".
  final String title;

  /// One-line explanation shown in the checklist.
  final String description;

  /// Points this item contributes toward 100.
  final int points;

  final ProfileCompletionCategory category;
  final bool isComplete;

  /// Actionable tip shown for incomplete items.
  final String hint;
}

// ── Score ─────────────────────────────────────────────────────────────────────

class ProfileCompletionScore {
  const ProfileCompletionScore(this.items);

  final List<ProfileCompletionItem> items;

  int get totalPoints => items.fold(0, (s, i) => s + i.points);

  int get earnedPoints =>
      items.where((i) => i.isComplete).fold(0, (s, i) => s + i.points);

  /// 0–100, rounded. Never exceeds 100.
  int get percentage =>
      totalPoints == 0 ? 0 : (earnedPoints / totalPoints * 100).round().clamp(0, 100);

  List<ProfileCompletionItem> get completed =>
      items.where((i) => i.isComplete).toList();

  List<ProfileCompletionItem> get incomplete =>
      items.where((i) => !i.isComplete).toList();

  /// Items grouped by category, preserving definition order within each group.
  Map<ProfileCompletionCategory, List<ProfileCompletionItem>> get byCategory {
    final map = <ProfileCompletionCategory, List<ProfileCompletionItem>>{};
    for (final item in items) {
      map.putIfAbsent(item.category, () => []).add(item);
    }
    return map;
  }

  // ── Live factory ───────────────────────────────────────────────────────────

  /// Builds the completion score from the live [DemoProfile] state.
  ///
  /// All [isComplete] flags are derived from real profile data — no
  /// hardcoded booleans. The score therefore stays in sync with any
  /// change made in EditProfileScreen or GalleryScreen without extra wiring.
  ///
  /// Completion thresholds:
  ///   preferences  — lookingFor is non-empty (has a default, so always true)
  ///   photo_first  — photoCount >= 1
  ///   photo_three  — photoCount >= 3
  ///   video        — video is non-null
  ///   bio          — bio.trim() is non-empty
  ///   interests    — interests.length >= 3
  ///   hobbies      — hobbies.length >= 2
  ///   live_selfie  — hasLiveSelfie param (from LiveSession.selfieFilePath != null)
  ///
  /// Account basics (name_age, location, email, phone) are always complete
  /// in the demo — they represent pre-filled sign-up data.
  factory ProfileCompletionScore.fromProfile(
    DemoProfile profile, {
    required bool hasLiveSelfie,
  }) {
    return ProfileCompletionScore([
      // ── Account Basics — 30 pts ─────────────────────────────────────────
      const ProfileCompletionItem(
        id: 'name_age',
        title: 'Name & Age',
        description: 'First name and age are set on your account',
        points: 10,
        category: ProfileCompletionCategory.basics,
        isComplete: true,
      ),
      const ProfileCompletionItem(
        id: 'location',
        title: 'Location & Discovery',
        description: 'Location access enabled so nearby users can find you',
        points: 8,
        category: ProfileCompletionCategory.basics,
        isComplete: true,
        hint: 'Enable location permissions in System Settings',
      ),
      const ProfileCompletionItem(
        id: 'email',
        title: 'Email Verified',
        description: 'Your email address has been confirmed',
        points: 7,
        category: ProfileCompletionCategory.basics,
        isComplete: true,
      ),
      ProfileCompletionItem(
        id: 'preferences',
        title: 'Dating Preferences',
        description: 'Who you\'re looking to meet and your age range',
        points: 5,
        category: ProfileCompletionCategory.basics,
        isComplete: profile.lookingFor.isNotEmpty,
        hint: 'Set your preferences in Edit Profile',
      ),

      // ── Photos & Media — 25 pts ─────────────────────────────────────────
      ProfileCompletionItem(
        id: 'photo_first',
        title: 'Profile Photo',
        description: 'Upload at least one photo to your gallery',
        points: 10,
        category: ProfileCompletionCategory.media,
        isComplete: profile.photoCount >= 1,
        hint: 'Tap My Gallery to upload your first photo',
      ),
      ProfileCompletionItem(
        id: 'photo_three',
        title: '3 or More Photos',
        description: 'Profiles with 3+ photos get 4× more connections',
        points: 8,
        category: ProfileCompletionCategory.media,
        isComplete: profile.photoCount >= 3,
        hint: 'Add more photos in My Gallery',
      ),
      ProfileCompletionItem(
        id: 'video',
        title: 'Intro Video',
        description: 'A short intro video makes your profile stand out',
        points: 7,
        category: ProfileCompletionCategory.media,
        isComplete: profile.video != null,
        hint: 'Upload a short video in My Gallery',
      ),

      // ── Personality — 25 pts ────────────────────────────────────────────
      ProfileCompletionItem(
        id: 'bio',
        title: 'Bio Written',
        description: 'Tell nearby people who you are in a few sentences',
        points: 10,
        category: ProfileCompletionCategory.personality,
        isComplete: profile.bio.trim().isNotEmpty,
        hint: 'Write your bio in Edit Profile',
      ),
      ProfileCompletionItem(
        id: 'interests',
        title: 'Interests Added',
        description: 'Add at least 3 interests (music, sport, travel…)',
        points: 8,
        category: ProfileCompletionCategory.personality,
        isComplete: profile.interests.length >= 3,
        hint: 'Add interests in Edit Profile',
      ),
      ProfileCompletionItem(
        id: 'hobbies',
        title: 'Hobbies Added',
        description: 'Add at least 2 hobbies to spark conversations',
        points: 7,
        category: ProfileCompletionCategory.personality,
        isComplete: profile.hobbies.length >= 2,
        hint: 'Add hobbies in Edit Profile',
      ),

      // ── Verification — 20 pts ───────────────────────────────────────────
      const ProfileCompletionItem(
        id: 'phone',
        title: 'Phone Verified',
        description: 'Your phone number is confirmed',
        points: 5,
        category: ProfileCompletionCategory.verification,
        isComplete: true,
      ),
      ProfileCompletionItem(
        id: 'live_selfie',
        title: 'Live Selfie Verified',
        description:
            'Real-time selfie verification builds trust with nearby users',
        points: 15,
        category: ProfileCompletionCategory.verification,
        isComplete: hasLiveSelfie,
        hint: 'Tap GO LIVE on the Home tab to complete verification',
      ),
    ]);
  }
}

// ── Top-tier profile field reference ─────────────────────────────────────────
//
// Complete set of fields required for a top-tier Icebreaker profile:
//
// Identity
//   • firstName (required)
//   • age / dateOfBirth (required)
//   • gender (required)
//   • sexualOrientation (required)
//   • location (required — device GPS)
//
// Media
//   • photos[]         — 1 required, up to 6 recommended
//   • introVideoUrl    — optional, boosts visibility
//
// Personality
//   • bio              — up to 150 chars
//   • interests[]      — tags (music, travel, sport…); min 3 recommended
//   • hobbies[]        — tags (cooking, hiking…); min 2 recommended
//
// Preferences
//   • lookingFor       — e.g. casual, serious, friendship
//   • preferredGenders — who they want to meet
//   • ageRangeMin / ageRangeMax
//
// Optional extra details
//   • height
//   • education        — e.g. Bachelor's, Master's
//   • occupation / jobTitle
//   • relationshipStatus
//   • languages[]
//
// Account / Verification
//   • email            — verified
//   • phoneNumber      — verified (E.164 format)
//   • liveSelfieUrl    — captured during GO LIVE flow
//   • isVerified       — server-side flag set after selfie review
//   • subscriptionTier — free | plus | gold
//   • createdAt / lastActiveAt
