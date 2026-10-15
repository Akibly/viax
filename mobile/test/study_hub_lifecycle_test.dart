import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivax/screens/study/study_hub_screen.dart';

void main() {
  testWidgets('study hub starts loading without throwing during initState',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: StudyHubScreen()),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
