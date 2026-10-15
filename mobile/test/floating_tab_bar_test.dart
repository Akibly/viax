import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivax/design/bold.dart';
import 'package:vivax/screens/shell/tab_shell.dart';

void main() {
  testWidgets(
      'floating tab bar stays at the bottom and leaves room for page content',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: boldLightTheme(),
        home: Scaffold(
          body: Container(key: const Key('shell-page')),
          bottomNavigationBar: ViaXFloatingTabBar(
            selectedIndex: 0,
            destinations: const [
              NavigationDestination(
                  icon: Icon(Icons.home_outlined), label: 'Home'),
              NavigationDestination(
                  icon: Icon(Icons.book_outlined), label: 'Library'),
              NavigationDestination(
                  icon: Icon(Icons.style_outlined), label: 'Study'),
              NavigationDestination(
                  icon: Icon(Icons.mic_none_rounded), label: 'Viva'),
              NavigationDestination(
                  icon: Icon(Icons.insights_rounded), label: 'Progress'),
            ],
            onSelect: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final screen = tester.getRect(find.byType(Scaffold));
    final page = tester.getRect(find.byKey(const Key('shell-page')));
    final dock = tester.getRect(find.byKey(const Key('viax-dock-surface')));

    expect(page.height, greaterThan(screen.height / 2));
    expect(screen.bottom - dock.bottom, closeTo(10, 1));
  });
}
