import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/location_service.dart';
import '../../../core/state/live_session.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/gradient_scaffold.dart';
import '../../../shared/widgets/icebreaker_logo.dart';
import '../../../shared/widgets/pill_button.dart';
import '../widgets/nearby_focus_card.dart';
import '../widgets/nearby_about_me_card.dart';

/// Nearby tab — real Firestore-backed discovery carousel.
///
/// Discovery pipeline:
///   1. Load the user's saved maxDistanceMeters (30–60 m) from Firestore.
///   2. Load the user's blocked UIDs.
///   3. Read initial device GPS position.
///   4. Compute current geohash-7 cell + 8 neighbors.
///   5. Subscribe to one Firestore stream per cell (isLive == true within
///      the geohash prefix range).  Results are merged in [_cellSnapshots].
///   6. Subscribe to the current user's own Firestore doc to detect position
///      changes written by LiveSession's 60-second refresh timer.  When the
///      position moves to a new geohash cell, cell subscriptions are replaced.
///      Within the same cell, only [_rebuildList] is called.
///   7. [_rebuildList] applies the exact Haversine distance filter
///      (≤ _effectiveRadiusMeters) and excludes self + blocked users.
///
/// Geohash is a coarse bounding-box query helper only — the Haversine
/// distance is the authoritative filter that enforces the selected radius.
///
/// When not live: "Go Live" gate is shown.
/// When live but loading: spinner.
/// When live but empty: empty state.
class NearbyScreen extends StatefulWidget {
  const NearbyScreen({super.key});

  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends State<NearbyScreen>
    with WidgetsBindingObserver {
  late final PageController _pageController;
  int _currentIndex = 0;

  // Discovery state.
  bool _loadingDiscovery = true;
  _DiscoveryError? _discoveryError;
  List<_NearbyUser> _nearbyUsers = [];

  // UID of the signed-in user — stored so the app-resume handler can call
  // _rebuildList without re-reading FirebaseAuth.
  String? _myUid;

  // Current user's position — updated by the own-doc position stream.
  double? _myLat;
  double? _myLng;

  // User's chosen discovery radius from Settings (30–60 m).
  // Default to minimum until loaded from Firestore.
  double _effectiveRadiusMeters = AppConstants.nearbyRadiusMeters;

  // Blocked user UIDs.
  Set<String> _blockedUids = {};

  // Per-cell snapshots: geohashPrefix → { userId → userData }.
  // Replacing the entire cell map on each snapshot correctly removes users
  // who went offline between snapshots without requiring docChanges tracking.
  final Map<String, Map<String, Map<String, dynamic>>> _cellSnapshots = {};

  // Active Firestore cell stream subscriptions.
  final List<StreamSubscription> _cellSubs = [];

  // The geohash prefixes currently subscribed.
  List<String> _subscribedHashes = [];

  // Stream subscription on the current user's own doc — detects position
  // updates written by LiveSession's periodic location refresh.
  StreamSubscription<DocumentSnapshot>? _myPositionSub;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.80);
    WidgetsBinding.instance.addObserver(this);
  }

  /// On app resume, force a freshness-gate pass so stale live users are
  /// evicted immediately — even if no Firestore stream event fired and the
  /// user's own position hasn't changed since being backgrounded.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final uid = _myUid;
      if (uid != null && _cellSubs.isNotEmpty) {
        debugPrint('[Nearby] app resumed — forcing freshness rebuild');
        _rebuildList(uid);
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final isLive = LiveSessionScope.isLive(context);
    if (isLive && _cellSubs.isEmpty) {
      _startDiscovery();
    } else if (!isLive && _cellSubs.isNotEmpty) {
      _stopDiscovery();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopDiscovery();
    _pageController.dispose();
    super.dispose();
  }

  // ── Discovery lifecycle ────────────────────────────────────────────────────

  Future<void> _startDiscovery() async {
    setState(() {
      _loadingDiscovery = true;
      _discoveryError = null;
    });

    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) {
      setState(() => _loadingDiscovery = false);
      return;
    }
    _myUid = myUid;

    // Load radius preference and blocked UIDs in parallel.
    await Future.wait([
      _loadRadiusPref(myUid),
      _loadBlockedUids(myUid),
    ]);

    if (!mounted) return;

    // Get initial GPS position.  On real devices a cold GPS fix can fail on
    // the first attempt and succeed a few seconds later, so we make one
    // automatic retry after a short delay before giving up.
    Position? pos = await LocationService.getPosition();
    if (!mounted) return;

    if (pos == null) {
      debugPrint('[Nearby] GPS attempt 1 failed — retrying in 3 s');
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted) return;
      pos = await LocationService.getPosition();
      if (!mounted) return;
    }

    if (pos == null) {
      // Both attempts failed.  Distinguish permission denial from GPS
      // unavailability so we can show the right error state and action.
      final permission = await LocationService.checkPermission();
      final isPermissionIssue =
          permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever ||
          permission == LocationPermission.unableToDetermine;
      debugPrint('[Nearby] GPS failed — permission=$permission '
          'isPermissionIssue=$isPermissionIssue');
      if (!mounted) return;
      setState(() {
        _loadingDiscovery = false;
        _discoveryError = isPermissionIssue
            ? _DiscoveryError.permissionDenied
            : _DiscoveryError.gpsFailed;
      });
      return;
    }

    _myLat = pos.latitude;
    _myLng = pos.longitude;

    // Subscribe to geohash cells.
    final hashes = LocationService.queryHashes(pos.latitude, pos.longitude);
    _subscribeCells(myUid, hashes);

    // Subscribe to own position updates (written every 60 s by LiveSession).
    _startPositionTracking(myUid);

    setState(() => _loadingDiscovery = false);
  }

  Future<void> _loadRadiusPref(String myUid) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(myUid)
          .get();
      if (doc.exists) {
        final raw =
            (doc.data()?['maxDistanceMeters'] as num?)?.toDouble();
        if (raw != null) {
          _effectiveRadiusMeters = raw.clamp(
              AppConstants.nearbyRadiusMeters, 60.0);
          debugPrint(
              '[Nearby] effectiveRadius=$_effectiveRadiusMeters m');
        }
      }
    } catch (e) {
      debugPrint('[Nearby] radius pref load failed (non-fatal): $e');
    }
  }

  Future<void> _loadBlockedUids(String myUid) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(myUid)
          .collection('blockedUsers')
          .get();
      _blockedUids = snap.docs.map((d) => d.id).toSet();
      debugPrint('[Nearby] ${_blockedUids.length} blocked UIDs loaded');
    } catch (e) {
      debugPrint('[Nearby] blocked UIDs load failed (non-fatal): $e');
    }
  }

  /// Opens one Firestore snapshot stream per geohash cell prefix.
  /// Each stream result completely replaces that cell's entry in
  /// [_cellSnapshots], which correctly handles users going offline.
  void _subscribeCells(String myUid, List<String> hashes) {
    for (final sub in _cellSubs) {
      sub.cancel();
    }
    _cellSubs.clear();
    _subscribedHashes = hashes;

    debugPrint('[Nearby] subscribing to ${hashes.length} cells: $hashes');

    final db = FirebaseFirestore.instance;
    for (final hash in hashes) {
      final sub = db
          .collection('users')
          .where('isLive', isEqualTo: true)
          .where('geohash', isGreaterThanOrEqualTo: hash)
          .where('geohash', isLessThan: '$hash~')
          .snapshots()
          .listen((snap) {
        _cellSnapshots[hash] = {
          for (final doc in snap.docs) doc.id: doc.data(),
        };
        if (mounted) _rebuildList(myUid);
      });
      _cellSubs.add(sub);
    }
  }

  /// Listens to the current user's own Firestore doc for latitude/longitude
  /// updates written by LiveSession's periodic location refresh (every 60 s).
  ///
  /// When position changes:
  ///   - Updates [_myLat] and [_myLng].
  ///   - If the new geohash cells differ, cancels old cell subscriptions
  ///     and opens new ones (handles moving to a new physical area).
  ///   - If still in the same cells, just re-runs [_rebuildList] with the
  ///     updated coordinates (closer/farther users recalculated by Haversine).
  void _startPositionTracking(String myUid) {
    _myPositionSub?.cancel();
    _myPositionSub = FirebaseFirestore.instance
        .collection('users')
        .doc(myUid)
        .snapshots()
        .listen((snap) {
      if (!snap.exists || !mounted) return;
      final data = snap.data()!;
      final lat = (data['latitude'] as num?)?.toDouble();
      final lng = (data['longitude'] as num?)?.toDouble();

      // Skip if position is absent or unchanged.
      if (lat == null || lng == null) return;
      if (lat == _myLat && lng == _myLng) return;

      _myLat = lat;
      _myLng = lng;
      debugPrint('[Nearby] position updated: $lat, $lng');

      final newHashes = LocationService.queryHashes(lat, lng);
      final hashesChanged =
          newHashes.length != _subscribedHashes.length ||
          !newHashes.toSet().containsAll(_subscribedHashes);

      if (hashesChanged) {
        // User moved to a new geohash cell — refresh cell subscriptions.
        debugPrint('[Nearby] moved to new cells — resubscribing');
        _cellSnapshots.clear();
        _subscribeCells(myUid, newHashes);
      } else {
        // Same cells — Haversine filter recomputed with new coordinates.
        _rebuildList(myUid);
      }
    });
  }

  /// Merges all cell snapshots, applies filters, and updates [_nearbyUsers].
  void _rebuildList(String myUid) {
    final lat = _myLat;
    final lng = _myLng;

    // Flatten all cells, deduplicating by uid (a user near a cell boundary
    // can appear in multiple adjacent cell streams).
    final merged = <String, Map<String, dynamic>>{};
    for (final cell in _cellSnapshots.values) {
      merged.addAll(cell);
    }

    final users = merged.entries
        .where((e) {
          final uid = e.key;
          final data = e.value;

          if (uid == myUid) return false;
          if (_blockedUids.contains(uid)) return false;

          final uLat = (data['latitude'] as num?)?.toDouble();
          final uLng = (data['longitude'] as num?)?.toDouble();
          if (uLat == null || uLng == null || lat == null || lng == null) {
            return false;
          }

          // Freshness gate: skip users whose location has not been updated
          // within locationStaleThresholdSeconds (120 s).  A null timestamp
          // means the field was never written — treat as stale.
          final updatedAt =
              (data['locationUpdatedAt'] as Timestamp?)?.toDate();
          if (updatedAt == null) {
            debugPrint('[Nearby] skipping live doc $uid — locationUpdatedAt missing');
            return false;
          }
          final age = DateTime.now().difference(updatedAt).inSeconds;
          if (age > AppConstants.locationStaleThresholdSeconds) {
            debugPrint('[Nearby] skipping live doc $uid — location stale (${age}s old)');
            return false;
          }

          // Haversine is the authoritative distance gate.
          // Geohash is only the coarse bounding-box query helper.
          final distance =
              LocationService.distanceMeters(lat, lng, uLat, uLng);
          return distance <= _effectiveRadiusMeters;
        })
        .map((e) => _NearbyUser.fromFirestore(e.key, e.value))
        .whereType<_NearbyUser>()
        .toList();

    // Sort closest first.
    if (lat != null && lng != null) {
      users.sort((a, b) {
        final da =
            LocationService.distanceMeters(lat, lng, a.lat, a.lng);
        final db =
            LocationService.distanceMeters(lat, lng, b.lat, b.lng);
        return da.compareTo(db);
      });
    }

    setState(() {
      _nearbyUsers = users;
      if (_currentIndex >= _nearbyUsers.length && _nearbyUsers.isNotEmpty) {
        _currentIndex = _nearbyUsers.length - 1;
        if (_pageController.hasClients) {
          _pageController.jumpToPage(_currentIndex);
        }
      }
    });
  }

  void _stopDiscovery() {
    _myPositionSub?.cancel();
    _myPositionSub = null;
    for (final sub in _cellSubs) {
      sub.cancel();
    }
    _cellSubs.clear();
    _cellSnapshots.clear();
    _subscribedHashes = [];
    _nearbyUsers = [];
    _discoveryError = null;
    _myUid = null;
    _myLat = null;
    _myLng = null;
  }

  // ── Block ─────────────────────────────────────────────────────────────────

  Future<void> _blockUser(_NearbyUser user) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // Optimistic removal.
    setState(() {
      _blockedUids.add(user.id);
      _nearbyUsers.removeWhere((u) => u.id == user.id);
      if (_nearbyUsers.isNotEmpty) {
        _currentIndex = _currentIndex.clamp(0, _nearbyUsers.length - 1);
        if (_pageController.hasClients) {
          _pageController.jumpToPage(_currentIndex);
        }
      }
    });
    // Also remove from merged buffer so it won't reappear on next rebuild.
    for (final cell in _cellSnapshots.values) {
      cell.remove(user.id);
    }

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('blockedUsers')
          .doc(user.id)
          .set({
        'blockedAt': FieldValue.serverTimestamp(),
        'displayName': user.firstName,
        'photoUrl': user.photoUrl,
      });
      debugPrint('[Block] blocked ${user.id} (${user.firstName})');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${user.firstName} has been blocked.'),
            backgroundColor: AppColors.bgElevated,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } catch (e) {
      debugPrint('[Block] Firestore write failed (non-fatal): $e');
    }
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  void _navigateSendIcebreaker(_NearbyUser user) {
    final session = LiveSessionScope.of(context);
    if (session.icebreakerCredits <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No Icebreakers left — visit the Shop to get more.',
            style: AppTextStyles.bodyS.copyWith(color: Colors.white),
          ),
          backgroundColor: AppColors.bgElevated,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: 'Shop',
            textColor: AppColors.brandCyan,
            onPressed: () => context.push(AppRoutes.shop),
          ),
        ),
      );
      return;
    }

    context.push(
      AppRoutes.sendIcebreaker,
      extra: {
        'recipientId': user.id,
        'firstName': user.firstName,
        'age': user.age,
        'photoUrl': user.photoUrl,
        'bio': user.bio,
      },
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: _buildAppBar(),
      body: SafeArea(
        top: false,
        child: LiveSessionScope.isLive(context)
            ? _buildDiscovery()
            : _buildNotLiveGate(),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      title: Text('Nearby', style: AppTextStyles.h3),
      actions: [
        IconButton(
          icon: const Icon(Icons.tune_rounded,
              color: AppColors.textSecondary),
          onPressed: () {
            // TODO: open preference filter sheet
          },
        ),
      ],
    );
  }

  // ── Discovery layout ──────────────────────────────────────────────────────

  Widget _buildDiscovery() {
    if (_loadingDiscovery) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.brandPink),
      );
    }

    if (_discoveryError != null) return _buildLocationErrorState(_discoveryError!);

    if (_nearbyUsers.isEmpty) return _buildEmptyState();

    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            clipBehavior: Clip.none,
            itemCount: _nearbyUsers.length,
            onPageChanged: (i) => setState(() => _currentIndex = i),
            itemBuilder: (context, i) {
              final u = _nearbyUsers[i];
              return NearbyFocusCard(
                recipientId: u.id,
                firstName: u.firstName,
                age: u.age,
                photoUrl: u.photoUrl,
                isGold: u.isGold,
                isActive: i == _currentIndex,
                onSendIcebreaker: () => _navigateSendIcebreaker(u),
                onBlock: () => _blockUser(u),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.06),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: NearbyAboutMeCard(
              key: ValueKey(_currentIndex),
              age: _nearbyUsers[_currentIndex].age,
              hometown: _nearbyUsers[_currentIndex].hometown,
              occupation: _nearbyUsers[_currentIndex].occupation,
              height: _nearbyUsers[_currentIndex].height,
              lookingFor: _nearbyUsers[_currentIndex].lookingFor,
            ),
          ),
        ),
      ],
    );
  }

  // ── Empty / gate states ───────────────────────────────────────────────────

  Widget _buildEmptyState() {
    final radius = _effectiveRadiusMeters.toInt();
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const IcebreakerLogo(size: 72, showGlow: true),
            const SizedBox(height: 24),
            Text(
              'No one nearby right now',
              style: AppTextStyles.h3,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Check back when you\'re out —\n'
              'users only appear within $radius metres.',
              style: AppTextStyles.bodyS,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _retryDiscovery() {
    _stopDiscovery();
    _startDiscovery();
  }

  Widget _buildLocationErrorState(_DiscoveryError error) {
    final isPermission = error == _DiscoveryError.permissionDenied;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isPermission
                  ? Icons.location_off_rounded
                  : Icons.gps_off_rounded,
              color: AppColors.textMuted,
              size: 56,
            ),
            const SizedBox(height: 24),
            Text(
              isPermission
                  ? 'Location access needed'
                  : 'Could not get your location',
              style: AppTextStyles.h3,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              isPermission
                  ? 'Icebreaker needs location permission\n'
                    'to show who\'s nearby.'
                  : 'GPS timed out or is unavailable.\n'
                    'Try again when you have a signal.',
              style: AppTextStyles.bodyS,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            if (isPermission) ...[
              PillButton.primary(
                label: 'Open Settings',
                icon: Icons.settings_rounded,
                onTap: LocationService.openSettings,
                width: double.infinity,
                height: 48,
              ),
              const SizedBox(height: 12),
            ],
            PillButton.outlined(
              label: 'Retry',
              icon: Icons.refresh_rounded,
              onTap: _retryDiscovery,
              width: double.infinity,
              height: 48,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotLiveGate() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const IcebreakerLogo(size: 80, showGlow: true),
            const SizedBox(height: 28),
            Text(
              'Go Live to see\nwho\'s nearby',
              style: AppTextStyles.h2,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'You need an active Live session to\nbrowse people around you.',
              style: AppTextStyles.bodyS,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _DiscoveryError
// ─────────────────────────────────────────────────────────────────────────────

enum _DiscoveryError {
  /// Location permission is denied or permanently denied.
  /// Show "Open Settings" action.
  permissionDenied,

  /// Permission is granted but GPS timed out, returned null, or is disabled.
  /// Show "Retry" action only.
  gpsFailed,
}

// ─────────────────────────────────────────────────────────────────────────────
// _NearbyUser
// ─────────────────────────────────────────────────────────────────────────────

class _NearbyUser {
  const _NearbyUser({
    required this.id,
    required this.firstName,
    required this.age,
    required this.bio,
    required this.photoUrl,
    required this.lat,
    required this.lng,
    this.hometown,
    this.occupation,
    this.height,
    this.lookingFor,
    this.isGold = false,
  });

  final String id;
  final String firstName;
  final int age;
  final String bio;
  final String photoUrl;
  final double lat;
  final double lng;
  final String? hometown;
  final String? occupation;
  final String? height;
  final String? lookingFor;
  final bool isGold;

  /// Returns null (and logs) if the doc is missing position fields.
  /// This guards against the race window where isLive=true is written
  /// before the async GPS write completes.
  static _NearbyUser? fromFirestore(
      String uid, Map<String, dynamic> data) {
    final lat = (data['latitude'] as num?)?.toDouble();
    final lng = (data['longitude'] as num?)?.toDouble();

    if (lat == null || lng == null) {
      debugPrint('[Nearby] skipping live doc $uid — position fields missing');
      return null;
    }

    // Hometown may be a map (city + state) or a plain string.
    final hometownRaw = data['hometown'];
    String? hometown;
    if (hometownRaw is Map) {
      final city = hometownRaw['city'] as String? ?? '';
      final state = hometownRaw['stateCode'] as String? ??
          hometownRaw['state'] as String? ??
          '';
      hometown =
          [city, state].where((s) => s.isNotEmpty).join(', ');
    } else if (hometownRaw is String && hometownRaw.isNotEmpty) {
      hometown = hometownRaw;
    }

    return _NearbyUser(
      id: uid,
      firstName: (data['firstName'] as String?) ?? 'Someone',
      age: (data['age'] as num?)?.toInt() ?? 0,
      bio: (data['bio'] as String?) ?? '',
      photoUrl: (data['photoUrl'] as String?) ?? '',
      lat: lat,
      lng: lng,
      hometown: hometown,
      occupation: data['occupation'] as String?,
      height: data['height'] as String?,
      lookingFor: data['lookingFor'] as String?,
      isGold: (data['plan'] as String?) == 'gold',
    );
  }
}
