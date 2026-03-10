import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Icebreaker typography system.
///
/// Font: Plus Jakarta Sans — clean, modern, slightly geometric.
/// Matches the rounded-but-precise feel of the product mockups.
///
/// Scale (sp):
///   display  → 56  (countdown timers, "MATCHED!" hero text)
///   h1       → 32  (screen-level headings)
///   h2       → 24  (section headings, card names)
///   h3       → 20  (sub-section labels)
///   bodyL    → 18  (primary body, button labels)
///   body     → 16  (standard body)
///   bodyS    → 14  (secondary info)
///   caption  → 12  (timestamps, hints)
abstract final class AppTextStyles {
  // ─── Display ──────────────────────────────────────────────────────────────

  /// Countdown timer — "4:59". Large, bold, white, high contrast.
  static TextStyle display = const TextStyle(
    fontFamily: 'PlusJakartaSans',
    fontSize: 56,
    fontWeight: FontWeight.w800,
    color: AppColors.textPrimary,
    letterSpacing: -1.0,
    height: 1.0,
  );

  /// Hero label — "MATCHED!", "COLOR MATCH!". Bold uppercase.
  static TextStyle displayLabel = const TextStyle(
    fontFamily: 'PlusJakartaSans',
    fontSize: 32,
    fontWeight: FontWeight.w800,
    color: AppColors.textPrimary,
    letterSpacing: 1.5,
    height: 1.1,
  );

  // ─── Headings ─────────────────────────────────────────────────────────────

  static TextStyle h1 = const TextStyle(
    fontFamily: 'PlusJakartaSans',
    fontSize: 32,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -0.5,
    height: 1.2,
  );

  static TextStyle h2 = const TextStyle(
    fontFamily: 'PlusJakartaSans',
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -0.3,
    height: 1.3,
  );

  static TextStyle h3 = const TextStyle(
    fontFamily: 'PlusJakartaSans',
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    letterSpacing: -0.2,
    height: 1.3,
  );

  // ─── Body ─────────────────────────────────────────────────────────────────

  static TextStyle bodyL = const TextStyle(
    fontFamily: 'PlusJakartaSans',
    fontSize: 18,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
    height: 1.5,
  );

  static TextStyle body = const TextStyle(
    fontFamily: 'PlusJakartaSans',
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
    height: 1.5,
  );

  static TextStyle bodyS = const TextStyle(
    fontFamily: 'PlusJakartaSans',
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 1.4,
  );

  static TextStyle caption = const TextStyle(
    fontFamily: 'PlusJakartaSans',
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.textMuted,
    height: 1.4,
  );

  // ─── Button labels ────────────────────────────────────────────────────────

  static TextStyle buttonL = const TextStyle(
    fontFamily: 'PlusJakartaSans',
    fontSize: 18,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: 0.3,
    height: 1.0,
  );

  static TextStyle button = const TextStyle(
    fontFamily: 'PlusJakartaSans',
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: 0.2,
    height: 1.0,
  );

  static TextStyle buttonS = const TextStyle(
    fontFamily: 'PlusJakartaSans',
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    letterSpacing: 0.1,
    height: 1.0,
  );

  // ─── Overline / Labels ────────────────────────────────────────────────────

  /// Small allcaps label — section headers in Messages tab.
  static TextStyle overline = const TextStyle(
    fontFamily: 'PlusJakartaSans',
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: AppColors.textMuted,
    letterSpacing: 1.4,
    height: 1.0,
  );

  // ─── Convenience modifiers ────────────────────────────────────────────────

  /// Returns [style] with [color] override.
  static TextStyle withColor(TextStyle style, Color color) =>
      style.copyWith(color: color);
}
