import 'package:flutter/material.dart';

import '../../data/repository.dart';
import '../../design/bold.dart';
import '../viva/viva_screen.dart';

/// One concept, in full.
///
/// This is where the prerequisite graph finally earns its place. A score says
/// *you are weak here*; this screen says *and here is why, and here is what
/// fixing it releases*. Both directions of the edge answer different
/// questions, and a student deciding where to spend twenty minutes needs both.
class ConceptDetailScreen extends StatefulWidget {
  const ConceptDetailScreen({
    super.key,
    required this.conceptId,
    required this.subject,
  });

  final String conceptId;
  final Subject subject;

  @override
  State<ConceptDetailScreen> createState() => _ConceptDetailScreenState();
}

class _ConceptDetailScreenState extends State<ConceptDetailScreen> {
  static const _repo = Repository();
  late Future<ConceptDetail> _detail;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => setState(() {
        _detail = _repo.conceptDetail(widget.conceptId);
      });

  Future<void> _practise(String id, String name) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => VivaScreen(
        subject: widget.subject,
        focusConcept: ConceptRow(id: id, name: name, importance: 2),
      ),
    ));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Bold.canvas,
        surfaceTintColor: Colors.transparent,
        title: Text('Concept', style: T.heading.copyWith(color: Bold.ink)),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: FutureBuilder<ConceptDetail>(
              future: _detail,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('${snap.error}',
                          textAlign: TextAlign.center,
                          style: T.small.copyWith(color: Bold.slate)),
                    ),
                  );
                }
                return _content(snap.data!);
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(ConceptDetail d) {
    final (label, colour) = Bold.mastery(d.mastery);
    final blocker = d.weakestPrerequisite;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
      children: [
        Text(d.name, style: T.display.copyWith(color: Bold.ink)),
        const SizedBox(height: 6),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Bold.wash(colour),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(label, style: T.small.copyWith(color: colour)),
            ),
            const SizedBox(width: 8),
            Text('${'●' * d.importance}${'○' * (3 - d.importance)} exam weight',
                style: T.small.copyWith(color: Bold.slate)),
          ],
        ),
        if (d.description != null && d.description!.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(d.description!,
              style: T.body.copyWith(color: Bold.slate, height: 1.55)),
        ],

        const SizedBox(height: 20),
        // The diagnosis first, when there is one. It changes what the student
        // should do next more than any number on this screen.
        if (blocker != null)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Bold.wash(Bold.warn),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.trending_down_rounded,
                        size: 19, color: Bold.warn),
                    const SizedBox(width: 8),
                    Text('Held back by a prerequisite',
                        style: T.body.copyWith(
                            color: Bold.warn, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${blocker.name} sits at ${blocker.mastery!.round()}%. '
                  'Drilling ${d.name} directly will not hold while the thing '
                  'underneath it is shaky.',
                  style: T.small.copyWith(color: Bold.warn, height: 1.5),
                ),
                const SizedBox(height: 14),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Bold.warn),
                  onPressed: () => _practise(blocker.id, blocker.name),
                  child: Text('Practise ${blocker.name} first'),
                ),
              ],
            ),
          ),

        if (d.history.length >= 2) ...[
          const SizedBox(height: 22),
          Text('Mastery over time', style: T.heading.copyWith(color: Bold.ink)),
          const SizedBox(height: 4),
          Text(
            '${d.history.length} reviews'
            '${d.lapses > 0 ? ' · ${d.lapses} lapse${d.lapses == 1 ? '' : 's'}' : ''}',
            style: T.small.copyWith(color: Bold.slate),
          ),
          const SizedBox(height: 12),
          Container(
            height: 130,
            padding: const EdgeInsets.fromLTRB(8, 14, 12, 8),
            decoration: BoxDecoration(
              color: Bold.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Bold.line),
            ),
            child: CustomPaint(
              size: const Size(double.infinity, double.infinity),
              painter: _HistoryPainter(d.history),
            ),
          ),
        ],

        const SizedBox(height: 22),
        Text('Schedule', style: T.heading.copyWith(color: Bold.ink)),
        const SizedBox(height: 10),
        _Facts(detail: d),

        if (d.prerequisites.isNotEmpty) ...[
          const SizedBox(height: 22),
          Text('Depends on', style: T.heading.copyWith(color: Bold.ink)),
          const SizedBox(height: 4),
          Text('Understand these first.',
              style: T.small.copyWith(color: Bold.slate)),
          const SizedBox(height: 10),
          for (final p in d.prerequisites)
            _LinkTile(link: p, onTap: () => _open(p.id)),
        ],

        if (d.unlocks.isNotEmpty) ...[
          const SizedBox(height: 22),
          Text('Unlocks', style: T.heading.copyWith(color: Bold.ink)),
          const SizedBox(height: 4),
          Text(
            // The argument for spending time here rather than elsewhere.
            'Improving ${d.name} helps ${d.unlocks.length} other '
            'concept${d.unlocks.length == 1 ? '' : 's'}.',
            style: T.small.copyWith(color: Bold.slate),
          ),
          const SizedBox(height: 10),
          for (final u in d.unlocks)
            _LinkTile(link: u, onTap: () => _open(u.id)),
        ],

        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => _practise(d.id, d.name),
          child: Text('Practise ${d.name}'),
        ),
      ],
    );
  }

  void _open(String id) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            ConceptDetailScreen(conceptId: id, subject: widget.subject),
      ));
}

class _Facts extends StatelessWidget {
  const _Facts({required this.detail});

  final ConceptDetail detail;

  @override
  Widget build(BuildContext context) {
    String due() {
      final d = detail.dueAt;
      if (d == null) return 'not scheduled';
      final days = d.difference(DateTime.now()).inDays;
      if (days < 0) return 'overdue';
      if (days == 0) return 'today';
      if (days == 1) return 'tomorrow';
      return 'in $days days';
    }

    final rows = <(String, String)>[
      ('Next review', due()),
      (
        'Interval',
        // The scheduler's own number, shown rather than hidden: a schedule a
        // student cannot interrogate is one they will not trust.
        detail.stability == null
            ? '—'
            : '${detail.stability!.toStringAsFixed(1)} days',
      ),
      (
        'Difficulty',
        detail.difficulty == null
            ? '—'
            : '${detail.difficulty!.toStringAsFixed(1)} of 10',
      ),
      ('Reviews', '${detail.reviews}'),
      ('Lapses', '${detail.lapses}'),
    ];

    return Container(
      decoration: BoxDecoration(
        color: Bold.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Bold.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final (k, v) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                      child: Text(k, style: T.body.copyWith(color: Bold.ink))),
                  Text(v, style: T.body.copyWith(color: Bold.slate)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({required this.link, required this.onTap});

  final ConceptLink link;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (label, colour) = Bold.mastery(link.mastery);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Bold.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Bold.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration:
                    BoxDecoration(color: colour, shape: BoxShape.circle),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(link.name,
                    style: T.body.copyWith(color: Bold.ink),
                    overflow: TextOverflow.ellipsis),
              ),
              Text(
                link.mastery == null ? label : '${link.mastery!.round()}%',
                style: T.small.copyWith(color: colour),
              ),
              Icon(Icons.chevron_right_rounded, size: 18, color: Bold.slate),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mastery over time, with lapses marked.
///
/// A lapse gets its own colour because it is a different event from a low
/// score: the scheduler collapses the interval on one and not the other, and
/// a student looking at a dip deserves to know which happened.
class _HistoryPainter extends CustomPainter {
  const _HistoryPainter(this.points);

  final List<MasteryPoint> points;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 28.0;
    final w = size.width - left - 4;
    final h = size.height - 18;

    final grid = Paint()
      ..color = Bold.line
      ..strokeWidth = 1;
    for (final frac in [0.0, 0.5, 1.0]) {
      final y = h * frac;
      canvas.drawLine(Offset(left, y), Offset(left + w, y), grid);
      final label = TextPainter(
        text: TextSpan(
          text: '${(100 - frac * 100).round()}',
          style: TextStyle(fontSize: 9, color: Bold.slate),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(left - label.width - 5, y - 5));
    }

    if (points.length < 2) return;
    final step = w / (points.length - 1);
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = left + step * i;
      final y = h * (1 - (points[i].value / 100).clamp(0, 1));
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..color = Bold.brand,
    );

    for (var i = 0; i < points.length; i++) {
      final x = left + step * i;
      final y = h * (1 - (points[i].value / 100).clamp(0, 1));
      final lapse = points[i].rating == 1;
      canvas.drawCircle(
          Offset(x, y), lapse ? 4.5 : 3, Paint()..color = Colors.white);
      canvas.drawCircle(
        Offset(x, y),
        lapse ? 4.5 : 3,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = lapse ? Bold.danger : Bold.brand,
      );
    }
  }

  @override
  bool shouldRepaint(_HistoryPainter old) => old.points != points;
}
