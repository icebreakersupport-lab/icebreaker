import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// Unified, app-wide photo-library permission state.
///
/// Same shape as [CameraStatus] / [LocationStatus], plus a [limited] case
/// because iOS 14+ exposes a "Selected Photos" tier that is functionally
/// distinct from full grant — we surface it as its own chip rather than
/// hiding it behind "Granted" so the user can see what they actually
/// allowed.
///
/// Note on relevance: image_picker on iOS 14+ uses PHPickerViewController,
/// which is an out-of-process picker that does NOT require any photo-library
/// permission — the user can pick an image even when this returns
/// [requestable].  So this row is informational on the iOS happy path; it
/// only becomes load-bearing when the user has explicitly denied or limited
/// access and wants to reverse that without leaving the app.
enum PhotosStatus {
  /// Full photo-library access.  PHPicker and full-library reads both work.
  granted,

  /// iOS 14+ "Selected Photos" — only the photos the user explicitly chose
  /// in the limited-library picker are visible.  PHPicker continues to work.
  /// UI: offer "Manage" / "Allow Full Access" copy.
  limited,

  /// Permission has not yet been granted but can still be requested in-app.
  /// First-launch state on iOS/Android (the OS dialog has not been shown
  /// yet).  UI: offer "Allow Photos".
  requestable,

  /// The user has permanently denied permission (iOS "Don't Allow") or the
  /// OS has restricted it (Screen Time / parental controls / MDM).
  /// Re-prompting will not present the dialog.  Recovery requires a trip
  /// to system Settings.  UI: offer "Open Settings".
  blockedForever,

  /// Photo-library is not available on this platform — non-mobile (web,
  /// Linux, Windows).  Permission_handler has no meaningful photos state on
  /// these platforms, so we collapse to a single "unavailable" branch.
  unavailable,
}

/// Photo-library permission state machine.
///
/// Mirrors [CameraPermissionService]: a non-prompting [currentStatus], a
/// one-shot prompting [requestIfNeeded], and an [openSettings] escape
/// hatch for the blocked-forever state.
abstract final class PhotosPermissionService {
  static bool get _isMobile =>
      !kIsWeb && (Platform.isIOS || Platform.isAndroid || Platform.isMacOS);

  /// Returns the current permission status without prompting.
  ///
  /// On non-mobile platforms returns [PhotosStatus.unavailable].
  static Future<PhotosStatus> currentStatus() async {
    if (!_isMobile) return PhotosStatus.unavailable;
    try {
      final p = await Permission.photos.status;
      return _mapPermission(p);
    } catch (e) {
      debugPrint('[Photos] currentStatus failed (non-fatal): $e');
      return PhotosStatus.requestable;
    }
  }

  /// Reads [currentStatus]; if it's [PhotosStatus.requestable], presents the
  /// OS permission dialog and remaps to the resulting status.  Otherwise
  /// returns the current status unchanged (no-op for granted, limited,
  /// blockedForever, or unavailable).
  static Future<PhotosStatus> requestIfNeeded() async {
    if (!_isMobile) return PhotosStatus.unavailable;
    final status = await currentStatus();
    if (status != PhotosStatus.requestable) return status;
    try {
      final p = await Permission.photos.request();
      return _mapPermission(p);
    } catch (e) {
      debugPrint('[Photos] requestIfNeeded failed (non-fatal): $e');
      return status;
    }
  }

  static PhotosStatus _mapPermission(PermissionStatus p) {
    if (p.isGranted || p.isProvisional) return PhotosStatus.granted;
    if (p.isLimited) return PhotosStatus.limited;
    if (p.isPermanentlyDenied || p.isRestricted) {
      return PhotosStatus.blockedForever;
    }
    return PhotosStatus.requestable;
  }

  /// Opens the platform's app-settings screen so the user can change photo
  /// permission.  Returns true on success.
  static Future<bool> openSettings() => openAppSettings();
}
