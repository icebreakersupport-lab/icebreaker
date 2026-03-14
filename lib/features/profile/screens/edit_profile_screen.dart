import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/gradient_scaffold.dart';
import '../../../shared/widgets/pill_button.dart';

/// Edit Profile screen — stub with Bio, Interests, Hobbies, Preferences sections.
///
/// [initialSection] scrolls/highlights the relevant section on open.
/// Valid values: 'bio' | 'interests' | 'hobbies' | 'preferences'
/// (null = show full screen from top)
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key, this.initialSection});
  final String? initialSection;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final ScrollController _scroll = ScrollController();

  // Section GlobalKeys for scroll-to
  final _bioKey = GlobalKey();
  final _interestsKey = GlobalKey();
  final _hobbiesKey = GlobalKey();
  final _prefsKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (widget.initialSection != null) {
      // Scroll after first frame so layout is complete
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollTo(widget.initialSection!));
    }
  }

  void _scrollTo(String section) {
    final key = switch (section) {
      'bio' => _bioKey,
      'interests' => _interestsKey,
      'hobbies' => _hobbiesKey,
      'preferences' => _prefsKey,
      _ => null,
    };
    if (key?.currentContext == null) return;
    Scrollable.ensureVisible(
      key!.currentContext!,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text('Edit Profile', style: AppTextStyles.h3),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.textSecondary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Save',
                style: AppTextStyles.buttonS
                    .copyWith(color: AppColors.brandPink),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
          children: [
            // ── Bio ──────────────────────────────────────────────────────
            _SectionCard(
              key: _bioKey,
              title: 'Bio',
              accent: AppColors.brandPink,
              icon: Icons.edit_note_rounded,
              highlight: widget.initialSection == 'bio',
              child: _StubTextArea(
                placeholder:
                    'Tell people who you are in a few sentences…\n\nMax 150 characters.',
                lines: 4,
              ),
            ),

            const SizedBox(height: 16),

            // ── Interests ─────────────────────────────────────────────────
            _SectionCard(
              key: _interestsKey,
              title: 'Interests',
              accent: AppColors.brandCyan,
              icon: Icons.tag_rounded,
              highlight: widget.initialSection == 'interests',
              child: _StubChipArea(
                placeholder: 'Add at least 3 interests',
                examples: const [
                  'Music', 'Travel', 'Photography', 'Food', 'Sport',
                  'Art', 'Tech', 'Film', 'Fashion', 'Books',
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Hobbies ───────────────────────────────────────────────────
            _SectionCard(
              key: _hobbiesKey,
              title: 'Hobbies',
              accent: AppColors.brandPurple,
              icon: Icons.emoji_emotions_rounded,
              highlight: widget.initialSection == 'hobbies',
              child: _StubChipArea(
                placeholder: 'Add at least 2 hobbies',
                examples: const [
                  'Hiking', 'Cooking', 'Gaming', 'Yoga', 'Cycling',
                  'Painting', 'Dancing', 'Running', 'Surfing',
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Dating Preferences ────────────────────────────────────────
            _SectionCard(
              key: _prefsKey,
              title: 'Dating Preferences',
              accent: const Color(0xFFFFD700),
              icon: Icons.favorite_border_rounded,
              highlight: widget.initialSection == 'preferences',
              child: const _StubPreferences(),
            ),

            const SizedBox(height: 24),

            PillButton.primary(
              label: 'Save Changes',
              onTap: () => Navigator.of(context).pop(),
              width: double.infinity,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Section card ──────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    super.key,
    required this.title,
    required this.accent,
    required this.icon,
    required this.child,
    this.highlight = false,
  });

  final String title;
  final Color accent;
  final IconData icon;
  final Widget child;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: highlight
              ? accent.withValues(alpha: 0.60)
              : AppColors.divider,
          width: highlight ? 1.5 : 1.0,
        ),
        boxShadow: highlight
            ? [
                BoxShadow(
                  color: accent.withValues(alpha: 0.14),
                  blurRadius: 16,
                  spreadRadius: 0,
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accent, size: 18),
              const SizedBox(width: 8),
              Text(
                title,
                style: AppTextStyles.h3.copyWith(
                  color: accent,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

// ── Stub widgets ──────────────────────────────────────────────────────────────

class _StubTextArea extends StatelessWidget {
  const _StubTextArea({required this.placeholder, this.lines = 3});
  final String placeholder;
  final int lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Text(
        placeholder,
        style: AppTextStyles.bodyS.copyWith(
          color: AppColors.textMuted,
          height: 1.6,
        ),
      ),
    );
  }
}

class _StubChipArea extends StatelessWidget {
  const _StubChipArea({required this.placeholder, required this.examples});
  final String placeholder;
  final List<String> examples;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          placeholder,
          style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: examples.map((tag) {
            return Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.bgElevated,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.divider),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_rounded,
                      size: 13, color: AppColors.textMuted),
                  const SizedBox(width: 4),
                  Text(
                    tag,
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _StubPreferences extends StatelessWidget {
  const _StubPreferences();

  @override
  Widget build(BuildContext context) {
    const rows = [
      ('Looking for', 'Select…'),
      ('Interested in', 'Select gender(s)…'),
      ('Age range', '18 – 35'),
    ];
    return Column(
      children: rows.map((row) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: Text(
                  row.$1,
                  style: AppTextStyles.bodyS
                      .copyWith(color: AppColors.textSecondary),
                ),
              ),
              Expanded(
                flex: 3,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.bgElevated,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(row.$2,
                          style: AppTextStyles.bodyS
                              .copyWith(color: AppColors.textMuted)),
                      const Icon(Icons.chevron_right_rounded,
                          size: 16, color: AppColors.textMuted),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
