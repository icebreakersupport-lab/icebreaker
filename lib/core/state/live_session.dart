import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';

import '../constants/app_constants.dart';
import '../services/location_service.dart';

/// Holds the single source of truth for whether the user has an active
/// Live session, when it expires, and the current Icebreaker credit balance.
///
/// Consumed via [LiveSessionScope] anywhere in the widget tree.
/// The notifier is owned by [IcebreakerApp] and lives for the app lifetime.
class LiveSession extends ChangeNotifier {
  bool _isLive = false;
  DateTime? _expiresAt;
  int _liveCredits = 1;
  String? _selfieFilePath;

  /// One-shot timer that calls [endSession] when the live session expires.
  /// Survives tab navigation because [LiveSession] is app-lifetime scoped.
  Timer? _expiryTimer;

  /// Periodic timer that refreshes the user's GPS position in Firestore every
  /// [AppConstants.locationUpdateIntervalSeconds] seconds while live.
  /// Cancelled immediately in [endSession] so the user's position is stale
  /// after going offline rather than reflecting their last-known location.
  Timer? _locationTimer;

  /// One-shot timer that fires at the exact moment the free-credit reset
  /// window elapses.  When it fires, [hydrateCredits] is called with the
  /// stored uid, applying the reset, updating Firestore, notifying listeners,
  /// and scheduling the next timer automatically.
  Timer? _resetTimer;

  /// UID of the currently signed-in user.  Set on first successful hydration
  /// so the reset timer closure can call [hydrateCredits] without a widget
  /// context.
  String? _uid;

  /// In-memory Icebreaker credit balance.
  /// Authoritative value comes from Firestore via [hydrateCredits].
  int _icebreakerCredits = AppConstants.freeIcebreakerCreditsPerSignup;

  /// When the current 24-hour free-credit window resets.
  /// Null until [hydrateCredits] runs successfully.
  DateTime? _icebreakerCreditsResetAt;

  // ── Getters ────────────────────────────────────────────────────────────────

  bool get isLive => _isLive;
  DateTime? get expiresAt => _expiresAt;
  String? get selfieFilePath => _selfieFilePath;
  int get liveCredits => _liveCredits;
  int get icebreakerCredits => _icebreakerCredits;
  DateTime? get icebreakerCreditsResetAt => _icebreakerCreditsResetAt;

  /// Time remaining in the current session. Zero when not live or expired.
  Duration get remainingDuration {
    if (_expiresAt == null || !_isLive) return Duration.zero;
    final remaining = _expiresAt!.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  // ── Session mutators ───────────────────────────────────────────────────────

  void goLive({String? selfieFilePath}) {
    _isLive = true;
    _expiresAt = DateTime.now().add(const Duration(hours: 1));
    if (selfieFilePath != null) _selfieFilePath = selfieFilePath;
    if (_liveCredits > 0) _liveCredits--;
    _scheduleExpiry();
    // Mark the user as live in Firestore and clear DND in a single write so
    // the notification Cloud Function sees a consistent state.
    //
    // Null-uid fix: _uid is set by hydrateCredits(), which may not have
    // completed yet on a very fast cold-launch path.  Fall back to FirebaseAuth
    // directly so goLive() never silently skips the Firestore update.
    //
    // Known limitation: if the app is force-killed while live, endSession()
    // never fires and isLive stays true in Firestore until the next cold-start
    // (where hydrateCredits resets it).  Addressed by TODO below.
    final uid = _uid ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      // Write isLive immediately so the user is discoverable without waiting
      // for GPS.  Position fields are written in a follow-up update once the
      // GPS fix arrives (typically < 2 s with a warm GPS cache).
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update({'isLive': true, 'doNotDisturb': false}).catchError(
        (Object e) =>
            debugPrint('[LiveSession] goLive Firestore update failed: $e'),
      );

      // Async GPS write — does not block the session starting.
      _writePositionToFirestore(uid);

      // Start the periodic refresh so position stays current as the user moves.
      _startLocationRefresh(uid);
    }
    notifyListeners();
  }

  /// Arms a periodic timer that refreshes the GPS position every
  /// [AppConstants.locationUpdateIntervalSeconds] seconds.
  /// Safe to call multiple times — always cancels the previous timer first.
  void _startLocationRefresh(String uid) {
    _locationTimer?.cancel();
    _locationTimer = Timer.periodic(
      const Duration(seconds: AppConstants.locationUpdateIntervalSeconds),
      (_) {
        debugPrint('[LiveSession] periodic location refresh');
        _writePositionToFirestore(uid);
      },
    );
  }

  /// Reads the device's current GPS position and writes latitude, longitude,
  /// and geohash to the user's Firestore doc.  Non-fatal — if GPS is
  /// unavailable the user is still live but simply won't appear in nearby
  /// discovery until a position is written.
  Future<void> _writePositionToFirestore(String uid) async {
    final pos = await LocationService.getPosition();
    if (pos == null) {
      debugPrint('[LiveSession] no GPS position — skipping position write');
      return;
    }
    final geohash = LocationService.encode(pos.latitude, pos.longitude);
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'geohash': geohash,
        'locationUpdatedAt': FieldValue.serverTimestamp(),
      });
      debugPrint('[LiveSession] position written: '
          '${pos.latitude},${pos.longitude} geohash=$geohash');
    } catch (e) {
      debugPrint('[LiveSession] position write failed (non-fatal): $e');
    }
  }

  void _scheduleExpiry() {
    _expiryTimer?.cancel();
    if (_expiresAt == null) return;
    final remaining = _expiresAt!.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      endSession();
      return;
    }
    _expiryTimer = Timer(remaining, endSession);
  }

  /// Called by the app lifecycle observer when the app returns from the
  /// background.  If a live session is active:
  ///   1. Writes the current GPS position immediately (timer may have been
  ///      throttled or paused by iOS in the background).
  ///   2. Restarts [_locationTimer] so the 60-second cadence is correct from
  ///      the moment of resume, not from whenever the old timer last fired.
  ///
  /// No-op when not live.
  void onResume() {
    if (!_isLive) return;
    final uid = _uid ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    debugPrint('[LiveSession] onResume — refreshing position and restarting timer');
    _writePositionToFirestore(uid);
    _startLocationRefresh(uid); // cancels any throttled timer and starts fresh
  }

  void updateSelfie(String path) {
    _selfieFilePath = path;
    notifyListeners();
  }

  void endSession() {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _locationTimer?.cancel();
    _locationTimer = null;
    _isLive = false;
    _expiresAt = null;
    // Mirror the in-memory state to Firestore so the notification Cloud
    // Function correctly treats the user as off-live after a session ends.
    final uid = _uid ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      FirebaseFirestore.instance.collection('users').doc(uid).update({
        'isLive': false,
        // Clear position so the user is never shown as nearby while offline.
        'latitude': FieldValue.delete(),
        'longitude': FieldValue.delete(),
        'geohash': FieldValue.delete(),
        'locationUpdatedAt': FieldValue.delete(),
      }).catchError(
        (Object e) =>
            debugPrint('[LiveSession] endSession Firestore update failed: $e'),
      );
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    _locationTimer?.cancel();
    _resetTimer?.cancel();
    super.dispose();
  }

  // ── Icebreaker credit mutators ─────────────────────────────────────────────

  /// Directly set the credit balance and reset window (called after a
  /// successful send transaction where Firestore is the authoritative source).
  void setCredits(int credits, DateTime? resetAt) {
    _icebreakerCredits = credits.clamp(0, 9999);
    _icebreakerCreditsResetAt = resetAt;
    // Re-arm the reset timer with the updated window.
    if (_uid != null) _scheduleResetTimer(_uid!);
    notifyListeners();
  }

  // ── Free-credit reset ──────────────────────────────────────────────────────

  /// Reads all credit fields from `users/{uid}`, applies the 24-hour free-tier
  /// reset if the window has elapsed (or was never set), and schedules a
  /// one-shot timer so the reset fires automatically while the app is open —
  /// no restart required.
  ///
  /// Only mutates credits for `plan == 'free'`.  Plus/Gold values are read
  /// and synced as-is without any reset being applied.
  ///
  /// Non-fatal — falls back to current in-memory values on any Firestore error.
  /// Call on cold-start, sign-in, and app resume.
  Future<void> hydrateCredits(String uid) async {
    _uid = uid; // retain so the reset timer can call back without context
    try {
      final db = FirebaseFirestore.instance;
      final snap = await db.collection('users').doc(uid).get();
      if (!snap.exists) return;

      final data = snap.data()!;
      final plan = (data['plan'] as String?) ?? 'free';
      final isFree = plan == 'free';

      final storedIcebreakers = (data['icebreakerCredits'] as num?)?.toInt();
      final storedLiveCredits = (data['liveCredits'] as num?)?.toInt();
      final storedResetAt =
          (data['icebreakerCreditsResetAt'] as Timestamp?)?.toDate();

      final now = DateTime.now();

      // Reset condition (free users only):
      //   • storedResetAt is null  → field never written; initialise now
      //   • now > storedResetAt    → 24-hour window has elapsed
      final windowExpired =
          isFree && (storedResetAt == null || now.isAfter(storedResetAt));

      debugPrint('[LiveSession] hydrateCredits:'
          '\n  uid=$uid  plan=$plan'
          '\n  storedIcebreakers=$storedIcebreakers'
          '\n  storedLiveCredits=$storedLiveCredits'
          '\n  storedResetAt=$storedResetAt'
          '\n  now=$now'
          '\n  windowExpired=$windowExpired');

      if (windowExpired) {
        final newResetAt = now.add(const Duration(hours: 24));
        final newIcebreakers = AppConstants.freeIcebreakerCreditsPerSignup;
        final newLiveCredits = AppConstants.freeGoLiveCreditsPerSignup;

        await db.collection('users').doc(uid).set(
          {
            'icebreakerCredits': newIcebreakers,
            'liveCredits': newLiveCredits,
            'icebreakerCreditsResetAt': Timestamp.fromDate(newResetAt),
          },
          SetOptions(merge: true),
        );

        _icebreakerCredits = newIcebreakers;
        _liveCredits = newLiveCredits;
        _icebreakerCreditsResetAt = newResetAt;

        debugPrint('[LiveSession] ✅ reset applied —'
            ' icebreakerCredits=$newIcebreakers'
            ' liveCredits=$newLiveCredits'
            ' newResetAt=$newResetAt');
      } else {
        // No reset due — sync stored values.
        // Fall back to free defaults for fields absent from legacy docs.
        _icebreakerCredits =
            (storedIcebreakers ?? AppConstants.freeIcebreakerCreditsPerSignup)
                .clamp(0, 9999);
        _liveCredits =
            (storedLiveCredits ?? AppConstants.freeGoLiveCreditsPerSignup)
                .clamp(0, 9999);
        _icebreakerCreditsResetAt = storedResetAt;

        debugPrint('[LiveSession] ✅ hydrated (no reset) —'
            ' icebreakerCredits=$_icebreakerCredits'
            ' liveCredits=$_liveCredits'
            ' resetAt=$_icebreakerCreditsResetAt');
      }

      // Crash recovery: if Firestore says isLive=true but we have no active
      // session in memory, the previous session was never cleanly ended
      // (app force-killed).  Correct it now so DND enforcement is accurate.
      final storedIsLive = (data['isLive'] as bool?) ?? false;
      if (!_isLive && storedIsLive) {
        debugPrint('[LiveSession] ⚠ crash-recovery: resetting stale isLive=true');
        db
            .collection('users')
            .doc(uid)
            .update({'isLive': false}).catchError(
          (Object e) => debugPrint('[LiveSession] crash-recovery write failed: $e'),
        );
      }

      notifyListeners();

      // Schedule a timer for the next reset boundary so credits restore while
      // the app is open, without requiring a restart or user action.
      _scheduleResetTimer(uid);
    } catch (e, st) {
      debugPrint('[LiveSession] ❌ hydrateCredits failed (non-fatal): $e\n$st');
    }
  }

  /// Arms a one-shot timer that fires exactly when [_icebreakerCreditsResetAt]
  /// elapses and calls [hydrateCredits] to apply the reset in-process.
  ///
  /// Safe to call multiple times — always cancels the previous timer first.
  void _scheduleResetTimer(String uid) {
    _resetTimer?.cancel();
    _resetTimer = null;

    if (_icebreakerCreditsResetAt == null) return;

    final remaining = _icebreakerCreditsResetAt!.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      // Already past — run hydration immediately (shouldn't happen normally,
      // but guards against clock skew or a very tight race).
      hydrateCredits(uid);
      return;
    }

    debugPrint('[LiveSession] ⏱ reset timer scheduled in '
        '${remaining.inSeconds}s (at $_icebreakerCreditsResetAt)');

    _resetTimer = Timer(remaining, () {
      debugPrint('[LiveSession] ⏱ reset timer fired — running hydrateCredits');
      hydrateCredits(uid);
    });
  }
}

// ── Scope ──────────────────────────────────────────────────────────────────────

/// InheritedNotifier that exposes [LiveSession] to the entire widget tree.
///
/// Any widget that reads via [LiveSessionScope.of] rebuilds automatically
/// when the live state changes.
class LiveSessionScope extends InheritedNotifier<LiveSession> {
  const LiveSessionScope({
    super.key,
    required LiveSession session,
    required super.child,
  }) : super(notifier: session);

  static LiveSession of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<LiveSessionScope>();
    assert(scope != null, 'No LiveSessionScope found in widget tree.');
    return scope!.notifier!;
  }

  static bool isLive(BuildContext context) => of(context).isLive;
}
