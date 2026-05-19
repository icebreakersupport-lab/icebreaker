import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/camera_service.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/notifications_permission_service.dart';
import '../../../core/services/photos_permission_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/gradient_scaffold.dart';

// ─── Local settings model ─────────────────────────────────────────────────────

/// Settings subset of users/{uid}.  All fields default to sane values so
/// the screen is usable even on a brand-new account that has never saved
/// preferences.
///
/// Discovery preferences (interestedIn / age range / max distance) are NOT
/// modeled here — they moved to Edit Profile and the Settings Discovery
/// section deep-links into that surface instead of editing in place.
class _UserSettings {
  _UserSettings({
    this.photosToMatchesOnly = false,
    this.doNotDisturb = false,
    this.subscriptionTier = 'free',
    this.notifReminders = true,
    this.notifIcebreakers = true,
    this.notifMessages = true,
    this.notifMatchConfirmed = true,
    this.notifSession = true,
  });

  // ── Privacy ────────────────────────────────────────────────────────────────

  /// Firestore field: photosToMatchesOnly.
  bool photosToMatchesOnly;

  /// Firestore field: doNotDisturb.
  /// Silences chat/message push notifications while the user is NOT live.
  /// Auto-cleared to false by LiveSession.goLive() when a session starts.
  /// Has no effect on discovery — discoverability is governed by live session
  /// state only (isLive in users/{uid}, set/unset by the session flow).
  bool doNotDisturb;

  // ── Account ────────────────────────────────────────────────────────────────

  /// Read from Firestore 'plan' field.  Not mutated here — use Shop screen.
  String subscriptionTier;

  // ── Notifications ──────────────────────────────────────────────────────────
  // Firestore fields: notifReminders, notifIcebreakers, notifMessages,
  // notifMatchConfirmed, notifSession.
  bool notifReminders;
  bool notifIcebreakers;
  bool notifMessages;
  bool notifMatchConfirmed;
  bool notifSession;

  factory _UserSettings.fromFirestore(Map<String, dynamic> data) {
    return _UserSettings(
      photosToMatchesOnly: (data['photosToMatchesOnly'] as bool?) ?? false,
      doNotDisturb: (data['doNotDisturb'] as bool?) ?? false,
      subscriptionTier: (data['plan'] as String?) ?? 'free',
      notifReminders: (data['notifReminders'] as bool?) ?? true,
      notifIcebreakers: (data['notifIcebreakers'] as bool?) ?? true,
      notifMessages: (data['notifMessages'] as bool?) ?? true,
      notifMatchConfirmed: (data['notifMatchConfirmed'] as bool?) ?? true,
      notifSession: (data['notifSession'] as bool?) ?? true,
    );
  }
}

// ─── Label / colour helpers ───────────────────────────────────────────────────


String _tierLabel(String tier) => switch (tier) {
      'plus' => 'Plus',
      'gold' => 'Gold',
      _ => 'Free',
    };

Color _tierColor(String tier) => switch (tier) {
      'plus' => AppColors.brandCyan,
      'gold' => AppColors.warning,
      _ => AppColors.textMuted,
    };

// ─── SettingsScreen ───────────────────────────────────────────────────────────

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  _UserSettings? _settings;
  bool _loadError = false;

  /// True while sendEmailVerification() is in flight.
  bool _emailSending = false;

  /// True after a verification email was sent this session — changes CTA copy
  /// from "Tap to send" to "Check your inbox — tap to resend".
  bool _emailJustSent = false;

  /// Seconds remaining on the client-side resend cooldown.
  /// Prevents spam-tapping that triggers Firebase too-many-requests.
  /// Starts at 60 after a successful send, or after a too-many-requests error.
  int _emailCooldownSeconds = 0;
  Timer? _cooldownTimer;

  /// Current OS-level location permission status, refreshed on screen open
  /// and on app resume so the chip stays in sync with what the user toggled
  /// in system Settings.  Null while the very first read is in flight.
  LocationStatus? _locationStatus;

  /// Same shape as [_locationStatus] but for camera permission.  Mirrors the
  /// LocationService pattern so the chip and tap behaviour stay consistent
  /// with what live verification does.
  CameraStatus? _cameraStatus;

  /// Photo-library permission status.  Drives the Photos row chip; updated
  /// on screen open and on app resume so it stays in sync with system
  /// Settings.  Null while the very first read is in flight.
  PhotosStatus? _photosStatus;

  /// Notifications permission status.  Drives the Notifications row chip;
  /// updated on screen open and on app resume.  Null while the very first
  /// read is in flight.
  NotificationsStatus? _notificationsStatus;

  /// True while the server-owned account deletion callable is running.
  bool _deletingAccount = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
    _refreshLocationStatus();
    _refreshCameraStatus();
    _refreshPhotosStatus();
    _refreshNotificationsStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cooldownTimer?.cancel();
    super.dispose();
  }

  /// Starts (or restarts) a countdown that disables the resend button for
  /// [seconds] seconds. Prevents rapid re-sends that trigger Firebase
  /// too-many-requests.
  void _startEmailCooldown(int seconds) {
    _cooldownTimer?.cancel();
    setState(() => _emailCooldownSeconds = seconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _emailCooldownSeconds--;
        if (_emailCooldownSeconds <= 0) {
          _emailCooldownSeconds = 0;
          t.cancel();
        }
      });
    });
  }

  /// On app resume, reload the Firebase Auth user so [emailVerified] reflects
  /// any verification the user completed outside the app (e.g. clicking the
  /// link in their inbox).  Then rebuild so the row updates immediately, and
  /// surface a confirmation snackbar if verification just flipped to true.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Re-read every permission status — the user may have just come back
      // from system Settings where they toggled any of them.
      _refreshLocationStatus();
      _refreshCameraStatus();
      _refreshPhotosStatus();
      _refreshNotificationsStatus();
      final beforeVerified =
          FirebaseAuth.instance.currentUser?.emailVerified ?? false;
      FirebaseAuth.instance.currentUser
          ?.reload()
          .then((_) {
            if (!mounted) return;
            final afterVerified =
                FirebaseAuth.instance.currentUser?.emailVerified ?? false;
            setState(() {});
            if (!beforeVerified && afterVerified) {
              debugPrint('[verifyEmail] ✅ flipped to verified on resume');
              _cooldownTimer?.cancel();
              _emailCooldownSeconds = 0;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Email verified — you\'re all set.'),
                ),
              );
            }
          })
          .catchError((Object e) {
            debugPrint('[Settings] user reload failed: $e');
            return null;
          });
    }
  }

  /// Reloads the current user and refreshes the UI.  Used by the explicit
  /// "Refresh status" action so the user can confirm a clicked link without
  /// having to background-and-foreground the app.
  Future<void> _refreshVerificationStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final before = user.emailVerified;
    debugPrint('[verifyEmail] refresh-status: before=$before');
    try {
      await user.reload();
      final fresh = FirebaseAuth.instance.currentUser;
      final after = fresh?.emailVerified ?? false;
      debugPrint('[verifyEmail] refresh-status: after=$after');
      if (!mounted) return;
      setState(() {});
      if (!before && after) {
        _cooldownTimer?.cancel();
        _emailCooldownSeconds = 0;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Email verified — you\'re all set.'),
          ),
        );
      } else if (!after) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Not verified yet. Open the link in your inbox, then try again.'),
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      debugPrint('[verifyEmail] refresh-status failed:'
          '\n  code=${e.code}'
          '\n  message=${e.message}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.code == 'network-request-failed'
                ? 'No network connection. Check your connection and try again.'
                : 'Could not refresh status (${e.code}).',
          ),
        ),
      );
    }
  }

  // ── Firestore I/O ──────────────────────────────────────────────────────────

  Future<void> _loadSettings() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _loadError = true);
      return;
    }
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      if (!mounted) return;
      setState(() => _settings = snap.exists
          ? _UserSettings.fromFirestore(snap.data()!)
          : _UserSettings());
    } catch (e) {
      debugPrint('[Settings] load failed: $e');
      if (mounted) setState(() => _loadError = true);
    }
  }

  // ── Permissions ────────────────────────────────────────────────────────────

  /// Reads the unified [LocationStatus] and stores it in [_locationStatus].
  /// Fire-and-forget — the chip renders "Checking…" until the first read
  /// completes, then updates reactively.
  Future<void> _refreshLocationStatus() async {
    final status = await LocationService.currentStatus();
    if (!mounted) return;
    setState(() => _locationStatus = status);
  }

  /// Tap action on the Location row.  Three branches:
  ///
  ///   • [LocationStatus.requestable]      — present the OS prompt in-app.
  ///                                         This is the path that avoids the
  ///                                         iOS Settings dead-end where the
  ///                                         per-app Location row doesn't yet
  ///                                         exist.
  ///   • [LocationStatus.blockedForever]
  ///   • [LocationStatus.servicesDisabled] — open system Settings.  Recovery
  ///                                         from these states is not
  ///                                         possible from inside the app.
  ///   • [LocationStatus.granted]          — already on; tap is a no-op
  ///                                         (row is non-tappable in this
  ///                                         state — see _buildLocationRow).
  Future<void> _onLocationRowTap() async {
    final status = _locationStatus;
    if (status == null) return;
    switch (status) {
      case LocationStatus.requestable:
        final next = await LocationService.requestIfNeeded();
        if (!mounted) return;
        setState(() => _locationStatus = next);
      case LocationStatus.blockedForever:
      case LocationStatus.servicesDisabled:
        await LocationService.openSettings();
      case LocationStatus.granted:
        break;
    }
  }

  /// Reads the unified [CameraStatus] and stores it in [_cameraStatus].
  /// Same fire-and-forget pattern as [_refreshLocationStatus].
  Future<void> _refreshCameraStatus() async {
    final status = await CameraPermissionService.currentStatus();
    if (!mounted) return;
    setState(() => _cameraStatus = status);
  }

  /// Tap action on the Camera row.  Mirrors [_onLocationRowTap]:
  ///
  ///   • [CameraStatus.requestable]    — present the OS prompt in-app, same
  ///                                     dead-end fix as Location.
  ///   • [CameraStatus.blockedForever] — open system Settings.
  ///   • [CameraStatus.granted]        — no-op (row non-tappable).
  ///   • [CameraStatus.unavailable]    — no-op (row non-tappable; the chip
  ///                                     just communicates that camera APIs
  ///                                     don't apply on this platform).
  Future<void> _onCameraRowTap() async {
    final status = _cameraStatus;
    if (status == null) return;
    switch (status) {
      case CameraStatus.requestable:
        final next = await CameraPermissionService.requestIfNeeded();
        if (!mounted) return;
        setState(() => _cameraStatus = next);
      case CameraStatus.blockedForever:
        await CameraPermissionService.openSettings();
      case CameraStatus.granted:
      case CameraStatus.unavailable:
        break;
    }
  }

  /// Reads the unified [PhotosStatus] and stores it in [_photosStatus].
  Future<void> _refreshPhotosStatus() async {
    final status = await PhotosPermissionService.currentStatus();
    if (!mounted) return;
    setState(() => _photosStatus = status);
  }

  /// Tap action on the Photos row.
  ///
  ///   • [PhotosStatus.requestable]    — present the OS prompt in-app.
  ///   • [PhotosStatus.limited]
  ///   • [PhotosStatus.blockedForever] — open system Settings.  iOS does
  ///                                     not let an app re-prompt to lift
  ///                                     a "Selected Photos" choice or a
  ///                                     denial; system Settings is the
  ///                                     only path forward.
  ///   • [PhotosStatus.granted]
  ///   • [PhotosStatus.unavailable]    — non-tappable (handled at the row
  ///                                     level via tappable=false).
  Future<void> _onPhotosRowTap() async {
    final status = _photosStatus;
    if (status == null) return;
    switch (status) {
      case PhotosStatus.requestable:
        final next = await PhotosPermissionService.requestIfNeeded();
        if (!mounted) return;
        setState(() => _photosStatus = next);
      case PhotosStatus.limited:
      case PhotosStatus.blockedForever:
        await PhotosPermissionService.openSettings();
      case PhotosStatus.granted:
      case PhotosStatus.unavailable:
        break;
    }
  }

  /// Reads the unified [NotificationsStatus] and stores it in
  /// [_notificationsStatus].
  Future<void> _refreshNotificationsStatus() async {
    final status = await NotificationsPermissionService.currentStatus();
    if (!mounted) return;
    setState(() => _notificationsStatus = status);
  }

  /// Tap action on the Notifications row.  Same branching as Camera.
  Future<void> _onNotificationsRowTap() async {
    final status = _notificationsStatus;
    if (status == null) return;
    switch (status) {
      case NotificationsStatus.requestable:
        final next = await NotificationsPermissionService.requestIfNeeded();
        if (!mounted) return;
        setState(() => _notificationsStatus = next);
      case NotificationsStatus.blockedForever:
        await NotificationsPermissionService.openSettings();
      case NotificationsStatus.granted:
      case NotificationsStatus.unavailable:
        break;
    }
  }

  /// Optimistic single-field persist.  Shows a snackbar only on write failure.
  void _save(String field, dynamic value) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .update({field: value}).catchError((Object e) {
      debugPrint('[Settings] save $field failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save. Please try again.')),
        );
      }
    });
  }

  // ── Email verification ─────────────────────────────────────────────────────

  /// Sends a Firebase verification email to the current user's address.
  ///
  /// Guards:
  ///   • Already verified → no-op (button should be hidden by then, but safe).
  ///   • Already sending → no-op (prevents double-tap).
  ///
  /// On success: sets [_emailJustSent] so subtitle changes to "Check your
  /// inbox — tap to resend" until the screen is disposed or email is verified.
  /// On failure: shows a snackbar; does not set [_emailJustSent].
  Future<void> _sendVerificationEmail() async {
    final user = FirebaseAuth.instance.currentUser;

    // ── Pre-flight diagnostics ─────────────────────────────────────────────
    debugPrint('[verifyEmail] pre-flight:'
        '\n  uid=${user?.uid}'
        '\n  email=${user?.email}'
        '\n  emailVerified=${user?.emailVerified}'
        '\n  isAnonymous=${user?.isAnonymous}');

    if (user == null || user.emailVerified || _emailSending) return;

    if (user.email == null || user.email!.isEmpty) {
      debugPrint('[verifyEmail] no email address on account — cannot send');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No email address found on your account.'),
          ),
        );
      }
      return;
    }

    setState(() => _emailSending = true);

    try {
      // Reload first so the auth token is fresh — a stale token causes
      // sendEmailVerification to fail with user-token-expired.
      await user.reload();

      // Re-read currentUser after reload: reload() can replace the instance
      // internally, making the old reference stale.
      final freshUser = FirebaseAuth.instance.currentUser;
      debugPrint('[verifyEmail] after reload:'
          '\n  freshUser=${freshUser?.uid}'
          '\n  emailVerified=${freshUser?.emailVerified}');

      if (freshUser == null) {
        debugPrint('[verifyEmail] user is null after reload — session ended');
        if (mounted) setState(() => _emailSending = false);
        return;
      }

      if (freshUser.emailVerified) {
        // Verified while we reloaded — update UI without sending.
        debugPrint('[verifyEmail] already verified after reload');
        if (mounted) setState(() => _emailSending = false);
        return;
      }

      // Route through the Cloud Function so the verification email ships
      // from our authenticated domain via Resend instead of Firebase's
      // default `noreply@<project>.firebaseapp.com` sender, which iCloud
      // and Yahoo aggressively filter and Gmail routes to spam.
      final result = await FirebaseFunctions.instance
          .httpsCallable('sendCustomVerificationEmail')
          .call<Map<String, dynamic>>();
      debugPrint('[verifyEmail] ✅ cloud function returned ${result.data}');

      if (mounted) {
        setState(() {
          _emailSending = false;
          _emailJustSent = true;
        });
        // 60-second cooldown prevents rapid re-sends.
        _startEmailCooldown(60);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Email sent to ${freshUser.email} — check your inbox',
            ),
          ),
        );
      }
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[verifyEmail] ❌ FirebaseFunctionsException:'
          '\n  code=${e.code}'
          '\n  message=${e.message}'
          '\n  details=${e.details}');
      if (mounted) {
        setState(() => _emailSending = false);
        final msg = switch (e.code) {
          'unauthenticated' =>
            'Session expired — please sign out and sign back in.',
          'failed-precondition' =>
            'No email address found on your account.',
          'resource-exhausted' || 'unavailable' =>
            'Email service is busy. Please try again in a moment.',
          _ =>
            'Could not send verification email. Please try again.',
        };
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
    } on FirebaseAuthException catch (e) {
      // Log the exact Firebase error code so we can diagnose it.
      debugPrint('[verifyEmail] ❌ FirebaseAuthException:'
          '\n  code=${e.code}'
          '\n  message=${e.message}');
      if (mounted) {
        setState(() => _emailSending = false);
        final msg = switch (e.code) {
          'user-token-expired' || 'invalid-user-token' =>
            'Session expired — please sign out and sign back in.',
          'network-request-failed' =>
            'No network connection. Check your connection and try again.',
          _ =>
            'Could not send verification email (${e.code}). Please try again.',
        };
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
    } catch (e, st) {
      debugPrint('[verifyEmail] ❌ unexpected error: $e\n$st');
      if (mounted) {
        setState(() => _emailSending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unexpected error. Please try again.')),
        );
      }
    }
  }

  // ── Auth dialogs ───────────────────────────────────────────────────────────

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgElevated,
        title: Text('Log out?',
            style: AppTextStyles.h3.copyWith(color: AppColors.textPrimary)),
        content: Text(
          'You will need to sign back in to use Icebreaker.',
          style: AppTextStyles.bodyS,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel',
                style:
                    AppTextStyles.body.copyWith(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Log Out',
                style: AppTextStyles.body.copyWith(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      debugPrint('[Settings] signOut failed: $e');
    }
    if (mounted) context.go(AppRoutes.signIn);
  }

  Future<void> _confirmDeleteAccount() async {
    if (_deletingAccount) return;

    // Step 1 — explain consequences.
    final step1 = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgElevated,
        title: Text('Delete account?',
            style: AppTextStyles.h3.copyWith(color: AppColors.danger)),
        content: Text(
          'This permanently deletes your profile, photos, live verification '
          'selfies, messages, matches, meetup history, and account data from '
          'Icebreaker. '
          'This cannot be undone.',
          style: AppTextStyles.bodyS,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel',
                style:
                    AppTextStyles.body.copyWith(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Continue',
                style: AppTextStyles.body.copyWith(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (step1 != true) return;

    // Step 2 — final irreversible confirmation.
    if (!mounted) return;
    final step2 = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgElevated,
        title: Text('Are you sure?',
            style: AppTextStyles.h3.copyWith(color: AppColors.danger)),
        content: Text(
          'Tap "Delete Forever" to permanently close your account. '
          'There is no way to recover it after this.',
          style: AppTextStyles.bodyS,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel',
                style:
                    AppTextStyles.body.copyWith(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Delete Forever',
                style: AppTextStyles.body.copyWith(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (step2 != true) return;

    try {
      if (mounted) {
        setState(() => _deletingAccount = true);
      }

      debugPrint('[Settings] delete account: calling deleteMyAccount');
      await FirebaseFunctions.instance
          .httpsCallable('deleteMyAccount')
          .call();
      debugPrint('[Settings] delete account: deleteMyAccount succeeded');

      await FirebaseAuth.instance.signOut().catchError((Object e) {
        debugPrint('[Settings] signOut after delete failed (non-fatal): $e');
      });

      if (!mounted) return;
      context.go(AppRoutes.signIn);
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[Settings] delete account callable failed: ${e.code} ${e.message}');
      if (mounted) {
        setState(() => _deletingAccount = false);
      }
      if (!mounted) return;
      final msg = switch (e.code) {
        'unauthenticated' => 'Please sign in again before deleting your account.',
        'deadline-exceeded' =>
          'Deletion is taking longer than expected. Please try again in a minute.',
        _ => e.message ?? 'Could not delete account right now. Please try again.',
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
      return;
    } on FirebaseAuthException catch (e) {
      debugPrint('[Settings] signOut after delete failed: ${e.code}');
      if (mounted) {
        setState(() => _deletingAccount = false);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Account deleted, but sign-out failed (${e.code}).')),
        );
      }
      return;
    } catch (e) {
      debugPrint('[Settings] delete account unexpected error: $e');
      if (mounted) {
        setState(() => _deletingAccount = false);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not delete account. Please try again.'),
          ),
        );
      }
      return;
    }
  }

  // ── URL launcher ───────────────────────────────────────────────────────────

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open $url')),
        );
      }
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text('Settings', style: AppTextStyles.h3),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.textSecondary, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        top: false,
        child: _buildBody(),
      ),
    );
  }

  /// Renders the Location row in the Permissions section.  The chip and tap
  /// behaviour both branch on [_locationStatus]:
  ///
  ///   granted          → "Granted" (success), row non-tappable
  ///   requestable      → "Not granted" (danger), tap → in-app OS prompt
  ///   blockedForever   → "Blocked" (danger), tap → system Settings
  ///   servicesDisabled → "Services off" (warning), tap → system Settings
  ///   null (in-flight) → "Checking…" (muted), row non-tappable
  Widget _buildLocationRow() {
    final status = _locationStatus;
    final (chipLabel, chipColor, subtitle, tappable) = switch (status) {
      LocationStatus.granted => (
          'Granted',
          AppColors.success,
          'Used to find people nearby while you\'re live',
          false,
        ),
      LocationStatus.requestable => (
          'Not granted',
          AppColors.danger,
          'Tap to allow Icebreaker to use your location',
          true,
        ),
      LocationStatus.blockedForever => (
          'Blocked',
          AppColors.danger,
          'Tap to open system Settings and re-enable',
          true,
        ),
      LocationStatus.servicesDisabled => (
          'Services off',
          AppColors.warning,
          'Location Services are off device-wide. Tap to open Settings',
          true,
        ),
      null => ('Checking…', AppColors.textMuted, null, false),
    };

    return _SettingsRow(
      icon: Icons.location_on_outlined,
      iconColor: status == LocationStatus.granted
          ? AppColors.success
          : AppColors.brandCyan,
      label: 'Location',
      subtitle: subtitle,
      onTap: tappable ? _onLocationRowTap : null,
      showChevron: tappable,
      trailing: _ValueChip(label: chipLabel, labelColor: chipColor),
    );
  }

  /// Renders the Camera row.  Same chip / tap branching as [_buildLocationRow]:
  ///
  ///   granted        → "Granted" (success), row non-tappable
  ///   requestable    → "Not granted" (danger), tap → in-app OS prompt
  ///   blockedForever → "Blocked" (danger), tap → system Settings
  ///   unavailable    → "Unavailable" (muted), row non-tappable.  Non-mobile
  ///                    platforms (web, macOS, Linux, Windows) — there is no
  ///                    permission to grant; live verification falls back to
  ///                    a photo-library path on macOS for the support account.
  ///   null           → "Checking…" (muted), row non-tappable.
  Widget _buildCameraRow() {
    final status = _cameraStatus;
    final (chipLabel, chipColor, subtitle, tappable) = switch (status) {
      CameraStatus.granted => (
          'Granted',
          AppColors.success,
          'Used for Live Verification selfies',
          false,
        ),
      CameraStatus.requestable => (
          'Not granted',
          AppColors.danger,
          'Tap to allow Icebreaker to use your camera',
          true,
        ),
      CameraStatus.blockedForever => (
          'Blocked',
          AppColors.danger,
          'Tap to open system Settings and re-enable',
          true,
        ),
      CameraStatus.unavailable => (
          'Unavailable',
          AppColors.textMuted,
          'Camera is not available on this platform',
          false,
        ),
      null => ('Checking…', AppColors.textMuted, null, false),
    };

    return _SettingsRow(
      icon: Icons.photo_camera_outlined,
      iconColor: status == CameraStatus.granted
          ? AppColors.success
          : AppColors.brandCyan,
      label: 'Camera',
      subtitle: subtitle,
      onTap: tappable ? _onCameraRowTap : null,
      showChevron: tappable,
      trailing: _ValueChip(label: chipLabel, labelColor: chipColor),
    );
  }

  /// Renders the Photos row.  Same chip / tap branching as
  /// [_buildLocationRow], with an extra [PhotosStatus.limited] tier:
  ///
  ///   granted        → "Granted" (success), row non-tappable
  ///   limited        → "Limited" (warning), tap → system Settings
  ///                    (iOS-only state; the user has shared a subset of
  ///                    their library and the only way to lift it is via
  ///                    system Settings)
  ///   requestable    → "Not granted" (danger), tap → in-app OS prompt
  ///   blockedForever → "Blocked" (danger), tap → system Settings
  ///   unavailable    → "Unavailable" (muted), row non-tappable
  ///   null           → "Checking…" (muted), row non-tappable
  Widget _buildPhotosRow() {
    final status = _photosStatus;
    final (chipLabel, chipColor, subtitle, tappable) = switch (status) {
      PhotosStatus.granted => (
          'Granted',
          AppColors.success,
          'Used when you pick photos for your profile',
          false,
        ),
      PhotosStatus.limited => (
          'Limited',
          AppColors.warning,
          'You shared a subset of your library. Tap to change in Settings',
          true,
        ),
      PhotosStatus.requestable => (
          'Not granted',
          AppColors.danger,
          'Tap to allow access to your photo library',
          true,
        ),
      PhotosStatus.blockedForever => (
          'Blocked',
          AppColors.danger,
          'Tap to open system Settings and re-enable',
          true,
        ),
      PhotosStatus.unavailable => (
          'Unavailable',
          AppColors.textMuted,
          'Photo library is not available on this platform',
          false,
        ),
      null => ('Checking…', AppColors.textMuted, null, false),
    };

    return _SettingsRow(
      icon: Icons.photo_library_outlined,
      iconColor: status == PhotosStatus.granted
          ? AppColors.success
          : AppColors.brandCyan,
      label: 'Photos',
      subtitle: subtitle,
      onTap: tappable ? _onPhotosRowTap : null,
      showChevron: tappable,
      trailing: _ValueChip(label: chipLabel, labelColor: chipColor),
    );
  }

  /// Renders the Notifications row.  Same chip / tap branching as
  /// [_buildCameraRow]:
  ///
  ///   granted        → "Granted" (success), row non-tappable
  ///   requestable    → "Not granted" (danger), tap → in-app OS prompt
  ///   blockedForever → "Blocked" (danger), tap → system Settings
  ///   unavailable    → "Unavailable" (muted), row non-tappable
  ///   null           → "Checking…" (muted), row non-tappable
  Widget _buildNotificationsRow() {
    final status = _notificationsStatus;
    final (chipLabel, chipColor, subtitle, tappable) = switch (status) {
      NotificationsStatus.granted => (
          'Granted',
          AppColors.success,
          'Used for icebreakers, messages, and session alerts',
          false,
        ),
      NotificationsStatus.requestable => (
          'Not granted',
          AppColors.danger,
          'Tap to allow Icebreaker to send notifications',
          true,
        ),
      NotificationsStatus.blockedForever => (
          'Blocked',
          AppColors.danger,
          'Tap to open system Settings and re-enable',
          true,
        ),
      NotificationsStatus.unavailable => (
          'Unavailable',
          AppColors.textMuted,
          'Notifications are not available on this platform',
          false,
        ),
      null => ('Checking…', AppColors.textMuted, null, false),
    };

    return _SettingsRow(
      icon: Icons.notifications_active_outlined,
      iconColor: status == NotificationsStatus.granted
          ? AppColors.success
          : AppColors.brandCyan,
      label: 'Notifications',
      subtitle: subtitle,
      onTap: tappable ? _onNotificationsRowTap : null,
      showChevron: tappable,
      trailing: _ValueChip(label: chipLabel, labelColor: chipColor),
    );
  }

  Widget _buildBody() {
    if (_loadError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Could not load settings', style: AppTextStyles.bodyS),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () {
                setState(() => _loadError = false);
                _loadSettings();
              },
              child: Text('Retry',
                  style:
                      AppTextStyles.body.copyWith(color: AppColors.brandCyan)),
            ),
          ],
        ),
      );
    }

    if (_settings == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.brandPink),
      );
    }

    final s = _settings!;

    // Verification status from FirebaseAuth — read-only, cannot be forged.
    final currentUser = FirebaseAuth.instance.currentUser;
    final emailVerified = currentUser?.emailVerified ?? false;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 48),
      children: [
        // ── Account ─────────────────────────────────────────────────────────
        const _SectionHeader(title: 'Account'),
        _SettingsCard(items: [
          _SettingsRow(
            icon: Icons.person_outline_rounded,
            iconColor: AppColors.brandPink,
            label: 'Edit Profile',
            onTap: () => context.push(AppRoutes.editProfile),
          ),
          _SettingsRow(
            icon: Icons.verified_outlined,
            iconColor: AppColors.brandCyan,
            label: 'Live Verification',
            onTap: () => context.push(AppRoutes.liveVerify, extra: false),
          ),
          _SettingsRow(
            icon: Icons.workspace_premium_outlined,
            iconColor: AppColors.warning,
            label: 'Subscription',
            onTap: () => context.push(AppRoutes.shop),
            trailing: _ValueChip(
              label: _tierLabel(s.subscriptionTier),
              labelColor: _tierColor(s.subscriptionTier),
            ),
          ),
          // Email Verification: tappable when unverified — sends a Firebase
          // verification email.  During cooldown, the row still taps through to
          // a status refresh so the user can confirm a clicked link without
          // waiting for the resend timer or backgrounding the app.  Chip
          // updates to "Verified" once the user clicks the link and returns.
          _SettingsRow(
            icon: Icons.email_outlined,
            iconColor:
                emailVerified ? AppColors.success : AppColors.brandCyan,
            label: 'Email Verification',
            subtitle: emailVerified
                ? null
                : _emailCooldownSeconds > 0
                    ? 'Check your inbox — retry in ${_emailCooldownSeconds}s · tap to refresh'
                    : _emailJustSent
                        ? 'Check your inbox — tap to resend'
                        : 'Tap to send a verification email',
            onTap: emailVerified || _emailSending
                ? null
                : _emailCooldownSeconds > 0
                    ? _refreshVerificationStatus
                    : _sendVerificationEmail,
            trailing: _emailSending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.brandCyan,
                    ),
                  )
                : _ValueChip(
                    label: emailVerified ? 'Verified' : 'Not verified',
                    labelColor:
                        emailVerified ? AppColors.success : AppColors.danger,
                  ),
          ),
        ]),
        const SizedBox(height: 24),

        // ── Discovery ────────────────────────────────────────────────────────
        // The discovery preference set (interestedIn, age range, max distance)
        // is now owned end-to-end by Edit Profile so there is exactly one
        // canonical surface for editing them.  This row is a deep-link into
        // that surface — taps land on the Preferences section.
        const _SectionHeader(title: 'Discovery'),
        _SettingsCard(items: [
          _SettingsRow(
            icon: Icons.tune_rounded,
            iconColor: AppColors.brandPurple,
            label: 'Dating preferences',
            subtitle: 'Edit who you see and who sees you',
            onTap: () => context.push(
              AppRoutes.editProfile,
              extra: 'preferences',
            ),
            trailing: const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textMuted,
            ),
          ),
        ]),
        const SizedBox(height: 24),

        // ── Privacy & Safety ─────────────────────────────────────────────────
        const _SectionHeader(title: 'Privacy & Safety'),
        _SettingsCard(items: [
          _SettingsRow(
            icon: Icons.block_rounded,
            iconColor: AppColors.danger,
            label: 'Blocked Users',
            onTap: () => context.push(AppRoutes.blockedUsers),
          ),
          _SettingsRow(
            icon: Icons.flag_outlined,
            iconColor: AppColors.warning,
            label: 'Reporting & Blocking',
            onTap: () => context.push(AppRoutes.reportingAndBlocking),
          ),
          _SettingsToggleRow(
            icon: Icons.photo_outlined,
            iconColor: AppColors.textSecondary,
            label: 'Show Photos to Matches Only',
            value: s.photosToMatchesOnly,
            onChanged: (v) {
              setState(() => s.photosToMatchesOnly = v);
              _save('photosToMatchesOnly', v);
            },
          ),
        ]),
        const SizedBox(height: 24),

        // ── Permissions ──────────────────────────────────────────────────────
        // Surfaces OS-level permission state directly so the user can see at
        // a glance whether the app has what it needs, and recover from a
        // denial without hunting through system Settings menus.  Each row
        // resolves through its own service (LocationService /
        // CameraPermissionService / PhotosPermissionService /
        // NotificationsPermissionService) so the chip stays consistent with
        // every other prompt the app surfaces.
        const _SectionHeader(title: 'Permissions'),
        _SettingsCard(items: [
          _buildLocationRow(),
          _buildCameraRow(),
          _buildPhotosRow(),
          _buildNotificationsRow(),
        ]),
        const SizedBox(height: 24),

        // ── Notifications ─────────────────────────────────────────────────────
        // Values are persisted to Firestore immediately and enforced by the
        // backend push senders for reminders, icebreakers, messages,
        // match-confirmed, and session-start alerts.
        const _SectionHeader(title: 'Notifications'),
        _SettingsCard(items: [
          // Do Not Disturb: silences chat/message push notifications while the
          // user is not live.  Auto-cleared to false when a session starts
          // (LiveSession.goLive writes doNotDisturb: false to Firestore).
          // Has no effect on discoverability — that is governed by live session
          // state only.
          _SettingsToggleRow(
            icon: Icons.do_not_disturb_on_outlined,
            iconColor: AppColors.brandPurple,
            label: 'Do Not Disturb',
            subtitle: 'Silence chats when not live',
            value: s.doNotDisturb,
            onChanged: (v) {
              setState(() => s.doNotDisturb = v);
              _save('doNotDisturb', v);
            },
          ),
          _SettingsToggleRow(
            icon: Icons.alarm_on_outlined,
            iconColor: AppColors.warning,
            label: 'Reminders',
            subtitle: 'Time-sensitive nudges before things expire',
            value: s.notifReminders,
            onChanged: (v) {
              setState(() => s.notifReminders = v);
              _save('notifReminders', v);
            },
          ),
          _SettingsToggleRow(
            icon: Icons.notifications_outlined,
            iconColor: AppColors.brandPink,
            label: 'New Icebreakers',
            value: s.notifIcebreakers,
            onChanged: (v) {
              setState(() => s.notifIcebreakers = v);
              _save('notifIcebreakers', v);
            },
          ),
          _SettingsToggleRow(
            icon: Icons.chat_bubble_outline_rounded,
            iconColor: AppColors.brandCyan,
            label: 'New Messages',
            value: s.notifMessages,
            onChanged: (v) {
              setState(() => s.notifMessages = v);
              _save('notifMessages', v);
            },
          ),
          _SettingsToggleRow(
            icon: Icons.favorite_border_rounded,
            iconColor: AppColors.success,
            label: 'Match Confirmed',
            value: s.notifMatchConfirmed,
            onChanged: (v) {
              setState(() => s.notifMatchConfirmed = v);
              _save('notifMatchConfirmed', v);
            },
          ),
          _SettingsToggleRow(
            icon: Icons.bolt_outlined,
            iconColor: AppColors.warning,
            label: 'Session Starting',
            value: s.notifSession,
            onChanged: (v) {
              setState(() => s.notifSession = v);
              _save('notifSession', v);
            },
          ),
        ]),
        const SizedBox(height: 24),

        // ── Help & Legal ──────────────────────────────────────────────────────
        const _SectionHeader(title: 'Help & Legal'),
        _SettingsCard(items: [
          _SettingsRow(
            icon: Icons.help_outline_rounded,
            iconColor: AppColors.brandCyan,
            label: 'Help Center',
            onTap: () => _launchUrl('https://icebreakerlive.com/support.html'),
          ),
          _SettingsRow(
            icon: Icons.privacy_tip_outlined,
            iconColor: AppColors.textSecondary,
            label: 'Privacy Policy',
            onTap: () => _launchUrl('https://icebreakerlive.com/privacy.html'),
          ),
          _SettingsRow(
            icon: Icons.description_outlined,
            iconColor: AppColors.textSecondary,
            label: 'Terms of Service',
            onTap: () => _launchUrl('https://icebreakerlive.com/terms.html'),
          ),
          _SettingsRow(
            icon: Icons.delete_forever_outlined,
            iconColor: AppColors.danger,
            label: 'Account Deletion Help',
            onTap: () => _launchUrl('https://icebreakerlive.com/delete-account.html'),
          ),
          _SettingsRow(
            icon: Icons.info_outline_rounded,
            iconColor: AppColors.textMuted,
            label: 'App Version',
            onTap: null,
            showChevron: false,
            trailing: Text('1.0.0', style: AppTextStyles.bodyS),
          ),
        ]),
        const SizedBox(height: 24),

        // ── Danger zone ───────────────────────────────────────────────────────
        _SettingsCard(items: [
          _SettingsRow(
            icon: Icons.logout_rounded,
            iconColor: AppColors.danger,
            label: 'Log Out',
            labelColor: AppColors.danger,
            onTap: _confirmSignOut,
          ),
          _SettingsRow(
            icon: Icons.delete_outline_rounded,
            iconColor: AppColors.danger,
            label: _deletingAccount ? 'Deleting Account…' : 'Delete Account',
            labelColor: AppColors.danger,
            onTap: _deletingAccount ? null : _confirmDeleteAccount,
            showChevron: false,
          ),
        ]),
      ],
    );
  }
}

// ─── Layout widgets ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(title.toUpperCase(), style: AppTextStyles.overline),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.items});
  final List<Widget> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            items[i],
            if (i < items.length - 1)
              const Divider(
                height: 1,
                indent: 62,
                endIndent: 0,
                color: AppColors.divider,
              ),
          ],
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    this.labelColor,
    this.subtitle,
    this.onTap,
    this.trailing,
    this.showChevron = true,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final Color? labelColor;

  /// Optional secondary line below the label (e.g. "Coming soon").
  final String? subtitle;

  final VoidCallback? onTap;
  final Widget? trailing;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            _IconBox(icon: icon, color: iconColor),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: AppTextStyles.body.copyWith(
                      fontWeight: FontWeight.w600,
                      color: labelColor ?? AppColors.textPrimary,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: AppTextStyles.caption),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing!,
            ],
            if (showChevron && onTap != null) ...[
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textMuted,
                size: 20,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Controlled toggle row — parent owns the value and calls setState on change.
class _SettingsToggleRow extends StatelessWidget {
  const _SettingsToggleRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          _IconBox(icon: icon, color: iconColor),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style:
                      AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: AppTextStyles.caption),
                ],
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.brandPink,
            trackColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return AppColors.brandPink.withValues(alpha: 0.3);
              }
              return AppColors.divider;
            }),
          ),
        ],
      ),
    );
  }
}

class _IconBox extends StatelessWidget {
  const _IconBox({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(9),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: color, size: 18),
    );
  }
}

class _ValueChip extends StatelessWidget {
  const _ValueChip({required this.label, this.labelColor});

  final String label;
  final Color? labelColor;

  @override
  Widget build(BuildContext context) {
    final color = labelColor ?? AppColors.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: AppTextStyles.caption.copyWith(color: color),
      ),
    );
  }
}
