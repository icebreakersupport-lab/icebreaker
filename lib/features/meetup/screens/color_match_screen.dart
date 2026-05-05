import 'dart:async';
import 'dart:ui';

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
import '../../../shared/widgets/pill_button.dart';

/// "Talking" phase screen — both users have confirmed they found each other
/// and the 10-minute conversation timer (talkExpiresAt) is running.
///
/// Visually this screen is the direct continuation of MatchedScreen — same
/// neon match-colour gradient, same photo-pair-with-timer-between layout —
/// so the transition from "finding" to "talking" reads as a single
/// continuous flow rather than a hard cut.
///
/// This screen also owns the post-meet *decision* phase: when the talk
/// timer hits 0 (locally OR via the server status flip to
/// 'awaiting_post_talk_decision'), a frosted-glass overlay rises over the
/// photo pair with the "Pass" / "Stay in touch" choice.  The photos remain
/// faintly visible behind the blur so the moment of choosing stays
/// emotionally anchored to the person you just spoke with.
///
/// Server-driven lifecycle:
///   • Entered when [onMeetupFoundConfirmed] flips the meetup status from
///     'finding' to 'talking' and stamps `talkExpiresAt`.  The
///     FlowCoordinator picks up the new status and redirects both
///     participants here.
///   • Decision phase: when the 10-min timer elapses, the scheduled
///     [onMeetupTalkExpired] flips status to 'awaiting_post_talk_decision'
///     and stamps `decisionExpiresAt`.  We render the overlay either at
///     local 0:00 OR on the status flip — whichever lands first — so the
///     decision card never has dead-air waiting on the every-1-min server
///     scheduler.
///   • Decision write: the overlay creates `meetups/{id}/decisions/{uid}`.
///     [onMeetupDecisionWritten] picks up the second decision and either
///     creates the conversation + flips status to 'matched' (mutual
///     'we_got_this') or flips to 'no_match' (any 'nice_meeting_you').
///   • Exit via the X button: only available during 'talking' (server-side
///     rules deny cancelRequests during the decision phase) — see
///     [onFindingCancelRequestCreated] which now handles both phases.
///   • All terminal statuses cascade through [onMeetupTerminal] which
///     clears `currentMeetupId`; FlowCoordinator's redirect then releases
///     us off this screen.
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
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _myDecisionSub;

  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;
  bool _isCancelling = false;

  /// True once the local countdown crosses 0 — drives the overlay before
  /// the server scheduler has a chance to flip status.
  bool _localTimerExpired = false;

  /// True while a decision write is in flight (incl. retry loop while we
  /// wait for the server to flip status into 'awaiting_post_talk_decision').
  bool _isSubmitting = false;

  /// My submitted decision, or null if I haven't submitted.  Sourced from
  /// `meetups/{id}/decisions/{myUid}` so the screen survives a cold restart
  /// mid-decision-window without losing my choice.
  String? _myDecision;

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
    final ref = FirebaseFirestore.instance
        .collection('meetups')
        .doc(widget.meetupId);

    _sub = ref.snapshots().listen(
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

    final uid = _myUid;
    if (uid != null) {
      _myDecisionSub =
          ref.collection('decisions').doc(uid).snapshots().listen((snap) {
        if (!mounted) return;
        setState(() {
          _myDecision = snap.data()?['decision'] as String?;
        });
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _myDecisionSub?.cancel();
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

  String? get _meetupStatus => _data?['status'] as String?;

  /// True when the post-talk decision overlay should render — either the
  /// local timer ticked past 0 OR the server has flipped status into the
  /// decision phase, whichever comes first.  We don't wait for both: the
  /// scheduled CF can lag the local clock by up to ~60 s and that lag is
  /// exactly the dead-air window the user reported.
  bool get _showDecisionOverlay {
    return _localTimerExpired || _meetupStatus == 'awaiting_post_talk_decision';
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

  /// Fired the moment our local talk timer ticks past 0 — writes
  /// `talkExpiredRequests/{uid}` so onTalkExpiredRequestCreated can flip
  /// status to 'awaiting_post_talk_decision' immediately rather than waiting
  /// up to ~60 s for the next onMeetupTalkExpired scheduler tick.  The
  /// scheduler is still authoritative if both clients are closed — this is
  /// a fast-path that eliminates the dead-air window when the user taps
  /// Pass / Stay in touch the instant the overlay appears.
  bool _talkExpiredRequestSent = false;
  Future<void> _bestEffortTalkExpiredRequest() async {
    if (_talkExpiredRequestSent) return;
    final uid = _myUid;
    if (uid == null) return;
    _talkExpiredRequestSent = true;
    try {
      await FirebaseFirestore.instance
          .collection('meetups')
          .doc(widget.meetupId)
          .collection('talkExpiredRequests')
          .doc(uid)
          .set({
        'uid': uid,
        'requestedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint(
          '[ColorMatchScreen] talk-expired request best-effort write failed: $e');
    }
  }

  // ── Decision flow ─────────────────────────────────────────────────────────

  /// Writes `meetups/{id}/decisions/{myUid}`.  Firestore rules enforce that
  /// status === 'awaiting_post_talk_decision', so when the user taps a
  /// button while we're still in the local-only "timer hit 0" window
  /// (server status hasn't flipped yet), the first attempt may be denied
  /// by the rule.  We retry up to 4 times spaced 1.5 s apart so the user
  /// never sees the rule lag — by the second attempt the server scheduler
  /// has almost always caught up.
  Future<void> _submit(String decision) async {
    final uid = _myUid;
    if (uid == null || _isSubmitting || _myDecision != null) return;
    setState(() => _isSubmitting = true);
    var lastError = '';
    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        await FirebaseFirestore.instance
            .collection('meetups')
            .doc(widget.meetupId)
            .collection('decisions')
            .doc(uid)
            .set({
          'uid': uid,
          'decision': decision,
          'createdAt': FieldValue.serverTimestamp(),
        });
        if (mounted) setState(() => _isSubmitting = false);
        return;
      } catch (e) {
        lastError = e.toString();
        debugPrint(
            '[ColorMatchScreen] decision write attempt ${attempt + 1} failed: $e');
        if (attempt < 3) {
          await Future<void>.delayed(const Duration(milliseconds: 1500));
        }
      }
    }
    if (!mounted) return;
    setState(() => _isSubmitting = false);
    debugPrint('[ColorMatchScreen] decision write gave up: $lastError');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not submit — try again.')),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // System-back is intercepted into the cancel flow during 'talking'.
    // Once the decision overlay is up the back gesture is a no-op — the
    // user has to choose Pass or Stay in touch to move forward.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_showDecisionOverlay) return;
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
    final showOverlay = _showDecisionOverlay;
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
        // X close button — hidden during the decision phase since
        // cancelRequests are no longer accepted server-side and the only
        // legal exit is choosing Pass or Stay in touch.
        if (!showOverlay)
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
                  onTimerExpired: () {
                    if (!mounted || _localTimerExpired) return;
                    setState(() => _localTimerExpired = true);
                    unawaited(_bestEffortTalkExpiredRequest());
                  },
                ),
              ),
              const Spacer(),
              const SizedBox(height: 32),
            ],
          ),
        ),
        if (showOverlay)
          Positioned.fill(
            child: _DecisionOverlay(
              otherFirstName: _otherFirstName,
              matchColor: _matchColor,
              isSubmitting: _isSubmitting,
              myDecision: _myDecision,
              onPass: () => _submit('nice_meeting_you'),
              onStayInTouch: () => _submit('we_got_this'),
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
    required this.onTimerExpired,
  });

  final String leftUrl;
  final String leftName;
  final String rightUrl;
  final String rightName;
  final Color matchColor;
  final Key timerKey;
  final int timerSecondsRemaining;
  final VoidCallback onTimerExpired;

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
                  onExpired: onTimerExpired,
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

/// Frosted-glass decision overlay.
///
/// The whole screen behind it is heavily blurred (σ ≈ 18) and dimmed with a
/// dark scrim, so the photo pair stays *just* visible — emotional context
/// for the choice, not a distraction.  A translucent rounded card holds the
/// question, a small "your answer is private" hint, and the two pill
/// buttons (Pass / Stay in touch).  Once the user has submitted, the card
/// flips to a calm "waiting for {name}…" state until the meetup's terminal
/// status releases the screen.
class _DecisionOverlay extends StatelessWidget {
  const _DecisionOverlay({
    required this.otherFirstName,
    required this.matchColor,
    required this.isSubmitting,
    required this.myDecision,
    required this.onPass,
    required this.onStayInTouch,
  });

  final String otherFirstName;
  final Color matchColor;
  final bool isSubmitting;
  final String? myDecision;
  final VoidCallback onPass;
  final VoidCallback onStayInTouch;

  @override
  Widget build(BuildContext context) {
    final hasDecided = myDecision != null;
    return Stack(
      children: [
        // Frost — everything underneath is blurred + dimmed.  The dark
        // scrim is intentionally light (alpha 0.32) so the gradient and
        // the ghosted photo circles still read through, keeping the moment
        // tied to the person you just talked to.
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              color: Colors.black.withValues(alpha: 0.32),
            ),
          ),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: BackdropFilter(
                  // Second blur on the card itself adds depth — the card
                  // reads as physically closer than the rest of the frost.
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.22),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: matchColor.withValues(alpha: 0.30),
                          blurRadius: 36,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                    child: hasDecided
                        ? _WaitingState(
                            decision: myDecision!,
                            otherFirstName: otherFirstName,
                          )
                        : _DecisionPrompt(
                            isSubmitting: isSubmitting,
                            onPass: onPass,
                            onStayInTouch: onStayInTouch,
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DecisionPrompt extends StatelessWidget {
  const _DecisionPrompt({
    required this.isSubmitting,
    required this.onPass,
    required this.onStayInTouch,
  });

  final bool isSubmitting;
  final VoidCallback onPass;
  final VoidCallback onStayInTouch;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'How did it go?',
          style: AppTextStyles.h2,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          "Stay in touch only sticks if you're both in.",
          style: AppTextStyles.bodyS.copyWith(
            color: Colors.white.withValues(alpha: 0.78),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: PillButton.danger(
                label: 'Pass',
                onTap: isSubmitting ? null : onPass,
                height: 60,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: PillButton.success(
                label: 'Stay in touch',
                onTap: isSubmitting ? null : onStayInTouch,
                isLoading: isSubmitting,
                height: 60,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _WaitingState extends StatelessWidget {
  const _WaitingState({
    required this.decision,
    required this.otherFirstName,
  });

  final String decision;
  final String otherFirstName;

  @override
  Widget build(BuildContext context) {
    final choseYes = decision == 'we_got_this';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          choseYes ? Icons.favorite_rounded : Icons.waving_hand_rounded,
          size: 44,
          color: choseYes
              ? AppColors.success
              : Colors.white.withValues(alpha: 0.85),
        ),
        const SizedBox(height: 14),
        Text(
          choseYes
              ? 'Waiting for $otherFirstName…'
              : 'Nice meeting $otherFirstName 👋',
          style: AppTextStyles.h3,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          choseYes
              ? "If they're in too, you'll stay in touch."
              : "We'll wrap things up here in a moment.",
          style: AppTextStyles.bodyS.copyWith(
            color: Colors.white.withValues(alpha: 0.78),
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
