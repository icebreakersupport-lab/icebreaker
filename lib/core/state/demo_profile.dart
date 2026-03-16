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
