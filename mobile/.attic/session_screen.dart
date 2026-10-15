import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../design/theme.dart';
import '../design/tokens.dart';
import '../mock_data.dart';
import 'widgets/scaffold.dart';

/// The examination screen.
///
/// The strictest rule in the design guide: this reads as an examination, never
/// a chat thread. One question, full width, and the only element on screen
/// carrying that type weight.
class SessionScreen extends StatefulWidget {
  const SessionScreen({super.key, this.focus});

  final String? focus;

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  int? _selected;
  static const _mode = VxMode.examination;

  String get _focusName => widget.focus == null
      ? 'Operating Systems'
      : Mock.concepts
          .firstWhere((c) => c.id == widget.focus,
              orElse: () => Mock.concepts.first)
          .name;

  /// A timed attempt is not discarded on a stray tap.
  Future<void> _confirmExit() async {
    if (!_mode.isTimed) {
      if (mounted) context.pop();
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Leave this examination?'),
        content: const Text(
          'The attempt will be recorded as abandoned and cannot be resumed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if ((leave ?? false) && mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final vx = context.vx;

    return VxScreen(
      onBack: _confirmExit,
      backLabel: 'Exit',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(VxSpace.md, VxSpace.xs, VxSpace.md, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Question 2 of 8 · $_focusName',
                    style: VxType.caption.copyWith(color: vx.muted),
                  ),
                  Text(
                    '02:14',
                    style: VxType.label.copyWith(
                      color: vx.textOn(VxPalette.amber),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: VxSpace.md),

              // The question. No card, no border, no accent rail — it is the
              // largest thing on screen, which is the whole hierarchy.
              Text(
                Mock.question,
                style: VxType.question.copyWith(color: vx.text),
              ),
              const SizedBox(height: VxSpace.md),

              // Position, without a "2 / 8" that invites clock-watching.
              Row(
                children: [
                  for (var i = 0; i < 8; i++) ...[
                    if (i > 0) const SizedBox(width: 3),
                    Expanded(
                      child: Container(
                        height: 2,
                        color: i < 2 ? vx.text : vx.hairline,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),

        VxGroup(
          header: 'Your answer',
          footer: 'Three real responses at different depths — the rubric '
              'separates them.',
          children: [
            for (var i = 0; i < Mock.answers.length; i++)
              _AnswerRow(
                answer: Mock.answers[i],
                selected: _selected == i,
                onTap: () => setState(() => _selected = i),
              ),
          ],
        ),

        const SizedBox(height: VxSpace.lg),
        VxAction(
          label: _selected == null ? 'Choose a response' : 'Submit answer',
          onPressed: _selected == null
              ? null
              : () => context.push('/evaluation?answer=$_selected'),
        ),
      ],
    );
  }
}

class _AnswerRow extends StatelessWidget {
  const _AnswerRow({
    required this.answer,
    required this.selected,
    required this.onTap,
  });

  final MockAnswer answer;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final vx = context.vx;

    return Semantics(
      button: true,
      selected: selected,
      label: '${answer.label} answer. ${answer.text}',
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: VxSpace.md, vertical: VxSpace.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // A radio mark, the native affordance for one-of-many. The
                // previous pass signalled selection with a coloured border and
                // a tinted fill, which reads as decoration rather than state.
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 20,
                    color: selected ? vx.accent : vx.faint,
                  ),
                ),
                const SizedBox(width: VxSpace.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        answer.label,
                        style: VxType.label.copyWith(color: vx.muted),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        answer.text,
                        style: VxType.body.copyWith(color: vx.text, height: 1.45),
                      ),
                    ],
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
