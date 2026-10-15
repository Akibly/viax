import 'package:flutter/material.dart';

import '../../data/repository.dart';
import '../../design/bold.dart';

/// Past sittings, and what was said in them.
///
/// Every viva was already being stored and nothing showed it back. A
/// transcript is what turns a score into something revisable: a student can
/// see the answer they actually gave, not just the number it earned, and
/// compare a concept across sittings rather than only within one.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  static const _repo = Repository();
  late Future<List<PastSession>> _sessions;

  @override
  void initState() {
    super.initState();
    _sessions = _repo.sessions();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Bold.canvas,
        surfaceTintColor: Colors.transparent,
        title:
            Text('Past sittings', style: T.heading.copyWith(color: Bold.ink)),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: FutureBuilder<List<PastSession>>(
              future: _sessions,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final sessions = snap.data ?? const <PastSession>[];
                if (sessions.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.history_rounded,
                              size: 38, color: Bold.line),
                          const SizedBox(height: 16),
                          Text('No sittings yet',
                              style: T.heading.copyWith(color: Bold.ink)),
                          const SizedBox(height: 8),
                          Text(
                            'Once you answer a question, the full transcript '
                            'shows up here.',
                            textAlign: TextAlign.center,
                            style: T.small
                                .copyWith(color: Bold.slate, height: 1.55),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                  itemCount: sessions.length,
                  itemBuilder: (context, i) =>
                      _SessionTile(session: sessions[i]),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session});

  final PastSession session;

  String get _when {
    final now = DateTime.now();
    final d = session.startedAt;
    final days = DateTime(now.year, now.month, now.day)
        .difference(DateTime(d.year, d.month, d.day))
        .inDays;
    final time =
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return switch (days) {
      0 => 'Today, $time',
      1 => 'Yesterday, $time',
      < 7 => '$days days ago, $time',
      _ => '${d.day}/${d.month}/${d.year}',
    };
  }

  @override
  Widget build(BuildContext context) {
    final (band, colour) = Bold.band(session.mean);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Bold.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Bold.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        // The default divider on an ExpansionTile fights the card border.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          title: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(session.subject,
                        style: T.body.copyWith(
                            color: Bold.ink, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(
                      '$_when · ${session.answers.length} question'
                      '${session.answers.length == 1 ? '' : 's'} · ${session.mode}',
                      style: T.small.copyWith(color: Bold.slate),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${session.mean.round()}',
                      style: T.stat.copyWith(fontSize: 21, color: colour)),
                  Text(band, style: T.small.copyWith(color: colour)),
                ],
              ),
            ],
          ),
          children: [
            for (var i = 0; i < session.answers.length; i++)
              _AnswerBlock(index: i + 1, answer: session.answers[i]),
          ],
        ),
      ),
    );
  }
}

class _AnswerBlock extends StatelessWidget {
  const _AnswerBlock({required this.index, required this.answer});

  final int index;
  final PastAnswer answer;

  @override
  Widget build(BuildContext context) {
    final score = answer.score;
    final colour = score == null ? Bold.slate : Bold.band(score).$2;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Bold.canvas,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Q$index', style: T.small.copyWith(color: Bold.slate)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(answer.concept,
                    style: T.small.copyWith(color: Bold.brandDeep),
                    overflow: TextOverflow.ellipsis),
              ),
              Text(
                // An unmarked answer is not a zero; a session interrupted
                // mid-evaluation should say so rather than imply failure.
                score == null ? 'not marked' : '${score.round()}',
                style: T.small.copyWith(color: colour),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(answer.question,
              style: T.bodyQuiet.copyWith(
                  color: Bold.ink, height: 1.45, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('You said', style: T.small.copyWith(color: Bold.slate)),
          const SizedBox(height: 3),
          Text(answer.answer,
              style: T.small.copyWith(color: Bold.slate, height: 1.5)),
        ],
      ),
    );
  }
}
