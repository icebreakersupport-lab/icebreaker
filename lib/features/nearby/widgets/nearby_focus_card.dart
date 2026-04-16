import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/pill_button.dart';
import '../../reports/widgets/report_sheet.dart';

/// The hero profile card shown in the Nearby discovery carousel.
///
/// Intentionally minimal — attraction and quick ID only:
///   - Full-bleed portrait photo
///   - Gradient border ring (pink → purple → cyan) with outer neon glow
///   - Deep bottom scrim
///   - Name + age overlay
///   - Gold badge (optional)
///   - "Send Icebreaker" CTA at card bottom
///
/// Bio, distance, hometown, and chat opener are deliberately excluded;
/// those live in the NearbyAboutMeCard below the carousel.
///
/// [isActive] drives scale (1.0 vs 0.94) and glow intensity.
class NearbyFocusCard extends StatelessWidget {
  const NearbyFocusCard({
    super.key,
    required this.recipientId,
    required this.firstName,
    required this.age,
    required this.photoUrl,
    this.isGold = false,
    this.isActive = true,
    required this.onSendIcebreaker,
    required this.onBlock,
  });

  final String recipientId;
  final String firstName;
  final int age;
  final String photoUrl;
  final bool isGold;

  /// True when this card is the centred, focused card in the carousel.
  final bool isActive;

  final VoidCallback onSendIcebreaker;

  /// Called after the user confirms a block action for this card.
  final VoidCallback onBlock;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Vertical breathing room lets the glow shadow render unclipped.
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      child: AnimatedScale(
        scale: isActive ? 1.0 : 0.94,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: isActive ? 1.0 : 0.60,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          child: _GlowBorderShell(
            isActive: isActive,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // ── Photo ─────────────────────────────────────────────────────
                _Photo(url: photoUrl),

                // ── Bottom scrim ──────────────────────────────────────────────
                const _BottomScrim(),

                // ── Gold badge ────────────────────────────────────────────────
                if (isGold)
                  const Positioned(
                    top: 16,
                    right: 16,
                    child: _GoldBadge(),
                  ),

                // ── More-options button (top-left) ────────────────────────────
                Positioned(
                  top: 14,
                  left: 14,
                  child: _MoreOptionsButton(
                    recipientId: recipientId,
                    firstName: firstName,
                    cardContext: context,
                    onBlock: onBlock,
                  ),
                ),

                // ── Bottom overlay: name + age + button ───────────────────────
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 18,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Name + age row
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Flexible(
                            child: Text(
                              firstName,
                              style: AppTextStyles.h1.copyWith(
                                fontSize: 36,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.8,
                                shadows: const [
                                  Shadow(color: Colors.black87, blurRadius: 10),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 5),
                            child: Text(
                              '$age',
                              style: AppTextStyles.h3.copyWith(
                                color: AppColors.textSecondary,
                                shadows: const [
                                  Shadow(color: Colors.black87, blurRadius: 6),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 18),

                      // CTA button — centered label, no icon/emoji
                      PillButton.primary(
                        label: 'Send Icebreaker',
                        onTap: onSendIcebreaker,
                        width: double.infinity,
                        height: 52,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _MoreOptionsButton
// ─────────────────────────────────────────────────────────────────────────────

/// Small frosted pill button in the top-left corner of the card.
/// Tapping opens a bottom sheet with the Block action.
///
/// [cardContext] is the BuildContext from NearbyFocusCard.build — used to
/// show the confirmation dialog after the sheet is dismissed, so the dialog
/// mounts correctly on the route below the sheet.
class _MoreOptionsButton extends StatelessWidget {
  const _MoreOptionsButton({
    required this.recipientId,
    required this.firstName,
    required this.cardContext,
    required this.onBlock,
  });

  final String recipientId;
  final String firstName;
  final BuildContext cardContext;
  final VoidCallback onBlock;

  void _showOptions() {
    showModalBottomSheet<void>(
      context: cardContext,
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
              // ── Report ──────────────────────────────────────────────────
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
                  'Report $firstName',
                  style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
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
                  showReportSheet(
                    cardContext,
                    reportedUserId: recipientId,
                    firstName: firstName,
                    source: 'nearby',
                  );
                },
              ),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Divider(
                    height: 1, color: AppColors.divider.withValues(alpha: 0.6)),
              ),

              // ── Block ────────────────────────────────────────────────────
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
                  'Block $firstName',
                  style: AppTextStyles.body.copyWith(
                    color: AppColors.danger,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  'They won\'t see you or be able to message you',
                  style:
                      AppTextStyles.caption.copyWith(color: AppColors.textMuted),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                onTap: () async {
                  Navigator.of(sheetCtx).pop();
                  // Confirm before blocking.
                  final confirmed = await showDialog<bool>(
                    context: cardContext,
                    builder: (dialogCtx) => AlertDialog(
                      backgroundColor: AppColors.bgElevated,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18)),
                      title: Text(
                        'Block $firstName?',
                        style: AppTextStyles.h3
                            .copyWith(color: AppColors.textPrimary),
                      ),
                      content: Text(
                        '$firstName won\'t appear in Nearby and '
                        'won\'t be able to send you Icebreakers.',
                        style: AppTextStyles.bodyS,
                      ),
                      actions: [
                        TextButton(
                          onPressed: () =>
                              Navigator.of(dialogCtx).pop(false),
                          child: Text(
                            'Cancel',
                            style: AppTextStyles.body.copyWith(
                                color: AppColors.textSecondary),
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
                  if (confirmed == true) onBlock();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _showOptions,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: Colors.white.withValues(alpha: 0.12), width: 0.5),
        ),
        child: const Icon(
          Icons.more_horiz_rounded,
          color: Colors.white,
          size: 20,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _GlowBorderShell
// ─────────────────────────────────────────────────────────────────────────────

/// Outer container that renders the gradient border ring and neon glow.
///
/// Technique: gradient Container (2.5 pt) → padding → ClipRRect (child).
/// The outer boxShadow layers create the soft neon glow.
class _GlowBorderShell extends StatelessWidget {
  const _GlowBorderShell({required this.isActive, required this.child});

  final bool isActive;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.brandPink,
            AppColors.brandPurple,
            AppColors.brandCyan,
          ],
          stops: [0.0, 0.55, 1.0],
        ),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: AppColors.brandPink.withValues(alpha: 0.45),
                  blurRadius: 30,
                  spreadRadius: 2,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: AppColors.brandPurple.withValues(alpha: 0.30),
                  blurRadius: 52,
                  spreadRadius: 0,
                  offset: const Offset(0, 14),
                ),
              ]
            : [
                BoxShadow(
                  color: AppColors.brandPink.withValues(alpha: 0.08),
                  blurRadius: 12,
                  spreadRadius: 0,
                ),
              ],
      ),
      padding: const EdgeInsets.all(2.5),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: child,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _Photo
// ─────────────────────────────────────────────────────────────────────────────

class _Photo extends StatelessWidget {
  const _Photo({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    if (url.isNotEmpty) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : const _PhotoPlaceholder(),
        errorBuilder: (context, error, stackTrace) => const _PhotoPlaceholder(),
      );
    }
    return const _PhotoPlaceholder();
  }
}

class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.bgSurface, AppColors.bgElevated],
        ),
      ),
      child: const Center(
        child: Icon(Icons.person_rounded, size: 72, color: AppColors.textMuted),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _BottomScrim
// ─────────────────────────────────────────────────────────────────────────────

class _BottomScrim extends StatelessWidget {
  const _BottomScrim();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0.30, 0.62, 1.0],
          colors: [
            Colors.transparent,
            Color(0xBB000000),
            Color(0xF2000000),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _GoldBadge
// ─────────────────────────────────────────────────────────────────────────────

class _GoldBadge extends StatelessWidget {
  const _GoldBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFFFD700),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFD700).withValues(alpha: 0.40),
            blurRadius: 10,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Text(
        'GOLD',
        style: AppTextStyles.caption.copyWith(
          color: Colors.black,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.9,
        ),
      ),
    );
  }
}

