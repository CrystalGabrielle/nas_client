import 'package:flutter/material.dart';

@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.paper,
    required this.ink,
    required this.muted,
    required this.card,
    required this.line,
    required this.accent,
    required this.accentInk,
    required this.accentSoft,
    required this.samba,
    required this.sambaSoft,
    required this.ftp,
    required this.ftpSoft,
    required this.danger,
    required this.ok,
  });

  final Color paper;
  final Color ink;
  final Color muted;
  final Color card;
  final Color line;
  final Color accent;
  final Color accentInk;
  final Color accentSoft;
  final Color samba;
  final Color sambaSoft;
  final Color ftp;
  final Color ftpSoft;
  final Color danger;
  final Color ok;

  static AppPalette of(BuildContext context) {
    return Theme.of(context).extension<AppPalette>()!;
  }

  static const light = AppPalette(
    paper: Color(0xFFF3EEE6),
    ink: Color(0xFF1C1714),
    muted: Color(0xFF7C736A),
    card: Color(0xFFFFFCF8),
    line: Color(0xFFE6DCD0),
    accent: Color(0xFFD4531E),
    accentInk: Color(0xFFFFFFFF),
    accentSoft: Color(0xFFF8E3D6),
    samba: Color(0xFF1B6B4A),
    sambaSoft: Color(0xFFE3F2EA),
    ftp: Color(0xFF2C4E96),
    ftpSoft: Color(0xFFE4EAF8),
    danger: Color(0xFFB42318),
    ok: Color(0xFF1B7A45),
  );

  static const dark = AppPalette(
    paper: Color(0xFF141210),
    ink: Color(0xFFF6EFE6),
    muted: Color(0xFFB3A79C),
    card: Color(0xFF221C18),
    line: Color(0xFF3A322C),
    accent: Color(0xFFFF8A5B),
    accentInk: Color(0xFF2A1208),
    accentSoft: Color(0xFF3A241C),
    samba: Color(0xFF7DDBA8),
    sambaSoft: Color(0xFF1A2E24),
    ftp: Color(0xFF9BB6F5),
    ftpSoft: Color(0xFF1C2436),
    danger: Color(0xFFFFB4AB),
    ok: Color(0xFF8EE0AE),
  );

  @override
  AppPalette copyWith({
    Color? paper,
    Color? ink,
    Color? muted,
    Color? card,
    Color? line,
    Color? accent,
    Color? accentInk,
    Color? accentSoft,
    Color? samba,
    Color? sambaSoft,
    Color? ftp,
    Color? ftpSoft,
    Color? danger,
    Color? ok,
  }) {
    return AppPalette(
      paper: paper ?? this.paper,
      ink: ink ?? this.ink,
      muted: muted ?? this.muted,
      card: card ?? this.card,
      line: line ?? this.line,
      accent: accent ?? this.accent,
      accentInk: accentInk ?? this.accentInk,
      accentSoft: accentSoft ?? this.accentSoft,
      samba: samba ?? this.samba,
      sambaSoft: sambaSoft ?? this.sambaSoft,
      ftp: ftp ?? this.ftp,
      ftpSoft: ftpSoft ?? this.ftpSoft,
      danger: danger ?? this.danger,
      ok: ok ?? this.ok,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      paper: Color.lerp(paper, other.paper, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      card: Color.lerp(card, other.card, t)!,
      line: Color.lerp(line, other.line, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentInk: Color.lerp(accentInk, other.accentInk, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      samba: Color.lerp(samba, other.samba, t)!,
      sambaSoft: Color.lerp(sambaSoft, other.sambaSoft, t)!,
      ftp: Color.lerp(ftp, other.ftp, t)!,
      ftpSoft: Color.lerp(ftpSoft, other.ftpSoft, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      ok: Color.lerp(ok, other.ok, t)!,
    );
  }
}

class AppTheme {
  static ThemeData light() => _build(Brightness.light, AppPalette.light);

  static ThemeData dark() => _build(Brightness.dark, AppPalette.dark);

  static ThemeData _build(Brightness brightness, AppPalette palette) {
    final scheme = ColorScheme.fromSeed(
      seedColor: palette.accent,
      brightness: brightness,
      surface: palette.card,
      primary: palette.accent,
      onPrimary: palette.accentInk,
    );
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: palette.paper,
      splashFactory: InkRipple.splashFactory,
      extensions: [palette],
    );
    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: palette.paper,
        foregroundColor: palette.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: palette.card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: palette.ink,
        contentTextStyle: TextStyle(color: palette.paper),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: brightness == Brightness.light
            ? const Color(0xFFF7F1EA)
            : const Color(0xFF2A241F),
        hintStyle: TextStyle(color: palette.muted),
        labelStyle: TextStyle(color: palette.muted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: palette.accent, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: palette.accent,
          foregroundColor: palette.accentInk,
          minimumSize: const Size(64, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: palette.ink),
      ),
      dividerColor: palette.line,
      textTheme: base.textTheme.apply(
        bodyColor: palette.ink,
        displayColor: palette.ink,
      ),
    );
  }
}
