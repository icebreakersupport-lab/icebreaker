import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/pill_button.dart';
import '../../reports/widgets/report_sheet.dart';

/// Image kind tag for the Nearby hero rail.  Both kinds render with
/// [BoxFit.cover] so the photo fills the entire card edge-to-edge.  The
/// kind is preserved for future per-source treatment (badges, ordering,
/// etc.) but no longer drives framing.
enum NearbyImageKind { liveSelfie, profilePhoto }

/// One entry in the hero card's image rail.  Carries the URL plus a [kind]
/// so the rail can pick the right framing per image instead of treating
/// every URL identically.
class NearbyImage {
  const NearbyImage({required this.url, required this.kind});

  final String url;
  final NearbyImageKind kind;
}

/// The hero profile card shown in the Nearby discovery carousel.
///
/// Intentionally minimal — attraction and quick ID only:
///   - Full-bleed portrait photo with horizontal swipe through this user's
///     image rail (live selfie first, then profile gallery)
///   - Gradient border ring (pink → purple → cyan) with outer neon glow
///   - Deep bottom scrim
///   - Name + age overlay
///   - Gold badge (optional)
///   - "Send Icebreaker" CTA at card bottom
///
/// Bio, distance, hometown, and chat opener are deliberately excluded;
/// those live in the NearbyAboutMeCard below.
///
/// Gesture model — nested horizontal PageViews:
///   The card's photo region owns an inner horizontal [PageView] for its
///   own image rail.  The OUTER between-people PageView lives above this
///   widget and reads its gestures from the about-me area below the card,
///   not from this card's surface (Flutter routes a horizontal drag to the
///   deepest scrollable that wants it; the inner PageView wins inside the
///   card).  When the inner reaches an edge it bounces in place rather than
///   advancing the outer — release and drag on the about-me card to change
///   person.  See `_buildDiscovery` in nearby_screen.dart for the layout.
///
/// [isActive] drives glow intensity only.  Page-level scale/opacity for
/// active vs inactive cards is applied by the parent in `_buildDiscovery`
/// so the about-me card below this hero dims/shrinks in lockstep.
class NearbyFocusCard extends StatefulWidget {
  const NearbyFocusCard({
    super.key,
    required this.recipientId,
    required this.firstName,
    required this.age,
    required this.images,
    this.isGold = false,
    this.isActive = true,
    this.hideActions = false,
    this.onSendIcebreaker,
    this.onBlock,
  });

  final String recipientId;
  final String firstName;
  final int age;

  /// Ordered display rail.  Index 0 is preferred to be the live selfie
  /// ([NearbyImageKind.liveSelfie]) and is followed by profile gallery
  /// entries ([NearbyImageKind.profilePhoto]) in profile order.  Empty
  /// list renders the placeholder gradient.
  final List<NearbyImage> images;

  final bool isGold;

  /// True when this card is the centred, focused card in the carousel.
  final bool isActive;

  /// When true, suppresses the more-options menu (top-left) and the
  /// "Send Icebreaker" CTA at the bottom.  Used by surfaces that re-use
  /// the card chrome but don't need the Nearby-discovery actions — most
  /// notably the chat profile sheet, where the user is already in a
  /// conversation with this person and block/report live on the chat
  /// thread itself.
  final bool hideActions;

  /// Tapped to send an icebreaker.  Required when [hideActions] is false.
  final VoidCallback? onSendIcebreaker;

  /// Called after the user confirms a block action for this card.
  /// Required when [hideActions] is false.
  final VoidCallback? onBlock;

  @override
  State<NearbyFocusCard> createState() => _NearbyFocusCardState();
}

class _NearbyFocusCardState extends State<NearbyFocusCard> {
  late final PageController _imageController = PageController();
  int _imageIndex = 0;

  @override
  void didUpdateWidget(covariant NearbyFocusCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the image rail shrank below the current index (e.g., a profile photo
    // was removed mid-session), clamp back to a valid page so the indicator
    // and PageView stay in sync.
    if (_imageIndex >= widget.images.length && widget.images.isNotEmpty) {
      _imageIndex = widget.images.length - 1;
      if (_imageController.hasClients) {
        _imageController.jumpToPage(_imageIndex);
      }
    }
  }

  @override
  void dispose() {
    _imageController.dispose();
    super.dispose();
  }

  Widget _buildPhoto(NearbyImage image) {
    return _Photo(url: image.url);
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.images;
    return Padding(
      // Vertical breathing room lets the glow shadow render unclipped.
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      child: _GlowBorderShell(
        isActive: widget.isActive,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── Image rail ────────────────────────────────────────────────
            if (images.isEmpty)
              const _PhotoPlaceholder()
            else if (images.length == 1)
              _buildPhoto(images.first)
            else
              PageView.builder(
                controller: _imageController,
                itemCount: images.length,
                physics: const PageScrollPhysics(),
                onPageChanged: (i) => setState(() => _imageIndex = i),
                itemBuilder: (_, i) => _buildPhoto(images[i]),
              ),

            // ── Bottom scrim ──────────────────────────────────────────────
            // Decorative only — `IgnorePointer` so horizontal drag events
            // sail through to the image-rail PageView underneath.  Without
            // this, the scrim's `BoxDecoration` absorbs hit-tests across
            // the bottom ~70% of the card and the rail feels unswipeable
            // anywhere near the name/age band.
            const IgnorePointer(child: _BottomScrim()),

            // ── Image position indicators (dots) ──────────────────────────
            // Also pointer-transparent — same rationale as the scrim.  The
            // active-dot pill is wide enough to swallow a drag start that
            // begins near the top of the card.
            if (images.length > 1)
              Positioned(
                top: 14,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Center(
                    child: _PageIndicators(
                      count: images.length,
                      index: _imageIndex,
                    ),
                  ),
                ),
              ),

            // ── Gold badge ────────────────────────────────────────────────
            if (widget.isGold)
              const Positioned(
                top: 16,
                right: 16,
                child: IgnorePointer(child: _GoldBadge()),
              ),

            // ── More-options button (top-left) ────────────────────────────
            if (!widget.hideActions)
              Positioned(
                top: 14,
                left: 14,
                child: _MoreOptionsButton(
                  recipientId: widget.recipientId,
                  firstName: widget.firstName,
                  cardContext: context,
                  onBlock: widget.onBlock ?? () {},
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
                          widget.firstName,
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
                          '${widget.age}',
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

                  if (!widget.hideActions) ...[
                    const SizedBox(height: 18),

                    // CTA button — centered label, no icon/emoji
                    PillButton.primary(
                      label: 'Send Icebreaker',
                      onTap: widget.onSendIcebreaker ?? () {},
                      width: double.infinity,
                      height: 52,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _PageIndicators
// ─────────────────────────────────────────────────────────────────────────────

/// Horizontal row of small dots showing which image in the rail is active.
/// Rendered above the gold badge / more-options buttons; sits inside the
/// card's clipped corners so it never punches through the gradient ring.
///
/// Wrapped in a translucent dark capsule so the dots stay legible against
/// any photo — pure-white dots over a bright outdoor selfie used to wash
/// out, and a per-dot drop shadow couldn't carry that on its own.  The
/// capsule reads as a single intentional indicator pill rather than five
/// stranded specks.
class _PageIndicators extends StatelessWidget {
  const _PageIndicators({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(count, (i) {
          final isActive = i == index;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: isActive ? 18 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: isActive
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(99),
            ),
          );
        }),
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
    // Stops are tuned to the bottom-overlay geometry: the name+age band sits
    // around 80% down the card (just above the 18 pt margin + 52 pt CTA +
    // 18 pt gap + 36 pt name = ~124 pt from bottom).  So:
    //   • 0.0 → 0.58: fully transparent — the upper portrait reads clean
    //     and the photo's own composition (eyes, framing) carries the card.
    //   • 0.58 → 0.82: ramp from 0 to ~63% black — the dim arrives just in
    //     time to back the name without bleeding into the middle of the
    //     image.  Lighter than the previous 0xBB middle so the transition
    //     feels like a vignette, not a curtain.
    //   • 0.82 → 1.0: ramp to 0xF2 (~95%) — full readability behind the
    //     CTA pill on bright outdoor photos.
    // The name itself also carries `Shadow(blurRadius: 10)` (see build()),
    // so the scrim only needs to provide a backdrop, not full coverage.
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0.58, 0.82, 1.0],
          colors: [
            Colors.transparent,
            Color(0xA0000000),
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
