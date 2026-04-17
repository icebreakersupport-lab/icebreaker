import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../reports/widgets/report_sheet.dart';

/// Chat thread screen — three display modes determined by [status]:
///
///  'locked'            — outgoing icebreaker, awaiting recipient response.
///                        Shows the original message bubble + lock explanation.
///  'expired'|'declined'— concluded history, read-only view with outcome pill.
///  'unlocked'          — post-"We Got This" conversation; live Firestore
///                        message stream + composer.
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

class _ChatThreadScreenState extends State<ChatThreadScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  bool _isSending = false;

  // Conversation verification result when conversationId is present.
  // null  = loading (Firestore fetch in flight)
  // true  = verified: user is a participant and conversation is active
  // false = denied:  doc missing, user not in participants, or status != 'active'
  //
  // Unlock state is intentionally NOT derived from widget.status alone.
  // The route can pass any string argument — only a successful Firestore
  // participant check should unlock the composer and message stream.
  bool? _convVerified;

  // Populated once _verifyConversationAccess() resolves — used by the block flow.
  String? _otherUserId;
  bool _isBlocking = false;

  // Live subscription on the conversation doc — detects status changes
  // (e.g. status='blocked' written by the Cloud Function when a block occurs)
  // and flips _convVerified reactively so the composer closes without requiring
  // a navigation event.
  StreamSubscription<DocumentSnapshot>? _convStatusSub;

  bool get _isLocked => widget.status == 'locked';

  // Unlocked iff Firestore confirmed the user is a participant in an active
  // conversation.  A widget argument of 'unlocked' alone is NOT sufficient.
  bool get _isUnlocked =>
      widget.conversationId != null && _convVerified == true;

  @override
  void initState() {
    super.initState();
    if (widget.conversationId != null) {
      _verifyConversationAccess();
    }
  }

  /// Reads the conversation doc once to confirm:
  ///   1. The doc exists.
  ///   2. The authenticated user is in [participants].
  ///   3. [status] == 'active'.
  ///
  /// This is the server-driven gate for unlocking the chat UI.
  /// Firestore security rules enforce the same check at the network layer,
  /// so a malicious client that forges `_convVerified = true` still cannot
  /// read or write messages without passing the rule.
  Future<void> _verifyConversationAccess() async {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) {
      if (mounted) setState(() => _convVerified = false);
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('conversations')
          .doc(widget.conversationId)
          .get();
      if (!doc.exists) {
        if (mounted) setState(() => _convVerified = false);
        return;
      }
      final data = doc.data()!;
      final participants = List<String>.from(
          (data['participants'] as List<dynamic>?) ?? []);
      final status = data['status'] as String? ?? '';
      final isParticipant = participants.contains(myUid);
      final isActive = status == 'active';
      final otherId =
          participants.firstWhere((p) => p != myUid, orElse: () => '');
      if (mounted) {
        setState(() {
          _convVerified = isParticipant && isActive;
          _otherUserId = otherId.isNotEmpty ? otherId : null;
        });
      }

      // After confirming participation, subscribe to live status changes.
      // This ensures that if the conversation is blocked while this screen
      // is open (e.g. the other user blocks us via the Cloud Function), the
      // composer and stream gate close immediately without requiring a reload.
      if (isParticipant) {
        _convStatusSub = FirebaseFirestore.instance
            .collection('conversations')
            .doc(widget.conversationId)
            .snapshots()
            .listen((snap) {
          if (!mounted) return;
          final liveStatus = snap.data()?['status'] as String? ?? '';
          final isStillActive = liveStatus == 'active';
          if (_convVerified != isStillActive) {
            setState(() => _convVerified = isStillActive);
          }
        });
      }
    } catch (e) {
      debugPrint('[ChatThread] conversation access check failed: $e');
      if (mounted) setState(() => _convVerified = false);
    }
  }

  @override
  void dispose() {
    _convStatusSub?.cancel();
    _messageController.dispose();
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

  /// Routes the conversation body through the verification result.
  /// This is the UI-layer gate that mirrors the Firestore rule.
  Widget _buildConversationBody() {
    if (_convVerified == null) {
      // Fetch in flight.
      return const Center(child: CircularProgressIndicator());
    }
    if (_convVerified == false) {
      // Denied — show a neutral error; don't leak why.
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
    }
    // Verified — show live stream.
    return _buildChatStream();
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
        });

        if (docs.isEmpty) {
          return Center(
            child: Text(
              'Say hello to ${widget.otherFirstName}!',
              style: AppTextStyles.bodyS,
            ),
          );
        }

        final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';

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
    // Conversation path: footer tracks verification state.
    if (widget.conversationId != null) {
      if (_convVerified == true) return _buildComposer(context);
      // Loading or denied: no footer chrome needed.
      return const SizedBox.shrink();
    }
    // Static path: footer follows the passed status.
    if (_isLocked) return _buildLockedFooter();
    return _buildHistoryFooter();
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
                style: AppTextStyles.body
                    .copyWith(color: AppColors.textPrimary),
                maxLines: 5,
                minLines: 1,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
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
      await convRef.update({
        'lastMessage': text,
        'lastMessageAt': FieldValue.serverTimestamp(),
      });
      _messageController.clear();
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
      final db = FirebaseFirestore.instance;
      final batch = db.batch();
      // Forward entry: my blocked-users list.
      batch.set(
        db.collection('users').doc(myUid).collection('blockedUsers').doc(otherId),
        {'blockedAt': FieldValue.serverTimestamp(), 'displayName': widget.otherFirstName, 'photoUrl': widget.otherPhotoUrl},
      );
      // Reverse entry: lets the blocked user stream who has blocked them.
      batch.set(
        db.collection('blockedBy').doc(otherId).collection('blockers').doc(myUid),
        {'blockedAt': FieldValue.serverTimestamp()},
      );
      await batch.commit();
      debugPrint('[ChatBlock] blocked $otherId (${widget.otherFirstName})');
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      debugPrint('[ChatBlock] write failed: $e');
      if (mounted) {
        setState(() => _isBlocking = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Could not block. Please try again.')),
        );
      }
    }
  }

  void _showProfileSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _ProfilePreviewSheet(
        firstName: widget.otherFirstName,
        photoUrl: widget.otherPhotoUrl,
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

// ── Profile preview sheet ─────────────────────────────────────────────────────

class _ProfilePreviewSheet extends StatelessWidget {
  const _ProfilePreviewSheet({
    required this.firstName,
    required this.photoUrl,
  });

  final String firstName;
  final String photoUrl;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          _AvatarCircle(
            url: photoUrl,
            initials: firstName.isNotEmpty ? firstName[0] : '?',
            radius: 44,
          ),
          const SizedBox(height: 16),
          Text(firstName, style: AppTextStyles.h2),
          const SizedBox(height: 6),
          Text('Profile preview', style: AppTextStyles.bodyS),
          const SizedBox(height: 28),
          Container(
            width: double.infinity,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.bgSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.divider),
            ),
            alignment: Alignment.center,
            child: Text(
              'Full profile — coming soon',
              style: AppTextStyles.bodyS,
            ),
          ),
        ],
      ),
    );
  }
}
