import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/services/blocks_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../nearby/models/nearby_image.dart';
import '../../nearby/widgets/nearby_about_me_card.dart';
import '../../nearby/widgets/nearby_focus_card.dart';
import '../../reports/widgets/report_sheet.dart';

/// Chat thread screen — display modes:
///
///  Static (no [conversationId]):
///    'locked'            — outgoing icebreaker, awaiting recipient response.
///                          Original message bubble + lock explanation.
///    'expired'|'declined'— concluded icebreaker history, read-only view with
///                          outcome pill.
///
///  Conversation ([conversationId] supplied) — sub-mode is decided by a live
///  Firestore lookup of `conversations/{conversationId}.status`, NOT by the
///  passed [status] arg:
///    participant + status=='active'                    → live stream + composer
///    participant + status in {ended,expired,blocked}   → live stream, READ-ONLY
///                                                        (no composer; status
///                                                        footer instead)
///    not a participant / doc missing / unknown status  → "Chat unavailable"
///
///  The participant + 'active' gate is what unlocks the composer; non-active
///  conversations still allow message reads to participants (Firestore rules
///  permit read for any participant, but only allow create when status=='active').
///
/// Navigation:
///   AppBar avatar/name → profile preview sheet.
///   Back arrow         → Navigator.pop().
class ChatThreadScreen extends StatefulWidget {
  const ChatThreadScreen({
    super.key,
    required this.icebreakerId,
    required this.otherFirstName,
    required this.otherPhotoUrl,
    required this.message,
    required this.status,
    this.sentAt,
    this.expiresAt,
    this.conversationId,
  });

  final String icebreakerId;
  final String otherFirstName;
  final String otherPhotoUrl;

  /// The original icebreaker message body.
  final String message;

  /// 'locked' | 'expired' | 'declined' | 'unlocked'
  final String status;

  /// When the icebreaker was sent — used for the date label in locked/history.
  final DateTime? sentAt;

  /// Wall-clock expiry — forwarded to the locked footer countdown.
  final DateTime? expiresAt;

  /// Required when [status] == 'unlocked' — identifies the conversation doc.
  final String? conversationId;

  @override
  State<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

/// Resolved access state for a conversation-mode chat thread.
///
/// Decided by [_ChatThreadScreenState._verifyConversationAccess] from the
/// live conversation doc — NOT from the widget's [ChatThreadScreen.status]
/// arg, which the caller may set freely.
enum _ConvAccess {
  /// Participant + status=='active': live stream + composer.
  active,

  /// Participant + status in {ended, expired, blocked}: live stream is
  /// rendered read-only (composer hidden; status footer shown instead).
  /// Firestore rules already block message creation when status != 'active',
  /// so the read-only UI matches the rule layer.
  history,

  /// Doc missing, user not in participants, or unknown status — neutral
  /// "Chat unavailable" landing.
  denied,
}

class _ChatThreadScreenState extends State<ChatThreadScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _messageFocusNode = FocusNode();
  bool _isSending = false;
  bool _readSyncInFlight = false;
  String? _lastReadClearedMessageId;

  // Conversation access state when conversationId is present.
  // null = loading (Firestore fetch in flight); see [_ConvAccess] for the
  // resolved cases.
  //
  // Unlock state is intentionally NOT derived from widget.status alone.
  // The route can pass any string argument — only a successful Firestore
  // participant check should unlock the composer and message stream.
  _ConvAccess? _convAccess;

  /// Live conversation status string (mirrors [_convAccess] but preserves the
  /// underlying value — used to label the history footer with the specific
  /// reason: "ended" / "expired" / "closed").
  String? _convStatus;

  // Populated once _verifyConversationAccess() resolves — used by the block flow.
  String? _otherUserId;
  bool _isBlocking = false;

  // Live subscription on the conversation doc — detects status changes
  // (e.g. status='blocked' written by the Cloud Function when a block occurs)
  // and flips _convAccess reactively so the composer closes without requiring
  // a navigation event.  An active→history transition keeps the stream visible
  // but hides the composer.
  StreamSubscription<DocumentSnapshot>? _convStatusSub;

  bool get _isLocked => widget.status == 'locked';

  // Unlocked iff Firestore confirmed the user is a participant in an active
  // conversation.  A widget argument of 'unlocked' alone is NOT sufficient.
  // Drives the AppBar online dot, the "more" menu (block/report), and the
  // composer; read-only history mode evaluates this as false on purpose.
  bool get _isUnlocked =>
      widget.conversationId != null && _convAccess == _ConvAccess.active;

  @override
  void initState() {
    super.initState();
    if (widget.conversationId != null) {
      _verifyConversationAccess();
    } else if (widget.icebreakerId.isNotEmpty) {
      _resolveOtherUidFromIcebreaker();
    }
  }

  /// Fills [_otherUserId] from the icebreaker doc when the chat thread is
  /// opened without a conversationId (locked / expired / declined modes).
  /// Lets the avatar tap render the full profile sheet on these paths too,
  /// not just on unlocked conversations.
  Future<void> _resolveOtherUidFromIcebreaker() async {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('icebreakers')
          .doc(widget.icebreakerId)
          .get();
      if (!doc.exists || !mounted) return;
      final data = doc.data() ?? const <String, dynamic>{};
      final senderId = data['senderId'] as String?;
      final recipientId = data['recipientId'] as String?;
      final otherId = (senderId != null && senderId != myUid)
          ? senderId
          : (recipientId != null && recipientId != myUid)
              ? recipientId
              : null;
      if (otherId != null && otherId.isNotEmpty && mounted) {
        setState(() => _otherUserId = otherId);
      }
    } catch (e) {
      debugPrint('[ChatThread] icebreaker uid lookup failed (non-fatal): $e');
    }
  }

  /// Reads the conversation doc once to decide [_convAccess]:
  ///
  ///   not a participant / doc missing                   → denied
  ///   participant + status == 'active'                  → active
  ///   participant + status in {ended, expired, blocked} → history
  ///   participant + any other status string             → denied
  ///
  /// Firestore security rules enforce the same participant requirement at the
  /// network layer for both reads and writes — and additionally require
  /// `status == 'active'` for message creates.  So a malicious client that
  /// forces _convAccess to active still cannot send messages on a non-active
  /// conversation; the rule layer rejects the write.
  Future<void> _verifyConversationAccess() async {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) {
      if (mounted) setState(() => _convAccess = _ConvAccess.denied);
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('conversations')
          .doc(widget.conversationId)
          .get();
      if (!doc.exists) {
        if (mounted) setState(() => _convAccess = _ConvAccess.denied);
        return;
      }
      final data = doc.data()!;
      final participants = List<String>.from(
          (data['participants'] as List<dynamic>?) ?? []);
      final status = data['status'] as String? ?? '';
      final isParticipant = participants.contains(myUid);
      final otherId =
          participants.firstWhere((p) => p != myUid, orElse: () => '');
      final access = _resolveAccess(isParticipant, status);
      if (mounted) {
        setState(() {
          _convAccess = access;
          _convStatus = status;
          _otherUserId = otherId.isNotEmpty ? otherId : null;
        });
      }
      if (isParticipant) {
        _markConversationRead();
      }

      // After confirming participation, subscribe to live status changes.
      // This ensures that if the conversation is blocked / ended while this
      // screen is open (e.g. the other user blocks us via the Cloud Function),
      // the composer hides and the read-only history footer renders without
      // requiring a navigation event.
      if (isParticipant) {
        _convStatusSub = FirebaseFirestore.instance
            .collection('conversations')
            .doc(widget.conversationId)
            .snapshots()
            .listen((snap) {
          if (!mounted) return;
          final liveStatus = snap.data()?['status'] as String? ?? '';
          final liveAccess = _resolveAccess(true, liveStatus);
          if (_convAccess != liveAccess || _convStatus != liveStatus) {
            setState(() {
              _convAccess = liveAccess;
              _convStatus = liveStatus;
            });
          }
        });
      }
    } catch (e) {
      debugPrint('[ChatThread] conversation access check failed: $e');
      if (mounted) setState(() => _convAccess = _ConvAccess.denied);
    }
  }

  static _ConvAccess _resolveAccess(bool isParticipant, String status) {
    if (!isParticipant) return _ConvAccess.denied;
    if (status == 'active') return _ConvAccess.active;
    if (status == 'ended' || status == 'expired' || status == 'blocked') {
      return _ConvAccess.history;
    }
    return _ConvAccess.denied;
  }

  Future<void> _markConversationRead({String? newestMessageId}) async {
    final conversationId = widget.conversationId;
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (conversationId == null || myUid == null || myUid.isEmpty) return;
    if (newestMessageId != null && newestMessageId == _lastReadClearedMessageId) {
      return;
    }
    if (_readSyncInFlight) return;

    _readSyncInFlight = true;
    try {
      await FirebaseFirestore.instance
          .collection('conversations')
          .doc(conversationId)
          .update({
        'unreadCount_$myUid': 0,
        'lastReadAt_$myUid': FieldValue.serverTimestamp(),
      });
      if (newestMessageId != null) {
        _lastReadClearedMessageId = newestMessageId;
      }
    } catch (e) {
      debugPrint('[ChatThread] mark read failed: $e');
    } finally {
      _readSyncInFlight = false;
    }
  }

  @override
  void dispose() {
    _convStatusSub?.cancel();
    _messageController.dispose();
    _messageFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: _buildAppBar(context),
      body: Column(
        children: [
          Expanded(
            child: widget.conversationId != null
                ? _buildConversationBody()
                : _buildStaticBody(),
          ),
          _buildFooter(context),
        ],
      ),
    );
  }

  /// Routes the conversation body through [_convAccess].
  ///
  ///   null    → loading spinner (initial Firestore fetch in flight)
  ///   denied  → neutral "Chat unavailable" landing
  ///   active  → live message stream (composer rendered by _buildFooter)
  ///   history → live message stream rendered read-only (composer hidden;
  ///             status footer rendered by _buildFooter instead).  Read access
  ///             is permitted by Firestore rules for any participant; create
  ///             access is gated on status=='active' at the rule layer too,
  ///             so the read-only UI is consistent with what the server allows.
  Widget _buildConversationBody() {
    switch (_convAccess) {
      case null:
        return const Center(child: CircularProgressIndicator());
      case _ConvAccess.denied:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline_rounded,
                    color: AppColors.textMuted, size: 48),
                const SizedBox(height: 16),
                Text('Chat unavailable',
                    style: AppTextStyles.h3, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(
                  'This conversation is no longer accessible.',
                  style: AppTextStyles.bodyS,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      case _ConvAccess.active:
      case _ConvAccess.history:
        return _buildChatStream();
    }
  }

  // ── App bar ────────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: AppColors.bgBase,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(
          Icons.arrow_back_ios_new_rounded,
          color: Colors.white,
          size: 20,
        ),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: GestureDetector(
        onTap: () => _showProfileSheet(context),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _AvatarCircle(
              url: widget.otherPhotoUrl,
              initials:
                  widget.otherFirstName.isNotEmpty ? widget.otherFirstName[0] : '?',
              radius: 18,
            ),
            const SizedBox(width: 10),
            Text(widget.otherFirstName, style: AppTextStyles.h3),
            if (_isUnlocked) ...[
              const SizedBox(width: 8),
              // Online indicator
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.success,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
      centerTitle: false,
      // Only show block option when the user is in an active conversation.
      actions: _isUnlocked
          ? [
              IconButton(
                icon: const Icon(Icons.more_vert_rounded,
                    color: AppColors.textSecondary),
                onPressed: () => _showChatOptions(context),
              ),
            ]
          : null,
    );
  }

  // ── Static body (locked / history) ────────────────────────────────────────

  Widget _buildStaticBody() {
    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      children: [
        // Date label
        Center(
          child: Text(
            widget.sentAt != null
                ? _formatDate(widget.sentAt!)
                : 'Icebreaker sent',
            style: AppTextStyles.caption,
          ),
        ),
        const SizedBox(height: 20),

        // Original message bubble — outgoing style (right-aligned, brand gradient)
        Align(
          alignment: Alignment.centerRight,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 280),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: AppColors.brandGradient,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(4),
              ),
            ),
            child: Text(
              widget.message.isNotEmpty ? widget.message : '(no message)',
              style: AppTextStyles.body.copyWith(color: Colors.white),
            ),
          ),
        ),

        const SizedBox(height: 40),

        // Locked: lock icon + explanation
        if (_isLocked) _buildLockedExplanation(),

        // History: outcome pill
        if (!_isLocked) Center(child: _OutcomePill(status: widget.status)),
      ],
    );
  }

  Widget _buildLockedExplanation() {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: AppColors.bgElevated,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.divider, width: 1),
          ),
          child: const Icon(
            Icons.lock_outline_rounded,
            color: AppColors.textMuted,
            size: 28,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Chat unlocks after you meet',
          style: AppTextStyles.h3,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Find ${widget.otherFirstName} nearby and both tap\n"We Got This" to open the chat.',
          style: AppTextStyles.bodyS,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  // ── Unlocked: live message stream ──────────────────────────────────────────

  Widget _buildChatStream() {
    final convId = widget.conversationId;
    if (convId == null || convId.isEmpty) {
      return Center(
        child: Text('No conversation found.', style: AppTextStyles.bodyS),
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('conversations')
          .doc(convId)
          .collection('messages')
          .orderBy('createdAt', descending: false)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Text('Could not load messages.',
                style: AppTextStyles.bodyS),
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snap.data!.docs;
        final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';

        // Scroll to bottom after new messages land
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients &&
              _scrollController.position.maxScrollExtent > 0) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }

          if (docs.isNotEmpty) {
            final lastData = docs.last.data() as Map<String, dynamic>;
            final latestSenderId = lastData['senderId'] as String? ?? '';
            if (latestSenderId.isNotEmpty && latestSenderId != myUid) {
              _markConversationRead(newestMessageId: docs.last.id);
            }
          }
        });

        if (docs.isEmpty) {
          return Center(
            child: Text(
              'Say hello to ${widget.otherFirstName}!',
              style: AppTextStyles.bodyS,
            ),
          );
        }
        return ListView.builder(
          controller: _scrollController,
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final data = docs[i].data() as Map<String, dynamic>;
            final senderId = data['senderId'] as String? ?? '';
            final isMe = senderId == myUid;
            final text = data['text'] as String? ?? '';
            final createdAt =
                (data['createdAt'] as Timestamp?)?.toDate();

            // System messages render as a centre label
            if (data['type'] == 'system') {
              return _SystemLabel(text: text);
            }

            return _MessageBubble(
              text: text,
              isMe: isMe,
              createdAt: createdAt,
            );
          },
        );
      },
    );
  }

  // ── Footer ─────────────────────────────────────────────────────────────────

  Widget _buildFooter(BuildContext context) {
    // Conversation path: footer tracks the resolved access state.
    //   active  → composer
    //   history → status footer (no composer; messages already rendered above)
    //   denied / loading → no footer chrome
    if (widget.conversationId != null) {
      switch (_convAccess) {
        case _ConvAccess.active:
          return _buildComposer(context);
        case _ConvAccess.history:
          return _buildConvHistoryFooter();
        case _ConvAccess.denied:
        case null:
          return const SizedBox.shrink();
      }
    }
    // Static (icebreaker) path: footer follows the passed status arg.
    if (_isLocked) return _buildLockedFooter();
    return _buildHistoryFooter();
  }

  /// Footer for a conversation rendered in read-only history mode.  Mirrors
  /// the chrome of the locked / icebreaker-history footers but labels the
  /// state from the live conversation status.
  Widget _buildConvHistoryFooter() {
    final status = _convStatus ?? '';
    final (icon, text) = switch (status) {
      'blocked' => (Icons.block_rounded, 'This conversation is closed'),
      'expired' => (Icons.timer_off_outlined, 'This conversation expired'),
      _ => (Icons.lock_outline_rounded, 'This conversation has ended'),
    };
    return Container(
      color: AppColors.bgSurface,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 14, color: AppColors.textMuted),
          const SizedBox(width: 6),
          Text(text, style: AppTextStyles.caption),
        ],
      ),
    );
  }

  Widget _buildComposer(BuildContext context) {
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      color: AppColors.bgSurface,
      padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPad + 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Text field
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.bgInput,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.divider),
              ),
              child: TextField(
                controller: _messageController,
                focusNode: _messageFocusNode,
                style: AppTextStyles.body
                    .copyWith(color: AppColors.textPrimary),
                maxLines: 5,
                minLines: 1,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _isSending ? null : _sendMessage(),
                decoration: InputDecoration(
                  hintText: 'Say something...',
                  hintStyle: AppTextStyles.body
                      .copyWith(color: AppColors.textMuted),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 12),
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Send button
          GestureDetector(
            onTap: _isSending ? null : _sendMessage,
            child: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                gradient: AppColors.brandGradient,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: _isSending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded,
                      color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLockedFooter() {
    return Container(
      color: AppColors.bgSurface,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.schedule_rounded,
              size: 14, color: AppColors.brandCyan),
          const SizedBox(width: 6),
          Text(
            'Waiting for ${widget.otherFirstName} to respond',
            style:
                AppTextStyles.caption.copyWith(color: AppColors.brandCyan),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryFooter() {
    return Container(
      color: AppColors.bgSurface,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            widget.status == 'declined'
                ? Icons.close_rounded
                : Icons.timer_off_outlined,
            size: 14,
            color: AppColors.textMuted,
          ),
          const SizedBox(width: 6),
          Text(
            widget.status == 'declined'
                ? 'This Icebreaker was declined'
                : 'This Icebreaker expired',
            style: AppTextStyles.caption,
          ),
        ],
      ),
    );
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || widget.conversationId == null) return;
    // Defense in depth — the composer is only built when active, but a stale
    // tap (status flipped to ended/blocked between focus and send) should
    // bail out before hitting Firestore. Rules also reject creates when
    // status != 'active', so this is belt-and-suspenders.
    if (_convAccess != _ConvAccess.active) return;

    setState(() => _isSending = true);
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final convRef = FirebaseFirestore.instance
        .collection('conversations')
        .doc(widget.conversationId);

    try {
      await convRef.collection('messages').add({
        'senderId': myUid,
        'text': text,
        'type': 'text',
        'createdAt': FieldValue.serverTimestamp(),
      });
      final update = <String, Object?>{
        'lastMessage': text,
        'lastSenderId': myUid,
        'lastMessageAt': FieldValue.serverTimestamp(),
      };
      final otherUid = _otherUserId;
      if (otherUid != null && otherUid.isNotEmpty) {
        update['unreadCount_$otherUid'] = FieldValue.increment(1);
        update['unreadCount_$myUid'] = 0;
        update['lastReadAt_$myUid'] = FieldValue.serverTimestamp();
      }
      await convRef.update(update);
      _messageController.clear();
      _messageFocusNode.unfocus();
    } catch (e) {
      debugPrint('[Chat] send failed: $e');
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _showChatOptions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // ── Report ────────────────────────────────────────────────────
              ListTile(
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.flag_rounded,
                      color: AppColors.warning, size: 18),
                ),
                title: Text(
                  'Report ${widget.otherFirstName}',
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  'Submit a confidential report to our safety team',
                  style:
                      AppTextStyles.caption.copyWith(color: AppColors.textMuted),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  if (!mounted) return;
                  final otherId = _otherUserId;
                  if (otherId == null) return;
                  showReportSheet(
                    context,
                    reportedUserId: otherId,
                    firstName: widget.otherFirstName,
                    conversationId: widget.conversationId,
                    source: 'chat',
                  );
                },
              ),

              // Subtle divider between Report and Block
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Divider(
                    height: 1, color: AppColors.divider.withValues(alpha: 0.6)),
              ),

              // ── Block ─────────────────────────────────────────────────────
              ListTile(
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.block_rounded,
                      color: AppColors.danger, size: 18),
                ),
                title: Text(
                  'Block ${widget.otherFirstName}',
                  style: AppTextStyles.body.copyWith(
                    color: AppColors.danger,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  'They won\'t be able to message you or find you nearby',
                  style:
                      AppTextStyles.caption.copyWith(color: AppColors.textMuted),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                onTap: () async {
                  Navigator.of(sheetCtx).pop();
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (dialogCtx) => AlertDialog(
                      backgroundColor: AppColors.bgElevated,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18)),
                      title: Text(
                        'Block ${widget.otherFirstName}?',
                        style: AppTextStyles.h3
                            .copyWith(color: AppColors.textPrimary),
                      ),
                      content: Text(
                        '${widget.otherFirstName} won\'t be able to message '
                        'you or find you in Nearby. This conversation will be closed.',
                        style: AppTextStyles.bodyS,
                      ),
                      actions: [
                        TextButton(
                          onPressed: () =>
                              Navigator.of(dialogCtx).pop(false),
                          child: Text(
                            'Cancel',
                            style: AppTextStyles.body
                                .copyWith(color: AppColors.textSecondary),
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              Navigator.of(dialogCtx).pop(true),
                          child: Text(
                            'Block',
                            style: AppTextStyles.body
                                .copyWith(color: AppColors.danger),
                          ),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true && mounted) {
                    await _blockFromChat();
                  }
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  /// Writes a block record then pops this screen.
  ///
  /// The Cloud Function `onUserBlocked` will set the conversation status to
  /// 'blocked', preventing new messages at both the rules and UI layers.
  /// We navigate away immediately (optimistic) so the user doesn't see a
  /// broken composer while the function runs.
  Future<void> _blockFromChat() async {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    final otherId = _otherUserId;
    if (myUid == null || otherId == null || _isBlocking) return;

    setState(() => _isBlocking = true);
    try {
      // BlocksRepository fans out to canonical blocks/{...} + forward index +
      // reverse index in one batch.  source='chat' + the conversationId give
      // moderation enough provenance to find the offending thread later.
      await BlocksRepository().block(
        blockerId: myUid,
        blockedId: otherId,
        source: 'chat',
        conversationId: widget.conversationId,
        blockedDisplayName: widget.otherFirstName,
        blockedPhotoUrl: widget.otherPhotoUrl,
      );
      debugPrint('[ChatBlock] blocked $otherId (${widget.otherFirstName})');
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      debugPrint('[ChatBlock] write failed: $e');
      if (mounted) {
        setState(() => _isBlocking = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Couldn't block ${widget.otherFirstName}. Check your connection and try again.",
              style: AppTextStyles.bodyS.copyWith(color: Colors.white),
            ),
            backgroundColor: AppColors.bgElevated,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Retry',
              textColor: AppColors.brandCyan,
              onPressed: _blockFromChat,
            ),
          ),
        );
      }
    }
  }

  void _showProfileSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _FullProfileSheet(
        otherUid: _otherUserId,
        fallbackFirstName: widget.otherFirstName,
        fallbackPhotoUrl: widget.otherPhotoUrl,
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static String _formatDate(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    return '${diff.inDays} days ago';
  }
}

// ── Message bubble ────────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.text,
    required this.isMe,
    this.createdAt,
  });

  final String text;
  final bool isMe;
  final DateTime? createdAt;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) const SizedBox(width: 4),
          Flexible(
            child: Column(
              crossAxisAlignment: isMe
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Container(
                  constraints: const BoxConstraints(maxWidth: 280),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: isMe ? AppColors.brandGradient : null,
                    color: isMe ? null : AppColors.bgElevated,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(isMe ? 18 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 18),
                    ),
                  ),
                  child: Text(
                    text,
                    style: AppTextStyles.body.copyWith(
                      color: isMe
                          ? Colors.white
                          : AppColors.textPrimary,
                    ),
                  ),
                ),
                if (createdAt != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    _formatTime(createdAt!),
                    style: AppTextStyles.caption,
                  ),
                ],
              ],
            ),
          ),
          if (isMe) const SizedBox(width: 4),
        ],
      ),
    );
  }

  static String _formatTime(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour < 12 ? 'am' : 'pm';
    return '$h:$m $ampm';
  }
}

// ── System label ──────────────────────────────────────────────────────────────

class _SystemLabel extends StatelessWidget {
  const _SystemLabel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Text(text, style: AppTextStyles.caption),
      ),
    );
  }
}

// ── Outcome pill ──────────────────────────────────────────────────────────────

class _OutcomePill extends StatelessWidget {
  const _OutcomePill({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final isDeclined = status == 'declined';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: (isDeclined ? AppColors.danger : AppColors.textMuted)
            .withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: (isDeclined ? AppColors.danger : AppColors.textMuted)
              .withValues(alpha: 0.30),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isDeclined ? Icons.close_rounded : Icons.timer_off_outlined,
            size: 13,
            color: isDeclined ? AppColors.danger : AppColors.textMuted,
          ),
          const SizedBox(width: 5),
          Text(
            isDeclined ? 'Declined' : 'Expired',
            style: AppTextStyles.caption.copyWith(
              color: isDeclined ? AppColors.danger : AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Avatar circle ─────────────────────────────────────────────────────────────

class _AvatarCircle extends StatelessWidget {
  const _AvatarCircle({
    required this.url,
    required this.initials,
    this.radius = 24,
  });

  final String url;
  final String initials;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.bgElevated,
      backgroundImage: url.isNotEmpty ? NetworkImage(url) : null,
      child: url.isEmpty
          ? Text(
              initials.toUpperCase(),
              style: AppTextStyles.bodyS.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            )
          : null,
    );
  }
}

// ── Full-profile sheet ────────────────────────────────────────────────────────
//
// Replaces the old single-photo "Profile preview — coming soon" placeholder.
// Renders the same NearbyFocusCard + NearbyAboutMeCard pair as the Nearby
// discovery carousel, but with [hideActions: true] so the Send Icebreaker
// CTA and more-options menu are suppressed (you're already in this person's
// chat thread — sending another icebreaker or surfacing block from here
// would be redundant).
//
// When [otherUid] is null (icebreaker doc lookup failed, or this surface
// was opened before the lookup resolved), falls back to a minimal
// avatar + name preview so the avatar tap never feels broken.

class _FullProfileSheet extends StatelessWidget {
  const _FullProfileSheet({
    required this.otherUid,
    required this.fallbackFirstName,
    required this.fallbackPhotoUrl,
  });

  final String? otherUid;
  final String fallbackFirstName;
  final String fallbackPhotoUrl;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.bgBase,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Drag handle
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: (otherUid == null || otherUid!.isEmpty)
                    ? _MinimalProfileBody(
                        firstName: fallbackFirstName,
                        photoUrl: fallbackPhotoUrl,
                        scrollController: scrollController,
                      )
                    : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance
                            .collection('profiles')
                            .doc(otherUid)
                            .snapshots(),
                        builder: (context, snap) {
                          if (snap.connectionState ==
                                  ConnectionState.waiting &&
                              !snap.hasData) {
                            return const Center(
                              child: CircularProgressIndicator(
                                color: AppColors.brandPink,
                                strokeWidth: 2.5,
                              ),
                            );
                          }
                          final data = snap.data?.data();
                          if (data == null) {
                            return _MinimalProfileBody(
                              firstName: fallbackFirstName,
                              photoUrl: fallbackPhotoUrl,
                              scrollController: scrollController,
                            );
                          }
                          return _FullProfileBody(
                            uid: otherUid!,
                            profile: data,
                            fallbackFirstName: fallbackFirstName,
                            fallbackPhotoUrl: fallbackPhotoUrl,
                            scrollController: scrollController,
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Renders the Nearby-style card + about-me block stacked vertically inside
/// the sheet, sourced from the live `profiles/{otherUid}` doc.
class _FullProfileBody extends StatelessWidget {
  const _FullProfileBody({
    required this.uid,
    required this.profile,
    required this.fallbackFirstName,
    required this.fallbackPhotoUrl,
    required this.scrollController,
  });

  final String uid;
  final Map<String, dynamic> profile;
  final String fallbackFirstName;
  final String fallbackPhotoUrl;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final firstName =
        (profile['firstName'] as String?)?.trim().isNotEmpty == true
            ? profile['firstName'] as String
            : fallbackFirstName;
    final age = (profile['age'] as num?)?.toInt() ?? 0;
    final bio = profile['bio'] as String?;
    final hometownDisplay = profile['hometownDisplay'] as String?;
    final occupation = profile['occupation'] as String?;
    final height = profile['height'] as String?;
    final lookingFor = profile['lookingFor'] as String?;
    final interests = (profile['interests'] as List<dynamic>?)
            ?.whereType<String>()
            .toList() ??
        const <String>[];
    final hobbies = (profile['hobbies'] as List<dynamic>?)
            ?.whereType<String>()
            .toList() ??
        const <String>[];
    final photoUrls = (profile['photoUrls'] as List<dynamic>?)
            ?.whereType<String>()
            .toList() ??
        const <String>[];
    final primaryPhoto = profile['primaryPhotoUrl'] as String?;
    final liveSelfieUrl = profile['liveSelfieUrl'] as String?;
    final isGold = (profile['isGold'] as bool?) ?? false;

    // Build image rail: live selfie first (when present), then ordered
    // gallery, then the primary-photo fallback, then the fallback URL the
    // chat thread was opened with.  Dedupes by URL so a primary photo
    // already in the gallery doesn't render twice.
    final images = <NearbyImage>[];
    final seen = <String>{};
    void add(String? url, NearbyImageKind kind) {
      if (url == null) return;
      final v = url.trim();
      if (v.isEmpty) return;
      if (seen.add(v)) images.add(NearbyImage(url: v, kind: kind));
    }
    add(liveSelfieUrl, NearbyImageKind.liveSelfie);
    for (final u in photoUrls) {
      add(u, NearbyImageKind.profilePhoto);
    }
    add(primaryPhoto, NearbyImageKind.profilePhoto);
    add(fallbackPhotoUrl, NearbyImageKind.profilePhoto);

    return SingleChildScrollView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 32),
      child: Column(
        children: [
          // Hero card — matches the Nearby focus card visually.  Aspect
          // ratio mirrors the discovery surface so a user pulled in from
          // Messages feels like they're seeing the same canonical card.
          AspectRatio(
            aspectRatio: 3 / 4,
            child: NearbyFocusCard(
              recipientId: uid,
              firstName: firstName,
              age: age,
              images: images,
              isGold: isGold,
              isActive: true,
              hideActions: true,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: NearbyAboutMeCard(
              age: age,
              bio: bio,
              hometown: hometownDisplay,
              occupation: occupation,
              height: height,
              lookingFor: lookingFor,
              interests: interests,
              hobbies: hobbies,
            ),
          ),
        ],
      ),
    );
  }
}

/// Minimal fallback rendered when [otherUid] is null (icebreaker uid lookup
/// failed) or the `profiles/{uid}` doc is missing.  Shows the same data the
/// chat thread already has on hand so the user gets *something* useful.
class _MinimalProfileBody extends StatelessWidget {
  const _MinimalProfileBody({
    required this.firstName,
    required this.photoUrl,
    required this.scrollController,
  });

  final String firstName;
  final String photoUrl;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(
        children: [
          _AvatarCircle(
            url: photoUrl,
            initials: firstName.isNotEmpty ? firstName[0] : '?',
            radius: 56,
          ),
          const SizedBox(height: 18),
          Text(firstName, style: AppTextStyles.h2),
          const SizedBox(height: 8),
          Text(
            "We couldn't load this profile right now.",
            style: AppTextStyles.bodyS.copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
