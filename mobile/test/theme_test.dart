import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivax/design/bold.dart';

void main() {
  group('ViaX theme', () {
    test('uses the evidence-blue focus color', () {
      expect(Bold.brand, const Color(0xFF3157D5));
    });

    test('light theme has light brightness and correct seed', () {
      final theme = boldLightTheme();
      expect(theme.brightness, Brightness.light);
      expect(theme.colorScheme.primary, Bold.brand);
      expect(theme.scaffoldBackgroundColor, Bold.canvasLight);
    });

    test('dark theme has dark brightness and dark background', () {
      final theme = boldDarkTheme();
      expect(theme.brightness, Brightness.dark);
      expect(theme.colorScheme.primary, Bold.brandLift);
      expect(theme.scaffoldBackgroundColor, Bold.canvasDark);
    });

    test('Bold color tokens and wash adapt between light and dark modes', () {
      // Light mode tokens
      expect(Bold.card, Bold.cardLight);
      expect(Bold.canvas, Bold.canvasLight);
      expect(Bold.ink, Bold.inkLight);
      expect(Bold.slate, Bold.slateLight);
      expect(Bold.line, Bold.lineLight);

      // Dark mode tokens
      expect(Bold.cardDark, isNot(Bold.canvasDark));
      expect(Bold.inkDark, isNot(Bold.slateDark));
      expect(Bold.lineDark, isNot(Bold.canvasDark));

      // Wash adaptation
      expect(Bold.wash(Bold.brand, false), const Color(0xFFE7ECFF));
      expect(Bold.wash(Bold.brand, true), Bold.brand.withValues(alpha: 0.18));
    });

    test('themeNotifier updates state', () {
      Bold.themeNotifier.value = ThemeMode.dark;
      expect(Bold.themeNotifier.value, ThemeMode.dark);

      Bold.themeNotifier.value = ThemeMode.light;
      expect(Bold.themeNotifier.value, ThemeMode.light);

      Bold.themeNotifier.value = ThemeMode.system;
      expect(Bold.themeNotifier.value, ThemeMode.system);
    });
  });
}
