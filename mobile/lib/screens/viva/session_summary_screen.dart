import 'package:flutter/material.dart';

import '../../data/repository.dart';
import '../../design/bold.dart';
import 'mode_picker_screen.dart';

/// The end of a sitting.
///
/// A viva that just loops back to another question has no shape — a student
/// never learns whether the session went well, only how the last answer did.
/// This is the closing report: what was asked, how it trended, and the one
/// thing to do next.
class SessionSummaryScreen extends StatelessWidget {
  const SessionSummaryScreen({
    super.key,
    required this.subject,
    required this.answers,
    required this.onPractiseWeakest,
    this.mode,
  });

  final Subject subject;

  /// Every answer given in this sitting, oldest first.
  final List<SessionAnswer> answers;
  final void Function(SessionAnswer) onPractiseWeakest;
  final VivaMode? mode;

  double get _mean => answers.isEmpty
      ? 0
      : answers.map((a) => a.score).reduce((a, b) => a + b) / answers.length;

  /// The trend within the sitting, not against all history: a student wants
  /// to know whether they warmed up, and that is a local question.
  double get _trend {
    if (answers.length < 2) return 0;
    final half = answers.length ~/ 2;
    final first = answers.take(half).map((a) => a.score);
    final last = answers.skip(answers.length - half).map((a) => a.score);
    return (last.reduce((a, b) => a + b) / half) -
        (first.reduce((a, b) => a + b) / half);
  }

  int get _totalSeconds => answers.fold(0, (sum, a) => sum + a.durationSeconds);

  int get _meanWpm {
    final paced = answers.where((a) => a.wordsPerMinute > 0).toList();
    return paced.isEmpty
        ? 0
        : (paced.map((a) => a.wordsPerMinute).reduce((a, b) => a + b) /
                paced.length)
            .round();
  }

  int get _totalFillers =>
      answers.fold(0, (sum, a) => sum + a.fillerWordsCount);

  @override
  Widget build(BuildContext context) {
    final (band, colour) = Bold.band(_mean);
    final weakest = answers.isEmpty
        ? null
        : answers.reduce((a, b) => a.score <= b.score ? a : b);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Bold.canvas,
        surfaceTintColor: Colors.transparent,
        title:
            Text('Session summary', style: T.heading.copyWith(color: Bold.ink)),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Bold.wash(colour),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Column(
                    children: [
                      if (mode != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(mode!.icon, size: 14, color: mode!.accent),
                              const SizedBox(width: 6),
                              Text(mode!.label,
                                  style: T.small.copyWith(color: mode!.accent)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      Text(
                          '${answers.length} question'
                          '${answers.length == 1 ? '' : 's'} answered',
                          style: T.small.copyWith(color: colour)),
                      const SizedBox(height: 8),
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: _mean),
                        duration: const Duration(milliseconds: 800),
                        curve: Curves.easeOutCubic,
                        builder: (context, v, _) => Text(
                          '${v.round()}',
                          style: TextStyle(
                            fontSize: 58,
                            height: 1,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -2,
                            color: colour,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                      Text('average · $band',
                          style: T.body.copyWith(color: colour)),
                      if (answers.length >= 2) ...[
                        const SizedBox(height: 12),
                        Text(
                          _trend > 3
                              ? 'You warmed up — later answers scored '
                                  '${_trend.round()} points higher.'
                              : _trend < -3
                                  ? 'You tired off — later answers dropped '
                                      '${_trend.abs().round()} points.'
                                  : 'Steady across the sitting.',
                          textAlign: TextAlign.center,
                          style: T.small.copyWith(color: colour, height: 1.45),
                        ),
                      ],
                    ],
                  ),
                ),
                if (_meanWpm > 0 || _totalFillers > 0 || _totalSeconds > 0) ...[
                  const SizedBox(height: 20),
                  _DeliveryCoachingCard(
                    meanWpm: _meanWpm,
                    totalFillers: _totalFillers,
                    totalSeconds: _totalSeconds,
                  ),
                ],
                const SizedBox(height: 24),
                Text('What you were asked',
                    style: T.heading.copyWith(color: Bold.ink)),
                const SizedBox(height: 10),
                for (var i = 0; i < answers.length; i++)
                  _AnswerRow(index: i + 1, answer: answers[i]),
                if (weakest != null) ...[
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Bold.card,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Bold.line),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Do this next',
                            style: T.heading.copyWith(color: Bold.ink)),
                        const SizedBox(height: 6),
                        Text(
                          '${weakest.concept} was your weakest at '
                          '${weakest.score.round()}. Practising it directly is '
                          'worth more than another mixed round.',
                          style:
                              T.small.copyWith(color: Bold.slate, height: 1.5),
                        ),
                        const SizedBox(height: 14),
                        FilledButton(
                          onPressed: () => onPractiseWeakest(weakest),
                          child: Text('Practise ${weakest.concept}'),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Done'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DeliveryCoachingCard extends StatelessWidget {
  const _DeliveryCoachingCard({
    required this.meanWpm,
    required this.totalFillers,
    required this.totalSeconds,
  });

  final int meanWpm;
  final int totalFillers;
  final int totalSeconds;

  @override
  Widget build(BuildContext context) {
    final String cadenceLabel;
    final Color cadenceColour;
    if (meanWpm == 0) {
      cadenceLabel = 'Unmeasured';
      cadenceColour = Bold.slate;
    } else if (meanWpm < 110) {
      cadenceLabel = 'Deliberate';
      cadenceColour = Bold.warn;
    } else if (meanWpm <= 160) {
      cadenceLabel = 'Ideal pace';
      cadenceColour = Bold.good;
    } else {
      cadenceLabel = 'Brisk';
      cadenceColour = Bold.warn;
    }

    final String fillerTip;
    if (totalFillers == 0) {
      fillerTip = 'Crisp & direct — zero filler words detected.';
    } else if (totalFillers <= 2) {
      fillerTip = 'Clean delivery with minimal hesitation.';
    } else {
      fillerTip =
          'Try replacing filler words ("um", "like") with brief pauses.';
    }

    final durationFormatted = totalSeconds < 60
        ? '${totalSeconds}s'
        : '${totalSeconds ~/ 60}m ${totalSeconds % 60}s';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Bold.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Bold.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Bold.wash(Bold.brand),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.graphic_eq_rounded,
                    size: 18, color: Bold.brand),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Delivery & Speech Coaching',
                        style:
                            T.heading.copyWith(fontSize: 15, color: Bold.ink)),
                    Text('Pacing and clarity during viva responses',
                        style: T.small.copyWith(color: Bold.slate)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _MetricTile(
                  label: 'Cadence',
                  value: meanWpm > 0 ? '$meanWpm WPM' : '—',
                  badge: cadenceLabel,
                  badgeColour: cadenceColour,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricTile(
                  label: 'Filler words',
                  value: '$totalFillers',
                  badge: totalFillers == 0 ? 'Clear' : '$totalFillers detected',
                  badgeColour: totalFillers == 0 ? Bold.good : Bold.warn,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricTile(
                  label: 'Speak time',
                  value: durationFormatted,
                  badge: 'Total',
                  badgeColour: Bold.slate,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Bold.canvas,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.tips_and_updates_outlined,
                    size: 15, color: Bold.brand),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    fillerTip,
                    style: T.small.copyWith(color: Bold.ink, height: 1.35),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.badge,
    required this.badgeColour,
  });

  final String label;
  final String value;
  final String badge;
  final Color badgeColour;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Bold.canvas,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Bold.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: T.small.copyWith(color: Bold.slate, fontSize: 11)),
          const SizedBox(height: 4),
          Text(value,
              style: T.body
                  .copyWith(color: Bold.ink, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Bold.wash(badgeColour),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              badge,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: badgeColour,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnswerRow extends StatelessWidget {
  const _AnswerRow({required this.index, required this.answer});

  final int index;
  final SessionAnswer answer;

  @override
  Widget build(BuildContext context) {
    final (_, colour) = Bold.band(answer.score);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Bold.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Bold.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: Bold.canvas,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text('$index', style: T.small.copyWith(color: Bold.slate)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(answer.concept,
                    style: T.body.copyWith(
                        color: Bold.ink, fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(answer.question,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: T.small.copyWith(color: Bold.slate, height: 1.4)),
                if (answer.wordsPerMinute > 0 ||
                    answer.fillerWordsCount > 0 ||
                    answer.durationSeconds > 0) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (answer.durationSeconds > 0)
                        _Pill(
                          icon: Icons.timer_outlined,
                          label: '${answer.durationSeconds}s',
                          colour: Bold.slate,
                        ),
                      if (answer.wordsPerMinute > 0)
                        _Pill(
                          icon: Icons.speed_rounded,
                          label: '${answer.wordsPerMinute} WPM',
                          colour: Bold.brand,
                        ),
                      if (answer.fillerWordsCount > 0)
                        _Pill(
                          icon: Icons.chat_bubble_outline_rounded,
                          label:
                              '${answer.fillerWordsCount} filler${answer.fillerWordsCount == 1 ? '' : 's'}',
                          colour: Bold.warn,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text('${answer.score.round()}',
              style: T.stat.copyWith(fontSize: 19, color: colour)),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.icon,
    required this.label,
    required this.colour,
  });

  final IconData icon;
  final String label;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Bold.wash(colour),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: colour),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: colour,
            ),
          ),
        ],
      ),
    );
  }
}

/// One answered question inside a sitting.
@immutable
class SessionAnswer {
  const SessionAnswer({
    required this.questionId,
    required this.conceptId,
    required this.concept,
    required this.question,
    required this.score,
    this.durationSeconds = 0,
    this.wordsPerMinute = 0,
    this.fillerWordsCount = 0,
  });

  final String questionId;
  final String conceptId;
  final String concept;
  final String question;
  final double score;
  final int durationSeconds;
  final int wordsPerMinute;
  final int fillerWordsCount;
}
