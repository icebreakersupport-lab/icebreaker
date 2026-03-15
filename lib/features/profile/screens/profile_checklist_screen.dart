import 'package:flutter/material.dart';

import '../../../core/models/profile_completion.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/gradient_scaffold.dart';
import '../../home/screens/live_verification_screen.dart';
import 'edit_profile_screen.dart';
import 'gallery_screen.dart';

/// Profile Checklist screen.
///
/// Shows the user exactly what is done, what is missing, and how each
/// item contributes to their overall profile score (0–100%).
///
/// Layout:
///   AppBar
///   Large circular progress ring + "XX% Complete" + pts earned
///   "X of 12 items complete" summary row
///   Scrollable category sections — each item shows:
///     ✓/✗ icon | title + description | pts badge
///     incomplete items also show a hint tip
class ProfileChecklistScreen extends StatelessWidget {
  const ProfileChecklistScreen({super.key, required this.score});

  final ProfileCompletionScore score;

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text('Profile Checklist', style: AppTextStyles.h3),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.textSecondary),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          children: [
            // ── Progress ring ───────────────────────────────────────────
            _ProgressRing(score: score),

            const SizedBox(height: 20),

            // ── Summary row ──────────────────────────────────────────────
            _SummaryRow(score: score),

            const SizedBox(height: 28),

            // ── Category sections ────────────────────────────────────────
            ...ProfileCompletionCategory.values.map((cat) {
              final items = score.byCategory[cat] ?? [];
              if (items.isEmpty) return const SizedBox.shrink();
              return _CategorySection(category: cat, items: items);
            }),
          ],
        ),
      ),
    );
  }
}

// ── Progress ring ─────────────────────────────────────────────────────────────

class _ProgressRing extends StatelessWidget {
  const _ProgressRing({required this.score});
  final ProfileCompletionScore score;

  @override
  Widget build(BuildContext context) {
    final pct = score.percentage / 100.0;

    return Center(
      child: SizedBox(
        width: 180,
        height: 180,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Track (background arc)
            SizedBox.expand(
              child: CircularProgressIndicator(
                value: 1.0,
                strokeWidth: 10,
                color: AppColors.divider,
              ),
            ),
            // Progress arc
            SizedBox.expand(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: pct),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) => CircularProgressIndicator(
                  value: value,
                  strokeWidth: 10,
                  strokeCap: StrokeCap.round,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppColors.brandPink,
                  ),
                ),
              ),
            ),
            // Centre text
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ShaderMask(
                  shaderCallback: (bounds) =>
                      AppColors.brandGradient.createShader(bounds),
                  child: Text(
                    '${score.percentage}%',
                    style: AppTextStyles.h1.copyWith(
                      fontSize: 44,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
                Text(
                  'complete',
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textMuted),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Summary row ───────────────────────────────────────────────────────────────

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.score});
  final ProfileCompletionScore score;

  @override
  Widget build(BuildContext context) {
    final done = score.completed.length;
    final total = score.items.length;

    final itemsChip = _SummaryChip(
      label: '$done of $total items',
      sublabel: 'completed',
      color: AppColors.success,
      icon: Icons.check_circle_rounded,
    );
    final ptsChip = _SummaryChip(
      label: '${score.earnedPoints} / ${score.totalPoints} pts',
      sublabel: 'earned',
      color: AppColors.brandCyan,
      icon: Icons.star_rounded,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // Below 360 dp the two chips sitting side-by-side overflow.
        // Stack them vertically and stretch each to full width instead.
        if (constraints.maxWidth < 360) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              itemsChip,
              const SizedBox(height: 10),
              ptsChip,
            ],
          );
        }
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            itemsChip,
            const SizedBox(width: 12),
            ptsChip,
          ],
        );
      },
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.label,
    required this.sublabel,
    required this.color,
    required this.icon,
  });
  final String label;
  final String sublabel;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: AppTextStyles.buttonS
                    .copyWith(color: color, fontWeight: FontWeight.w700),
              ),
              Text(sublabel,
                  style: AppTextStyles.caption
                      .copyWith(color: color.withValues(alpha: 0.70))),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Category section ──────────────────────────────────────────────────────────

class _CategorySection extends StatelessWidget {
  const _CategorySection({required this.category, required this.items});
  final ProfileCompletionCategory category;
  final List<ProfileCompletionItem> items;

  @override
  Widget build(BuildContext context) {
    final doneCount = items.where((i) => i.isComplete).length;
    final catPts = items.fold(0, (s, i) => s + i.points);
    final earnedPts = items.where((i) => i.isComplete).fold(0, (s, i) => s + i.points);

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Row(
            children: [
              Expanded(
                child: Text(
                  category.label,
                  style: AppTextStyles.h3.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '$doneCount/${items.length}  ·  $earnedPts/$catPts pts',
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Items
          Container(
            decoration: BoxDecoration(
              color: AppColors.bgSurface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.divider),
            ),
            child: Column(
              children: List.generate(items.length, (i) {
                final item = items[i];
                final isLast = i == items.length - 1;
                return Column(
                  children: [
                    _ChecklistItem(item: item),
                    if (!isLast)
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: AppColors.divider,
                        indent: 56,
                      ),
                  ],
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Checklist item ────────────────────────────────────────────────────────────

/// Tappable when incomplete — navigates to the screen that fixes the issue.
/// Completed items show a green check and are non-interactive.
///
/// Navigation map (by item.id):
///   bio, interests, hobbies, preferences → EditProfileScreen(initialSection)
///   photo_first, photo_three            → GalleryScreen()
///   video                               → GalleryScreen(scrollToVideo: true)
///   live_selfie                         → LiveVerificationScreen()
///   name_age, email, location, phone    → complete; no tap
class _ChecklistItem extends StatelessWidget {
  const _ChecklistItem({required this.item});
  final ProfileCompletionItem item;

  void _navigate(BuildContext context) {
    switch (item.id) {
      case 'bio':
      case 'interests':
      case 'hobbies':
      case 'preferences':
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => EditProfileScreen(initialSection: item.id),
        ));
      case 'photo_first':
      case 'photo_three':
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => const GalleryScreen(),
        ));
      case 'video':
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => const GalleryScreen(scrollToVideo: true),
        ));
      case 'live_selfie':
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => const LiveVerificationScreen(),
        ));
      // name_age, email, location, phone — complete; no action
    }
  }

  @override
  Widget build(BuildContext context) {
    final done = item.isComplete;
    final tappable = !done && _hasDest(item.id);
    final iconColor = done ? AppColors.success : AppColors.textMuted;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: tappable ? () => _navigate(context) : null,
        borderRadius: BorderRadius.circular(18),
        splashColor: AppColors.brandPink.withValues(alpha: 0.08),
        highlightColor: AppColors.brandPink.withValues(alpha: 0.04),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Check / X icon
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done
                      ? AppColors.success.withValues(alpha: 0.12)
                      : AppColors.bgElevated,
                  border: Border.all(
                    color: done
                        ? AppColors.success.withValues(alpha: 0.40)
                        : AppColors.divider,
                  ),
                ),
                child: Icon(
                  done ? Icons.check_rounded : Icons.close_rounded,
                  size: 16,
                  color: iconColor,
                ),
              ),

              const SizedBox(width: 12),

              // Title + description + hint
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: AppTextStyles.bodyS.copyWith(
                        color: done
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.description,
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.textMuted),
                    ),
                    if (!done && item.hint.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 9,
                            color: AppColors.brandCyan.withValues(alpha: 0.70),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              item.hint,
                              style: AppTextStyles.caption.copyWith(
                                color:
                                    AppColors.brandCyan.withValues(alpha: 0.80),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // Points badge + chevron for tappable items
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: done
                          ? AppColors.success.withValues(alpha: 0.10)
                          : AppColors.bgElevated,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: done
                            ? AppColors.success.withValues(alpha: 0.30)
                            : AppColors.divider,
                      ),
                    ),
                    child: Text(
                      '+${item.points}',
                      style: AppTextStyles.caption.copyWith(
                        color:
                            done ? AppColors.success : AppColors.textMuted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (tappable) ...[
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: AppColors.textMuted,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static bool _hasDest(String id) => const {
        'bio',
        'interests',
        'hobbies',
        'preferences',
        'photo_first',
        'photo_three',
        'video',
        'live_selfie',
      }.contains(id);
}
