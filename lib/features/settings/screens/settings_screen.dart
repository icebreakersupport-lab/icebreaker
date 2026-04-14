import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/gradient_scaffold.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text('Settings', style: AppTextStyles.h3),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.textSecondary, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 48),
          children: [
            // ── Account ───────────────────────────────────────────────────────
            _SectionHeader(title: 'Account'),
            _SettingsCard(
              items: [
                _SettingsRow(
                  icon: Icons.person_outline_rounded,
                  iconColor: AppColors.brandPink,
                  label: 'Edit Profile',
                  onTap: () => context.push(AppRoutes.editProfile),
                ),
                _SettingsRow(
                  icon: Icons.verified_outlined,
                  iconColor: AppColors.brandCyan,
                  label: 'Live Verification',
                  onTap: () => context.push(AppRoutes.liveVerify, extra: false),
                ),
                _SettingsRow(
                  icon: Icons.workspace_premium_outlined,
                  iconColor: AppColors.warning,
                  label: 'Subscription',
                  onTap: () => context.push(AppRoutes.shop),
                ),
                _SettingsRow(
                  icon: Icons.phone_outlined,
                  iconColor: AppColors.textSecondary,
                  label: 'Phone Number',
                  onTap: () {},
                  trailing: _ValueChip(label: _maskedPhone(context)),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ── Discovery Preferences ─────────────────────────────────────────
            _SectionHeader(title: 'Discovery'),
            _SettingsCard(
              items: [
                _SettingsRow(
                  icon: Icons.explore_outlined,
                  iconColor: AppColors.brandPurple,
                  label: 'Show Me',
                  onTap: () {},
                  trailing: const _ValueChip(label: 'Everyone'),
                ),
                _SettingsRow(
                  icon: Icons.cake_outlined,
                  iconColor: AppColors.brandPink,
                  label: 'Age Range',
                  onTap: () {},
                  trailing: const _ValueChip(label: '18 – 35'),
                ),
                _SettingsRow(
                  icon: Icons.location_on_outlined,
                  iconColor: AppColors.brandCyan,
                  label: 'Max Distance',
                  onTap: () {},
                  trailing: const _ValueChip(label: '30 m'),
                ),
                _SettingsToggleRow(
                  icon: Icons.visibility_outlined,
                  iconColor: AppColors.success,
                  label: 'Discoverable',
                  subtitle: 'Appear in Active Now',
                  initialValue: true,
                  onChanged: (_) {},
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ── Privacy & Safety ──────────────────────────────────────────────
            _SectionHeader(title: 'Privacy & Safety'),
            _SettingsCard(
              items: [
                _SettingsRow(
                  icon: Icons.block_rounded,
                  iconColor: AppColors.danger,
                  label: 'Blocked Users',
                  onTap: () {},
                ),
                _SettingsRow(
                  icon: Icons.report_gmailerrorred_outlined,
                  iconColor: AppColors.warning,
                  label: 'Reporting & Blocking',
                  onTap: () {},
                ),
                _SettingsToggleRow(
                  icon: Icons.photo_outlined,
                  iconColor: AppColors.textSecondary,
                  label: 'Show Photos to Matches Only',
                  initialValue: false,
                  onChanged: (_) {},
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ── Notifications ─────────────────────────────────────────────────
            _SectionHeader(title: 'Notifications'),
            _SettingsCard(
              items: [
                _SettingsToggleRow(
                  icon: Icons.notifications_outlined,
                  iconColor: AppColors.brandPink,
                  label: 'New Icebreakers',
                  initialValue: true,
                  onChanged: (_) {},
                ),
                _SettingsToggleRow(
                  icon: Icons.chat_bubble_outline_rounded,
                  iconColor: AppColors.brandCyan,
                  label: 'New Messages',
                  initialValue: true,
                  onChanged: (_) {},
                ),
                _SettingsToggleRow(
                  icon: Icons.favorite_border_rounded,
                  iconColor: AppColors.success,
                  label: 'Match Confirmed',
                  initialValue: true,
                  onChanged: (_) {},
                ),
                _SettingsToggleRow(
                  icon: Icons.bolt_outlined,
                  iconColor: AppColors.warning,
                  label: 'Session Starting',
                  initialValue: true,
                  onChanged: (_) {},
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ── Help & Legal ──────────────────────────────────────────────────
            _SectionHeader(title: 'Help & Legal'),
            _SettingsCard(
              items: [
                _SettingsRow(
                  icon: Icons.help_outline_rounded,
                  iconColor: AppColors.brandCyan,
                  label: 'Help Center',
                  onTap: () {},
                ),
                _SettingsRow(
                  icon: Icons.privacy_tip_outlined,
                  iconColor: AppColors.textSecondary,
                  label: 'Privacy Policy',
                  onTap: () {},
                ),
                _SettingsRow(
                  icon: Icons.description_outlined,
                  iconColor: AppColors.textSecondary,
                  label: 'Terms of Service',
                  onTap: () {},
                ),
                _SettingsRow(
                  icon: Icons.info_outline_rounded,
                  iconColor: AppColors.textMuted,
                  label: 'App Version',
                  onTap: null,
                  trailing: Text(
                    '1.0.0',
                    style: AppTextStyles.bodyS,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ── Danger zone ───────────────────────────────────────────────────
            _SettingsCard(
              items: [
                _SettingsRow(
                  icon: Icons.logout_rounded,
                  iconColor: AppColors.danger,
                  label: 'Log Out',
                  labelColor: AppColors.danger,
                  onTap: () => _confirmSignOut(context),
                ),
                _SettingsRow(
                  icon: Icons.delete_outline_rounded,
                  iconColor: AppColors.danger,
                  label: 'Delete Account',
                  labelColor: AppColors.danger,
                  onTap: () => _confirmDeleteAccount(context),
                  showChevron: false,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _maskedPhone(BuildContext context) {
    final phone = FirebaseAuth.instance.currentUser?.phoneNumber;
    if (phone == null || phone.isEmpty) return 'Not set';
    if (phone.length <= 4) return phone;
    return '••••${phone.substring(phone.length - 4)}';
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgElevated,
        title: Text('Log out?',
            style: AppTextStyles.h3.copyWith(color: AppColors.textPrimary)),
        content: Text(
          'You will need to sign back in to use Icebreaker.',
          style: AppTextStyles.bodyS,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child:
                Text('Cancel', style: AppTextStyles.body.copyWith(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child:
                Text('Log Out', style: AppTextStyles.body.copyWith(color: AppColors.danger)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    try {
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      debugPrint('[Settings] signOut failed: $e');
    }
    if (context.mounted) context.go(AppRoutes.signIn);
  }

  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgElevated,
        title: Text('Delete account?',
            style: AppTextStyles.h3.copyWith(color: AppColors.danger)),
        content: Text(
          'This permanently deletes your profile, matches, and messages. This cannot be undone.',
          style: AppTextStyles.bodyS,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel',
                style: AppTextStyles.body.copyWith(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Delete Forever',
                style: AppTextStyles.body.copyWith(color: AppColors.danger)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    try {
      await FirebaseAuth.instance.currentUser?.delete();
    } catch (e) {
      debugPrint('[Settings] delete account failed: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not delete account. Please sign in again and try.'),
          ),
        );
      }
      return;
    }
    if (context.mounted) context.go(AppRoutes.signIn);
  }
}

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(title.toUpperCase(), style: AppTextStyles.overline),
    );
  }
}

// ── Card container ────────────────────────────────────────────────────────────

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.items});
  final List<Widget> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            items[i],
            if (i < items.length - 1)
              const Divider(
                height: 1,
                indent: 62,
                endIndent: 0,
                color: AppColors.divider,
              ),
          ],
        ],
      ),
    );
  }
}

// ── Tappable row ──────────────────────────────────────────────────────────────

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    this.labelColor,
    this.onTap,
    this.trailing,
    this.showChevron = true,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final Color? labelColor;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            _IconBox(icon: icon, color: iconColor),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: AppTextStyles.body.copyWith(
                  fontWeight: FontWeight.w600,
                  color: labelColor ?? AppColors.textPrimary,
                ),
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing!,
            ],
            if (showChevron && onTap != null) ...[
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textMuted,
                size: 20,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Toggle row ────────────────────────────────────────────────────────────────

class _SettingsToggleRow extends StatefulWidget {
  const _SettingsToggleRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    this.subtitle,
    required this.initialValue,
    required this.onChanged,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String? subtitle;
  final bool initialValue;
  final ValueChanged<bool> onChanged;

  @override
  State<_SettingsToggleRow> createState() => _SettingsToggleRowState();
}

class _SettingsToggleRowState extends State<_SettingsToggleRow> {
  late bool _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initialValue;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          _IconBox(icon: widget.icon, color: widget.iconColor),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.label,
                  style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
                ),
                if (widget.subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(widget.subtitle!, style: AppTextStyles.caption),
                ],
              ],
            ),
          ),
          Switch(
            value: _value,
            onChanged: (v) {
              setState(() => _value = v);
              widget.onChanged(v);
            },
            activeThumbColor: AppColors.brandPink,
            trackColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return AppColors.brandPink.withValues(alpha: 0.3);
              }
              return AppColors.divider;
            }),
          ),
        ],
      ),
    );
  }
}

// ── Small icon box ────────────────────────────────────────────────────────────

class _IconBox extends StatelessWidget {
  const _IconBox({required this.icon, required this.color});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(9),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: color, size: 18),
    );
  }
}

// ── Value chip ────────────────────────────────────────────────────────────────

class _ValueChip extends StatelessWidget {
  const _ValueChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider),
      ),
      child: Text(label, style: AppTextStyles.caption),
    );
  }
}
