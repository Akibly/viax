import 'package:flutter/material.dart';

import '../theme.dart';
import '../tokens.dart';

/// One concept's standing in a subject.
@immutable
class VxConcept {
  const VxConcept({
    required this.id,
    required this.name,
    required this.mastery,
    this.delta,
    this.blockedBy,
    this.untested = false,
    this.dueLabel,
  });

  final String id;
  final String name;
  final double mastery;

  /// Change since the previous reading. Null on a first reading, which is not
  /// the same as no change and is not drawn the same way.
  final double? delta;

  /// The prerequisite actually holding this concept back.
  ///
  /// The line no competing study app can draw, and the reason the schema grew
  /// a `concept_edge` table (audit DB-01). "You are failing Deadlock" is a
  /// score; "you are failing Deadlock because you never learned Mutual
  /// Exclusion" is a diagnosis.
  final String? blockedBy;

  /// Never examined — an absence, not a low score. Rendering both as 0% would
  /// lie about one of them.
  final bool untested;

  final String? dueLabel;

  VxSeverity get severity => VxSeverity.fromMastery(mastery);
}

/// Concepts as a ranked list, weakest first.
///
/// Not a radar chart, which the design guide asked for: with twenty-plus
/// concepts the labels collide and the shape carries no ordering. A ranked
/// list answers the only question a student has — *what do I fix first?* —
/// and every row is one tap into practice on that concept.
class VxConceptGraph extends StatelessWidget {
  const VxConceptGraph({
    super.key,
    required this.concepts,
    required this.onPractise,
    this.maxRows,
  });

  final List<VxConcept> concepts;
  final void Function(VxConcept) onPractise;
  final int? maxRows;

  @override
  Widget build(BuildContext context) {
    final vx = context.vx;
    // Untested last: "unknown" is not "worst".
    final sorted = [...concepts]..sort((a, b) {
        if (a.untested != b.untested) return a.untested ? 1 : -1;
        return a.mastery.compareTo(b.mastery);
      });
    final rows = maxRows == null ? sorted : sorted.take(maxRows!).toList();

    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0)
            Padding(
              padding: const EdgeInsets.only(left: VxSpace.md),
              child: Divider(height: 1, thickness: 1, color: vx.hairline),
            ),
          _ConceptRow(concept: rows[i], onTap: () => onPractise(rows[i])),
        ],
      ],
    );
  }
}

class _ConceptRow extends StatelessWidget {
  const _ConceptRow({required this.concept, required this.onTap});

  final VxConcept concept;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final vx = context.vx;
    final hue = concept.severity.hue;

    return Semantics(
      button: true,
      label: concept.untested
          ? '${concept.name}, not yet examined. Opens practice.'
          : '${concept.name}, ${concept.mastery.round()} percent, '
              '${concept.severity.label}.'
              '${concept.blockedBy != null ? ' Held back by ${concept.blockedBy}.' : ''}'
              ' Opens practice.',
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: VxSpace.md, vertical: VxSpace.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        concept.name,
                        style: VxType.body.copyWith(color: vx.text),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      _MasteryBar(
                        mastery: concept.mastery,
                        hue: hue,
                        untested: concept.untested,
                      ),
                      const SizedBox(height: 6),
                      // Status, prerequisite and due date as one quiet
                      // secondary line. Previously each was its own coloured
                      // chip, and three badges per row is noise, not signal.
                      Text(
                        _secondary(),
                        style: VxType.caption.copyWith(
                          color: vx.muted,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: VxSpace.sm),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      concept.untested ? '—' : '${concept.mastery.round()}%',
                      style: VxType.metricSmall.copyWith(
                        color: concept.untested ? vx.muted : vx.text,
                      ),
                    ),
                    if (!concept.untested && concept.delta != null)
                      _Delta(value: concept.delta!),
                  ],
                ),
                const SizedBox(width: 2),
                Icon(Icons.chevron_right_rounded, size: 20, color: vx.faint),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _secondary() {
    if (concept.untested) return 'Not yet examined';
    final parts = <String>[concept.severity.label];
    if (concept.blockedBy != null) {
      parts.add('held back by ${concept.blockedBy}');
    }
    if (concept.dueLabel != null) parts.add(concept.dueLabel!.toLowerCase());
    return parts.join(' · ');
  }
}

/// The mastery bar — the one place semantic colour still earns its place,
/// because it encodes the value rather than labelling it.
class _MasteryBar extends StatelessWidget {
  const _MasteryBar({
    required this.mastery,
    required this.hue,
    required this.untested,
  });

  final double mastery;
  final VxHue hue;
  final bool untested;

  @override
  Widget build(BuildContext context) {
    final vx = context.vx;

    if (untested) {
      // An empty track, not a zero-filled one: no reading was taken.
      return Container(
        height: 4,
        decoration: BoxDecoration(
          color: vx.hairline,
          borderRadius: BorderRadius.circular(2),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: Stack(
        children: [
          Container(height: 4, color: vx.cardRaised),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: (mastery / 100).clamp(0.0, 1.0)),
            duration: context.motion(VxMotion.scoreReveal),
            curve: VxMotion.enter,
            builder: (context, t, _) => FractionallySizedBox(
              widthFactor: t,
              child: Container(height: 4, color: vx.textOn(hue)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Delta extends StatelessWidget {
  const _Delta({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final vx = context.vx;
    if (value.abs() < 0.5) {
      return Text('no change', style: VxType.caption.copyWith(color: vx.muted));
    }
    final up = value > 0;
    return Text(
      '${up ? '+' : '−'}${value.abs().round()}',
      style: VxType.caption.copyWith(
        color: vx.textOn(up ? VxPalette.green : VxPalette.red),
      ),
    );
  }
}
