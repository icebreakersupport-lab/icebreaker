import 'dart:async';
import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'core/constants/app_constants.dart';
import 'core/router/app_router.dart';
import 'core/services/profile_repository.dart';
import 'core/state/user_profile.dart';
import 'core/state/flow_coordinator.dart';
import 'core/state/live_session.dart';
import 'core/theme/app_theme.dart';

/// Root application widget.
///
/// Owns both [LiveSession] and [UserProfile] notifiers and exposes them
/// app-wide via their respective InheritedNotifier scopes.
///
/// On startup, if a Firebase Auth user is already signed in (e.g. a returning
/// user whose token is still valid), [LiveSession.hydrateCredits] is called
/// so the Icebreaker credit balance reflects the persisted Firestore value
/// rather than the default in-memory initialiser.
///
/// [initialLocation] is supplied by [BootstrapRoot] after it has finished
/// resolving auth + profile state, so the router opens directly on the
/// correct screen (welcome / home / onboarding) rather than briefly
/// rendering a loading placeholder at `/`.
class IcebreakerApp extends StatefulWidget {
  const IcebreakerApp({super.key, this.initialLocation = AppRoutes.splash});

  final String initialLocation;

  @override
  State<IcebreakerApp> createState() => _IcebreakerAppState();
}

class _IcebreakerAppState extends State<IcebreakerApp>
    with WidgetsBindingObserver {
  final LiveSession _session = LiveSession();
  final UserProfile _profile = UserProfile();
  final FlowCoordinator _flowCoordinator = FlowCoordinator();

  /// Built once per [IcebreakerApp] mount so the initial route reflects the
  /// destination [BootstrapRoot] resolved before the router was constructed,
  /// and the FlowCoordinator drives flow-lock redirects via refreshListenable.
  late final _router = buildAppRouter(
    initialLocation: widget.initialLocation,
    flowCoordinator: _flowCoordinator,
  );

  /// Honest lifecycle state for the initial FCM-token registration:
  ///
  ///   • [idle]       — no successful registration yet, and no attempt is
  ///                    currently running.  Eligible to start (or retry) on
  ///                    the next lifecycle hook (cold start / app resume).
  ///   • [inFlight]   — an attempt is currently running.  Reentrancy is
  ///                    blocked so overlapping lifecycle hooks don't issue
  ///                    parallel calls.
  ///   • [registered] — `users/{uid}.fcmToken` has been written successfully
  ///                    in this process.  No further attempts are made;
  ///                    rotation is handled by the [onTokenRefresh] listener.
  ///
  /// On Apple-platform deferrals (APNs not ready) and on transient failures
  /// the status returns to [idle], so the next [didChangeAppLifecycleState]
  /// resume tick automatically retries via [_hydrateCreditsIfSignedIn].
  /// `onTokenRefresh` remains as a secondary safety net but is no longer the
  /// only path that delivers the initial token.
  _FcmStatus _fcmStatus = _FcmStatus.idle;

  /// Subscription to authStateChanges so we hydrate the profile when a user
  /// signs in and clear it when they sign out.
  StreamSubscription<User?>? _authSub;

  /// Last hydrated uid — guards against re-running the Firestore fetch on
  /// unrelated auth-state pings (e.g. token refresh emitting the same user).
  String? _hydratedForUid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _hydrateCreditsIfSignedIn();
    _hydrateProfileIfSignedIn();
    _listenForAuthChanges();
    _listenForTokenRefresh();
  }

  /// Clears in-memory profile + live session on sign-out and re-hydrates both
  /// when a different user signs in. Keeps all per-account state honest across
  /// account switches without a full app restart.
  void _listenForAuthChanges() {
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null) {
        debugPrint('[App] auth cleared — wiping UserProfile + LiveSession');
        _hydratedForUid = null;
        _profile.clearAll();
        _session.clearForSignOut();
        return;
      }
      if (_hydratedForUid == user.uid) return;
      _profile.clearAll();
      _hydrateProfileForUid(user.uid);
      _session.hydrateOnLaunch(user.uid);
    });
  }

  /// Keeps users/{uid}.fcmToken fresh if the FCM service rotates the token
  /// after the initial registration (e.g. app reinstall, token expiry).
  /// Set up once in initState — not per-resume — to avoid duplicate listeners.
  void _listenForTokenRefresh() {
    FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      debugPrint('[App] FCM token refreshed — updating Firestore');
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update({'fcmToken': token}).catchError(
        (Object e) => debugPrint('[App] FCM token refresh write failed: $e'),
      );
    });
  }

  /// Re-run credit hydration whenever the app returns from the background.
  /// This catches the case where the user left the app for 24+ hours and
  /// resumes it without a cold start.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('[App] app resumed — re-hydrating credits');
      _hydrateCreditsIfSignedIn();
      // If a live session is active, immediately refresh GPS position and
      // restart the location timer.  iOS may have throttled or killed the
      // periodic timer while the app was in the background.
      _session.onResume();
      // Reload the Firebase Auth user so emailVerified reflects any
      // verification the user completed outside the app (e.g. email link).
      FirebaseAuth.instance.currentUser?.reload().catchError(
        (Object e) => debugPrint('[App] user reload failed: $e'),
      );
    }
  }

  /// If a user is already authenticated, pull their credit balance from
  /// Firestore and apply any pending 24-hour reset.  Fire-and-forget — the
  /// app renders immediately and counters update reactively.
  ///
  /// Also drives initial FCM-token registration: if [_fcmStatus] is still
  /// [_FcmStatus.idle] (cold start, or an earlier attempt deferred because
  /// APNs wasn't ready yet), we kick off another attempt.  Reentrancy is
  /// blocked inside [_registerFcmToken] itself, so a resume tick that fires
  /// while a prior attempt is in flight is a no-op.
  void _hydrateCreditsIfSignedIn() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      debugPrint('[App] hydrating credits for uid=$uid');
      _session.hydrateCredits(uid);
      if (_fcmStatus == _FcmStatus.idle) {
        _registerFcmToken(uid);
      }
    }
  }

  /// On cold start, if the user is already signed in (token persisted by
  /// Firebase Auth), pull the user's public profile from `profiles/{uid}`
  /// (canonical) so Profile/Gallery render the persisted state immediately
  /// rather than the in-memory defaults.
  void _hydrateProfileIfSignedIn() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) _hydrateProfileForUid(uid);
  }

  /// Hydrates the in-memory [UserProfile] from `profiles/{uid}`, falling
  /// back to `users/{uid}` for legacy accounts that pre-date the dual-write
  /// (no profiles doc has landed yet) or for individual fields that haven't
  /// migrated yet.  The fallback layer never clobbers fields already filled
  /// by the canonical source — see [UserProfile.hydrateAll].
  Future<void> _hydrateProfileForUid(String uid) async {
    final db = FirebaseFirestore.instance;
    var hydratedFromProfiles = false;

    // Reset first so a fresh account never renders the previous user's
    // in-memory values while Firestore hydration is still in flight.
    _profile.clearAll();

    try {
      final profileSnap = await ProfileRepository().fetch(uid);
      if (profileSnap != null) {
        _profile.hydrateAll(profileSnap);
        hydratedFromProfiles = true;
        debugPrint('[App] hydrated profiles/$uid '
            '(${profileSnap.length} fields)');
      } else {
        debugPrint('[App] profiles/$uid missing — falling back to users/$uid');
      }
    } catch (e) {
      debugPrint('[App] profiles/$uid hydrate failed: $e — '
          'falling back to users/$uid');
    }

    // Always attempt a users/{uid} backfill: it never overwrites fields
    // already filled by profiles, but it covers legacy accounts where some
    // public fields still only exist on the user doc (or the profiles read
    // failed entirely).
    Map<String, dynamic>? usersData;
    try {
      final userDoc = await db.collection('users').doc(uid).get();
      usersData = userDoc.data();
      if (usersData != null) {
        _profile.hydrateAll(usersData);
        if (!hydratedFromProfiles) {
          debugPrint('[App] hydrated users/$uid (legacy fallback)');
        }
      }
    } catch (e) {
      debugPrint('[App] users/$uid fallback hydrate failed: $e');
    }

    // If the canonical doc didn't exist on first read, materialise it now
    // from whatever we have on hand (the users/{uid} snapshot, or an empty
    // shell stamped only with updatedAt).  This guarantees `profiles/{uid}`
    // is observable in Firestore immediately after sign-in instead of only
    // after the first Edit Profile save — a UX gap the user flagged
    // explicitly.  Idempotent: ensureExists returns false on existing docs,
    // so resume ticks and account-switch hydrations don't re-write.
    if (!hydratedFromProfiles) {
      try {
        final created =
            await ProfileRepository().ensureExists(uid, fallback: usersData);
        if (created) {
          debugPrint('[App] profiles/$uid materialised from users fallback');
        }
      } catch (e) {
        debugPrint('[App] profiles/$uid ensureExists failed: $e');
      }
    }

    _hydratedForUid = uid;
  }

  /// True on iOS / macOS, where FCM token retrieval is gated on APNs.
  bool get _isApplePlatform =>
      !kIsWeb && (Platform.isIOS || Platform.isMacOS);

  /// Requests push-notification permission and writes the FCM token to
  /// users/{uid}.fcmToken.  Single-flight via [_fcmStatus]: callers don't
  /// need to think about reentrancy.
  ///
  /// Platform notes:
  ///   iOS/macOS — requestPermission shows the system dialog.  FCM token
  ///               retrieval requires that APNs has already handed an APNs
  ///               token to the app; on a fresh launch, simulator, or device
  ///               where APNs registration hasn't completed, this won't be
  ///               true yet.  We check `getAPNSToken()` first; if it's null
  ///               we leave [_fcmStatus] at [_FcmStatus.idle] so the next
  ///               `didChangeAppLifecycleState` resume tick retries.  This
  ///               makes the explicit acquisition path the primary mechanism
  ///               and keeps `onTokenRefresh` as a secondary safety net,
  ///               rather than the only way the initial token ever lands.
  ///   Android   — permission is auto-granted pre-API-33; API 33+ shows the
  ///               OS dialog.  No APNs gate — we go straight to getToken().
  ///   Web       — not targeted; VAPID key would be required.
  Future<void> _registerFcmToken(String uid) async {
    if (_fcmStatus != _FcmStatus.idle) return;
    _fcmStatus = _FcmStatus.inFlight;
    var success = false;
    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      // Apple-only readiness gate.  Without this, calling getToken() before
      // APNs is ready raises `[firebase_messaging/apns-token-not-set]`, which
      // is normal-but-noisy on cold start and on the iOS simulator.
      if (_isApplePlatform) {
        final apnsToken = await FirebaseMessaging.instance.getAPNSToken();
        if (apnsToken == null) {
          debugPrint(
              '[App] APNs token not ready — will retry on next app resume');
          return; // finally clause leaves status at idle → eligible to retry
        }
      }

      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) {
        // No APNs setup / simulator without push entitlement / permission
        // denied.  Not an error.  Leaving status idle means we'll retry on
        // the next resume — useful if the user grants permission via
        // Settings while the app is backgrounded.
        debugPrint(
            '[App] FCM token not available (simulator or no APNs setup) — '
            'will retry on next app resume');
        return;
      }
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update({'fcmToken': token});
      success = true;
      debugPrint('[App] FCM token registered');
    } on FirebaseException catch (e) {
      // Defensive: a race between getAPNSToken() and getToken() can still
      // surface apns-token-not-set even after the readiness gate passes.
      // Treat it as "not ready yet" — the resume retry will pick it up.
      if (e.code == 'apns-token-not-set') {
        debugPrint(
            '[App] APNs token not ready (race) — will retry on next app resume');
      } else {
        debugPrint('[App] FCM token registration failed: $e');
      }
    } catch (e) {
      // Non-fatal — app works without push notifications.
      debugPrint('[App] FCM token registration failed: $e');
    } finally {
      _fcmStatus = success ? _FcmStatus.registered : _FcmStatus.idle;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSub?.cancel();
    _session.dispose();
    _profile.dispose();
    _flowCoordinator.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return UserProfileScope(
      profile: _profile,
      child: LiveSessionScope(
        session: _session,
        child: FlowCoordinatorScope(
          coordinator: _flowCoordinator,
          child: MaterialApp.router(
            title: 'Icebreaker',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.dark,
            routerConfig: _router,
          ),
        ),
      ),
    );
  }
}

/// Lifecycle state for the initial FCM-token registration.  See the doc
/// comment on `_IcebreakerAppState._fcmStatus` for the full state machine.
enum _FcmStatus { idle, inFlight, registered }
