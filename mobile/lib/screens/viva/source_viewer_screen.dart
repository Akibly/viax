import 'package:flutter/material.dart';

import '../../data/repository.dart';
import '../../design/bold.dart';

/// The passage a citation points at (UI/UX §4.6: citation chips linking to
/// the exact source page).
///
/// This is where the product's central claim gets tested by the student: they
/// tap the citation and either find the passage that justifies the gap, or
/// they don't. It reads back from the chunk the question was built on, so
/// what they see is the evidence itself rather than a paraphrase — and a
/// fabricated citation could never have been stored in the first place,
/// because the database rejects one.
class SourceViewerScreen extends StatefulWidget {
  const SourceViewerScreen({
    super.key,
    required this.chunkId,
    required this.gapLabel,
    this.isQuestionSource = false,
  });

  final String chunkId;

  /// What the examiner said was missing, kept in view so the student can
  /// judge the claim against the text rather than remembering it.
  final String gapLabel;
  final bool isQuestionSource;

  @override
  State<SourceViewerScreen> createState() => _SourceViewerScreenState();
}

class _SourceViewerScreenState extends State<SourceViewerScreen> {
  static const _repo = Repository();
  late Future<Passage> _passage;

  @override
  void initState() {
    super.initState();
    _passage = _repo.passage(widget.chunkId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Bold.canvas,
        surfaceTintColor: Colors.transparent,
        title:
            Text('From your notes', style: T.heading.copyWith(color: Bold.ink)),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: FutureBuilder<Passage>(
              future: _passage,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.description_outlined,
                              size: 38, color: Bold.slate),
                          const SizedBox(height: 14),
                          Text('Could not open the passage',
                              style: T.heading.copyWith(color: Bold.ink)),
                          const SizedBox(height: 8),
                          Text('${snap.error}',
                              textAlign: TextAlign.center,
                              style: T.small.copyWith(color: Bold.slate)),
                        ],
                      ),
                    ),
                  );
                }
                final p = snap.data!;
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Bold.wash(
                            widget.isQuestionSource ? Bold.brand : Bold.danger),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              widget.isQuestionSource
                                  ? 'Question source'
                                  : 'What was missing',
                              style: T.small.copyWith(
                                color: widget.isQuestionSource
                                    ? Bold.brandDeep
                                    : Bold.danger,
                              )),
                          const SizedBox(height: 4),
                          Text(widget.gapLabel,
                              style: T.body.copyWith(
                                  color: Bold.ink,
                                  fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        const Icon(Icons.menu_book_rounded,
                            size: 17, color: Bold.brandDeep),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            p.page == null
                                ? p.filename
                                : '${p.filename} · page ${p.page}',
                            style: T.small.copyWith(color: Bold.brandDeep),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Bold.card,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Bold.line),
                      ),
                      child: SelectableText(
                        p.content,
                        // Long-form reading: taller lines than the UI text
                        // around it, because this is the one block on screen
                        // a student will actually read twice.
                        style: T.body.copyWith(color: Bold.ink, height: 1.65),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      widget.isQuestionSource
                          ? 'This is the exact note passage the examiner checked before asking the question.'
                          : 'This is the exact passage the question was built from. A citation that does not trace back to one is refused before it can be stored.',
                      style: T.small.copyWith(color: Bold.slate, height: 1.5),
                    ),
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
