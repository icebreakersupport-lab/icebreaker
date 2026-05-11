import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// Unified, app-wide camera permission state.
///
/// Same shape as [LocationStatus]: collapses the underlying
/// [permission_handler] enum into the four cases the UI actually has to render
/// different branches for.
///
/// The distinction between [requestable] and [blockedForever] is what makes
/// the Settings dead-end go away on iOS: when permission has not yet been
/// explicitly denied permanently, the right action is to call
/// [CameraPermissionService.requestIfNeeded] so the OS dialog presents.
/// Punting straight to system Settings would land the user on a page where
/// no Camera row has been created for this app yet.
enum CameraStatus {
  /// Permission is granted.  Camera can be opened.
  granted,

  /// Permission has not yet been granted but can still be requested in-app.
  /// First-launch state on iOS/Android (the OS dialog has not been shown
  /// yet), and on Android also the post-tap-Deny state where the OS still
  /// allows another prompt.  UI: offer "Allow Camera".
  requestable,

  /// The user has permanently denied permission (iOS "Don't Allow" — iOS only
  /// allows a single in-app prompt, then locks), or the OS has restricted it
  /// (Screen Time / parental controls / MDM).  Re-prompting will not present
  /// the dialog.  Recovery requires a trip to system Settings.
  /// UI: offer "Open Settings".
  blockedForever,

  /// Camera is not available on this platform — non-mobile (web, macOS,
  /// Linux, Windows).  Permission_handler has no meaningful camera state on
  /// these platforms, so we collapse to a single "unavailable" branch and
  /// leave hardware fallbacks (e.g. the macOS photo-library path) to the
  /// caller.
  unavailable,
}

/// Camera permission state machine.
///
/// Mirrors [LocationService]: a non-prompting [currentStatus], a one-shot
/// prompting [requestIfNeeded], and an [openSettings] escape hatch for the
/// blocked-forever state.
///
/// Live verification and the Permissions section of Settings both go through
/// this single source of truth, so the chip in Settings and the in-flow
/// permission gate cannot disagree.
abstract final class CameraPermissionService {
  static bool get _isMobile =>
      !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  /// Returns the current permission status without prompting.
  ///
  /// On non-mobile platforms returns [CameraStatus.unavailable] — the camera
  /// permission API does not apply there and the caller should pick a
  /// platform-appropriate path (e.g. the macOS photo-library fallback) rather
  /// than asking the user to "Allow Camera".
  static Future<CameraStatus> currentStatus() async {
    if (!_isMobile) return CameraStatus.unavailable;
    try {
      final p = await Permission.camera.status;
      return _mapPermission(p);
    } catch (e) {
      debugPrint('[Camera] currentStatus failed (non-fatal): $e');
      return CameraStatus.requestable;
    }
  }

  /// Reads [currentStatus]; if it's [CameraStatus.requestable], presents the
  /// OS permission dialog and remaps to the resulting status.  Otherwise
  /// returns the current status unchanged (no-op for granted, blockedForever,
  /// or unavailable — these states cannot be moved by an in-app prompt).
  ///
  /// This is the single entry point screens should use when the user has just
  /// signaled intent to grant permission ("Allow Camera" tap, Live Verify
  /// open, retry-after-failure).
  static Future<CameraStatus> requestIfNeeded() async {
    if (!_isMobile) return CameraStatus.unavailable;
    final status = await currentStatus();
    if (status != CameraStatus.requestable) return status;
    try {
      final p = await Permission.camera.request();
      return _mapPermission(p);
    } catch (e) {
      debugPrint('[Camera] requestIfNeeded failed (non-fatal): $e');
      return status;
    }
  }

  static CameraStatus _mapPermission(PermissionStatus p) {
    if (p.isGranted || p.isLimited || p.isProvisional) {
      return CameraStatus.granted;
    }
    if (p.isPermanentlyDenied || p.isRestricted) {
      return CameraStatus.blockedForever;
    }
    return CameraStatus.requestable;
  }

  /// Opens the platform's app-settings screen so the user can grant camera
  /// permission.  Returns true on success.
  static Future<bool> openSettings() => openAppSettings();
}
