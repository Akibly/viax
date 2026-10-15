import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../design/components/concept_graph.dart';
import '../design/tokens.dart';
import '../mock_data.dart';
import 'widgets/scaffold.dart';

class SubjectScreen extends StatelessWidget {
  const SubjectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final untested = Mock.concepts.where((c) => c.untested).length;

    return VxScreen(
      title: 'Concepts',
      subtitle: '3 documents · ${Mock.concepts.length} concepts',
      children: [
        VxGroup(
          header: 'Weakest first',
          footer: '$untested concepts have never been examined. They rank '
              'last, not first — an absence of evidence is not evidence of '
              'weakness.',
          children: [
            VxConceptGraph(
              concepts: Mock.concepts,
              onPractise: (c) => context.push('/session?concept=${c.id}'),
            ),
          ],
        ),
        const SizedBox(height: VxSpace.lg),
        VxAction(
          label: 'Examine the whole subject',
          onPressed: () => context.push('/session'),
        ),
      ],
    );
  }
}
