import 'package:flutter/material.dart';

/// ViaX's interface system: an evidence docket built from warm paper, dark
/// ink, decisive cobalt actions, and restrained proof marks.
abstract final class Bold {
  static const brand = Color(0xFF3157D5);
  static const brandDeep = Color(0xFF17213A);
  static const brandLift = Color(0xFFAFC1FF);
  static const coral = Color(0xFFEF5B4C);
  static const yellow = Color(0xFFE8B44C);

  // Status colors (preserved semantic meaning)
  static const danger = Color(0xFFBC3D37);
  static const warn = Color(0xFF8A5B00);
  static const good = Color(0xFF14715B);

  static const dangerLift = Color(0xFFFF9C92);
  static const warnLift = Color(0xFFF4CD68);
  static const goodLift = Color(0xFF71D6B7);

  // Light surfaces & typography
  static const inkLight = Color(0xFF171A21);
  static const slateLight = Color(0xFF636B78);
  static const lineLight = Color(0xFFD9DCE4);
  static const canvasLight = Color(0xFFF7F4ED);
  static const cardLight = Color(0xFFFFFEFB);

  // Dark surfaces & typography
  static const inkDark = Color(0xFFF3F5F8);
  static const slateDark = Color(0xFFAEB5C2);
  static const lineDark = Color(0xFF303746);
  static const canvasDark = Color(0xFF0E1118);
  static const cardDark = Color(0xFF171B24);

  // Dynamic getters — automatically adapt to active theme!
  static Color get ink => isDark ? inkDark : inkLight;
  static Color get slate => isDark ? slateDark : slateLight;
  static Color get line => isDark ? lineDark : lineLight;
  static Color get canvas => isDark ? canvasDark : canvasLight;
  static Color get card => isDark ? cardDark : cardLight;

  /// Reactive theme notifier: System, Light, or Dark.
  static final themeNotifier = ValueNotifier<ThemeMode>(ThemeMode.system);

  /// Active dark mode state, updated at app root on rebuilds.
  static bool isDark = false;

  /// Dynamic contextual color helpers
  static Color inkOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? inkDark : inkLight;
  static Color slateOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? slateDark : slateLight;
  static Color cardOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? cardDark : cardLight;
  static Color canvasOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? canvasDark
          : canvasLight;
  static Color lineOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? lineDark : lineLight;

  /// Fill for a status surface.
  static Color wash(Color role, [bool? dark]) {
    final useDark = dark ?? isDark;
    return useDark
        ? role.withValues(alpha: 0.18)
        : switch (role) {
            danger => const Color(0xFFFEE2E2),
            warn => const Color(0xFFFEF3C7),
            good => const Color(0xFFDCFCE7),
            _ => const Color(0xFFE7ECFF),
          };
  }

  /// Readiness bands. The words exist so colour is never the only signal.
  static (String, Color) band(double pct) => switch (pct) {
        >= 75 => ('On track', good),
        >= 50 => ('Some risk', warn),
        _ => ('At risk', danger),
      };

  static (String, Color) mastery(double? m) => switch (m) {
        null => ('Not examined', slate),
        >= 75 => ('Strong', good),
        >= 55 => ('Minor gap', brand),
        >= 35 => ('Needs work', warn),
        _ => ('Critical', danger),
      };
}

ThemeData boldTheme() => Bold.isDark ? boldDarkTheme() : boldLightTheme();

ThemeData boldLightTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Bold.brand,
    brightness: Brightness.light,
  ).copyWith(
    primary: Bold.brand,
    onPrimary: Colors.white,
    surface: Bold.cardLight,
    onSurface: Bold.inkLight,
    secondary: Bold.coral,
    outline: Bold.lineLight,
    surfaceContainerHighest: const Color(0xFFEDEAE3),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: scheme,
    scaffoldBackgroundColor: Bold.canvasLight,
    cardColor: Bold.cardLight,
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: const AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Bold.canvasLight,
      foregroundColor: Bold.inkLight,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        color: Bold.inkLight,
        fontSize: 21,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.45,
      ),
    ),
    cardTheme: CardThemeData(
      color: Bold.cardLight,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(18)),
        side: BorderSide(color: Bold.lineLight),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Bold.cardLight,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Bold.lineLight),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Bold.lineLight),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Bold.brand, width: 1.5),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: Bold.lineLight,
      thickness: 1,
      space: 1,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Bold.brand,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(56),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Bold.brand,
        minimumSize: const Size.fromHeight(52),
        side: const BorderSide(color: Bold.lineLight, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Bold.inkLight,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12))),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      backgroundColor: Bold.cardLight,
      indicatorColor: const Color(0xFFE1E7FF),
      surfaceTintColor: Colors.transparent,
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: Bold.brandDeep);
        }
        return const IconThemeData(color: Bold.slateLight);
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700, color: Bold.brandDeep);
        }
        return const TextStyle(
            fontSize: 12, fontWeight: FontWeight.w500, color: Bold.slateLight);
      }),
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: Bold.cardLight,
      indicatorColor: Color(0xFFE1E7FF),
      selectedIconTheme: IconThemeData(color: Bold.brandDeep),
      unselectedIconTheme: IconThemeData(color: Bold.slateLight),
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: Bold.brand,
      selectionColor: Color(0x333157D5),
      selectionHandleColor: Bold.brand,
    ),
  );
}

ThemeData boldDarkTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Bold.brandLift,
    brightness: Brightness.dark,
  ).copyWith(
    primary: Bold.brandLift,
    onPrimary: Colors.white,
    surface: Bold.cardDark,
    onSurface: Bold.inkDark,
    secondary: Bold.coral,
    outline: Bold.lineDark,
    surfaceContainerHighest: const Color(0xFF222835),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: Bold.canvasDark,
    cardColor: Bold.cardDark,
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: const AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Bold.canvasDark,
      foregroundColor: Bold.inkDark,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        color: Bold.inkDark,
        fontSize: 21,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.45,
      ),
    ),
    cardTheme: const CardThemeData(
      color: Bold.cardDark,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(18)),
        side: BorderSide(color: Bold.lineDark),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Bold.cardDark,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Bold.lineDark),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Bold.lineDark),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Bold.brandLift, width: 1.5),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: Bold.lineDark,
      thickness: 1,
      space: 1,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Bold.brandLift,
        foregroundColor: Bold.brandDeep,
        minimumSize: const Size.fromHeight(56),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Bold.brandLift,
        minimumSize: const Size.fromHeight(52),
        side: const BorderSide(color: Bold.lineDark, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Bold.cardDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      backgroundColor: Bold.cardDark,
      indicatorColor: const Color(0xFF273664),
      surfaceTintColor: Colors.transparent,
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: Bold.brandLift);
        }
        return const IconThemeData(color: Bold.slateDark);
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700, color: Bold.brandLift);
        }
        return const TextStyle(
            fontSize: 12, fontWeight: FontWeight.w500, color: Bold.slateDark);
      }),
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: Bold.cardDark,
      indicatorColor: Color(0xFF273664),
      selectedIconTheme: IconThemeData(color: Bold.brandLift),
      unselectedIconTheme: IconThemeData(color: Bold.slateDark),
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: Bold.brandLift,
      selectionColor: Color(0x55AFC1FF),
      selectionHandleColor: Bold.brandLift,
    ),
  );
}

/// Type scale. Sizes and weights only — the face is the device's.
abstract final class T {
  static const hero = TextStyle(
    fontSize: 52,
    height: 1.0,
    fontWeight: FontWeight.w800,
    letterSpacing: -2,
    color: Colors.white,
  );
  static const display = TextStyle(
      fontSize: 28,
      height: 1.08,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.7);
  static const title = TextStyle(
      fontSize: 21,
      height: 1.25,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.3);
  static const heading =
      TextStyle(fontSize: 17, height: 1.3, fontWeight: FontWeight.w700);
  static const body =
      TextStyle(fontSize: 15.5, height: 1.45, fontWeight: FontWeight.w500);
  static const bodyQuiet =
      TextStyle(fontSize: 14, height: 1.45, fontWeight: FontWeight.w500);
  static const small =
      TextStyle(fontSize: 12.5, height: 1.35, fontWeight: FontWeight.w600);
  static const stat = TextStyle(
    fontSize: 26,
    height: 1,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.8,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}

/// The generated ViaX crossed-path mark. Keep the raster isolated here so the
/// same optical size and corner treatment are used throughout the product.
class ViaXMark extends StatelessWidget {
  const ViaXMark({super.key, this.size = 40, this.radius});

  final double size;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius ?? size * 0.25),
      child: Image.asset(
        'assets/viax_icon.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        semanticLabel: 'ViaX',
      ),
    );
  }
}
