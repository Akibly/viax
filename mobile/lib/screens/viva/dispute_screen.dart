import 'package:flutter/material.dart';

import '../../data/repository.dart';
import '../../design/bold.dart';

/// Challenge a mark.
///
/// Nowhere in the specification could a student say "that is wrong". For a
/// product that assesses people that is both a fairness gap and a wasted
/// asset: every disagreement is a labelled example, and the disagreement rate
/// is the cheapest calibration signal available.
///
/// It is deliberately not a free-text box alone. A category makes the
/// complaint countable, and counting is what turns a grumble into evidence
/// that a prompt or a rubric weight needs changing.
class DisputeScreen extends StatefulWidget {
  const DisputeScreen({
    super.key,
    required this.evaluationId,
    required this.score,
    required this.question,
  });

  final String evaluationId;
  final double score;
  final String question;

  @override
  State<DisputeScreen> createState() => _DisputeScreenState();
}

class _DisputeScreenState extends State<DisputeScreen> {
  static const _repo = Repository();
  final _detail = TextEditingController();
  String? _reason;
  bool _busy = false;
  bool _sent = false;

  static const _reasons = <(String, String, String)>[
    (
      'marked_wrong',
      'It marked something wrong that was right',
      'The examiner disagreed with a point you are confident about.',
    ),
    (
      'missed_point',
      'It missed a point I did make',
      'You covered it, but the mark says you did not.',
    ),
    (
      'outside_notes',
      'The question was outside my notes',
      'It asked about something your uploaded material does not cover.',
    ),
    (
      'too_harsh',
      'The score feels too harsh',
      'The answer was reasonable and the number does not reflect that.',
    ),
    (
      'bad_citation',
      'A citation did not support the gap',
      'You opened the passage and it did not say what the gap claimed.',
    ),
  ];

  @override
  void dispose() {
    _detail.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_reason == null) return;
    setState(() => _busy = true);
    try {
      await _repo.disputeEvaluation(
        evaluationId: widget.evaluationId,
        reason: _reason!,
        detail: _detail.text.trim(),
      );
      if (mounted) setState(() => _sent = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Bold.canvas,
        surfaceTintColor: Colors.transparent,
        title: Text('Challenge this mark',
            style: T.heading.copyWith(color: Bold.ink)),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: _sent ? _thanks() : _form(),
          ),
        ),
      ),
    );
  }

  Widget _thanks() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.mark_email_read_outlined,
                size: 40, color: Bold.good),
            const SizedBox(height: 16),
            Text('Challenge recorded',
                style: T.title.copyWith(color: Bold.ink)),
            const SizedBox(height: 8),
            Text(
              'It goes into the set the examiner is calibrated against. Marks '
              'people push back on are exactly the ones worth re-checking.',
              textAlign: TextAlign.center,
              style: T.body.copyWith(color: Bold.slate, height: 1.55),
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Back to the evaluation'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _form() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
      children: [
        Container(
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
                children: [
                  Text('Marked ${widget.score.round()}',
                      style: T.stat.copyWith(fontSize: 20, color: Bold.ink)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('out of 100',
                        style: T.small.copyWith(color: Bold.slate)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(widget.question,
                  style: T.small.copyWith(color: Bold.slate, height: 1.5)),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Text('What went wrong?', style: T.heading.copyWith(color: Bold.ink)),
        const SizedBox(height: 10),
        for (final (code, label, hint) in _reasons)
          _ReasonTile(
            label: label,
            hint: hint,
            selected: _reason == code,
            onTap: () => setState(() => _reason = code),
          ),
        const SizedBox(height: 18),
        Text('Anything to add', style: T.small.copyWith(color: Bold.slate)),
        const SizedBox(height: 6),
        TextField(
          controller: _detail,
          maxLines: 5,
          minLines: 3,
          textCapitalization: TextCapitalization.sentences,
          style: T.body.copyWith(color: Bold.ink),
          decoration: InputDecoration(
            hintText: 'Optional, but it makes the challenge far more useful.',
            hintStyle: T.small.copyWith(color: Bold.slate),
            filled: true,
            fillColor: Bold.card,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Bold.line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Bold.line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Bold.brand, width: 2),
            ),
            contentPadding: const EdgeInsets.all(14),
          ),
        ),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: _reason == null || _busy ? null : _send,
          child: _busy
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('Send challenge'),
        ),
        const SizedBox(height: 12),
        Text(
          // Honest about what happens next: no promise of a re-mark that the
          // product cannot currently keep.
          'Your mark does not change automatically. Challenges are reviewed '
          'against the human-scored set the examiner is calibrated on.',
          style: T.small.copyWith(color: Bold.slate, height: 1.5),
        ),
      ],
    );
  }
}

class _ReasonTile extends StatelessWidget {
  const _ReasonTile({
    required this.label,
    required this.hint,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String hint;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: selected ? Bold.wash(Bold.brand) : Bold.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: selected ? Bold.brand : Bold.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 20,
                color: selected ? Bold.brand : Bold.line,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: T.body.copyWith(
                          color: Bold.ink,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                        )),
                    const SizedBox(height: 3),
                    Text(hint,
                        style:
                            T.small.copyWith(color: Bold.slate, height: 1.4)),
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
