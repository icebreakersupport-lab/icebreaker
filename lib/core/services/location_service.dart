import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Unified, app-wide location permission state.
///
/// Every screen that needs to check or act on location permission goes through
/// this enum — it collapses the underlying [LocationPermission] values plus
/// the device-wide services-enabled bit into the four cases the UI actually
/// has to render different branches for.
///
/// The distinction between [requestable] and [blockedForever] is what makes
/// the iOS "Open Settings dead-end" go away: when permission has never been
/// asked for (cold-launch state on iOS, where `Geolocator.checkPermission`
/// returns `denied` rather than `deniedForever`), the system Settings page
/// has no Location row yet.  The right action is to call
/// [LocationService.requestIfNeeded] so the OS dialog actually presents.
/// Punting straight to system Settings would land the user on a page with
/// nothing to toggle.
enum LocationStatus {
  /// Permission is granted (whileInUse or always).  Safe to read GPS.
  granted,

  /// Permission has not yet been granted but can still be requested in-app.
  /// First-launch state on iOS/Android (the OS dialog has not been shown
  /// yet), and on Android also the post-tap-Deny state where the OS still
  /// allows another prompt.  UI: offer "Allow Location".
  requestable,

  /// The user has permanently denied permission (iOS "Don't Allow", or
  /// Android "Don't ask again").  Re-prompting silently fails — the OS will
  /// not present the dialog.  Recovery requires a trip to system Settings.
  /// UI: offer "Open Settings".
  blockedForever,

  /// The device-wide Location Services switch is off.  Per-app permission
  /// state is irrelevant until the user toggles it back on in system
  /// Settings.  UI: offer "Open Settings" with copy that points at the
  /// services switch, not the per-app permission row.
  servicesDisabled,
}

/// GPS coordinate reading, location-permission state machine, geohash
/// encoding, and Haversine distance.
///
/// Used by LiveSession.goLive() to write the user's position to Firestore
/// and by NearbyScreen to filter discovery results by exact distance.
///
/// Permission API:
///   [currentStatus]       — non-prompting read of [LocationStatus]
///   [requestIfNeeded]     — prompts the OS only when state is [requestable]
///   [openSettings]        — sends the user to per-app system Settings
///
/// Geohash strategy:
///   Precision 7 cells are ~76 m × 76 m, small enough to bound a 30 m
///   discovery radius within a handful of adjacent cells.  We store at
///   precision 7 in Firestore and query by prefix to get a rough bounding
///   box, then filter client-side with exact Haversine distance.
abstract final class LocationService {
  // ── Permission state machine ─────────────────────────────────────────────

  /// True on iOS / Android.  Used to skip the services-enabled gate on
  /// web/desktop where [Geolocator.isLocationServiceEnabled] is unreliable
  /// (it returns true on the macOS simulator regardless of actual state).
  static bool get _isMobile =>
      !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  /// Returns the current permission status without prompting.
  ///
  /// Order matters: the device-wide services switch is checked first so a
  /// user who has explicitly turned Location Services off doesn't get an
  /// "Allow Location" button that will never resolve to granted.
  static Future<LocationStatus> currentStatus() async {
    try {
      if (_isMobile) {
        final servicesOn = await Geolocator.isLocationServiceEnabled();
        if (!servicesOn) return LocationStatus.servicesDisabled;
      }
      final perm = await Geolocator.checkPermission();
      return _mapPermission(perm);
    } catch (e) {
      debugPrint('[Location] currentStatus failed (non-fatal): $e');
      // Treat unknown errors as requestable — better to let the user try the
      // OS dialog than to dead-end them in Settings.
      return LocationStatus.requestable;
    }
  }

  /// Reads [currentStatus]; if it's [LocationStatus.requestable], presents
  /// the OS permission dialog and remaps to the resulting status.  Otherwise
  /// returns the current status unchanged (no-op for granted, blockedForever,
  /// or servicesDisabled — these states cannot be moved by an in-app prompt).
  ///
  /// This is the single entry point screens should use when the user has
  /// just signaled intent to grant permission ("Allow Location" tap, Go Live
  /// tap, retry-after-failure).
  static Future<LocationStatus> requestIfNeeded() async {
    final status = await currentStatus();
    if (status != LocationStatus.requestable) return status;
    try {
      final perm = await Geolocator.requestPermission();
      // After a request, re-check the services bit too — the user may have
      // toggled it off in Settings between currentStatus() and now.
      if (_isMobile) {
        final servicesOn = await Geolocator.isLocationServiceEnabled();
        if (!servicesOn) return LocationStatus.servicesDisabled;
      }
      return _mapPermission(perm);
    } catch (e) {
      debugPrint('[Location] requestIfNeeded failed (non-fatal): $e');
      return status;
    }
  }

  /// Maps the geolocator-level enum to our [LocationStatus] without touching
  /// the services-enabled bit (caller does that gate).
  static LocationStatus _mapPermission(LocationPermission perm) {
    switch (perm) {
      case LocationPermission.always:
      case LocationPermission.whileInUse:
        return LocationStatus.granted;
      case LocationPermission.denied:
      case LocationPermission.unableToDetermine:
        return LocationStatus.requestable;
      case LocationPermission.deniedForever:
        return LocationStatus.blockedForever;
    }
  }

  /// Opens the platform's app-settings screen so the user can grant location
  /// permission or toggle Location Services.  Returns true on success.
  static Future<bool> openSettings() => Geolocator.openAppSettings();

  // ── GPS ──────────────────────────────────────────────────────────────────

  /// Returns the device's current position, or null if permission is not
  /// granted, location services are disabled, or any platform error occurs.
  ///
  /// Routes through [requestIfNeeded] so the OS dialog presents on the very
  /// first call — the same single source of truth that the UI uses.  Callers
  /// that need to distinguish "permission issue" from "GPS timed out" should
  /// call [currentStatus] after a null return.
  static Future<Position?> getPosition() async {
    try {
      final status = await requestIfNeeded();
      if (status != LocationStatus.granted) {
        debugPrint('[Location] getPosition aborted — status=$status');
        return null;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      debugPrint(
          '[Location] position: ${pos.latitude}, ${pos.longitude} ±${pos.accuracy}m');
      return pos;
    } catch (e) {
      debugPrint('[Location] getPosition failed (non-fatal): $e');
      return null;
    }
  }

  // ── Geohash ───────────────────────────────────────────────────────────────────

  static const String _base32 = '0123456789bcdefghjkmnpqrstuvwxyz';

  /// Encodes [lat]/[lng] to a geohash string of [precision] characters.
  /// Default precision 7 → ~76 m × 76 m cells.
  static String encode(double lat, double lng, {int precision = 7}) {
    var minLat = -90.0;
    var maxLat = 90.0;
    var minLng = -180.0;
    var maxLng = 180.0;

    final buffer = StringBuffer();
    var bits = 0;
    var hashValue = 0;
    var isEven = true;

    while (buffer.length < precision) {
      final mid = isEven ? (minLng + maxLng) / 2 : (minLat + maxLat) / 2;
      final val = isEven ? lng : lat;

      if (val >= mid) {
        hashValue = (hashValue << 1) + 1;
        if (isEven) {
          minLng = mid;
        } else {
          minLat = mid;
        }
      } else {
        hashValue = hashValue << 1;
        if (isEven) {
          maxLng = mid;
        } else {
          maxLat = mid;
        }
      }

      isEven = !isEven;
      bits++;
      if (bits == 5) {
        buffer.write(_base32[hashValue]);
        bits = 0;
        hashValue = 0;
      }
    }

    return buffer.toString();
  }

  /// Returns the 9 geohashes that cover the query region (current cell + 8
  /// neighbors) for a given position.  Querying all 9 ensures that users
  /// near cell boundaries are not missed.
  ///
  /// Neighbor computation uses the known inter-character adjacency tables for
  /// the base-32 geohash encoding.
  static List<String> queryHashes(double lat, double lng,
      {int precision = 7}) {
    final center = encode(lat, lng, precision: precision);
    final neighbors = _neighbors(center);
    return [center, ...neighbors];
  }

  // ── Haversine distance ────────────────────────────────────────────────────────

  /// Straight-line distance in metres between two coordinates.
  static double distanceMeters(
      double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0; // Earth radius in metres
    final phi1 = lat1 * math.pi / 180;
    final phi2 = lat2 * math.pi / 180;
    final dPhi = (lat2 - lat1) * math.pi / 180;
    final dLambda = (lng2 - lng1) * math.pi / 180;

    final a = math.sin(dPhi / 2) * math.sin(dPhi / 2) +
        math.cos(phi1) *
            math.cos(phi2) *
            math.sin(dLambda / 2) *
            math.sin(dLambda / 2);

    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  // ── Neighbor computation ──────────────────────────────────────────────────────

  // Compute neighbors by adjusting lat/lng
  // slightly in each cardinal direction, then encode.  Avoids the complex
  // base-32 adjacency table and handles all edge cases correctly.
  static List<String> _neighbors(String hash) {
    // Decode center of the cell back to lat/lng, offset by a fraction of the
    // cell size in each direction, then re-encode.
    final decoded = _decode(hash);
    final lat = decoded[0];
    final lng = decoded[1];
    final latErr = decoded[2];
    final lngErr = decoded[3];

    final precision = hash.length;
    final result = <String>[];
    for (var dlat = -1; dlat <= 1; dlat++) {
      for (var dlng = -1; dlng <= 1; dlng++) {
        if (dlat == 0 && dlng == 0) continue; // center (already have it)
        final nLat = (lat + dlat * latErr * 2).clamp(-90.0, 90.0);
        var nLng = lng + dlng * lngErr * 2;
        // Wrap longitude
        if (nLng > 180) nLng -= 360;
        if (nLng < -180) nLng += 360;
        final neighbor = encode(nLat, nLng, precision: precision);
        if (!result.contains(neighbor)) result.add(neighbor);
      }
    }
    return result;
  }

  /// Decodes a geohash back to [lat, lng, latError, lngError].
  static List<double> _decode(String hash) {
    var minLat = -90.0;
    var maxLat = 90.0;
    var minLng = -180.0;
    var maxLng = 180.0;
    var isEven = true;

    for (var i = 0; i < hash.length; i++) {
      final c = _base32.indexOf(hash[i]);
      for (var bits = 4; bits >= 0; bits--) {
        final bitN = (c >> bits) & 1;
        if (isEven) {
          final mid = (minLng + maxLng) / 2;
          if (bitN == 1) {
            minLng = mid;
          } else {
            maxLng = mid;
          }
        } else {
          final mid = (minLat + maxLat) / 2;
          if (bitN == 1) {
            minLat = mid;
          } else {
            maxLat = mid;
          }
        }
        isEven = !isEven;
      }
    }

    final lat = (minLat + maxLat) / 2;
    final lng = (minLng + maxLng) / 2;
    final latErr = (maxLat - minLat) / 2;
    final lngErr = (maxLng - minLng) / 2;
    return [lat, lng, latErr, lngErr];
  }
}
