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
/// cleared via [UserProfile.removePhotoSlot].
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

/// Shared mutable user profile state — the single source of truth for all
/// user-editable profile fields, hydrated from `profiles/{uid}` and
/// `users/{uid}`.
///
/// Owned by [IcebreakerApp] via [UserProfileScope] so every screen that
/// reads it rebuilds automatically when [notifyListeners] is called.
///
/// Mutate via the write methods (never set fields directly).
class UserProfile extends ChangeNotifier {
  // ── Identity ────────────────────────────────────────────────────────────────
  String firstName = '';
  int age = 0;

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
  Set<String> interests = {};
  Set<String> hobbies = {};

  // ── Profile Details ──────────────────────────────────────────────────────────
  String occupation = '';
  String height = '';

  // ── Dating Preferences ───────────────────────────────────────────────────────
  String lookingFor = '';

  /// Canonical lowercase code: 'everyone' | 'men' | 'women' | 'non_binary'.
  /// Storage and matching are always lowercase; UI renders via
  /// [interestedInLabel].  Legacy accounts whose users/{uid} still has
  /// Title-case 'Women' or the older 'showMe' / 'openTo' field are
  /// normalised by [hydrateAll] through [interestedInToCanonical].
  String interestedIn = '';
  RangeValues ageRange = const RangeValues(20, 35);

  // ── Private discovery controls (users/{uid} only — not on profiles) ─────────
  /// Discovery radius in metres.  Captured into
  /// `live_sessions/{uid}.maxDistanceMetersSnapshot` at Go Live.
  int maxDistanceMeters = 30;

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
  ///
  /// [interestedIn] must be canonical lowercase
  /// (`'everyone' | 'men' | 'women' | 'non_binary'`); callers pass values that
  /// originate from chip selections keyed by canonical code, so the field is
  /// stored as-is.  [maxDistanceMeters] is a private discovery control —
  /// Edit Profile collects it in the same surface as the public preferences
  /// for ergonomics, but the persistence layer only writes it to `users/{uid}`
  /// (see EditProfileScreen._save).
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
    required int maxDistanceMeters,
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
    this.maxDistanceMeters = maxDistanceMeters;
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

  /// Set or clear the **persisted URL** at [index].  Used by callers that
  /// have just finished an upload and need to land the resulting download URL
  /// into the same slot the local pick is sitting in, so a future
  /// [hydrateFromFirestore] (or sign-in on another device) reproduces the
  /// same arrangement.  Does not touch the local-pick layer.
  void setPhotoUrl(int index, String url) {
    _photoUrls[index] = url;
    notifyListeners();
  }

  /// Replace the slot's local pick with [xFile] AND clear any stale persisted
  /// URL at that slot in the same notify cycle.
  ///
  /// This is the honest semantic for a user-initiated "add or replace" gesture:
  /// once the user has chosen a new photo for a slot, the previous server-side
  /// URL no longer represents their intent for that slot.  Leaving it in
  /// [_photoUrls] would let a Firestore commit that runs before (or instead
  /// of) the new upload re-persist the old URL as if it were still current,
  /// breaking the contract that restart matches the user's latest intent.
  ///
  /// The slot's [imageProvider] still resolves immediately (local pick wins
  /// over URL), so visible UX is unchanged.  If the upload succeeds, the
  /// caller writes the new URL via [setPhotoUrl] and the slot is fully
  /// persisted.  If the upload fails or is cancelled, restart shows the slot
  /// as empty — which matches the user's last intent ("no longer the old
  /// photo") rather than silently restoring obsolete content.
  void replacePhoto(int index, XFile xFile) {
    _photos[index] = xFile;
    _photoUrls[index] = '';
    notifyListeners();
  }

  /// Snapshot of the persisted URL layer in slot order.  Used by the gallery
  /// to build the list it sends to Firestore after a swap or remove.  Returns
  /// an unmodifiable view so callers can't mutate the internal array.
  List<String> get allPhotoUrls => List.unmodifiable(_photoUrls);

  /// Returns the slot index currently holding [xFile] (by reference identity),
  /// or `-1` if the file is no longer in any slot.
  ///
  /// Used to resolve where a freshly uploaded photo actually lives by the
  /// time the upload completes — the user may have dragged or removed it
  /// while bytes were in flight, so the original slot index captured at
  /// upload start is no longer trustworthy.  Identity (`identical`) rather
  /// than path equality is the correct test: replacing a slot with another
  /// photo at the same temp path should not be confused with the original.
  int indexOfPhoto(XFile xFile) {
    for (var i = 0; i < _slotCount; i++) {
      if (identical(_photos[i], xFile)) return i;
    }
    return -1;
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

  /// Fully resets the in-memory profile to a blank new-account state.
  ///
  /// This is stronger than [clearMedia]: it clears text fields, chips,
  /// preferences, and media so account switches never leak the previous
  /// user's profile into a brand-new or half-onboarded account.
  void clearAll() {
    firstName = '';
    age = 0;
    hometownCity = '';
    hometownState = '';
    bio = '';
    interests = {};
    hobbies = {};
    occupation = '';
    height = '';
    lookingFor = '';
    interestedIn = '';
    ageRange = const RangeValues(20, 35);
    maxDistanceMeters = 30;
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

  /// Hydrates every public-profile field from a Firestore map.  Called on
  /// sign-in (`profiles/{uid}` snapshot) and on subsequent live updates so
  /// the user's own profile screen renders the canonical doc rather than
  /// the in-memory defaults.
  ///
  /// Fields not present in [data] are left untouched — this matters for the
  /// fallback path where `profiles/{uid}` is read first and `users/{uid}`
  /// is read as a backfill source for legacy accounts; the second call
  /// must not clobber values landed by the first.  Local photo picks are
  /// also preserved (mirrors [hydrateFromFirestore]).
  void hydrateAll(Map<String, dynamic> data) {
    final fn = data['firstName'];
    if (fn is String && fn.isNotEmpty) firstName = fn;

    final a = data['age'];
    if (a is num) age = a.toInt();

    final b = data['bio'];
    if (b is String) bio = b;

    final occ = data['occupation'];
    if (occ is String) occupation = occ;

    final h = data['height'];
    if (h is String) height = h;

    final lf = data['lookingFor'];
    if (lf is String) lookingFor = lf;

    // Interested-in legacy chain: prefer the new canonical field, then the
    // older `openTo` (lowercase canonical from onboarding) and `showMe`
    // (lowercase canonical from the retired Settings discovery sheet),
    // finally the very early Title-case persistence written before
    // canonicalisation existed.  All paths route through
    // [interestedInToCanonical] so the in-memory value is always lowercase
    // canonical regardless of which legacy source the doc carries.
    final ii = data['interestedIn'];
    final ot = data['openTo'];
    final sm = data['showMe'];
    if (ii is String && ii.isNotEmpty) {
      interestedIn = interestedInToCanonical(ii);
    } else if (ot is String && ot.isNotEmpty) {
      interestedIn = interestedInToCanonical(ot);
    } else if (sm is String && sm.isNotEmpty) {
      interestedIn = interestedInToCanonical(sm);
    }

    // Private discovery controls — read only when this map is the
    // `users/{uid}` doc.  hydrateAll being called twice (once with
    // profiles/{uid}, once with users/{uid}) is fine: the first call leaves
    // these fields untouched because the keys are absent on the public doc.
    final mdm = data['maxDistanceMeters'];
    if (mdm is num) {
      maxDistanceMeters = mdm.toInt().clamp(30, 60);
    }

    final amin = data['ageRangeMin'];
    final amax = data['ageRangeMax'];
    if (amin is num && amax is num) {
      ageRange = RangeValues(amin.toDouble(), amax.toDouble());
    }

    final ints = data['interests'];
    if (ints is List) {
      interests = ints.whereType<String>().toSet();
    }

    final hobs = data['hobbies'];
    if (hobs is List) {
      hobbies = hobs.whereType<String>().toSet();
    }

    final ht = data['hometown'];
    if (ht is Map) {
      final c = ht['city'];
      final s = ht['state'] ?? ht['stateCode'];
      if (c is String) hometownCity = c;
      if (s is String) hometownState = s;
    }

    final urls = data['photoUrls'];
    if (urls is List) {
      final cast = urls.whereType<String>().toList();
      for (var i = 0; i < _slotCount; i++) {
        _photoUrls[i] = i < cast.length ? cast[i] : '';
      }
    }

    notifyListeners();
  }

  // ── Interested-in canonicalisation ────────────────────────────────────────────

  /// Normalise any legacy or user-typed value to the canonical lowercase code.
  /// Accepts the canonical codes themselves, Title-case display labels left
  /// over from the pre-canonical persistence (`'Women'`, `'Men'`, …), and
  /// the older 'man' / 'woman' / 'female' / 'male' / 'nonbinary' / 'non-binary'
  /// shapes that appeared in early onboarding writes.  Anything unrecognised
  /// falls back to `'everyone'` so a corrupted doc still produces a usable
  /// preference rather than an exception path.
  static String interestedInToCanonical(String raw) {
    final v = raw.trim().toLowerCase();
    if (v == 'men' || v == 'man' || v == 'male') return 'men';
    if (v == 'women' || v == 'woman' || v == 'female') return 'women';
    if (v == 'non_binary' || v == 'nonbinary' || v == 'non-binary') {
      return 'non_binary';
    }
    return 'everyone';
  }

  /// Title-case display label for a canonical interested-in code.  UI layers
  /// render via this helper so the on-disk lowercase code never leaks into
  /// the user-visible surface.
  static String interestedInLabel(String canonical) => switch (canonical) {
        'men' => 'Men',
        'women' => 'Women',
        'non_binary' => 'Non-binary',
        _ => 'Everyone',
      };

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

/// InheritedNotifier that exposes [UserProfile] to the entire widget tree.
///
/// Usage (read + subscribe to rebuilds):
///   final profile = UserProfileScope.of(context);
///
/// Usage (mutate — EditProfileScreen, GalleryScreen only):
///   UserProfileScope.of(context).saveTextFields(...);
///   UserProfileScope.of(context).setPhoto(i, xFile);
class UserProfileScope extends InheritedNotifier<UserProfile> {
  const UserProfileScope({
    super.key,
    required UserProfile profile,
    required super.child,
  }) : super(notifier: profile);

  static UserProfile of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<UserProfileScope>();
    assert(scope != null, 'No UserProfileScope found in widget tree.');
    return scope!.notifier!;
  }
}
