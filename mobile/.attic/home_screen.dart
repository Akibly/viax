import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../design/components/concept_graph.dart';
import '../design/components/readiness_card.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../mock_data.dart';
import 'widgets/scaffold.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vx = context.vx;
    final dueToday =
        Mock.concepts.where((c) => c.dueLabel == 'Due today').toList();

    return VxScreen(
      title: 'Operating Systems',
      subtitle: 'Viva in 3 days',
      children: [
        VxReadinessCard(
          readiness: Mock.readiness,
          confidence: Mock.confidence,
          coverage: Mock.coverage,
          examDate: Mock.examDate,
          prediction: Mock.prediction,
          onExplain: () => context.push('/explain'),
        ),

        VxGroup(
          header: 'Due today',
          children: [
            VxConceptGraph(
              concepts: dueToday,
              maxRows: 3,
              onPractise: (c) => context.push('/session?concept=${c.id}'),
            ),
          ],
        ),

        VxGroup(
          header: 'Weakest concepts',
          children: [
            VxConceptGraph(
              concepts: Mock.concepts,
              maxRows: 4,
              onPractise: (c) => context.push('/session?concept=${c.id}'),
            ),
            VxRow(
              title: 'All ${Mock.concepts.length} concepts',
              onTap: () => context.go('/concepts'),
            ),
          ],
        ),

        const SizedBox(height: VxSpace.lg),
        VxAction(
          label: 'Begin examination',
          onPressed: () => context.push('/session'),
        ),
        const SizedBox(height: VxSpace.md),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: VxSpace.md),
          child: Text(
            'Sample data. No backend connected.',
            textAlign: TextAlign.center,
            style: VxType.caption.copyWith(color: vx.muted),
          ),
        ),
      ],
    );
  }
}
