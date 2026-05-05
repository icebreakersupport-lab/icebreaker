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
import '../../../shared/widgets/pill_button.dart';

/// "Finding" state screen — both participants need to physically find each
/// other within the find timer.
///
/// This screen is fully data-driven from `meetups/{meetupId}`:
///   • participants[]            — derive my/other UID
///   • participantNames map      — first names for both
///   • participantPhotos map     — meetup-render photo snapshot (prefer the
///                                 GO LIVE verification selfie, fall back to
///                                 profile photo)
///   • matchColorHex             — shared meetup accent chosen server-side
///   • status                    — used by FlowCoordinator + this screen for
///                                 confirmation messaging
///   • findExpiresAt             — countdown anchor
///   • foundConfirmedBy[]        — "I found them" participation
///
/// The path-parameterised route (`/meetup/matched/:meetupId`) lets the
/// FlowCoordinator redirect funnel users into this screen using nothing
/// more than `users/{uid}.currentMeetupId` — no in-memory extras to carry.
///
/// Cancel flow:
///   PopScope intercepts a back-press during `finding`, asks the user to
///   confirm, and on confirm writes `meetups/{id}/cancelRequests/{uid}`.
///   The CF (`onFindingCancelRequestCreated`) flips the meetup to
///   `cancelled_finding`, which cascades through `onMeetupTerminal` to
///   clear `currentMeetupId` on both users.  The FlowCoordinator notices
///   the cleared field, `targetRoute` flips to null, and go_router's
///   `refreshListenable` redirect pops everyone off this screen.
class MatchedScreen extends StatefulWidget {
  const MatchedScreen({
    super.key,
    required this.meetupId,
  });

  final String meetupId;

  @override
  State<MatchedScreen> createState() => _MatchedScreenState();
}

class _MatchedScreenState extends State<MatchedScreen> {
  static const Color _fallbackMatchColor = Color(0xFFFF1F6E);

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;
  bool _isConfirming = false;
  bool _timedOutLocally = false;
  bool _isReturningHome = false;
  bool _cancelledByOtherLocally = false;
  Timer? _timeoutNavTimer;

  // Fallback photo URLs sourced live from profiles/live_sessions when the
  // meetup doc's participantPhotos snapshot is missing/empty (e.g. neither
  // user had a primary photo or live selfie at meetup-create time).
  String? _myFallbackPhotoUrl;
  String? _otherFallbackPhotoUrl;
  bool _fallbackPhotoFetchStarted = false;

  // Finding-phase chat — lightweight subcollection, ordered ASC by
  // createdAt.  Bubbles render bottom-up (latest at the bottom near the
  // input).  Subscription lives only for the matched-screen lifetime; CF
  // status flip to a terminal phase pulls us off this screen.
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _messagesSub;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _messages = const [];
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();
  bool _isSending = false;

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
        final data = snap.data();
        setState(() {
          _data = data;
          _loading = false;
          _error = snap.exists ? null : 'Meetup not found.';
        });
        _maybeDetectCancelledByOther(data);
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

    _messagesSub = FirebaseFirestore.instance
        .collection('meetups')
        .doc(widget.meetupId)
        .collection('findingMessages')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final hadMessages = _messages.length;
      setState(() => _messages = snap.docs);
      if (snap.docs.length > hadMessages) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
    }, onError: (Object e) {
      debugPrint('[MatchedScreen] messages stream error: $e');
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _messagesSub?.cancel();
    _timeoutNavTimer?.cancel();
    _textController.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
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

  int get _findSecondsRemaining {
    final exp = (_data?['findExpiresAt'] as Timestamp?)?.toDate();
    if (exp == null) return 0;
    return exp.difference(DateTime.now()).inSeconds.clamp(0, 1 << 30);
  }

  bool get _iAlreadyConfirmed {
    final confirmed = List<String>.from(
        (_data?['foundConfirmedBy'] as List<dynamic>?) ?? const []);
    return confirmed.contains(_myUid);
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  /// Adds my UID to foundConfirmedBy.  The arrayUnion is allowed by
  /// firestore.rules (the only mutation a participant can make to the
  /// meetup doc).  The talking transition is owned by the
  /// onMeetupFoundConfirmed CF (deferred this pass) so the screen does not
  /// navigate from here yet — it just reflects the confirmation state via
  /// the live stream.
  Future<void> _handleConfirm() async {
    final uid = _myUid;
    if (uid == null || _isConfirming || _iAlreadyConfirmed) return;
    setState(() => _isConfirming = true);
    try {
      await FirebaseFirestore.instance
          .collection('meetups')
          .doc(widget.meetupId)
          .update({
        'foundConfirmedBy': FieldValue.arrayUnion([uid]),
      });
    } catch (e) {
      // Log the actual cause so future "could not confirm" reports come with
      // a concrete error string in the device console rather than a silent
      // snackbar (the matched-screen rule has subtle CEL gotchas that are
      // very hard to diagnose without the underlying PERMISSION_DENIED text).
      debugPrint('[MatchedScreen] foundConfirmedBy update failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not confirm — try again.')),
      );
    } finally {
      if (mounted) setState(() => _isConfirming = false);
    }
  }

  /// Sends a finding-phase chat message.  Optimistic-feeling: the input
  /// clears immediately, the write fires async.  The stream subscription
  /// rebuilds the list with the server-stamped doc the moment the write
  /// lands, so there's no need for a local optimistic insertion (and no
  /// risk of doubled bubbles).
  Future<void> _sendMessage() async {
    final raw = _textController.text.trim();
    if (raw.isEmpty || _isSending) return;
    final uid = _myUid;
    if (uid == null) return;
    final text = raw.length > 500 ? raw.substring(0, 500) : raw;
    setState(() => _isSending = true);
    _textController.clear();
    try {
      await FirebaseFirestore.instance
          .collection('meetups')
          .doc(widget.meetupId)
          .collection('findingMessages')
          .add({
        'senderId': uid,
        'text': text,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[MatchedScreen] message send failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not send — try again.')),
        );
        // Restore the text so the user doesn't lose what they typed.
        _textController.text = text;
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  /// Confirms the user wants to back out of finding, then leaves
  /// immediately for Home.  Mirrors the working timed-out return-home flow:
  ///
  ///   1. Suppress the matched-route lock for this meetup so the router
  ///      doesn't bounce us back here while currentMeetupId is still set.
  ///   2. Fire-and-forget the `cancelRequests/{uid}` write.  The CF flips
  ///      status to `cancelled_finding`, `onMeetupTerminal` cascades, and
  ///      the other user is notified via their meetup stream so they see
  ///      the "they cancelled — Return Home" panel.
  ///   3. `context.go(home)` immediately — no awaiting the write, no
  ///      "could not cancel" snackbar.  The user has explicitly chosen to
  ///      leave; cleanup is best-effort.  If the rule denies the write
  ///      (already past `finding` because the schedule expired or the
  ///      other user cancelled first), the meetup is already heading
  ///      terminal and the natural cleanup cascade will catch up.
  Future<void> _confirmCancel() async {
    final shouldCancel = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgElevated,
        title: Text('Cancel this Icebreaker?', style: AppTextStyles.h3),
        content: Text(
          'Your Icebreaker is still in progress. Leaving will cancel '
          'the current Icebreaker and meetup for both of you, and '
          'neither of you will get the Icebreaker back.',
          style: AppTextStyles.bodyS,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep finding'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Cancel Icebreaker',
              style: TextStyle(color: AppColors.brandPink),
            ),
          ),
        ],
      ),
    );
    if (shouldCancel != true) return;
    final uid = _myUid;
    if (uid == null || !mounted) return;

    debugPrint('[MatchedScreen] cancel confirmed — suppress + clear + go home');
    FlowCoordinatorScope.of(context)
        .suppressMatchedLockForTimedOutExit(meetupId: widget.meetupId);

    // Optimistically clear our own users.currentMeetupId so the LiveSession
    // mirror flips us back to `discoverable` immediately, independent of
    // whether the cancelRequests CF runs.  Without this, a CF crash / lag /
    // missed deploy strands the canceller as `hidden_in_meetup` until they
    // restart the app and the FlowCoordinator zombie self-heal kicks in.
    // The CF cleanup (when it does run) is idempotent: onMeetupTerminal
    // skips the user-doc update if currentMeetupId no longer points at the
    // same meetup.
    unawaited(_optimisticClearMyCurrentMeetupId(uid));

    // Fire-and-forget CF trigger so the OTHER user's meetup-status stream
    // sees `cancelled_finding` and surfaces the "they cancelled" panel.
    unawaited(_bestEffortCancelRequest(uid));

    if (!mounted) return;
    context.go(AppRoutes.home);
  }

  Future<void> _optimisticClearMyCurrentMeetupId(String uid) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'currentMeetupId': FieldValue.delete(),
      });
      debugPrint('[MatchedScreen] optimistic clear of currentMeetupId OK');
    } catch (e) {
      debugPrint('[MatchedScreen] optimistic clear failed: $e');
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
          '[MatchedScreen] cancel request best-effort write failed: $e');
    }
  }

  /// One-shot fresh read of `meetups/{id}.status`.  Returns true only when
  /// the doc is positively still in 'finding'.  Read failure (network /
  /// transient) returns true so the user sees the retry snackbar rather
  /// than a silent stuck spinner.
  Future<bool> _isStillInFinding() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('meetups')
          .doc(widget.meetupId)
          .get();
      return (snap.data()?['status'] as String?) == 'finding';
    } catch (_) {
      return true;
    }
  }

  /// Local find-timer-expiry UX.  The countdown reaching 0 does NOT move
  /// server state — that is the scheduled `onMeetupFindingExpired` CF's
  /// job, and it can lag the client tick by up to ~60 s.  Pre-fix the
  /// user sat on a `0:00` screen with the "I found them" CTA and the
  /// cancel X both still active; this swaps the body for a centered
  /// "This Icebreaker timed out" state and queues a self-release nav.
  ///
  /// Server-state ownership stays where it is: we do NOT mutate the
  /// meetup, do NOT clear currentMeetupId, do NOT touch FlowCoordinator.
  /// The follow-up `context.go(home)` only fires when the streamed
  /// status has positively moved out of 'finding' — at that point the
  /// router redirect (matched-route release branch) is heading to the
  /// same destination, so we don't fight it and we don't bounce.  When
  /// the server is still catching up the timer self-aborts and we sit
  /// on the timeout message until FlowCoordinator pops us.
  void _handleLocalExpiry() {
    if (_timedOutLocally || !mounted) return;
    setState(() => _timedOutLocally = true);
    _timeoutNavTimer?.cancel();
    _timeoutNavTimer = Timer(const Duration(seconds: 2), () {
      _goHomeIfTimeoutReleased(logIfBlocked: true);
    });
  }

  void _goHomeIfTimeoutReleased({bool logIfBlocked = false}) {
    if (!mounted) return; // Router already popped us — yield.
    final status = (_data?['status'] as String?);
    if (status == null || status == 'finding') {
      if (logIfBlocked) {
        debugPrint(
            '[MatchedScreen] timeout self-release skipped — status=$status, awaiting redirect');
      }
      return;
    }
    context.go(AppRoutes.home);
  }

  /// Timeout-screen "Return Home" button handler.  The button has to work
  /// during the worst-case window — the schedule lag between the client
  /// hitting 0:00 and `onMeetupFindingExpired` flipping status — which is
  /// also exactly when the user is most motivated to press it.
  ///
  /// Two paths, picked from the streamed status:
  ///   • status != 'finding' (server already terminal): the FlowCoordinator
  ///     redirect is already heading to /home (matched-route release branch
  ///     in app_router.dart).  We `context.go` ahead of it — same
  ///     destination, no fight.
  ///   • status == 'finding' (server hasn't caught up): write
  ///     `cancelRequests/{uid}`, the same server-owned exit path the X
  ///     button uses pre-timeout.  Confirmation dialog is intentionally
  ///     skipped — the user has already conceded by tapping "Return Home"
  ///     on a timed-out screen.  The CF flips status to
  ///     `cancelled_finding`, `onMeetupTerminal` cascades, currentMeetupId
  ///     clears, FlowCoordinator pops us, and the live-session mirror
  ///     restores `visibilityState = discoverable` automatically.  We do
  ///     NOT mutate the meetup directly, do NOT clear currentMeetupId, do
  ///     NOT touch FlowCoordinator — backend ownership is preserved.
  ///
  /// Race handling on the slow path mirrors `_confirmCancel`: the rule's
  /// `status == 'finding'` get() can see a post-finding state between our
  /// pre-check and the write.  Because the user explicitly chose to leave,
  /// we do not block Home navigation on that best-effort write; failures are
  /// logged and cleanup falls back to the scheduled expiry / terminal cascade.
  Future<void> _handleTimedOutReturnHome() async {
    if (_isReturningHome) return;

    final status = (_data?['status'] as String?);
    setState(() => _isReturningHome = true);

    // If we're still in the lag window (client hit 0:00, server status is
    // still 'finding'), temporarily suppress the matched-route lock so Home
    // navigation can win immediately instead of bouncing back here.
    FlowCoordinatorScope.of(context)
        .suppressMatchedLockForTimedOutExit(meetupId: widget.meetupId);

    if (status != null && status != 'finding') {
      context.go(AppRoutes.home);
      return;
    }

    final uid = _myUid;
    if (uid != null) {
      unawaited(_bestEffortTimedOutExitRequest(uid));
    }

    if (!mounted) return;
    context.go(AppRoutes.home);
  }

  Future<void> _bestEffortTimedOutExitRequest(String uid) async {
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
      final stillInFinding = await _isStillInFinding();
      if (!stillInFinding) {
        debugPrint(
            '[MatchedScreen] timed-out return-home request raced terminal transition ($e)');
        return;
      }
      debugPrint(
          '[MatchedScreen] timed-out return-home request failed while still in finding: $e');
    }
  }

  /// One-shot fallback photo fetch.  The meetup doc's `participantPhotos`
  /// is a snapshot taken at meetup-create time; if neither user had a
  /// primary photo or live selfie at that moment, the URLs are empty and
  /// the avatars degrade to letter placeholders.  This reads each user's
  /// `live_sessions/{uid}.liveSelfieUrl` and `profiles/{uid}.primaryPhotoUrl`
  /// directly so the matched screen can still render real photos when they
  /// exist post-meetup-create.  Fired once per screen lifetime — failures
  /// are silent (the placeholder UI is the natural fallback).
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
      debugPrint('[MatchedScreen] fallback photo fetch failed: $e');
    }
  }

  /// Detects "the OTHER participant cancelled" from the meetup stream and
  /// pins this screen so the cancellee sees the "they cancelled — Return
  /// Home" panel rather than being snapped to /home by the cleanup cascade.
  ///
  /// The CF (`onFindingCancelRequestCreated`) writes both
  /// `status: 'cancelled_finding'` and `cancelledBy: <canceller-uid>` in the
  /// same update, so a single snapshot is enough to identify this state.
  /// We pin via FlowCoordinator immediately because `onMeetupTerminal` will
  /// clear `currentMeetupId` on both users moments later — without the pin,
  /// the matched-route release branch would redirect us to /home before the
  /// user has a chance to read the message.
  void _maybeDetectCancelledByOther(Map<String, dynamic>? data) {
    if (_cancelledByOtherLocally || data == null) return;
    if (data['status'] != 'cancelled_finding') return;
    final cancelledBy = data['cancelledBy'] as String?;
    final uid = _myUid;
    if (cancelledBy == null || uid == null || cancelledBy == uid) return;
    if (!mounted) return;
    setState(() => _cancelledByOtherLocally = true);
    FlowCoordinatorScope.of(context)
        .pinMatchedScreenForReview(meetupId: widget.meetupId);
  }

  /// "Return Home" button handler for the cancellee panel.  Releases the
  /// FlowCoordinator pin so the matched-route release branch is allowed to
  /// run, then navigates Home.  Releasing before navigating ensures the
  /// router sees an empty `targetRoute` when it evaluates the redirect for
  /// /home — otherwise the pin would force us straight back here.
  void _handleCancelledReturnHome() {
    if (_isReturningHome) return;
    setState(() => _isReturningHome = true);
    FlowCoordinatorScope.of(context)
        .releasePinnedMatchedScreen(meetupId: widget.meetupId);
    context.go(AppRoutes.home);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // Cancel doesn't apply once the meetup is past 'finding' from this
        // user's perspective — the rule denies cancelRequests, and the
        // screen is on its way out via the local self-release or the
        // FlowCoordinator pin/redirect.  The system back gesture is a
        // no-op in those terminal panels; the user has to tap Return Home.
        if (_timedOutLocally || _cancelledByOtherLocally) return;
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
                : _cancelledByOtherLocally
                    ? _buildCancelledByOtherContent()
                    : _timedOutLocally
                        ? _buildTimedOutContent()
                        : _buildContent(),
      ),
    );
  }

  Widget _buildTimedOutContent() {
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
        Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.timer_off_rounded,
                  size: 56,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
                const SizedBox(height: 20),
                Text(
                  'This Icebreaker timed out',
                  style: AppTextStyles.h2,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                PillButton.primary(
                  label: 'Return Home',
                  onTap: _isReturningHome ? null : _handleTimedOutReturnHome,
                  isLoading: _isReturningHome,
                  width: double.infinity,
                  height: 60,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Cancellee panel — shown to the user whose partner cancelled the
  /// finding meetup.  Mirrors [_buildTimedOutContent] visually so the two
  /// terminal states feel like one cohesive design family.  The cleanup CF
  /// (`onMeetupTerminal`) clears `currentMeetupId` on this user, so the
  /// FlowCoordinator pin (set via `_maybeDetectCancelledByOther`) is the
  /// only thing keeping us here until Return Home is tapped.
  Widget _buildCancelledByOtherContent() {
    final otherName = _otherFirstName;
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
        Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.cancel_rounded,
                  size: 56,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
                const SizedBox(height: 20),
                Text(
                  '$otherName cancelled',
                  style: AppTextStyles.h2,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'You need to return home.',
                  style: AppTextStyles.bodyS,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                PillButton.primary(
                  label: 'Return Home',
                  onTap: _isReturningHome ? null : _handleCancelledReturnHome,
                  isLoading: _isReturningHome,
                  width: double.infinity,
                  height: 60,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContent() {
    // When the soft keyboard is up the column has to host title + subtitle
    // + photo pair + chat + input + swipe within whatever pixels are left
    // above the IME.  On smaller Android viewports that sum overflows by
    // ~16 px, so we collapse the title + subtitle (the static brief) when
    // the user is actively typing and shrink the photo pair so the chat
    // remains the focal element.
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
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
        Positioned(
          top: 0,
          left: 0,
          child: SafeArea(
            child: IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white70),
              onPressed: _confirmCancel,
            ),
          ),
        ),
        SafeArea(
          child: Column(
            children: [
              SizedBox(height: keyboardOpen ? 12 : 32),
              if (!keyboardOpen) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'Find each other! 🧊',
                    style: AppTextStyles.h1,
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'You have 5 minutes to meet in person.',
                    style: AppTextStyles.bodyS,
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 24),
              ],
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _MatchPhotoPair(
                  leftUrl: _myPhotoUrl,
                  leftName: _myFirstName,
                  rightUrl: _otherPhotoUrl,
                  rightName: _otherFirstName,
                  matchColor: _matchColor,
                  // Timer keyed on findExpiresAt — forces a fresh timer when
                  // the CF stamp lands (the stream's first event has it null).
                  timerKey: ValueKey<int>(_findSecondsRemaining),
                  timerSecondsRemaining: _findSecondsRemaining,
                  onTimerExpired: _handleLocalExpiry,
                  compact: keyboardOpen,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _buildMessageFeed(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildInputRow(),
              ),
              const SizedBox(height: 16),
              if (_iAlreadyConfirmed)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppColors.success.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.check_circle_rounded,
                            color: AppColors.success, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Confirmed! Waiting for $_otherFirstName...',
                          style: AppTextStyles.bodyS
                              .copyWith(color: AppColors.success),
                        ),
                      ],
                    ),
                  ),
                )
              else
                // Full-bleed: no horizontal padding, slider hugs both edges.
                _SwipeToConfirm(
                  label: 'Swipe — I found $_otherFirstName',
                  matchColor: _matchColor,
                  onConfirmed: _isConfirming ? null : _handleConfirm,
                  isLoading: _isConfirming,
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// Bubble feed.  Free-flowing — no card, border, or fixed height — so the
  /// chat reads as part of the screen rather than a contained widget.
  ///
  /// Always a scrollable ListView (even when empty) so the swipe-down
  /// keyboard-dismiss gesture works regardless of message count.  Bouncing
  /// physics (vs Android's default ClampingScrollPhysics) is the key bit:
  /// clamping physics doesn't emit drag updates when the list is at its
  /// boundary or too short to scroll, which is exactly when the user
  /// reaches to flick the chat down to dismiss the keyboard.  Bouncing
  /// physics emits drag updates regardless, so
  /// [ScrollViewKeyboardDismissBehavior.onDrag] picks them up on Android
  /// the same way it already does on iOS.
  Widget _buildMessageFeed() {
    return ListView.builder(
      controller: _scrollController,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: _messages.length,
      itemBuilder: (context, i) {
        final data = _messages[i].data();
        final senderId = data['senderId'] as String?;
        final text = (data['text'] as String?) ?? '';
        final isMine = senderId == _myUid;
        return _ChatBubble(
          text: text,
          isMine: isMine,
          matchColor: _matchColor,
        );
      },
    );
  }

  /// Lightweight chat input.  Pill-shaped translucent field, send arrow on
  /// the right.  No card around it — the rounded shape is the affordance.
  Widget _buildInputRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.32),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.18),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            child: TextField(
              controller: _textController,
              focusNode: _inputFocusNode,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
              style: AppTextStyles.body.copyWith(color: Colors.white),
              cursorColor: Colors.white,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Message $_otherFirstName…',
                hintStyle: AppTextStyles.body.copyWith(
                  color: Colors.white.withValues(alpha: 0.55),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _SendButton(
          matchColor: _matchColor,
          onTap: _isSending ? null : _sendMessage,
          isLoading: _isSending,
        ),
      ],
    );
  }
}

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
    this.compact = false,
  });

  final String leftUrl;
  final String leftName;
  final String rightUrl;
  final String rightName;
  final Color matchColor;
  final Key timerKey;
  final int timerSecondsRemaining;
  final VoidCallback onTimerExpired;

  /// When true (e.g. soft keyboard up), the photo circles shrink so the
  /// remaining vertical real-estate goes to the chat instead.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Budget 120 px of the row for the timer slot + the two 12 px gaps
        // (timer text "5:00" at h1 / 32 pt is ≈ 80 px, plus 24 px of gaps,
        // plus a safety margin so font-scale or denser locale digits never
        // tip the row into a RenderFlex overflow on narrower Android
        // viewports).  Two photos + their rings consume the rest.
        final maxRadius = compact ? 38.0 : 56.0;
        final minRadius = compact ? 26.0 : 36.0;
        final radius = ((constraints.maxWidth - 120) / 4)
            .clamp(minRadius, maxRadius);
        // Diameter including the 4pt gradient ring around each circle —
        // used to vertically center the timer with the circle (not with
        // the photo+name column).
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
            // Timer occupies the slot the gradient bar used to live in,
            // sized to the circle's vertical extent so it lines up with
            // the photos rather than the names below them.
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

/// iMessage-style chat bubble.  Mine (right-aligned) uses the meetup's
/// match color; theirs (left-aligned) uses a translucent dark fill that
/// reads softly against the colored background.  Asymmetric corner radius
/// gives each bubble a "tail" pointing back at its sender.
class _ChatBubble extends StatelessWidget {
  const _ChatBubble({
    required this.text,
    required this.isMine,
    required this.matchColor,
  });

  final String text;
  final bool isMine;
  final Color matchColor;

  @override
  Widget build(BuildContext context) {
    final align = isMine ? Alignment.centerRight : Alignment.centerLeft;
    final bubbleColor = isMine
        ? matchColor.withValues(alpha: 0.95)
        : Colors.black.withValues(alpha: 0.45);
    final textColor = Colors.white;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(22),
      topRight: const Radius.circular(22),
      bottomLeft: Radius.circular(isMine ? 22 : 6),
      bottomRight: Radius.circular(isMine ? 6 : 22),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Align(
        alignment: align,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.72,
          ),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: radius,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Text(
              text,
              style: AppTextStyles.body.copyWith(color: textColor),
            ),
          ),
        ),
      ),
    );
  }
}

/// Round send button with the meetup's match color, a paper-plane icon, and
/// an inline spinner while a write is in flight.  Disabled when [onTap] is
/// null (i.e. while sending).
class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.matchColor,
    required this.onTap,
    required this.isLoading,
  });

  final Color matchColor;
  final VoidCallback? onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [matchColor, matchColor.withValues(alpha: 0.7)],
          ),
          boxShadow: [
            BoxShadow(
              color: matchColor.withValues(alpha: 0.45),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: isLoading
            ? const Padding(
                padding: EdgeInsets.all(14),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Icon(Icons.arrow_upward_rounded, color: Colors.white),
      ),
    );
  }
}

/// Swipe-right slider that fires [onConfirmed] once the thumb crosses ~80%
/// of the track.  Snaps back if released early.  Replaces the old "I found
/// {name}" pill button — the gesture makes accidental confirmation harder
/// (an actual physical match has been found), and the visual reads as a
/// committal action rather than a tap.
class _SwipeToConfirm extends StatefulWidget {
  const _SwipeToConfirm({
    required this.label,
    required this.matchColor,
    required this.onConfirmed,
    required this.isLoading,
  });

  final String label;
  final Color matchColor;
  final VoidCallback? onConfirmed;
  final bool isLoading;

  @override
  State<_SwipeToConfirm> createState() => _SwipeToConfirmState();
}

class _SwipeToConfirmState extends State<_SwipeToConfirm>
    with SingleTickerProviderStateMixin {
  static const double _height = 60;
  static const double _thumbInset = 4;

  double _dragX = 0; // current drag offset relative to track left edge
  double _trackWidth = 0;
  bool _confirmed = false;

  double get _thumbSize => _height - _thumbInset * 2;
  double get _maxDrag => (_trackWidth - _thumbSize - _thumbInset * 2)
      .clamp(0, double.infinity)
      .toDouble();

  void _onUpdate(DragUpdateDetails d) {
    if (widget.onConfirmed == null || _confirmed) return;
    setState(() {
      _dragX = (_dragX + d.delta.dx).clamp(0, _maxDrag);
    });
  }

  void _onEnd(DragEndDetails _) {
    if (widget.onConfirmed == null || _confirmed) return;
    final threshold = _maxDrag * 0.78;
    if (_dragX >= threshold) {
      setState(() {
        _confirmed = true;
        _dragX = _maxDrag;
      });
      widget.onConfirmed?.call();
    } else {
      setState(() => _dragX = 0);
    }
  }

  @override
  void didUpdateWidget(covariant _SwipeToConfirm oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the parent re-enables the slider (e.g. send retry), reset.
    if (oldWidget.onConfirmed == null && widget.onConfirmed != null) {
      _confirmed = false;
      _dragX = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onConfirmed == null && !widget.isLoading;
    final trackRadius = BorderRadius.circular(_height / 2);
    return Padding(
      // Small breathing room from the screen edges so the pill ends read
      // as smooth round caps rather than getting clipped by the safe-area
      // gutter.  Bottom inset keeps the pill floating just above the home
      // indicator on iOS.
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          _trackWidth = constraints.maxWidth;
          final progress = _maxDrag == 0 ? 0.0 : (_dragX / _maxDrag);
          return Container(
            height: _height,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: trackRadius,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.18),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.30),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: trackRadius,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Filled track that grows behind the thumb as it slides.
                  // Clipped by the parent rounded rect so the leading edge
                  // always meets the pill cap cleanly.
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: (_dragX + _thumbSize + _thumbInset * 2)
                        .clamp(0, _trackWidth)
                        .toDouble(),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 80),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            widget.matchColor.withValues(alpha: 0.9),
                            widget.matchColor.withValues(alpha: 0.55),
                          ],
                        ),
                      ),
                    ),
                  ),
              // Label fades out as the user drags.
              IgnorePointer(
                child: Opacity(
                  opacity: (1 - progress * 1.4).clamp(0.0, 1.0),
                  child: Padding(
                    padding: EdgeInsets.only(left: _thumbSize + 16, right: 16),
                    child: Text(
                      widget.label,
                      style: AppTextStyles.body.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
              // Draggable thumb.
              Positioned(
                left: _thumbInset + _dragX,
                top: _thumbInset,
                child: GestureDetector(
                  onHorizontalDragUpdate: disabled ? null : _onUpdate,
                  onHorizontalDragEnd: disabled ? null : _onEnd,
                  child: Container(
                    width: _thumbSize,
                    height: _thumbSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: widget.isLoading
                        ? Padding(
                            padding: const EdgeInsets.all(14),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                widget.matchColor,
                              ),
                            ),
                          )
                        : Icon(
                            Icons.chevron_right_rounded,
                            color: widget.matchColor,
                            size: 32,
                          ),
                  ),
                ),
              ),
              ],
            ),
          ),
        );
        },
      ),
    );
  }
}
