import 'package:flutter/material.dart';

/// NESF brand palette, matching the green used on foundation letterhead so the
/// app and the documents it issues read as one identity.
class NesfColors {
  static const green = Color(0xFF1A4731);
  static const greenDark = Color(0xFF10301F);
  static const greenLight = Color(0xFFEEF3F0);
  static const accent = Color(0xFFFFC107); // NE Sports brand yellow
  static const ink = Color(0xFF111111);
  static const body = Color(0xFF3C4A43);
  static const muted = Color(0xFF6B7A72);
  static const line = Color(0xFFE2E8E5);
  static const surface = Color(0xFFF7F9F8);

  static const approved = Color(0xFF1A7F37);
  static const approvedBg = Color(0xFFE6F4EA);
  static const pending = Color(0xFF8A5300);
  static const pendingBg = Color(0xFFFFF4E5);
  static const rejected = Color(0xFFB3261E);
  static const rejectedBg = Color(0xFFFDECEA);
  static const info = Color(0xFF1B5E9C);
  static const infoBg = Color(0xFFE8F1FB);
}

ThemeData buildNesfTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: NesfColors.green,
    primary: NesfColors.green,
    surface: Colors.white,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: NesfColors.surface,
    fontFamily: 'Roboto',
    appBarTheme: const AppBarTheme(
      backgroundColor: NesfColors.green,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: NesfColors.line),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: NesfColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: NesfColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: NesfColors.green, width: 1.6),
      ),
      labelStyle: const TextStyle(color: NesfColors.muted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: NesfColors.green,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: NesfColors.green,
        minimumSize: const Size.fromHeight(48),
        side: const BorderSide(color: NesfColors.green),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    chipTheme: const ChipThemeData(
      backgroundColor: NesfColors.greenLight,
      labelStyle: TextStyle(fontSize: 12, color: NesfColors.green),
      side: BorderSide.none,
    ),
    dividerTheme: const DividerThemeData(color: NesfColors.line, thickness: 1),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );
}

/// Maps a workflow status to its chip colours, used everywhere a submission's
/// state is shown.
({Color fg, Color bg, String label}) statusStyle(String? status) {
  switch (status) {
    case 'approved':
      return (fg: NesfColors.approved, bg: NesfColors.approvedBg, label: 'Approved');
    case 'paid':
      return (fg: NesfColors.approved, bg: NesfColors.approvedBg, label: 'Paid');
    case 'reviewed':
      return (fg: NesfColors.pending, bg: NesfColors.pendingBg, label: 'Recommended');
    case 'submitted':
      return (fg: NesfColors.info, bg: NesfColors.infoBg, label: 'Awaiting review');
    case 'rejected':
      return (fg: NesfColors.rejected, bg: NesfColors.rejectedBg, label: 'Rejected');
    case 'cancelled':
      return (fg: NesfColors.muted, bg: NesfColors.greenLight, label: 'Cancelled');
    case 'draft':
      return (fg: NesfColors.muted, bg: NesfColors.greenLight, label: 'Draft');
    default:
      return (fg: NesfColors.muted, bg: NesfColors.greenLight, label: status ?? '—');
  }
}
