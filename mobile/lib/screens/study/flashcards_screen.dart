import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/repository.dart';
import '../../design/bold.dart';
import 'study_models.dart';

/// Flashcards with 3D flip animation, swipe gestures, and star filtering.
class FlashcardsScreen extends StatefulWidget {
  const FlashcardsScreen({
    super.key,
    required this.title,
    required this.cards,
    this.subjectId,
  });

  final String title;
  final List<StudyCard> cards;
  final String? subjectId;

  @override
  State<FlashcardsScreen> createState() => _FlashcardsScreenState();
}

class _FlashcardsScreenState extends State<FlashcardsScreen>
    with SingleTickerProviderStateMixin {
  static const _repo = Repository();
  late List<StudyCard> _deck;
  int _currentIndex = 0;
  bool _isFlipped = false;
  late AnimationController _flipController;
  late Animation<double> _flipAnimation;

  final Set<String> _known = {};
  final Set<String> _learning = {};
  final Set<String> _starred = {};

  bool _onlyStarred = false;

  @override
  void initState() {
    super.initState();
    _deck = List.of(widget.cards);
    _starred.addAll(
        widget.cards.where((card) => card.starred).map((card) => card.id));
    _flipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _flipAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _flipController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _flipController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _flipController.duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 300);
  }

  List<StudyCard> get _activeDeck => _onlyStarred
      ? _deck.where((c) => _starred.contains(c.id)).toList()
      : _deck;

  void _flip() {
    HapticFeedback.selectionClick();
    if (_isFlipped) {
      _flipController.reverse();
    } else {
      _flipController.forward();
    }
    setState(() => _isFlipped = !_isFlipped);
  }

  void _markKnown() {
    if (_activeDeck.isEmpty) return;
    HapticFeedback.lightImpact();
    final card = _activeDeck[_currentIndex];
    setState(() {
      _known.add(card.id);
      _learning.remove(card.id);
      _nextCard();
    });
  }

  void _markLearning() {
    if (_activeDeck.isEmpty) return;
    HapticFeedback.mediumImpact();
    final card = _activeDeck[_currentIndex];
    setState(() {
      _learning.add(card.id);
      _known.remove(card.id);
      _nextCard();
    });
  }

  void _nextCard() {
    if (_currentIndex < _activeDeck.length - 1) {
      if (_isFlipped) {
        _flipController.reverse();
        _isFlipped = false;
      }
      setState(() => _currentIndex++);
    } else {
      _showCompletionDialog();
    }
  }

  void _prevCard() {
    if (_currentIndex > 0) {
      if (_isFlipped) {
        _flipController.reverse();
        _isFlipped = false;
      }
      setState(() => _currentIndex--);
    }
  }

  void _shuffle() {
    HapticFeedback.selectionClick();
    setState(() {
      _deck.shuffle();
      _currentIndex = 0;
      if (_isFlipped) {
        _flipController.reverse();
        _isFlipped = false;
      }
    });
  }

  Future<void> _toggleStar(String id) async {
    HapticFeedback.selectionClick();
    final next = !_starred.contains(id);
    setState(() {
      if (!next) {
        _starred.remove(id);
      } else {
        _starred.add(id);
      }
    });
    try {
      await _repo.setConceptStarred(id, next);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (next) {
          _starred.remove(id);
        } else {
          _starred.add(id);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update the study library: $e')),
      );
    }
  }

  void _showCompletionDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Bold.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Round Complete! 🎉',
            style: T.heading.copyWith(color: Bold.ink)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You reviewed ${_activeDeck.length} cards.',
              style: T.body.copyWith(color: Bold.slate),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Bold.wash(Bold.good),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_outline_rounded,
                          size: 16, color: Bold.good),
                      const SizedBox(width: 4),
                      Text('Known: ${_known.length}',
                          style: T.small.copyWith(color: Bold.good)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Bold.wash(Bold.warn),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.refresh_rounded,
                          size: 16, color: Bold.warn),
                      const SizedBox(width: 4),
                      Text('Still Learning: ${_learning.length}',
                          style: T.small.copyWith(color: Bold.warn)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              setState(() {
                _currentIndex = 0;
                _known.clear();
                _learning.clear();
                if (_isFlipped) {
                  _flipController.reverse();
                  _isFlipped = false;
                }
              });
            },
            child: const Text('Restart'),
          ),
          FilledButton(
            onPressed: () async {
              if (widget.subjectId != null) {
                final scores = <String, int>{};
                for (final id in _known) {
                  scores[id] = 100;
                }
                for (final id in _learning) {
                  scores[id] = 50;
                }
                if (scores.isNotEmpty) {
                  try {
                    await _repo.submitStudyResults(widget.subjectId!, scores);
                  } catch (error) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text('Could not save this round: $error')),
                    );
                    return;
                  }
                }
              }
              if (!mounted || !ctx.mounted) return;
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final active = _activeDeck;
    final hasCards = active.isNotEmpty;
    final currentCard = hasCards ? active[_currentIndex] : null;
    final isStarred = currentCard != null && _starred.contains(currentCard.id);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Bold.canvas,
        surfaceTintColor: Colors.transparent,
        title: Text(widget.title, style: T.heading.copyWith(color: Bold.ink)),
        actions: [
          IconButton(
            icon: Icon(
              _onlyStarred ? Icons.star_rounded : Icons.star_outline_rounded,
              color: _onlyStarred ? Bold.warnLift : Bold.slate,
            ),
            tooltip: _onlyStarred ? 'Show all cards' : 'Show starred only',
            onPressed: () {
              if (_starred.isEmpty && !_onlyStarred) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content:
                        Text('Star some cards first to filter by starred!'),
                  ),
                );
                return;
              }
              setState(() {
                _onlyStarred = !_onlyStarred;
                _currentIndex = 0;
                if (_isFlipped) {
                  _flipController.reverse();
                  _isFlipped = false;
                }
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.shuffle_rounded),
            tooltip: 'Shuffle deck',
            onPressed: hasCards ? _shuffle : null,
          ),
        ],
      ),
      body: SafeArea(
        child: !hasCards
            ? Center(
                child: Text('No cards available in this set.',
                    style: T.body.copyWith(color: Bold.slate)),
              )
            : Column(
                children: [
                  // Progress header
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.arrow_back_ios_rounded,
                                      size: 16),
                                  tooltip: 'Previous card',
                                  onPressed:
                                      _currentIndex > 0 ? _prevCard : null,
                                ),
                                Text(
                                  '${_currentIndex + 1} / ${active.length}',
                                  style: T.heading.copyWith(color: Bold.ink),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Bold.wash(Bold.good),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text('Known: ${_known.length}',
                                      style:
                                          T.small.copyWith(color: Bold.good)),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Bold.wash(Bold.warn),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text('Learning: ${_learning.length}',
                                      style:
                                          T.small.copyWith(color: Bold.warn)),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: (active.isEmpty)
                                ? 0
                                : (_currentIndex + 1) / active.length,
                            backgroundColor: Bold.line,
                            color: Bold.brand,
                            minHeight: 6,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // The Flashcard with 3D Flip
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                      child: GestureDetector(
                        onTap: _flip,
                        onHorizontalDragEnd: (details) {
                          if (details.primaryVelocity != null) {
                            if (details.primaryVelocity! > 150) {
                              _markKnown(); // Swipe Right = Know it
                            } else if (details.primaryVelocity! < -150) {
                              _markLearning(); // Swipe Left = Still Learning
                            }
                          }
                        },
                        child: AnimatedBuilder(
                          animation: _flipAnimation,
                          builder: (context, child) {
                            final angle = _flipAnimation.value * math.pi;
                            final isUnder = angle > (math.pi / 2);

                            return Transform(
                              transform: Matrix4.identity()
                                ..setEntry(3, 2, 0.001)
                                ..rotateY(angle),
                              alignment: Alignment.center,
                              child: Container(
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: Bold.card,
                                  borderRadius: BorderRadius.circular(24),
                                  border:
                                      Border.all(color: Bold.line, width: 1.5),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.04),
                                      blurRadius: 16,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                padding: const EdgeInsets.all(28),
                                child: isUnder
                                    ? Transform(
                                        transform: Matrix4.identity()
                                          ..rotateY(math.pi),
                                        alignment: Alignment.center,
                                        child: _CardSide(
                                          tag: 'DEFINITION',
                                          tagColor: Bold.brand,
                                          content: currentCard!.definition,
                                          isStarred: isStarred,
                                          onStar: () =>
                                              _toggleStar(currentCard.id),
                                          hint: 'Tap to flip back to term',
                                        ),
                                      )
                                    : _CardSide(
                                        tag: 'TERM',
                                        tagColor: Bold.slate,
                                        content: currentCard!.term,
                                        isStarred: isStarred,
                                        onStar: () =>
                                            _toggleStar(currentCard.id),
                                        hint: 'Tap card to flip',
                                      ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),

                  // Bottom Action Controls (Still Learning / Know buttons)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 10, 24, 28),
                    child: Row(
                      children: [
                        // Still learning button (Left)
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Bold.warn,
                              side: BorderSide(
                                  color: Bold.warn.withValues(alpha: 0.5)),
                              minimumSize: const Size.fromHeight(54),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                            ),
                            onPressed: _markLearning,
                            icon: const Icon(Icons.close_rounded, size: 20),
                            label: const Text('Still Learning'),
                          ),
                        ),
                        const SizedBox(width: 14),
                        // Know it button (Right)
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: Bold.good,
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(54),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                            ),
                            onPressed: _markKnown,
                            icon: const Icon(Icons.check_rounded, size: 20),
                            label: const Text('Know It'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _CardSide extends StatelessWidget {
  const _CardSide({
    required this.tag,
    required this.tagColor,
    required this.content,
    required this.isStarred,
    required this.onStar,
    required this.hint,
  });

  final String tag;
  final Color tagColor;
  final String content;
  final bool isStarred;
  final VoidCallback onStar;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Bold.wash(tagColor),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                tag,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: tagColor,
                ),
              ),
            ),
            IconButton(
              icon: Icon(
                isStarred ? Icons.star_rounded : Icons.star_outline_rounded,
                color: isStarred ? Bold.warnLift : Bold.slate,
              ),
              onPressed: onStar,
            ),
          ],
        ),
        const Spacer(),
        Center(
          child: Text(
            content,
            textAlign: TextAlign.center,
            style: T.heading.copyWith(
              fontSize: 22,
              height: 1.4,
              color: Bold.ink,
            ),
          ),
        ),
        const Spacer(),
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.touch_app_outlined, size: 14, color: Bold.slate),
              const SizedBox(width: 6),
              Text(
                hint,
                style: T.small.copyWith(color: Bold.slate),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
