import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';
import '../tokens.dart';

/// Risk level shown alongside readiness.
enum VxRisk {
  low('On track', VxPalette.green),
  medium('Some risk', VxPalette.amber),
  high('At risk', VxPalette.red);

  const VxRisk(this.label, this.hue);
  final String label;
  final VxHue hue;

  static VxRisk fromReadiness(double pct) => switch (pct) {
        >= 75 => VxRisk.low,
        >= 50 => VxRisk.medium,
        _ => VxRisk.high,
      };
}

/// The readiness reading — the one hero on the home screen.
///
/// Rewritten to strip the generated-interface tells the first pass carried: a
/// gradient ground, a coloured glow behind the arc, and a pill badge floating
/// in the corner. What is left is the reading itself, which is all a student
/// came for.
///
/// Two decisions worth keeping:
///
/// **It is a gauge, not a ring.** A ring says "portion of a whole", which
/// readiness is not — it is a reading on a scale, so it gets a scale, with the
/// risk bands drawn into the track. Position carries the meaning; colour only
/// confirms it.
///
/// **Tapping explains the number.** Audit UX-04: this is the most prominent
/// figure in the product and six documents never defined how it is computed.
/// [onExplain] is required so no caller can ship the number without somewhere
/// for "how?" to go.
class VxReadinessCard extends StatefulWidget {
  const VxReadinessCard({
    super.key,
    required this.readiness,
    required this.confidence,
    required this.coverage,
    required this.onExplain,
    this.examDate,
    this.prediction,
  });

  final double readiness;
  final double confidence;
  final double coverage;
  final VoidCallback onExplain;
  final DateTime? examDate;

  /// A plain-language read on the number. Never a predicted grade — dropped
  /// deliberately (audit C-08): nothing in this product can validate one.
  final String? prediction;

  @override
  State<VxReadinessCard> createState() => _VxReadinessCardState();
}

class _VxReadinessCardState extends State<VxReadinessCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: VxMotion.scoreReveal,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.reduceMotion) {
      _controller.value = 1;
    } else if (!_controller.isAnimating && _controller.value == 0) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vx = context.vx;
    final risk = VxRisk.fromReadiness(widget.readiness);

    return Semantics(
      label: 'Viva readiness ${widget.readiness.round()} percent, '
          '${risk.label.toLowerCase()}. Confidence ${widget.confidence.round()} '
          'percent, coverage ${widget.coverage.round()} percent. '
          'Opens how this is calculated.',
      button: true,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: VxSpace.md),
          child: Material(
            // Flat. The examiner navy is the product's identity; a gradient
            // and a glow on top of it were decoration, not identity.
            color: vx.examinerChrome,
            borderRadius: BorderRadius.circular(VxRadius.card),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: widget.onExplain,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    VxSpace.md, VxSpace.md, VxSpace.md, VxSpace.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Viva readiness',
                          style: VxType.label.copyWith(
                            color: Colors.white.withValues(alpha: 0.72),
                          ),
                        ),
                        // A word and a dot, not a bordered pill. The status
                        // still reads without colour.
                        Row(
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: risk.hue.tint,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              risk.label,
                              style: VxType.label.copyWith(color: risk.hue.tint),
                            ),
                          ],
                        ),
                      ],
                    ),
                    AnimatedBuilder(
                      animation: _controller,
                      builder: (context, _) {
                        final t =
                            Curves.easeOutCubic.transform(_controller.value);
                        return _Gauge(value: widget.readiness * t);
                      },
                    ),
                    if (widget.prediction != null)
                      Text(
                        widget.prediction!,
                        style: VxType.caption.copyWith(
                          color: Colors.white.withValues(alpha: 0.66),
                          height: 1.45,
                        ),
                      ),
                    const SizedBox(height: VxSpace.md),
                    Row(
                      children: [
                        _Stat(label: 'Confidence', value: '${widget.confidence.round()}%'),
                        _Stat(label: 'Coverage', value: '${widget.coverage.round()}%'),
                        _Stat(
                          label: widget.examDate == null ? 'Exam date' : 'Viva in',
                          value: _examLabel(),
                          highlight: _isUrgent(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool _isUrgent() {
    if (widget.examDate == null) return false;
    return _daysLeft() <= 3 && _daysLeft() >= 0;
  }

  int _daysLeft() {
    final now = DateTime.now();
    final d = widget.examDate!;
    return DateTime(d.year, d.month, d.day)
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
  }

  String _examLabel() {
    if (widget.examDate == null) return 'Not set';
    return switch (_daysLeft()) {
      < 0 => 'Passed',
      0 => 'Today',
      1 => '1 day',
      final d => '$d days',
    };
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.highlight = false});

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: VxType.caption.copyWith(
              color: Colors.white.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: VxType.metricSmall.copyWith(
              color: highlight ? VxPalette.amber.tint : Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _Gauge extends StatelessWidget {
  const _Gauge({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 104,
      width: double.infinity,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Positioned.fill(child: CustomPaint(painter: _GaugePainter(value: value))),
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value.round().toString(),
                  style: VxType.metric.copyWith(color: Colors.white),
                ),
                Text(
                  '%',
                  style: VxType.heading.copyWith(
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A shallow arc over a track banded by risk.
///
/// The bands let a student see that 62 sits inside "some risk" without reading
/// the label — position does the work, so the reading survives greyscale and
/// colour-blindness alike.
class _GaugePainter extends CustomPainter {
  const _GaugePainter({required this.value});

  final double value;

  static const _start = math.pi * 0.9;
  static const _sweep = math.pi * 1.2;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 8.0;
    final radius = math.min(size.width / 2, size.height) - stroke;
    final centre = Offset(size.width / 2, size.height - stroke / 2);
    final rect = Rect.fromCircle(center: centre, radius: radius);

    for (final (from, to, colour) in <(double, double, Color)>[
      (0.0, 0.50, VxPalette.red.tint),
      (0.50, 0.75, VxPalette.amber.tint),
      (0.75, 1.0, VxPalette.green.tint),
    ]) {
      canvas.drawArc(
        rect,
        _start + _sweep * from,
        _sweep * (to - from),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = colour.withValues(alpha: 0.22),
      );
    }

    final fraction = (value / 100).clamp(0.0, 1.0);
    if (fraction <= 0) return;

    // One solid colour, not a sweep gradient. The gradient was ornament and
    // it made the reading harder to locate, not easier.
    canvas.drawArc(
      rect,
      _start,
      _sweep * fraction,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = Colors.white,
    );

    final angle = _start + _sweep * fraction;
    final tip = Offset(
      centre.dx + radius * math.cos(angle),
      centre.dy + radius * math.sin(angle),
    );
    canvas.drawCircle(tip, stroke / 2 + 2.5, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.value != value;
}
