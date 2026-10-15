import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/repository.dart';
import '../../design/bold.dart';
import 'history_screen.dart';

/// Progress: analytics, revision plan, and achievements (UI/UX §4.8–4.10).
///
/// Three tabs rather than three screens, because they answer one question
/// between them — *am I getting better, and what do I do next* — and a
/// student comparing them should not have to navigate.
class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen>
    with SingleTickerProviderStateMixin {
  static const _repo = Repository();
  late final TabController _tabs = TabController(length: 3, vsync: this);
  late Future<_ProgressData> _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _load() {
    setState(() {
      _data = () async {
        final subjects = await _repo.subjects();
        final analytics = await _repo.analytics();
        final revision = <RevisionItem>[];
        for (final s in subjects) {
          revision.addAll(await _repo.revision(s.id));
        }
        return _ProgressData(
          analytics: analytics,
          revision: revision,
          subjects: subjects,
        );
      }();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('Progress',
                            style: T.display.copyWith(color: Bold.ink)),
                      ),
                      IconButton(
                        icon: Icon(Icons.history_rounded, color: Bold.slate),
                        tooltip: 'Past sittings',
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const HistoryScreen()),
                        ),
                      ),
                    ],
                  ),
                ),
                TabBar(
                  controller: _tabs,
                  labelColor: Bold.brandDeep,
                  unselectedLabelColor: Bold.slate,
                  indicatorColor: Bold.brand,
                  labelStyle: T.body.copyWith(fontWeight: FontWeight.w700),
                  tabs: const [
                    Tab(text: 'Revision'),
                    Tab(text: 'Analytics'),
                    Tab(text: 'Achievements'),
                  ],
                ),
                Expanded(
                  child: FutureBuilder<_ProgressData>(
                    future: _data,
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
                      final d = snap.data!;
                      return TabBarView(
                        controller: _tabs,
                        children: [
                          _RevisionTab(items: d.revision),
                          _AnalyticsTab(analytics: d.analytics),
                          _AchievementsTab(
                              analytics: d.analytics, subjects: d.subjects),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProgressData {
  const _ProgressData({
    required this.analytics,
    required this.revision,
    required this.subjects,
  });

  final Analytics analytics;
  final List<RevisionItem> revision;
  final List<Subject> subjects;
}

/// Four buckets — Today / Tomorrow / Weekend / Before Exam (UI/UX §4.8).
///
/// These are *views over a due date*, not stored categories. That is the fix
/// for the original enum design: "today" computed from a date is still right
/// tomorrow, whereas a stored bucket silently rots.
class _RevisionTab extends StatefulWidget {
  const _RevisionTab({required this.items});

  final List<RevisionItem> items;

  @override
  State<_RevisionTab> createState() => _RevisionTabState();
}

class _RevisionTabState extends State<_RevisionTab> {
  final _done = <String>{};
  int _bucket = 0;

  static const _buckets = ['today', 'tomorrow', 'this_week', 'before_exam'];
  static const _labels = ['Today', 'Tomorrow', 'This week', 'Before exam'];

  @override
  Widget build(BuildContext context) {
    final wanted = _buckets[_bucket];
    final items = widget.items.where((r) {
      if (wanted == 'today') {
        return r.bucket == 'today' || r.bucket == 'unscheduled';
      }
      return r.bucket == wanted;
    }).toList();
    final remaining = items.where((r) => !_done.contains(r.conceptId)).toList();
    final minutes = remaining.fold<int>(0, (a, r) => a + r.minutes);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      children: [
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _labels.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) => ChoiceChip(
              label: Text(_labels[i]),
              selected: _bucket == i,
              onSelected: (_) => setState(() => _bucket = i),
              selectedColor: Bold.wash(Bold.brand),
              backgroundColor: Bold.card,
              showCheckmark: false,
              side: BorderSide(color: _bucket == i ? Bold.brand : Bold.line),
              labelStyle: T.small.copyWith(
                color: _bucket == i ? Bold.brandDeep : Bold.slate,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (items.isEmpty)
          _Empty(
            icon: Icons.event_available_outlined,
            title: 'Nothing scheduled',
            body: _bucket == 0
                ? 'Answer some questions and the scheduler will start planning '
                    'your revision around when you are likely to forget.'
                : 'Nothing falls in this window yet.',
          )
        else ...[
          Text(
            remaining.isEmpty
                ? 'All done for now.'
                : '${remaining.length} left · about $minutes minutes',
            style: T.small.copyWith(color: Bold.slate),
          ),
          const SizedBox(height: 12),
          for (final item in items)
            _RevisionRow(
              item: item,
              done: _done.contains(item.conceptId),
              onToggle: () => setState(() {
                if (!_done.remove(item.conceptId)) _done.add(item.conceptId);
              }),
            ),
          const SizedBox(height: 14),
          Text(
            // The interval is shown because a schedule a student cannot
            // interrogate is one they will not trust.
            'Intervals come from your own review history: answer well and an '
            'item moves further out, miss it and it returns sooner.',
            style: T.small.copyWith(color: Bold.slate, height: 1.5),
          ),
        ],
      ],
    );
  }
}

class _RevisionRow extends StatelessWidget {
  const _RevisionRow({
    required this.item,
    required this.done,
    required this.onToggle,
  });

  final RevisionItem item;
  final bool done;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final (label, colour) = Bold.mastery(item.mastery);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Bold.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Bold.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(
                done ? Icons.check_circle_rounded : Icons.circle_outlined,
                size: 22,
                color: done ? Bold.good : Bold.line,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: T.body.copyWith(
                        color: done ? Bold.slate : Bold.ink,
                        decoration: done ? TextDecoration.lineThrough : null,
                        decorationColor: Bold.slate,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text('$label · ~${item.minutes} min',
                        style: T.small.copyWith(color: colour)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnalyticsTab extends StatelessWidget {
  const _AnalyticsTab({required this.analytics});

  final Analytics analytics;

  @override
  Widget build(BuildContext context) {
    if (analytics.questionsAnswered == 0) {
      return const _Empty(
        icon: Icons.insights_outlined,
        title: 'No data yet',
        body: 'Answer a few questions and your improvement curve will appear '
            'here — measured against your own start, not a cohort.',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      children: [
        Text('Improvement curve', style: T.heading.copyWith(color: Bold.ink)),
        const SizedBox(height: 4),
        Text(
          analytics.scores.length < 3
              ? 'Needs a few more answers before a trend means anything.'
              : analytics.improvement >= 0
                  ? 'Up ${analytics.improvement.round()} points since you started.'
                  : 'Down ${analytics.improvement.abs().round()} points — the '
                      'questions may be getting harder.',
          style: T.small.copyWith(color: Bold.slate),
        ),
        const SizedBox(height: 14),
        Container(
          height: 170,
          padding: const EdgeInsets.fromLTRB(8, 16, 12, 8),
          decoration: BoxDecoration(
            color: Bold.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Bold.line),
          ),
          child: CustomPaint(
            size: const Size(double.infinity, double.infinity),
            painter: _CurvePainter(analytics.scores),
          ),
        ),
        const SizedBox(height: 22),
        Text('Activity', style: T.heading.copyWith(color: Bold.ink)),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.7,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          children: [
            _Stat(
                value: '${analytics.questionsAnswered}',
                label: 'questions answered'),
            _Stat(value: '${analytics.meanScore.round()}', label: 'mean score'),
            _Stat(value: '${analytics.reviewsLogged}', label: 'reviews logged'),
            _Stat(
              value: '${analytics.lapses}',
              label: 'lapses',
              // A lapse is not a failure to hide; it is what the scheduler
              // uses to bring a concept back sooner.
              colour: analytics.lapses > 0 ? Bold.warn : Bold.good,
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text('Study consistency', style: T.heading.copyWith(color: Bold.ink)),
        const SizedBox(height: 4),
        Text(
          'Daily review density across the past 12 weeks.',
          style: T.small.copyWith(color: Bold.slate),
        ),
        const SizedBox(height: 12),
        _ConsistencyHeatmap(reviewDates: analytics.reviewDates),
      ],
    );
  }
}

/// The improvement curve, drawn to a scale with labelled bounds.
class _CurvePainter extends CustomPainter {
  const _CurvePainter(this.scores);

  final List<double> scores;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 30.0;
    final w = size.width - left - 4;
    final h = size.height - 22;

    final grid = Paint()
      ..color = Bold.line
      ..strokeWidth = 1;
    for (final frac in [0.0, 0.5, 1.0]) {
      final y = h * frac;
      canvas.drawLine(Offset(left, y), Offset(left + w, y), grid);
      final label = TextPainter(
        text: TextSpan(
          text: '${(100 - frac * 100).round()}',
          style: TextStyle(fontSize: 10, color: Bold.slate),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(left - label.width - 6, y - 6));
    }

    if (scores.isEmpty) return;
    final step = scores.length == 1 ? 0.0 : w / (scores.length - 1);
    final path = Path();
    for (var i = 0; i < scores.length; i++) {
      final x = left + step * i;
      final y = h * (1 - (scores[i] / 100).clamp(0, 1));
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }

    final fill = Path.from(path)
      ..lineTo(left + step * (scores.length - 1), h)
      ..lineTo(left, h)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Bold.brand.withValues(alpha: 0.25),
            Bold.brand.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(left, 0, w, h)),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..color = Bold.brand,
    );

    // The most recent point is emphasised: it is the one the student is
    // actually asking about.
    final lastX = left + step * (scores.length - 1);
    final lastY = h * (1 - (scores.last / 100).clamp(0, 1));
    canvas.drawCircle(Offset(lastX, lastY), 5, Paint()..color = Colors.white);
    canvas.drawCircle(
      Offset(lastX, lastY),
      5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = Bold.brand,
    );
  }

  @override
  bool shouldRepaint(covariant _CurvePainter old) => old.scores != scores;
}

class _ConsistencyHeatmap extends StatelessWidget {
  const _ConsistencyHeatmap({required this.reviewDates});

  final List<DateTime> reviewDates;

  @override
  Widget build(BuildContext context) {
    // Bucket dates by YYYY-MM-DD
    final counts = <String, int>{};
    for (final d in reviewDates) {
      final key =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      counts[key] = (counts[key] ?? 0) + 1;
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // 12 weeks: 12 columns x 7 rows (Mon=1 ... Sun=7)
    final currentWeekday = today.weekday;
    final startOfCurrentWeek =
        today.subtract(Duration(days: currentWeekday - 1));
    final startDate = startOfCurrentWeek.subtract(const Duration(days: 11 * 7));

    // Calculate streak
    var streak = 0;
    var checkDate = today;
    final todayKey =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final hasToday = (counts[todayKey] ?? 0) > 0;
    if (!hasToday) {
      checkDate = today.subtract(const Duration(days: 1));
    }
    while (true) {
      final key =
          '${checkDate.year}-${checkDate.month.toString().padLeft(2, '0')}-${checkDate.day.toString().padLeft(2, '0')}';
      if ((counts[key] ?? 0) > 0) {
        streak++;
        checkDate = checkDate.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }

    final activeDays = counts.values.where((c) => c > 0).length;
    const weekDays = ['M', '', 'W', '', 'F', '', 'S'];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Bold.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Bold.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: streak > 0
                          ? Bold.wash(Bold.brand)
                          : Bold.wash(Bold.slate),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.local_fire_department_rounded,
                          size: 14,
                          color: streak > 0 ? Bold.brand : Bold.slate,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$streak day streak',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: streak > 0 ? Bold.brand : Bold.slate,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$activeDays active days',
                    style: T.small.copyWith(color: Bold.slate),
                  ),
                ],
              ),
              Row(
                children: [
                  Text('Less',
                      style: T.small.copyWith(fontSize: 10, color: Bold.slate)),
                  const SizedBox(width: 4),
                  const _HeatBox(level: 0),
                  const SizedBox(width: 2),
                  const _HeatBox(level: 1),
                  const SizedBox(width: 2),
                  const _HeatBox(level: 2),
                  const SizedBox(width: 2),
                  const _HeatBox(level: 3),
                  const SizedBox(width: 4),
                  Text('More',
                      style: T.small.copyWith(fontSize: 10, color: Bold.slate)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    for (var r = 0; r < 7; r++)
                      Container(
                        height: 14,
                        margin: const EdgeInsets.symmetric(vertical: 2),
                        alignment: Alignment.centerLeft,
                        child: Text(
                          weekDays[r],
                          style: TextStyle(
                              fontSize: 9, color: Bold.slate, height: 1),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 6),
                for (var w = 0; w < 12; w++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Column(
                      children: [
                        for (var d = 0; d < 7; d++)
                          _DayCell(
                            date: startDate.add(Duration(days: w * 7 + d)),
                            today: today,
                            count: counts[
                                    '${startDate.add(Duration(days: w * 7 + d)).year}-${startDate.add(Duration(days: w * 7 + d)).month.toString().padLeft(2, '0')}-${startDate.add(Duration(days: w * 7 + d)).day.toString().padLeft(2, '0')}'] ??
                                0,
                          ),
                      ],
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

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.today,
    required this.count,
  });

  final DateTime date;
  final DateTime today;
  final int count;

  @override
  Widget build(BuildContext context) {
    final isFuture = date.isAfter(today);
    final isToday = date.year == today.year &&
        date.month == today.month &&
        date.day == today.day;

    final Color color;
    if (isFuture) {
      color = Colors.transparent;
    } else if (count == 0) {
      color = Bold.canvas;
    } else if (count == 1) {
      color = Bold.brand.withValues(alpha: 0.35);
    } else if (count <= 3) {
      color = Bold.brand.withValues(alpha: 0.65);
    } else {
      color = Bold.brand;
    }

    final dateStr = '${date.month}/${date.day}';
    final tooltipText = isFuture
        ? ''
        : count == 0
            ? 'No activity on $dateStr'
            : '$count ${count == 1 ? 'activity' : 'activities'} on $dateStr';

    return Tooltip(
      message: tooltipText,
      child: Container(
        width: 14,
        height: 14,
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
          border: isToday
              ? Border.all(color: Bold.brand, width: 1.5)
              : isFuture
                  ? null
                  : Border.all(
                      color: Bold.line.withValues(alpha: 0.6), width: 0.8),
        ),
      ),
    );
  }
}

class _HeatBox extends StatelessWidget {
  const _HeatBox({required this.level});

  final int level;

  @override
  Widget build(BuildContext context) {
    final Color color;
    switch (level) {
      case 1:
        color = Bold.brand.withValues(alpha: 0.35);
        break;
      case 2:
        color = Bold.brand.withValues(alpha: 0.65);
        break;
      case 3:
        color = Bold.brand;
        break;
      default:
        color = Bold.canvas;
    }

    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: Bold.line, width: 0.6),
      ),
    );
  }
}

class _AchievementsTab extends StatelessWidget {
  const _AchievementsTab({required this.analytics, required this.subjects});

  final Analytics analytics;
  final List<Subject> subjects;

  @override
  Widget build(BuildContext context) {
    // XP is derived, never stored: it is a view of real work, so it cannot
    // drift out of step with what the student actually did.
    final xp = analytics.questionsAnswered * 10 + analytics.reviewsLogged * 5;
    final level = math.max(1, (xp / 250).floor() + 1);
    final intoLevel = (xp % 250) / 250;

    final badges = <(String, String, bool, IconData)>[
      (
        'First viva',
        'Answer your first question',
        analytics.questionsAnswered >= 1,
        Icons.flag_outlined
      ),
      (
        'Getting serious',
        'Answer 25 questions',
        analytics.questionsAnswered >= 25,
        Icons.forum_outlined
      ),
      (
        'Well read',
        'Build a subject with 10+ concepts',
        subjects.any((s) => s.conceptCount >= 10),
        Icons.menu_book_outlined
      ),
      (
        'Consistent',
        'Log 20 reviews',
        analytics.reviewsLogged >= 20,
        Icons.repeat_rounded
      ),
      (
        'Improving',
        'Raise your mean score by 10 points',
        analytics.improvement >= 10,
        Icons.trending_up_rounded
      ),
      (
        'Distinction',
        'Score 85 or more on an answer',
        analytics.scores.any((s) => s >= 85),
        Icons.workspace_premium_outlined
      ),
    ];
    final earned = badges.where((b) => b.$3).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Bold.brandDeep,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Level $level',
                      style: T.title.copyWith(color: Colors.white)),
                  Text('$xp XP', style: T.body.copyWith(color: Colors.white70)),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Stack(
                  children: [
                    Container(
                        height: 7, color: Colors.white.withValues(alpha: 0.25)),
                    FractionallySizedBox(
                      widthFactor: intoLevel,
                      child: Container(height: 7, color: Colors.white),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text('${250 - (xp % 250)} XP to level ${level + 1}',
                  style: T.small.copyWith(color: Colors.white70)),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            Expanded(
                child:
                    Text('Badges', style: T.heading.copyWith(color: Bold.ink))),
            Text('$earned of ${badges.length}',
                style: T.small.copyWith(color: Bold.slate)),
          ],
        ),
        const SizedBox(height: 12),
        for (final (name, how, unlocked, icon) in badges)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Bold.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: unlocked ? Bold.wash(Bold.good) : Bold.line),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: unlocked ? Bold.wash(Bold.good) : Bold.canvas,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon,
                      size: 21, color: unlocked ? Bold.good : Bold.line),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: T.body.copyWith(
                            color: unlocked ? Bold.ink : Bold.slate,
                            fontWeight: FontWeight.w700,
                          )),
                      const SizedBox(height: 2),
                      // The criterion is always visible, locked or not: a
                      // badge you cannot work toward is decoration.
                      Text(how, style: T.small.copyWith(color: Bold.slate)),
                    ],
                  ),
                ),
                if (unlocked)
                  const Icon(Icons.check_circle_rounded,
                      color: Bold.good, size: 20),
              ],
            ),
          ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.colour});

  final String value;
  final String label;
  final Color? colour;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Bold.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Bold.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(value, style: T.stat.copyWith(color: colour ?? Bold.ink)),
          const SizedBox(height: 4),
          Text(label, style: T.small.copyWith(color: Bold.slate)),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 38, color: Bold.line),
            const SizedBox(height: 16),
            Text(title, style: T.heading.copyWith(color: Bold.ink)),
            const SizedBox(height: 8),
            Text(body,
                textAlign: TextAlign.center,
                style: T.small.copyWith(color: Bold.slate, height: 1.55)),
          ],
        ),
      ),
    );
  }
}
