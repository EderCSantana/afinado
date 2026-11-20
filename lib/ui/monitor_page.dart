import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../audio/mic_listener.dart';
import '../music/chords.dart';
import '../music/pitch.dart';
import '../music/pitch_track.dart';
import 'widgets/cents_meter.dart';

/// A pitch monitor: what you sing or play, drawn over time on a piano-roll
/// (one row per note), colored by how in tune it is, with the chords heard
/// in a band above. Pause to look back (drag sideways).
class MonitorTab extends StatefulWidget {
  const MonitorTab({super.key});

  @override
  State<MonitorTab> createState() => _MonitorTabState();
}

class _MonitorTabState extends State<MonitorTab> {
  final _mic = MicListener(analyzeChords: true);
  final _track = PitchTrack();
  final _chords = ChordFollower();
  final _clock = Stopwatch()..start();
  final _focus = FocusNode();
  StreamSubscription<MicReading>? _readings;
  String? _error;

  /// Seconds shown across the chart.
  double _window = 10;
  bool _paused = false;

  /// While paused: the time at the right edge (moved by dragging).
  double _viewEnd = 0;

  /// Note range shown, smoothed so the grid does not jump.
  double _low = 55, _high = 72;

  double? _currentMidi;
  Chord? _currentChord;
  double _lastPitchAt = -1;

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
    _focus.dispose();
    super.dispose();
  }

  double get _now => _clock.elapsedMicroseconds / 1e6;

  void _onReading(MicReading r) {
    if (!mounted || _paused) return;
    final t = _now;
    final midi = r.midi;
    if (midi != null) {
      _track.addPitch(t, midi);
      _currentMidi = _track.points.last.midi;
      _lastPitchAt = t;
    }
    final chroma = r.chroma;
    if (chroma != null) {
      final loud =
          chroma.any((c) => c > 0) && (midi != null || r.confidence > 0.3);
      _currentChord = _chords.update(chroma, loud: loud);
      _track.addChord(t, _currentChord);
    }
    final (low, high) = _track.rangeFor(t - _window, t);
    // Ease towards the new range.
    _low += (low - _low) * 0.15;
    _high += (high - _high) * 0.15;
    setState(() {});
  }

  void _togglePause() => setState(() {
    _paused = !_paused;
    _viewEnd = _now;
    if (!_paused) _clock.start();
  });

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
    final now = _paused ? _viewEnd : _now;
    final active = !_paused && now - _lastPitchAt < 0.4;
    final midi = active ? _currentMidi : null;
    final cents = midi == null ? null : centsFromNearest(midi);
    final note = midi?.round();

    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.space) {
          _togglePause();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Monitor', style: theme.textTheme.headlineSmall),
                SizedBox(
                  width: 190,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: note == null
                              ? '—'
                              : noteLabel(note + transposition, naming),
                          style: theme.textTheme.headlineMedium?.copyWith(
                            color: tuningColor(cents, colors),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextSpan(
                          text: cents == null
                              ? ''
                              : '  ${cents > 0 ? '+' : ''}${cents.round()} c',
                          style: theme.textTheme.titleMedium,
                        ),
                      ],
                    ),
                  ),
                ),
                Chip(
                  avatar: const Icon(Icons.piano, size: 18),
                  label: Text(
                    _currentChord == null || _paused
                        ? 'Acorde: —'
                        : 'Acorde: ${_currentChord!.name(naming)}',
                  ),
                ),
                SegmentedButton<double>(
                  segments: const [
                    ButtonSegment(value: 5, label: Text('5 s')),
                    ButtonSegment(value: 10, label: Text('10 s')),
                    ButtonSegment(value: 20, label: Text('20 s')),
                    ButtonSegment(value: 40, label: Text('40 s')),
                  ],
                  selected: {_window},
                  onSelectionChanged: (s) => setState(() => _window = s.single),
                ),
                FilledButton.tonalIcon(
                  onPressed: _togglePause,
                  icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
                  label: Text(_paused ? 'Continuar (espaço)' : 'Pausar (espaço)'),
                ),
                IconButton(
                  tooltip: 'Limpar',
                  onPressed: () => setState(_track.clear),
                  icon: const Icon(Icons.delete_sweep_outlined),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _paused
                  ? 'Pausado: arraste para os lados para rever os últimos '
                        '${_track.keepSeconds.round()} s.'
                  : 'Cante ou toque: a linha mostra a altura no tempo '
                        '(verde afinado, amarelo quase, laranja desafinado).',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: GestureDetector(
                onHorizontalDragUpdate: !_paused
                    ? null
                    : (d) => setState(() {
                        final box = context.size?.width ?? 800;
                        _viewEnd = (_viewEnd - d.delta.dx / box * _window)
                            .clamp(_window, _now);
                      }),
                child: CustomPaint(
                  size: Size.infinite,
                  painter: MonitorPainter(
                    track: _track,
                    end: now,
                    window: _window,
                    low: _low,
                    high: _high,
                    label: (m) => noteLabel(m + transposition, naming),
                    chordLabel: (c) => c.name(naming),
                    colors: colors,
                    text: theme.textTheme,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Note name with octave, e.g. "Lá4" or "A4".
String noteLabel(int midi, NoteNaming naming) =>
    '${pitchClassName(midi, naming)}${midi ~/ 12 - 1}';

/// Draws the monitor chart: note rows, the pitch line and the chord band.
class MonitorPainter extends CustomPainter {
  MonitorPainter({
    required this.track,
    required this.end,
    required this.window,
    required this.low,
    required this.high,
    required this.label,
    required this.chordLabel,
    required this.colors,
    required this.text,
  });

  final PitchTrack track;
  final double end;
  final double window;
  final double low;
  final double high;
  final String Function(int midi) label;
  final String Function(Chord chord) chordLabel;
  final ColorScheme colors;
  final TextTheme text;

  static const _labelWidth = 52.0;
  static const _chordBand = 30.0;
  static const _black = {1, 3, 6, 8, 10};

  @override
  void paint(Canvas canvas, Size size) {
    final start = end - window;
    final chart = Rect.fromLTRB(
      _labelWidth,
      _chordBand,
      size.width,
      size.height,
    );
    double x(double t) => chart.left + (t - start) / window * chart.width;
    double y(double midi) =>
        chart.bottom - (midi - (low - 0.5)) / (high - low + 1) * chart.height;
    final rowHeight = chart.height / (high - low + 1);

    // Note rows: black keys shaded, C and the other natural notes labeled.
    for (var m = low.floor(); m <= high.ceil(); m++) {
      final top = y(m + 0.5), bottom = y(m - 0.5);
      if (bottom < chart.top || top > chart.bottom) continue;
      final row = Rect.fromLTRB(
        chart.left,
        top.clamp(chart.top, chart.bottom),
        chart.right,
        bottom.clamp(chart.top, chart.bottom),
      );
      final pc = m % 12;
      if (_black.contains(pc)) {
        canvas.drawRect(
          row,
          Paint()..color = colors.surfaceContainerHighest.withValues(alpha: 0.6),
        );
      }
      canvas.drawLine(
        Offset(chart.left, bottom),
        Offset(chart.right, bottom),
        Paint()
          ..color = colors.outlineVariant.withValues(alpha: pc == 0 ? 0.9 : 0.3)
          ..strokeWidth = pc == 0 ? 1.2 : 0.5,
      );
      if (!_black.contains(pc) && rowHeight >= 9) {
        _text(
          canvas,
          label(m),
          Offset(4, (top + bottom) / 2),
          (pc == 0 ? text.labelMedium : text.labelSmall)?.copyWith(
            color: pc == 0 ? colors.onSurface : colors.onSurfaceVariant,
            fontWeight: pc == 0 ? FontWeight.bold : null,
          ),
          centerY: true,
        );
      }
    }

    // Seconds ticks.
    for (var s = start.ceil(); s <= end; s++) {
      final major = s % 5 == 0;
      canvas.drawLine(
        Offset(x(s.toDouble()), chart.top),
        Offset(x(s.toDouble()), chart.bottom),
        Paint()
          ..color = colors.outlineVariant.withValues(alpha: major ? 0.35 : 0.12),
      );
    }

    // Chords.
    for (final span in track.chordsBetween(start, end)) {
      final left = x(span.start).clamp(chart.left, chart.right);
      final right = x(span.end).clamp(chart.left, chart.right);
      final box = Rect.fromLTRB(left, 2, right.clamp(left + 2, chart.right), _chordBand - 4);
      canvas.drawRRect(
        RRect.fromRectAndRadius(box, const Radius.circular(4)),
        Paint()..color = colors.secondaryContainer,
      );
      if (box.width > 24) {
        canvas.save();
        canvas.clipRect(box);
        _text(
          canvas,
          chordLabel(span.chord),
          Offset(box.left + 4, box.center.dy),
          text.labelMedium?.copyWith(color: colors.onSecondaryContainer),
          centerY: true,
        );
        canvas.restore();
      }
    }

    // Pitch line, colored by tuning, broken at silences.
    canvas.save();
    canvas.clipRect(chart);
    PitchPoint? previous;
    for (final p in track.between(start - 0.2, end)) {
      final color = tuningColor(centsFromNearest(p.midi), colors);
      final point = Offset(x(p.t), y(p.midi));
      if (previous != null &&
          p.t - previous.t <= PitchTrack.gapSeconds &&
          (p.midi - previous.midi).abs() < 1.5) {
        canvas.drawLine(
          Offset(x(previous.t), y(previous.midi)),
          point,
          Paint()
            ..color = color
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round,
        );
      } else {
        canvas.drawCircle(point, 2, Paint()..color = color);
      }
      previous = p;
    }
    canvas.restore();

    canvas.drawRect(
      chart,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = colors.outlineVariant,
    );
  }

  void _text(
    Canvas canvas,
    String value,
    Offset at,
    TextStyle? style, {
    bool centerY = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: value, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      centerY ? at.translate(0, -painter.height / 2) : at,
    );
  }

  @override
  bool shouldRepaint(MonitorPainter old) => true;
}
