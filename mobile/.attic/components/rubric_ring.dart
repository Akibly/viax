import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import '../tokens.dart';

/// One scored rubric dimension.
@immutable
class VxDimension {
  const VxDimension({
    required this.name,
    required this.score,
    this.unavailableReason,
  });

  final String name;

  /// 0–100. Ignored when [unavailableReason] is set.
  final double score;

  /// Why this dimension could not be scored.
  ///
  /// Exists because of audit AI-02. `Confidence` is in the rubric, but it is
  /// prosodic — carried by pace and hesitation, not by word choice. Scored
  /// from typed text it measures hedging vocabulary and punishes the
  /// appropriately careful, and the product's own second persona is "anxious
  /// about oral exams specifically".
  ///
  /// So an unscorable dimension says so. Quietly filling it with a plausible
  /// number would be the worse failure precisely because nobody would notice.
  final String? unavailableReason;

  bool get isScored => unavailableReason == null;
}

/// The composite score, revealed rather than displayed.
///
/// The design guide's principle is *earn the feedback*: a number that appears
/// instantly reads as generated; one that resolves over ~800ms reads as
/// diagnosed. This is the only place in VivaX where slower is deliberately
/// better, and the haptic tick on completion is what makes it land as a
/// verdict rather than an animation.
///
/// Under reduced motion the value is simply present. Withholding information
/// from someone who asked for less motion would be the wrong reading of the
/// setting.
class VxScoreRing extends StatefulWidget {
  const VxScoreRing({
    super.key,
    required this.score,
    required this.mode,
    this.size = 158,
  });

  final double score;
  final VxMode mode;
  final double size;

  @override
  State<VxScoreRing> createState() => _VxScoreRingState();
}

class _VxScoreRingState extends State<VxScoreRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: VxMotion.scoreReveal,
  );
  bool _ticked = false;

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && !_ticked) {
        _ticked = true;
        HapticFeedback.mediumImpact();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.reduceMotion) {
      _controller.value = 1;
      _ticked = true;
    } else if (_controller.value == 0 && !_controller.isAnimating) {
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
    final hue = widget.mode.hue;

    return Semantics(
      label: 'Score ${widget.score.round()} out of 100',
      child: ExcludeSemantics(
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final t = VxMotion.settle.transform(_controller.value).clamp(0.0, 1.0);
              final shown = widget.score * t;
              return Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: Size.square(widget.size),
                    painter: _RingPainter(
                      fraction: shown / 100,
                      track: vx.cardRaised,
                      // fillUnderWhite() is the darkened variant; on the ring
                      // it also happens to be the one that reads clearly
                      // against both card surfaces.
                      colour: vx.isDark ? hue.tint : hue.strong,
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        shown.round().toString(),
                        style: VxType.metric.copyWith(
                          fontSize: widget.size * 0.24,
                          color: vx.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'OUT OF 100',
                        style: VxType.eyebrow.copyWith(color: vx.muted),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.fraction,
    required this.track,
    required this.colour,
  });

  final double fraction;
  final Color track;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 11.0;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: size.width / 2 - stroke / 2,
    );

    canvas.drawCircle(
      rect.center,
      rect.width / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = track,
    );

    if (fraction <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * fraction.clamp(0.0, 1.0),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = colour,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction || old.colour != colour || old.track != track;
}

/// The per-dimension breakdown under the ring.
///
/// Dimensions with no score are rendered as explicitly unavailable, with the
/// reason, rather than omitted. Omitting them would leave a student wondering
/// whether the rubric changed; a number would be a fabrication.
class VxRubricBreakdown extends StatelessWidget {
  const VxRubricBreakdown({super.key, required this.dimensions});

  final List<VxDimension> dimensions;

  @override
  Widget build(BuildContext context) {
    final vx = context.vx;
    return Column(
      children: [
        for (var i = 0; i < dimensions.length; i++) ...[
          if (i > 0) Divider(height: 1, color: vx.hairline),
          _DimensionRow(dimension: dimensions[i]),
        ],
      ],
    );
  }
}

class _DimensionRow extends StatelessWidget {
  const _DimensionRow({required this.dimension});

  final VxDimension dimension;

  @override
  Widget build(BuildContext context) {
    final vx = context.vx;

    if (!dimension.isScored) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: VxSpace.xs),
        child: Row(
          children: [
            Expanded(
              child: Text(
                dimension.name,
                style: VxType.label.copyWith(color: vx.muted),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: vx.cardRaised,
                borderRadius: BorderRadius.circular(VxRadius.chip),
              ),
              child: Text(
                dimension.unavailableReason!,
                style: VxType.caption.copyWith(color: vx.muted),
              ),
            ),
          ],
        ),
      );
    }

    return Semantics(
      label: '${dimension.name}, ${dimension.score.round()} out of 100',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: VxSpace.xs),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  dimension.name,
                  style: VxType.label.copyWith(color: vx.text),
                ),
              ),
              SizedBox(
                width: 76,
                height: 6,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(
                    begin: 0,
                    end: (dimension.score / 100).clamp(0.0, 1.0),
                  ),
                  duration: context.motion(VxMotion.scoreReveal),
                  curve: VxMotion.enter,
                  builder: (context, t, _) => Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: vx.cardRaised,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      FractionallySizedBox(
                        widthFactor: t,
                        child: Container(
                          decoration: BoxDecoration(
                            color: vx.textOn(VxPalette.focus),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: VxSpace.xs),
              SizedBox(
                width: 26,
                child: Text(
                  dimension.score.round().toString(),
                  textAlign: TextAlign.right,
                  style: VxType.label.copyWith(
                    color: vx.text,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
