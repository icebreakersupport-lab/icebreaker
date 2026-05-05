import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';

import '../constants/app_constants.dart';

/// App-wide flow lock for the Icebreaker → Meetup pipeline.
///
/// The product requirement is two real "you cannot leave" states:
///
///   1. After sending an icebreaker, the sender is locked into a waiting
///      screen (`/icebreaker-waiting/{id}`) until the recipient
///      accepts, declines, or the icebreaker expires.
///   2. Once a meetup exists in `finding`, both participants are locked
///      into [AppRoutes.matched] until the meetup terminates (cancel,
///      timer expiry, or transition into `talking`).
///
/// Implementing those locks anywhere except the router invites bugs
/// — back-button overrides, deep links, race-y push/pop sequences.
/// Centralising them in a [ChangeNotifier] that the [GoRouter] reads via
/// `refreshListenable` plus a redirect closure makes the policy a single
/// pure function over observed Firestore state.
///
/// State sources (Cloud Functions are the only writers for state-machine
/// transitions; the client just observes):
///   • Outgoing pending icebreaker:
///     `icebreakers where senderId == me AND status == 'sent'` (most recent
///     unexpired).  Cleared the moment the CF flips status to accepted /
///     declined / expired.
///   • currentMeetupId: `users/{uid}.currentMeetupId`, written by
///     [onMeetupCreated] / cleared by [onMeetupTerminal].  This is the
///     same field [LiveSession] already mirrors into live_sessions for
///     visibility — we read it independently here so router redirect can
///     fire without depending on [LiveSession] being initialised.
///   • Current meetup status: `meetups/{currentMeetupId}.status`, used to
///     scope the lock to phases where it is product-correct (`finding`
///     today; `talking` / decision phases will join later).
///
/// [targetRoute] is the only thing the router reads.  When non-null, the
/// router redirects any other location to this path; when null, the user
/// is free to navigate anywhere.
class FlowCoordinator extends ChangeNotifier {
  FlowCoordinator({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance {
    _authSub = _auth.authStateChanges().listen(_onAuthChanged);
    _onAuthChanged(_auth.currentUser);
  }

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _outgoingSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _meetupSub;

  /// Forces re-evaluation of [pendingOutgoingIcebreakerId] when an icebreaker
  /// passes its TTL between snapshots.  Firestore won't push a new event when
  /// nothing changed in the doc, so without this tick a fresh-but-just-expired
  /// outgoing pending would keep the wait-screen lock indefinitely until the
  /// scheduled CF flips status to 'expired'.
  Timer? _expiryTick;

  String? _uid;
  String? _pendingOutgoingIcebreakerId;
  DateTime? _pendingOutgoingExpiresAt;
  String? _currentMeetupId;
  String? _currentMeetupStatus;
  String? _suppressedMatchedMeetupId;
  String? _pinnedMatchedMeetupId;

  /// Meetup ids we've already attempted to self-heal in this session.  Keeps
  /// [_isZombieMeetupSnapshot] from looping if the heal write fails — we try
  /// once per zombie per session, log on failure, and let a process restart
  /// or a fresh entry into the meetup re-arm the detector.
  final Set<String> _zombieHealAttempted = <String>{};

  /// The most recent outgoing icebreaker that's still 'sent' and not past
  /// expiresAt.  Null when there is none.
  String? get pendingOutgoingIcebreakerId => _pendingOutgoingIcebreakerId;

  /// The active meetup id pulled from `users/{uid}.currentMeetupId`, or null
  /// when the user is not in a meetup.
  String? get currentMeetupId => _currentMeetupId;

  /// Status of the meetup at [currentMeetupId], or null.
  String? get currentMeetupStatus => _currentMeetupStatus;

  /// While non-null, [targetRoute] forces the router to keep the user on
  /// `/meetup/matched/{id}` even after [currentMeetupId] has cleared. Set by
  /// [MatchedScreen] when it detects that the OTHER participant cancelled:
  /// the cancellee needs to see the "they cancelled — Return Home" message
  /// before being released, but `onMeetupTerminal` clears `currentMeetupId`
  /// almost immediately, which would otherwise let the matched-route release
  /// branch redirect them to /home before they read the message.
  String? get pinnedMatchedMeetupId => _pinnedMatchedMeetupId;

  /// Forced redirect target, or null when the user is unlocked.
  ///
  /// Priority: an active meetup outranks an outgoing pending icebreaker.
  /// In practice the two states are mutually exclusive — accept-on-recipient
  /// flips the icebreaker to 'accepted' and creates the meetup in the same
  /// transaction — but ordering them defensively makes the redirect total
  /// even if a stream lags.
  ///
  /// The status → route map mirrors the server-side state machine driven by
  /// onMeetupFoundConfirmed / onMeetupTalkExpired:
  ///
  ///   finding                     → /meetup/matched/{id}      (find each other)
  ///   talking                     → /meetup/color-match/{id}  (in conversation)
  ///   awaiting_post_talk_decision → /meetup/color-match/{id}  (frosted-glass
  ///                                                            decision overlay
  ///                                                            on top of the
  ///                                                            talk screen)
  ///
  /// Terminal statuses (matched / no_match / ended / expired_finding /
  /// cancelled_finding) cause the [onMeetupTerminal] CF to clear
  /// currentMeetupId, which makes the meetup branch fall through to null and
  /// releases the user.
  String? get targetRoute {
    // Cancellee pin wins over everything: when the other participant has
    // cancelled the finding meetup, we hold this user on MatchedScreen so
    // they can read "{name} cancelled — Return Home" before tapping out.
    // Without the pin override, the cleanup CF clearing currentMeetupId
    // would let the release branch in the router redirect to /home before
    // the user sees the message.
    final pinned = _pinnedMatchedMeetupId;
    if (pinned != null) return '${AppRoutes.matched}/$pinned';

    final meetupId = _currentMeetupId;
    if (meetupId != null) {
      // A user-explicit exit during finding OR talking suppresses the lock for
      // that meetup id until the cleanup CF clears currentMeetupId.  The
      // suppress flag is phase-agnostic on purpose: the exit flow (cancel
      // confirmation + best-effort cancelRequest write) is identical in both
      // phases, and the user has already chosen to leave by the time it's set.
      if (_suppressedMatchedMeetupId == meetupId &&
          (_currentMeetupStatus == 'finding' ||
              _currentMeetupStatus == 'talking')) {
        return null;
      }
      switch (_currentMeetupStatus) {
        case 'finding':
          return '${AppRoutes.matched}/$meetupId';
        case 'talking':
        case 'awaiting_post_talk_decision':
          // The talk screen owns the decision phase too — it renders the
          // frosted-glass "Pass / Stay in touch" overlay over the (still-
          // visible) photo pair so the moment of choosing stays visually
          // anchored to the person you just talked to.
          return '${AppRoutes.colorMatch}/$meetupId';
      }
      // Status null (initial snapshot) or any other value (terminal that the
      // CF hasn't yet cleared, or an unknown transition state) — fall through
      // to no lock so the user isn't stranded if the cascade lags.
    }
    final pending = _pendingOutgoingIcebreakerId;
    if (pending != null) {
      return '${AppRoutes.icebreakerWaiting}/$pending';
    }
    return null;
  }

  /// Optimistically seeds the sender wait lock immediately after a successful
  /// send transaction commits and before the outgoing Firestore stream has had
  /// time to deliver the new `status == 'sent'` document.
  ///
  /// Why this exists: without a local seed, `SendIcebreakerScreen` can
  /// navigate to `/icebreaker-waiting/{id}` before [_onOutgoingSnap] has set
  /// [_pendingOutgoingIcebreakerId]. During that brief window [targetRoute] is
  /// still null, so the router's release branch thinks the user is on a stale
  /// wait screen and bounces them to Home. The subsequent stream snapshot
  /// remains the source of truth — it confirms, replaces, or clears this
  /// optimistic value as soon as Firestore catches up.
  void seedPendingOutgoing({
    required String icebreakerId,
    required DateTime expiresAt,
  }) {
    final changed = _pendingOutgoingIcebreakerId != icebreakerId ||
        _pendingOutgoingExpiresAt != expiresAt;
    _pendingOutgoingIcebreakerId = icebreakerId;
    _pendingOutgoingExpiresAt = expiresAt;
    if (changed) notifyListeners();
  }

  /// Temporarily suppresses the matched-screen flow lock for one meetup after
  /// the user explicitly chooses to leave (timed-out "Return Home" or cancel
  /// confirmation).  Does NOT mutate Firestore state; only stops the router
  /// from bouncing a manual Home navigation back to `/meetup/matched/{id}`
  /// while backend cleanup catches up.
  ///
  /// User-explicit exits are trusted unconditionally — the previous defensive
  /// guard (`_currentMeetupId == meetupId && _currentMeetupStatus == 'finding'`)
  /// quietly no-op'd the suppress on cold-start race windows, after which the
  /// `notifyListeners` and `context.go(home)` would race the router redirect
  /// and bounce the user right back to the matched screen with no visible
  /// effect.  The auto-clear in [_clearSuppressedMatchedMeetupIfStale] still
  /// undoes the suppression on the next snapshot if it isn't appropriate, so
  /// the unguarded path is safe; the user is on their way to /home before
  /// that next snapshot lands.
  void suppressMatchedLockForTimedOutExit({
    required String meetupId,
  }) {
    if (_suppressedMatchedMeetupId == meetupId) return;
    _suppressedMatchedMeetupId = meetupId;
    notifyListeners();
  }

  /// Holds the cancellee on `/meetup/matched/{meetupId}` after the other
  /// participant has cancelled, so they can see the "they cancelled — Return
  /// Home" panel.  Called by [MatchedScreen] from its meetup stream listener
  /// the moment it sees `status == 'cancelled_finding'` with a `cancelledBy`
  /// that is not this user.  The pin is released by
  /// [releasePinnedMatchedScreen] when the user taps Return Home, by sign-out,
  /// or by entering a new meetup.
  void pinMatchedScreenForReview({required String meetupId}) {
    if (_pinnedMatchedMeetupId == meetupId) return;
    _pinnedMatchedMeetupId = meetupId;
    notifyListeners();
  }

  /// Releases a [pinMatchedScreenForReview] pin set on [meetupId].  No-op when
  /// the pin is already cleared or pointed at a different meetup.
  void releasePinnedMatchedScreen({required String meetupId}) {
    if (_pinnedMatchedMeetupId != meetupId) return;
    _pinnedMatchedMeetupId = null;
    notifyListeners();
  }

  // ── Wiring ──────────────────────────────────────────────────────────────────

  void _onAuthChanged(User? user) {
    final uid = user?.uid;
    if (uid == _uid) return;
    _uid = uid;
    _outgoingSub?.cancel();
    _outgoingSub = null;
    _userSub?.cancel();
    _userSub = null;
    _meetupSub?.cancel();
    _meetupSub = null;
    _expiryTick?.cancel();
    _expiryTick = null;

    final didChange = _pendingOutgoingIcebreakerId != null ||
        _currentMeetupId != null ||
        _currentMeetupStatus != null ||
        _suppressedMatchedMeetupId != null ||
        _pinnedMatchedMeetupId != null;
    _pendingOutgoingIcebreakerId = null;
    _pendingOutgoingExpiresAt = null;
    _currentMeetupId = null;
    _currentMeetupStatus = null;
    _suppressedMatchedMeetupId = null;
    _pinnedMatchedMeetupId = null;
    _zombieHealAttempted.clear();

    if (uid == null) {
      if (didChange) notifyListeners();
      return;
    }

    _attachStreams(uid);
    if (didChange) notifyListeners();
  }

  void _attachStreams(String uid) {
    _outgoingSub = _firestore
        .collection('icebreakers')
        .where('senderId', isEqualTo: uid)
        .where('status', isEqualTo: 'sent')
        .orderBy('createdAt', descending: true)
        .limit(1)
        .snapshots()
        .listen(
      _onOutgoingSnap,
      onError: (Object e) =>
          debugPrint('[FlowCoordinator] outgoing stream error: $e'),
    );

    _userSub = _firestore.collection('users').doc(uid).snapshots().listen(
      _onUserSnap,
      onError: (Object e) =>
          debugPrint('[FlowCoordinator] user stream error: $e'),
    );

    _expiryTick = Timer.periodic(const Duration(seconds: 15), (_) {
      _evaluateExpiry();
    });
  }

  void _onOutgoingSnap(QuerySnapshot<Map<String, dynamic>> snap) {
    String? nextId;
    DateTime? nextExpiresAt;
    final now = DateTime.now();
    for (final doc in snap.docs) {
      final data = doc.data();
      final expiresAt = (data['expiresAt'] as Timestamp?)?.toDate();
      if (expiresAt == null || expiresAt.isAfter(now)) {
        nextId = doc.id;
        nextExpiresAt = expiresAt;
        break;
      }
    }
    if (nextId != _pendingOutgoingIcebreakerId) {
      _pendingOutgoingIcebreakerId = nextId;
      _pendingOutgoingExpiresAt = nextExpiresAt;
      notifyListeners();
    } else {
      _pendingOutgoingExpiresAt = nextExpiresAt;
    }
  }

  void _onUserSnap(DocumentSnapshot<Map<String, dynamic>> snap) {
    final next = snap.data()?['currentMeetupId'] as String?;
    if (next == _currentMeetupId) return;

    _currentMeetupId = next;
    _meetupSub?.cancel();
    _meetupSub = null;
    final hadStatus = _currentMeetupStatus != null;
    _currentMeetupStatus = null;
    final clearedOverride = _clearSuppressedMatchedMeetupIfStale();
    // If the user just entered a *different* meetup, drop a stale cancellee
    // pin from a previous meetup — the new meetup's natural target route
    // should win.  We intentionally do NOT clear the pin when next == null
    // (that's exactly the case the pin is designed to cover: cleanup CF has
    // wiped currentMeetupId on the cancellee, we still want them on the
    // "they cancelled" panel until they tap Return Home).
    if (_pinnedMatchedMeetupId != null &&
        next != null &&
        next != _pinnedMatchedMeetupId) {
      _pinnedMatchedMeetupId = null;
    }

    if (next != null) {
      _meetupSub =
          _firestore.collection('meetups').doc(next).snapshots().listen(
        (mSnap) {
          final data = mSnap.data();
          final status = data?['status'] as String?;

          // Zombie self-heal.  `users.currentMeetupId` is supposed to be
          // cleared by `onMeetupTerminal` when the meetup reaches a terminal
          // status, and by `onMeetupFindingExpired` when the find timer
          // crosses TTL.  When a CF crashes / lags / never deploys, both
          // participants stay stuck with their `live_sessions.visibilityState`
          // mirrored to `hidden_in_meetup`, so neither shows up in Nearby.
          // Detect that state from the only authoritative thing we trust —
          // the meetup doc itself — and clear our own currentMeetupId.  The
          // LiveSession mirror writes `discoverable` automatically once the
          // user-doc tick lands.
          if (_isZombieMeetupSnapshot(meetupId: next, snap: mSnap)) {
            unawaited(_selfHealClearCurrentMeetupId(next, status: status));
            return;
          }

          if (status == _currentMeetupStatus) return;
          _currentMeetupStatus = status;
          _clearSuppressedMatchedMeetupIfStale();
          notifyListeners();
        },
        onError: (Object e) =>
            debugPrint('[FlowCoordinator] meetup stream error: $e'),
      );
    }

    notifyListeners();
    // If we cleared status in the same tick, the notify above already covered
    // that change.  The `hadStatus` flag is just a defensive belt — redirect
    // re-evaluation is idempotent.
    if (hadStatus && _currentMeetupStatus == null && next == null) {
      // single notify already issued
    }
    if (clearedOverride) {
      // single notify already issued
    }
  }

  /// Set of statuses that should always have triggered `onMeetupTerminal` to
  /// clear `users.currentMeetupId`.  Seeing any of these on the meetup our
  /// user-doc still points at is positive evidence of a stranded mirror
  /// (CF crash, missed deploy, expired retry budget) and warrants a self-heal.
  static const _terminalStatuses = <String>{
    'matched',
    'no_match',
    'ended',
    'expired_finding',
    'cancelled_finding',
    'cancelled_talking',
  };

  /// Returns true when the meetup snapshot represents a zombie state that
  /// requires us to self-clear `users/{me}.currentMeetupId`.
  ///
  /// Two positive cases:
  ///   1. Status is in [_terminalStatuses].  `onMeetupTerminal` should have
  ///      cleared currentMeetupId; if it didn't, we do.
  ///   2. Status is `finding` but `findExpiresAt` is past by more than 90 s.
  ///      The scheduled `onMeetupFindingExpired` runs every 1 min, so a 90 s
  ///      lag is well outside the normal envelope and indicates the schedule
  ///      isn't running.
  ///
  /// Deliberately does NOT trigger on `!snap.exists`: a freshly-created
  /// meetup can briefly look "missing" between the user-doc write that sets
  /// currentMeetupId and the meetup-doc write propagating to this listener.
  /// Triggering on absence would race that window and clear a real,
  /// in-flight meetup before it stabilises.  A meetup that genuinely never
  /// existed will still drop us out via the terminal-status path the moment
  /// any CF flips its status, which always happens for a real meetup id.
  bool _isZombieMeetupSnapshot({
    required String meetupId,
    required DocumentSnapshot<Map<String, dynamic>> snap,
  }) {
    if (_zombieHealAttempted.contains(meetupId)) return false;
    if (!snap.exists) return false;
    final data = snap.data();
    final status = data?['status'] as String?;
    if (_terminalStatuses.contains(status)) return true;
    if (status == 'finding') {
      final exp = (data?['findExpiresAt'] as Timestamp?)?.toDate();
      if (exp != null &&
          DateTime.now().difference(exp) > const Duration(seconds: 90)) {
        return true;
      }
    }
    return false;
  }

  /// Clears `users/{uid}.currentMeetupId` to break the user out of a stranded
  /// meetup mirror.  Marked attempted in [_zombieHealAttempted] before the
  /// write so a failed write doesn't loop the listener.  The user-doc write
  /// triggers [_onUserSnap] → cancels [_meetupSub] → flips this user's
  /// `live_sessions.visibilityState` to `discoverable` via the [LiveSession]
  /// mirror, which is exactly what un-zombies Nearby for them.
  Future<void> _selfHealClearCurrentMeetupId(
    String meetupId, {
    String? status,
  }) async {
    final uid = _uid;
    if (uid == null) return;
    if (!_zombieHealAttempted.add(meetupId)) return;
    debugPrint(
        '[FlowCoordinator] self-heal: clearing currentMeetupId=$meetupId '
        '(status=$status) — onMeetupTerminal/onMeetupFindingExpired did not '
        'run');
    try {
      await _firestore.collection('users').doc(uid).update({
        'currentMeetupId': FieldValue.delete(),
      });
      debugPrint(
          '[FlowCoordinator] self-heal write OK for currentMeetupId=$meetupId');
    } catch (e) {
      debugPrint('[FlowCoordinator] self-heal write FAILED ($e) — '
          'leaving _zombieHealAttempted set; restart will retry');
    }
  }

  bool _clearSuppressedMatchedMeetupIfStale() {
    final suppressed = _suppressedMatchedMeetupId;
    if (suppressed == null) return false;
    // Keep the suppress active while the user is still in the same meetup AND
    // we're in a phase where they can hit exit (finding or talking).  Any
    // other phase (awaiting_post_talk_decision, terminal, or no meetup at all)
    // means the natural lifecycle has moved past the cancel window, so the
    // override is no longer load-bearing.
    if (_currentMeetupId == suppressed &&
        (_currentMeetupStatus == 'finding' ||
            _currentMeetupStatus == 'talking')) {
      return false;
    }
    _suppressedMatchedMeetupId = null;
    return true;
  }

  /// Tick handler — re-evaluates the pending outgoing icebreaker against the
  /// wall clock so a TTL crossing without a corresponding Firestore write
  /// (the scheduled-expire CF runs every minute, not every second) still
  /// releases the wait-screen lock promptly.
  void _evaluateExpiry() {
    if (_pendingOutgoingIcebreakerId == null) return;
    final exp = _pendingOutgoingExpiresAt;
    if (exp == null) return;
    if (DateTime.now().isBefore(exp)) return;
    debugPrint(
        '[FlowCoordinator] pending outgoing crossed TTL — releasing lock');
    _pendingOutgoingIcebreakerId = null;
    _pendingOutgoingExpiresAt = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _outgoingSub?.cancel();
    _userSub?.cancel();
    _meetupSub?.cancel();
    _expiryTick?.cancel();
    super.dispose();
  }
}

/// InheritedNotifier scope so any widget under the app root can read the
/// coordinator without a manual provider.  Mirrors [DemoProfileScope] +
/// [LiveSessionScope] for consistency.
class FlowCoordinatorScope extends InheritedNotifier<FlowCoordinator> {
  const FlowCoordinatorScope({
    super.key,
    required FlowCoordinator coordinator,
    required super.child,
  }) : super(notifier: coordinator);

  static FlowCoordinator of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<FlowCoordinatorScope>();
    assert(scope != null, 'No FlowCoordinatorScope found in widget tree.');
    return scope!.notifier!;
  }
}
