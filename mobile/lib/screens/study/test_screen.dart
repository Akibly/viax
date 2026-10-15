import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/repository.dart';
import '../../design/bold.dart';
import 'study_models.dart';

enum QuestionType { multipleChoice, trueFalse }

class TestQuestion {
  TestQuestion({
    required this.card,
    required this.type,
    required this.prompt,
    required this.options,
    required this.correctAnswer,
  });

  final StudyCard card;
  final QuestionType type;
  final String prompt;
  final List<String> options;
  final String correctAnswer;
  String? studentAnswer;

  bool get isCorrect => studentAnswer == correctAnswer;
}

/// Practice Test generator with multiple choice and true/false questions.
class TestScreen extends StatefulWidget {
  const TestScreen({
    super.key,
    required this.title,
    required this.cards,
    this.subjectId,
    this.questionCount,
  });

  final String title;
  final List<StudyCard> cards;
  final String? subjectId;
  final int? questionCount;

  @override
  State<TestScreen> createState() => _TestScreenState();
}

class _TestScreenState extends State<TestScreen> {
  static const _repo = Repository();
  late List<TestQuestion> _questions;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _generateTest();
  }

  void _generateTest() {
    final list = <TestQuestion>[];
    final shuffled = List<StudyCard>.of(widget.cards)..shuffle();
    if (widget.questionCount != null &&
        widget.questionCount! > 0 &&
        shuffled.length > widget.questionCount!) {
      shuffled.removeRange(widget.questionCount!, shuffled.length);
    }

    for (var i = 0; i < shuffled.length; i++) {
      final card = shuffled[i];
      final isTF = i % 2 == 1 && shuffled.length > 1;

      if (isTF) {
        // True / False question
        final isActuallyTrue = i % 3 != 0;
        final displayedTerm = isActuallyTrue
            ? card.term
            : (shuffled[(i + 1) % shuffled.length].term);

        list.add(TestQuestion(
          card: card,
          type: QuestionType.trueFalse,
          prompt: 'Term: "$displayedTerm"\n\nDefinition: ${card.definition}',
          options: const ['True', 'False'],
          correctAnswer: isActuallyTrue ? 'True' : 'False',
        ));
      } else {
        // Multiple Choice question
        final distractors = widget.cards
            .where((c) => c.id != card.id)
            .map((c) => c.term)
            .toList()
          ..shuffle();
        final options = <String>[card.term];
        options.addAll(distractors.take(3));
        options.shuffle();

        list.add(TestQuestion(
          card: card,
          type: QuestionType.multipleChoice,
          prompt: card.definition,
          options: options,
          correctAnswer: card.term,
        ));
      }
    }

    setState(() {
      _questions = list;
      _submitted = false;
    });
  }

  Future<bool> _saveResults() async {
    if (widget.subjectId == null) return true;
    final scores = <String, int>{};
    for (final q in _questions) {
      if (q.card.id.length > 5) {
        scores[q.card.id] = q.isCorrect ? 100 : 0;
      }
    }
    if (scores.isEmpty) return true;
    try {
      await _repo.submitStudyResults(widget.subjectId!, scores);
      return true;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save this test: $error')),
        );
      }
      return false;
    }
  }

  Future<void> _submitTest() async {
    final unanswered = _questions.where((q) => q.studentAnswer == null).length;
    if (unanswered > 0) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Bold.card,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text('Unanswered Questions',
              style: T.heading.copyWith(color: Bold.ink)),
          content: Text(
            'You still have $unanswered unanswered question${unanswered == 1 ? '' : 's'}. Are you sure you want to submit?',
            style: T.body.copyWith(color: Bold.slate),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Keep answering'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                HapticFeedback.heavyImpact();
                if (!await _saveResults() || !mounted) return;
                setState(() => _submitted = true);
              },
              child: const Text('Submit anyway'),
            ),
          ],
        ),
      );
      return;
    }

    HapticFeedback.heavyImpact();

    if (!await _saveResults() || !mounted) return;
    setState(() => _submitted = true);
  }

  @override
  Widget build(BuildContext context) {
    final correctCount = _questions.where((q) => q.isCorrect).length;
    final scorePct = _questions.isEmpty
        ? 0
        : (correctCount / _questions.length * 100).round();
    final (grade, gradeColor) = Bold.band(scorePct.toDouble());

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Bold.canvas,
        surfaceTintColor: Colors.transparent,
        title: Text('Test: ${widget.title}',
            style: T.heading.copyWith(color: Bold.ink)),
        actions: [
          if (_submitted)
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'New Test',
              onPressed: _generateTest,
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
          children: [
            if (_submitted) ...[
              // Score Banner
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: Bold.wash(gradeColor),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    Text('Your Test Score',
                        style: T.small.copyWith(color: gradeColor)),
                    const SizedBox(height: 6),
                    Text(
                      '$scorePct%',
                      style: TextStyle(
                        fontSize: 54,
                        fontWeight: FontWeight.w800,
                        color: gradeColor,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                        '$correctCount / ${_questions.length} correct · $grade',
                        style: T.body.copyWith(
                            color: gradeColor, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text('Detailed Review',
                  style: T.heading.copyWith(color: Bold.ink)),
              const SizedBox(height: 12),
            ],
            for (var i = 0; i < _questions.length; i++) ...[
              _QuestionCard(
                index: i + 1,
                question: _questions[i],
                submitted: _submitted,
                onSelectAnswer: (ans) {
                  if (_submitted) return;
                  HapticFeedback.selectionClick();
                  setState(() => _questions[i].studentAnswer = ans);
                },
              ),
              const SizedBox(height: 16),
            ],
            if (!_submitted) ...[
              const SizedBox(height: 10),
              FilledButton(
                onPressed: _submitTest,
                child: const Text('Submit Practice Test'),
              ),
            ] else ...[
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _generateTest,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retake Test (New Questions)'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.index,
    required this.question,
    required this.submitted,
    required this.onSelectAnswer,
  });

  final int index;
  final TestQuestion question;
  final bool submitted;
  final void Function(String) onSelectAnswer;

  @override
  Widget build(BuildContext context) {
    final isCorrect = question.isCorrect;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Bold.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: submitted ? (isCorrect ? Bold.good : Bold.danger) : Bold.line,
          width: submitted ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Question $index',
                style: T.small.copyWith(
                  color: Bold.brand,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (submitted)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Bold.wash(isCorrect ? Bold.good : Bold.danger),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    isCorrect ? 'Correct' : 'Incorrect',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isCorrect ? Bold.good : Bold.danger,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            question.prompt,
            style: T.body.copyWith(color: Bold.ink, height: 1.4),
          ),
          const SizedBox(height: 14),
          for (final opt in question.options) ...[
            _TestOptionTile(
              text: opt,
              isSelected: question.studentAnswer == opt,
              isCorrect: opt == question.correctAnswer,
              submitted: submitted,
              onTap: () => onSelectAnswer(opt),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _TestOptionTile extends StatelessWidget {
  const _TestOptionTile({
    required this.text,
    required this.isSelected,
    required this.isCorrect,
    required this.submitted,
    required this.onTap,
  });

  final String text;
  final bool isSelected;
  final bool isCorrect;
  final bool submitted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Color bg = Bold.canvas;
    Color border = Bold.line;
    Color textColor = Bold.ink;

    if (submitted) {
      if (isCorrect) {
        bg = Bold.wash(Bold.good);
        border = Bold.good;
        textColor = Bold.good;
      } else if (isSelected) {
        bg = Bold.wash(Bold.danger);
        border = Bold.danger;
        textColor = Bold.danger;
      }
    } else if (isSelected) {
      bg = Bold.wash(Bold.brand);
      border = Bold.brand;
      textColor = Bold.brand;
    }

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: submitted ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border, width: isSelected ? 1.5 : 1.0),
          ),
          child: Row(
            children: [
              Icon(
                isSelected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                size: 18,
                color: border,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: T.body.copyWith(
                    color: textColor,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
