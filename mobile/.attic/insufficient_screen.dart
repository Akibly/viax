import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../design/theme.dart';
import '../design/tokens.dart';
import 'widgets/scaffold.dart';

/// Not enough material to examine on.
///
/// The product's core promise is that questions come only from the student's
/// own uploaded notes. Ask for a viva on three pages and an ungrounded system
/// will cheerfully generate ten questions from what the model already knows —
/// silently breaking the one thing separating this from a chatbot.
///
/// So the coverage guard counts distinct concepts and refuses below the
/// threshold, naming the number and offering a way forward. Declining is the
/// feature; a fabricated viva would be the bug nobody notices.
class InsufficientScreen extends StatelessWidget {
  const InsufficientScreen({super.key});

  static const _minConcepts = 5;
  static const _found = 2;

  @override
  Widget build(BuildContext context) {
    final vx = context.vx;

    return VxScreen(
      onBack: () => context.pop(),
      backLabel: 'Home',
      title: 'Not enough to examine you on',
      subtitle: 'Computer Networks · 3 pages uploaded',
      children: [
        VxGroup(
          footer: 'Below this, questions would come from general knowledge '
              'rather than your material — which is the one thing this is '
              'meant not to do.',
          children: [
            VxRow(
              title: 'Concepts found',
              trailing: Text(
                '$_found',
                style: VxType.metricSmall
                    .copyWith(color: vx.textOn(VxPalette.amber)),
              ),
            ),
            VxRow(
              title: 'Needed for a viva',
              trailing: Text(
                '$_minConcepts',
                style: VxType.metricSmall.copyWith(color: vx.text),
              ),
            ),
          ],
        ),
        const SizedBox(height: VxSpace.lg),
        VxAction(label: 'Add more notes', onPressed: () {}),
        VxAction(
          label: 'Examine me on Operating Systems instead',
          secondary: true,
          onPressed: () => context.go('/'),
        ),
      ],
    );
  }
}
