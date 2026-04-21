import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/pill_button.dart';

// ── Reason model ──────────────────────────────────────────────────────────────

class _ReportReason {
  const _ReportReason({
    required this.label,
    required this.description,
    required this.firestoreValue,
    required this.icon,
    required this.iconColor,
  });

  final String label;
  final String description;

  /// Value written to Firestore — must match the security rule allowlist.
  final String firestoreValue;
  final IconData icon;
  final Color iconColor;
}

const _reasons = [
  _ReportReason(
    label: 'Harassment or threats',
    description: 'Abusive, threatening, or bullying behaviour',
    firestoreValue: 'harassment',
    icon: Icons.warning_amber_rounded,
    iconColor: Color(0xFFFF6B35),
  ),
  _ReportReason(
    label: 'Spam or scam',
    description: 'Advertising, bots, or fraudulent activity',
    firestoreValue: 'spam',
    icon: Icons.block_rounded,
    iconColor: AppColors.warning,
  ),
  _ReportReason(
    label: 'Fake profile',
    description: 'Impersonation or misleading identity',
    firestoreValue: 'fake_profile',
    icon: Icons.person_off_rounded,
    iconColor: AppColors.brandPurple,
  ),
  _ReportReason(
    label: 'Inappropriate content',
    description: 'Explicit, offensive, or adult material',
    firestoreValue: 'inappropriate_content',
    icon: Icons.visibility_off_rounded,
    iconColor: AppColors.danger,
  ),
  _ReportReason(
    label: 'Other',
    description: 'Anything else that feels wrong',
    firestoreValue: 'other',
    icon: Icons.flag_rounded,
    iconColor: AppColors.textSecondary,
  ),
];

// ── Public entry point ────────────────────────────────────────────────────────

/// Opens the report bottom sheet.
///
/// [reportedUserId] — UID of the person being reported.
/// [firstName]      — Display name shown in the sheet title.
/// [conversationId] — Optional; attached to the report for context.
/// [source]         — Origin surface ('chat' | 'nearby').
void showReportSheet(
  BuildContext context, {
  required String reportedUserId,
  required String firstName,
  String? conversationId,
  String source = 'chat',
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ReportSheet(
      reportedUserId: reportedUserId,
      firstName: firstName,
      conversationId: conversationId,
      source: source,
    ),
  );
}

// ── Sheet widget ──────────────────────────────────────────────────────────────

class _ReportSheet extends StatefulWidget {
  const _ReportSheet({
    required this.reportedUserId,
    required this.firstName,
    required this.conversationId,
    required this.source,
  });

  final String reportedUserId;
  final String firstName;
  final String? conversationId;
  final String source;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  _ReportReason? _selected;
  final _noteController = TextEditingController();
  bool _submitting = false;
  bool _submitted = false;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  bool get _canSubmit => _selected != null && !_submitting;

  Future<void> _submit() async {
    if (!_canSubmit) return;

    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) return;

    setState(() => _submitting = true);
    try {
      final db = FirebaseFirestore.instance;
      final reason = _selected!.firestoreValue;
      final reportedRef = db.collection('users').doc(widget.reportedUserId);
      final dedupRef = reportedRef.collection('reportedBy').doc(myUid);

      // ── Dedup check ──────────────────────────────────────────────────────
      // If this reporter has already reported this user, show the success
      // state without writing a second record.
      final existing = await dedupRef.get();
      if (existing.exists) {
        debugPrint('[Report] duplicate — $myUid already reported ${widget.reportedUserId}');
        if (mounted) setState(() => _submitted = true);
        return;
      }

      // ── Write report + dedup index in parallel ───────────────────────────
      final payload = <String, dynamic>{
        'reporterId': myUid,
        'reportedId': widget.reportedUserId,
        'reason': reason,
        'note': _noteController.text.trim(),
        'source': widget.source,
        'createdAt': FieldValue.serverTimestamp(),
      };
      if (widget.conversationId != null) {
        payload['conversationId'] = widget.conversationId;
      }

      await Future.wait([
        db.collection('reports').add(payload),
        dedupRef.set({
          'reportedAt': FieldValue.serverTimestamp(),
          'reason': reason,
        }),
      ]);

      debugPrint('[Report] submitted for ${widget.reportedUserId} '
          'reason=$reason source=${widget.source}');

      if (mounted) setState(() => _submitted = true);
    } catch (e) {
      debugPrint('[Report] write failed: $e');
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not submit report. Please try again.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).viewInsets.bottom +
        MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(0, 0, 0, bottomPad),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: _submitted ? _buildSuccess() : _buildForm(),
      ),
    );
  }

  // ── Form ───────────────────────────────────────────────────────────────────

  Widget _buildForm() {
    return SingleChildScrollView(
      key: const ValueKey('form'),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 14, bottom: 20),
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Title
          Text(
            'Report ${widget.firstName}',
            style: AppTextStyles.h3,
          ),
          const SizedBox(height: 6),
          Text(
            'Help keep Icebreaker safe. Reports are reviewed by our team and kept confidential.',
            style: AppTextStyles.bodyS,
          ),

          const SizedBox(height: 24),

          // Reason list
          ...List.generate(_reasons.length, (i) {
            final reason = _reasons[i];
            final isSelected = _selected == reason;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ReasonTile(
                reason: reason,
                isSelected: isSelected,
                onTap: () => setState(() => _selected = reason),
              ),
            );
          }),

          const SizedBox(height: 20),

          // Optional notes
          _NotesField(controller: _noteController),

          const SizedBox(height: 24),

          // Submit
          PillButton.primary(
            label: 'Submit Report',
            onTap: _canSubmit ? _submit : null,
            isLoading: _submitting,
            width: double.infinity,
            height: 52,
          ),

          const SizedBox(height: 12),

          Center(
            child: Text(
              'Reporting will not notify ${widget.firstName}.',
              style: AppTextStyles.caption,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  // ── Success ────────────────────────────────────────────────────────────────

  Widget _buildSuccess() {
    return Padding(
      key: const ValueKey('success'),
      padding: const EdgeInsets.fromLTRB(32, 48, 32, 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Icon
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.success.withValues(alpha: 0.12),
              border: Border.all(
                  color: AppColors.success.withValues(alpha: 0.35), width: 1.5),
            ),
            child: const Icon(
              Icons.shield_rounded,
              color: AppColors.success,
              size: 34,
            ),
          ),

          const SizedBox(height: 24),

          Text(
            'Report submitted',
            style: AppTextStyles.h3,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            'Thank you for helping keep Icebreaker safe.\n'
            'Our team will review your report.',
            style: AppTextStyles.bodyS,
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 32),

          PillButton.outlined(
            label: 'Done',
            onTap: () => Navigator.of(context).pop(),
            width: double.infinity,
            height: 50,
          ),
        ],
      ),
    );
  }
}

// ── Reason tile ───────────────────────────────────────────────────────────────

class _ReasonTile extends StatelessWidget {
  const _ReasonTile({
    required this.reason,
    required this.isSelected,
    required this.onTap,
  });

  final _ReportReason reason;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.brandCyan.withValues(alpha: 0.07)
              : AppColors.bgElevated,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? AppColors.brandCyan.withValues(alpha: 0.55)
                : AppColors.divider,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            // Icon container
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: reason.iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(reason.icon, color: reason.iconColor, size: 18),
            ),

            const SizedBox(width: 14),

            // Label + description
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    reason.label,
                    style: AppTextStyles.body.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? AppColors.brandCyan
                          : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    reason.description,
                    style: AppTextStyles.caption,
                  ),
                ],
              ),
            ),

            const SizedBox(width: 10),

            // Selection indicator
            AnimatedOpacity(
              opacity: isSelected ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 180),
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.brandCyan,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: AppColors.bgBase,
                  size: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Notes field ───────────────────────────────────────────────────────────────

class _NotesField extends StatelessWidget {
  const _NotesField({required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Additional details',
          style: AppTextStyles.bodyS.copyWith(
              color: AppColors.textSecondary, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppColors.bgInput,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.divider),
          ),
          child: TextField(
            controller: controller,
            maxLines: 3,
            minLines: 2,
            maxLength: 500,
            buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
            style: AppTextStyles.body,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'Optional — describe what happened...',
              hintStyle:
                  AppTextStyles.body.copyWith(color: AppColors.textMuted),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              border: InputBorder.none,
            ),
          ),
        ),
      ],
    );
  }
}
