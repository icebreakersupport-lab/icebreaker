import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Shared mutable demo profile state — the single source of truth for all
/// user-editable profile fields while no backend is wired.
///
/// Owned by [IcebreakerApp] via [DemoProfileScope] so every screen that
/// reads it rebuilds automatically when [notifyListeners] is called.
///
/// Mutate via the write methods (never set fields directly).
class DemoProfile extends ChangeNotifier {
  // ── Identity ────────────────────────────────────────────────────────────────
  String firstName = 'You';
  int age = 24;

  // ── Hometown ─────────────────────────────────────────────────────────────────
  String hometownCity = '';
  String hometownState = '';

  /// "City, State" — used on the profile page.
  String get hometownDisplay {
    final c = hometownCity.trim();
    final s = hometownState.trim();
    if (c.isEmpty && s.isEmpty) return '';
    if (c.isEmpty) return s;
    if (s.isEmpty) return c;
    return '$c, $s';
  }

  /// "City, ST" — used on nearby carousel cards.
  String get hometownShort {
    final c = hometownCity.trim();
    final s = hometownState.trim();
    if (c.isEmpty && s.isEmpty) return '';
    final code = abbreviateState(s);
    if (c.isEmpty) return code;
    if (s.isEmpty) return c;
    return '$c, $code';
  }

  // ── Bio / Chips ─────────────────────────────────────────────────────────────
  String bio = '';
  Set<String> interests = {'Music', 'Travel'};
  Set<String> hobbies = {'Cooking'};

  // ── Profile Details ──────────────────────────────────────────────────────────
  String occupation = 'Product Designer';
  String height = "5'10\"";

  // ── Dating Preferences ───────────────────────────────────────────────────────
  String lookingFor = 'Casual dating';
  String interestedIn = 'Women';
  RangeValues ageRange = const RangeValues(20, 35);

  // ── Media ────────────────────────────────────────────────────────────────────
  /// Six photo slots. null = empty slot. Slot 0 is always the main photo.
  final List<XFile?> photos = [null, null, null, null, null, null];

  /// Single optional intro video.
  XFile? video;

  // ── Derived helpers ──────────────────────────────────────────────────────────
  XFile? get mainPhoto => photos.firstWhere((p) => p != null, orElse: () => null);
  int get photoCount => photos.where((p) => p != null).length;

  // ── Write API ─────────────────────────────────────────────────────────────────

  /// Persist all text/chip/preference fields at once (called from Save in EditProfileScreen).
  void saveTextFields({
    required String firstName,
    required int age,
    required String bio,
    required String occupation,
    required String height,
    required String lookingFor,
    required String interestedIn,
    required RangeValues ageRange,
    required Set<String> interests,
    required Set<String> hobbies,
  }) {
    this.firstName = firstName;
    this.age = age;
    this.bio = bio;
    this.occupation = occupation;
    this.height = height;
    this.lookingFor = lookingFor;
    this.interestedIn = interestedIn;
    this.ageRange = ageRange;
    this.interests = Set.from(interests);
    this.hobbies = Set.from(hobbies);
    notifyListeners();
  }

  /// Update hometown city and state. Triggers a full rebuild.
  void setHometown(String city, String state) {
    hometownCity = city.trim();
    hometownState = state.trim();
    notifyListeners();
  }

  /// Set or clear a single photo slot. Rebuilds all listeners immediately.
  void setPhoto(int index, XFile? xFile) {
    photos[index] = xFile;
    notifyListeners();
  }

  /// Swap two photo slots (used for "Set as Main").
  void swapPhotos(int a, int b) {
    final tmp = photos[a];
    photos[a] = photos[b];
    photos[b] = tmp;
    notifyListeners();
  }

  /// Set or clear the intro video.
  void setVideo(XFile? xFile) {
    video = xFile;
    notifyListeners();
  }

  // ── State abbreviation helper ─────────────────────────────────────────────────

  /// Returns a short code for [state]:
  ///   - Matches US state names (case-insensitive) → standard 2-letter code
  ///   - Already a ≤3-char string → uppercased as-is
  ///   - Multi-word non-match → initials (e.g. "New South Wales" → "NSW")
  ///   - Single-word non-match → first 2 chars uppercased
  static String abbreviateState(String state) {
    final key = state.trim().toLowerCase();
    final code = _usStateCodes[key];
    if (code != null) return code;
    final s = state.trim();
    if (s.length <= 3) return s.toUpperCase();
    final words = s.split(RegExp(r'\s+'));
    if (words.length >= 2) {
      return words.map((w) => w.isEmpty ? '' : w[0].toUpperCase()).join();
    }
    return s.substring(0, 2).toUpperCase();
  }

  static const Map<String, String> _usStateCodes = {
    'alabama': 'AL', 'alaska': 'AK', 'arizona': 'AZ', 'arkansas': 'AR',
    'california': 'CA', 'colorado': 'CO', 'connecticut': 'CT', 'delaware': 'DE',
    'florida': 'FL', 'georgia': 'GA', 'hawaii': 'HI', 'idaho': 'ID',
    'illinois': 'IL', 'indiana': 'IN', 'iowa': 'IA', 'kansas': 'KS',
    'kentucky': 'KY', 'louisiana': 'LA', 'maine': 'ME', 'maryland': 'MD',
    'massachusetts': 'MA', 'michigan': 'MI', 'minnesota': 'MN', 'mississippi': 'MS',
    'missouri': 'MO', 'montana': 'MT', 'nebraska': 'NE', 'nevada': 'NV',
    'new hampshire': 'NH', 'new jersey': 'NJ', 'new mexico': 'NM', 'new york': 'NY',
    'north carolina': 'NC', 'north dakota': 'ND', 'ohio': 'OH', 'oklahoma': 'OK',
    'oregon': 'OR', 'pennsylvania': 'PA', 'rhode island': 'RI', 'south carolina': 'SC',
    'south dakota': 'SD', 'tennessee': 'TN', 'texas': 'TX', 'utah': 'UT',
    'vermont': 'VT', 'virginia': 'VA', 'washington': 'WA', 'west virginia': 'WV',
    'wisconsin': 'WI', 'wyoming': 'WY', 'district of columbia': 'DC',
  };
}

/// InheritedNotifier that exposes [DemoProfile] to the entire widget tree.
///
/// Usage (read + subscribe to rebuilds):
///   final profile = DemoProfileScope.of(context);
///
/// Usage (mutate — EditProfileScreen, GalleryScreen only):
///   DemoProfileScope.of(context).saveTextFields(...);
///   DemoProfileScope.of(context).setPhoto(i, xFile);
class DemoProfileScope extends InheritedNotifier<DemoProfile> {
  const DemoProfileScope({
    super.key,
    required DemoProfile profile,
    required super.child,
  }) : super(notifier: profile);

  static DemoProfile of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<DemoProfileScope>();
    assert(scope != null, 'No DemoProfileScope found in widget tree.');
    return scope!.notifier!;
  }
}
