import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../design/theme.dart';
import '../design/tokens.dart';
import 'widgets/scaffold.dart';

/// First run — reading a freshly uploaded document.
///
/// Audit UX-01: all six specification documents assumed populated data. A new
/// user has no subjects, no readiness and no concepts, and must wait minutes
/// for ingestion before a single question can exist. The screen that decides
/// whether anyone reaches the second screen was designed nowhere.
///
/// So the wait shows the work: named stages, and concepts appearing as they
/// are found. A spinner would hide the one thing worth showing.
class IngestScreen extends StatefulWidget {
  const IngestScreen({super.key});

  @override
  State<IngestScreen> createState() => _IngestScreenState();
}

class _IngestScreenState extends State<IngestScreen> {
  static const _stages = [
    ('Extracting text', '47 pages'),
    ('Splitting into passages', '214 found'),
    ('Mapping concepts', '31 so far'),
    ('Building the prerequisite graph', null),
  ];

  static const _found = [
    'Deadlock',
    'Paging',
    'Semaphore',
    'Scheduling',
    'Virtual memory',
    'TLB',
  ];

  int _stage = 0;
  int _concepts = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Stands in for progress events from the ingestion job.
    _timer = Timer.periodic(const Duration(milliseconds: 900), (t) {
      if (!mounted) return t.cancel();
      setState(() {
        if (_stage < _stages.length - 1) _stage++;
        if (_concepts < _found.length) _concepts++;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vx = context.vx;
    final done = _stage >= _stages.length - 1 && _concepts >= _found.length;

    return VxScreen(
      title: 'Reading your notes',
      subtitle: 'OperatingSystems.pdf · 47 pages',
      children: [
        VxGroup(
          children: [
            for (var i = 0; i < _stages.length; i++)
              _StageRow(
                label: _stages[i].$1,
                detail: _stages[i].$2,
                state: i < _stage
                    ? _StageState.done
                    : i == _stage
                        ? _StageState.active
                        : _StageState.pending,
              ),
          ],
        ),
        if (_concepts > 0)
          VxGroup(
            header: 'Concepts found so far',
            children: [
              Padding(
                padding: const EdgeInsets.all(VxSpace.md),
                child: Wrap(
                  spacing: VxSpace.xs,
                  runSpacing: VxSpace.xs,
                  children: [
                    for (final c in _found.take(_concepts))
                      Text(
                        c,
                        style: VxType.body.copyWith(color: vx.text),
                      ),
                  ],
                ),
              ),
            ],
          ),
        const SizedBox(height: VxSpace.lg),
        VxAction(
          label: done ? 'Start your first viva' : 'Preparing…',
          onPressed: done ? () => context.go('/') : null,
        ),
      ],
    );
  }
}

enum _StageState { done, active, pending }

class _StageRow extends StatelessWidget {
  const _StageRow({
    required this.label,
    required this.detail,
    required this.state,
  });

  final String label;
  final String? detail;
  final _StageState state;

  @override
  Widget build(BuildContext context) {
    final vx = context.vx;

    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: VxSpace.md, vertical: VxSpace.sm),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: switch (state) {
              _StageState.done => Icon(Icons.check_rounded,
                  size: 18, color: vx.textOn(VxPalette.green)),
              _StageState.active => Padding(
                  padding: const EdgeInsets.all(3),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: vx.accent,
                  ),
                ),
              _StageState.pending =>
                Icon(Icons.circle_outlined, size: 16, color: vx.faint),
            },
          ),
          const SizedBox(width: VxSpace.sm),
          Expanded(
            child: Text(
              label,
              style: VxType.body.copyWith(
                color: state == _StageState.pending ? vx.muted : vx.text,
              ),
            ),
          ),
          if (detail != null)
            Text(detail!, style: VxType.caption.copyWith(color: vx.muted)),
        ],
      ),
    );
  }
}
