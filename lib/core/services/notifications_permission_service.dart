import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// Unified, app-wide notifications permission state.
///
/// Same shape as [CameraStatus] / [LocationStatus]: collapses the
/// underlying [permission_handler] enum into the four cases the UI has to
/// render different branches for.
///
/// FCM remains the actual transport — see `lib/app.dart` where
/// `FirebaseMessaging.requestPermission` is called at startup.  This
/// service is the single source of truth for the Settings chip and for
/// mid-session re-prompts; it goes through the OS layer rather than FCM
/// so the state stays consistent with what permission_handler reports
/// elsewhere in the app.
enum NotificationsStatus {
  /// Permission is granted (alert, sound, badge — or provisional, which is
  /// iOS's silent-trial mode, treated as granted because it still allows
  /// notifications to surface in the Notification Center).
  granted,

  /// Permission has not yet been granted but can still be requested
  /// in-app.  First-launch state on iOS/Android (the OS dialog has not
  /// been shown yet).  UI: offer "Allow Notifications".
  requestable,

  /// The user has permanently denied permission (iOS "Don't Allow", or
  /// Android "Block").  Re-prompting will not present the dialog.
  /// Recovery requires a trip to system Settings.  UI: offer
  /// "Open Settings".
  blockedForever,

  /// Notifications are not available on this platform — non-mobile (web,
  /// Linux, Windows).  Permission_handler has no meaningful state on
  /// these platforms, so we collapse to a single "unavailable" branch.
  unavailable,
}

/// Notifications permission state machine.
///
/// Mirrors [CameraPermissionService]: a non-prompting [currentStatus], a
/// one-shot prompting [requestIfNeeded], and an [openSettings] escape
/// hatch for the blocked-forever state.
abstract final class NotificationsPermissionService {
  static bool get _isMobile =>
      !kIsWeb && (Platform.isIOS || Platform.isAndroid || Platform.isMacOS);

  /// Returns the current permission status without prompting.
  ///
  /// On non-mobile platforms returns [NotificationsStatus.unavailable].
  static Future<NotificationsStatus> currentStatus() async {
    if (!_isMobile) return NotificationsStatus.unavailable;
    try {
      final p = await Permission.notification.status;
      return _mapPermission(p);
    } catch (e) {
      debugPrint('[Notifications] currentStatus failed (non-fatal): $e');
      return NotificationsStatus.requestable;
    }
  }

  /// Reads [currentStatus]; if it's [NotificationsStatus.requestable],
  /// presents the OS permission dialog and remaps to the resulting status.
  /// Otherwise returns the current status unchanged.
  static Future<NotificationsStatus> requestIfNeeded() async {
    if (!_isMobile) return NotificationsStatus.unavailable;
    final status = await currentStatus();
    if (status != NotificationsStatus.requestable) return status;
    try {
      final p = await Permission.notification.request();
      return _mapPermission(p);
    } catch (e) {
      debugPrint('[Notifications] requestIfNeeded failed (non-fatal): $e');
      return status;
    }
  }

  static NotificationsStatus _mapPermission(PermissionStatus p) {
    if (p.isGranted || p.isProvisional) return NotificationsStatus.granted;
    if (p.isPermanentlyDenied || p.isRestricted) {
      return NotificationsStatus.blockedForever;
    }
    return NotificationsStatus.requestable;
  }

  /// Opens the platform's app-settings screen so the user can change the
  /// notifications permission.  Returns true on success.
  static Future<bool> openSettings() => openAppSettings();
}
