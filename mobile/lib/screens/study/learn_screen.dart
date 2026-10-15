import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/repository.dart';
import '../../design/bold.dart';
import 'study_models.dart';

/// Learn mode with adaptive multiple-choice questions
/// and mastery progression (New -> Learning -> Mastered).
class LearnScreen extends StatefulWidget {
  const LearnScreen({
    super.key,
    required this.title,
    required this.cards,
    this.subjectId,
  });

  final String title;
  final List<StudyCard> cards;
  final String? subjectId;

  @override
  State<LearnScreen> createState() => _LearnScreenState();
}

class _LearnScreenState extends State<LearnScreen> {
  static const _repo = Repository();
  late List<StudyCard> _pool;
  late Map<String, int>
      _mastery; // id -> level (0 = New, 1 = Learning, 2 = Mastered)
  int _questionIndex = 0;
  List<String> _currentOptions = [];
  String? _selectedOption;
  bool _answered = false;

  @override
  void initState() {
    super.initState();
    _pool = List.of(widget.cards)..shuffle();
    _mastery = {for (final c in widget.cards) c.id: 0};
    _prepareQuestion();
  }

  StudyCard? get _currentCard =>
      _pool.isNotEmpty && _questionIndex < _pool.length
          ? _pool[_questionIndex]
          : null;

  int get _masteredCount => _mastery.values.where((lvl) => lvl >= 2).length;

  int get _learningCount => _mastery.values.where((lvl) => lvl == 1).length;

  int get _newCount => _mastery.values.where((lvl) => lvl == 0).length;

  void _prepareQuestion() {
    final card = _currentCard;
    if (card == null) return;

    final distractors = widget.cards
        .where((c) => c.id != card.id)
        .map((c) => c.term)
        .toList()
      ..shuffle();

    final options = <String>[card.term];
    options.addAll(distractors.take(3));
    options.shuffle();

    setState(() {
      _currentOptions = options;
      _selectedOption = null;
      _answered = false;
    });
  }

  void _chooseOption(String option) {
    if (_answered) return;
    final card = _currentCard;
    if (card == null) return;

    final isCorrect = option == card.term;
    if (isCorrect) {
      HapticFeedback.lightImpact();
      _mastery[card.id] = (_mastery[card.id] ?? 0) + 1;
    } else {
      HapticFeedback.heavyImpact();
      _mastery[card.id] = 0; // Lapse resets to 0, spaced repetition rule
    }

    setState(() {
      _selectedOption = option;
      _answered = true;
    });
  }

  void _next() {
    if (_masteredCount >= widget.cards.length) {
      _showCompletionDialog();
      return;
    }

    if (_questionIndex < _pool.length - 1) {
      setState(() => _questionIndex++);
    } else {
      // Re-pool unmastered cards
      final unmastered = widget.cards
          .where((c) => (_mastery[c.id] ?? 0) < 2)
          .toList()
        ..shuffle();
      if (unmastered.isEmpty) {
        _showCompletionDialog();
        return;
      }
      setState(() {
        _pool = unmastered;
        _questionIndex = 0;
      });
    }
    _prepareQuestion();
  }

  void _showCompletionDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Bold.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Set Mastered! 🎓',
            style: T.heading.copyWith(color: Bold.ink)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'You successfully mastered all ${widget.cards.length} terms in ${widget.title}!',
              style: T.body.copyWith(color: Bold.slate),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () async {
              if (widget.subjectId != null) {
                final scores = <String, int>{};
                for (final entry in _mastery.entries) {
                  if (entry.key.length > 5) {
                    scores[entry.key] = entry.value * 50; // 0, 50, or 100
                  }
                }
                if (scores.isNotEmpty) {
                  try {
                    await _repo.submitStudyResults(widget.subjectId!, scores);
                  } catch (error) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text('Could not save this round: $error')),
                    );
                    return;
                  }
                }
              }
              if (!mounted || !ctx.mounted) return;
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
            },
            child: const Text('Great!'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final card = _currentCard;

    if (card == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: const Center(child: Text('No terms available.')),
      );
    }

    final isCorrect = _selectedOption == card.term;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Bold.canvas,
        surfaceTintColor: Colors.transparent,
        title: Text('Learn: ${widget.title}',
            style: T.heading.copyWith(color: Bold.ink)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Mastery breakdown header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _MasteryPill(
                        label: 'New',
                        count: _newCount,
                        color: Bold.slate,
                      ),
                      _MasteryPill(
                        label: 'Learning',
                        count: _learningCount,
                        color: Bold.warn,
                      ),
                      _MasteryPill(
                        label: 'Mastered',
                        count: _masteredCount,
                        color: Bold.good,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: widget.cards.isEmpty
                          ? 0
                          : _masteredCount / widget.cards.length,
                      backgroundColor: Bold.line,
                      color: Bold.good,
                      minHeight: 6,
                    ),
                  ),
                ],
              ),
            ),

            // Prompt (Definition)
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: Bold.card,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Bold.line),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'DEFINITION',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: Bold.brand,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          card.definition,
                          style: T.body.copyWith(
                            color: Bold.ink,
                            height: 1.5,
                            fontSize: 17,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Choose matching term',
                    style: T.small.copyWith(color: Bold.slate),
                  ),
                  const SizedBox(height: 10),

                  // Multiple-choice options
                  for (final opt in _currentOptions) ...[
                    _OptionButton(
                      text: opt,
                      isSelected: _selectedOption == opt,
                      isCorrectAnswer: opt == card.term,
                      answered: _answered,
                      onTap: () => _chooseOption(opt),
                    ),
                    const SizedBox(height: 10),
                  ],

                  if (_answered) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isCorrect
                            ? Bold.wash(Bold.good)
                            : Bold.wash(Bold.danger),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isCorrect
                                ? Icons.check_circle_rounded
                                : Icons.cancel_rounded,
                            color: isCorrect ? Bold.good : Bold.danger,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              isCorrect
                                  ? 'Correct! Nice recall.'
                                  : 'Not quite. The correct term is "${card.term}".',
                              style: T.body.copyWith(
                                color: isCorrect ? Bold.good : Bold.danger,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _next,
                      child: const Text('Continue'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MasteryPill extends StatelessWidget {
  const _MasteryPill({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Bold.wash(color),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$count',
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}

class _OptionButton extends StatelessWidget {
  const _OptionButton({
    required this.text,
    required this.isSelected,
    required this.isCorrectAnswer,
    required this.answered,
    required this.onTap,
  });

  final String text;
  final bool isSelected;
  final bool isCorrectAnswer;
  final bool answered;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Color bg = Bold.card;
    Color border = Bold.line;
    Color textColor = Bold.ink;

    if (answered) {
      if (isCorrectAnswer) {
        bg = Bold.wash(Bold.good);
        border = Bold.good;
        textColor = Bold.good;
      } else if (isSelected) {
        bg = Bold.wash(Bold.danger);
        border = Bold.danger;
        textColor = Bold.danger;
      }
    }

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: answered ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border, width: 1.5),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  text,
                  style: T.body.copyWith(
                    color: textColor,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              if (answered && isCorrectAnswer)
                const Icon(Icons.check_circle_rounded,
                    size: 20, color: Bold.good)
              else if (answered && isSelected)
                const Icon(Icons.cancel_rounded, size: 20, color: Bold.danger),
            ],
          ),
        ),
      ),
    );
  }
}
