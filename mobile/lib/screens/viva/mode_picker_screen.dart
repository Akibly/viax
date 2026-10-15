import 'package:flutter/material.dart';

import '../../data/repository.dart';
import '../../design/bold.dart';
import 'viva_screen.dart';

/// The four viva modes a student can sit (UI/UX §4.4).
///
/// Each carries its own accent so the mode is felt before it is read, and
/// each says plainly what to expect — the difference between Practice and
/// Examination is a difference in *stakes*, and hiding that would be unfair.
enum VivaMode {
  practice(
    'Practice',
    'Unlimited attempts, hints, and the expected answer after every question.',
    Icons.school_outlined,
    Bold.brand,
  ),
  examination(
    'Examination',
    'Timed. No hints, no second attempts, strict marking.',
    Icons.timer_outlined,
    Bold.warn,
  ),
  professor(
    'Professor',
    'Harder follow-ups and cross-topic questions. Higher difficulty floor.',
    Icons.psychology_outlined,
    Bold.brandDeep,
  ),
  mock(
    'Mock interview',
    'Industry style: behavioural and technical questions mixed together.',
    Icons.groups_outlined,
    Bold.good,
  );

  const VivaMode(this.label, this.blurb, this.icon, this.accent);

  final String label;
  final String blurb;
  final IconData icon;
  final Color accent;

  bool get isTimed => this == VivaMode.examination;

  /// P1 in the PRD (§5.2). Shown but marked, rather than hidden — a student
  /// should be able to see where the product is going.
  bool get isPreview => this == VivaMode.professor || this == VivaMode.mock;
}

class ModePickerScreen extends StatefulWidget {
  const ModePickerScreen({
    super.key,
    required this.onChanged,
    this.onOpenLibrary,
  });

  final VoidCallback onChanged;
  final VoidCallback? onOpenLibrary;

  @override
  State<ModePickerScreen> createState() => _ModePickerScreenState();
}

class _ModePickerScreenState extends State<ModePickerScreen> {
  static const _repo = Repository();
  late Future<List<Subject>> _subjects;
  Subject? _chosen;

  @override
  void initState() {
    super.initState();
    _subjects = _repo.subjects();
  }

  Future<void> _start(VivaMode mode) async {
    final subject = _chosen;
    if (subject == null || mode.isPreview) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => VivaScreen(subject: subject, mode: mode),
    ));
    if (mounted) widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: FutureBuilder<List<Subject>>(
              future: _subjects,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final subjects = snap.data ?? const <Subject>[];
                final ready = subjects.where((s) => s.canExamine).toList();
                _chosen ??= ready.isNotEmpty ? ready.first : null;

                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                  children: [
                    Text('Sit a viva',
                        style: T.display.copyWith(color: Bold.ink)),
                    const SizedBox(height: 6),
                    Text(
                      ready.isEmpty
                          ? 'No subject has enough material yet.'
                          : 'Pick a subject, then choose how hard you want it.',
                      style: T.body.copyWith(color: Bold.slate),
                    ),
                    const SizedBox(height: 22),
                    if (ready.isEmpty)
                      _NotReady(
                        subjects: subjects,
                        onAddMaterial: widget.onOpenLibrary,
                      )
                    else ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: Bold.card,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Bold.line),
                        ),
                        child: Row(children: [
                          const Icon(Icons.verified_outlined,
                              size: 19, color: Bold.brand),
                          const SizedBox(width: 10),
                          Expanded(
                              child: Text(
                            'Questions are grounded in the concepts extracted from your material.',
                            style:
                                T.small.copyWith(color: Bold.ink, height: 1.35),
                          )),
                        ]),
                      ),
                      const SizedBox(height: 18),
                      Text('Subject',
                          style: T.small.copyWith(color: Bold.slate)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final s in ready)
                            ChoiceChip(
                              label: Text(s.name),
                              selected: _chosen?.id == s.id,
                              onSelected: (_) => setState(() => _chosen = s),
                              selectedColor: Bold.wash(Bold.brand),
                              labelStyle: T.body.copyWith(
                                color: _chosen?.id == s.id
                                    ? Bold.brandDeep
                                    : Bold.slate,
                                fontWeight: _chosen?.id == s.id
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                              side: BorderSide(
                                color: _chosen?.id == s.id
                                    ? Bold.brand
                                    : Bold.line,
                              ),
                              backgroundColor: Bold.card,
                              showCheckmark: false,
                            ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Text('Mode', style: T.small.copyWith(color: Bold.slate)),
                      const SizedBox(height: 10),
                      for (final mode in VivaMode.values) ...[
                        _ModeCard(mode: mode, onTap: () => _start(mode)),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({required this.mode, required this.onTap});

  final VivaMode mode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Bold.card,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: mode.isPreview ? null : onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Bold.line),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Bold.wash(mode.accent),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(mode.icon, color: mode.accent, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(mode.label,
                            style: T.heading.copyWith(color: Bold.ink)),
                        if (mode.isTimed) ...[
                          const SizedBox(width: 8),
                          _Tag(text: '120s', colour: mode.accent),
                        ],
                        if (mode.isPreview) ...[
                          const SizedBox(width: 8),
                          _Tag(text: 'Coming soon', colour: Bold.slate),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(mode.blurb,
                        style:
                            T.small.copyWith(color: Bold.slate, height: 1.45)),
                  ],
                ),
              ),
              Icon(
                mode.isPreview
                    ? Icons.lock_outline_rounded
                    : Icons.chevron_right_rounded,
                color: Bold.slate,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.colour});

  final String text;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Bold.wash(colour),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text, style: T.small.copyWith(color: colour, fontSize: 11)),
    );
  }
}

class _NotReady extends StatelessWidget {
  const _NotReady({required this.subjects, required this.onAddMaterial});

  final List<Subject> subjects;
  final VoidCallback? onAddMaterial;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Bold.wash(Bold.warn),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.library_books_outlined, color: Bold.warn, size: 26),
          const SizedBox(height: 12),
          Text('Nothing to examine you on yet',
              style: T.heading.copyWith(color: Bold.ink)),
          const SizedBox(height: 8),
          Text(
            subjects.isEmpty
                ? 'Add a subject and upload your notes first.'
                : 'A viva needs at least ${Subject.minConceptsForViva} concepts. '
                    'Below that the questions would come from general knowledge '
                    'rather than your material.',
            style: T.small.copyWith(color: Bold.warn, height: 1.5),
          ),
          if (subjects.isNotEmpty) ...[
            const SizedBox(height: 14),
            for (final s in subjects)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '${s.name} — ${s.conceptCount} of '
                  '${Subject.minConceptsForViva} concepts',
                  style: T.small.copyWith(color: Bold.warn),
                ),
              ),
          ],
          if (onAddMaterial != null) ...[
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onAddMaterial,
              icon: const Icon(Icons.upload_file_rounded),
              label: const Text('Add course material'),
            ),
          ],
        ],
      ),
    );
  }
}
