import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/content_hash.dart';
import '../../data/repository.dart';
import '../../design/bold.dart';

/// The knowledge base for one subject (UI/UX §4.3).
///
/// A document list with per-file processing status and an upload area. This
/// exists as its own screen because ingestion is where the product most often
/// disappoints: a scanned PDF yields nothing, and a student who is not told
/// that assumes the app is broken rather than that their file is.
class KnowledgeBaseScreen extends StatefulWidget {
  const KnowledgeBaseScreen({super.key, required this.subject});

  final Subject subject;

  @override
  State<KnowledgeBaseScreen> createState() => _KnowledgeBaseScreenState();
}

class _KnowledgeBaseScreenState extends State<KnowledgeBaseScreen> {
  static const _repo = Repository();
  late Future<List<Document>> _documents;
  String? _stage;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => setState(() {
        _documents = _repo.documents(widget.subject.id);
      });

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _upload() async {
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
      withData: true,
    );
    final file = picked?.files.firstOrNull;
    if (file == null) return;
    final bytes = file.bytes;
    if (bytes == null) {
      _say('Could not read that file.');
      return;
    }
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
      final hash = await compute(contentFingerprint, bytes);
      final doc = await _repo.upload(
        subjectId: widget.subject.id,
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
      if (mounted) setState(() => _stage = 'Reading the document…');
      final result = await _repo.ingest(doc.id);
      if (mounted) {
        _say('Found ${result.concepts} concepts across ${result.pages} pages'
            '${result.edges > 0 ? ', and ${result.edges} prerequisite links' : ''}.');
      }
    } catch (e) {
      _say('$e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _stage = null;
        });
        _load();
      }
    }
  }

  /// Re-runs ingestion on a document that failed.
  ///
  /// Offered rather than automatic: a re-run costs model calls, and a scan
  /// that failed for lacking a text layer will fail again — the student needs
  /// to decide, which is why the failure reason is shown next to the button.
  Future<void> _retry(Document doc) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _stage = 'Re-reading ${doc.filename}…';
    });
    try {
      final result = await _repo.ingest(doc.id);
      if (mounted) _say('Found ${result.concepts} concepts this time.');
    } catch (e) {
      _say('$e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _stage = null;
        });
        _load();
      }
    }
  }

  Future<void> _remove(Document doc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove this document?'),
        content: Text(
          'Questions already asked from ${doc.filename} keep their citations, '
          'but it will no longer be used for new ones.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Bold.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _repo.removeDocument(doc.id);
      _load();
    } catch (e) {
      _say('$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Bold.canvas,
        surfaceTintColor: Colors.transparent,
        title:
            Text('Knowledge base', style: T.heading.copyWith(color: Bold.ink)),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: FutureBuilder<List<Document>>(
              future: _documents,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      const SizedBox(height: 72),
                      Icon(Icons.cloud_off_rounded,
                          size: 36, color: Bold.slate),
                      const SizedBox(height: 14),
                      Text('Could not load your documents',
                          textAlign: TextAlign.center,
                          style: T.title.copyWith(color: Bold.ink)),
                      const SizedBox(height: 8),
                      Text('$snap.error',
                          textAlign: TextAlign.center,
                          style: T.small.copyWith(color: Bold.slate)),
                      const SizedBox(height: 20),
                      OutlinedButton(
                        onPressed: _load,
                        child: const Text('Try again'),
                      ),
                    ],
                  );
                }
                final docs = snap.data ?? const <Document>[];
                return RefreshIndicator(
                  onRefresh: () async => _load(),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                    children: [
                      Text(widget.subject.name,
                          style: T.title.copyWith(color: Bold.ink)),
                      const SizedBox(height: 4),
                      Text(
                        docs.isEmpty
                            ? 'Every question comes from what you upload here.'
                            : '${docs.length} document'
                                '${docs.length == 1 ? '' : 's'} · '
                                '${widget.subject.conceptCount} concepts found',
                        style: T.small.copyWith(color: Bold.slate),
                      ),
                      const SizedBox(height: 18),
                      _UploadArea(
                        busy: _busy,
                        stage: _stage,
                        onTap: _busy ? null : _upload,
                      ),
                      const SizedBox(height: 20),
                      if (docs.isNotEmpty) ...[
                        Text('Your documents',
                            style: T.heading.copyWith(color: Bold.ink)),
                        const SizedBox(height: 10),
                        for (final d in docs)
                          _DocumentTile(
                            document: d,
                            onRetry: () => _retry(d),
                            onRemove: () => _remove(d),
                          ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        'PDF, PowerPoint, Word, Markdown, text, and CSV are supported. '
                        'PDFs exported from the original document work best. '
                        'A photographed or scanned page has no text layer, so '
                        'there is nothing to read.',
                        style: T.small.copyWith(color: Bold.slate, height: 1.5),
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

class _UploadArea extends StatelessWidget {
  const _UploadArea({
    required this.busy,
    required this.stage,
    required this.onTap,
  });

  final bool busy;
  final String? stage;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Bold.wash(Bold.brand),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Bold.brand.withValues(alpha: 0.35)),
          ),
          child: Column(
            children: [
              if (busy)
                const SizedBox(
                  height: 30,
                  width: 30,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              else
                const Icon(Icons.upload_file_rounded,
                    size: 30, color: Bold.brandDeep),
              const SizedBox(height: 12),
              Text(
                // The stage is named rather than shown as a bare spinner: the
                // wait is long enough that "working…" is not reassuring.
                busy ? (stage ?? 'Working…') : 'Add notes',
                style: T.body.copyWith(
                    color: Bold.brandDeep, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                busy
                    ? 'Reading, embedding and mapping concepts.'
                    : 'PDF, PPTX, DOCX, MD, TXT or CSV · up to 25 MB',
                textAlign: TextAlign.center,
                style: T.small.copyWith(color: Bold.brandDeep),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DocumentTile extends StatelessWidget {
  const _DocumentTile({
    required this.document,
    required this.onRetry,
    required this.onRemove,
  });

  final Document document;
  final VoidCallback onRetry;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final failed = document.hasFailed;
    final ready = document.isReady;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Bold.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: failed ? Bold.wash(Bold.danger) : Bold.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: failed
                    ? const Icon(Icons.error_outline_rounded,
                        size: 21, color: Bold.danger)
                    : ready
                        ? const Icon(Icons.check_circle_rounded,
                            size: 21, color: Bold.good)
                        : const CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(document.filename,
                        style: T.body.copyWith(
                            color: Bold.ink, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 3),
                    Text(
                      [
                        if (document.pageCount != null)
                          '${document.pageCount} pages',
                        '${(document.byteSize / 1048576).toStringAsFixed(1)} MB',
                        if (!ready && !failed) document.status,
                      ].join(' · '),
                      style: T.small.copyWith(color: Bold.slate),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.delete_outline_rounded,
                    size: 20, color: Bold.slate),
                tooltip: 'Remove',
                onPressed: onRemove,
              ),
            ],
          ),
          if (failed) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Bold.wash(Bold.danger),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // The specific reason the server recorded, not a shrug.
                  Text(document.errorMessage ?? 'Could not be read.',
                      style:
                          T.small.copyWith(color: Bold.danger, height: 1.45)),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: onRetry,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(40),
                      foregroundColor: Bold.danger,
                      side:
                          BorderSide(color: Bold.danger.withValues(alpha: 0.4)),
                    ),
                    child: const Text('Try reading it again'),
                  ),
                ],
              ),
            ),
          ],
          if (ready) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Reprocess note sources'),
            ),
          ],
        ],
      ),
    );
  }
}
