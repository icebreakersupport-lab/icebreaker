import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

/// Icebreaker pill-shaped CTA button.
///
/// Variants:
///   [PillButton.primary]   — hot-pink/magenta gradient (GO LIVE, primary CTAs)
///   [PillButton.cyan]      — solid neon cyan (Send, secondary CTAs)
///   [PillButton.success]   — solid green (YES / confirm)
///   [PillButton.danger]    — solid red-pink (NO / destructive)
///   [PillButton.outlined]  — transparent with brand border
class PillButton extends StatelessWidget {
  const PillButton._({
    required this.label,
    required this.onTap,
    required this.backgroundColor,
    required this.textColor,
    this.gradient,
    this.icon,
    this.isLoading = false,
    this.enabled = true,
    this.width,
    this.height = 56,
    super.key,
  });

  // ─── Factories ────────────────────────────────────────────────────────────

  factory PillButton.primary({
    Key? key,
    required String label,
    required VoidCallback? onTap,
    IconData? icon,
    bool isLoading = false,
    double? width,
    double height = 56,
  }) =>
      PillButton._(
        key: key,
        label: label,
        onTap: onTap,
        backgroundColor: AppColors.brandPink,
        textColor: AppColors.textPrimary,
        gradient: AppColors.brandGradient,
        icon: icon,
        isLoading: isLoading,
        enabled: onTap != null,
        width: width,
        height: height,
      );

  factory PillButton.cyan({
    Key? key,
    required String label,
    required VoidCallback? onTap,
    IconData? icon,
    bool isLoading = false,
    double? width,
    double height = 52,
  }) =>
      PillButton._(
        key: key,
        label: label,
        onTap: onTap,
        backgroundColor: AppColors.brandCyan,
        textColor: AppColors.textInverse,
        icon: icon,
        isLoading: isLoading,
        enabled: onTap != null,
        width: width,
        height: height,
      );

  factory PillButton.success({
    Key? key,
    required String label,
    required VoidCallback? onTap,
    IconData? icon,
    bool isLoading = false,
    double? width,
    double height = 64,
  }) =>
      PillButton._(
        key: key,
        label: label,
        onTap: onTap,
        backgroundColor: AppColors.success,
        textColor: AppColors.textInverse,
        icon: icon,
        isLoading: isLoading,
        enabled: onTap != null,
        width: width,
        height: height,
      );

  factory PillButton.danger({
    Key? key,
    required String label,
    required VoidCallback? onTap,
    IconData? icon,
    bool isLoading = false,
    double? width,
    double height = 64,
  }) =>
      PillButton._(
        key: key,
        label: label,
        onTap: onTap,
        backgroundColor: AppColors.danger,
        textColor: AppColors.textPrimary,
        icon: icon,
        isLoading: isLoading,
        enabled: onTap != null,
        width: width,
        height: height,
      );

  factory PillButton.outlined({
    Key? key,
    required String label,
    required VoidCallback? onTap,
    IconData? icon,
    double? width,
    double height = 52,
  }) =>
      PillButton._(
        key: key,
        label: label,
        onTap: onTap,
        backgroundColor: Colors.transparent,
        textColor: AppColors.textPrimary,
        icon: icon,
        enabled: onTap != null,
        width: width,
        height: height,
      );

  // ─── Fields ───────────────────────────────────────────────────────────────

  final String label;
  final VoidCallback? onTap;
  final Color backgroundColor;
  final Color textColor;
  final Gradient? gradient;
  final IconData? icon;
  final bool isLoading;
  final bool enabled;
  final double? width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final isOutlined = backgroundColor == Colors.transparent;

    return GestureDetector(
      onTap: enabled && !isLoading ? onTap : null,
      child: AnimatedOpacity(
        opacity: enabled ? 1.0 : 0.45,
        duration: const Duration(milliseconds: 150),
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(height / 2),
            gradient: !isOutlined ? gradient : null,
            color: gradient == null ? backgroundColor : null,
            border: isOutlined
                ? Border.all(color: AppColors.brandPink, width: 1.5)
                : null,
          ),
          alignment: Alignment.center,
          child: isLoading
              ? SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: textColor,
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, color: textColor, size: 20),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      label,
                      style: AppTextStyles.buttonL.copyWith(color: textColor),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
