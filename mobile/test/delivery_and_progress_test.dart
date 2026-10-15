import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivax/data/repository.dart';
import 'package:vivax/screens/viva/mode_picker_screen.dart';
import 'package:vivax/screens/viva/session_summary_screen.dart';

void main() {
  group('Delivery Analytics in SessionSummaryScreen', () {
    const subject = Subject(
      id: 'sub-test',
      name: 'Computer Networks',
      documentCount: 2,
      conceptCount: 8,
    );

    testWidgets(
        'renders delivery and speech coaching card with cadence and filler words',
        (tester) async {
      final answers = [
        const SessionAnswer(
          questionId: 'q1',
          conceptId: 'c1',
          concept: 'TCP Handshake',
          question: 'Explain the 3-way handshake in TCP.',
          score: 85,
          durationSeconds: 30,
          wordsPerMinute: 135,
          fillerWordsCount: 0,
        ),
        const SessionAnswer(
          questionId: 'q2',
          conceptId: 'c2',
          concept: 'BGP Routing',
          question: 'How does BGP prevent routing loops?',
          score: 72,
          durationSeconds: 45,
          wordsPerMinute: 120,
          fillerWordsCount: 2,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: SessionSummaryScreen(
            subject: subject,
            answers: answers,
            mode: VivaMode.examination,
            onPractiseWeakest: (_) {},
          ),
        ),
      );

      // Verify coaching card header
      expect(find.text('Delivery & Speech Coaching'), findsOneWidget);
      expect(find.text('Pacing and clarity during viva responses'),
          findsOneWidget);

      // Verify Cadence metric
      expect(find.text('Cadence'), findsOneWidget);
      expect(find.text('128 WPM'),
          findsOneWidget); // (135 + 120) / 2 = 127.5 -> 128
      expect(find.text('Ideal pace'), findsOneWidget);

      // Verify Filler words metric
      expect(find.text('Filler words'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('2 detected'), findsOneWidget);

      // Verify speak time (30s + 45s = 75s -> 1m 15s)
      expect(find.text('Speak time'), findsOneWidget);
      expect(find.text('1m 15s'), findsOneWidget);

      // Scroll to answer rows to ensure they are rendered in the ListView
      await tester.scrollUntilVisible(
        find.text('135 WPM'),
        200,
        scrollable: find.byType(Scrollable),
      );

      // Verify per-answer pill badges
      expect(find.text('135 WPM'), findsOneWidget);
      expect(find.text('120 WPM'), findsOneWidget);
      expect(find.text('2 fillers'), findsOneWidget);
      expect(find.text('30s'), findsOneWidget);
      expect(find.text('45s'), findsOneWidget);
    });

    testWidgets('displays clean tip when zero filler words detected',
        (tester) async {
      final answers = [
        const SessionAnswer(
          questionId: 'q1',
          conceptId: 'c1',
          concept: 'DNS Resolution',
          question: 'Describe recursive DNS resolution.',
          score: 90,
          durationSeconds: 20,
          wordsPerMinute: 140,
          fillerWordsCount: 0,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: SessionSummaryScreen(
            subject: subject,
            answers: answers,
            onPractiseWeakest: (_) {},
          ),
        ),
      );

      expect(find.text('Crisp & direct — zero filler words detected.'),
          findsOneWidget);
      expect(find.text('Clear'), findsOneWidget);
    });
  });

  group('Analytics reviewDates and consistency', () {
    test('Analytics accepts reviewDates and defaults to empty list', () {
      const a = Analytics(
        scores: [80, 85, 90],
        questionsAnswered: 3,
        reviewsLogged: 5,
        lapses: 1,
        improvement: 10,
        minutesPractised: 15,
      );
      expect(a.reviewDates, isEmpty);

      final now = DateTime.now();
      final a2 = Analytics(
        scores: [80],
        questionsAnswered: 1,
        reviewsLogged: 1,
        lapses: 0,
        improvement: 0,
        minutesPractised: 5,
        reviewDates: [now],
      );
      expect(a2.reviewDates.length, 1);
      expect(a2.reviewDates.first, now);
    });
  });
}
