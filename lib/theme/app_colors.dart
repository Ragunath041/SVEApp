import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // ── Primary Palette ─────────────────────────────
  static const Color primaryDeep = Color(0xFF1A1B4B);
  static const Color primary = Color(0xFF2D31FA);
  static const Color primaryLight = Color(0xFF5B5FFF);
  static const Color primarySoft = Color(0xFFE8E9FF);

  // ── Accent / Neon Blue Glow ─────────────────────
  static const Color accent = Color(0xFF00D4FF);
  static const Color accentGlow = Color(0x3300D4FF);
  static const Color accentSoft = Color(0xFFE0F7FF);

  // ── Background ──────────────────────────────────
  static const Color bgLight = Color(0xFFF7F8FC);
  static const Color bgCard = Color(0xFFFFFFFF);
  static const Color bgGlass = Color(0xB3FFFFFF); // 70% opacity white
  static const Color bgDark = Color(0xFF0D0E2B);
  static const Color bgGradientStart = Color(0xFF0D0E2B);
  static const Color bgGradientEnd = Color(0xFF1A1B4B);

  // ── Text ────────────────────────────────────────
  static const Color textPrimary = Color(0xFF1A1B2E);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textHint = Color(0xFF9CA3AF);
  static const Color textOnPrimary = Color(0xFFFFFFFF);
  static const Color textOnDark = Color(0xFFE5E7EB);

  // ── Status ──────────────────────────────────────
  static const Color success = Color(0xFF10B981);
  static const Color successSoft = Color(0xFFD1FAE5);
  static const Color successGlow = Color(0x3310B981);
  static const Color error = Color(0xFFEF4444);
  static const Color errorSoft = Color(0xFFFEE2E2);
  static const Color warning = Color(0xFFF59E0B);
  static const Color warningSoft = Color(0xFFFEF3C7);

  // ── Borders & Dividers ──────────────────────────
  static const Color border = Color(0xFFE5E7EB);
  static const Color borderLight = Color(0xFFF3F4F6);
  static const Color divider = Color(0xFFF3F4F6);

  // ── Shadows ─────────────────────────────────────
  static const Color shadow = Color(0x0D000000);
  static const Color shadowMedium = Color(0x1A000000);

  // ── Gradients ───────────────────────────────────
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, Color(0xFF6366F1)],
  );

  static const LinearGradient darkGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [bgGradientStart, bgGradientEnd],
  );

  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accent, Color(0xFF818CF8)],
  );

  static const LinearGradient glassGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x80FFFFFF), Color(0x40FFFFFF)],
  );

  static const LinearGradient successGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF10B981), Color(0xFF34D399)],
  );

  static const LinearGradient errorGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFEF4444), Color(0xFFF87171)],
  );
}
