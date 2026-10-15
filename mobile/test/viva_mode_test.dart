import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivax/data/repository.dart';
import 'package:vivax/screens/viva/mode_picker_screen.dart';
import 'package:vivax/screens/viva/session_summary_screen.dart';

void main() {
  group('VivaMode properties', () {
    test('examination mode is timed and not preview', () {
      expect(VivaMode.examination.isTimed, isTrue);
      expect(VivaMode.examination.isPreview, isFalse);
      expect(VivaMode.examination.label, 'Examination');
    });

    test('practice mode is not timed and not preview', () {
      expect(VivaMode.practice.isTimed, isFalse);
      expect(VivaMode.practice.isPreview, isFalse);
      expect(VivaMode.practice.label, 'Practice');
    });

    test('professor and mock modes are preview modes', () {
      expect(VivaMode.professor.isPreview, isTrue);
      expect(VivaMode.professor.isTimed, isFalse);
      expect(VivaMode.mock.isPreview, isTrue);
      expect(VivaMode.mock.isTimed, isFalse);
    });
  });

  group('SessionSummaryScreen metrics and trend', () {
    const subject = Subject(
      id: 'sub-1',
      name: 'Distributed Systems',
      documentCount: 3,
      conceptCount: 12,
    );

    test('trend calculation detects positive improvement', () {
      final answers = [
        const SessionAnswer(
          questionId: 'q1',
          conceptId: 'c1',
          concept: 'Paxos',
          question: 'What is Paxos?',
          score: 50,
        ),
        const SessionAnswer(
          questionId: 'q2',
          conceptId: 'c2',
          concept: 'Raft',
          question: 'What is Raft?',
          score: 80,
        ),
      ];

      final screen = SessionSummaryScreen(
        subject: subject,
        answers: answers,
        mode: VivaMode.examination,
        onPractiseWeakest: (_) {},
      );

      expect(screen.mode, VivaMode.examination);
      expect(screen.answers.length, 2);
    });

    testWidgets(
        'renders session summary with mode badge and weakest recommendation',
        (tester) async {
      final answers = [
        const SessionAnswer(
          questionId: 'q1',
          conceptId: 'c1',
          concept: 'Two-Phase Commit',
          question: 'Explain 2PC coordinator failure.',
          score: 40,
        ),
        const SessionAnswer(
          questionId: 'q2',
          conceptId: 'c2',
          concept: 'Vector Clocks',
          question: 'How do vector clocks detect causality?',
          score: 90,
        ),
      ];

      SessionAnswer? practiced;

      await tester.pumpWidget(
        MaterialApp(
          home: SessionSummaryScreen(
            subject: subject,
            answers: answers,
            mode: VivaMode.examination,
            onPractiseWeakest: (weakest) {
              practiced = weakest;
            },
          ),
        ),
      );

      // Verify mode badge appears
      expect(find.text('Examination'), findsOneWidget);

      // Verify question count and title
      expect(find.text('2 questions answered'), findsOneWidget);
      expect(find.text('What you were asked'), findsOneWidget);

      // Verify weakest recommendation identifies Two-Phase Commit
      expect(find.text('Do this next'), findsOneWidget);
      expect(find.text('Practise Two-Phase Commit'), findsOneWidget);

      // Scroll to and tap weakest recommendation
      await tester.ensureVisible(find.text('Practise Two-Phase Commit'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Practise Two-Phase Commit'));
      expect(practiced?.concept, 'Two-Phase Commit');
    });
  });
}
