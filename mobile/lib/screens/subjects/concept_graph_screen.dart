import 'package:flutter/material.dart';

import '../../data/repository.dart';
import '../../design/bold.dart';
import '../viva/viva_screen.dart';
import 'concept_detail_screen.dart';

/// The Concept Mastery Graph, full screen (UI/UX §4.7).
///
/// Tappable per-concept bars; tapping a weak concept jumps straight into a
/// focused practice viva on that concept alone — the PRD's own success metric
/// is a one-tap flow with no dead ends, and this is that tap.
///
/// Bars rather than the radar chart the guide suggests: with twenty-plus
/// concepts a radar's labels collide and its shape carries no ordering, while
/// a ranked list answers the only question a student actually has — *what do
/// I fix first?*
class ConceptGraphScreen extends StatefulWidget {
  const ConceptGraphScreen({super.key, required this.subject});

  final Subject subject;

  @override
  State<ConceptGraphScreen> createState() => _ConceptGraphScreenState();
}

class _ConceptGraphScreenState extends State<ConceptGraphScreen> {
  static const _repo = Repository();
  late Future<List<ConceptRow>> _concepts;
  _Filter _filter = _Filter.all;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _concepts = _repo.concepts(widget.subject.id);
    });
  }

  Future<void> _details(ConceptRow concept) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ConceptDetailScreen(
        conceptId: concept.id,
        subject: widget.subject,
      ),
    ));
    if (mounted) _load();
  }

  Future<void> _practise(ConceptRow concept) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) =>
          VivaScreen(subject: widget.subject, focusConcept: concept),
    ));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Bold.canvas,
        surfaceTintColor: Colors.transparent,
        title:
            Text('Concept mastery', style: T.heading.copyWith(color: Bold.ink)),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: FutureBuilder<List<ConceptRow>>(
              future: _concepts,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final all = snap.data ?? const <ConceptRow>[];
                if (all.isEmpty) {
                  return const _Empty();
                }
                final shown = all.where(_filter.matches).toList();

                return RefreshIndicator(
                  onRefresh: () async => _load(),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                    children: [
                      _Distribution(
                          concepts: all, subjectName: widget.subject.name),
                      const SizedBox(height: 18),
                      SizedBox(
                        height: 36,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _Filter.values.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (context, i) {
                            final f = _Filter.values[i];
                            final count = all.where(f.matches).length;
                            return ChoiceChip(
                              label: Text('${f.label} ($count)'),
                              selected: _filter == f,
                              onSelected: (_) => setState(() => _filter = f),
                              backgroundColor: Bold.card,
                              selectedColor: Bold.wash(Bold.brand),
                              showCheckmark: false,
                              side: BorderSide(
                                  color: _filter == f ? Bold.brand : Bold.line),
                              labelStyle: T.small.copyWith(
                                color:
                                    _filter == f ? Bold.brandDeep : Bold.slate,
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (shown.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Text('Nothing in this band.',
                              textAlign: TextAlign.center,
                              style: T.body.copyWith(color: Bold.slate)),
                        )
                      else
                        for (final c in shown)
                          _ConceptBar(
                            concept: c,
                            onTap: () => _practise(c),
                            onDetails: () => _details(c),
                          ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

enum _Filter {
  all('All'),
  critical('Critical'),
  weak('Needs work'),
  strong('Strong'),
  untested('Not examined');

  const _Filter(this.label);
  final String label;

  bool matches(ConceptRow c) => switch (this) {
        _Filter.all => true,
        _Filter.untested => c.mastery == null,
        _Filter.critical => c.mastery != null && c.mastery! < 35,
        _Filter.weak =>
          c.mastery != null && c.mastery! >= 35 && c.mastery! < 75,
        _Filter.strong => c.mastery != null && c.mastery! >= 75,
      };
}

/// The one hero visual on this screen (UI/UX §2: one per screen).
///
/// A stacked band rather than five separate numbers: the question is what
/// proportion of the syllabus is in trouble, and a proportion is a shape.
class _Distribution extends StatelessWidget {
  const _Distribution({required this.concepts, required this.subjectName});

  final List<ConceptRow> concepts;
  final String subjectName;

  @override
  Widget build(BuildContext context) {
    final total = concepts.length;
    int count(bool Function(ConceptRow) p) => concepts.where(p).length;

    final bands = <(String, int, Color)>[
      (
        'Strong',
        count((c) => c.mastery != null && c.mastery! >= 75),
        Bold.good
      ),
      (
        'Needs work',
        count((c) => c.mastery != null && c.mastery! >= 35 && c.mastery! < 75),
        Bold.warn
      ),
      (
        'Critical',
        count((c) => c.mastery != null && c.mastery! < 35),
        Bold.danger
      ),
      ('Not examined', count((c) => c.mastery == null), Bold.line),
    ];
    final examined = total - bands.last.$2;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Bold.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Bold.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('$total',
                  style: T.stat.copyWith(color: Bold.ink, fontSize: 34)),
              const SizedBox(width: 8),
              Text('concepts in $subjectName',
                  style: T.body.copyWith(color: Bold.slate)),
            ],
          ),
          const SizedBox(height: 4),
          Text('$examined examined so far',
              style: T.small.copyWith(color: Bold.slate)),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: SizedBox(
              height: 10,
              child: Row(
                children: [
                  for (final (_, n, colour) in bands)
                    if (n > 0)
                      Expanded(flex: n, child: Container(color: colour)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              for (final (label, n, colour) in bands)
                if (n > 0)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                            color: colour, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      // The word is always present, so the split reads without
                      // relying on colour alone (UI/UX §5).
                      Text('$label $n',
                          style: T.small.copyWith(color: Bold.slate)),
                    ],
                  ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConceptBar extends StatelessWidget {
  const _ConceptBar({
    required this.concept,
    required this.onTap,
    required this.onDetails,
  });

  final ConceptRow concept;
  final VoidCallback onTap;

  /// Opens the concept in full. Kept off the main tap target so the PRD's
  /// one-tap route into practice stays exactly one tap.
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    final (label, colour) = Bold.mastery(concept.mastery);
    final untested = concept.mastery == null;

    return Semantics(
      button: true,
      label: untested
          ? '${concept.name}, not yet examined. Practise this concept.'
          : '${concept.name}, ${concept.mastery!.round()} percent, $label.'
              '${concept.blockedBy != null ? ' Held back by ${concept.blockedBy}.' : ''}'
              ' Practise this concept.',
      child: ExcludeSemantics(
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: Bold.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Bold.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(concept.name,
                            style: T.body.copyWith(
                                color: Bold.ink, fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        untested ? '—' : '${concept.mastery!.round()}%',
                        style: T.stat.copyWith(
                            fontSize: 19,
                            color: untested ? Bold.slate : colour),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // The bar reveals rather than snapping: "earn the feedback".
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      height: 7,
                      child: Stack(
                        children: [
                          Container(color: Bold.canvas),
                          if (!untested)
                            TweenAnimationBuilder<double>(
                              tween: Tween(
                                  begin: 0,
                                  end: (concept.mastery! / 100).clamp(0, 1)),
                              duration: const Duration(milliseconds: 700),
                              curve: Curves.easeOutCubic,
                              builder: (context, v, _) => FractionallySizedBox(
                                widthFactor: v,
                                child: Container(color: colour),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text(
                        [
                          label,
                          if (concept.reviews > 0)
                            '${concept.reviews} review'
                                '${concept.reviews == 1 ? '' : 's'}',
                        ].join(' · '),
                        style: T.small.copyWith(color: Bold.slate),
                      ),
                      const Spacer(),
                      InkWell(
                        onTap: onDetails,
                        borderRadius: BorderRadius.circular(999),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          child: Text('Details',
                              style: T.small.copyWith(color: Bold.slate)),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text('Practise',
                          style: T.small.copyWith(color: Bold.brand)),
                      const Icon(Icons.chevron_right_rounded,
                          size: 16, color: Bold.brand),
                    ],
                  ),
                  if (concept.blockedBy != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Bold.wash(Bold.brand),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.subdirectory_arrow_right_rounded,
                              size: 15, color: Bold.brandDeep),
                          const SizedBox(width: 8),
                          Expanded(
                            // The diagnosis rather than the score. This needs
                            // the prerequisite graph, which is why the schema
                            // carries one.
                            child: Text(
                              'Held back by ${concept.blockedBy} — revise that first',
                              style: T.small.copyWith(color: Bold.brandDeep),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_tree_outlined, size: 40, color: Bold.line),
            const SizedBox(height: 16),
            Text('No concepts yet', style: T.heading.copyWith(color: Bold.ink)),
            const SizedBox(height: 8),
            Text(
              'Upload notes for this subject and ViaX will map the concepts '
              'inside them, including which ones depend on which.',
              textAlign: TextAlign.center,
              style: T.small.copyWith(color: Bold.slate, height: 1.55),
            ),
          ],
        ),
      ),
    );
  }
}
