import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../design/theme.dart';
import '../design/tokens.dart';
import 'widgets/scaffold.dart';

/// How readiness is calculated.
///
/// Audit UX-04: readiness is the most prominent number in the product and six
/// specification documents never defined how it is computed. A score a student
/// cannot interrogate is a score they should not trust, so the derivation sits
/// one tap from the figure.
class ExplainScreen extends StatelessWidget {
  const ExplainScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vx = context.vx;

    return VxScreen(
      onBack: () => context.pop(),
      backLabel: 'Home',
      title: 'How readiness is calculated',
      children: [
        VxGroup(
          children: [
            VxRow(
              title: 'Concept coverage',
              detail: 'How much of your notes you have been examined on, '
                  'weighted by how much space each concept takes up in them.',
              trailing: Text('81%',
                  style: VxType.metricSmall.copyWith(color: vx.text)),
            ),
            VxRow(
              title: 'Mastery, decayed by time',
              detail: 'Older readings count for less. Memory fades, so a score '
                  'from three weeks ago should not carry full weight.',
              trailing: Text('58%',
                  style: VxType.metricSmall.copyWith(color: vx.text)),
            ),
            VxRow(
              title: 'Untested penalty',
              detail: 'File Systems and Inode have never been examined. An '
                  'untested concept is a risk, not a neutral.',
              trailing: Text(
                '−9',
                style: VxType.metricSmall
                    .copyWith(color: vx.textOn(VxPalette.red)),
              ),
            ),
          ],
        ),

        VxGroup(
          header: 'What we do not show',
          footer: 'There is no ground truth to validate a grade prediction '
              'against, so it would be a confident guess dressed as a '
              'measurement. It was dropped deliberately.',
          children: const [
            VxRow(
              title: 'A predicted grade',
              detail: 'The original proposal wanted "Estimated Viva '
                  'Performance: B+".',
            ),
          ],
        ),
      ],
    );
  }
}
