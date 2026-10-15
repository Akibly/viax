import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../design/components/rubric_ring.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../mock_data.dart';
import 'widgets/scaffold.dart';

class EvaluationScreen extends StatefulWidget {
  const EvaluationScreen({super.key, required this.answer});

  final MockAnswer answer;

  @override
  State<EvaluationScreen> createState() => _EvaluationScreenState();
}

class _EvaluationScreenState extends State<EvaluationScreen> {
  bool _showPassage = false;

  @override
  Widget build(BuildContext context) {
    final vx = context.vx;
    final a = widget.answer;

    return VxScreen(
      onBack: () => context.pop(),
      backLabel: 'Session',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              VxSpace.md, VxSpace.md, VxSpace.md, 0),
          child: Column(
            children: [
              Center(child: VxScoreRing(score: a.score, mode: a.mode)),
              const SizedBox(height: VxSpace.md),
              Text(
                a.verdict,
                textAlign: TextAlign.center,
                style: VxType.heading.copyWith(color: vx.text),
              ),
              const SizedBox(height: VxSpace.xs),
              Text(
                a.note,
                textAlign: TextAlign.center,
                style: VxType.prose.copyWith(color: vx.muted),
              ),
            ],
          ),
        ),

        VxGroup(
          header: 'Rubric',
          footer: 'Confidence is carried by how you speak, not what you write, '
              'so a typed answer cannot supply it.',
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: VxSpace.md),
              child: VxRubricBreakdown(dimensions: a.dimensions),
            ),
          ],
        ),

        if (a.gapTitle != null)
          VxGroup(
            header: 'What was missing',
            children: [
              VxRow(title: a.gapTitle!, detail: a.gapBody),
              VxRow(
                title: 'OperatingSystems.pdf',
                detail: 'Page 47 · the passage this gap came from',
                onTap: () => setState(() => _showPassage = !_showPassage),
                trailing: Icon(
                  _showPassage
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 20,
                  color: vx.faint,
                ),
              ),
              if (_showPassage)
                Container(
                  width: double.infinity,
                  color: vx.cardRaised,
                  padding: const EdgeInsets.all(VxSpace.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        Mock.passage,
                        style: VxType.prose.copyWith(color: vx.text),
                      ),
                      const SizedBox(height: VxSpace.xs),
                      Text(
                        'Chunk 0x1F4 · resolved server-side',
                        style: VxType.caption.copyWith(color: vx.muted),
                      ),
                    ],
                  ),
                ),
            ],
          )
        else
          VxGroup(
            header: 'What was missing',
            children: [
              VxRow(
                title: 'Nothing',
                detail: 'The examiner would move to a harder follow-up rather '
                    'than probe this one further.',
              ),
            ],
          ),

        const SizedBox(height: VxSpace.lg),
        VxAction(label: 'Next question', onPressed: () => context.pop()),
        // An assessment product must let the assessed contest the assessment.
        VxAction(
          label: 'I think this score is wrong',
          secondary: true,
          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Challenge recorded. It goes to the calibration set.'),
            ),
          ),
        ),
      ],
    );
  }
}
