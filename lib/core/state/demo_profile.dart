import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Per-slot media state — the combined view of an in-session local pick and
/// a persisted Firestore URL for the same slot index.
///
/// Render priority is **local first, URL second**.  Both can be set at the
/// same time (e.g. the user replaces a persisted photo with a fresh local
/// pick before any commit-to-server flow runs); the local file shadows the
/// URL for display and remains shadowing it until the slot is explicitly
/// cleared via [DemoProfile.removePhotoSlot].
///
/// A slot is [isEmpty] when neither layer has content.
@immutable
class ProfilePhotoSlot {
  const ProfilePhotoSlot._(this.localFile, this.url);

  final XFile? localFile;
  final String url;

  bool get hasLocalPick => localFile != null;
  bool get hasPersistedUrl => url.isNotEmpty;
  bool get isEmpty => localFile == null && url.isEmpty;
  bool get isNotEmpty => !isEmpty;

  /// Real on-disk path for the local pick, if any.  Used by callers that
  /// require a file path specifically (e.g. the live-verification screen
  /// hands the path to `LiveSession.goLive`).  Returns null whenever the
  /// slot has only a persisted URL.
  String? get localPath => localFile?.path;

  /// The right [ImageProvider] for rendering this slot.  Returns null when
  /// the slot is empty so callers can render a placeholder unconditionally.
  ImageProvider? get imageProvider {
    final lf = localFile;
    if (lf != null) return FileImage(File(lf.path));
    if (url.isNotEmpty) return NetworkImage(url);
    return null;
  }
}

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
  // Two parallel 6-slot lists, one per ownership layer:
  //   [_photos]    — local in-session picks (XFile on disk)
  //   [_photoUrls] — persisted Firestore URLs (rehydrated on sign-in)
  // They are kept index-aligned at all times.  Use [photoAt] to read and the
  // mutators below to write — direct list access is intentionally private.
  static const int _slotCount = 6;

  final List<XFile?> _photos =
      List<XFile?>.filled(_slotCount, null, growable: false);
  final List<String> _photoUrls =
      List<String>.filled(_slotCount, '', growable: false);

  /// Single optional intro video.  No URL layer for now — video persistence
  /// isn't wired through Firestore on this branch.
  XFile? video;

  /// Combined slot value at [index].  Throws on out-of-range.
  ProfilePhotoSlot photoAt(int index) {
    return ProfilePhotoSlot._(_photos[index], _photoUrls[index]);
  }

  /// Number of slots with any media at all (local pick OR persisted URL).
  /// Drives gallery count badges and profile-completion scoring; both should
  /// reflect "the user has photos" regardless of which layer they live in.
  int get photoCount {
    var n = 0;
    for (var i = 0; i < _slotCount; i++) {
      if (_photos[i] != null || _photoUrls[i].isNotEmpty) n++;
    }
    return n;
  }

  /// Total slot count exposed for grids that iterate by index.
  int get photoSlotCount => _slotCount;

  /// First non-empty slot's local pick (XFile-only).  Used by the live
  /// verification screen which requires a real on-disk path — a remote URL
  /// can't be handed to the verifier — so this getter intentionally ignores
  /// the persisted URL layer.  Returns null when no local pick exists in any
  /// slot, even if persisted URLs are present.
  XFile? get mainPhoto {
    for (final p in _photos) {
      if (p != null) return p;
    }
    return null;
  }

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

  /// Set or clear the **local pick** at [index].  Leaves the persisted URL at
  /// that slot untouched so a temporary local clear reveals the URL again
  /// rather than wiping server state.  To wipe both layers, use
  /// [removePhotoSlot].
  void setPhoto(int index, XFile? xFile) {
    _photos[index] = xFile;
    notifyListeners();
  }

  /// Wipes the slot completely — both the local pick and the persisted URL.
  /// This is the operation behind a user-visible "Remove" action.
  void removePhotoSlot(int index) {
    _photos[index] = null;
    _photoUrls[index] = '';
    notifyListeners();
  }

  /// Swap two slots in lockstep across both layers so the visible order
  /// matches the order that would be persisted on a future commit.
  void swapPhotos(int a, int b) {
    final tmpFile = _photos[a];
    _photos[a] = _photos[b];
    _photos[b] = tmpFile;
    final tmpUrl = _photoUrls[a];
    _photoUrls[a] = _photoUrls[b];
    _photoUrls[b] = tmpUrl;
    notifyListeners();
  }

  /// Set or clear the intro video.
  void setVideo(XFile? xFile) {
    video = xFile;
    notifyListeners();
  }

  /// Clears every in-memory media layer for the active account: local picks,
  /// persisted URL cache, and the intro video.  Called on sign-out so the
  /// next account doesn't see leftover media.
  void clearMedia() {
    for (var i = 0; i < _slotCount; i++) {
      _photos[i] = null;
      _photoUrls[i] = '';
    }
    video = null;
    notifyListeners();
  }

  /// Rehydrates the persisted URL layer from `users/{uid}.photoUrls`.
  ///
  /// In-session local picks are intentionally left alone — a user who has
  /// just picked a fresh photo locally should not have it overwritten by a
  /// background Firestore read.  Slots beyond [urls].length are zeroed so
  /// the cache reflects the server's array length exactly.
  void hydrateFromFirestore(List<String> urls) {
    for (var i = 0; i < _slotCount; i++) {
      _photoUrls[i] = i < urls.length ? urls[i] : '';
    }
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
    'alabama': 'AL',
    'alaska': 'AK',
    'arizona': 'AZ',
    'arkansas': 'AR',
    'california': 'CA',
    'colorado': 'CO',
    'connecticut': 'CT',
    'delaware': 'DE',
    'florida': 'FL',
    'georgia': 'GA',
    'hawaii': 'HI',
    'idaho': 'ID',
    'illinois': 'IL',
    'indiana': 'IN',
    'iowa': 'IA',
    'kansas': 'KS',
    'kentucky': 'KY',
    'louisiana': 'LA',
    'maine': 'ME',
    'maryland': 'MD',
    'massachusetts': 'MA',
    'michigan': 'MI',
    'minnesota': 'MN',
    'mississippi': 'MS',
    'missouri': 'MO',
    'montana': 'MT',
    'nebraska': 'NE',
    'nevada': 'NV',
    'new hampshire': 'NH',
    'new jersey': 'NJ',
    'new mexico': 'NM',
    'new york': 'NY',
    'north carolina': 'NC',
    'north dakota': 'ND',
    'ohio': 'OH',
    'oklahoma': 'OK',
    'oregon': 'OR',
    'pennsylvania': 'PA',
    'rhode island': 'RI',
    'south carolina': 'SC',
    'south dakota': 'SD',
    'tennessee': 'TN',
    'texas': 'TX',
    'utah': 'UT',
    'vermont': 'VT',
    'virginia': 'VA',
    'washington': 'WA',
    'west virginia': 'WV',
    'wisconsin': 'WI',
    'wyoming': 'WY',
    'district of columbia': 'DC',
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
    final scope = context
        .dependOnInheritedWidgetOfExactType<DemoProfileScope>();
    assert(scope != null, 'No DemoProfileScope found in widget tree.');
    return scope!.notifier!;
  }
}
