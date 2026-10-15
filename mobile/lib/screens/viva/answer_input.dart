import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../design/bold.dart';

/// The Answer Input Bar (UI/UX §2.4).
///
/// A text field with an inline mic that becomes a live waveform while
/// recording. Voice is the point of a viva — it is a spoken examination — but
/// typing is never taken away: transcription accuracy varies by accent and by
/// device, and the PRD's own risk register (§7) requires a graceful fallback
/// rather than a student stuck against a microphone that will not hear them.
///
/// What is transcribed lands in the same field the student can edit, so a
/// misheard word is corrected rather than argued with.
class AnswerInput extends StatefulWidget {
  const AnswerInput({
    super.key,
    required this.controller,
    required this.onSubmit,
    required this.submitting,
  });

  final TextEditingController controller;
  final VoidCallback onSubmit;
  final bool submitting;

  @override
  State<AnswerInput> createState() => _AnswerInputState();
}

class _AnswerInputState extends State<AnswerInput>
    with SingleTickerProviderStateMixin {
  final _speech = SpeechToText();
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  bool _available = false;
  bool _initializing = false;
  bool _initialized = false;
  bool _listening = false;
  String _unavailableReason = '';

  /// What was in the field before this dictation began, so a second attempt
  /// appends rather than silently wiping a typed answer.
  String _baseText = '';
  double _level = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_answerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_answerChanged);
    _pulse.dispose();
    _speech.cancel();
    super.dispose();
  }

  void _answerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant AnswerInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_answerChanged);
      widget.controller.addListener(_answerChanged);
    }
    if (widget.submitting && !oldWidget.submitting) {
      _listening = false;
      _pulse.stop();
      _speech.cancel();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPulse();
  }

  void _syncPulse() {
    if (_listening && !MediaQuery.disableAnimationsOf(context)) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
    }
  }

  Future<void> _submit() async {
    if (widget.submitting || widget.controller.text.trim().isEmpty) return;
    final wasListening = _listening;
    setState(() => _listening = false);
    _pulse.stop();
    if (wasListening) await _speech.cancel();
    if (mounted && !widget.submitting) widget.onSubmit();
  }

  Future<void> _initSpeech() async {
    setState(() => _initializing = true);
    try {
      final ok = await _speech.initialize(
        onStatus: (status) {
          if (!mounted) return;
          if (status == 'done' || status == 'notListening') {
            setState(() => _listening = false);
            _syncPulse();
          }
        },
        onError: (e) {
          if (!mounted) return;
          setState(() {
            _listening = false;
            // Named, not swallowed: "no speech detected" and "permission
            // denied" need different responses from the student.
            _unavailableReason = e.errorMsg;
          });
          _syncPulse();
        },
      );
      if (mounted) {
        setState(() {
          _available = ok;
          _initialized = true;
          if (!ok) _unavailableReason = "permission or speech unavailable";
        });
      }
    } catch (_) {
      // Speech is genuinely unavailable on some browsers and locked-down
      // devices. That is a missing feature, not an error worth interrupting
      // an examination for.
      if (mounted) {
        setState(() {
          _available = false;
          _initialized = true;
          _unavailableReason = "unavailable";
        });
      }
    } finally {
      if (mounted) setState(() => _initializing = false);
    }
  }

  Future<void> _toggle() async {
    if (widget.submitting || _initializing) return;
    HapticFeedback.lightImpact();
    if (_listening) {
      await _speech.stop();
      if (mounted) {
        setState(() => _listening = false);
        _syncPulse();
      }
      return;
    }
    if (!_available) await _initSpeech();
    if (!mounted || !_available || widget.submitting) return;

    _baseText = widget.controller.text.trimRight();
    setState(() {
      _listening = true;
      _unavailableReason = '';
    });

    _syncPulse();
    try {
      await _speech.listen(
        onResult: (result) {
          if (!mounted || !_listening || widget.submitting) return;
          final spoken = result.recognizedWords;
          final joined = _baseText.isEmpty ? spoken : '$_baseText $spoken';
          widget.controller.value = TextEditingValue(
            text: joined,
            selection: TextSelection.collapsed(offset: joined.length),
          );
        },
        onSoundLevelChange: (level) {
          if (mounted) setState(() => _level = level);
        },
        listenOptions: SpeechListenOptions(
          // Partial results as they arrive: a viva answer is long, and watching
          // nothing happen for thirty seconds reads as a broken microphone.
          partialResults: true,
          cancelOnError: false,
          listenFor: const Duration(minutes: 3),
          pauseFor: const Duration(seconds: 6),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _listening = false;
          _unavailableReason = 'unavailable';
        });
        _syncPulse();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: widget.controller,
              readOnly: widget.submitting || _listening,
              maxLines: 8,
              minLines: 5,
              textCapitalization: TextCapitalization.sentences,
              style: T.body.copyWith(color: Bold.ink),
              decoration: InputDecoration(
                labelText: 'Your answer',
                alignLabelWithHint: true,
                hintText:
                    _listening ? 'Listening…' : 'Answer as you would out loud…',
                hintStyle: T.body.copyWith(color: Bold.slate),
                filled: true,
                fillColor: Bold.card,
                contentPadding: const EdgeInsets.all(16),
                border: _border(Bold.line),
                enabledBorder: _border(Bold.line),
                focusedBorder:
                    _border(Theme.of(context).colorScheme.primary, width: 2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  if (_listening)
                    Expanded(child: _Waveform(level: _level, pulse: _pulse))
                  else
                    Expanded(
                      child: Text(
                        _initializing
                            ? 'Setting up voice input…'
                            : !_initialized || _available
                                ? 'Type or tap the mic to answer aloud'
                                : 'Voice unavailable on this device',
                        style: T.small.copyWith(color: Bold.slate),
                      ),
                    ),
                  const SizedBox(width: 12),
                  _MicButton(
                    listening: _listening,
                    enabled: !_initializing && !widget.submitting,
                    onTap: _toggle,
                  ),
                ],
              ),
            ),
          ],
        ),
        if (_unavailableReason.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            _friendly(_unavailableReason),
            style: T.small.copyWith(
                color: Theme.of(context).colorScheme.error, height: 1.4),
          ),
        ],
        const SizedBox(height: 14),
        FilledButton(
          onPressed: widget.submitting || widget.controller.text.trim().isEmpty
              ? null
              : _submit,
          child: widget.submitting
              ? const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 12),
                    Flexible(child: Text('Checking against your notes…')),
                  ],
                )
              : const Text('Submit answer'),
        ),
      ],
    );
  }

  OutlineInputBorder _border(Color colour, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: colour, width: width),
      );

  /// Speech errors arrive as engine codes. A student needs to know what to do.
  static String _friendly(String code) {
    final c = code.toLowerCase();
    if (c.contains('permission') || c.contains('denied')) {
      return 'Microphone access is blocked. Allow it in your device or browser settings, '
          'or type your answer instead.';
    }
    if (c.contains('no match') || c.contains('speech')) {
      return 'Nothing was heard. Try again, or type your answer.';
    }
    if (c.contains('network')) {
      return 'Speech recognition needs a connection. Typing still works.';
    }
    return 'Voice input had a problem. Typing still works.';
  }
}

class _MicButton extends StatelessWidget {
  const _MicButton({
    required this.listening,
    required this.enabled,
    required this.onTap,
  });

  final bool listening;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: listening ? 'Stop recording' : 'Answer by voice',
      child: ExcludeSemantics(
        child: Material(
          color: listening
              ? Bold.danger
              : enabled
                  ? Bold.brand
                  : Bold.line,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled ? onTap : null,
            child: SizedBox(
              width: 48,
              height: 48,
              child: Icon(
                listening ? Icons.stop_rounded : Icons.mic_rounded,
                color: enabled || listening ? Colors.white : Bold.slate,
                size: 21,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The live waveform the guide asks the mic to morph into while recording.
///
/// Driven by the real sound level rather than a canned animation: a bar that
/// moves when the room is silent tells the student the microphone is working
/// when it is not.
class _Waveform extends StatelessWidget {
  const _Waveform({required this.level, required this.pulse});

  final double level;
  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 26,
      child: AnimatedBuilder(
        animation: pulse,
        builder: (context, _) => CustomPaint(
          painter: _WavePainter(level: level, phase: pulse.value),
          size: const Size(double.infinity, 26),
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  const _WavePainter({required this.level, required this.phase});

  /// Engine sound level, roughly -2 (silent) to 10 (loud).
  final double level;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    const bars = 22;
    const gap = 3.0;
    if (size.width <= gap * (bars - 1)) return;
    final width = (size.width - gap * (bars - 1)) / bars;
    final normalised = ((level + 2) / 12).clamp(0.0, 1.0);

    final paint = Paint()..color = Bold.danger;
    for (var i = 0; i < bars; i++) {
      // A standing pattern modulated by real amplitude: silence collapses it
      // rather than leaving a decorative ripple.
      final offset = (i / bars) + phase;
      final wobble = 0.35 + 0.65 * ((offset * 3) % 1.0);
      final h =
          (4 + normalised * wobble * (size.height - 6)).clamp(3.0, size.height);
      final x = i * (width + gap);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, (size.height - h) / 2, width, h),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.level != level || old.phase != phase;
}
