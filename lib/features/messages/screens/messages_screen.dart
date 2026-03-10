import 'package:flutter/material.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/gradient_scaffold.dart';
import '../../../shared/widgets/icebreaker_logo.dart';
import '../widgets/active_now_card.dart';
import '../widgets/message_list_card.dart';
import '../widgets/messages_section_header.dart';

/// Messages tab — 3-section list.
///
/// Section 1 — Active Now: time-sensitive items (pending icebreakers,
///   finding/in_conversation/post_meet conversations), sorted urgency-first.
/// Section 2 — Chats: chat_unlocked conversations, sorted by lastMessageAt DESC.
/// Section 3 — History: ended conversations + declined/expired icebreakers
///   (deduplication: icebreakers with conversationId are excluded here).
///
/// Spec: Revision 4 Final, Part 6.
class MessagesScreen extends StatelessWidget {
  const MessagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // TODO: replace mock data with real Firestore streams via Riverpod
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
    // ── Mock state for UI scaffolding ──────────────────────────────────────
    // Section 1: Active Now — 1 pending icebreaker received
    final activeNowItems = [
      _ActiveNowItem(
        id: 'ib_1',
        otherFirstName: 'Jordan',
        otherPhotoUrl: '',
        statusLabel: 'Respond to Icebreaker 🧊',
        secondsRemaining: 247,
        matchColor: null,
      ),
    ];

    // Section 2: Chats — 1 chat_unlocked conversation
    final chatItems = [
      _ChatItem(
        id: 'conv_1',
        otherFirstName: 'Casey',
        otherPhotoUrl: '',
        lastMessage: 'This is so cool, I can\'t believe we actually met haha',
        timestamp: '2m ago',
        hasUnread: true,
      ),
    ];

    // Section 3: History — 1 declined icebreaker
    final historyItems = [
      _HistoryItem(
        id: 'ib_2',
        otherFirstName: 'Alex',
        otherPhotoUrl: '',
        previewText: 'Icebreaker expired',
        timestamp: 'Yesterday',
        icon: Icons.timer_off_outlined,
      ),
    ];

    final hasActive = activeNowItems.isNotEmpty;
    final hasChats = chatItems.isNotEmpty;
    final hasHistory = historyItems.isNotEmpty;
    final isEmpty = !hasActive && !hasChats && !hasHistory;

    if (isEmpty) {
      return _buildEmptyState();
    }

    return ListView(
      children: [
        // ── Section 1: Active Now ──────────────────────────────────────────
        if (hasActive) ...[
          MessagesSectionHeader(
            title: 'Active Now',
            badge: activeNowItems.length,
          ),
          ...activeNowItems.map(
            (item) => ActiveNowCard(
              otherFirstName: item.otherFirstName,
              otherPhotoUrl: item.otherPhotoUrl,
              statusLabel: item.statusLabel,
              secondsRemaining: item.secondsRemaining,
              matchColor: item.matchColor,
              onTap: () => _handleActiveNowTap(context, item),
            ),
          ),
        ],

        // ── Section 2: Chats ──────────────────────────────────────────────
        if (hasChats) ...[
          const MessagesSectionHeader(title: 'Chats'),
          ...chatItems.map(
            (item) => Column(
              children: [
                MessageListCard(
                  otherFirstName: item.otherFirstName,
                  otherPhotoUrl: item.otherPhotoUrl,
                  previewText: item.lastMessage,
                  timestamp: item.timestamp,
                  hasUnread: item.hasUnread,
                  onTap: () => _handleChatTap(context, item),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Divider(height: 1),
                ),
              ],
            ),
          ),
        ],

        // ── Section 3: History ─────────────────────────────────────────────
        if (hasHistory) ...[
          const MessagesSectionHeader(title: 'History'),
          ...historyItems.map(
            (item) => MessageListCard(
              otherFirstName: item.otherFirstName,
              otherPhotoUrl: item.otherPhotoUrl,
              previewText: item.previewText,
              timestamp: item.timestamp,
              isDimmed: true,
              statusIcon: item.icon,
              onTap: () {},
            ),
          ),
        ],

        const SizedBox(height: 40),
      ],
    );
  }

  void _handleActiveNowTap(BuildContext context, _ActiveNowItem item) {
    // TODO: navigate to appropriate screen based on item type/status
    // - Icebreaker received → IcebreakerReceivedScreen
    // - Finding → MatchedScreen
    // - In conversation → ColorMatchScreen
    // - Post meet → PostMeetScreen
  }

  void _handleChatTap(BuildContext context, _ChatItem item) {
    // TODO: navigate to ChatScreen
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
}

// ── Mock data models ──────────────────────────────────────────────────────────

class _ActiveNowItem {
  const _ActiveNowItem({
    required this.id,
    required this.otherFirstName,
    required this.otherPhotoUrl,
    required this.statusLabel,
    required this.secondsRemaining,
    this.matchColor,
  });
  final String id;
  final String otherFirstName;
  final String otherPhotoUrl;
  final String statusLabel;
  final int secondsRemaining;
  final Color? matchColor;
}

class _ChatItem {
  const _ChatItem({
    required this.id,
    required this.otherFirstName,
    required this.otherPhotoUrl,
    required this.lastMessage,
    required this.timestamp,
    required this.hasUnread,
  });
  final String id;
  final String otherFirstName;
  final String otherPhotoUrl;
  final String lastMessage;
  final String timestamp;
  final bool hasUnread;
}

class _HistoryItem {
  const _HistoryItem({
    required this.id,
    required this.otherFirstName,
    required this.otherPhotoUrl,
    required this.previewText,
    required this.timestamp,
    this.icon,
  });
  final String id;
  final String otherFirstName;
  final String otherPhotoUrl;
  final String previewText;
  final String timestamp;
  final IconData? icon;
}
