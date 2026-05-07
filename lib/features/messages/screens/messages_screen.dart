import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/gradient_scaffold.dart';
import '../../../shared/widgets/icebreaker_logo.dart';
import '../widgets/active_now_card.dart';
import '../widgets/message_list_card.dart';
import '../widgets/messages_section_header.dart';
import 'chat_thread_screen.dart';
import '../../meetup/screens/icebreaker_received_screen.dart';

/// Messages tab — four Firestore-backed sections.
///
/// Section 1 — Active Now: time-sensitive items, sorted urgency-first.
///   * Pending icebreakers received (status='sent', expiresAt > now)
///   * Pending icebreakers sent     (status='sent', expiresAt > now)
///
/// Section 2 — Matches: active conversations (status='active') that have
///   never had a message sent — i.e. the post-meet "stay in touch"
///   moment landed but neither person has texted yet.  Rendered as a
///   horizontal avatar strip so they read as a "fresh tray" rather than
///   another list of rows.  Tapping opens the chat thread, same as Chats.
///
/// Section 3 — Chats: active conversations (status='active') with at
///   least one message, sorted by lastMessageAt DESC.
///
/// Section 4 — History: ended/expired/blocked conversations, plus expired
///   icebreakers (status='expired').  Sent icebreakers that produced a
///   conversation stay at status='sent' in Firestore (the unlock cloud
///   function does not rewrite the icebreaker), so filtering history to
///   status='expired' naturally deduplicates against the corresponding
///   conversation row.
class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

/// Per-stream lifecycle state.  Tracked independently for each of the three
/// Firestore subscriptions so the screen can never deadlock on a single
/// failing stream:
///   loading — initial state; no snapshot or error has arrived yet.
///   ready   — at least one snapshot delivered (may still be empty).
///   error   — the stream's onError fired (e.g. missing composite index,
///             rules denial, network).  Treated as "this stream contributes
///             zero items" by [_partition], and surfaces a retry affordance
///             at the screen level.
enum _StreamState { loading, ready, error }

class _MessagesScreenState extends State<MessagesScreen>
    with WidgetsBindingObserver {
  String? _myUid;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _receivedSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sentSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _convSub;

  /// Latest snapshots — set on every successful event and reset on retry.
  /// Defaults to const [] (not null) so [_partition] can always run; per-
  /// stream readiness is tracked separately by [_StreamState].
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _received = const [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _sent = const [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _conversations = const [];

  _StreamState _receivedState = _StreamState.loading;
  _StreamState _sentState = _StreamState.loading;
  _StreamState _convState = _StreamState.loading;

  /// First error message captured across the three streams — surfaced under
  /// the retry button so a missing-index URL is visible to the developer
  /// without a separate console trip.
  String? _firstError;

  /// Per-section readiness — drives an incremental render policy so the
  /// screen never blocks on the slowest stream.
  ///
  /// Chats are sourced exclusively from the conversations stream, so the
  /// section can render the moment that single snapshot arrives — even if
  /// the two icebreaker streams are still in flight.
  bool get _chatsReady => _convState == _StreamState.ready;

  /// Active Now and History both require all three streams:
  ///   * Active Now's "icebreaker sent" path is deduped against the
  ///     conversations stream (icebreakers whose `sourceIcebreakerId`
  ///     already produced a conversation are hidden), and the section
  ///     also unions received-pending + sent-pending — printing one
  ///     without the others would either double-show or under-show items.
  ///   * History merges three sources (received-expired, sent-expired,
  ///     conversation-history); the same dedup against
  ///     `sourceIcebreakerId` applies, and a stale render would show an
  ///     "Icebreaker expired" row alongside its already-graduated
  ///     conversation row.
  ///
  /// So both sections gate on the full triple being [_StreamState.ready].
  bool get _allStreamsReady =>
      _receivedState == _StreamState.ready &&
      _sentState == _StreamState.ready &&
      _convState == _StreamState.ready;

  /// True when at least one stream errored out — drives the screen-level
  /// retry UX.  Partial data from the streams that did succeed is
  /// intentionally not rendered when this is true: with one stream missing
  /// the partition is incomplete (e.g. dedupe between sent icebreakers and
  /// conversations would misclassify items), so the safer UX is "tell the
  /// user something failed and let them retry" rather than show a
  /// suspiciously short list.
  bool get _hasAnyError =>
      _receivedState == _StreamState.error ||
      _sentState == _StreamState.error ||
      _convState == _StreamState.error;

  /// Forces a 30-second tick so countdowns expire client-side without a
  /// Firestore write — pending icebreakers move from Active Now to History
  /// the moment expiresAt passes.
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _myUid = FirebaseAuth.instance.currentUser?.uid;
    _attachStreams();
    // Re-attach streams whenever the auth uid changes (sign-in, sign-out,
    // account switch).  Without this, the screen keeps listening under the
    // uid that was current at first build — invisible to the user when they
    // switch accounts and explains why a freshly-sent icebreaker never
    // appears for users whose State outlived an auth change.
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      final newUid = user?.uid;
      if (newUid == _myUid) return;
      _myUid = newUid;
      _resetStreams();
      _attachStreams();
    });
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSub?.cancel();
    _receivedSub?.cancel();
    _sentSub?.cancel();
    _convSub?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  /// On iOS, Firestore listeners can get stuck after the app spends time in
  /// the background — the connection silently drops and reattach is needed
  /// to resume real-time updates.  Force a clean re-attach on every resume
  /// so the Messages screen always reflects the current server state, not a
  /// stale local cache from before the app went to sleep.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final current = FirebaseAuth.instance.currentUser?.uid;
    _myUid = current;
    _resetStreams();
    _attachStreams();
  }

  /// Cancels active Firestore subscriptions and resets the per-stream
  /// readiness/error state to `loading`.  Used by `_retry`, the auth-change
  /// listener, and the resume hook so re-attach always starts from a clean
  /// slate (not "ready with stale data").
  void _resetStreams() {
    _receivedSub?.cancel();
    _sentSub?.cancel();
    _convSub?.cancel();
    if (!mounted) return;
    setState(() {
      _received = const [];
      _sent = const [];
      _conversations = const [];
      _receivedState = _StreamState.loading;
      _sentState = _StreamState.loading;
      _convState = _StreamState.loading;
      _firstError = null;
    });
  }

  void _attachStreams() {
    final uid = _myUid;
    if (uid == null) return;
    final db = FirebaseFirestore.instance;

    _receivedSub = db
        .collection('icebreakers')
        .where('recipientId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .listen(
          (snap) {
            if (!mounted) return;
            setState(() {
              _received = snap.docs;
              _receivedState = _StreamState.ready;
            });
          },
          onError: (Object e) => _onStreamError('received', e, (s) {
            _receivedState = s;
            _received = const [];
          }),
        );

    _sentSub = db
        .collection('icebreakers')
        .where('senderId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .listen(
          (snap) {
            if (!mounted) return;
            setState(() {
              _sent = snap.docs;
              _sentState = _StreamState.ready;
            });
          },
          onError: (Object e) => _onStreamError('sent', e, (s) {
            _sentState = s;
            _sent = const [];
          }),
        );

    _convSub = db
        .collection('conversations')
        .where('participants', arrayContains: uid)
        .orderBy('lastMessageAt', descending: true)
        .limit(50)
        .snapshots()
        .listen(
          (snap) {
            if (!mounted) return;
            setState(() {
              _conversations = snap.docs;
              _convState = _StreamState.ready;
            });
          },
          onError: (Object e) => _onStreamError('conv', e, (s) {
            _convState = s;
            _conversations = const [];
          }),
        );
  }

  /// Single sink for stream errors.  Logs the failure with enough detail to
  /// recover the missing-index URL Firestore prints, marks the stream as
  /// errored (so [_hasAnyError] flips true and the screen drops out of any
  /// loading state into the retry UX), and remembers the first error for
  /// display under the retry CTA.
  void _onStreamError(
    String label,
    Object error,
    void Function(_StreamState) apply,
  ) {
    debugPrint('[Messages] $label stream error: $error');
    if (!mounted) return;
    setState(() {
      apply(_StreamState.error);
      _firstError ??= error.toString();
    });
  }

  /// Cancels the existing subscriptions and re-attaches all three streams
  /// from a clean slate.  Triggered by the Retry button on the error state
  /// and by pull-to-refresh.
  void _retry() {
    _resetStreams();
    _attachStreams();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: _buildAppBar(),
      body: SafeArea(
        top: false,
        child: _buildBody(context),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      title: Text('Messages', style: AppTextStyles.h3),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_myUid == null) {
      return _buildEmptyState();
    }
    // Any errored stream → screen-level retry.  Rendering partial data here
    // would risk a misleading partition (e.g. dedupe between sent icebreakers
    // and conversations would misclassify items if the conversations stream
    // failed), so the safer UX is to surface the failure and offer retry.
    if (_hasAnyError) {
      return _buildErrorState();
    }

    // Full-screen spinner only while *nothing* renderable has arrived yet.
    // Chats is the first section that can paint (it depends on the
    // conversations stream alone), so we exit the spinner the moment
    // [_chatsReady] flips true even if the two icebreaker streams haven't
    // reported in.  The Active Now / History sections then fade in
    // independently as [_allStreamsReady] flips true.
    if (!_chatsReady) {
      return const Center(child: CircularProgressIndicator());
    }

    final partition = _partition();

    // Empty-state must wait for every stream — otherwise a user who has
    // pending icebreakers but no active conversations would briefly see
    // "Send your first Icebreaker" between the conversations snapshot and
    // the icebreaker snapshots.
    if (_allStreamsReady && partition.isEmpty) {
      return _buildEmptyState();
    }

    return ListView(
      children: [
        // Active Now is gated on all three streams being ready: the section
        // unions received-pending + sent-pending and dedupes the latter
        // against the converted-conversation set.  Showing it before all
        // three are in would either over-show (missing dedupe) or
        // under-show (missing branch).
        if (_allStreamsReady && partition.activeNow.isNotEmpty) ...[
          MessagesSectionHeader(
            title: 'Active Now',
            badge: partition.activeNow.length,
          ),
          ...partition.activeNow.map(
            (item) => ActiveNowCard(
              otherFirstName: item.otherFirstName,
              otherPhotoUrl: item.otherPhotoUrl,
              statusLabel: item.statusLabel,
              secondsRemaining: item.secondsRemaining,
              onTap: () => _onActiveNowTap(item),
            ),
          ),
        ],
        // Matches — horizontal avatar strip of mutual stay-in-touch pairs
        // who haven't messaged yet.  Sourced exclusively from the
        // conversations stream so it's gated by the same [_chatsReady]
        // check as Chats; renders the moment a fresh post-meet match
        // lands, even if the icebreaker streams are still in flight.
        if (partition.matches.isNotEmpty) ...[
          MessagesSectionHeader(
            title: 'Matches',
            badge: partition.matches.length,
          ),
          SizedBox(
            height: 124,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: partition.matches.length,
              itemBuilder: (_, i) {
                final m = partition.matches[i];
                return _MatchAvatarTile(
                  match: m,
                  onTap: () => _onMatchTap(m),
                );
              },
            ),
          ),
        ],
        // Chats requires only the conversations stream — guard already
        // satisfied by the [_chatsReady] check above, so no extra gate
        // needed here beyond "is the list non-empty".
        if (partition.chats.isNotEmpty) ...[
          const MessagesSectionHeader(title: 'Chats'),
          ...partition.chats.map(
            (item) => Column(
              children: [
                MessageListCard(
                  otherFirstName: item.otherFirstName,
                  otherPhotoUrl: item.otherPhotoUrl,
                  previewText: item.previewText,
                  timestamp: item.timestamp,
                  hasUnread: item.hasUnread,
                  onTap: () => _onChatTap(item),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Divider(height: 1),
                ),
              ],
            ),
          ),
        ],
        // History merges all three streams (expired received + expired sent
        // + ended/expired/blocked conversations) and reuses the same
        // sourceIcebreakerId dedupe — so it gates on the full triple too.
        if (_allStreamsReady && partition.history.isNotEmpty) ...[
          const MessagesSectionHeader(title: 'History'),
          ...partition.history.map(
            (item) => MessageListCard(
              otherFirstName: item.otherFirstName,
              otherPhotoUrl: item.otherPhotoUrl,
              previewText: item.previewText,
              timestamp: item.timestamp,
              isDimmed: true,
              statusIcon: item.icon,
              onTap: () => _onHistoryTap(item),
            ),
          ),
        ],
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const IcebreakerLogo(size: 72, showGlow: false),
            const SizedBox(height: 24),
            Text(
              'Send your first Icebreaker 🧊',
              style: AppTextStyles.h3,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Go Live and browse people nearby.\nWhen you connect, conversations appear here.',
              style: AppTextStyles.bodyS,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// Screen-level failure state.  Shown when any of the three streams hits
  /// onError so the UI never sits on an indefinite spinner.  The Retry button
  /// re-attaches all three subscriptions; the captured Firestore error is
  /// shown below in muted text so a missing-index URL is recoverable without
  /// digging through `flutter logs`.
  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 56,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              "Couldn't load messages",
              style: AppTextStyles.h3,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Check your connection and try again.',
              style: AppTextStyles.bodyS,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            TextButton.icon(
              onPressed: _retry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
            if (_firstError != null) ...[
              const SizedBox(height: 16),
              Text(
                _firstError!,
                style: AppTextStyles.bodyS.copyWith(
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Partition ──────────────────────────────────────────────────────────────

  /// Single pass over the three Firestore snapshots that produces the three
  /// rendered sections.  Centralising the rules here keeps the dedup
  /// invariants ("an icebreaker that produced a conversation appears only as
  /// the conversation row") in one place.
  _MessagesPartition _partition() {
    final myUid = _myUid!;
    final now = DateTime.now();

    final activeNow = <_ActiveNowItem>[];
    final matches = <_MatchItem>[];
    final chats = <_ChatItem>[];
    final history = <_HistoryItem>[];

    // ── Icebreakers received ────────────────────────────────────────────────
    for (final doc in _received) {
      final data = doc.data();
      final status = data['status'] as String? ?? '';
      final expiresAt = (data['expiresAt'] as Timestamp?)?.toDate();
      final senderFirstName = data['senderFirstName'] as String? ?? 'Someone';
      final senderId = data['senderId'] as String? ?? '';
      final message = data['message'] as String? ?? '';
      final createdAt = (data['createdAt'] as Timestamp?)?.toDate();

      // Pending and not yet expired → Active Now (incoming).
      if (status == 'sent' &&
          expiresAt != null &&
          expiresAt.isAfter(now)) {
        activeNow.add(_ActiveNowItem(
          icebreakerId: doc.id,
          kind: _ActiveKind.icebreakerReceived,
          otherFirstName: senderFirstName,
          otherPhotoUrl: '', // resolved on tap
          otherUserId: senderId,
          statusLabel: 'Respond to Icebreaker 🧊',
          secondsRemaining:
              expiresAt.difference(now).inSeconds.clamp(0, 1 << 30),
          expiresAt: expiresAt,
          message: message,
          sentAt: createdAt,
          sortKey: expiresAt.millisecondsSinceEpoch,
        ));
        continue;
      }

      // Anything past Active Now → History.  Status drives the preview/icon;
      // accepted icebreakers join their meetup outcome to differentiate the
      // post-accept stages (no_match, cancelled_finding, etc.).
      final terminal = _terminalForIcebreaker(
        status: status,
        meetupOutcome: data['meetupOutcome'] as String?,
        expiresAt: expiresAt,
        now: now,
      );
      if (terminal != null) {
        // Matched: handled by the conversation row, never the icebreaker.
        if (terminal.skip) continue;
        history.add(_HistoryItem(
          icebreakerId: doc.id,
          conversationId: null,
          isOutgoing: false,
          otherFirstName: senderFirstName,
          otherPhotoUrl: '',
          previewText: terminal.previewIncoming,
          timestamp: _formatRelative(
            terminal.timestampSource(
              expiresAt: expiresAt,
              createdAt: createdAt,
              concludedAt:
                  (data['meetupConcludedAt'] as Timestamp?)?.toDate(),
            ),
            now,
          ),
          icon: terminal.icon,
          message: message,
          status: terminal.statusCode,
          sentAt: createdAt,
          expiresAt: expiresAt,
          sortMs: (terminal
                      .timestampSource(
                        expiresAt: expiresAt,
                        createdAt: createdAt,
                        concludedAt: (data['meetupConcludedAt'] as Timestamp?)
                            ?.toDate(),
                      ) ??
                  now)
              .millisecondsSinceEpoch,
        ));
      }
    }

    // ── Icebreakers sent ────────────────────────────────────────────────────
    // sourceIcebreakerId on conversations lets us hide "sent" icebreakers
    // that already became conversations, so the same thread doesn't appear in
    // both Active Now (locked) and Chats (unlocked).
    final convertedIcebreakerIds = <String>{
      for (final c in _conversations)
        if ((c.data()['sourceIcebreakerId'] as String?)?.isNotEmpty ?? false)
          c.data()['sourceIcebreakerId'] as String,
    };

    for (final doc in _sent) {
      final data = doc.data();
      final status = data['status'] as String? ?? '';
      final expiresAt = (data['expiresAt'] as Timestamp?)?.toDate();
      final recipientFirstName =
          data['recipientFirstName'] as String? ?? 'Someone';
      final recipientId = data['recipientId'] as String? ?? '';
      final message = data['message'] as String? ?? '';
      final createdAt = (data['createdAt'] as Timestamp?)?.toDate();

      // Once a conversation exists for this icebreaker, the conversation
      // is the source of truth — skip the icebreaker entirely.
      if (convertedIcebreakerIds.contains(doc.id)) continue;

      if (status == 'sent' &&
          expiresAt != null &&
          expiresAt.isAfter(now)) {
        activeNow.add(_ActiveNowItem(
          icebreakerId: doc.id,
          kind: _ActiveKind.icebreakerSent,
          otherFirstName: recipientFirstName,
          otherPhotoUrl: '',
          otherUserId: recipientId,
          statusLabel: 'Waiting for $recipientFirstName',
          secondsRemaining:
              expiresAt.difference(now).inSeconds.clamp(0, 1 << 30),
          expiresAt: expiresAt,
          message: message,
          sentAt: createdAt,
          sortKey: expiresAt.millisecondsSinceEpoch,
        ));
        continue;
      }

      final terminal = _terminalForIcebreaker(
        status: status,
        meetupOutcome: data['meetupOutcome'] as String?,
        expiresAt: expiresAt,
        now: now,
      );
      if (terminal != null) {
        if (terminal.skip) continue;
        history.add(_HistoryItem(
          icebreakerId: doc.id,
          conversationId: null,
          isOutgoing: true,
          otherFirstName: recipientFirstName,
          otherPhotoUrl: '',
          previewText: terminal.previewOutgoing,
          timestamp: _formatRelative(
            terminal.timestampSource(
              expiresAt: expiresAt,
              createdAt: createdAt,
              concludedAt:
                  (data['meetupConcludedAt'] as Timestamp?)?.toDate(),
            ),
            now,
          ),
          icon: terminal.icon,
          message: message,
          status: terminal.statusCode,
          sentAt: createdAt,
          expiresAt: expiresAt,
          sortMs: (terminal
                      .timestampSource(
                        expiresAt: expiresAt,
                        createdAt: createdAt,
                        concludedAt: (data['meetupConcludedAt'] as Timestamp?)
                            ?.toDate(),
                      ) ??
                  now)
              .millisecondsSinceEpoch,
        ));
      }
    }

    // ── Conversations ───────────────────────────────────────────────────────
    for (final doc in _conversations) {
      final data = doc.data();
      final status = data['status'] as String? ?? '';
      final participants =
          List<String>.from((data['participants'] as List<dynamic>?) ?? []);
      final otherUid = participants.firstWhere(
        (p) => p != myUid,
        orElse: () => '',
      );
      if (otherUid.isEmpty) continue;
      final names = (data['participantNames'] as Map<String, dynamic>?) ?? {};
      final photos = (data['participantPhotos'] as Map<String, dynamic>?) ?? {};
      final otherFirstName = (names[otherUid] as String?) ?? 'Someone';
      final otherPhotoUrl = (photos[otherUid] as String?) ?? '';
      final lastMessage = data['lastMessage'] as String? ?? '';
      final lastMessageAt = (data['lastMessageAt'] as Timestamp?)?.toDate();
      final unread = (data['unreadCount_$myUid'] as num?)?.toInt() ?? 0;

      if (status == 'active') {
        // Split active conversations by whether anyone has messaged yet.
        // Pre-message threads land in the Matches strip (the trophy);
        // post-message threads land in Chats with the latest preview.
        // The CF stamps lastMessageAt = createdAt at conversation creation,
        // so the sortMs is the match-age regardless of which bucket.
        final sortMs = (lastMessageAt ?? DateTime(1970)).millisecondsSinceEpoch;
        if (lastMessage.isEmpty) {
          matches.add(_MatchItem(
            conversationId: doc.id,
            otherFirstName: otherFirstName,
            otherPhotoUrl: otherPhotoUrl,
            sortMs: sortMs,
          ));
        } else {
          chats.add(_ChatItem(
            conversationId: doc.id,
            otherFirstName: otherFirstName,
            otherPhotoUrl: otherPhotoUrl,
            previewText: lastMessage,
            timestamp: _formatRelative(lastMessageAt, now),
            hasUnread: unread > 0,
            sortMs: sortMs,
          ));
        }
      } else if (status == 'ended' ||
          status == 'expired' ||
          status == 'blocked') {
        history.add(_HistoryItem(
          icebreakerId: null,
          conversationId: doc.id,
          isOutgoing: false,
          otherFirstName: otherFirstName,
          otherPhotoUrl: otherPhotoUrl,
          previewText: switch (status) {
            'blocked' => 'Conversation closed',
            'expired' => 'Conversation expired',
            _ => 'Conversation ended',
          },
          timestamp: _formatRelative(lastMessageAt, now),
          icon: status == 'blocked'
              ? Icons.block_rounded
              : Icons.lock_outline_rounded,
          message: '',
          status: status,
          sentAt: lastMessageAt,
          expiresAt: null,
          sortMs:
              (lastMessageAt ?? DateTime(1970)).millisecondsSinceEpoch,
        ));
      }
    }

    activeNow.sort((a, b) => a.sortKey.compareTo(b.sortKey));
    matches.sort((a, b) => b.sortMs.compareTo(a.sortMs));
    chats.sort((a, b) => b.sortMs.compareTo(a.sortMs));
    history.sort((a, b) => b.sortMs.compareTo(a.sortMs));

    return _MessagesPartition(
      activeNow: activeNow,
      matches: matches,
      chats: chats,
      history: history,
    );
  }

  // ── Tap handlers ───────────────────────────────────────────────────────────

  /// Active Now tap.
  ///
  ///   icebreakerReceived → IcebreakerReceivedScreen (accept / decline UI).
  ///                        Sender's photo isn't denormalised onto the
  ///                        icebreaker doc, so fetch it on demand from
  ///                        users/{senderId} before navigating.
  ///   icebreakerSent     → ChatThreadScreen in 'locked' mode (read-only
  ///                        message bubble + "Waiting for X to respond"
  ///                        footer).  Reuses the existing static body path
  ///                        in chat_thread_screen.dart.
  Future<void> _onActiveNowTap(_ActiveNowItem item) async {
    if (item.kind == _ActiveKind.icebreakerReceived) {
      // Sender's photo + age aren't denormalised onto the icebreaker doc, so
      // fetch them on tap.  Read priority is `profiles/{uid}` (canonical
      // public surface) → `users/{uid}` (legacy mirror, still dual-written
      // for transition).  My own profile is pulled in the same batch.
      // All four values default to safe placeholders if every read fails.
      var senderPhotoUrl = '';
      var senderAge = 0;
      var myFirstName = '';
      var myPhotoUrl = '';
      try {
        final db = FirebaseFirestore.instance;
        final results = await Future.wait([
          db.collection('profiles').doc(item.otherUserId).get(),
          db.collection('profiles').doc(_myUid).get(),
          db.collection('users').doc(item.otherUserId).get(),
          db.collection('users').doc(_myUid).get(),
        ]);
        final senderProfile = results[0].exists ? results[0].data()! : const {};
        final myProfile = results[1].exists ? results[1].data()! : const {};
        final senderUser = results[2].data() ?? const {};
        final myUser = results[3].data() ?? const {};

        senderPhotoUrl = _coalescePhotoUrl(senderProfile, senderUser);
        senderAge = (senderProfile['age'] as num?)?.toInt() ??
            (senderUser['age'] as num?)?.toInt() ??
            0;
        myFirstName = (myProfile['firstName'] as String?) ??
            (myUser['firstName'] as String?) ??
            '';
        myPhotoUrl = _coalescePhotoUrl(myProfile, myUser);
      } catch (e) {
        debugPrint('[Messages] sender lookup failed (non-fatal): $e');
      }
      if (!mounted) return;
      final secondsRemaining = item.expiresAt == null
          ? 0
          : item.expiresAt!
              .difference(DateTime.now())
              .inSeconds
              .clamp(0, 1 << 30);
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => IcebreakerReceivedScreen(
          icebreakerId: item.icebreakerId,
          senderFirstName: item.otherFirstName,
          senderAge: senderAge,
          senderPhotoUrl: senderPhotoUrl,
          myFirstName: myFirstName,
          myPhotoUrl: myPhotoUrl,
          message: item.message,
          secondsRemaining: secondsRemaining,
        ),
      ));
      return;
    }

    // Outgoing pending icebreaker — locked chat thread.
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ChatThreadScreen(
        icebreakerId: item.icebreakerId,
        otherFirstName: item.otherFirstName,
        otherPhotoUrl: item.otherPhotoUrl,
        message: item.message,
        status: 'locked',
        sentAt: item.sentAt,
        expiresAt: item.expiresAt,
      ),
    ));
  }

  /// Match-tile tap → unlocked chat thread.  Identical wire-up to chat
  /// tap; the only thing differentiating a Match from a Chat is whether
  /// anyone has sent a message yet, and the thread screen handles both
  /// cases via its own `_verifyConversationAccess()` flow.
  void _onMatchTap(_MatchItem item) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ChatThreadScreen(
        icebreakerId: '',
        otherFirstName: item.otherFirstName,
        otherPhotoUrl: item.otherPhotoUrl,
        message: '',
        status: 'unlocked',
        conversationId: item.conversationId,
      ),
    ));
  }

  /// Active conversation tap → unlocked chat thread.
  ///
  /// ChatThreadScreen self-verifies via _verifyConversationAccess() — the
  /// conversation must exist, contain myUid in participants, and be
  /// status='active'.  Passing the args here does NOT bypass that check; if
  /// status flips to 'blocked' or 'ended' between the snapshot and the tap,
  /// the screen renders "Chat unavailable" and hides the composer.
  void _onChatTap(_ChatItem item) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ChatThreadScreen(
        icebreakerId: '',
        otherFirstName: item.otherFirstName,
        otherPhotoUrl: item.otherPhotoUrl,
        message: '',
        status: 'unlocked',
        conversationId: item.conversationId,
      ),
    ));
  }

  /// History tap.
  ///   conversation → ChatThreadScreen with conversationId.  The thread does
  ///                  its own Firestore lookup; for ended/blocked/expired
  ///                  conversations where the user is still a participant,
  ///                  it renders the live message stream read-only with a
  ///                  status footer in place of the composer.  The widget
  ///                  status arg is unused on this path — access is decided
  ///                  by the thread's own _verifyConversationAccess().
  ///   icebreaker   → ChatThreadScreen in 'expired' static mode, showing
  ///                  the original message bubble and the expiry pill.
  void _onHistoryTap(_HistoryItem item) {
    if (item.conversationId != null) {
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ChatThreadScreen(
          icebreakerId: '',
          otherFirstName: item.otherFirstName,
          otherPhotoUrl: item.otherPhotoUrl,
          message: '',
          status: 'unlocked',
          conversationId: item.conversationId,
        ),
      ));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ChatThreadScreen(
        icebreakerId: item.icebreakerId ?? '',
        otherFirstName: item.otherFirstName,
        otherPhotoUrl: item.otherPhotoUrl,
        message: item.message,
        status: item.status,
        sentAt: item.sentAt,
        expiresAt: item.expiresAt,
      ),
    ));
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Maps an icebreaker's `(status, meetupOutcome, expiry)` triple to the
  /// History card it should produce — or null when the row should NOT
  /// surface in History (e.g. still sent and unexpired; the Active Now path
  /// handles those).
  ///
  /// The full set of terminal stages an icebreaker can reach:
  ///
  ///   sent → (TTL) → expired                  "Icebreaker expired"
  ///   sent → declined                         "{They|You} declined"
  ///   sent → accepted → matched               (skipped — conversation row)
  ///   sent → accepted → no_match              "No match"
  ///   sent → accepted → expired_finding       "Missed each other"
  ///   sent → accepted → cancelled_finding     "Cancelled before meeting"
  ///   sent → accepted → cancelled_talking     "Cancelled mid-conversation"
  ///   sent → accepted → ended                 (skipped — conversation row,
  ///                                            ended is the post-match
  ///                                            continued-private exit)
  ///   sent → accepted → (no outcome yet)      "Connecting…"
  ///
  /// `previewIncoming` / `previewOutgoing` differ where pronouns matter
  /// ("You declined" vs "They declined").  `timestampSource` chooses the
  /// best wall-clock anchor for each terminal: meetupConcludedAt wins for
  /// post-accept terminals, expiresAt for TTL expiry, createdAt as a
  /// last-resort fallback.
  static _IcebreakerTerminal? _terminalForIcebreaker({
    required String status,
    required String? meetupOutcome,
    required DateTime? expiresAt,
    required DateTime now,
  }) {
    final timeExpired =
        status == 'sent' && expiresAt != null && !expiresAt.isAfter(now);
    if (status == 'expired' || timeExpired) {
      return const _IcebreakerTerminal(
        statusCode: 'expired',
        previewIncoming: 'Icebreaker expired',
        previewOutgoing: 'Icebreaker expired',
        icon: Icons.timer_off_outlined,
        anchor: _TerminalAnchor.expiry,
      );
    }
    if (status == 'declined') {
      return const _IcebreakerTerminal(
        statusCode: 'declined',
        previewIncoming: 'You declined',
        previewOutgoing: 'They declined',
        icon: Icons.close_rounded,
        anchor: _TerminalAnchor.created,
      );
    }
    if (status == 'accepted') {
      switch (meetupOutcome) {
        case 'matched':
        case 'ended':
          return const _IcebreakerTerminal.skip();
        case 'no_match':
          return const _IcebreakerTerminal(
            statusCode: 'no_match',
            previewIncoming: 'No match',
            previewOutgoing: 'No match',
            icon: Icons.heart_broken_outlined,
            anchor: _TerminalAnchor.concluded,
          );
        case 'expired_finding':
          return const _IcebreakerTerminal(
            statusCode: 'expired_finding',
            previewIncoming: 'Missed each other',
            previewOutgoing: 'Missed each other',
            icon: Icons.location_off_outlined,
            anchor: _TerminalAnchor.concluded,
          );
        case 'cancelled_finding':
          return const _IcebreakerTerminal(
            statusCode: 'cancelled_finding',
            previewIncoming: 'Cancelled before meeting',
            previewOutgoing: 'Cancelled before meeting',
            icon: Icons.cancel_outlined,
            anchor: _TerminalAnchor.concluded,
          );
        case 'cancelled_talking':
          return const _IcebreakerTerminal(
            statusCode: 'cancelled_talking',
            previewIncoming: 'Cancelled mid-conversation',
            previewOutgoing: 'Cancelled mid-conversation',
            icon: Icons.cancel_outlined,
            anchor: _TerminalAnchor.concluded,
          );
        default:
          // Accepted but no outcome on the doc yet — meetup is in flight,
          // OR the icebreaker pre-dates the onMeetupTerminal backref deploy
          // and the meetup doc isn't joined here.  Render a neutral "in
          // progress" row so the user at least sees that the icebreaker
          // was accepted.
          return const _IcebreakerTerminal(
            statusCode: 'accepted',
            previewIncoming: 'Connecting…',
            previewOutgoing: 'Connecting…',
            icon: Icons.hourglass_bottom_rounded,
            anchor: _TerminalAnchor.created,
          );
      }
    }
    return null;
  }

  /// Compact relative-time formatter for chat-list rows.  Avoids pulling in
  /// `package:intl` for what is effectively six branches.
  static String _formatRelative(DateTime? dt, DateTime now) {
    if (dt == null) return '';
    final diff = now.difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${diff.inDays ~/ 7}w ago';
  }

  /// Resolves the best display photo URL across the dual-write surfaces.
  ///
  /// `profiles/{uid}` writes `primaryPhotoUrl` (and `photoUrls[0]` as the
  /// underlying source); `users/{uid}` still mirrors the older `photoUrl`
  /// field for legacy readers.  We try them in canonical-first order and
  /// return the first non-empty value, so an account whose Edit Profile
  /// save landed on profiles but never on users still resolves to a real
  /// photo here, and an account that has only the legacy users-doc photo
  /// also resolves correctly during the transition.
  static String _coalescePhotoUrl(
    Map<dynamic, dynamic> profile,
    Map<dynamic, dynamic> user,
  ) {
    String pick(dynamic v) => (v is String && v.isNotEmpty) ? v : '';
    final fromProfilePrimary = pick(profile['primaryPhotoUrl']);
    if (fromProfilePrimary.isNotEmpty) return fromProfilePrimary;
    final profileUrls = profile['photoUrls'];
    if (profileUrls is List && profileUrls.isNotEmpty) {
      final first = pick(profileUrls.first);
      if (first.isNotEmpty) return first;
    }
    final fromUserSingle = pick(user['photoUrl']);
    if (fromUserSingle.isNotEmpty) return fromUserSingle;
    final userUrls = user['photoUrls'];
    if (userUrls is List && userUrls.isNotEmpty) {
      return pick(userUrls.first);
    }
    return '';
  }
}

// ─── View models ─────────────────────────────────────────────────────────────

class _MessagesPartition {
  const _MessagesPartition({
    required this.activeNow,
    required this.matches,
    required this.chats,
    required this.history,
  });
  final List<_ActiveNowItem> activeNow;
  final List<_MatchItem> matches;
  final List<_ChatItem> chats;
  final List<_HistoryItem> history;

  bool get isEmpty =>
      activeNow.isEmpty && matches.isEmpty && chats.isEmpty && history.isEmpty;
}

enum _ActiveKind { icebreakerReceived, icebreakerSent }

class _ActiveNowItem {
  const _ActiveNowItem({
    required this.icebreakerId,
    required this.kind,
    required this.otherFirstName,
    required this.otherPhotoUrl,
    required this.otherUserId,
    required this.statusLabel,
    required this.secondsRemaining,
    required this.expiresAt,
    required this.message,
    required this.sentAt,
    required this.sortKey,
  });
  final String icebreakerId;
  final _ActiveKind kind;
  final String otherFirstName;
  final String otherPhotoUrl;
  final String otherUserId;
  final String statusLabel;
  final int secondsRemaining;
  final DateTime? expiresAt;
  final String message;
  final DateTime? sentAt;
  final int sortKey;
}

class _ChatItem {
  const _ChatItem({
    required this.conversationId,
    required this.otherFirstName,
    required this.otherPhotoUrl,
    required this.previewText,
    required this.timestamp,
    required this.hasUnread,
    required this.sortMs,
  });
  final String conversationId;
  final String otherFirstName;
  final String otherPhotoUrl;
  final String previewText;
  final String timestamp;
  final bool hasUnread;
  final int sortMs;
}

class _MatchItem {
  const _MatchItem({
    required this.conversationId,
    required this.otherFirstName,
    required this.otherPhotoUrl,
    required this.sortMs,
  });
  final String conversationId;
  final String otherFirstName;
  final String otherPhotoUrl;
  final int sortMs;
}

class _HistoryItem {
  const _HistoryItem({
    required this.icebreakerId,
    required this.conversationId,
    required this.isOutgoing,
    required this.otherFirstName,
    required this.otherPhotoUrl,
    required this.previewText,
    required this.timestamp,
    required this.icon,
    required this.message,
    required this.status,
    required this.sentAt,
    required this.expiresAt,
    required this.sortMs,
  });
  final String? icebreakerId;
  final String? conversationId;
  final bool isOutgoing;
  final String otherFirstName;
  final String otherPhotoUrl;
  final String previewText;
  final String timestamp;
  final IconData icon;
  final String message;
  final String status;
  final DateTime? sentAt;
  final DateTime? expiresAt;
  final int sortMs;
}

/// Which wall-clock value to anchor a History row to — picked per-terminal
/// because each stage has a different "this is when it concluded" moment.
enum _TerminalAnchor {
  /// status='expired' or sent-past-TTL — anchor on expiresAt (when the TTL
  /// crossed) so the timestamp matches the stage label.
  expiry,

  /// status='declined' or status='accepted' without an outcome yet — anchor
  /// on the icebreaker createdAt because we don't have a more precise
  /// transition time on the doc.
  created,

  /// Post-accept terminals — anchor on meetupConcludedAt (written by
  /// onMeetupTerminal) which captures the moment the meetup actually
  /// resolved.
  concluded,
}

class _IcebreakerTerminal {
  const _IcebreakerTerminal({
    required this.statusCode,
    required this.previewIncoming,
    required this.previewOutgoing,
    required this.icon,
    required this.anchor,
  }) : skip = false;

  /// Skipped terminals — the row should NOT render in History because
  /// another surface owns it (the conversation row for matched / ended).
  const _IcebreakerTerminal.skip()
      : statusCode = '',
        previewIncoming = '',
        previewOutgoing = '',
        icon = Icons.help_outline,
        anchor = _TerminalAnchor.created,
        skip = true;

  final String statusCode;
  final String previewIncoming;
  final String previewOutgoing;
  final IconData icon;
  final _TerminalAnchor anchor;
  final bool skip;

  DateTime? timestampSource({
    required DateTime? expiresAt,
    required DateTime? createdAt,
    required DateTime? concludedAt,
  }) {
    switch (anchor) {
      case _TerminalAnchor.expiry:
        return expiresAt ?? createdAt;
      case _TerminalAnchor.created:
        return createdAt;
      case _TerminalAnchor.concluded:
        return concludedAt ?? createdAt;
    }
  }
}

/// Horizontal avatar tile for the Matches strip.  Photo in a brand-pink
/// gradient ring + first name underneath — the standard "fresh tray"
/// pattern from dating-app conventions, scaled to the Icebreaker palette.
class _MatchAvatarTile extends StatelessWidget {
  const _MatchAvatarTile({
    required this.match,
    required this.onTap,
  });

  final _MatchItem match;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const radius = 36.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 84,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.brandPink,
                      AppColors.brandPink.withValues(alpha: 0.6),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.brandPink.withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: CircleAvatar(
                  radius: radius,
                  backgroundColor: AppColors.bgElevated,
                  backgroundImage: match.otherPhotoUrl.isNotEmpty
                      ? NetworkImage(match.otherPhotoUrl)
                      : null,
                  child: match.otherPhotoUrl.isEmpty
                      ? Text(
                          match.otherFirstName.isNotEmpty
                              ? match.otherFirstName[0].toUpperCase()
                              : '?',
                          style: AppTextStyles.h2.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                match.otherFirstName,
                style: AppTextStyles.bodyS,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
