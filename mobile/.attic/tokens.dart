/// VivaX design tokens.
///
/// The palette in the UI/UX Design Guide §2.1 is kept as the product's
/// identity, with one correction the audit forced (finding A11Y-01): the guide
/// and the SRS both require WCAG AA contrast, and the guide's own hex values
/// fail it in five documented usages. Measured, not estimated:
///
///   white on Calm Sky    #38BDF8 → 2.14:1   (needs 4.5:1)
///   white on Alert Amber #F59E0B → 2.15:1
///   white on Mastery Grn #22C55E → 2.28:1
///   Alert Amber text on Surface Light → 2.05:1
///   white on Gap Red     #EF4444 → 3.76:1   (large text only)
///
/// The fix keeps every hue's identity and splits each into two roles:
///
///   * [VxHue.tint]   — the guide's original value. Fills, strokes, glyphs,
///                      and text **on dark surfaces**, where they measure
///                      8.33:1 (Sky) and 8.31:1 (Amber) and are excellent.
///   * [VxHue.strong] — a darkened variant for text on light surfaces and for
///                      any fill that carries white text. All verified ≥ 4.5:1.
///
/// So the app still looks like the design guide; it just stops failing the
/// standard the design guide mandates.
library;

import 'package:flutter/widgets.dart';

// ---------------------------------------------------------------------------
// Raw palette
// ---------------------------------------------------------------------------

/// A hue with its two accessible roles, so a caller cannot accidentally pick
/// the one that fails on the surface they are drawing on.
@immutable
class VxHue {
  const VxHue({
    required this.tint,
    required this.strong,
    required this.wash,
    required this.washDark,
  });

  /// Identity value. Safe as text on dark surfaces, and for fills/strokes.
  final Color tint;

  /// Darkened. Safe as text on light surfaces, and as a fill under white text.
  final Color strong;

  /// Very light background for chips and banners in light theme.
  final Color wash;

  /// Deep background for the same in dark theme.
  final Color washDark;
}

abstract final class VxPalette {
  /// Examiner Navy — primary text and exam-mode chrome. 13.98:1 on Surface
  /// Light; the anchor of the whole palette and already correct.
  static const navy = Color(0xFF1E293B);
  static const navyDeep = Color(0xFF0F172A);

  /// Focus Blue — primary actions. 5.17:1 on white, already correct.
  static const focus = VxHue(
    tint: Color(0xFF2563EB),
    strong: Color(0xFF1D4ED8),
    wash: Color(0xFFEFF6FF),
    washDark: Color(0xFF132038),
  );

  /// Calm Sky — Practice mode. Lighter, encouraging.
  static const sky = VxHue(
    tint: Color(0xFF38BDF8),
    strong: Color(0xFF0369A1), // white on this = 5.93:1
    wash: Color(0xFFE0F2FE),
    washDark: Color(0xFF07293D),
  );

  /// Alert Amber — Examination mode. Timer, strict-mode indicators.
  static const amber = VxHue(
    tint: Color(0xFFF59E0B),
    strong: Color(0xFFB45309), // white on this = 5.02:1
    wash: Color(0xFFFEF3C7),
    washDark: Color(0xFF33240B),
  );

  /// Mastery Green — strong concept mastery.
  static const green = VxHue(
    tint: Color(0xFF22C55E),
    strong: Color(0xFF15803D), // white on this = 5.02:1
    wash: Color(0xFFDCFCE7),
    washDark: Color(0xFF0F2A19),
  );

  /// Gap Red — critical learning gaps.
  static const red = VxHue(
    tint: Color(0xFFEF4444),
    strong: Color(0xFFDC2626), // white on this = 4.83:1
    wash: Color(0xFFFEE2E2),
    washDark: Color(0xFF2E1517),
  );

  /// Professor mode. Not in the guide's table; chosen to sit between navy and
  /// focus so the mode reads as "harder" without introducing a new family.
  static const violet = VxHue(
    tint: Color(0xFF8B5CF6),
    strong: Color(0xFF6D28D9),
    wash: Color(0xFFF3EEFF),
    washDark: Color(0xFF1E1633),
  );

  // Neutrals. Cool-biased toward Examiner Navy rather than a pure grey, so
  // the surfaces read as belonging to the same family as the text on them.
  static const surfaceLight = Color(0xFFF8FAFC);
  static const surfaceDark = Color(0xFF0F172A);
  static const cardLight = Color(0xFFFFFFFF);
  static const cardDark = Color(0xFF16213A);
  static const borderLight = Color(0xFFE2E8F0);
  static const borderDark = Color(0xFF243049);
  static const textLight = Color(0xFF1E293B);
  static const textDark = Color(0xFFE7ECF5);
  static const mutedLight = Color(0xFF64748B); // 4.76:1 on white
  static const mutedDark = Color(0xFF93A2BC); // 6.20:1 on card dark
}

// ---------------------------------------------------------------------------
// Spacing — 8pt base, per UI/UX §2.3
// ---------------------------------------------------------------------------

abstract final class VxSpace {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;

  /// Screen padding on mobile.
  static const screen = 16.0;
}

abstract final class VxRadius {
  static const chip = 999.0;
  static const card = 16.0;
  static const sheet = 24.0;
  static const control = 14.0;
}

// ---------------------------------------------------------------------------
// Motion
// ---------------------------------------------------------------------------

/// Durations and curves, named for what they express rather than how long
/// they take — so "the score reveal" is tuned in one place.
///
/// The guide's principle is *earn the feedback*: a score that appears
/// instantly reads as generated, one that resolves over ~800ms reads as
/// diagnosed. That is the only place in the app where slower is better, and
/// it is deliberately the longest motion in the system.
abstract final class VxMotion {
  /// Question reveal: 200ms fade + 8px rise (UI/UX §2.5).
  static const questionReveal = Duration(milliseconds: 200);
  static const questionRise = 8.0;

  /// Rubric ring fill, with a haptic tick on completion.
  static const scoreReveal = Duration(milliseconds: 800);

  /// Mode switch colour-wash, so the mode change is felt before it is read.
  static const modeWash = Duration(milliseconds: 420);

  /// Ordinary UI state changes.
  static const fast = Duration(milliseconds: 120);
  static const normal = Duration(milliseconds: 220);

  /// Badge celebration, hard-capped so it never blocks the next action.
  static const celebrationCap = Duration(milliseconds: 1500);

  static const enter = Curves.easeOutCubic;
  static const exit = Curves.easeInCubic;

  /// Slight overshoot for the score ring — it settles rather than stops,
  /// which is what makes it feel measured rather than mechanical.
  static const settle = Cubic(0.2, 0.9, 0.25, 1.05);
}

// ---------------------------------------------------------------------------
// Gap severity
// ---------------------------------------------------------------------------

/// Severity of a learning gap.
///
/// The corpus defined this vocabulary three different ways (audit C-05); this
/// mirrors the `gap_severity` enum the database now uses, so the label a
/// student sees and the value stored cannot drift.
///
/// Every level carries a [label] as well as a colour. UI/UX §5 requires that
/// colour is never the only signal, and this is the type that guarantees it —
/// a caller cannot render severity without also having the word.
enum VxSeverity {
  strong('Strong'),
  minor('Minor gap'),
  medium('Needs work'),
  critical('Critical');

  const VxSeverity(this.label);
  final String label;

  static VxSeverity fromMastery(double pct) => switch (pct) {
        >= 75 => VxSeverity.strong,
        >= 55 => VxSeverity.minor,
        >= 35 => VxSeverity.medium,
        _ => VxSeverity.critical,
      };

  VxHue get hue => switch (this) {
        VxSeverity.strong => VxPalette.green,
        VxSeverity.minor => VxPalette.sky,
        VxSeverity.medium => VxPalette.amber,
        VxSeverity.critical => VxPalette.red,
      };
}

// ---------------------------------------------------------------------------
// Viva modes
// ---------------------------------------------------------------------------

/// A viva mode and the visual language that belongs to it.
///
/// UI/UX §2.5 asks that the student feels the mode shift before reading a
/// label. Keeping the accent on the mode itself — rather than scattering
/// `if (mode == exam)` across widgets — is what makes that consistent.
enum VxMode {
  practice(
    'Practice',
    'Unlimited attempts, hints, and the expected answer after each question.',
    VxPalette.sky,
  ),
  examination(
    'Examination',
    'Timed. No hints, no edits, strict scoring.',
    VxPalette.amber,
  ),
  professor(
    'Professor',
    'Hard follow-ups and cross-topic questions. Higher difficulty floor.',
    VxPalette.violet,
  ),
  interview(
    'Mock Interview',
    'Industry style: behavioural, technical, and system design.',
    VxPalette.focus,
  );

  const VxMode(this.label, this.blurb, this.hue);
  final String label;
  final String blurb;
  final VxHue hue;

  bool get isTimed => this == VxMode.examination;
  bool get showsHints => this == VxMode.practice;
}
