import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/content_hash.dart';
import '../../data/repository.dart';
import '../../design/bold.dart';
import '../profile/settings_screen.dart';
import 'subject_detail_screen.dart';
import '../viva/viva_screen.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// The entrance to the product.
///
/// Everything else assumed this existed. It did not — there was no way to get
/// a document into the app at all, which made every other screen decoration.
/// A student's first run lands here: create a subject, add notes, watch them
/// become concepts.
class SubjectsScreen extends StatefulWidget {
  const SubjectsScreen({super.key, this.onChanged});

  /// Uploading notes changes readiness everywhere, so the shell refreshes the
  /// other tabs rather than letting them show a stale figure.
  final VoidCallback? onChanged;

  @override
  State<SubjectsScreen> createState() => _SubjectsScreenState();
}

class _SubjectsScreenState extends State<SubjectsScreen> {
  static const _repo = Repository();

  late Future<List<Subject>> _subjects;
  bool _busy = false;

  /// What the app is doing right now, in the student's words.
  String? _stage;

  @override
  void initState() {
    super.initState();
    _subjects = _repo.subjects();
  }

  void _reload() {
    // A block body, not an arrow: `setState(() => x = f())` returns the value
    // of the assignment, and when that value is a Future, Flutter rejects the
    // callback outright. The assignment must be a statement.
    setState(() {
      _subjects = _repo.subjects();
    });
  }

  Future<void> _newSubject() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New subject'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'Operating Systems',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;

    try {
      await _repo.createSubject(name);
      _reload();
    } catch (e) {
      _say('Could not create the subject. $e');
    }
  }

  Future<void> _addNotes(Subject subject) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const [
        'pdf',
        'pptx',
        'docx',
        'txt',
        'csv',
        'md',
        'markdown'
      ],
      withData: true, // web has no file path; bytes are the portable route
    );
    final file = picked?.files.firstOrNull;
    if (file == null) return;

    final bytes = file.bytes;
    if (bytes == null) {
      _say('Could not read that file.');
      return;
    }
    // The bucket enforces this too, but failing here saves a wasted upload
    // and gives a message that names the actual limit.
    if (bytes.length > 25 * 1024 * 1024) {
      _say('${file.name} is ${(bytes.length / 1048576).toStringAsFixed(1)} MB. '
          'The limit is 25 MB.');
      return;
    }

    setState(() {
      _busy = true;
      _stage = 'Uploading ${file.name}…';
    });
    try {
      // Content hash is the de-duplication key — re-uploading the same notes
      // must not pay for extraction and embeddings twice.
      final hash = await compute(contentFingerprint, bytes);
      final doc = await _repo.upload(
        subjectId: subject.id,
        filename: file.name,
        bytes: bytes,
        contentHash: hash,
        mimeType: switch (file.extension?.toLowerCase()) {
          'pptx' =>
            'application/vnd.openxmlformats-officedocument.presentationml.presentation',
          'docx' =>
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
          'txt' => 'text/plain',
          'csv' => 'text/csv',
          'md' || 'markdown' => 'text/markdown',
          _ => 'application/pdf',
        },
      );

      // Reading the PDF, embedding it and naming its concepts takes a while.
      // The student is told what is happening rather than watching a spinner
      // that could mean anything.
      if (mounted) setState(() => _stage = 'Reading the document…');
      final result = await _repo.ingest(doc.id);

      if (mounted) {
        _say('Found ${result.concepts} concepts across ${result.pages} pages'
            '${result.edges > 0 ? ', and ${result.edges} prerequisite links' : ''}.');
      }
      _reload();
      widget.onChanged?.call();
    } catch (e) {
      _say('$e');
      _reload();
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _stage = null;
        });
      }
    }
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: RefreshIndicator(
              onRefresh: () async => _reload(),
              child: FutureBuilder<List<Subject>>(
                future: _subjects,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return _Error(
                      error: '${snap.error}',
                      onRetry: _reload,
                    );
                  }
                  final subjects = snap.data ?? const [];
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text('Library',
                                style: T.display.copyWith(color: Bold.ink)),
                          ),
                          IconButton(
                            icon: const Icon(Icons.settings_outlined),
                            tooltip: 'Settings',
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const SettingsScreen(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subjects.isEmpty
                            ? 'Your material, organized for focused revision.'
                            : '${subjects.length} subject${subjects.length == 1 ? '' : 's'} · tap one to explore its material',
                        style: T.bodyQuiet.copyWith(color: Bold.slate),
                      ),
                      const SizedBox(height: 16),
                      if (subjects.isEmpty)
                        _FirstRun(onCreate: _newSubject)
                      else ...[
                        for (final s in subjects) ...[
                          _SubjectCard(
                            subject: s,
                            busy: _busy,
                            stage: _stage,
                            onAdd: () => _addNotes(s),
                          ),
                          const SizedBox(height: 12),
                        ],
                        const SizedBox(height: 4),
                        OutlinedButton.icon(
                          onPressed: _newSubject,
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Add another subject'),
                        ),
                      ],
                    ]
                        .animate(interval: 50.ms)
                        .fade(duration: 400.ms, curve: Curves.easeOut)
                        .slideY(begin: 0.1, curve: Curves.easeOutQuad),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FirstRun extends StatelessWidget {
  const _FirstRun({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Bold.brandDeep,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.auto_stories_rounded, color: Colors.white, size: 34),
          const SizedBox(height: 16),
          const Text(
            'Start with your notes',
            style: TextStyle(
              fontSize: 26,
              height: 1.15,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Upload course material and ViaX finds the concepts inside it, then examines '
            'you on those — never on anything it made up.',
            style: T.body.copyWith(color: Colors.white.withValues(alpha: 0.88)),
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onCreate,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Bold.brandDeep,
              ),
              child: const Text('Create your first subject'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SubjectCard extends StatelessWidget {
  const _SubjectCard({
    required this.subject,
    required this.busy,
    required this.stage,
    required this.onAdd,
  });

  final Subject subject;
  final bool busy;
  final String? stage;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final ready = subject.canExamine;

    return Material(
      color: Bold.card,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => SubjectDetailScreen(subject: subject),
        )),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Bold.line),
          ),
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(subject.name, style: T.title)),
                  if (subject.daysUntilExam != null)
                    _Chip(
                      label: '${subject.daysUntilExam}d',
                      color:
                          subject.daysUntilExam! <= 3 ? Bold.warn : Bold.slate,
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _Stat(value: '${subject.documentCount}', label: 'documents'),
                  const SizedBox(width: 24),
                  _Stat(value: '${subject.conceptCount}', label: 'concepts'),
                ],
              ),
              const SizedBox(height: 16),
              // The refusal, shown before the student can hit it. Below five
              // concepts a viva would come from general knowledge rather than
              // their material, so the button says why it is not available.
              if (!ready)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Bold.wash(Bold.warn),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    subject.documentCount == 0
                        ? 'Add notes to get started.'
                        : 'Found ${subject.conceptCount} of '
                            '${Subject.minConceptsForViva} concepts needed. '
                            'Add more notes, or wait for processing to finish.',
                    style: T.small.copyWith(color: Bold.warn),
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: busy ? null : onAdd,
                      icon: busy
                          ? const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.upload_file_rounded, size: 18),
                      label: Text(busy ? (stage ?? 'Working…') : 'Add notes'),
                    ),
                  ),
                  if (ready) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => VivaScreen(subject: subject),
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                        ),
                        child: const Text('Examine me'),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: T.stat.copyWith(color: Bold.ink)),
        const SizedBox(width: 6),
        Text(label, style: T.bodyQuiet.copyWith(color: Bold.slate)),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Bold.wash(color),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: T.small.copyWith(color: color)),
    );
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 60),
        Icon(Icons.cloud_off_rounded, size: 40, color: Bold.slate),
        const SizedBox(height: 16),
        Text('Could not reach your library', style: T.title),
        const SizedBox(height: 8),
        // The real error, not a shrug. A student who can screenshot this can
        // be helped; "something went wrong" cannot.
        Text(error, style: T.bodyQuiet.copyWith(color: Bold.slate)),
        const SizedBox(height: 20),
        OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
      ],
    );
  }
}
