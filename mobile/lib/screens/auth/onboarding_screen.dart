import 'package:flutter/material.dart';

import '../../design/bold.dart';

/// Three screens establishing the "real examiner" positioning (UI/UX §4.1).
///
/// The job is to reset an expectation before the student meets the product:
/// this is not another chatbot that answers questions, it is something that
/// asks them. Three pages, skippable, ending at the sign-up door.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pages = PageController();
  int _index = 0;

  static const _slides = <(_Art, String, String)>[
    (
      _Art.examiner,
      'An examiner, not a chatbot',
      'ViaX asks the questions. It follows up when an answer is thin, and it '
          'marks you against a rubric — the way a real viva works.',
    ),
    (
      _Art.notes,
      'Grounded in your own notes',
      'Upload your syllabus and every question comes from it. Nothing is '
          'invented, and every gap it finds cites the page it came from.',
    ),
    (
      _Art.graph,
      'Find out what is actually weak',
      'You get a concept-by-concept map and a revision plan — including which '
          'prerequisite is holding a topic back, not just the score.',
    ),
  ];

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final last = _index == _slides.length - 1;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 14, 12, 0),
                  child: Row(
                    children: [
                      const ViaXMark(size: 36, radius: 10),
                      const SizedBox(width: 10),
                      Text('ViaX',
                          style: T.title.copyWith(
                            color: Bold.ink,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.6,
                          )),
                      const Spacer(),
                      Text(
                        '${_index + 1} / ${_slides.length}',
                        style: T.small.copyWith(color: Bold.slate),
                      ),
                      const SizedBox(width: 10),
                      TextButton(
                        onPressed: widget.onDone,
                        child: Text('Skip',
                            style: T.body.copyWith(color: Bold.slate)),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _pages,
                    itemCount: _slides.length,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (context, i) {
                      final (art, title, body) = _slides[i];
                      return SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              height: 220,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: Bold.card,
                                borderRadius: BorderRadius.circular(22),
                                border: Border.all(color: Bold.line),
                              ),
                              child: CustomPaint(
                                size: const Size(double.infinity, 220),
                                painter: _SlidePainter(art),
                              ),
                            ),
                            const SizedBox(height: 34),
                            Text(title,
                                style: T.display.copyWith(color: Bold.ink)),
                            const SizedBox(height: 12),
                            Text(body,
                                style: T.body
                                    .copyWith(color: Bold.slate, height: 1.55)),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < _slides.length; i++)
                      AnimatedContainer(
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 220),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: i == _index ? 22 : 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: i == _index ? Bold.brand : Bold.line,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                  child: FilledButton(
                    onPressed: () {
                      if (last) {
                        widget.onDone();
                      } else if (MediaQuery.disableAnimationsOf(context)) {
                        _pages.jumpToPage(_index + 1);
                      } else {
                        _pages.nextPage(
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOutCubic,
                        );
                      }
                    },
                    child: Text(last ? 'Get started' : 'Next'),
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

enum _Art { examiner, notes, graph }

/// Line illustrations, drawn rather than shipped as assets.
///
/// UI/UX §2.6 asks for custom line illustrations to keep empty and
/// introductory states warm rather than clinical. Painting them keeps the
/// bundle small and lets them take their colour from the theme.
class _SlidePainter extends CustomPainter {
  const _SlidePainter(this.art);

  final _Art art;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..color = Bold.brand;
    final soft = Paint()..color = Bold.wash(Bold.brand);
    final w = size.width, h = size.height;

    switch (art) {
      case _Art.examiner:
        // A desk, and one question suspended above it.
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.18, h * 0.52, w * 0.64, h * 0.30),
            const Radius.circular(10),
          ),
          soft,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.18, h * 0.52, w * 0.64, h * 0.30),
            const Radius.circular(10),
          ),
          stroke,
        );
        canvas.drawCircle(Offset(w * 0.5, h * 0.26), h * 0.13, soft);
        canvas.drawCircle(Offset(w * 0.5, h * 0.26), h * 0.13, stroke);
        final q = TextPainter(
          text: TextSpan(
            text: '?',
            style: TextStyle(
              fontSize: h * 0.16,
              fontWeight: FontWeight.w800,
              color: Bold.brandDeep,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        q.paint(canvas, Offset(w * 0.5 - q.width / 2, h * 0.26 - q.height / 2));

      case _Art.notes:
        // Stacked pages with a highlighted passage.
        for (var i = 2; i >= 0; i--) {
          final r = RRect.fromRectAndRadius(
            Rect.fromLTWH(
                w * 0.26 + i * 10, h * 0.18 + i * 12, w * 0.42, h * 0.58),
            const Radius.circular(8),
          );
          canvas.drawRRect(
              r,
              i == 0 ? soft : Paint()
                ..color = Colors.white);
          canvas.drawRRect(r, stroke);
        }
        for (var i = 0; i < 4; i++) {
          final y = h * 0.30 + i * h * 0.10;
          canvas.drawLine(
            Offset(w * 0.32, y),
            Offset(w * 0.32 + w * (i == 1 ? 0.20 : 0.28), y),
            Paint()
              ..color = i == 1 ? Bold.brand : Bold.line
              ..strokeWidth = i == 1 ? 5 : 3
              ..strokeCap = StrokeCap.round,
          );
        }

      case _Art.graph:
        // Mastery bars, one visibly short, with an arrow to its prerequisite.
        const heights = [0.55, 0.34, 0.72, 0.20, 0.62];
        for (var i = 0; i < heights.length; i++) {
          final bh = h * 0.62 * heights[i];
          final x = w * 0.22 + i * (w * 0.13);
          final weak = heights[i] < 0.35;
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(x, h * 0.78 - bh, w * 0.075, bh),
              const Radius.circular(5),
            ),
            Paint()..color = weak ? Bold.danger : Bold.brand,
          );
        }
        canvas.drawLine(
          Offset(w * 0.30, h * 0.20),
          Offset(w * 0.60, h * 0.20),
          stroke,
        );
        canvas.drawLine(
          Offset(w * 0.60, h * 0.20),
          Offset(w * 0.60, h * 0.44),
          stroke,
        );
        canvas.drawPath(
          Path()
            ..moveTo(w * 0.60, h * 0.50)
            ..lineTo(w * 0.575, h * 0.42)
            ..lineTo(w * 0.625, h * 0.42)
            ..close(),
          Paint()..color = Bold.brand,
        );
    }
  }

  @override
  bool shouldRepaint(_SlidePainter old) => old.art != art;
}
