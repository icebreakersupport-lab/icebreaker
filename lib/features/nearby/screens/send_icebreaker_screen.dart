import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/state/user_profile.dart';
import '../../../core/state/flow_coordinator.dart';
import '../../../core/state/live_session.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/pill_button.dart';

/// Send Icebreaker screen.
///
/// Send flow:
///   1. In-memory credit gate (fast, no network).
///   2. Best-effort one-active-at-a-time Firestore query.
///   3. Atomic Firestore transaction:
///        a. Read users/{uid} — authoritative credit count + reset window.
///        b. Apply 24-hour reset if window has expired.
///        c. Verify credits > 0 (server-side safety net).
///        d. Decrement icebreakerCredits + update icebreakerCreditsResetAt.
///        e. Create icebreakers/{auto-id} document.
///   4. Sync in-memory LiveSession state with the transaction result.
///   5. Navigate to Messages.
///
/// If the transaction fails for any reason, credits are NOT deducted
/// and the icebreaker is NOT created.
///
/// Firestore document written to: icebreakers/{auto-id}
///   senderId           — Firebase Auth UID
///   recipientId        — target user ID
///   senderFirstName    — from UserProfile (denormalised)
///   recipientFirstName — from route extra (denormalised)
///   message            — trimmed user input
///   status             — 'sent'
///   createdAt          — Timestamp (client)
///   expiresAt          — Timestamp (client + icebreakerTtlSeconds)
class SendIcebreakerScreen extends StatefulWidget {
  const SendIcebreakerScreen({
    super.key,
    required this.recipientId,
    required this.recipientFirstName,
    required this.recipientAge,
    required this.recipientPhotoUrl,
    required this.recipientBio,
  });

  final String recipientId;
  final String recipientFirstName;
  final int recipientAge;
  final String recipientPhotoUrl;
  final String recipientBio;

  @override
  State<SendIcebreakerScreen> createState() => _SendIcebreakerScreenState();
}

class _SendIcebreakerScreenState extends State<SendIcebreakerScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _isSending = false;

  int get _charsRemaining =>
      AppConstants.icebreakerMessageMaxLength - _controller.text.length;

  bool get _canSend => _controller.text.trim().isNotEmpty && !_isSending;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _focusNode.requestFocus(),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // If the live session expires while this screen is open, pop back to Home
    // immediately.  didChangeDependencies fires whenever LiveSessionScope
    // notifies (because this widget depends on it via LiveSessionScope.of).
    if (!LiveSessionScope.of(context).isLive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go(AppRoutes.home);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ── Send logic ─────────────────────────────────────────────────────────────

  Future<void> _handleSend() async {
    if (!_canSend) return;

    final session = LiveSessionScope.of(context);

    // 0. Live session guard — session may have expired while screen was open.
    if (!session.isLive) {
      _showSnackBar('Your Live session has ended — go Live again to send.');
      if (mounted) context.go(AppRoutes.home);
      return;
    }

    // 1. Quick in-memory gate — avoids a network round-trip when obviously out
    if (session.icebreakerCredits <= 0) {
      _showSnackBar('No Icebreakers left — visit the Shop to get more.');
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _showSnackBar('You must be signed in to send an Icebreaker.');
      return;
    }

    setState(() => _isSending = true);
    debugPrint('[SendIcebreaker] ▶ starting send to ${widget.recipientId}');

    try {
      final db = FirebaseFirestore.instance;

      // 2. Best-effort one-active-at-a-time check.
      //    Fetch all 'sent' docs for this sender (bounded by 24h credit limit,
      //    so always ≤ 3 docs) and filter client-side for expiresAt > now.
      //    This avoids the composite index that a Firestore range filter on
      //    expiresAt would require. Expired docs are opportunistically updated
      //    to 'expired' so they don't accumulate in the Messages stream.
      final snapshot = await db
          .collection('icebreakers')
          .where('senderId', isEqualTo: uid)
          .where('status', isEqualTo: 'sent')
          .get();

      if (!mounted) return;

      final now = DateTime.now();
      bool hasActiveIcebreaker = false;

      for (final doc in snapshot.docs) {
        final expiresAt = (doc['expiresAt'] as Timestamp?)?.toDate();
        if (expiresAt != null && expiresAt.isAfter(now)) {
          hasActiveIcebreaker = true;
        } else {
          // Past the 5-minute TTL — mark expired so the Messages stream
          // and future checks see the correct status.
          db
              .collection('icebreakers')
              .doc(doc.id)
              .update({'status': 'expired'})
              .ignore();
          debugPrint(
              '[SendIcebreaker] marked ${doc.id} as expired (TTL elapsed)');
        }
      }

      if (hasActiveIcebreaker) {
        debugPrint('[SendIcebreaker] ⚠️ existing active icebreaker found');
        _showSnackBar(
            'You already have an active Icebreaker waiting for a response.');
        setState(() => _isSending = false);
        return;
      }

      // 2b. Block preflight — check both directions before spending a network
      //     round-trip on the transaction.  The security rule enforces the same
      //     check, but catching it here gives a specific user-facing message.
      final blockedByMeSnap = await db
          .collection('users')
          .doc(uid)
          .collection('blockedUsers')
          .doc(widget.recipientId)
          .get();

      if (!mounted) return;

      if (blockedByMeSnap.exists) {
        debugPrint('[SendIcebreaker] ⚠️ sender has blocked recipient');
        _showSnackBar(
            'You have blocked ${widget.recipientFirstName}. Unblock them in Settings to send.');
        setState(() => _isSending = false);
        return;
      }

      final blockedByThemSnap = await db
          .collection('users')
          .doc(widget.recipientId)
          .collection('blockedUsers')
          .doc(uid)
          .get();

      if (!mounted) return;

      if (blockedByThemSnap.exists) {
        debugPrint('[SendIcebreaker] ⚠️ recipient has blocked sender');
        _showSnackBar(
            'You can\'t send an Icebreaker to ${widget.recipientFirstName}.');
        setState(() => _isSending = false);
        return;
      }

      // 3. Gather values needed inside the transaction.
      final profile = UserProfileScope.of(context);
      final senderFirstName = profile.firstName;
      // First non-empty photo URL = the user's primary photo for matching
      // surfaces.  Snapshotted onto the icebreaker doc so the sender's
      // wait screen can render the paired-photo hero from `icebreakers/{id}`
      // alone, surviving cold launch / redirect / app resume.
      final senderPhotoUrl = profile.allPhotoUrls
          .firstWhere((u) => u.isNotEmpty, orElse: () => '');
      final expiresAt = now.add(
        const Duration(seconds: AppConstants.icebreakerTtlSeconds),
      );
      final message = _controller.text.trim();

      final userRef = db.collection('users').doc(uid);
      final icebreakerRef = db.collection('icebreakers').doc();

      // Track the post-transaction values so we can update in-memory state.
      int newCredits = 0;
      DateTime? newResetAt;

      // 4. Atomic transaction: read credits → maybe reset → verify → decrement
      //    + create icebreaker. If credits hit zero server-side, the transaction
      //    throws a FirebaseException with code 'no-credits'.
      await db.runTransaction((tx) async {
        final userSnap = await tx.get(userRef);

        // Read stored credits. Default to free allowance if field is absent
        // (covers accounts created before credit fields were added).
        int credits =
            (userSnap.data()?['icebreakerCredits'] as num?)?.toInt() ??
            AppConstants.freeIcebreakerCreditsPerSignup;

        final storedResetAt =
            (userSnap.data()?['icebreakerCreditsResetAt'] as Timestamp?)
                ?.toDate();

        // Apply 24-hour reset if the window has expired.
        final windowExpired =
            storedResetAt != null && now.isAfter(storedResetAt);
        if (windowExpired) {
          debugPrint('[SendIcebreaker] 24h window expired — resetting credits');
          credits = AppConstants.freeIcebreakerCreditsPerSignup;
        }

        // Server-side credit guard. Throws so the transaction aborts cleanly.
        if (credits <= 0) {
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'no-credits',
            message: 'Icebreaker credits exhausted',
          );
        }

        newCredits = credits - 1;
        newResetAt = (windowExpired || storedResetAt == null)
            ? now.add(const Duration(hours: 24))
            : storedResetAt;

        // a. Update user credits.
        tx.update(userRef, {
          'icebreakerCredits': newCredits,
          'icebreakerCreditsResetAt': Timestamp.fromDate(newResetAt!),
        });

        // b. Create icebreaker document.
        tx.set(icebreakerRef, {
          'senderId': uid,
          'recipientId': widget.recipientId,
          'senderFirstName': senderFirstName,
          'recipientFirstName': widget.recipientFirstName,
          'senderPhotoUrl': senderPhotoUrl,
          'recipientPhotoUrl': widget.recipientPhotoUrl,
          'message': message,
          'status': 'sent',
          'createdAt': Timestamp.fromDate(now),
          'expiresAt': Timestamp.fromDate(expiresAt),
        });
      });

      debugPrint('[SendIcebreaker] ✅ transaction committed — '
          'icebreakerId=${icebreakerRef.id} newCredits=$newCredits');

      if (!mounted) return;

      // 5. Sync in-memory state with the committed Firestore values.
      session.setCredits(newCredits, newResetAt);

      // 6. Seed the FlowCoordinator lock BEFORE navigation so the router
      // agrees that /icebreaker-waiting/{id} is a live lock in the very
      // first redirect pass. The outgoing Firestore stream remains the
      // source of truth and will confirm/clear this optimistic value.
      FlowCoordinatorScope.of(context).seedPendingOutgoing(
        icebreakerId: icebreakerRef.id,
        expiresAt: expiresAt,
      );

      // 7. Land the sender directly on the locked wait screen.
      final waitTarget = '${AppRoutes.icebreakerWaiting}/${icebreakerRef.id}';
      context.go(waitTarget);
    } on FirebaseException catch (e) {
      debugPrint('[SendIcebreaker] ❌ FirebaseException '
          'code=${e.code} message=${e.message}');
      if (!mounted) return;
      setState(() => _isSending = false);

      switch (e.code) {
        case 'no-credits':
          session.setCredits(0, session.icebreakerCreditsResetAt);
          _showSnackBar('No Icebreakers left — visit the Shop to get more.');
        case 'permission-denied':
          _showSnackBar(
              'Permission denied — please sign out and sign back in.');
        case 'not-found':
          _showSnackBar(
              'Your account could not be found — please sign out and sign back in.');
        default:
          _showSnackBar('Failed to send — please try again.');
      }
    } catch (e, st) {
      debugPrint('[SendIcebreaker] ❌ unexpected error: $e\n$st');
      if (!mounted) return;
      setState(() => _isSending = false);
      _showSnackBar('Something went wrong — please try again.');
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: AppTextStyles.caption.copyWith(color: Colors.white),
        ),
        backgroundColor: AppColors.bgElevated,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final credits = LiveSessionScope.of(context).icebreakerCredits;
    final hasCredits = credits > 0;

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          // ── Background photo ────────────────────────────────────────────
          Positioned.fill(
            child: widget.recipientPhotoUrl.isNotEmpty
                ? Image.network(
                    widget.recipientPhotoUrl,
                    fit: BoxFit.cover,
                  )
                : Container(
                    color: AppColors.bgSurface,
                    child: const Icon(Icons.person_rounded,
                        size: 120, color: AppColors.textMuted),
                  ),
          ),

          // Gradient overlay
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x66000000), Color(0xDD000000)],
                  stops: [0.0, 0.6],
                ),
              ),
            ),
          ),

          // ── Content ─────────────────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),

                  // Recipient name + hint
                  Center(
                    child: Column(
                      children: [
                        Text(widget.recipientFirstName,
                            style: AppTextStyles.h1),
                        const SizedBox(height: 4),
                        Text(
                          'One message · The worst they can say is no.',
                          style: AppTextStyles.bodyS,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),

                  const Spacer(),

                  if (!hasCredits)
                    _NoCreditsMessage(
                      onShopTap: () => context.push(AppRoutes.shop),
                    )
                  else ...[
                    _MessageInputField(
                      controller: _controller,
                      focusNode: _focusNode,
                      maxLength: AppConstants.icebreakerMessageMaxLength,
                      charsRemaining: _charsRemaining,
                    ),

                    const SizedBox(height: 16),

                    // Credits badge
                    Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.favorite_rounded,
                            size: 12,
                            color:
                                AppColors.brandPink.withValues(alpha: 0.70),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '$credits Icebreaker${credits == 1 ? '' : 's'} remaining',
                            style: AppTextStyles.caption
                                .copyWith(color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    PillButton.cyan(
                      label: 'Send Icebreaker',
                      onTap: _canSend ? _handleSend : null,
                      isLoading: _isSending,
                      width: double.infinity,
                      height: 56,
                    ),
                  ],

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── No-credits gate ───────────────────────────────────────────────────────────

class _NoCreditsMessage extends StatelessWidget {
  const _NoCreditsMessage({required this.onShopTap});
  final VoidCallback onShopTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.brandPink.withValues(alpha: 0.30),
            ),
          ),
          child: Column(
            children: [
              Icon(
                Icons.favorite_rounded,
                size: 36,
                color: AppColors.brandPink.withValues(alpha: 0.60),
              ),
              const SizedBox(height: 12),
              Text('No Icebreakers left',
                  style: AppTextStyles.h3, textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text(
                'Watch an ad or pick up a pack to keep the momentum going.',
                style: AppTextStyles.bodyS
                    .copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        PillButton.primary(
          label: 'Go to Shop',
          onTap: onShopTap,
          width: double.infinity,
          height: 52,
        ),
      ],
    );
  }
}

// ── Message input field ───────────────────────────────────────────────────────

class _MessageInputField extends StatelessWidget {
  const _MessageInputField({
    required this.controller,
    required this.focusNode,
    required this.maxLength,
    required this.charsRemaining,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final int maxLength;
  final int charsRemaining;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.brandCyan.withValues(alpha: 0.4),
              width: 1,
            ),
          ),
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            maxLines: 4,
            minLines: 2,
            maxLength: maxLength,
            buildCounter: (
              _, {
              required currentLength,
              required isFocused,
              maxLength,
            }) =>
                null,
            style: AppTextStyles.body,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'Say something genuine...',
              hintStyle:
                  AppTextStyles.body.copyWith(color: AppColors.textMuted),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 16),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '$charsRemaining',
          style: AppTextStyles.caption.copyWith(
            color: charsRemaining < 20
                ? AppColors.warning
                : AppColors.textMuted,
          ),
        ),
      ],
    );
  }
}
