import 'package:flutter/material.dart';

/// Icebreaker design system — color tokens.
///
/// Sourced from the visual mockups in the product deck (slides 5–12).
/// Dark-mode only. All backgrounds are very dark purple-black.
/// The brand uses a hot-pink → electric-purple gradient with a cyan lightning accent.
abstract final class AppColors {
  // ─── Backgrounds ──────────────────────────────────────────────────────────

  /// True base background — deepest level (scaffold, nav bar).
  static const Color bgBase = Color(0xFF090011);

  /// Surface level — cards, bottom sheets.
  static const Color bgSurface = Color(0xFF130020);

  /// Elevated level — dialogs, popovers.
  static const Color bgElevated = Color(0xFF1C002E);

  /// Input fields, text areas.
  static const Color bgInput = Color(0xFF1A0028);

  // ─── Brand ────────────────────────────────────────────────────────────────

  /// Hot pink / magenta — left/warm end of the brand gradient.
  /// Used for: GO LIVE button, heart left half, primary CTAs.
  static const Color brandPink = Color(0xFFFF1F6E);

  /// Electric purple-blue — right/cool end of the brand gradient.
  /// Used for: heart right half, secondary accents.
  static const Color brandPurple = Color(0xFF7B2FF7);

  /// Neon cyan — lightning bolt colour, secondary CTAs (Send button).
  static const Color brandCyan = Color(0xFF00E5FF);

  // ─── Gradient helpers ─────────────────────────────────────────────────────

  /// Full brand gradient (pink → purple), left to right.
  static const Gradient brandGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [brandPink, brandPurple],
  );

  /// Diagonal brand gradient for backgrounds / cards.
  static const Gradient brandGradientDiagonal = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [brandPink, brandPurple],
  );

  /// Radial glow used behind the logo.
  static const Gradient logoGlow = RadialGradient(
    center: Alignment.center,
    radius: 0.9,
    colors: [Color(0x30FF1F6E), Color(0x00000000)],
  );

  // ─── Text ─────────────────────────────────────────────────────────────────

  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFB0A4C0);
  static const Color textMuted = Color(0xFF6A5F7A);
  static const Color textInverse = Color(0xFF090011);

  // ─── Semantic ─────────────────────────────────────────────────────────────

  /// "YES" / connection confirmed / chat unlocked.
  static const Color success = Color(0xFF4CD98A);

  /// "NO" / danger / destructive.
  static const Color danger = Color(0xFFFF3B5C);

  /// Countdown warning threshold (≤ 30 s remaining).
  static const Color warning = Color(0xFFFFBE3C);

  // ─── UI chrome ────────────────────────────────────────────────────────────

  /// Subtle divider / separator line.
  static const Color divider = Color(0xFF2A1040);

  /// Nav bar border (top edge).
  static const Color navBorder = Color(0xFF1E0030);

  /// Semi-transparent photo overlay — bottom scrim on carousel cards.
  static const Color photoScrim = Color(0xCC000000);

  /// Semi-transparent photo overlay — lighter top scrim.
  static const Color photoScrimLight = Color(0x66000000);
}
