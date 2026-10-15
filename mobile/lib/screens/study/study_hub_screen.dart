import 'package:flutter/material.dart';

import '../../data/repository.dart';
import '../../design/bold.dart';
import 'flashcards_screen.dart';
import 'learn_screen.dart';
import 'match_game_screen.dart';
import 'study_models.dart';
import 'test_screen.dart';

enum _StudyScope { smart, due, weak, starred, all }

enum _StudyMode { flashcards, learn, test, match }

class StudyHubScreen extends StatefulWidget {
  const StudyHubScreen({super.key, this.onChanged, this.onOpenLibrary});

  final VoidCallback? onChanged;
  final VoidCallback? onOpenLibrary;

  @override
  State<StudyHubScreen> createState() => _StudyHubScreenState();
}

class _StudyHubScreenState extends State<StudyHubScreen> {
  static const _repo = Repository();
  late Future<_StudyData> _data;
  final _search = TextEditingController();
  String? _subjectId;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _data = _fetch();
    _search.addListener(() {
      final next = _search.text.trim().toLowerCase();
      if (next != _query) setState(() => _query = next);
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _load() {
    setState(() {
      _data = _fetch();
    });
  }

  Future<_StudyData> _fetch() async {
    final subjects = await _repo.subjects();
    final preferencesFuture = _repo.studyPreferences();
    final starsFuture = _repo.starredConceptIds();
    final dueFuture = _repo.dueConcepts();
    final conceptLists = await Future.wait([
      for (final subject in subjects) _repo.concepts(subject.id),
    ]);
    return _StudyData(
      subjects: subjects,
      concepts: {
        for (var i = 0; i < subjects.length; i++)
          subjects[i].id: conceptLists[i],
      },
      due: await dueFuture,
      stars: await starsFuture,
      preferences: await preferencesFuture,
    );
  }

  Subject? _selectedSubject(_StudyData data) {
    if (data.subjects.isEmpty) return null;
    return data.subjects.firstWhere(
      (s) => s.id == _subjectId,
      orElse: () => data.subjects.first,
    );
  }

  Future<void> _toggleStar(_StudyData data, String id) async {
    final next = !data.stars.contains(id);
    setState(() {
      if (next) {
        data.stars.add(id);
      } else {
        data.stars.remove(id);
      }
    });
    try {
      await _repo.setConceptStarred(id, next);
      widget.onChanged?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (next) {
          data.stars.remove(id);
        } else {
          data.stars.add(id);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update the study library: $e')),
      );
    }
  }

  List<StudyCard> _cardsFor(
    _StudyData data,
    Subject subject,
    _StudyScope scope,
    int limit,
    bool shuffle,
  ) {
    final concepts = (data.concepts[subject.id] ?? const <ConceptRow>[])
        .where((c) => c.description?.trim().isNotEmpty == true)
        .toList();
    final dueIds = {
      for (final item in data.due)
        if (item.subjectId == subject.id &&
            (item.bucket == 'today' || item.bucket == 'unscheduled'))
          item.conceptId,
    };

    bool include(ConceptRow c) => switch (scope) {
          _StudyScope.due => dueIds.contains(c.id),
          _StudyScope.weak => c.mastery == null || c.mastery! < 55,
          _StudyScope.starred => data.stars.contains(c.id),
          _ => true,
        };

    var selected = concepts.where(include).toList();
    if (scope == _StudyScope.smart) {
      selected.sort((a, b) {
        int priority(ConceptRow c) {
          if (dueIds.contains(c.id)) return 0;
          if (c.mastery == null) return 1;
          if (c.mastery! < 55) return 2;
          return 3;
        }

        final p = priority(a).compareTo(priority(b));
        if (p != 0) return p;
        return (a.mastery ?? 0).compareTo(b.mastery ?? 0);
      });
    } else if (shuffle) {
      selected.shuffle();
    }
    if (limit > 0 && selected.length > limit) {
      selected = selected.take(limit).toList();
    }
    return [
      for (final concept in selected)
        StudyCard.fromConcept(concept)
            .copyWith(starred: data.stars.contains(concept.id)),
    ];
  }

  Future<void> _configureAndStart(
    _StudyData data,
    Subject subject, {
    _StudyScope initialScope = _StudyScope.smart,
    _StudyMode initialMode = _StudyMode.learn,
  }) async {
    var scope = initialScope;
    var mode = initialMode;
    var length = 10;
    var shuffle = true;
    final accepted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.88,
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                20,
                4,
                20,
                20 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Build a study round', style: T.title),
                  const SizedBox(height: 4),
                  Text(subject.name,
                      style: T.bodyQuiet.copyWith(color: Bold.slate)),
                  const SizedBox(height: 20),
                  Text('Activity', style: T.heading),
                  const SizedBox(height: 8),
                  SegmentedButton<_StudyMode>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                          value: _StudyMode.learn, label: Text('Learn')),
                      ButtonSegment(
                          value: _StudyMode.flashcards, label: Text('Cards')),
                      ButtonSegment(
                          value: _StudyMode.test, label: Text('Test')),
                      ButtonSegment(
                          value: _StudyMode.match, label: Text('Match')),
                    ],
                    selected: {mode},
                    onSelectionChanged: (value) =>
                        setSheetState(() => mode = value.first),
                  ),
                  const SizedBox(height: 20),
                  Text('Material', style: T.heading),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final item in _StudyScope.values)
                        ChoiceChip(
                          label: Text(switch (item) {
                            _StudyScope.smart => 'Smart mix',
                            _StudyScope.due => 'Due now',
                            _StudyScope.weak => 'Needs work',
                            _StudyScope.starred => 'Starred',
                            _StudyScope.all => 'Everything',
                          }),
                          selected: scope == item,
                          onSelected: (_) => setSheetState(() => scope = item),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(child: Text('Round length', style: T.heading)),
                      Text(length == 0 ? 'All' : '$length cards',
                          style: T.body),
                    ],
                  ),
                  Slider(
                    value: length.toDouble(),
                    min: 0,
                    max: 20,
                    divisions: 4,
                    label: length == 0 ? 'All' : '$length',
                    onChanged: (value) =>
                        setSheetState(() => length = value.round()),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Shuffle this round'),
                    subtitle: const Text('Smart mix keeps priority order.'),
                    value: shuffle,
                    onChanged: scope == _StudyScope.smart
                        ? null
                        : (value) => setSheetState(() => shuffle = value),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Start round'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (accepted != true || !mounted) return;

    final cards = _cardsFor(data, subject, scope, length, shuffle);
    if (cards.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('That filter needs at least two grounded concepts.')),
      );
      return;
    }

    final screen = switch (mode) {
      _StudyMode.flashcards => FlashcardsScreen(
          title: subject.name,
          cards: cards,
          subjectId: subject.id,
        ),
      _StudyMode.learn => LearnScreen(
          title: subject.name,
          cards: cards,
          subjectId: subject.id,
        ),
      _StudyMode.test => TestScreen(
          title: subject.name,
          cards: cards,
          subjectId: subject.id,
          questionCount: length == 0 ? cards.length : length,
        ),
      _StudyMode.match => MatchGameScreen(
          title: subject.name,
          cards: cards,
          subjectId: subject.id,
        ),
    };
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (mounted) {
      _load();
      widget.onChanged?.call();
    }
  }

  Future<void> _editPreferences(_StudyData data) async {
    var minutes = data.preferences.dailyGoalMinutes;
    var retention = data.preferences.desiredRetention;
    final save = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Study preferences', style: T.title),
                const SizedBox(height: 18),
                Text('Daily goal · $minutes minutes', style: T.heading),
                Slider(
                  value: minutes.toDouble(),
                  min: 5,
                  max: 60,
                  divisions: 11,
                  onChanged: (v) => setSheetState(() => minutes = v.round()),
                ),
                const SizedBox(height: 8),
                Text('Target recall · ${(retention * 100).round()}%',
                    style: T.heading),
                Text(
                  'Higher recall schedules more frequent review.',
                  style: T.bodyQuiet.copyWith(color: Bold.slate),
                ),
                Slider(
                  value: retention,
                  min: .80,
                  max: .95,
                  divisions: 15,
                  onChanged: (v) => setSheetState(() => retention = v),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Save preferences'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (save != true) return;
    await _repo.updateStudyPreferences(
      dailyGoalMinutes: minutes,
      desiredRetention: retention,
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: FutureBuilder<_StudyData>(
              future: _data,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return _StudyError(error: '${snap.error}', onRetry: _load);
                }
                return _content(snap.data!);
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(_StudyData data) {
    final subject = _selectedSubject(data);
    if (subject == null) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Study', style: T.display),
          const SizedBox(height: 80),
          Icon(Icons.layers_clear_outlined, size: 44, color: Bold.slate),
          const SizedBox(height: 16),
          Text('Your study tools are ready',
              style: T.title, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            'Upload course notes to build real flashcards, Adaptive Learn rounds, practice tests, and Match games. ViaX will not fill this screen with sample content.',
            style: T.bodyQuiet.copyWith(color: Bold.slate),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          if (widget.onOpenLibrary != null)
            FilledButton.icon(
              onPressed: widget.onOpenLibrary,
              icon: const Icon(Icons.upload_file_rounded),
              label: const Text('Add course material'),
            ),
        ],
      );
    }

    final allConcepts = data.concepts.values.expand((items) => items);
    final visible = allConcepts.where((concept) {
      if (_query.isEmpty) return concept.id != '__hidden__';
      return concept.name.toLowerCase().contains(_query) ||
          (concept.description?.toLowerCase().contains(_query) ?? false);
    }).toList();
    final subjectConcepts = data.concepts[subject.id] ?? const <ConceptRow>[];
    final due = data.due
        .where((item) =>
            item.subjectId == subject.id &&
            (item.bucket == 'today' || item.bucket == 'unscheduled'))
        .toList();
    final estimated = due.fold<int>(0, (sum, item) => sum + item.minutes);

    return RefreshIndicator(
      onRefresh: () async => _load(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
        children: [
          Row(
            children: [
              Expanded(child: Text('Study', style: T.display)),
              IconButton(
                tooltip: 'Study preferences',
                onPressed: () => _editPreferences(data),
                icon: const Icon(Icons.tune_rounded),
              ),
            ],
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: subject.id,
            decoration: const InputDecoration(
              labelText: 'Subject',
              prefixIcon: Icon(Icons.folder_open_rounded),
            ),
            items: [
              for (final item in data.subjects)
                DropdownMenuItem(value: item.id, child: Text(item.name)),
            ],
            onChanged: (value) => setState(() => _subjectId = value),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: Bold.brandDeep,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  due.isEmpty
                      ? 'Build momentum today'
                      : '${due.length} concepts are ready to review',
                  style: T.title.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 8),
                Text(
                  due.isEmpty
                      ? 'A smart round starts with unseen and low-mastery concepts.'
                      : '$estimated estimated minutes · ${data.preferences.dailyGoalMinutes}-minute daily goal',
                  style: T.bodyQuiet.copyWith(color: Colors.white70),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Bold.coral,
                    foregroundColor: Bold.brandDeep,
                  ),
                  onPressed: subjectConcepts.length < 2
                      ? null
                      : () => _configureAndStart(
                            data,
                            subject,
                            initialScope: due.isEmpty
                                ? _StudyScope.smart
                                : _StudyScope.due,
                          ),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(
                      due.isEmpty ? 'Start smart round' : 'Review what is due'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text('Choose how to practise', style: T.heading),
          const SizedBox(height: 8),
          _ModeRow(
            onTap: (mode) => _configureAndStart(
              data,
              subject,
              initialMode: mode,
            ),
          ),
          const SizedBox(height: 26),
          TextField(
            controller: _search,
            decoration: InputDecoration(
              hintText: 'Search concepts',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: _search.clear,
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Text(
                    _query.isEmpty
                        ? '${subject.name} concepts'
                        : 'Search results',
                    style: T.heading),
              ),
              Text(
                '${_query.isEmpty ? subjectConcepts.length : visible.length}',
                style: T.small.copyWith(color: Bold.slate),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final concept in (_query.isEmpty ? subjectConcepts : visible))
            _ConceptRow(
              concept: concept,
              starred: data.stars.contains(concept.id),
              onStar: () => _toggleStar(data, concept.id),
            ),
        ],
      ),
    );
  }
}

class _ModeRow extends StatelessWidget {
  const _ModeRow({required this.onTap});

  final void Function(_StudyMode mode) onTap;

  @override
  Widget build(BuildContext context) {
    const items = [
      (_StudyMode.flashcards, Icons.style_outlined, 'Cards'),
      (_StudyMode.learn, Icons.school_outlined, 'Learn'),
      (_StudyMode.test, Icons.fact_check_outlined, 'Test'),
      (_StudyMode.match, Icons.grid_view_rounded, 'Match'),
    ];
    return SizedBox(
      height: 76,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final item = items[index];
          return Material(
            color: Bold.card,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => onTap(item.$1),
              child: Container(
                width: 108,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  border: Border.all(color: Bold.line),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(item.$2, color: Bold.brand, size: 21),
                    const SizedBox(width: 8),
                    Text(item.$3, style: T.small.copyWith(color: Bold.ink)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ConceptRow extends StatelessWidget {
  const _ConceptRow({
    required this.concept,
    required this.starred,
    required this.onStar,
  });

  final ConceptRow concept;
  final bool starred;
  final VoidCallback onStar;

  @override
  Widget build(BuildContext context) {
    final (label, color) = Bold.mastery(concept.mastery);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Bold.line)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Bold.wash(color),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              concept.mastery == null ? '—' : '${concept.mastery!.round()}',
              style: T.small.copyWith(color: color),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(concept.name,
                    style: T.body.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(label, style: T.small.copyWith(color: color)),
              ],
            ),
          ),
          IconButton(
            tooltip: starred ? 'Remove from starred' : 'Add to starred',
            onPressed: onStar,
            icon: Icon(
              starred ? Icons.star_rounded : Icons.star_border_rounded,
              color: starred ? Bold.yellow : Bold.slate,
            ),
          ),
        ],
      ),
    );
  }
}

class _StudyError extends StatelessWidget {
  const _StudyError({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 80),
        Icon(Icons.sync_problem_rounded, size: 44, color: Bold.slate),
        const SizedBox(height: 16),
        Text('Could not load your study library',
            style: T.title, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(error,
            style: T.bodyQuiet.copyWith(color: Bold.slate),
            textAlign: TextAlign.center),
        const SizedBox(height: 20),
        OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
      ],
    );
  }
}

class _StudyData {
  _StudyData({
    required this.subjects,
    required this.concepts,
    required this.due,
    required this.stars,
    required this.preferences,
  });

  final List<Subject> subjects;
  final Map<String, List<ConceptRow>> concepts;
  final List<RevisionItem> due;
  final Set<String> stars;
  final StudyPreferences preferences;
}
