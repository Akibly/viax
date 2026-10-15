import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'tokens.dart';

/// Surface and text colours for one theme.
///
/// A [ThemeExtension] rather than abuse of [ColorScheme]: VivaX has named
/// surfaces (card, hairline, muted, examiner chrome) that do not map onto
/// Material's semantic slots, and forcing them in produces widgets that read
/// `colorScheme.surfaceContainerHighest` and mean "card". This keeps the
/// vocabulary the design guide actually uses.
@immutable
class VxColors extends ThemeExtension<VxColors> {
  const VxColors({
    required this.surface,
    required this.card,
    required this.cardRaised,
    required this.border,
    required this.hairline,
    required this.text,
    required this.muted,
    required this.inverseText,
    required this.examinerChrome,
    required this.isDark,
  });

  final Color surface;
  final Color card;

  /// One step above [card], for a surface that sits on a card — the answer
  /// field inside a question card, a chip inside a banner. Elevation by
  /// value rather than by shadow, which is what keeps dark mode from turning
  /// into a soup of drop shadows.
  final Color cardRaised;

  final Color border;

  /// Dividers only. Deliberately weaker than [border] so a list of rows does
  /// not read as a stack of boxes.
  final Color hairline;

  final Color text;
  final Color muted;
  final Color inverseText;

  /// The deep navy used behind the readiness hero and in exam mode.
  final Color examinerChrome;

  final bool isDark;

  static const light = VxColors(
    surface: VxPalette.surfaceLight,
    card: VxPalette.cardLight,
    cardRaised: Color(0xFFF1F5F9),
    border: VxPalette.borderLight,
    hairline: Color(0xFFEEF2F7),
    text: VxPalette.textLight,
    muted: VxPalette.mutedLight,
    inverseText: Color(0xFFFFFFFF),
    examinerChrome: VxPalette.navy,
    isDark: false,
  );

  static const dark = VxColors(
    surface: VxPalette.surfaceDark,
    card: VxPalette.cardDark,
    cardRaised: Color(0xFF1C2A47),
    border: VxPalette.borderDark,
    hairline: Color(0xFF1D2740),
    text: VxPalette.textDark,
    muted: VxPalette.mutedDark,
    inverseText: Color(0xFF0B1220),
    examinerChrome: Color(0xFF16213A),
    isDark: true,
  );

  /// The correct colour for [hue] used as text on this theme's card surface.
  ///
  /// This is the API that makes A11Y-01 unrepeatable: callers ask for "amber
  /// text" and get the variant that actually passes on the surface they are
  /// drawing on, instead of picking a hex and hoping.
  Color textOn(VxHue hue) => isDark ? hue.tint : hue.strong;

  /// The correct fill for [hue] when white text sits on top of it.
  Color fillUnderWhite(VxHue hue) => hue.strong;

  /// The correct chip background for [hue].
  Color wash(VxHue hue) => isDark ? hue.washDark : hue.wash;

  /// The accent for interactive text — back buttons, links, selected state.
  /// One accent, resolved to the variant that passes AA on this surface, so
  /// screens never reach for a raw hue and guess.
  Color get accent => textOn(VxPalette.focus);

  /// Disclosure chevrons and other pure affordances. Deliberately below the
  /// muted ramp: these are not content and should not compete with it.
  Color get faint => isDark ? const Color(0xFF5B6880) : const Color(0xFFB6C0CE);

  @override
  VxColors copyWith({
    Color? surface,
    Color? card,
    Color? cardRaised,
    Color? border,
    Color? hairline,
    Color? text,
    Color? muted,
    Color? inverseText,
    Color? examinerChrome,
    bool? isDark,
  }) {
    return VxColors(
      surface: surface ?? this.surface,
      card: card ?? this.card,
      cardRaised: cardRaised ?? this.cardRaised,
      border: border ?? this.border,
      hairline: hairline ?? this.hairline,
      text: text ?? this.text,
      muted: muted ?? this.muted,
      inverseText: inverseText ?? this.inverseText,
      examinerChrome: examinerChrome ?? this.examinerChrome,
      isDark: isDark ?? this.isDark,
    );
  }

  @override
  VxColors lerp(covariant VxColors? other, double t) {
    if (other == null) return this;
    return VxColors(
      surface: Color.lerp(surface, other.surface, t)!,
      card: Color.lerp(card, other.card, t)!,
      cardRaised: Color.lerp(cardRaised, other.cardRaised, t)!,
      border: Color.lerp(border, other.border, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      text: Color.lerp(text, other.text, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      inverseText: Color.lerp(inverseText, other.inverseText, t)!,
      examinerChrome: Color.lerp(examinerChrome, other.examinerChrome, t)!,
      isDark: t < 0.5 ? isDark : other.isDark,
    );
  }
}

/// Type scale from UI/UX §2.2: 32/24/18/16/14/12, generous line height for
/// long evaluation text.
///
/// The type scale. No family is named anywhere in it.
///
/// A bundled display face is one of the clearest tells of a generated
/// interface, and it fights the platform: an app in San Francisco on iOS and
/// Segoe UI on Windows reads as *part of the device*, while the same app in a
/// downloaded grotesque reads as a web page in a wrapper. Every native app
/// worth imitating uses the system face.
///
/// So these styles carry size, weight and spacing only, and inherit the
/// family from the ambient DefaultTextStyle — which `vxTheme` points at the
/// platform's own UI font.
abstract final class VxType {
  static const display = TextStyle(
    fontSize: 32,
    height: 1.1,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
  );

  static const title = TextStyle(
    fontSize: 24,
    height: 1.2,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
  );

  static const heading = TextStyle(
    fontSize: 18,
    height: 1.3,
    fontWeight: FontWeight.w600,
  );

  /// The question itself. Large, generous, and the only thing on screen with
  /// this weight — the guide's "one hero visual per screen" applied to type.
  static const question = TextStyle(
    fontSize: 20,
    height: 1.45,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
  );

  static const body = TextStyle(
    fontSize: 16,
    height: 1.5,
    fontWeight: FontWeight.w400,
  );

  static const bodyStrong = TextStyle(
    fontSize: 16,
    height: 1.5,
    fontWeight: FontWeight.w600,
  );

  /// Long-form evaluation feedback. Taller lines because this is the text a
  /// student actually reads carefully, sometimes twice.
  static const prose = TextStyle(
    fontSize: 15,
    height: 1.6,
    fontWeight: FontWeight.w400,
  );

  static const label = TextStyle(
    fontSize: 14,
    height: 1.4,
    fontWeight: FontWeight.w500,
  );

  static const caption = TextStyle(
    fontSize: 12,
    height: 1.4,
    fontWeight: FontWeight.w500,
  );

  /// Small all-caps eyebrow. Letter-spaced because at 11px, caps without
  /// tracking read as a single blur.
  static const eyebrow = TextStyle(
    fontSize: 11,
    height: 1.3,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.8,
  );

  /// Any figure that changes in place — a countdown, a score counting up, a
  /// percentage. Tabular figures stop the layout from twitching as digits
  /// change, which is the difference between a timer and a distraction.
  static const metric = TextStyle(
    fontSize: 44,
    height: 1.0,
    fontWeight: FontWeight.w700,
    letterSpacing: -1.5,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const metricSmall = TextStyle(
    fontSize: 20,
    height: 1.1,
    fontWeight: FontWeight.w700,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}

/// Convenience accessors so widgets read `context.vx.card` rather than
/// `Theme.of(context).extension<VxColors>()!.card`.
extension VxThemeContext on BuildContext {
  VxColors get vx => Theme.of(this).extension<VxColors>()!;

  /// Whether the platform has asked for reduced motion.
  ///
  /// The design guide specifies score-ring fills, colour-wash transitions and
  /// Lottie celebrations, and says nothing about this (audit A11Y-03). Every
  /// animation in the app consults it.
  bool get reduceMotion => MediaQuery.maybeDisableAnimationsOf(this) ?? false;

  /// A duration that collapses to zero when motion is reduced.
  Duration motion(Duration value) => reduceMotion ? Duration.zero : value;
}

ThemeData vxTheme({required Brightness brightness}) {
  final isDark = brightness == Brightness.dark;
  final vx = isDark ? VxColors.dark : VxColors.light;

  final scheme = ColorScheme.fromSeed(
    seedColor: VxPalette.focus.tint,
    brightness: brightness,
  ).copyWith(
    surface: vx.surface,
    onSurface: vx.text,
    primary: isDark ? VxPalette.focus.tint : VxPalette.focus.strong,
    onPrimary: Colors.white,
    outline: vx.border,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: vx.surface,
    // null lets the engine resolve the platform's UI font — San Francisco on
    // iOS and macOS, Roboto on Android. Flutter web has no such default, so
    // it gets the CSS keyword that means the same thing there.
    fontFamily: kIsWeb ? 'system-ui' : null,
    extensions: [vx],
    splashFactory: InkSparkle.splashFactory,
    textTheme: TextTheme(
      displayLarge: VxType.display.copyWith(color: vx.text),
      titleLarge: VxType.title.copyWith(color: vx.text),
      titleMedium: VxType.heading.copyWith(color: vx.text),
      bodyLarge: VxType.body.copyWith(color: vx.text),
      bodyMedium: VxType.prose.copyWith(color: vx.text),
      labelLarge: VxType.label.copyWith(color: vx.text),
      labelSmall: VxType.caption.copyWith(color: vx.muted),
    ),
    dividerTheme: DividerThemeData(color: vx.hairline, thickness: 1, space: 1),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VxRadius.control),
        ),
        textStyle: VxType.bodyStrong,
      ),
    ),
  );
}
