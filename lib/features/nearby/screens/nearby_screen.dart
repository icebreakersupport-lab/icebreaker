import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/location_service.dart';
import '../../../core/state/live_session.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/gradient_scaffold.dart';
import '../../../shared/widgets/icebreaker_logo.dart';
import '../widgets/nearby_focus_card.dart';
import '../widgets/nearby_about_me_card.dart';

/// Nearby tab — real Firestore-backed discovery carousel.
///
/// Discovery pipeline:
///   1. Read device GPS position (once when the tab builds while live).
///   2. Compute the current geohash (precision 7) and its 8 neighbors.
///   3. Query Firestore: users where isLive==true AND geohash starts with
///      one of those 9 prefixes.  Each prefix issues one stream; results
///      are merged in-memory.
///   4. Exclude self, exclude blocked users (from the local blockedUsers
///      subcollection), exclude users outside the exact radius.
///   5. Render the carousel and About Me panel — same widgets as before.
///
/// When not live: "Go Live" gate is shown.
/// When live but loading: spinner.
/// When live but no users found: empty state.
class NearbyScreen extends StatefulWidget {
  const NearbyScreen({super.key});

  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends State<NearbyScreen> {
  late final PageController _pageController;
  int _currentIndex = 0;

  // Discovery state.
  bool _loadingDiscovery = true;
  List<_NearbyUser> _nearbyUsers = [];

  // Current user's position — set once per live session.
  double? _myLat;
  double? _myLng;

  // Blocked user UIDs — fetched once and kept in memory.
  Set<String> _blockedUids = {};

  // Active Firestore stream subscriptions — one per geohash neighbor cell.
  final List<StreamSubscription> _subs = [];

  // Buffer: userId → user doc — merged from all cell streams.
  final Map<String, Map<String, dynamic>> _userBuffer = {};

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.80);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final isLive = LiveSessionScope.isLive(context);
    if (isLive && _subs.isEmpty) {
      _startDiscovery();
    } else if (!isLive && _subs.isNotEmpty) {
      _stopDiscovery();
    }
  }

  @override
  void dispose() {
    _stopDiscovery();
    _pageController.dispose();
    super.dispose();
  }

  // ── Discovery lifecycle ────────────────────────────────────────────────────

  Future<void> _startDiscovery() async {
    setState(() => _loadingDiscovery = true);

    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) {
      setState(() => _loadingDiscovery = false);
      return;
    }

    // 1. Load blocked UIDs so they can be excluded before rendering.
    await _loadBlockedUids(myUid);

    // 2. Get GPS position.
    final pos = await LocationService.getPosition();
    if (!mounted) return;

    if (pos == null) {
      // No GPS — show empty discovery rather than crash.
      debugPrint('[Nearby] no GPS position — showing empty state');
      setState(() => _loadingDiscovery = false);
      return;
    }

    _myLat = pos.latitude;
    _myLng = pos.longitude;

    // 3. Compute query hashes (current cell + 8 neighbors).
    final hashes = LocationService.queryHashes(pos.latitude, pos.longitude);
    debugPrint('[Nearby] querying ${hashes.length} geohash cells: $hashes');

    // 4. Subscribe to one stream per cell.
    final db = FirebaseFirestore.instance;
    for (final hash in hashes) {
      final sub = db
          .collection('users')
          .where('isLive', isEqualTo: true)
          .where('geohash', isGreaterThanOrEqualTo: hash)
          .where('geohash', isLessThan: '${hash}~')
          .snapshots()
          .listen((snap) {
        for (final doc in snap.docs) {
          _userBuffer[doc.id] = doc.data();
        }
        // Removed docs (went offline mid-session) should be cleared.
        final docIds = snap.docs.map((d) => d.id).toSet();
        _userBuffer.removeWhere((id, _) =>
            LocationService.encode(
                  _userBuffer[id]?['latitude'] as double? ?? 0,
                  _userBuffer[id]?['longitude'] as double? ?? 0,
                ) ==
                hash &&
            !docIds.contains(id));
        if (mounted) _rebuildList(myUid);
      });
      _subs.add(sub);
    }

    setState(() => _loadingDiscovery = false);
  }

  Future<void> _loadBlockedUids(String myUid) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(myUid)
          .collection('blockedUsers')
          .get();
      _blockedUids = snap.docs.map((d) => d.id).toSet();
      debugPrint('[Nearby] loaded ${_blockedUids.length} blocked UIDs');
    } catch (e) {
      debugPrint('[Nearby] blocked UIDs load failed (non-fatal): $e');
    }
  }

  void _rebuildList(String myUid) {
    final lat = _myLat;
    final lng = _myLng;

    final users = _userBuffer.entries
        .where((e) {
          final uid = e.key;
          final data = e.value;

          // Exclude self.
          if (uid == myUid) return false;

          // Exclude blocked users.
          if (_blockedUids.contains(uid)) return false;

          // Exact distance filter — must have a valid position.
          final uLat = data['latitude'] as double?;
          final uLng = data['longitude'] as double?;
          if (uLat == null || uLng == null || lat == null || lng == null) {
            return false;
          }

          final distance =
              LocationService.distanceMeters(lat, lng, uLat, uLng);
          return distance <= AppConstants.nearbyRadiusMeters;
        })
        .map((e) => _NearbyUser.fromFirestore(e.key, e.value))
        .toList();

    // Sort closest first.
    if (lat != null && lng != null) {
      users.sort((a, b) {
        final da = LocationService.distanceMeters(lat, lng, a.lat, a.lng);
        final db = LocationService.distanceMeters(lat, lng, b.lat, b.lng);
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
    for (final sub in _subs) {
      sub.cancel();
    }
    _subs.clear();
    _userBuffer.clear();
    _nearbyUsers = [];
    _myLat = null;
    _myLng = null;
  }

  // ── Block ─────────────────────────────────────────────────────────────────

  Future<void> _blockUser(_NearbyUser user) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // Optimistic: remove immediately.
    setState(() {
      _blockedUids.add(user.id);
      _nearbyUsers.removeWhere((u) => u.id == user.id);
      _userBuffer.remove(user.id);
      if (_nearbyUsers.isNotEmpty) {
        _currentIndex = _currentIndex.clamp(0, _nearbyUsers.length - 1);
        if (_pageController.hasClients) {
          _pageController.jumpToPage(_currentIndex);
        }
      }
    });

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
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
          icon: const Icon(Icons.tune_rounded, color: AppColors.textSecondary),
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
              'Check back when you\'re out —\nusers only appear within ${AppConstants.nearbyRadiusMeters.toInt()} metres.',
              style: AppTextStyles.bodyS,
              textAlign: TextAlign.center,
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

  factory _NearbyUser.fromFirestore(String uid, Map<String, dynamic> data) {
    // Hometown may be a map (city + state) or a plain string.
    final hometownRaw = data['hometown'];
    String? hometown;
    if (hometownRaw is Map) {
      final city = hometownRaw['city'] as String? ?? '';
      final state = hometownRaw['stateCode'] as String? ??
          hometownRaw['state'] as String? ?? '';
      hometown = [city, state].where((s) => s.isNotEmpty).join(', ');
    } else if (hometownRaw is String && hometownRaw.isNotEmpty) {
      hometown = hometownRaw;
    }

    return _NearbyUser(
      id: uid,
      firstName: (data['firstName'] as String?) ?? 'Someone',
      age: (data['age'] as num?)?.toInt() ?? 0,
      bio: (data['bio'] as String?) ?? '',
      photoUrl: (data['photoUrl'] as String?) ?? '',
      lat: (data['latitude'] as num).toDouble(),
      lng: (data['longitude'] as num).toDouble(),
      hometown: hometown,
      occupation: data['occupation'] as String?,
      height: data['height'] as String?,
      lookingFor: data['lookingFor'] as String?,
      isGold: (data['plan'] as String?) == 'gold',
    );
  }
}
