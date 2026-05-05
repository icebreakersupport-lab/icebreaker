import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/state/flow_coordinator.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/countdown_timer_widget.dart';
import '../../../shared/widgets/gradient_scaffold.dart';

/// "Talking" phase screen — both users have confirmed they found each other
/// and the 10-minute conversation timer (talkExpiresAt) is running.
///
/// Visually this screen is the direct continuation of MatchedScreen — same
/// neon match-colour gradient, same photo-pair-with-timer-between layout —
/// so the transition from "finding" to "talking" reads as a single
/// continuous flow rather than a hard cut.
///
/// Server-driven lifecycle:
///   • Entered when [onMeetupFoundConfirmed] flips the meetup status from
///     'finding' to 'talking' and stamps `talkExpiresAt`.  The
///     FlowCoordinator picks up the new status and redirects both
///     participants here.
///   • Exited when [onMeetupTalkExpired] flips the status to
///     'awaiting_post_talk_decision'; the coordinator then redirects to
///     PostMeetScreen.
///   • Exited via the X button: writes `cancelRequests/{uid}`; the
///     [onFindingCancelRequestCreated] CF (phase-agnostic — also handles
///     'talking') flips status to `cancelled_talking`, the
///     [onMeetupTerminal] cascade clears `currentMeetupId`, and the
///     FlowCoordinator releases both users to /home.
///
/// Path-parameterised on `meetupId` so a cold-launch redirect can route
/// into this screen using nothing more than `users/{uid}.currentMeetupId`.
class ColorMatchScreen extends StatefulWidget {
  const ColorMatchScreen({
    super.key,
    required this.meetupId,
  });

  final String meetupId;

  @override
  State<ColorMatchScreen> createState() => _ColorMatchScreenState();
}

class _ColorMatchScreenState extends State<ColorMatchScreen> {
  /// Same fallback brand pink MatchedScreen uses when matchColorHex is
  /// missing or unparseable, so the two screens never diverge visually.
  static const Color _fallbackMatchColor = Color(0xFFFF1F6E);

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;
  bool _isCancelling = false;

  // Fallback photo URLs sourced live from profiles/live_sessions when the
  // meetup doc's participantPhotos snapshot is missing/empty.  Mirrors the
  // pattern from MatchedScreen so a meetup that started without a primary
  // photo on either side still renders real faces here.
  String? _myFallbackPhotoUrl;
  String? _otherFallbackPhotoUrl;
  bool _fallbackPhotoFetchStarted = false;

  String? get _myUid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _sub = FirebaseFirestore.instance
        .collection('meetups')
        .doc(widget.meetupId)
        .snapshots()
        .listen(
      (snap) {
        if (!mounted) return;
        setState(() {
          _data = snap.data();
          _loading = false;
          _error = snap.exists ? null : 'Meetup not found.';
        });
        _maybeFetchFallbackPhotos();
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'Could not load meetup.';
        });
      },
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  // ── Derived state ─────────────────────────────────────────────────────────

  String get _myFirstName {
    final names = (_data?['participantNames'] as Map<String, dynamic>?) ?? {};
    return (names[_myUid] as String?) ?? '';
  }

  String get _myPhotoUrl {
    final photos = (_data?['participantPhotos'] as Map<String, dynamic>?) ?? {};
    final url = (photos[_myUid] as String?) ?? '';
    if (url.isNotEmpty) return url;
    return _myFallbackPhotoUrl ?? '';
  }

  String? get _otherUid {
    final ps = List<String>.from(
        (_data?['participants'] as List<dynamic>?) ?? const []);
    return ps.firstWhere((p) => p != _myUid, orElse: () => '');
  }

  String get _otherFirstName {
    final names = (_data?['participantNames'] as Map<String, dynamic>?) ?? {};
    return (names[_otherUid] as String?) ?? 'Them';
  }

  String get _otherPhotoUrl {
    final photos = (_data?['participantPhotos'] as Map<String, dynamic>?) ?? {};
    final url = (photos[_otherUid] as String?) ?? '';
    if (url.isNotEmpty) return url;
    return _otherFallbackPhotoUrl ?? '';
  }

  Color get _matchColor {
    final rawHex = _data?['matchColorHex'];
    if (rawHex is! String) return _fallbackMatchColor;
    final hex = rawHex.replaceFirst('#', '').trim();
    final isRgbHex = RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(hex);
    if (!isRgbHex) return _fallbackMatchColor;
    return Color(int.parse('FF$hex', radix: 16));
  }

  int get _talkSecondsRemaining {
    final exp = (_data?['talkExpiresAt'] as Timestamp?)?.toDate();
    if (exp == null) return 0;
    return exp.difference(DateTime.now()).inSeconds.clamp(0, 1 << 30);
  }

  /// One-shot fallback photo fetch — same behaviour as MatchedScreen.
  Future<void> _maybeFetchFallbackPhotos() async {
    if (_fallbackPhotoFetchStarted) return;
    final uid = _myUid;
    final otherUid = _otherUid;
    if (uid == null || otherUid == null || otherUid.isEmpty) return;
    _fallbackPhotoFetchStarted = true;

    String pick(
      DocumentSnapshot<Map<String, dynamic>> live,
      DocumentSnapshot<Map<String, dynamic>> profile,
    ) {
      final selfie = live.data()?['liveSelfieUrl'];
      if (selfie is String && selfie.isNotEmpty) return selfie;
      final primary = profile.data()?['primaryPhotoUrl'];
      if (primary is String && primary.isNotEmpty) return primary;
      return '';
    }

    try {
      final db = FirebaseFirestore.instance;
      final results = await Future.wait([
        db.collection('profiles').doc(uid).get(),
        db.collection('profiles').doc(otherUid).get(),
        db.collection('live_sessions').doc(uid).get(),
        db.collection('live_sessions').doc(otherUid).get(),
      ]);
      if (!mounted) return;
      setState(() {
        _myFallbackPhotoUrl = pick(results[2], results[0]);
        _otherFallbackPhotoUrl = pick(results[3], results[1]);
      });
    } catch (e) {
      debugPrint('[ColorMatchScreen] fallback photo fetch failed: $e');
    }
  }

  // ── Cancel flow ───────────────────────────────────────────────────────────

  /// Mirrors MatchedScreen's `_confirmCancel`: a single dialog, then a
  /// best-effort `cancelRequests/{uid}` write that the (phase-agnostic) CF
  /// turns into a `cancelled_talking` terminal.  The user is sent to /home
  /// the moment they confirm — no awaiting the write — because they have
  /// already chosen to leave.
  Future<void> _confirmCancel() async {
    if (_isCancelling) return;
    final shouldCancel = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgElevated,
        title: Text('Leave this Icebreaker?', style: AppTextStyles.h3),
        content: Text(
          'You\'re in the middle of your 10-minute talk. Leaving will end '
          'the Icebreaker for both of you, and neither of you will get '
          'the Icebreaker back.',
          style: AppTextStyles.bodyS,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep talking'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Leave Icebreaker',
              style: TextStyle(color: AppColors.brandPink),
            ),
          ),
        ],
      ),
    );
    if (shouldCancel != true) return;
    final uid = _myUid;
    if (uid == null || !mounted) return;

    setState(() => _isCancelling = true);
    debugPrint(
        '[ColorMatchScreen] cancel confirmed — suppress + clear + go home');
    FlowCoordinatorScope.of(context)
        .suppressMatchedLockForTimedOutExit(meetupId: widget.meetupId);

    unawaited(_optimisticClearMyCurrentMeetupId(uid));
    unawaited(_bestEffortCancelRequest(uid));

    if (!mounted) return;
    context.go(AppRoutes.home);
  }

  Future<void> _optimisticClearMyCurrentMeetupId(String uid) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'currentMeetupId': FieldValue.delete(),
      });
      debugPrint('[ColorMatchScreen] optimistic clear of currentMeetupId OK');
    } catch (e) {
      debugPrint('[ColorMatchScreen] optimistic clear failed: $e');
    }
  }

  Future<void> _bestEffortCancelRequest(String uid) async {
    try {
      await FirebaseFirestore.instance
          .collection('meetups')
          .doc(widget.meetupId)
          .collection('cancelRequests')
          .doc(uid)
          .set({
        'uid': uid,
        'requestedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint(
          '[ColorMatchScreen] cancel request best-effort write failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // System-back is intercepted into the same confirm-cancel flow as the X
    // button so Android's gesture and the in-screen close icon behave
    // identically.  The talking phase has no other legal exit until the
    // server flips status forward.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _confirmCancel();
      },
      child: GradientScaffold(
        showTopGlow: false,
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _error!,
                        style: AppTextStyles.bodyS,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  _matchColor.withValues(alpha: 0.65),
                  _matchColor.withValues(alpha: 0.30),
                ],
              ),
            ),
          ),
        ),
        // Top-left close button — same affordance as MatchedScreen so users
        // who learned to bail out of the finding phase here recognise it
        // immediately during talking.
        Positioned(
          top: 0,
          left: 0,
          child: SafeArea(
            child: IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white70),
              onPressed: _isCancelling ? null : _confirmCancel,
            ),
          ),
        ),
        SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 32),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  "You're talking 💬",
                  style: AppTextStyles.h1,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'Make these 10 minutes count.',
                  style: AppTextStyles.bodyS,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 32),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _MatchPhotoPair(
                  leftUrl: _myPhotoUrl,
                  leftName: _myFirstName,
                  rightUrl: _otherPhotoUrl,
                  rightName: _otherFirstName,
                  matchColor: _matchColor,
                  // Timer keyed on talkExpiresAt — forces a fresh timer when
                  // the CF stamp lands (the stream's first event has it null).
                  timerKey: ValueKey<int>(_talkSecondsRemaining),
                  timerSecondsRemaining: _talkSecondsRemaining,
                ),
              ),
              const Spacer(),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ],
    );
  }
}

/// Two ringed photos with the talk-timer countdown centered between them.
/// Mirrors MatchedScreen's _MatchPhotoPair so the visual flow from finding
/// to talking is seamless — same ring colour, same circle sizes, same
/// gap/budget formula.
class _MatchPhotoPair extends StatelessWidget {
  const _MatchPhotoPair({
    required this.leftUrl,
    required this.leftName,
    required this.rightUrl,
    required this.rightName,
    required this.matchColor,
    required this.timerKey,
    required this.timerSecondsRemaining,
  });

  final String leftUrl;
  final String leftName;
  final String rightUrl;
  final String rightName;
  final Color matchColor;
  final Key timerKey;
  final int timerSecondsRemaining;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Same budgeting as MatchedScreen: 120 px reserved for the timer
        // slot + two 12 px gaps so the row never overflows on Android.
        final radius = ((constraints.maxWidth - 120) / 4).clamp(36.0, 56.0);
        final ringDiameter = (radius + 4) * 2;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PhotoCircle(
                url: leftUrl,
                name: leftName,
                matchColor: matchColor,
                radius: radius),
            const SizedBox(width: 12),
            SizedBox(
              height: ringDiameter,
              child: Center(
                child: CountdownTimerWidget(
                  key: timerKey,
                  initialSeconds: timerSecondsRemaining,
                  // Server-owned: onMeetupTalkExpired flips status to
                  // awaiting_post_talk_decision; FlowCoordinator's
                  // refreshListenable redirects us to PostMeetScreen.
                  onExpired: () {},
                  style: AppTextStyles.h1,
                ),
              ),
            ),
            const SizedBox(width: 12),
            _PhotoCircle(
                url: rightUrl,
                name: rightName,
                matchColor: matchColor,
                radius: radius),
          ],
        );
      },
    );
  }
}

class _PhotoCircle extends StatelessWidget {
  const _PhotoCircle({
    required this.url,
    required this.name,
    required this.matchColor,
    this.radius = 56,
  });

  final String url;
  final String name;
  final Color matchColor;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [matchColor, matchColor.withValues(alpha: 0.6)],
            ),
          ),
          child: CircleAvatar(
            radius: radius,
            backgroundColor: AppColors.bgElevated,
            backgroundImage: url.isNotEmpty ? NetworkImage(url) : null,
            child: url.isEmpty
                ? Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: AppTextStyles.h2
                        .copyWith(color: AppColors.textSecondary),
                  )
                : null,
          ),
        ),
        const SizedBox(height: 8),
        Text(name, style: AppTextStyles.bodyS),
      ],
    );
  }
}
