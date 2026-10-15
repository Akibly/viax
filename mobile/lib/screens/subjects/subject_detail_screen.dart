import 'package:flutter/material.dart';
import '../../data/repository.dart';
import '../../design/bold.dart';
import '../study/flashcards_screen.dart';
import '../study/learn_screen.dart';
import '../study/match_game_screen.dart';
import '../study/study_models.dart';
import '../study/test_screen.dart';
import '../viva/viva_screen.dart';
import 'concept_graph_screen.dart';
import 'knowledge_base_screen.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// One subject: how ready you are, what is weakest, and what is due.
///
/// Every figure here is computed server-side from real answers. Nothing is
/// seeded, and an empty state means the work genuinely has not been done yet
/// rather than that the screen is a placeholder.
class SubjectDetailScreen extends StatefulWidget {
  const SubjectDetailScreen({super.key, required this.subject});

  final Subject subject;

  @override
  State<SubjectDetailScreen> createState() => _SubjectDetailScreenState();
}

class _SubjectDetailScreenState extends State<SubjectDetailScreen> {
  static const _repo = Repository();
  late Future<_Overview> _data;
  DateTime? _examDate;
  final Set<String> _retrying = {};

  Future<void> _retryDocument(Document document) async {
    if (!_retrying.add(document.id)) return;
    setState(() {});
    try {
      await _repo.ingest(document.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your notes are ready.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Processing did not finish. Your file is saved; see its status below.')),
      );
    } finally {
      _retrying.remove(document.id);
      if (mounted) _load();
    }
  }

  @override
  void initState() {
    super.initState();
    _examDate = widget.subject.examDate;
    _load();
  }

  void _load() {
    setState(() {
      _data = _fetch();
    });
  }

  Future<_Overview> _fetch() async {
    final results = await Future.wait([
      _repo.readiness(widget.subject.id),
      _repo.concepts(widget.subject.id),
      _repo.revision(widget.subject.id),
      _repo.documents(widget.subject.id),
    ]);
    return _Overview(
      readiness: results[0] as Readiness,
      concepts: results[1] as List<ConceptRow>,
      revision: results[2] as List<RevisionItem>,
      documents: results[3] as List<Document>,
    );
  }

  Future<void> _examine([ConceptRow? focus]) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => VivaScreen(subject: widget.subject, focusConcept: focus),
    ));
    // Mastery moves while the student is in there, so the figures behind it
    // are stale the moment they come back.
    if (mounted) _load();
  }

  /// The exam date is not decoration: the scheduler refuses to place a review
  /// after it and pulls weak concepts well inside it, so setting one changes
  /// every interval from that point on.
  Future<void> _pickExamDate() async {
    final now = DateUtils.dateOnly(DateTime.now());
    final lastDate = now.add(const Duration(days: 365));
    final existing = _examDate ?? now.add(const Duration(days: 14));
    final initialDate = existing.isBefore(now)
        ? now
        : (existing.isAfter(lastDate) ? lastDate : existing);
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: now,
      lastDate: lastDate,
      helpText: 'When is your viva?',
    );
    if (picked == null) return;
    try {
      await _repo.setExamDate(widget.subject.id, picked);
      if (!mounted) return;
      setState(() => _examDate = picked);
      _load();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Revision now compresses toward your viva.')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Bold.canvas,
        surfaceTintColor: Colors.transparent,
        title: Text(widget.subject.name, style: T.heading),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open_outlined),
            tooltip: 'Knowledge base',
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(
              builder: (_) => KnowledgeBaseScreen(subject: widget.subject),
            ))
                .then((_) {
              if (mounted) _load();
            }),
          ),
          IconButton(
            icon: const Icon(Icons.event_outlined),
            tooltip: 'Set exam date',
            onPressed: _pickExamDate,
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: FutureBuilder<_Overview>(
              future: _data,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.cloud_off_outlined,
                              color: Bold.slate, size: 36),
                          const SizedBox(height: 16),
                          Text('Could not load this subject', style: T.title),
                          const SizedBox(height: 8),
                          Text(
                              'Check your connection and try again. Your notes are still saved.',
                              textAlign: TextAlign.center,
                              style: T.bodyQuiet.copyWith(color: Bold.slate)),
                          const SizedBox(height: 20),
                          OutlinedButton.icon(
                              onPressed: _load,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Try again')),
                        ],
                      ),
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    _load();
                    await _data;
                  },
                  child: _content(snap.data!),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(_Overview data) {
    final due = data.revision
        .where((r) => r.bucket == 'today' || r.bucket == 'unscheduled')
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      children: [
        _ReadinessCard(
          readiness: data.readiness,
          examDate: _examDate,
          onSetExamDate: _pickExamDate,
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _examine,
          child: const Text('Examine me (Viva)'),
        ),
        const SizedBox(height: 16),
        _SubjectStudyModes(
          subjectName: widget.subject.name,
          subjectId: widget.subject.id,
          cards: data.concepts
              .where(
                  (concept) => concept.description?.trim().isNotEmpty == true)
              .map(StudyCard.fromConcept)
              .toList(),
        ),
        if (due.isNotEmpty) ...[
          const SizedBox(height: 28),
          Text('Due now', style: T.heading.copyWith(color: Bold.ink)),
          const SizedBox(height: 4),
          Text(
            'Scheduled by when you are likely to forget, not by a fixed ladder.',
            style: T.small.copyWith(color: Bold.slate),
          ),
          const SizedBox(height: 10),
          for (final item in due.take(4)) _DueRow(item: item),
        ],
        if (data.documents.any((d) => !d.isReady)) ...[
          const SizedBox(height: 28),
          Text('Your notes', style: T.heading.copyWith(color: Bold.ink)),
          const SizedBox(height: 10),
          // Only the ones needing attention. A ready document has nothing to
          // say, and listing it would bury the one that failed.
          for (final d in data.documents.where((d) => !d.isReady))
            _DocumentRow(
                document: d,
                retrying: _retrying.contains(d.id),
                onRetry: () => _retryDocument(d)),
        ],
        const SizedBox(height: 28),
        Row(
          children: [
            Expanded(
              child:
                  Text('Concepts', style: T.heading.copyWith(color: Bold.ink)),
            ),
            TextButton(
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(
                builder: (_) => ConceptGraphScreen(subject: widget.subject),
              ))
                  .then((_) {
                if (mounted) _load();
              }),
              child:
                  Text('See all', style: T.small.copyWith(color: Bold.brand)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          data.readiness.examinedConcepts == 0
              ? '${data.concepts.length} found in your notes. None examined yet.'
              : '${data.readiness.examinedConcepts} of ${data.concepts.length} '
                  'examined · weakest first',
          style: T.small.copyWith(color: Bold.slate),
        ),
        const SizedBox(height: 10),
        for (final c in data.concepts.take(25))
          _ConceptTile(concept: c, onPractise: () => _examine(c)),
      ]
          .animate(interval: 50.ms)
          .fade(duration: 400.ms, curve: Curves.easeOut)
          .slideY(begin: 0.1, curve: Curves.easeOutQuad),
    );
  }
}

class _Overview {
  const _Overview({
    required this.readiness,
    required this.concepts,
    required this.revision,
    required this.documents,
  });

  final Readiness readiness;
  final List<ConceptRow> concepts;
  final List<RevisionItem> revision;
  final List<Document> documents;
}

class _ReadinessCard extends StatelessWidget {
  const _ReadinessCard({
    required this.readiness,
    required this.examDate,
    required this.onSetExamDate,
  });

  final Readiness readiness;
  final DateTime? examDate;
  final VoidCallback onSetExamDate;

  @override
  Widget build(BuildContext context) {
    final score = readiness.score;
    final (band, colour) = Bold.band(score);
    final untested = readiness.totalConcepts - readiness.examinedConcepts;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Bold.brandDeep,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Viva readiness',
                  style: T.bodyQuiet.copyWith(color: Colors.white70)),
              // The word is always present, so the reading survives greyscale.
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(band, style: T.small.copyWith(color: Colors.white)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('${score.round()}', style: T.hero),
              Text('%',
                  style: T.title
                      .copyWith(color: Colors.white.withValues(alpha: 0.6))),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Stack(
              children: [
                Container(
                    height: 7, color: Colors.white.withValues(alpha: 0.22)),
                FractionallySizedBox(
                  widthFactor: (score / 100).clamp(0, 1),
                  child: Container(height: 7, color: Colors.white),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _Metric(
                value: '${readiness.coverage.round()}%',
                label: 'examined',
              ),
              _Metric(
                value: '${readiness.meanMastery.round()}%',
                label: 'mean mastery',
              ),
              if (examDate != null)
                _Metric(
                  value: '${examDate!.difference(DateTime.now()).inDays}d',
                  label: 'to viva',
                )
              else
                Expanded(
                  child: GestureDetector(
                    onTap: onSetExamDate,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Set',
                            style: T.stat
                                .copyWith(fontSize: 20, color: Colors.white)),
                        Text('exam date',
                            style: T.small.copyWith(color: Colors.white70)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          if (untested > 0) ...[
            const SizedBox(height: 14),
            Text(
              // Stated rather than hidden: an untested concept lowers this
              // number, and a student deserves to know why.
              '$untested concept${untested == 1 ? '' : 's'} never examined — '
              'that holds this figure down.',
              style: T.small.copyWith(color: Colors.white70, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: T.stat.copyWith(fontSize: 20, color: Colors.white)),
          Text(label, style: T.small.copyWith(color: Colors.white70)),
        ],
      ),
    );
  }
}

class _DueRow extends StatelessWidget {
  const _DueRow({required this.item});

  final RevisionItem item;

  @override
  Widget build(BuildContext context) {
    final (_, colour) = Bold.mastery(item.mastery);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Bold.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Bold.line),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(item.name,
                style: T.body.copyWith(color: Bold.ink),
                overflow: TextOverflow.ellipsis),
          ),
          Text('~${item.minutes} min',
              style: T.small.copyWith(color: Bold.slate)),
        ],
      ),
    );
  }
}

class _ConceptTile extends StatelessWidget {
  const _ConceptTile({required this.concept, required this.onPractise});

  final ConceptRow concept;
  final VoidCallback onPractise;

  @override
  Widget build(BuildContext context) {
    final (label, colour) = Bold.mastery(concept.mastery);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Bold.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Bold.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  concept.name,
                  style: T.body
                      .copyWith(color: Bold.ink, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Bold.wash(colour),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  concept.mastery == null
                      ? label
                      : '${concept.mastery!.round()}%',
                  style: T.small.copyWith(color: colour),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [
              'Priority ${concept.importance}/3',
              if (concept.reviews > 0)
                '${concept.reviews} review${concept.reviews == 1 ? '' : 's'}',
            ].join(' · '),
            style: T.small.copyWith(color: Bold.slate),
          ),
          if (concept.blockedBy != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.subdirectory_arrow_right_rounded,
                    size: 15, color: Bold.slate),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Held back by ${concept.blockedBy} — revise that first',
                    style: T.small.copyWith(color: Bold.brandDeep),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// A document that is still processing, or that failed.
///
/// The ingestion function records a specific reason on failure — "this looks
/// like a scan, try a PDF exported from the original" — and until now nothing
/// displayed it. A document silently stuck on "processing" is the worst
/// version of this screen.
class _DocumentRow extends StatelessWidget {
  const _DocumentRow(
      {required this.document, required this.retrying, required this.onRetry});

  final Document document;
  final bool retrying;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final failed = document.hasFailed && !retrying;
    final colour = failed ? Bold.danger : Bold.brand;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Bold.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: failed ? Bold.wash(Bold.danger) : Bold.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: failed
                ? const Icon(Icons.error_outline_rounded,
                    size: 20, color: Bold.danger)
                : const CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(document.filename,
                    style: T.body.copyWith(color: Bold.ink),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 3),
                Text(
                  retrying
                      ? 'Reading your saved notes…'
                      : failed
                          ? (document.errorMessage ?? 'Could not be read.')
                          : 'Reading — ${document.status}…',
                  style: T.small.copyWith(color: colour, height: 1.4),
                ),
                if (document.hasFailed || document.status == 'pending')
                  TextButton.icon(
                    onPressed: retrying ? null : onRetry,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: Text(retrying ? 'Processing…' : 'Retry processing'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SubjectStudyModes extends StatelessWidget {
  const _SubjectStudyModes({
    required this.subjectName,
    required this.subjectId,
    required this.cards,
  });

  final String subjectName;
  final String subjectId;
  final List<StudyCard> cards;

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Bold.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Bold.line),
        ),
        child: Text(
          'Study cards will appear after your notes finish processing. If this '
          'subject has no linked source passages, add a document with more '
          'explainable text.',
          style: T.bodyQuiet.copyWith(color: Bold.slate),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Core Study Modes',
              style: T.heading.copyWith(
                color: Bold.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Bold.wash(Bold.brand),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${cards.length} cards',
                style: T.small.copyWith(
                  color: Bold.brand,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _ModeChip(
                icon: Icons.style_outlined,
                label: 'Flashcards',
                color: Bold.brand,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => FlashcardsScreen(
                      title: subjectName,
                      cards: cards,
                      subjectId: subjectId,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _ModeChip(
                icon: Icons.auto_awesome_outlined,
                label: 'Learn',
                color: Bold.brand,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => LearnScreen(
                      title: subjectName,
                      cards: cards,
                      subjectId: subjectId,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _ModeChip(
                icon: Icons.quiz_outlined,
                label: 'Test',
                color: Bold.coral,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => TestScreen(
                      title: subjectName,
                      cards: cards,
                      subjectId: subjectId,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _ModeChip(
                icon: Icons.grid_view_rounded,
                label: 'Match',
                color: Bold.brand,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => MatchGameScreen(
                      title: subjectName,
                      cards: cards,
                      subjectId: subjectId,
                    ),
                  ),
                ),
              ),
            ].animate(interval: 40.ms).fade(duration: 300.ms).scale(
                begin: const Offset(0.8, 0.8), curve: Curves.easeOutBack),
          ),
        ),
      ],
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Bold.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Bold.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: T.body.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Bold.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
