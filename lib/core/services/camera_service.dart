import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// Coarse camera permission state used by [LiveVerificationScreen] to pick
/// which UI branch to render (preview / blocked / permission-denied).
///
/// The screen calls `package:camera`'s `availableCameras()` and
/// `CameraController.initialize()` directly — this enum is the layer that
/// translates platform-specific errors into a discrete state the UI can
/// switch on without leaking platform_channel exception types.
enum CameraStatus {
  /// Permission granted and at least one camera is available.  The
  /// preview view is safe to render.
  granted,

  /// Permission has been permanently denied — only the system Settings
  /// can recover.  The UI shows an "Open Settings" CTA.
  blockedForever,

  /// Permission hasn't been determined yet, or was denied non-permanently.
  /// The UI can re-prompt.
  requestable,
}

/// Static helpers for camera permission state — kept separate from the bare
/// [CameraStatus] enum so screens can import either independently.
abstract final class CameraPermissionService {
  /// Returns the current camera permission state without prompting.  Used
  /// when the user returns from system Settings to detect whether they
  /// flipped the toggle.
  static Future<CameraStatus> currentStatus() async {
    try {
      final status = await Permission.camera.status;
      return _map(status);
    } catch (e) {
      debugPrint('[CameraPermissionService] currentStatus failed: $e');
      return CameraStatus.requestable;
    }
  }

  /// Opens the platform's app-settings screen so the user can flip the
  /// camera permission manually.  Returns true if the screen was opened.
  static Future<bool> openSettings() async {
    try {
      return await openAppSettings();
    } catch (e) {
      debugPrint('[CameraPermissionService] openSettings failed: $e');
      return false;
    }
  }

  static CameraStatus _map(PermissionStatus s) {
    if (s.isGranted || s.isLimited) return CameraStatus.granted;
    if (s.isPermanentlyDenied || s.isRestricted) return CameraStatus.blockedForever;
    return CameraStatus.requestable;
  }
}
