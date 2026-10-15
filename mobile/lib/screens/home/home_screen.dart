import 'package:flutter/material.dart';
import '../../data/auth.dart';
import '../../data/repository.dart';
import '../../design/bold.dart';
import '../profile/profile_screen.dart';
import '../study/flashcards_screen.dart';
import '../study/learn_screen.dart';
import '../study/match_game_screen.dart';
import '../study/study_models.dart';
import '../study/test_screen.dart';
import '../subjects/subject_detail_screen.dart';
import '../viva/viva_screen.dart';

/// Home (UI/UX §4.2).
///
/// Readiness Card as the hero, today's revision beneath it, streak pill, and
/// a prominent "Start a Viva". The order is the guide's and it is the right
/// one: the number a student came to check, then the work that moves it.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.onSignedOut,
    required this.onChanged,
    required this.onOpenTab,
  });

  final VoidCallback onSignedOut;
  final VoidCallback onChanged;
  final void Function(int) onOpenTab;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _repo = Repository();
  static const _auth = Auth();
  late Future<HomeSummary> _summary;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _summary = _repo.homeSummary().timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw Exception(
              'Loading your remote study data took too long. Check your connection and retry.',
            ),
          );
    });
  }

  Future<void> _startViva(Subject subject, {ConceptRow? focus}) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => VivaScreen(subject: subject, focusConcept: focus),
    ));
    if (mounted) {
      _load();
      widget.onChanged();
    }
  }

  Future<void> _openStudyMode(String mode, HomeSummary summary) async {
    if (summary.subjects.isEmpty) {
      widget.onOpenTab(1);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Add a subject and upload your notes first.')),
      );
      return;
    }

    Subject? subject;
    if (summary.subjects.length == 1) {
      subject = summary.subjects.first;
    } else {
      subject = await showModalBottomSheet<Subject>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              Text('Choose a subject',
                  style: T.title.copyWith(color: Bold.ink)),
              const SizedBox(height: 8),
              for (final candidate in summary.subjects)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(candidate.name),
                  subtitle: Text('${candidate.conceptCount} concepts'),
                  trailing: const Icon(Icons.arrow_forward_rounded),
                  onTap: () => Navigator.of(context).pop(candidate),
                ),
            ],
          ),
        ),
      );
    }
    if (subject == null || !mounted) return;

    List<ConceptRow> concepts;
    try {
      concepts = await _repo.concepts(subject.id);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Could not load your study material. Check your connection and try again.'),
        ));
      }
      return;
    }
    if (!mounted) return;
    final cards = concepts
        .where((concept) => concept.description?.trim().isNotEmpty == true)
        .map(StudyCard.fromConcept)
        .toList();
    if (cards.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'No grounded study cards yet. Finish or retry document processing.'),
        ),
      );
      return;
    }
    final title = subject.name;

    switch (mode) {
      case 'flashcards':
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => FlashcardsScreen(
            title: title,
            cards: cards,
            subjectId: subject!.id,
          ),
        ));
        break;
      case 'learn':
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => LearnScreen(
            title: title,
            cards: cards,
            subjectId: subject!.id,
          ),
        ));
        break;
      case 'test':
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => TestScreen(
            title: title,
            cards: cards,
            subjectId: subject!.id,
          ),
        ));
        break;
      case 'match':
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => MatchGameScreen(
            title: title,
            cards: cards,
            subjectId: subject!.id,
          ),
        ));
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: RefreshIndicator(
              onRefresh: () async => _load(),
              child: FutureBuilder<HomeSummary>(
                future: _summary,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const _HomeSkeleton();
                  }
                  if (snap.hasError) {
                    return _ErrorState(error: '${snap.error}', onRetry: _load);
                  }
                  return _content(snap.data!);
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(HomeSummary s) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(greeting,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: T.title.copyWith(color: Bold.ink)),
                  const SizedBox(height: 2),
                  Text(
                    s.isEmpty
                        ? 'Add your notes to get started.'
                        : '${s.subjects.length} subject${s.subjects.length == 1 ? '' : 's'}'
                            ' · ${s.answeredTotal} answers given',
                    style: T.small.copyWith(color: Bold.slate),
                  ),
                ],
              ),
            ),
            if (s.streakDays > 0) _StreakPill(days: s.streakDays),
            const SizedBox(width: 4),
            ValueListenableBuilder<ThemeMode>(
              valueListenable: Bold.themeNotifier,
              builder: (context, mode, _) {
                final isDark = Bold.isDark;
                return IconButton(
                  tooltip:
                      isDark ? 'Switch to Light Mode' : 'Switch to Dark Mode',
                  icon: Icon(
                    isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                    color: isDark ? Bold.warnLift : Bold.brandDeep,
                    size: 22,
                  ),
                  onPressed: () {
                    Bold.themeNotifier.value =
                        isDark ? ThemeMode.light : ThemeMode.dark;
                  },
                );
              },
            ),
            const SizedBox(width: 4),
            _Avatar(
              initials: _auth.displayName.characters.first.toUpperCase(),
              onTap: () async {
                await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) =>
                      ProfileScreen(onSignedOut: widget.onSignedOut),
                ));
                if (mounted) _load();
              },
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (s.isEmpty) ...[
          _FirstRun(
            onAddNotes: () => widget.onOpenTab(1),
          ),
          const SizedBox(height: 20),
          _FeaturePreview(onAddNotes: () => widget.onOpenTab(1)),
        ] else ...[
          _ReadinessHero(
            summary: s,
            onStart: () => widget.onOpenTab(3),
          ),
          const SizedBox(height: 18),
          if (s.due.isNotEmpty) ...[
            _SectionHeader(
              title: 'Due today',
              trailing: '${s.due.length} · ~${s.dueMinutes} min',
            ),
            const SizedBox(height: 4),
            Text(
              'Scheduled by when you are likely to forget, not a fixed ladder.',
              style: T.small.copyWith(color: Bold.slate),
            ),
            const SizedBox(height: 12),
            // Horizontally scrollable, per UI/UX §4.2 — the list is a nudge,
            // not the screen's subject, so it must not push readiness away.
            SizedBox(
              height: 122,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: s.due.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, i) {
                  final item = s.due[i];
                  final subject = s.subjects.firstWhere(
                    (x) => x.id == item.subjectId,
                    orElse: () => s.subjects.first,
                  );
                  return _DueCard(
                    item: item,
                    onTap: () => _startViva(
                      subject,
                      focus: ConceptRow(
                        id: item.conceptId,
                        name: item.name,
                        importance: 2,
                        mastery: item.mastery,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 22),
          ],
          _SectionHeader(title: 'Your subjects'),
          const SizedBox(height: 10),
          for (final subject in s.subjects) ...[
            _SubjectRow(
              subject: subject,
              onTap: () async {
                await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => SubjectDetailScreen(subject: subject),
                ));
                if (mounted) {
                  _load();
                  widget.onChanged();
                }
              },
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 18),
          _StudyModesSection(onOpenMode: (mode) => _openStudyMode(mode, s)),
          const SizedBox(height: 18),
          _PracticeRecord(
            streakDays: s.streakDays,
            answeredTotal: s.answeredTotal,
            onOpenAnalytics: () => widget.onOpenTab(4),
          ),
        ],
      ],
    );
  }
}

class _ReadinessHero extends StatelessWidget {
  const _ReadinessHero({required this.summary, required this.onStart});

  final HomeSummary summary;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final score = summary.readiness;
    final hasPracticeData = summary.answeredTotal > 0;
    final (band, _) = Bold.band(score);
    final nearest = summary.subjects
        .where((s) => s.daysUntilExam != null)
        .fold<int?>(null, (a, s) {
      final d = s.daysUntilExam!;
      return a == null || d < a ? d : a;
    });

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Bold.brandDeep,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Bold.isDark ? Bold.lineDark : Bold.brand),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Readiness',
                  style: T.small.copyWith(
                    color: Bold.brandLift,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w700,
                  )),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(999),
                ),
                // Colour is never the only signal (UI/UX §5).
                child: Text(
                  hasPracticeData ? band : 'Not measured',
                  style: T.small.copyWith(color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                hasPracticeData ? '${score.round()}' : '—',
                style: T.hero.copyWith(fontSize: 54),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Text(
                  hasPracticeData ? '% ready' : 'ready after practice',
                  style: T.body.copyWith(color: Colors.white70),
                ),
              ),
              const Spacer(),
              if (nearest != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                      nearest <= 0 ? 'Viva today' : 'Viva in $nearest d',
                      style: T.small.copyWith(color: Colors.white70)),
                ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Stack(
              children: [
                Container(
                    height: 4, color: Colors.white.withValues(alpha: 0.14)),
                if (hasPracticeData)
                  FractionallySizedBox(
                    widthFactor: (score / 100).clamp(0, 1),
                    child: Container(height: 4, color: Bold.brandLift),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            !hasPracticeData
                ? 'Your material is ready. Answer questions in Study or Viva to measure your readiness.'
                : nearest == null
                    ? 'Based on your demonstrated recall across subjects.'
                    : 'Based on your recall and nearest exam date.',
            style: T.small.copyWith(color: Colors.white70, height: 1.4),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onStart,
              style: FilledButton.styleFrom(
                backgroundColor: Bold.cardLight,
                foregroundColor: Bold.brandDeep,
              ),
              icon: const Icon(Icons.mic_rounded),
              label: const Text('Start a viva'),
            ),
          ),
        ],
      ),
    );
  }
}

class _DueCard extends StatelessWidget {
  const _DueCard({required this.item, required this.onTap});

  final RevisionItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (label, colour) = Bold.mastery(item.mastery);
    return SizedBox(
      width: 190,
      child: Material(
        color: Bold.card,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Bold.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration:
                          BoxDecoration(color: colour, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Text(label, style: T.small.copyWith(color: colour)),
                  ],
                ),
                Text(item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: T.body.copyWith(color: Bold.ink)),
                Row(
                  children: [
                    Text('~${item.minutes} min',
                        style: T.small.copyWith(color: Bold.slate)),
                    const Spacer(),
                    const Icon(Icons.arrow_forward_rounded,
                        size: 16, color: Bold.brand),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SubjectRow extends StatelessWidget {
  const _SubjectRow({required this.subject, required this.onTap});

  final Subject subject;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Bold.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Bold.line),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(subject.name,
                        style: T.body.copyWith(
                            color: Bold.ink, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(
                      '${subject.documentCount} document'
                      '${subject.documentCount == 1 ? '' : 's'} · '
                      '${subject.conceptCount} concept'
                      '${subject.conceptCount == 1 ? '' : 's'}',
                      style: T.small.copyWith(color: Bold.slate),
                    ),
                  ],
                ),
              ),
              if (subject.daysUntilExam != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: Bold.wash(
                        subject.daysUntilExam! <= 3 ? Bold.warn : Bold.brand),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${subject.daysUntilExam}d',
                    style: T.small.copyWith(
                      color: subject.daysUntilExam! <= 3
                          ? Bold.warn
                          : Bold.brandDeep,
                    ),
                  ),
                ),
              Icon(Icons.chevron_right_rounded, color: Bold.slate),
            ],
          ),
        ),
      ),
    );
  }
}

class _StreakPill extends StatelessWidget {
  const _StreakPill({required this.days});

  final int days;

  @override
  Widget build(BuildContext context) {
    // Small and persistent, never a full-screen interruption (UI/UX §2.4).
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Bold.wash(Bold.warn),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.local_fire_department_rounded,
              size: 15, color: Bold.warn),
          const SizedBox(width: 4),
          Text('$days', style: T.small.copyWith(color: Bold.warn)),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.initials, required this.onTap});

  final String initials;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 48,
        height: 48,
        decoration: const BoxDecoration(
          color: Bold.brand,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(initials,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16)),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
            child: Text(title, style: T.heading.copyWith(color: Bold.ink))),
        if (trailing != null)
          Text(trailing!, style: T.small.copyWith(color: Bold.slate)),
      ],
    );
  }
}

class _FirstRun extends StatelessWidget {
  const _FirstRun({
    required this.onAddNotes,
  });

  final VoidCallback onAddNotes;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: Bold.brandDeep,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Bold.isDark ? Bold.lineDark : Bold.brand),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.auto_stories_rounded, color: Colors.white, size: 32),
          const SizedBox(height: 16),
          Text('Your notes unlock the whole study kit',
              style: T.heading.copyWith(color: Colors.white)),
          const SizedBox(height: 8),
          Text(
            'ViaX builds practice from your material—not sample content. Add a subject and upload notes to get started.',
            style: T.bodyQuiet.copyWith(
                color: Colors.white.withValues(alpha: 0.88), height: 1.45),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onAddNotes,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Bold.brandDeep,
              ),
              child: const Text('Create a subject & upload notes'),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'PDF · PowerPoint · Word · Markdown · text · CSV',
            style:
                T.small.copyWith(color: Colors.white.withValues(alpha: 0.78)),
          ),
        ],
      ),
    );
  }
}

/// Shows the real product surface before a student has uploaded material.
/// These cards contain no sample questions or fabricated progress; they point
/// to the actual prerequisite for each grounded activity.
class _FeaturePreview extends StatelessWidget {
  const _FeaturePreview({required this.onAddNotes});

  final VoidCallback onAddNotes;

  @override
  Widget build(BuildContext context) {
    const features = <_FeaturePreviewItem>[
      _FeaturePreviewItem(
        title: 'Flashcards',
        detail: 'Flip through concepts and recall them actively.',
        requirement: '2+ extracted concepts',
        icon: Icons.style_rounded,
        accent: Bold.brand,
      ),
      _FeaturePreviewItem(
        title: 'Adaptive Learn',
        detail: 'Practice adjusts as your answers improve.',
        requirement: '2+ extracted concepts',
        icon: Icons.school_rounded,
        accent: Bold.good,
      ),
      _FeaturePreviewItem(
        title: 'Practice Test',
        detail: 'Check what you know with a grounded quiz.',
        requirement: '2+ extracted concepts',
        icon: Icons.fact_check_rounded,
        accent: Bold.warn,
      ),
      _FeaturePreviewItem(
        title: 'Match Game',
        detail: 'Pair key terms with their explanations.',
        requirement: '2+ extracted concepts',
        icon: Icons.grid_view_rounded,
        accent: Bold.coral,
      ),
      _FeaturePreviewItem(
        title: 'AI Viva',
        detail: 'Answer aloud; follow-ups use your course material.',
        requirement: '${Subject.minConceptsForViva}+ extracted concepts',
        icon: Icons.mic_rounded,
        accent: Bold.brandDeep,
      ),
      _FeaturePreviewItem(
        title: 'Progress & review',
        detail: 'Mastery and spaced reviews build from real sessions.',
        requirement: 'Starts after your first answer',
        icon: Icons.query_stats_rounded,
        accent: Bold.good,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('What your notes unlock',
            style: T.heading.copyWith(color: Bold.ink)),
        const SizedBox(height: 4),
        Text(
          'These tools appear in Study, Viva, and Progress as soon as your material is processed.',
          style: T.small.copyWith(color: Bold.slate, height: 1.45),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = (constraints.maxWidth - 10) / 2;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final feature in features)
                  SizedBox(
                    width: width,
                    child: _FeaturePreviewCard(
                      feature: feature,
                      onTap: onAddNotes,
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _FeaturePreviewItem {
  const _FeaturePreviewItem({
    required this.title,
    required this.detail,
    required this.requirement,
    required this.icon,
    required this.accent,
  });

  final String title;
  final String detail;
  final String requirement;
  final IconData icon;
  final Color accent;
}

class _FeaturePreviewCard extends StatelessWidget {
  const _FeaturePreviewCard({required this.feature, required this.onTap});

  final _FeaturePreviewItem feature;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Bold.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 166,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Bold.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Bold.wash(feature.accent),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(feature.icon, size: 19, color: feature.accent),
              ),
              const SizedBox(height: 9),
              Text(feature.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: T.body
                      .copyWith(color: Bold.ink, fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(
                feature.detail,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: T.small.copyWith(color: Bold.slate, height: 1.35),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.lock_outline_rounded, size: 13, color: Bold.slate),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      feature.requirement,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: T.small.copyWith(
                        color: Bold.slate,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StudyModesSection extends StatelessWidget {
  const _StudyModesSection({required this.onOpenMode});

  final void Function(String) onOpenMode;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Study Modes', style: T.heading.copyWith(color: Bold.ink)),
            Text('Practice',
                style: T.small
                    .copyWith(color: Bold.brand, fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StudyModeTile(
                icon: Icons.style_rounded,
                iconColor: Bold.brand,
                title: 'Flashcards',
                subtitle: 'Flip & swipe',
                onTap: () => onOpenMode('flashcards'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StudyModeTile(
                icon: Icons.school_rounded,
                iconColor: Bold.good,
                title: 'Learn',
                subtitle: 'Adaptive quiz',
                onTap: () => onOpenMode('learn'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _StudyModeTile(
                icon: Icons.quiz_rounded,
                iconColor: Bold.warn,
                title: 'Test',
                subtitle: 'Practice exam',
                onTap: () => onOpenMode('test'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StudyModeTile(
                icon: Icons.bolt_rounded,
                iconColor: Bold.coral,
                title: 'Match',
                subtitle: 'Speed game',
                onTap: () => onOpenMode('match'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StudyModeTile extends StatelessWidget {
  const _StudyModeTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Bold.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Bold.line),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Bold.wash(iconColor),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 20, color: iconColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: T.body.copyWith(
                            color: Bold.ink, fontWeight: FontWeight.w700)),
                    Text(subtitle,
                        style:
                            T.small.copyWith(color: Bold.slate, fontSize: 11)),
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

/// Skeleton shimmer, not a bare spinner (UI/UX §2.5).
class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget block(double h, {double w = double.infinity, double r = 14}) =>
        Container(
          height: h,
          width: w,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Bold.line.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(r),
          ),
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      children: [
        Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Text('Syncing your remote library',
                style: T.body.copyWith(color: Bold.ink)),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Fetching your real subjects and progress. Study, Viva, and Progress are available from the tabs below.',
          style: T.small.copyWith(color: Bold.slate, height: 1.4),
        ),
        const SizedBox(height: 18),
        block(26, w: 220, r: 8),
        block(14, w: 150, r: 6),
        const SizedBox(height: 10),
        block(168, r: 24),
        const SizedBox(height: 8),
        block(18, w: 120, r: 6),
        block(110, r: 16),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        const SizedBox(height: 60),
        Icon(Icons.cloud_off_rounded, size: 38, color: Bold.slate),
        const SizedBox(height: 14),
        Text('Could not load your progress',
            textAlign: TextAlign.center,
            style: T.title.copyWith(color: Bold.ink)),
        const SizedBox(height: 8),
        // The real message: a student who can screenshot this can be helped.
        Text(error,
            textAlign: TextAlign.center,
            style: T.small.copyWith(color: Bold.slate, height: 1.5)),
        const SizedBox(height: 20),
        OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
      ],
    );
  }
}

class _PracticeRecord extends StatelessWidget {
  const _PracticeRecord({
    required this.streakDays,
    required this.answeredTotal,
    required this.onOpenAnalytics,
  });

  final int streakDays;
  final int answeredTotal;
  final VoidCallback onOpenAnalytics;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Bold.card,
        borderRadius: BorderRadius.circular(20),
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
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Bold.wash(Bold.brand),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.insights_rounded,
                        size: 18, color: Bold.brand),
                  ),
                  const SizedBox(width: 10),
                  Text('Practice record',
                      style: T.heading.copyWith(color: Bold.ink, fontSize: 15)),
                ],
              ),
              SizedBox(
                height: 48,
                child: InkWell(
                  onTap: onOpenAnalytics,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        Text('Analytics',
                            style: T.small.copyWith(
                                color: Bold.brand,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(width: 2),
                        const Icon(Icons.arrow_forward_ios_rounded,
                            size: 11, color: Bold.brand),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Bold.canvas,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Bold.line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.local_fire_department_rounded,
                              size: 15,
                              color: streakDays > 0 ? Bold.brand : Bold.slate),
                          const SizedBox(width: 4),
                          Text('Study Streak',
                              style: T.small
                                  .copyWith(fontSize: 11, color: Bold.slate)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        streakDays > 0 ? '$streakDays Days' : 'Start Today',
                        style: T.body.copyWith(
                            color: Bold.ink, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text('Consecutive study days',
                          style: T.small
                              .copyWith(fontSize: 10, color: Bold.slate)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Bold.canvas,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Bold.line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.task_alt_rounded,
                              size: 15, color: Bold.good),
                          const SizedBox(width: 4),
                          Text('Answers reviewed',
                              style: T.small
                                  .copyWith(fontSize: 11, color: Bold.slate)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$answeredTotal',
                        style: T.body.copyWith(
                            color: Bold.ink, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text('From your real sessions',
                          style: T.small
                              .copyWith(fontSize: 10, color: Bold.slate)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
