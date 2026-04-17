import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'core/router/app_router.dart';
import 'core/state/demo_profile.dart';
import 'core/state/live_session.dart';
import 'core/theme/app_theme.dart';

/// Root application widget.
///
/// Owns both [LiveSession] and [DemoProfile] notifiers and exposes them
/// app-wide via their respective InheritedNotifier scopes.
///
/// On startup, if a Firebase Auth user is already signed in (e.g. a returning
/// user whose token is still valid), [LiveSession.hydrateCredits] is called
/// so the Icebreaker credit balance reflects the persisted Firestore value
/// rather than the default in-memory initialiser.
class IcebreakerApp extends StatefulWidget {
  const IcebreakerApp({super.key});

  @override
  State<IcebreakerApp> createState() => _IcebreakerAppState();
}

class _IcebreakerAppState extends State<IcebreakerApp>
    with WidgetsBindingObserver {
  final LiveSession _session = LiveSession();
  final DemoProfile _profile = DemoProfile();

  /// Guards the initial permission request + token write so they run at most
  /// once per cold start.  Token *rotation* is handled separately by the
  /// onTokenRefresh stream listener set up in initState.
  bool _fcmInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _hydrateCreditsIfSignedIn();
    _listenForTokenRefresh();
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
  /// Also registers the FCM token on cold start (guarded by [_fcmInitialized]
  /// so it does not repeat on every app-resume).
  void _hydrateCreditsIfSignedIn() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      debugPrint('[App] hydrating credits for uid=$uid');
      _session.hydrateCredits(uid);
      if (!_fcmInitialized) {
        _fcmInitialized = true;
        _registerFcmToken(uid);
      }
    }
  }

  /// Requests push-notification permission and writes the FCM token to
  /// users/{uid}.fcmToken.
  ///
  /// Platform notes:
  ///   iOS/macOS — requestPermission shows the system dialog; getToken()
  ///               returns null until APNs credentials are configured in the
  ///               Firebase Console and the app runs on a real device.
  ///   Android   — permission is granted automatically pre-API-33; on API 33+
  ///               requestPermission triggers the OS dialog.
  ///   Web       — not targeted; VAPID key would be required.
  Future<void> _registerFcmToken(String uid) async {
    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) {
        // Normal on simulator / before APNs is configured.
        debugPrint('[App] FCM token not available (simulator or no APNs setup)');
        return;
      }
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update({'fcmToken': token});
      debugPrint('[App] FCM token registered');
    } catch (e) {
      // Non-fatal — app works without push notifications.
      debugPrint('[App] FCM token registration failed: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session.dispose();
    _profile.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DemoProfileScope(
      profile: _profile,
      child: LiveSessionScope(
        session: _session,
        child: MaterialApp.router(
          title: 'Icebreaker',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.dark,
          routerConfig: appRouter,
        ),
      ),
    );
  }
}
