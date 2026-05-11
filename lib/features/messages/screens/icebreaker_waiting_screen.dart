import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/gradient_scaffold.dart';
import '../../../shared/widgets/countdown_timer_widget.dart';

/// Sender-side wait screen.  Shown to the user who just sent an icebreaker,
/// locking them on this route (via FlowCoordinator) until the recipient
/// responds or the TTL expires.
///
/// The route is `/icebreaker-waiting/:icebreakerId`.  The FlowCoordinator
/// clears the lock when the underlying `icebreakers/{id}.status` flips from
/// 'pending' to 'accepted', 'declined', or 'expired', so this screen is
/// intentionally passive — it just renders the countdown + the cancel
/// affordance and lets the coordinator drive routing.
class IcebreakerWaitingScreen extends StatefulWidget {
  const IcebreakerWaitingScreen({super.key, required this.icebreakerId});

  final String icebreakerId;

  @override
  State<IcebreakerWaitingScreen> createState() =>
      _IcebreakerWaitingScreenState();
}

class _IcebreakerWaitingScreenState extends State<IcebreakerWaitingScreen> {
  late final StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>
      _docSub;

  String? _recipientName;
  DateTime? _expiresAt;

  @override
  void initState() {
    super.initState();
    _docSub = FirebaseFirestore.instance
        .collection('icebreakers')
        .doc(widget.icebreakerId)
        .snapshots()
        .listen(_onDoc);
  }

  void _onDoc(DocumentSnapshot<Map<String, dynamic>> snap) {
    final data = snap.data();
    if (data == null) return;
    final expires = data['expiresAt'];
    final name = data['recipientFirstName'] as String?;
    setState(() {
      if (expires is Timestamp) _expiresAt = expires.toDate();
      if (name != null && name.isNotEmpty) _recipientName = name;
    });
  }

  @override
  void dispose() {
    _docSub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final headline = _recipientName != null
        ? 'Waiting on ${_recipientName!}'
        : 'Waiting…';
    return GradientScaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.hourglass_bottom_rounded,
                color: AppColors.brandPink,
                size: 56,
              ),
              const SizedBox(height: 20),
              Text(
                headline,
                style: AppTextStyles.h1,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Your icebreaker is on the way. We\'ll move you forward as soon '
                'as they respond — or this expires.',
                style: AppTextStyles.bodyS.copyWith(
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              if (_expiresAt != null)
                CountdownTimerWidget(
                  initialSeconds: _expiresAt!
                      .difference(DateTime.now())
                      .inSeconds
                      .clamp(0, AppConstants.icebreakerTtlSeconds),
                  warningThresholdSeconds:
                      AppConstants.icebreakerWarningSeconds,
                )
              else
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppColors.brandPink,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
