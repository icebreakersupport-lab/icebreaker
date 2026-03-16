import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/gradient_scaffold.dart';
import '../../../shared/widgets/pill_button.dart';

/// Edit Profile screen — full-featured profile editing flow.
///
/// Sections (top → bottom):
///   1. Identity       — name, age
///   2. Photos & Media — quick links to GalleryScreen
///   3. Bio            — 150-char text field with live counter
///   4. Interests      — toggleable chip picker (min 3)
///   5. Hobbies        — toggleable chip picker (min 2)
///   6. Dating Prefs   — looking for, interested in, age range slider
///   7. Profile Details — occupation, height
///
/// [initialSection] scrolls to and highlights the relevant section on open.
/// Values: 'name_age' | 'bio' | 'interests' | 'hobbies' |
///         'preferences' | 'photos' | 'video' | 'details'
/// (null = full screen from top, no banner)
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key, this.initialSection});
  final String? initialSection;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final ScrollController _scroll = ScrollController();

  // Section GlobalKeys for scroll-to anchoring
  final _identityKey = GlobalKey();
  final _mediaKey = GlobalKey();
  final _bioKey = GlobalKey();
  final _interestsKey = GlobalKey();
  final _hobbiesKey = GlobalKey();
  final _prefsKey = GlobalKey();
  final _detailsKey = GlobalKey();

  // Text controllers
  late final TextEditingController _nameCtrl;
  late final TextEditingController _ageCtrl;
  late final TextEditingController _bioCtrl;
  late final TextEditingController _occupationCtrl;
  late final TextEditingController _heightCtrl;

  // Chip-picker state
  final Set<String> _selectedInterests = {'Music', 'Travel'};
  final Set<String> _selectedHobbies = {'Cooking'};

  // Dating preference state
  String _lookingFor = 'Casual dating';
  String _interestedIn = 'Women';
  RangeValues _ageRange = const RangeValues(20, 35);

  // Fades the section highlight out after 3 s
  String? _highlightedSection;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: 'You');
    _ageCtrl = TextEditingController(text: '24');
    _bioCtrl = TextEditingController(text: '');
    _occupationCtrl = TextEditingController(text: 'Product Designer');
    _heightCtrl = TextEditingController(text: "5'10\"");

    _highlightedSection = widget.initialSection;

    if (widget.initialSection != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToSection(widget.initialSection!);
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) setState(() => _highlightedSection = null);
        });
      });
    }
  }

  void _scrollToSection(String section) {
    final key = switch (section) {
      'name_age' => _identityKey,
      'photos' || 'photo_first' || 'photo_three' => _mediaKey,
      'video' => _mediaKey,
      'bio' => _bioKey,
      'interests' => _interestsKey,
      'hobbies' => _hobbiesKey,
      'preferences' => _prefsKey,
      'details' => _detailsKey,
      _ => null,
    };
    final ctx = key?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
      alignment: 0.08,
    );
  }

  bool _isHighlighted(String section) => _highlightedSection == section;

  bool _isMediaHighlighted() =>
      _isHighlighted('photos') ||
      _isHighlighted('photo_first') ||
      _isHighlighted('photo_three') ||
      _isHighlighted('video');

  void _save() {
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _nameCtrl.dispose();
    _ageCtrl.dispose();
    _bioCtrl.dispose();
    _occupationCtrl.dispose();
    _heightCtrl.dispose();
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
              onPressed: _save,
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
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
          children: [
            // ── Focus banner (shown when routed from Profile Checklist) ──────
            if (widget.initialSection != null) ...[
              _FocusBanner(section: widget.initialSection!),
              const SizedBox(height: 16),
            ],

            // ── 1. Identity ──────────────────────────────────────────────────
            _SectionCard(
              key: _identityKey,
              title: 'Identity',
              subtitle: 'Your name and age shown on your profile',
              accent: AppColors.brandPink,
              icon: Icons.person_rounded,
              highlight: _isHighlighted('name_age'),
              child: _IdentitySection(
                nameCtrl: _nameCtrl,
                ageCtrl: _ageCtrl,
              ),
            ),

            const SizedBox(height: 14),

            // ── 2. Photos & Media ────────────────────────────────────────────
            _SectionCard(
              key: _mediaKey,
              title: 'Photos & Media',
              subtitle: 'Upload photos and an optional intro video',
              accent: AppColors.brandCyan,
              icon: Icons.photo_library_rounded,
              highlight: _isMediaHighlighted(),
              child: _MediaSection(),
            ),

            const SizedBox(height: 14),

            // ── 3. Bio ───────────────────────────────────────────────────────
            _SectionCard(
              key: _bioKey,
              title: 'Bio',
              subtitle: 'Tell people who you are — max 150 characters',
              accent: AppColors.brandPink,
              icon: Icons.edit_note_rounded,
              highlight: _isHighlighted('bio'),
              child: _BioField(ctrl: _bioCtrl),
            ),

            const SizedBox(height: 14),

            // ── 4. Interests ─────────────────────────────────────────────────
            _SectionCard(
              key: _interestsKey,
              title: 'Interests',
              subtitle: 'Pick at least 3 — shown on your profile card',
              accent: AppColors.brandCyan,
              icon: Icons.tag_rounded,
              highlight: _isHighlighted('interests'),
              child: _ChipPicker(
                selected: _selectedInterests,
                options: const [
                  'Music', 'Travel', 'Photography', 'Food', 'Sport',
                  'Art', 'Tech', 'Film', 'Fashion', 'Books',
                  'Fitness', 'Gaming', 'Nature', 'Coffee', 'Wine',
                ],
                accent: AppColors.brandCyan,
                minCount: 3,
                onChanged: (tag, on) => setState(() {
                  if (on) { _selectedInterests.add(tag); }
                  else { _selectedInterests.remove(tag); }
                }),
              ),
            ),

            const SizedBox(height: 14),

            // ── 5. Hobbies ───────────────────────────────────────────────────
            _SectionCard(
              key: _hobbiesKey,
              title: 'Hobbies',
              subtitle: 'Pick at least 2 — great conversation starters',
              accent: AppColors.brandPurple,
              icon: Icons.emoji_emotions_rounded,
              highlight: _isHighlighted('hobbies'),
              child: _ChipPicker(
                selected: _selectedHobbies,
                options: const [
                  'Hiking', 'Cooking', 'Gaming', 'Yoga', 'Cycling',
                  'Painting', 'Dancing', 'Running', 'Surfing', 'Reading',
                  'Climbing', 'Swimming', 'Camping', 'Pottery',
                ],
                accent: AppColors.brandPurple,
                minCount: 2,
                onChanged: (tag, on) => setState(() {
                  if (on) { _selectedHobbies.add(tag); }
                  else { _selectedHobbies.remove(tag); }
                }),
              ),
            ),

            const SizedBox(height: 14),

            // ── 6. Dating Preferences ────────────────────────────────────────
            _SectionCard(
              key: _prefsKey,
              title: 'Dating Preferences',
              subtitle: 'Who you want to meet and your age range',
              accent: const Color(0xFFFFBE3C),
              icon: Icons.favorite_border_rounded,
              highlight: _isHighlighted('preferences'),
              child: _PreferencesSection(
                lookingFor: _lookingFor,
                interestedIn: _interestedIn,
                ageRange: _ageRange,
                onLookingForChanged: (v) => setState(() => _lookingFor = v),
                onInterestedInChanged: (v) =>
                    setState(() => _interestedIn = v),
                onAgeRangeChanged: (v) => setState(() => _ageRange = v),
              ),
            ),

            const SizedBox(height: 14),

            // ── 7. Profile Details ───────────────────────────────────────────
            _SectionCard(
              key: _detailsKey,
              title: 'Profile Details',
              subtitle: 'Extra info that helps people connect with you',
              accent: AppColors.brandPurple,
              icon: Icons.info_outline_rounded,
              highlight: _isHighlighted('details'),
              child: _DetailsSection(
                occupationCtrl: _occupationCtrl,
                heightCtrl: _heightCtrl,
              ),
            ),

            const SizedBox(height: 28),

            PillButton.primary(
              label: 'Save Changes',
              onTap: _save,
              width: double.infinity,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Focus banner ──────────────────────────────────────────────────────────────

/// Pink gradient banner shown when the user was routed here from Profile
/// Checklist to fix a specific missing item.
class _FocusBanner extends StatelessWidget {
  const _FocusBanner({required this.section});
  final String section;

  static const _map = <String, (String, String)>{
    'bio': (
      'Write your bio',
      'Scroll to the Bio section below and tell people who you are.',
    ),
    'interests': (
      'Add interests',
      'Scroll to Interests and pick at least 3 that fit you.',
    ),
    'hobbies': (
      'Add hobbies',
      'Scroll to Hobbies and pick at least 2 to spark conversations.',
    ),
    'preferences': (
      'Set your preferences',
      'Scroll to Dating Preferences and complete your settings.',
    ),
    'name_age': (
      'Confirm your identity',
      'Your name and age are at the top — review and update if needed.',
    ),
    'photos': (
      'Add photos',
      'Tap "Manage Photos" in the Photos & Media section below.',
    ),
    'photo_first': (
      'Add your first photo',
      'Tap "Manage Photos" in the Photos & Media section below.',
    ),
    'photo_three': (
      'Add more photos',
      'Tap "Manage Photos" below — profiles with 3+ photos get 4× more connections.',
    ),
    'video': (
      'Upload an intro video',
      'Tap "Upload Video" in the Photos & Media section below.',
    ),
    'details': (
      'Complete your details',
      'Scroll to Profile Details at the bottom and fill in your info.',
    ),
  };

  @override
  Widget build(BuildContext context) {
    final entry = _map[section];
    if (entry == null) return const SizedBox.shrink();
    final (title, body) = entry;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.brandPink.withValues(alpha: 0.13),
            AppColors.brandPurple.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: AppColors.brandPink.withValues(alpha: 0.32)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              color: AppColors.brandPink.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.arrow_downward_rounded,
                color: AppColors.brandPink, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.bodyS.copyWith(
                    color: AppColors.brandPink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Section card ──────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.icon,
    required this.child,
    this.highlight = false,
  });

  final String title;
  final String subtitle;
  final Color accent;
  final IconData icon;
  final Widget child;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color:
              highlight ? accent.withValues(alpha: 0.65) : AppColors.divider,
          width: highlight ? 1.5 : 1.0,
        ),
        boxShadow: highlight
            ? [
                BoxShadow(
                  color: accent.withValues(alpha: 0.14),
                  blurRadius: 22,
                  spreadRadius: 0,
                )
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Card header ────────────────────────────────────────────────
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accent, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.bodyS.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              if (highlight)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Update',
                    style: AppTextStyles.caption.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),

          // ── Divider ────────────────────────────────────────────────────
          Container(
            height: 1,
            color: AppColors.divider,
            margin: const EdgeInsets.symmetric(vertical: 16),
          ),

          child,
        ],
      ),
    );
  }
}

// ── Identity section ──────────────────────────────────────────────────────────

class _IdentitySection extends StatelessWidget {
  const _IdentitySection({
    required this.nameCtrl,
    required this.ageCtrl,
  });

  final TextEditingController nameCtrl;
  final TextEditingController ageCtrl;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 300) {
          return Column(
            children: [
              _LabeledField(label: 'First name', ctrl: nameCtrl),
              const SizedBox(height: 12),
              _LabeledField(
                label: 'Age',
                ctrl: ageCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: _LabeledField(label: 'First name', ctrl: nameCtrl),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: _LabeledField(
                label: 'Age',
                ctrl: ageCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Labeled text field ────────────────────────────────────────────────────────

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.ctrl,
    this.keyboardType,
    this.inputFormatters,
    this.hint,
  });

  final String label;
  final TextEditingController ctrl;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: AppTextStyles.caption.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 7),
        TextField(
          controller: ctrl,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          style: AppTextStyles.bodyS.copyWith(color: AppColors.textPrimary),
          cursorColor: AppColors.brandPink,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: AppTextStyles.bodyS.copyWith(color: AppColors.textMuted),
            filled: true,
            fillColor: AppColors.bgInput,
            counterText: '',
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.divider),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.divider),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: AppColors.brandPink, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Media section ─────────────────────────────────────────────────────────────

class _MediaSection extends StatelessWidget {
  const _MediaSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _MediaTile(
          icon: Icons.photo_library_rounded,
          color: AppColors.brandCyan,
          title: 'Manage Photos',
          subtitle: '0 of 6 photos — first photo is your profile photo',
          onTap: () => context.push(AppRoutes.gallery),
        ),
        const SizedBox(height: 10),
        _MediaTile(
          icon: Icons.videocam_rounded,
          color: AppColors.brandPurple,
          title: 'Upload Intro Video',
          subtitle: 'Max 30 seconds · boosts profile visibility',
          onTap: () => context.push(
            AppRoutes.gallery,
            extra: {'scrollToVideo': true},
          ),
        ),
      ],
    );
  }
}

class _MediaTile extends StatelessWidget {
  const _MediaTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTextStyles.bodyS.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.textMuted),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded,
                color: color.withValues(alpha: 0.70), size: 20),
          ],
        ),
      ),
    );
  }
}

// ── Bio field ─────────────────────────────────────────────────────────────────

class _BioField extends StatefulWidget {
  const _BioField({required this.ctrl});
  final TextEditingController ctrl;

  @override
  State<_BioField> createState() => _BioFieldState();
}

class _BioFieldState extends State<_BioField> {
  static const _maxChars = 150;
  late int _count;

  @override
  void initState() {
    super.initState();
    _count = widget.ctrl.text.length;
    widget.ctrl.addListener(_onChanged);
  }

  void _onChanged() {
    if (mounted) setState(() => _count = widget.ctrl.text.length);
  }

  @override
  void dispose() {
    widget.ctrl.removeListener(_onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nearLimit = _count >= _maxChars - 20;
    final counterColor =
        nearLimit ? AppColors.warning : AppColors.textMuted;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        TextField(
          controller: widget.ctrl,
          maxLines: 5,
          maxLength: _maxChars,
          style: AppTextStyles.bodyS.copyWith(
            color: AppColors.textPrimary,
            height: 1.65,
          ),
          cursorColor: AppColors.brandPink,
          decoration: InputDecoration(
            hintText:
                'I\'m an adventurous soul who loves exploring new places…',
            hintStyle: AppTextStyles.bodyS.copyWith(
              color: AppColors.textMuted,
              height: 1.65,
            ),
            filled: true,
            fillColor: AppColors.bgInput,
            counterText: '',
            contentPadding: const EdgeInsets.all(14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.divider),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.divider),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: AppColors.brandPink, width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 7),
        Text(
          '$_count / $_maxChars',
          style: AppTextStyles.caption.copyWith(
            color: counterColor,
            fontWeight: nearLimit ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

// ── Chip picker ───────────────────────────────────────────────────────────────

class _ChipPicker extends StatelessWidget {
  const _ChipPicker({
    required this.selected,
    required this.options,
    required this.accent,
    required this.minCount,
    required this.onChanged,
  });

  final Set<String> selected;
  final List<String> options;
  final Color accent;
  final int minCount;
  final void Function(String tag, bool on) onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Min count hint
        Row(
          children: [
            Icon(
              selected.length >= minCount
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 13,
              color: selected.length >= minCount
                  ? AppColors.success
                  : AppColors.textMuted,
            ),
            const SizedBox(width: 5),
            Text(
              '${selected.length} selected — minimum $minCount',
              style: AppTextStyles.caption.copyWith(
                color: selected.length >= minCount
                    ? AppColors.success
                    : AppColors.textMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((tag) {
            final isOn = selected.contains(tag);
            return GestureDetector(
              onTap: () => onChanged(tag, !isOn),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isOn
                      ? accent.withValues(alpha: 0.16)
                      : AppColors.bgElevated,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: isOn
                        ? accent.withValues(alpha: 0.65)
                        : AppColors.divider,
                    width: isOn ? 1.5 : 1.0,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isOn) ...[
                      Icon(Icons.check_rounded, size: 12, color: accent),
                      const SizedBox(width: 5),
                    ],
                    Text(
                      tag,
                      style: AppTextStyles.caption.copyWith(
                        color: isOn ? accent : AppColors.textSecondary,
                        fontWeight:
                            isOn ? FontWeight.w700 : FontWeight.w400,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ── Dating preferences section ────────────────────────────────────────────────

class _PreferencesSection extends StatelessWidget {
  const _PreferencesSection({
    required this.lookingFor,
    required this.interestedIn,
    required this.ageRange,
    required this.onLookingForChanged,
    required this.onInterestedInChanged,
    required this.onAgeRangeChanged,
  });

  final String lookingFor;
  final String interestedIn;
  final RangeValues ageRange;
  final ValueChanged<String> onLookingForChanged;
  final ValueChanged<String> onInterestedInChanged;
  final ValueChanged<RangeValues> onAgeRangeChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PrefRow(
          label: 'Looking for',
          value: lookingFor,
          options: const [
            'Meet someone tonight',
            'Casual dating',
            'Serious dating',
            'Open to anything',
            'Friends / social',
          ],
          onChanged: onLookingForChanged,
        ),
        const SizedBox(height: 10),
        _PrefRow(
          label: 'Interested in',
          value: interestedIn,
          options: const ['Men', 'Women', 'Everyone'],
          onChanged: onInterestedInChanged,
        ),
        const SizedBox(height: 18),
        // Age range
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Age range',
              style: AppTextStyles.bodyS
                  .copyWith(color: AppColors.textSecondary),
            ),
            Text(
              '${ageRange.start.round()} – ${ageRange.end.round()}',
              style: AppTextStyles.bodyS.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: AppColors.brandPink,
            inactiveTrackColor: AppColors.divider,
            thumbColor: AppColors.brandPink,
            overlayColor: AppColors.brandPink.withValues(alpha: 0.14),
            trackHeight: 3,
            rangeThumbShape:
                const RoundRangeSliderThumbShape(enabledThumbRadius: 10),
          ),
          child: RangeSlider(
            values: ageRange,
            min: 18,
            max: 60,
            divisions: 42,
            onChanged: onAgeRangeChanged,
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('18',
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.textMuted)),
            Text('60',
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.textMuted)),
          ],
        ),
      ],
    );
  }
}

class _PrefRow extends StatelessWidget {
  const _PrefRow({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 300;
        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              _PrefDropdown(
                value: value,
                options: options,
                label: label,
                onChanged: onChanged,
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(
                label,
                style: AppTextStyles.bodyS
                    .copyWith(color: AppColors.textSecondary),
              ),
            ),
            Expanded(
              flex: 3,
              child: _PrefDropdown(
                value: value,
                options: options,
                label: label,
                onChanged: onChanged,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PrefDropdown extends StatelessWidget {
  const _PrefDropdown({
    required this.value,
    required this.options,
    required this.label,
    required this.onChanged,
  });

  final String value;
  final List<String> options;
  final String label;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final result = await showModalBottomSheet<String>(
          context: context,
          backgroundColor: AppColors.bgSurface,
          shape: const RoundedRectangleBorder(
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(24)),
          ),
          builder: (_) => _PickerSheet(
            title: label,
            options: options,
            selected: value,
          ),
        );
        if (result != null) onChanged(result);
      },
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.bgInput,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                value,
                style: AppTextStyles.bodyS
                    .copyWith(color: AppColors.textPrimary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.expand_more_rounded,
                size: 18, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

// ── Picker bottom sheet ───────────────────────────────────────────────────────

class _PickerSheet extends StatelessWidget {
  const _PickerSheet({
    required this.title,
    required this.options,
    required this.selected,
  });

  final String title;
  final List<String> options;
  final String selected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(title, style: AppTextStyles.h3),
            ),
            const SizedBox(height: 10),
            ...options.map((opt) {
              final isSel = opt == selected;
              return ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 24),
                title: Text(
                  opt,
                  style: AppTextStyles.body.copyWith(
                    color: isSel
                        ? AppColors.brandPink
                        : AppColors.textPrimary,
                    fontWeight:
                        isSel ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
                trailing: isSel
                    ? const Icon(Icons.check_rounded,
                        color: AppColors.brandPink)
                    : null,
                onTap: () => Navigator.of(context).pop(opt),
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ── Profile details section ───────────────────────────────────────────────────

class _DetailsSection extends StatelessWidget {
  const _DetailsSection({
    required this.occupationCtrl,
    required this.heightCtrl,
  });

  final TextEditingController occupationCtrl;
  final TextEditingController heightCtrl;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _LabeledField(
          label: 'Occupation',
          ctrl: occupationCtrl,
          hint: 'e.g. Software Engineer',
        ),
        const SizedBox(height: 14),
        _LabeledField(
          label: 'Height',
          ctrl: heightCtrl,
          hint: "e.g. 5'10\"",
        ),
      ],
    );
  }
}
