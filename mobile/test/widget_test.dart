import 'package:flutter_test/flutter_test.dart';
import 'package:vivax/data/repository.dart';
import 'package:vivax/design/bold.dart';

/// Pure-logic tests.
///
/// The app itself now signs in to Supabase before it paints, so pumping
/// `ViaXApp` in a unit test would need a live network and would be testing
/// the backend rather than the widget. The rules worth protecting here are
/// the ones that decide what a student is told.
void main() {
  group('readiness bands', () {
    test('thresholds match the scale, and each carries a word', () {
      // Colour is never the only signal, so every band must name itself.
      expect(Bold.band(80).$1, 'On track');
      expect(Bold.band(75).$1, 'On track');
      expect(Bold.band(62).$1, 'Some risk');
      expect(Bold.band(50).$1, 'Some risk');
      expect(Bold.band(34).$1, 'At risk');
    });
  });

  group('mastery bands', () {
    test('an unexamined concept is not a failing one', () {
      // Both would render as 0%, so the distinction has to live in the label.
      expect(Bold.mastery(null).$1, 'Not examined');
      expect(Bold.mastery(0).$1, 'Critical');
    });

    test('bands ascend correctly', () {
      expect(Bold.mastery(90).$1, 'Strong');
      expect(Bold.mastery(60).$1, 'Minor gap');
      expect(Bold.mastery(40).$1, 'Needs work');
      expect(Bold.mastery(10).$1, 'Critical');
    });
  });

  group('coverage guard', () {
    Subject withConcepts(int n) => Subject(
          id: 's',
          name: 'OS',
          documentCount: 1,
          conceptCount: n,
        );

    test('refuses a viva below the concept floor', () {
      // Under this, questions would come from the model's general knowledge
      // rather than the student's notes — the one promise the product makes.
      expect(withConcepts(0).canExamine, isFalse);
      expect(withConcepts(4).canExamine, isFalse);
      expect(withConcepts(5).canExamine, isTrue);
      expect(withConcepts(40).canExamine, isTrue);
    });
  });

  group('exam countdown', () {
    test('counts whole days, ignoring the time of day', () {
      final subject = Subject(
        id: 's',
        name: 'OS',
        documentCount: 1,
        conceptCount: 9,
        examDate: DateTime.now().add(const Duration(days: 3)),
      );
      expect(subject.daysUntilExam, 3);
    });

    test('is null when no date is set, not zero', () {
      // Zero would render as "today" and panic a student who never set a date.
      expect(withoutDate().daysUntilExam, isNull);
    });
  });
}

Subject withoutDate() =>
    const Subject(id: 's', name: 'OS', documentCount: 1, conceptCount: 9);
