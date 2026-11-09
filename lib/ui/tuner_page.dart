import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../audio/mic_listener.dart';
import '../models/instrument.dart';
import '../music/chords.dart';
import '../music/pitch.dart';
import 'widgets/cents_meter.dart';

/// A tuner: the note (or chord) being played, how many cents off, and how
/// steady it is.
class TunerTab extends StatefulWidget {
  const TunerTab({super.key});

  @override
  State<TunerTab> createState() => _TunerTabState();
}

class _TunerTabState extends State<TunerTab> {
  final _mic = MicListener(analyzeChords: true);
  StreamSubscription<MicReading>? _readings;
  String? _error;

  /// Recent pitches, for a steadier display.
  final _recent = <double>[];
  double? _midi;
  DateTime _lastPitch = DateTime(0);

  /// Smoothed chroma and the chord it suggests.
  List<double> _chroma = List.filled(12, 0);
  (Chord, double)? _chord;

  /// (seconds, cents from the nearest note) of the last few seconds.
  final _history = <(double, double)>[];
  final _clock = Stopwatch()..start();

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final deviceId = AppScope.read(context).settings.deviceId;
      await _mic.start(deviceId: deviceId);
      _readings = _mic.readings.listen(_onReading);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Não foi possível abrir o microfone: $e');
      }
    }
  }

  @override
  void dispose() {
    _readings?.cancel();
    _mic.dispose();
    super.dispose();
  }

  void _onReading(MicReading r) {
    if (!mounted) return;
    final now = _clock.elapsedMicroseconds / 1e6;
    final midi = r.midi;
    if (midi != null) {
      // A jump to another note restarts the smoothing.
      if (_recent.isNotEmpty && (midi - _recent.last).abs() > 0.5) {
        _recent.clear();
      }
      _recent.add(midi);
      if (_recent.length > 5) _recent.removeAt(0);
      final sorted = [..._recent]..sort();
      _midi = sorted[sorted.length ~/ 2];
      _lastPitch = DateTime.now();
      _history.add((now, centsFromNearest(_midi!)));
    }
    _history.removeWhere((p) => p.$1 < now - 4);

    final chroma = r.chroma;
    if (chroma != null) {
      final loud =
          chroma.any((c) => c > 0) && (midi != null || r.confidence > 0.3);
      _chroma = [
        for (var i = 0; i < 12; i++)
          _chroma[i] * 0.6 + (loud ? chroma[i] : 0) * 0.4,
      ];
      final best = loud ? bestChord(_chroma) : null;
      _chord = best != null && best.$2 >= 0.6 ? best : null;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final naming = state.settings.naming;
    final transposition = state.instrument.transposition;
    if (_error != null) {
      return Center(
        child: Text(_error!, style: TextStyle(color: colors.error)),
      );
    }

    final active =
        DateTime.now().difference(_lastPitch) <
        const Duration(milliseconds: 600);
    final midi = _midi;
    final cents = midi == null || !active ? null : centsFromNearest(midi);
    final note = midi?.round();
    final color = active ? tuningColor(cents, colors) : colors.outline;

    // Steadiness: spread of the last second of readings.
    final now = _clock.elapsedMicroseconds / 1e6;
    final lastSecond = [
      for (final p in _history)
        if (p.$1 > now - 1) p.$2,
    ];
    double? spread;
    if (lastSecond.length >= 8 && active) {
      final mean = lastSecond.reduce((a, b) => a + b) / lastSecond.length;
      spread = math.sqrt(
        lastSecond.map((c) => (c - mean) * (c - mean)).reduce((a, b) => a + b) /
            lastSecond.length,
      );
    }

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Text('Afinador', style: theme.textTheme.headlineSmall),
            const Spacer(),
            DropdownMenu<Instrument>(
              label: const Text('Instrumento'),
              width: 280,
              initialSelection: state.instrument,
              dropdownMenuEntries: [
                for (final i in instruments)
                  DropdownMenuEntry(value: i, label: '${i.icon}  ${i.name}'),
              ],
              onSelected: (i) {
                if (i != null) state.setInstrument(i);
              },
            ),
            const SizedBox(width: 12),
            SegmentedButton<NoteNaming>(
              segments: [
                for (final n in NoteNaming.values)
                  ButtonSegment(value: n, label: Text(n.label)),
              ],
              selected: {naming},
              onSelectionChanged: (s) {
                state.settings.naming = s.single;
                state.save();
              },
            ),
          ],
        ),
        const SizedBox(height: 24),
        Center(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: note == null
                      ? '—'
                      : pitchClassName(note + transposition, naming),
                  style: theme.textTheme.displayLarge?.copyWith(
                    fontSize: 120,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                if (note != null)
                  TextSpan(
                    text: '${(note + transposition) ~/ 12 - 1}',
                    style: theme.textTheme.displaySmall?.copyWith(color: color),
                  ),
              ],
            ),
          ),
        ),
        Center(
          child: Text(
            midi == null
                ? 'Toque ou cante uma nota'
                : '${midiToFrequency(midi).toStringAsFixed(1)} Hz'
                      '${cents == null ? '' : ' · ${cents > 0 ? '+' : ''}${cents.round()} cents'}'
                      '${transposition != 0 ? ' · som real ${noteName(note!, naming)}' : ''}',
            style: theme.textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            cents == null
                ? ' '
                : cents.abs() <= 5
                ? 'Afinado!'
                : cents > 0
                ? 'Alto — abaixe'
                : 'Baixo — suba',
            style: theme.textTheme.titleLarge?.copyWith(color: color),
          ),
        ),
        const SizedBox(height: 16),
        CentsMeter(cents: cents, height: 72),
        const SizedBox(height: 24),
        Row(
          children: [
            Text('Estabilidade', style: theme.textTheme.titleMedium),
            const SizedBox(width: 12),
            Text(
              spread == null
                  ? '—'
                  : spread <= 4
                  ? 'Muito firme (±${spread.round()} cents)'
                  : spread <= 10
                  ? 'Firme (±${spread.round()} cents)'
                  : 'Oscilando (±${spread.round()} cents)',
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 120,
          child: CustomPaint(
            size: Size.infinite,
            painter: _HistoryPainter(_history, now, colors),
          ),
        ),
        const SizedBox(height: 32),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('Acorde', style: theme.textTheme.titleMedium),
            const SizedBox(width: 16),
            Text(
              _chord == null
                  ? '—'
                  : Chord(
                      (_chord!.$1.root + transposition) % 12,
                      _chord!.$1.quality,
                    ).name(naming),
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 140,
          child: CustomPaint(
            size: Size.infinite,
            painter: _ChromaPainter(
              _chroma,
              _chord?.$1.pitchClasses ?? const {},
              naming,
              transposition,
              colors,
            ),
          ),
        ),
        Text(
          'Barras: quanto de cada nota está soando. As do acorde reconhecido ficam em destaque.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// Cents from the nearest note over the last seconds, with the in-tune band.
class _HistoryPainter extends CustomPainter {
  _HistoryPainter(this.history, this.now, this.colors);

  final List<(double, double)> history;
  final double now;
  final ColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) {
    double y(double cents) => size.height / 2 - cents / 50 * size.height / 2;
    double x(double t) => size.width - (now - t) / 4 * size.width;
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = colors.surfaceContainerLow,
    );
    canvas.drawRect(
      Rect.fromLTRB(0, y(12), size.width, y(-12)),
      Paint()..color = Colors.greenAccent.withValues(alpha: 0.08),
    );
    canvas.drawLine(
      Offset(0, y(0)),
      Offset(size.width, y(0)),
      Paint()..color = colors.outline,
    );
    final line = Paint()
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (var i = 1; i < history.length; i++) {
      final a = history[i - 1], b = history[i];
      if (b.$1 - a.$1 > 0.2 || (b.$2 - a.$2).abs() > 30) continue;
      line.color = tuningColor(b.$2, colors);
      canvas.drawLine(Offset(x(a.$1), y(a.$2)), Offset(x(b.$1), y(b.$2)), line);
    }
  }

  @override
  bool shouldRepaint(_HistoryPainter old) => true;
}

/// One bar per pitch class.
class _ChromaPainter extends CustomPainter {
  _ChromaPainter(
    this.chroma,
    this.chord,
    this.naming,
    this.transposition,
    this.colors,
  );

  final List<double> chroma;
  final Set<int> chord;
  final NoteNaming naming;
  final int transposition;
  final ColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width / 12;
    final barArea = size.height - 22;
    final top = chroma.fold(0.0, math.max);
    for (var pc = 0; pc < 12; pc++) {
      final h = top == 0 ? 0.0 : chroma[pc] / top * barArea;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(pc * w + 6, barArea - h, w - 12, h),
          const Radius.circular(4),
        ),
        Paint()
          ..color = chord.contains(pc) ? colors.primary : colors.outlineVariant,
      );
      final text = TextPainter(
        text: TextSpan(
          text: pitchClassName(pc + transposition, naming),
          style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(canvas, Offset(pc * w + (w - text.width) / 2, barArea + 4));
    }
  }

  @override
  bool shouldRepaint(_ChromaPainter old) => true;
}
