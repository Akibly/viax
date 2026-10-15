import 'package:flutter/material.dart';

import '../design/theme.dart';
import '../design/tokens.dart';
import '../mock_data.dart';
import 'widgets/scaffold.dart';

/// The revision plan.
///
/// Scheduled by FSRS — the open-source algorithm benchmarked across hundreds
/// of millions of reviews, roughly 20–30% fewer reviews for the same
/// retention, and Anki's default. The four tabs are *views over a due date*,
/// not stored buckets (audit DB-04), which is what lets an item roll over
/// instead of silently going stale.
class RevisionScreen extends StatefulWidget {
  const RevisionScreen({super.key});

  @override
  State<RevisionScreen> createState() => _RevisionScreenState();
}

class _RevisionScreenState extends State<RevisionScreen> {
  int _tab = 0;

  static const _tabs = ['Today', 'Tomorrow', 'This week', 'Before the viva'];

  bool _inTab(RevisionItem r) => switch (_tab) {
        0 => r.dueInDays <= 0,
        1 => r.dueInDays == 1,
        2 => r.dueInDays > 1 && r.dueInDays < 7,
        _ => r.dueInDays >= 7,
      };

  @override
  Widget build(BuildContext context) {
    final vx = context.vx;
    final items = Mock.revision.where(_inTab).toList();
    final remaining = items.where((r) => !r.done).length;
    final minutes =
        items.where((r) => !r.done).fold<int>(0, (sum, r) => sum + r.minutes);

    return VxScreen(
      title: 'Revision',
      subtitle: remaining == 0
          ? 'Nothing left in this window.'
          : '$remaining to go · about $minutes minutes',
      children: [
        // A segmented control, not a row of coloured pills.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: VxSpace.md),
          child: SegmentedButton<int>(
            segments: [
              for (var i = 0; i < _tabs.length; i++)
                ButtonSegment(value: i, label: Text(_tabs[i])),
            ],
            selected: {_tab},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _tab = s.first),
            style: SegmentedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              textStyle: VxType.caption,
            ),
          ),
        ),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.all(VxSpace.xl),
            child: Text(
              'Nothing scheduled in this window.',
              textAlign: TextAlign.center,
              style: VxType.body.copyWith(color: vx.muted),
            ),
          )
        else
          VxGroup(
            footer: 'Intervals come from your own review history. Answer well '
                'and an item moves further out; miss it and it comes back '
                'sooner.',
            children: [
              for (final r in items)
                _RevisionRow(
                  item: r,
                  onToggle: () => setState(() => r.done = !r.done),
                ),
            ],
          ),
      ],
    );
  }
}

class _RevisionRow extends StatelessWidget {
  const _RevisionRow({required this.item, required this.onToggle});

  final RevisionItem item;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final vx = context.vx;

    return Semantics(
      checked: item.done,
      label: '${item.title}, ${item.minutes} minutes',
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: VxSpace.md, vertical: VxSpace.sm),
            child: Row(
              children: [
                Icon(
                  item.done
                      ? Icons.check_circle_rounded
                      : Icons.circle_outlined,
                  size: 22,
                  color: item.done ? vx.textOn(VxPalette.green) : vx.faint,
                ),
                const SizedBox(width: VxSpace.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: VxType.body.copyWith(
                          color: item.done ? vx.muted : vx.text,
                          decoration:
                              item.done ? TextDecoration.lineThrough : null,
                          decorationColor: vx.muted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${item.minutes} min · next interval '
                        '${item.intervalDays}d',
                        style: VxType.caption.copyWith(color: vx.muted),
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
