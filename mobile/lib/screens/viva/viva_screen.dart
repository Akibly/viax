import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/repository.dart';
import '../../design/bold.dart';
import 'mode_picker_screen.dart';
import 'session_summary_screen.dart';
import 'answer_input.dart';
import 'dispute_screen.dart';
import 'source_viewer_screen.dart';

/// The examination.
///
/// One question, full width, and the only thing on screen with that weight —
/// this must read as an oral examination, never as a chat thread. The answer
/// box sits below it, and the evaluation replaces the question rather than
/// stacking beneath it, so a student is never comparing their answer to a
/// mark while writing the next one.
class VivaScreen extends StatefulWidget {
  const VivaScreen({
    super.key,
    required this.subject,
    this.focusConcept,
    this.mode = VivaMode.practice,
  });

  final Subject subject;

  /// Practice by default: a student who lands here from a weak concept wants
  /// to learn it, not be timed on it.
  final VivaMode mode;

  /// Examine this concept specifically. Entered by tapping a concept, which
  /// is the PRD's own success metric: concept graph to focused practice in
  /// one tap, with no dead end in between.
  final ConceptRow? focusConcept;

  @override
  State<VivaScreen> createState() => _VivaScreenState();
}

class _VivaScreenState extends State<VivaScreen> {
  static const _repo = Repository();
  final _answer = TextEditingController();

  VivaQuestion? _question;
  VivaResult? _result;
  String? _sessionId;
  String? _reviewConceptId;
  String? _error;
  InsufficientMaterial? _refused;
  bool _loading = true;
  bool _marking = false;

  /// Examination mode timer (120 seconds per question).
  Timer? _examTimer;
  static const int _totalExamSeconds = 120;
  int _secondsRemaining = _totalExamSeconds;

  /// Timestamp when the current question was presented, for pacing analytics.
  DateTime? _questionStartTime;

  /// Every answer in this sitting, oldest first. A viva is a sitting, not a
  /// series of one-offs, and the summary at the end is what makes it one.
  final List<SessionAnswer> _sitting = [];

  /// Kept so the report can put what the student said beside what was
  /// expected — UI/UX §4.6 asks for that comparison, and a mark without it
  /// is an assertion.
  String _lastAnswer = '';

  /// The question just marked. A probe needs it, and it outlives `_question`
  /// because that is cleared when the next question loads.
  String? _markedQuestionId;
  int get _answered => _sitting.length;

  @override
  void initState() {
    super.initState();
    _ask();
  }

  @override
  void dispose() {
    _stopTimer();
    _answer.dispose();
    super.dispose();
  }

  void _startTimer() {
    _stopTimer();
    if (widget.mode != VivaMode.examination) return;
    setState(() => _secondsRemaining = _totalExamSeconds);
    _examTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_secondsRemaining > 1) {
        setState(() => _secondsRemaining--);
        if (_secondsRemaining == 30) {
          HapticFeedback.mediumImpact();
        } else if (_secondsRemaining <= 10) {
          HapticFeedback.lightImpact();
        }
      } else {
        _stopTimer();
        setState(() => _secondsRemaining = 0);
        HapticFeedback.heavyImpact();
        _submit();
      }
    });
  }

  void _stopTimer() {
    _examTimer?.cancel();
    _examTimer = null;
  }

  /// Lets the examiner press on the last answer.
  ///
  /// Falls through to a fresh question when the examiner declines — a student
  /// tapping "continue" should never hit a dead end because the rule decided
  /// there was nothing worth asking.
  Future<void> _press() async {
    _stopTimer();
    final id = _markedQuestionId;
    if (id == null) return _ask();
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      final probe = await _repo.followUp(questionId: id);
      if (!mounted) return;
      if (probe == null) return _ask();
      setState(() {
        _question = probe;
        _sessionId = probe.sessionId;
        _loading = false;
        _answer.clear();
        _questionStartTime = DateTime.now();
      });
      _startTimer();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _ask() async {
    _stopTimer();
    setState(() {
      _loading = true;
      _error = null;
      _refused = null;
      _result = null;
    });
    try {
      final q = await _repo.nextQuestion(
        subjectId: widget.subject.id,
        sessionId: _sessionId,
        conceptId: _reviewConceptId ?? widget.focusConcept?.id,
        mode: widget.mode.name,
      );
      if (!mounted) return;
      setState(() {
        _question = q;
        _sessionId = q.sessionId;
        _loading = false;
        _answer.clear();
        _questionStartTime = DateTime.now();
      });
      _startTimer();
    } on InsufficientMaterial catch (e) {
      if (mounted) {
        setState(() {
          _refused = e;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _submit() async {
    if (_marking || _loading || _result != null) return;
    final text = _answer.text.trim();
    if (text.isEmpty || _question == null) return;
    _stopTimer();
    HapticFeedback.mediumImpact();
    setState(() {
      _marking = true;
      _lastAnswer = text;
      _markedQuestionId = _question!.id;
    });
    final duration = _questionStartTime != null
        ? DateTime.now().difference(_questionStartTime!).inSeconds
        : 0;
    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    final wpm =
        duration > 0 ? ((words / (duration / 60.0)).round()).clamp(0, 350) : 0;
    final fillerMatches = RegExp(
      r'\b(um|uh|like|you know|actually|basically|literally|sort of|kind of)\b',
      caseSensitive: false,
    ).allMatches(text).length;

    try {
      final result = await _repo.evaluate(
        questionId: _question!.id,
        answer: text,
      );
      if (mounted) {
        HapticFeedback.lightImpact();
        setState(() {
          _result = result;
          _marking = false;
          _sitting.add(SessionAnswer(
            questionId: _question!.id,
            conceptId: _question!.conceptId.isNotEmpty
                ? _question!.conceptId
                : widget.focusConcept?.id ?? '',
            concept: _question!.concept,
            question: _question!.text,
            score: result.composite,
            durationSeconds: duration,
            wordsPerMinute: wpm,
            fillerWordsCount: fillerMatches,
          ));
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _marking = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  /// Closes the sitting and shows the report.
  ///
  /// Offered rather than forced: a student may want twelve questions or two,
  /// and an arbitrary cut-off would be the app deciding how long a viva is.
  Future<void> _finish() async {
    _stopTimer();
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SessionSummaryScreen(
        subject: widget.subject,
        answers: List.of(_sitting),
        mode: widget.mode,
        onPractiseWeakest: (weakest) {
          // Straight back into a focused round on the weakest concept,
          // without a stop at the mode picker.
          Navigator.of(context).pop();
          setState(() {
            _sitting.clear();
            _result = null;
            _sessionId = null;
            _reviewConceptId =
                weakest.conceptId.isEmpty ? null : weakest.conceptId;
          });
          _ask();
        },
      ),
    ));
    if (mounted && _sitting.isNotEmpty) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final showExamTimer = widget.mode == VivaMode.examination &&
        _question != null &&
        _result == null &&
        !_loading;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Bold.canvas,
        surfaceTintColor: Colors.transparent,
        title: Text(
          widget.focusConcept?.name ?? widget.subject.name,
          style: T.heading,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (showExamTimer)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _secondsRemaining <= 15
                        ? Bold.wash(Bold.danger)
                        : (_secondsRemaining <= 30
                            ? Bold.wash(Bold.warn)
                            : Bold.wash(Bold.brand)),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: _secondsRemaining <= 15
                          ? Bold.danger
                          : (_secondsRemaining <= 30 ? Bold.warn : Bold.brand),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.timer_outlined,
                        size: 14,
                        color: _secondsRemaining <= 15
                            ? Bold.danger
                            : (_secondsRemaining <= 30
                                ? Bold.warn
                                : Bold.brand),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${(_secondsRemaining ~/ 60).toString().padLeft(2, '0')}:${(_secondsRemaining % 60).toString().padLeft(2, '0')}',
                        style: T.small.copyWith(
                          color: _secondsRemaining <= 15
                              ? Bold.danger
                              : (_secondsRemaining <= 30
                                  ? Bold.warn
                                  : Bold.brand),
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_answered > 0)
            TextButton(
              onPressed: _marking || _loading ? null : _finish,
              child: Text('Finish', style: T.small.copyWith(color: Bold.brand)),
            ),
          if (_answered > 0)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  '$_answered answered',
                  style: T.small.copyWith(color: Bold.slate),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: _body(),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Reading your notes for a question…'),
          ],
        ),
      );
    }
    if (_refused != null) {
      return _Refusal(refusal: _refused!, onBack: () => Navigator.pop(context));
    }
    if (_error != null) {
      return _Message(
        icon: Icons.cloud_off_rounded,
        title: 'The examiner could not answer',
        body: _error!,
        action: 'Try again',
        onAction: _ask,
      );
    }
    if (_result != null) {
      return _Evaluation(
        result: _result!,
        yourAnswer: _lastAnswer,
        question: _question?.text ?? '',
        onNext: _ask,
        onPress: _result!.followUpAvailable ? _press : null,
      );
    }
    return _Question(
      question: _question!,
      controller: _answer,
      marking: _marking,
      onSubmit: _submit,
      mode: widget.mode,
      secondsRemaining: _secondsRemaining,
      totalSeconds: _totalExamSeconds,
      onViewSource: _openQuestionSource,
    );
  }

  Future<void> _openQuestionSource() async {
    final question = _question;
    if (question == null || question.sourceChunkIds.isEmpty) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SourceViewerScreen(
        chunkId: question.sourceChunkIds.first,
        gapLabel: 'Evidence cited for this question',
        isQuestionSource: true,
      ),
    ));
  }
}

class _Question extends StatelessWidget {
  const _Question({
    required this.question,
    required this.controller,
    required this.marking,
    required this.onSubmit,
    required this.mode,
    required this.secondsRemaining,
    required this.totalSeconds,
    required this.onViewSource,
  });

  final VivaQuestion question;
  final TextEditingController controller;
  final bool marking;
  final VoidCallback onSubmit;
  final VivaMode mode;
  final int secondsRemaining;
  final int totalSeconds;
  final VoidCallback onViewSource;

  @override
  Widget build(BuildContext context) {
    final timerFraction = (secondsRemaining / totalSeconds).clamp(0.0, 1.0);
    final timerColor = secondsRemaining <= 15
        ? Bold.danger
        : (secondsRemaining <= 30 ? Bold.warn : Bold.brand);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        if (mode == VivaMode.examination) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Bold.wash(timerColor),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: timerColor.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.timer_outlined, size: 16, color: timerColor),
                        const SizedBox(width: 6),
                        Text(
                          'Examination Mode',
                          style: T.small.copyWith(
                              color: timerColor, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    Text(
                      '${(secondsRemaining ~/ 60).toString().padLeft(2, '0')}:${(secondsRemaining % 60).toString().padLeft(2, '0')}',
                      style: T.small.copyWith(
                        color: timerColor,
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: timerFraction,
                    minHeight: 5,
                    backgroundColor: Colors.white,
                    valueColor: AlwaysStoppedAnimation(timerColor),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ] else if (mode == VivaMode.professor) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Bold.wash(Bold.brandDeep),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(Icons.psychology_outlined,
                    size: 18, color: Bold.brandDeep),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Professor Mode · Higher difficulty floor and advanced follow-ups',
                    style: T.small.copyWith(color: Bold.brandDeep),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ] else if (mode == VivaMode.mock) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Bold.wash(Bold.good),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(Icons.groups_outlined, size: 18, color: Bold.good),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Mock Interview · Mixed technical and behavioral viva',
                    style: T.small.copyWith(color: Bold.good),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Bold.wash(Bold.brand),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(question.concept,
                  style: T.small
                      .copyWith(color: Theme.of(context).colorScheme.primary)),
            ),
            Text('Level ${question.difficulty}',
                style: T.small.copyWith(color: Bold.slate)),
          ],
        ),
        if (question.sourceChunkIds.isNotEmpty) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onViewSource,
              icon: const Icon(Icons.menu_book_outlined, size: 17),
              label: Text(
                'Read supporting passage',
                style: T.small.copyWith(color: Bold.brandDeep),
              ),
            ),
          ),
        ],
        if (question.isFollowUp) ...[
          const SizedBox(height: 14),
          // Being pressed should feel different from being asked something
          // new. Without this the student reads a harder question about the
          // same topic and assumes the examiner is repeating itself.
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Bold.wash(Bold.warn),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(Icons.subdirectory_arrow_right_rounded,
                    size: 18, color: Bold.warn),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Following up on your last answer.',
                    style: T.small.copyWith(color: Bold.warn, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 18),
        // The question is the hierarchy. No card, no border, no accent rail.
        Text(
          question.text,
          style: TextStyle(
            fontSize: 22,
            height: 1.35,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            color: Bold.ink,
          ),
        ),
        const SizedBox(height: 24),
        AnswerInput(
          controller: controller,
          onSubmit: onSubmit,
          submitting: marking,
        ),
      ],
    );
  }
}

class _Evaluation extends StatelessWidget {
  const _Evaluation({
    required this.result,
    required this.yourAnswer,
    required this.question,
    required this.onNext,
    required this.onPress,
  });

  final VivaResult result;
  final String yourAnswer;
  final String question;
  final VoidCallback onNext;

  /// Null when the examiner has nothing worth pressing on.
  final VoidCallback? onPress;

  static const _labels = {
    'concept_accuracy': 'Concept accuracy',
    'completeness': 'Completeness',
    'depth': 'Depth',
    'logical_flow': 'Logical flow',
    'technical_vocabulary': 'Technical vocabulary',
    'examples_used': 'Examples used',
  };

  @override
  Widget build(BuildContext context) {
    final (band, colour) = Bold.band(result.composite);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Bold.wash(colour),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              Text(
                '${result.composite.round()}',
                style: TextStyle(
                  fontSize: 60,
                  height: 1,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -2,
                  color: colour,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text('out of 100', style: T.small.copyWith(color: colour)),
              if (result.verdict.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(result.verdict,
                    textAlign: TextAlign.center,
                    style: T.heading.copyWith(color: Bold.ink)),
              ],
            ],
          ),
        ),
        if (result.feedback.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(result.feedback, style: T.body.copyWith(color: Bold.slate)),
        ],
        if (result.expected.isNotEmpty) ...[
          const SizedBox(height: 24),
          _Comparison(yourAnswer: yourAnswer, expected: result.expected),
        ],

        const SizedBox(height: 24),
        Text('Rubric', style: T.heading.copyWith(color: Bold.ink)),
        const SizedBox(height: 10),
        for (final entry in _labels.entries)
          _Bar(label: entry.value, value: result.rubric[entry.key] ?? 0),
        const SizedBox(height: 8),
        // Shown as unavailable with its reason rather than filled with a
        // plausible number, because a fabrication nobody notices is worse.
        Row(
          children: [
            Expanded(
              child: Text('Confidence',
                  style: T.bodyQuiet.copyWith(color: Bold.slate)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: Bold.line),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text('Needs voice',
                  style: T.small.copyWith(color: Bold.slate)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Confidence lives in how you speak, not what you write, so it is not '
          'scored from a typed answer.',
          style: T.small.copyWith(color: Bold.slate, height: 1.4),
        ),
        if (result.gaps.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('What was missing', style: T.heading.copyWith(color: Bold.ink)),
          const SizedBox(height: 10),
          for (final gap in result.gaps) _GapCard(gap: gap),
        ],
        const SizedBox(height: 24),
        if (onPress != null) ...[
          // Offered, never forced. A student who wants to move on should not
          // have to argue with the examiner.
          FilledButton(
            onPressed: onPress,
            child: const Text('The examiner wants to press on this'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: onNext,
            child: const Text('Move to a new question'),
          ),
        ] else
          FilledButton(onPressed: onNext, child: const Text('Next question')),
        const SizedBox(height: 8),
        // An assessment product must let the assessed contest the assessment.
        if (result.evaluationId.isNotEmpty)
          TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => DisputeScreen(
                evaluationId: result.evaluationId,
                score: result.composite,
                question: question,
              ),
            )),
            child: Text('I think this mark is wrong',
                style: T.small.copyWith(color: Bold.slate)),
          ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Semantics(
      label: '$label: ${value.round()} out of 100',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                    child: Text(label,
                        style: T.bodyQuiet.copyWith(color: Bold.ink))),
                const SizedBox(width: 12),
                Text('${value.round()}',
                    style: T.bodyQuiet.copyWith(
                        color: Bold.ink,
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ]),
              const SizedBox(height: 8),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: (value / 100).clamp(0, 1)),
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 650),
                curve: Curves.easeOutCubic,
                builder: (context, progress, _) => LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(4),
                  color: primary,
                  backgroundColor: Bold.line,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GapCard extends StatelessWidget {
  const _GapCard({required this.gap});

  final Gap gap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Bold.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Bold.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(gap.label, style: T.heading.copyWith(color: Bold.ink)),
          if (gap.detail.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(gap.detail, style: T.bodyQuiet.copyWith(color: Bold.slate)),
          ],
          if (gap.chunkId != null || gap.page != null) ...[
            const SizedBox(height: 12),
            // A citation chip that opens the passage. A page number the
            // student has to go and find by hand is most of the way back to
            // not citing at all (UI/UX §4.6).
            InkWell(
              onTap: gap.chunkId == null
                  ? null
                  : () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => SourceViewerScreen(
                          chunkId: gap.chunkId!,
                          gapLabel: gap.label,
                        ),
                      )),
              borderRadius: BorderRadius.circular(999),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: Bold.wash(Bold.brand),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.menu_book_rounded,
                        size: 15, color: Bold.brandDeep),
                    const SizedBox(width: 7),
                    Text(
                      gap.page == null
                          ? 'Read the passage'
                          : 'Your notes · page ${gap.page}',
                      style: T.small.copyWith(color: Bold.brandDeep),
                    ),
                    if (gap.chunkId != null) ...[
                      const SizedBox(width: 3),
                      const Icon(Icons.chevron_right_rounded,
                          size: 15, color: Bold.brandDeep),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Refusal extends StatelessWidget {
  const _Refusal({required this.refusal, required this.onBack});

  final InsufficientMaterial refusal;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return _Message(
      icon: Icons.library_books_outlined,
      title: 'Not enough to examine you on',
      body: refusal.message,
      action: 'Add more notes',
      onAction: onBack,
      footer: 'Found ${refusal.found} of ${refusal.needed} concepts needed.',
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.body,
    required this.action,
    required this.onAction,
    this.footer,
  });

  final IconData icon;
  final String title;
  final String body;
  final String action;
  final VoidCallback onAction;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: Bold.slate),
            const SizedBox(height: 16),
            Text(title, textAlign: TextAlign.center, style: T.title),
            const SizedBox(height: 8),
            Text(body,
                textAlign: TextAlign.center,
                style: T.bodyQuiet.copyWith(color: Bold.slate)),
            if (footer != null) ...[
              const SizedBox(height: 10),
              Text(footer!, style: T.small.copyWith(color: Bold.slate)),
            ],
            const SizedBox(height: 22),
            OutlinedButton(onPressed: onAction, child: Text(action)),
          ],
        ),
      ),
    );
  }
}

/// What you said, beside what a complete answer needed (UI/UX §4.6).
///
/// The expected points were decided when the question was generated, not
/// reverse-engineered from the mark, so this is a genuine comparison rather
/// than a justification written after the fact.
class _Comparison extends StatelessWidget {
  const _Comparison({required this.yourAnswer, required this.expected});

  final String yourAnswer;
  final List<String> expected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Your answer vs. what was expected',
            style: T.heading.copyWith(color: Bold.ink)),
        const SizedBox(height: 10),
        _Panel(
          title: 'You said',
          colour: Bold.slate,
          child: Text(
            yourAnswer.isEmpty ? '(nothing recorded)' : yourAnswer,
            style: T.bodyQuiet.copyWith(color: Bold.ink, height: 1.55),
          ),
        ),
        const SizedBox(height: 10),
        _Panel(
          title: 'A complete answer needed',
          colour: Bold.brandDeep,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final point in expected)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 6, right: 8),
                        child:
                            Icon(Icons.circle, size: 6, color: Bold.brandDeep),
                      ),
                      Expanded(
                        child: Text(point,
                            style: T.bodyQuiet
                                .copyWith(color: Bold.ink, height: 1.5)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.colour,
    required this.child,
  });

  final String title;
  final Color colour;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Bold.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Bold.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: T.small.copyWith(color: colour)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}
