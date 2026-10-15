import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/repository.dart';
import '../../design/bold.dart';
import 'study_models.dart';

enum TileType { term, definition }

class MatchTile {
  MatchTile({
    required this.id,
    required this.cardId,
    required this.text,
    required this.type,
    this.isMatched = false,
    this.isSelected = false,
    this.isError = false,
  });

  final String id;
  final String cardId;
  final String text;
  final TileType type;
  bool isMatched;
  bool isSelected;
  bool isError;
}

/// Match Game: timed speed-matching of terms and definitions.
class MatchGameScreen extends StatefulWidget {
  const MatchGameScreen({
    super.key,
    required this.title,
    required this.cards,
    this.subjectId,
  });

  final String title;
  final List<StudyCard> cards;
  final String? subjectId;

  @override
  State<MatchGameScreen> createState() => _MatchGameScreenState();
}

class _MatchGameScreenState extends State<MatchGameScreen> {
  static const _repo = Repository();
  late List<MatchTile> _tiles;
  MatchTile? _firstSelected;
  bool _isProcessing = false;

  Timer? _stopwatchTimer;
  int _milliseconds = 0;
  bool _isFinished = false;

  static int? _bestTimeMs;

  @override
  void initState() {
    super.initState();
    _startNewGame();
  }

  @override
  void dispose() {
    _stopwatchTimer?.cancel();
    super.dispose();
  }

  void _startNewGame() {
    _stopwatchTimer?.cancel();
    _milliseconds = 0;
    _isFinished = false;
    _firstSelected = null;
    _isProcessing = false;

    final pool = List.of(widget.cards)..shuffle();
    final gameCards = pool.take(6).toList();

    final tiles = <MatchTile>[];
    for (final c in gameCards) {
      tiles.add(MatchTile(
        id: '${c.id}-term',
        cardId: c.id,
        text: c.term,
        type: TileType.term,
      ));
      tiles.add(MatchTile(
        id: '${c.id}-def',
        cardId: c.id,
        text: c.definition,
        type: TileType.definition,
      ));
    }
    tiles.shuffle();

    setState(() => _tiles = tiles);

    _stopwatchTimer = Timer.periodic(const Duration(milliseconds: 100), (t) {
      if (!mounted) return;
      setState(() => _milliseconds += 100);
    });
  }

  void _tapTile(MatchTile tile) {
    if (_isFinished || _isProcessing || tile.isMatched || tile.isSelected) {
      return;
    }

    HapticFeedback.selectionClick();

    setState(() {
      tile.isSelected = true;
    });

    if (_firstSelected == null) {
      _firstSelected = tile;
    } else {
      _isProcessing = true;
      final first = _firstSelected!;
      final second = tile;

      if (first.cardId == second.cardId && first.type != second.type) {
        // MATCH!
        HapticFeedback.lightImpact();
        Future.delayed(const Duration(milliseconds: 250), () {
          if (!mounted) return;
          setState(() {
            first.isMatched = true;
            second.isMatched = true;
            first.isSelected = false;
            second.isSelected = false;
            _firstSelected = null;
            _isProcessing = false;

            if (_tiles.every((t) => t.isMatched)) {
              _onGameWon();
            }
          });
        });
      } else {
        // MISMATCH!
        HapticFeedback.heavyImpact();
        first.isError = true;
        second.isError = true;
        _milliseconds += 1000; // 1-second penalty

        Future.delayed(const Duration(milliseconds: 600), () {
          if (!mounted) return;
          setState(() {
            first.isSelected = false;
            second.isSelected = false;
            first.isError = false;
            second.isError = false;
            _firstSelected = null;
            _isProcessing = false;
          });
        });
      }
    }
  }

  Future<void> _onGameWon() async {
    _stopwatchTimer?.cancel();
    _isFinished = true;

    if (widget.subjectId != null) {
      final scores = <String, int>{};
      for (final t in _tiles) {
        if (t.cardId.length > 5) scores[t.cardId] = 100;
      }
      if (scores.isNotEmpty) {
        try {
          await _repo.submitStudyResults(widget.subjectId!, scores);
        } catch (error) {
          if (!mounted) return;
          final retry = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Round not saved'),
              content: Text(
                'ViaX could not save this result. Check your connection and retry.\n\n$error',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Exit'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
          if (!mounted) return;
          if (retry == true) {
            await _onGameWon();
          } else {
            Navigator.of(context).pop();
          }
          return;
        }
      }
    }

    if (!mounted) return;

    if (_bestTimeMs == null || _milliseconds < _bestTimeMs!) {
      _bestTimeMs = _milliseconds;
    }

    final seconds = (_milliseconds / 1000).toStringAsFixed(1);
    final bestSeconds = (_bestTimeMs! / 1000).toStringAsFixed(1);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Bold.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Cleared the Board! ⚡',
            textAlign: TextAlign.center,
            style: T.heading.copyWith(color: Bold.ink, fontSize: 20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Time: ${seconds}s',
                style: TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.w800,
                  color: Bold.brand,
                )),
            const SizedBox(height: 6),
            Text('Personal Best: ${bestSeconds}s',
                style: T.small.copyWith(color: Bold.slate)),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          OutlinedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _startNewGame();
            },
            child: const Text('Play Again'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  String get _formattedTime {
    final seconds = _milliseconds ~/ 1000;
    final tenths = (_milliseconds % 1000) ~/ 100;
    return '$seconds.${tenths}s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Bold.canvas,
        surfaceTintColor: Colors.transparent,
        title: Text('Match: ${widget.title}',
            style: T.heading.copyWith(color: Bold.ink)),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Bold.wash(Bold.brand),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                const Icon(Icons.timer_outlined, size: 16, color: Bold.brand),
                const SizedBox(width: 6),
                Text(
                  _formattedTime,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Bold.brand,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(
                'Tap matching pairs to make them disappear!',
                style: T.small.copyWith(color: Bold.slate),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: GridView.builder(
                  itemCount: _tiles.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 1.35,
                  ),
                  itemBuilder: (context, i) {
                    final tile = _tiles[i];
                    return _MatchTileWidget(
                      tile: tile,
                      onTap: () => _tapTile(tile),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MatchTileWidget extends StatelessWidget {
  const _MatchTileWidget({
    required this.tile,
    required this.onTap,
  });

  final MatchTile tile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (tile.isMatched) {
      return const SizedBox.shrink(); // Disappears when matched!
    }

    Color bg = Bold.card;
    Color border = Bold.line;
    Color textColor = Bold.ink;

    if (tile.isError) {
      bg = Bold.wash(Bold.danger);
      border = Bold.danger;
      textColor = Bold.danger;
    } else if (tile.isSelected) {
      bg = Bold.wash(Bold.brand);
      border = Bold.brand;
      textColor = Bold.brand;
    }

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(16),
      elevation: tile.isSelected ? 2 : 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border:
                Border.all(color: border, width: tile.isSelected ? 2.0 : 1.0),
          ),
          child: Center(
            child: Text(
              tile.text,
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: T.small.copyWith(
                color: textColor,
                fontSize: tile.type == TileType.term ? 13.5 : 12,
                fontWeight: tile.type == TileType.term
                    ? FontWeight.w700
                    : FontWeight.w500,
                height: 1.3,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
