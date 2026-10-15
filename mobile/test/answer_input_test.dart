import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivax/screens/viva/answer_input.dart';

void main() {
  testWidgets('empty answers cannot submit and typed answers remain editable',
      (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var submitted = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AnswerInput(
      controller: controller,
      onSubmit: () => submitted++,
      submitting: false,
    ))));
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    await tester.enterText(find.byType(TextField), 'My explanation');
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull);
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(submitted, 1);
    expect(controller.text, 'My explanation');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'marking locks the answer and explains progress at large text scale',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = TextEditingController(text: 'Preserve this answer');
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
      data: const MediaQueryData(
          textScaler: TextScaler.linear(1.5), disableAnimations: true),
      child: Scaffold(
          body: SingleChildScrollView(
              child: AnswerInput(
        controller: controller,
        onSubmit: () => fail('must not submit twice'),
        submitting: true,
      ))),
    )));
    expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    expect(find.text('Checking against your notes…'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
