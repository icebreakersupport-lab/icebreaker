import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/gradient_scaffold.dart';
import '../../../shared/widgets/pill_button.dart';

/// Post-meet decision screen — the connection check.
///
/// Server-driven lifecycle:
///   • Entered when [onMeetupTalkExpired] flips the meetup status from
///     'talking' to 'awaiting_post_talk_decision' and stamps
///     `decisionExpiresAt`.  FlowCoordinator routes both participants here.
///   • Submitting a decision creates `meetups/{id}/decisions/{uid}` with
///     `{ uid, decision, createdAt }`.  Firestore rules gate the write on
///     status === 'awaiting_post_talk_decision' so submissions can only
///     land in this phase.
///   • [onMeetupDecisionWritten] picks up the second decision and either
///     creates the conversation + flips status to 'matched' (mutual
///     'we_got_this') or flips to 'no_match' (any 'nice_meeting_you').
///   • [onMeetupDecisionExpired] flips abandoned meetups to 'no_match'
///     after `decisionExpiresAt` so neither user is stranded waiting on
///     a peer who never opened this screen.
///   • All terminal statuses cascade through [onMeetupTerminal] which
///     clears `currentMeetupId`; FlowCoordinator's redirect then releases
///     us to Nearby.
///
/// Path-parameterised on `meetupId` so a cold-launch redirect can route
/// into this screen using nothing more than `users/{uid}.currentMeetupId`.
class PostMeetScreen extends StatefulWidget {
  const PostMeetScreen({
    super.key,
    required this.meetupId,
  });

  final String meetupId;

  @override
  State<PostMeetScreen> createState() => _PostMeetScreenState();
}

class _PostMeetScreenState extends State<PostMeetScreen> {
  /// Hard-coded match accent — same as MatchedScreen / ColorMatchScreen.
  /// Will live on the meetup doc once match-color lands.
  static const Color _matchColor = Color(0xFFFF6B9D);

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _meetupSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _myDecisionSub;

  Map<String, dynamic>? _meetupData;

  /// My submitted decision, or null if I haven't submitted yet.  Sourced
  /// from `meetups/{id}/decisions/{myUid}` so the screen survives a cold
  /// restart mid-decision-window without losing my choice.
  String? _myDecision;

  bool _loading = true;
  bool _isSubmitting = false;
  String? _error;

  String? get _myUid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    final ref = FirebaseFirestore.instance
        .collection('meetups')
        .doc(widget.meetupId);

    _meetupSub = ref.snapshots().listen(
      (snap) {
        if (!mounted) return;
        setState(() {
          _meetupData = snap.data();
          _loading = false;
          _error = snap.exists ? null : 'Meetup not found.';
        });
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
    _meetupSub?.cancel();
    _myDecisionSub?.cancel();
    super.dispose();
  }

  // ── Derived state ─────────────────────────────────────────────────────────

  String? get _otherUid {
    final ps = List<String>.from(
        (_meetupData?['participants'] as List<dynamic>?) ?? const []);
    return ps.firstWhere((p) => p != _myUid, orElse: () => '');
  }

  String get _otherFirstName {
    final names =
        (_meetupData?['participantNames'] as Map<String, dynamic>?) ?? {};
    return (names[_otherUid] as String?) ?? 'Them';
  }

  String get _otherPhotoUrl {
    final photos =
        (_meetupData?['participantPhotos'] as Map<String, dynamic>?) ?? {};
    return (photos[_otherUid] as String?) ?? '';
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  /// Writes `meetups/{id}/decisions/{myUid}`.  Firestore rules enforce that
  /// status === 'awaiting_post_talk_decision' and the doc id matches the
  /// caller's uid, so this is the entire client side of the decision
  /// pipeline; everything downstream is server-owned.
  Future<void> _submit(String decision) async {
    final uid = _myUid;
    if (uid == null || _isSubmitting || _myDecision != null) return;
    setState(() => _isSubmitting = true);
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
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not submit — try again.')),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
    // No client-side navigation.  When both decisions land or the decision
    // window expires, the meetup hits a terminal status, currentMeetupId
    // clears, and FlowCoordinator's redirect releases us to Nearby.
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    final avatarRadius = (h * 0.11).clamp(56.0, 80.0);

    // Back navigation blocked: the decision phase is owned by the server.
    // Once the user submits, they must wait for the other participant or
    // for the decision-window expiry — both terminal paths release them
    // automatically via FlowCoordinator.
    return PopScope(
      canPop: false,
      child: GradientScaffold(
        body: SafeArea(
          child: _loading
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
                  : _buildContent(avatarRadius),
        ),
      ),
    );
  }

  Widget _buildContent(double avatarRadius) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          const SizedBox(height: 32),
          Text(
            'Did you feel a connection?',
            style: AppTextStyles.h2,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Your answer is private.\n$_otherFirstName will never see your choice.',
            style: AppTextStyles.bodyS,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),
          _Avatar(
            url: _otherPhotoUrl,
            firstName: _otherFirstName,
            radius: avatarRadius,
            matchColor: _matchColor,
          ),
          const SizedBox(height: 16),
          Text(_otherFirstName, style: AppTextStyles.h2),
          const Spacer(),
          if (_myDecision != null)
            _WaitingState(
              decision: _myDecision!,
              otherFirstName: _otherFirstName,
            )
          else
            _DecisionButtons(
              isSubmitting: _isSubmitting,
              onYes: () => _submit('we_got_this'),
              onNo: () => _submit('nice_meeting_you'),
            ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.url,
    required this.firstName,
    required this.radius,
    required this.matchColor,
  });

  final String url;
  final String firstName;
  final double radius;
  final Color matchColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            matchColor,
            matchColor.withValues(alpha: 0.6),
          ],
        ),
      ),
      child: CircleAvatar(
        radius: radius,
        backgroundColor: AppColors.bgElevated,
        backgroundImage: url.isNotEmpty ? NetworkImage(url) : null,
        child: url.isEmpty
            ? Text(
                firstName.isNotEmpty ? firstName[0].toUpperCase() : '?',
                style: AppTextStyles.display
                    .copyWith(color: AppColors.textSecondary),
              )
            : null,
      ),
    );
  }
}

class _DecisionButtons extends StatelessWidget {
  const _DecisionButtons({
    required this.isSubmitting,
    required this.onYes,
    required this.onNo,
  });

  final bool isSubmitting;
  final VoidCallback onYes;
  final VoidCallback onNo;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'Your answer is visible only to you.',
          style: AppTextStyles.caption,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: PillButton.danger(
                label: 'Pass',
                onTap: isSubmitting ? null : onNo,
                height: 64,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: PillButton.success(
                label: 'Stay in touch',
                onTap: isSubmitting ? null : onYes,
                isLoading: isSubmitting,
                height: 64,
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
      children: [
        Icon(
          choseYes ? Icons.favorite_rounded : Icons.waving_hand_rounded,
          size: 48,
          color: choseYes ? AppColors.success : AppColors.textSecondary,
        ),
        const SizedBox(height: 16),
        Text(
          choseYes
              ? 'Waiting for $otherFirstName...'
              : 'Nice meeting $otherFirstName 👋',
          style: AppTextStyles.h3,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          choseYes
              ? "If they're in too, you'll stay in touch."
              : "We'll wrap things up here in a moment.",
          style: AppTextStyles.bodyS,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
