import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// GPS coordinate reading, geohash encoding, and Haversine distance.
///
/// Used by LiveSession.goLive() to write the user's position to Firestore
/// and by NearbyScreen to filter discovery results by exact distance.
///
/// Geohash strategy:
///   Precision 7 cells are ~76 m × 76 m, small enough to bound a 30 m
///   discovery radius within a handful of adjacent cells.  We store at
///   precision 7 in Firestore and query by prefix to get a rough bounding
///   box, then filter client-side with exact Haversine distance.
abstract final class LocationService {
  // ── GPS ──────────────────────────────────────────────────────────────────────

  /// Returns the device's current position, or null if:
  ///   - permission is denied
  ///   - location services are disabled
  ///   - any other platform error occurs
  ///
  /// Non-fatal on all platforms.  macOS / web fall back gracefully.
  static Future<Position?> getPosition() async {
    try {
      // On web/desktop, service check behaves differently — skip the disabled
      // guard because Geolocator.isLocationServiceEnabled() may always return
      // true even on macOS simulator.
      if (!kIsWeb) {
        final serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) {
          debugPrint('[Location] location services disabled');
          return null;
        }
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint('[Location] permission denied');
          return null;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        debugPrint('[Location] permission permanently denied');
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

  /// Returns the current location permission status without requesting it.
  /// Used by callers to distinguish a permission denial from a GPS failure
  /// after [getPosition] returns null.
  static Future<LocationPermission> checkPermission() async {
    try {
      return await Geolocator.checkPermission();
    } catch (_) {
      return LocationPermission.denied;
    }
  }

  /// Opens the platform's app-settings screen so the user can grant location
  /// permission.  Returns true if the screen was opened successfully.
  static Future<bool> openSettings() => Geolocator.openAppSettings();

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
