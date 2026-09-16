import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ── Design Tokens ────────────────────────────────────────────
class DrivoColors {
  static const primary    = Color(0xFF6C63FF);
  static const primaryDark= Color(0xFF5A52D5);
  static const accent     = Color(0xFF00D4AA);
  static const danger     = Color(0xFFFF4757);
  static const warning    = Color(0xFFFFA502);
  static const success    = Color(0xFF2ED573);
  static const bgDark     = Color(0xFF0F0F1A);
  static const bgCard     = Color(0xFF16162A);
  static const textPrimary= Color(0xFFF0F0FF);
  static const textSecondary=Color(0xFF8888AA);
  static const textMuted  = Color(0xFF5555AA);
  static const border     = Color(0x14FFFFFF);
}

class DrivoTheme {
  static ThemeData get theme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: DrivoColors.bgDark,
    colorScheme: const ColorScheme.dark(
      primary: DrivoColors.primary,
      secondary: DrivoColors.accent,
      surface: DrivoColors.bgCard,
      error: DrivoColors.danger,
    ),
    textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
    appBarTheme: const AppBarTheme(
      backgroundColor: DrivoColors.bgDark,
      foregroundColor: DrivoColors.textPrimary,
      elevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0x0AFFFFFF),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: DrivoColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: DrivoColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: DrivoColors.primary, width: 2),
      ),
      labelStyle: const TextStyle(color: DrivoColors.textSecondary),
      hintStyle: const TextStyle(color: DrivoColors.textMuted),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: DrivoColors.primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        minimumSize: const Size(double.infinity, 52),
        textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    cardTheme: CardThemeData(
      color: DrivoColors.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: DrivoColors.border),
      ),
      elevation: 0,
    ),
  );
}

// ── Reusable Widgets ─────────────────────────────────────────

/// Gradient-outlined card
class DrivoCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  const DrivoCard({super.key, required this.child, this.padding});

  @override
  Widget build(BuildContext context) => Container(
    padding: padding ?? const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: DrivoColors.bgCard,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: DrivoColors.border),
    ),
    child: child,
  );
}

/// Primary gradient button
class DrivoPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool loading;
  final IconData? icon;
  const DrivoPrimaryButton({super.key, required this.label, this.onTap, this.loading = false, this.icon});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: loading ? null : onTap,
    borderRadius: BorderRadius.circular(14),
    child: Container(
      height: 54,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [DrivoColors.primary, DrivoColors.primaryDark],
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: DrivoColors.primary.withOpacity(0.35), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Center(
        child: loading
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[Icon(icon, color: Colors.white, size: 18), const SizedBox(width: 8)],
                  Text(label, style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                ],
              ),
      ),
    ),
  );
}

/// Status badge
class DrivoBadge extends StatelessWidget {
  final String label;
  const DrivoBadge(this.label, {super.key});

  Color get _color => switch(label.toLowerCase()) {
    'approved' || 'online'  => DrivoColors.success,
    'pending'               => DrivoColors.warning,
    'rejected' || 'locked'  => DrivoColors.danger,
    'busy'                  => DrivoColors.accent,
    _                       => DrivoColors.textSecondary,
  };

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: _color.withOpacity(0.15),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: _color.withOpacity(0.35)),
    ),
    child: Text(label, style: TextStyle(color: _color, fontSize: 11, fontWeight: FontWeight.w600)),
  );
}

/// Section header
class SectionHeader extends StatelessWidget {
  final String title;
  const SectionHeader(this.title, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(title, style: GoogleFonts.inter(
      color: DrivoColors.textMuted, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.2,
    )),
  );
}
