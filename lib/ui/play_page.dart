import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../audio/mic_listener.dart';
import '../audio/playback.dart';
import '../game/judge.dart';
import '../models/instrument.dart';
import '../models/song.dart';
import '../music/pitch.dart';
import 'home_page.dart';

const _countdown = 3.0;

/// The game: notes scroll towards the line, the microphone listens and each
/// note is graded.
class PlayPage extends StatefulWidget {
  const PlayPage({
    super.key,
    required this.song,
    required this.part,
    required this.instrument,
    required this.settings,
  });

  final Song song;
  final Part part;
  final Instrument instrument;
  final PlaySettings settings;

  @override
  State<PlayPage> createState() => _PlayPageState();
}

class _PlayPageState extends State<PlayPage>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((_) => _tick());
  late Judge _judge;
  final _clock = Stopwatch();
  MicListener? _mic;
  StreamSubscription<MicReading>? _readings;
  SongPlayer? _player;
  GuideTone? _guide;

  double _time = -_countdown;
  bool _started = false;
  bool _finished = false;
  String? _error;

  /// Recent pitches heard: (song time, MIDI, right note?).
  final _trail = <(double, double, bool)>[];
  double? _heardMidi;
  double? _heardCents;

  Part get part => widget.part;
  bool get _chordMode => part.kind == PartKind.chords;

  double get _end {
    final last = part.events.isEmpty ? 0.0 : part.events.last.end;
    return math.max(
          last,
          widget.song.audioPath != null ? widget.song.duration : 0,
        ) +
        1;
  }

  @override
  void initState() {
    super.initState();
    _judge = Judge(part, anyOctave: widget.instrument.anyOctave);
    _setUp();
  }

  Future<void> _setUp() async {
    try {
      final mic = _mic = MicListener(
        analyzeChords: _chordMode || part.events.any((e) => e.isChord),
      );
      await mic.start(deviceId: widget.settings.deviceId);
      _readings = mic.readings.listen(_onReading);
      final audio = widget.song.audioPath;
      if (audio != null) _player = await SongPlayer.load(audio);
      if (widget.settings.guideTone) _guide = await GuideTone.create();
      if (!mounted) return;
      _clock.start();
      _ticker.start();
    } catch (e) {
      setState(
        () => _error = 'Não foi possível usar o microfone ou o áudio: $e',
      );
    }
  }

  void _tick() {
    final player = _player;
    if (_started && player != null) {
      final position = player.position;
      if (position == null) {
        _time = _end; // The song ended.
      } else {
        _time = position;
      }
    } else {
      _time = _clock.elapsedMicroseconds / 1e6 - _countdown;
      if (_time >= 0 && !_started) {
        _started = true;
        player?.play(volume: widget.settings.accompanimentVolume);
      }
    }

    final guide = _guide;
    if (guide != null) {
      final i = _judge.eventAt(_time);
      guide.set(i == null ? null : part.events[i].midi.first);
    }
    _trail.removeWhere((p) => p.$1 < _time - 3);
    if (_time >= _end && !_finished) _finish();
    setState(() {});
  }

  void _onReading(MicReading r) {
    if (!_clock.isRunning || _time < 0) return;
    final ago = DateTime.now().difference(r.at).inMicroseconds / 1e6;
    final soundTime =
        _time - ago - r.windowSeconds / 2 - widget.settings.latency;
    final cents = _judge.listen(
      Hearing(
        time: soundTime,
        midi: r.midi,
        chroma: r.chroma,
        tuningCents: r.tuningCents,
      ),
    );
    _heardMidi = r.midi;
    _heardCents = cents;
    if (r.midi != null) _trail.add((soundTime, r.midi!, cents != null));
  }

  void _togglePause() {
    if (_finished) return;
    if (_clock.isRunning) {
      _clock.stop();
      _player?.pause();
      _ticker.stop();
      _guide?.set(null);
    } else {
      _clock.start();
      if (_started) _player?.play();
      _ticker.start();
    }
    setState(() {});
  }

  Future<void> _finish() async {
    _finished = true;
    _ticker.stop();
    _clock.stop();
    _guide?.set(null);
    await _readings?.cancel();
    if (!mounted) return;
    final again = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _ResultsDialog(judge: _judge, naming: widget.settings.naming),
    );
    if (!mounted) return;
    if (again == true) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => PlayPage(
            song: widget.song,
            part: widget.part,
            instrument: widget.instrument,
            settings: widget.settings,
          ),
        ),
      );
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _readings?.cancel();
    _mic?.dispose();
    _player?.dispose();
    _guide?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final naming = widget.settings.naming;
    final current = _judge.eventAt(math.max(_time, 0));
    final target = current == null ? null : part.events[current];
    final transposition = widget.instrument.transposition;
    final finished = _judge.finishedBy(_time).toList();
    final hits = finished.where((r) => r.grade != Grade.missed).length;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${widget.song.title} — ${widget.instrument.icon} ${widget.instrument.name}',
        ),
        actions: [
          Center(
            child: Text(
              '${_judge.score} pts',
              style: theme.textTheme.titleLarge,
            ),
          ),
          const SizedBox(width: 16),
          if (finished.isNotEmpty)
            Center(
              child: Text('${(100 * hits / finished.length).round()}% certas'),
            ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: _clock.isRunning ? 'Pausar' : 'Continuar',
            icon: Icon(_clock.isRunning ? Icons.pause : Icons.play_arrow),
            onPressed: _togglePause,
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: (_time / _end).clamp(0, 1).toDouble(),
          ),
        ),
      ),
      body: _error != null
          ? Center(
              child: Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _HighwayPainter(
                            part: part,
                            judge: _judge,
                            time: _time,
                            trail: _trail,
                            naming: naming,
                            transposition: transposition,
                            anyOctave: widget.instrument.anyOctave,
                            chordLane: _chordMode,
                            colors: theme.colorScheme,
                          ),
                        ),
                      ),
                      if (_time < 0)
                        Center(
                          child: Text(
                            '${(-_time).ceil()}',
                            style: theme.textTheme.displayLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                _Tuner(
                  target: target,
                  heardMidi: _heardMidi,
                  cents: _heardCents,
                  naming: naming,
                  transposition: transposition,
                  chord: _chordMode || (target?.isChord ?? false),
                ),
              ],
            ),
    );
  }
}

/// Bottom bar: what to play, what is heard and how in tune it is.
class _Tuner extends StatelessWidget {
  const _Tuner({
    required this.target,
    required this.heardMidi,
    required this.cents,
    required this.naming,
    required this.transposition,
    required this.chord,
  });

  final NoteEvent? target;
  final double? heardMidi;
  final double? cents;
  final NoteNaming naming;
  final int transposition;
  final bool chord;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = target;
    final targetName = t == null
        ? '—'
        : t.chord != null
        ? t.chord!.name(naming)
        : t.midi.map((m) => noteName(m + transposition, naming)).join(' ');
    final heard = heardMidi == null
        ? '—'
        : noteName(heardMidi!.round() + transposition, naming);
    final c = cents;
    final status = c == null
        ? (heardMidi == null ? 'Silêncio' : 'Nota errada')
        : c.abs() <= 12
        ? 'Afinado!'
        : c > 0
        ? 'Alto (${c.round()} cents)'
        : 'Baixo (${c.round()} cents)';
    final color = c == null
        ? theme.colorScheme.outline
        : c.abs() <= 12
        ? Colors.greenAccent
        : c.abs() <= 25
        ? Colors.amber
        : Colors.deepOrange;

    return Container(
      color: theme.colorScheme.surfaceContainerHigh,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: [
          _label(context, 'Toque', targetName),
          const SizedBox(width: 32),
          if (!chord) _label(context, 'Ouvindo', heard),
          const SizedBox(width: 32),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status,
                  style: theme.textTheme.titleMedium?.copyWith(color: color),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 24,
                  child: CustomPaint(
                    painter: _NeedlePainter(
                      c,
                      color,
                      theme.colorScheme.outline,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(BuildContext context, String title, String value) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.labelMedium),
        Text(
          value,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

/// A -50..+50 cents scale with a needle.
class _NeedlePainter extends CustomPainter {
  _NeedlePainter(this.cents, this.color, this.scale);

  final double? cents;
  final Color color;
  final Color scale;

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.width / 2;
    final line = Paint()
      ..color = scale
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      line,
    );
    for (final c in [-50, -25, -12, 0, 12, 25, 50]) {
      final x = mid + c / 50 * mid;
      final h = c == 0 ? size.height : size.height / 2;
      canvas.drawLine(
        Offset(x, (size.height - h) / 2),
        Offset(x, (size.height + h) / 2),
        line,
      );
    }
    final value = cents;
    if (value == null) return;
    final x = mid + value.clamp(-50, 50) / 50 * mid;
    canvas.drawCircle(Offset(x, size.height / 2), 8, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_NeedlePainter old) =>
      old.cents != cents || old.color != color;
}

/// Notes as blocks moving right to left, past a line at the left where they
/// should be played; the pitches heard are drawn as a trail.
class _HighwayPainter extends CustomPainter {
  _HighwayPainter({
    required this.part,
    required this.judge,
    required this.time,
    required this.trail,
    required this.naming,
    required this.transposition,
    required this.anyOctave,
    required this.chordLane,
    required this.colors,
  });

  final Part part;
  final Judge judge;
  final double time;
  final List<(double, double, bool)> trail;
  final NoteNaming naming;
  final int transposition;
  final bool anyOctave;
  final bool chordLane;
  final ColorScheme colors;

  static const _past = 1.5;
  static const _ahead = 5.5;

  Color _colorFor(int index) {
    final event = part.events[index];
    if (event.end > time) {
      return event.start <= time ? colors.primary : colors.primaryContainer;
    }
    return switch (judge.results[index].grade) {
      Grade.perfect => Colors.green,
      Grade.good => Colors.lightGreen,
      Grade.outOfTune => Colors.amber.shade700,
      Grade.missed => Colors.red.shade900,
    };
  }

  @override
  void paint(Canvas canvas, Size size) {
    final pps = size.width / (_past + _ahead);
    final lineX = _past * pps;
    double x(double t) => lineX + (t - time) * pps;

    canvas.drawRect(Offset.zero & size, Paint()..color = colors.surface);

    if (chordLane) {
      _paintChords(canvas, size, x);
    } else {
      _paintNotes(canvas, size, x);
    }

    canvas.drawLine(
      Offset(lineX, 0),
      Offset(lineX, size.height),
      Paint()
        ..color = colors.onSurface
        ..strokeWidth = 3,
    );
  }

  void _paintChords(Canvas canvas, Size size, double Function(double) x) {
    final top = size.height * 0.3, height = size.height * 0.4;
    for (final (i, e) in part.events.indexed) {
      final left = x(e.start), right = x(e.end);
      if (right < 0 || left > size.width) continue;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTRB(left + 2, top, right - 2, top + height),
        const Radius.circular(12),
      );
      canvas.drawRRect(rect, Paint()..color = _colorFor(i));
      final name =
          e.chord?.name(naming) ??
          e.midi.map((m) => noteName(m + transposition, naming)).join(' ');
      final notes = e.midi
          .map((m) => pitchClassName(m + transposition, naming))
          .join(' · ');
      _text(
        canvas,
        name,
        Offset(left + 14, top + 12),
        32,
        colors.onPrimaryContainer,
        right - left - 20,
        bold: true,
      );
      _text(
        canvas,
        notes,
        Offset(left + 14, top + height - 34),
        16,
        colors.onPrimaryContainer,
        right - left - 20,
      );
    }
    // Chord mode shows whether the chord is right, not a pitch line.
    final recent = trail.where((p) => p.$1 > time - 0.3);
    if (recent.isNotEmpty) {
      canvas.drawCircle(
        Offset(x(time), top + height + 30),
        10,
        Paint()..color = recent.last.$3 ? Colors.greenAccent : colors.outline,
      );
    }
  }

  void _paintNotes(Canvas canvas, Size size, double Function(double) x) {
    final range = part.range ?? (60, 72);
    var low = range.$1 - 2, high = range.$2 + 2;
    if (high - low < 14) {
      final pad = (14 - (high - low)) ~/ 2;
      low -= pad;
      high += pad;
    }
    final rowHeight = size.height / (high - low + 1);
    double y(double midi) => (high - midi) * rowHeight + rowHeight / 2;

    // Lanes: shaded for sharps, labeled at C (or every note when they fit).
    for (var m = low; m <= high; m++) {
      final top = y(m.toDouble()) - rowHeight / 2;
      if ({1, 3, 6, 8, 10}.contains((m + transposition) % 12)) {
        canvas.drawRect(
          Rect.fromLTWH(0, top, size.width, rowHeight),
          Paint()..color = colors.surfaceContainerLow,
        );
      }
      if (rowHeight >= 16 || (m + transposition) % 12 == 0) {
        _text(
          canvas,
          noteName(m + transposition, naming),
          Offset(4, top + rowHeight / 2 - 7),
          11,
          colors.outline,
          60,
        );
      }
    }

    for (final (i, e) in part.events.indexed) {
      final left = x(e.start), right = x(e.end);
      if (right < 0 || left > size.width) continue;
      for (final m in e.midi) {
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTRB(
            left + 1,
            y(m.toDouble()) - rowHeight * 0.45,
            right - 1,
            y(m.toDouble()) + rowHeight * 0.45,
          ),
          Radius.circular(math.min(8, rowHeight / 3)),
        );
        canvas.drawRRect(rect, Paint()..color = _colorFor(i));
        if (right - left > 40 && rowHeight >= 12) {
          _text(
            canvas,
            noteName(m + transposition, naming),
            Offset(left + 6, y(m.toDouble()) - math.min(rowHeight * 0.4, 9)),
            math.min(rowHeight * 0.7, 14),
            colors.onPrimaryContainer,
            right - left - 8,
            bold: true,
          );
        }
      }
    }

    // The pitch trail, folded into the part's range for octave-free voices.
    final path = Paint()
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    (double, double, bool)? previous;
    for (final p in trail) {
      var midi = p.$2;
      if (anyOctave) {
        final i = judge.eventAt(p.$1);
        final reference = i == null
            ? (low + high) / 2
            : part.events[i].midi.first.toDouble();
        midi -= 12 * ((midi - reference) / 12).round();
      }
      final point = (p.$1, midi, p.$3);
      if (previous != null &&
          p.$1 - previous.$1 < 0.15 &&
          (midi - previous.$2).abs() < 1.5) {
        path.color = p.$3 ? Colors.greenAccent : Colors.white70;
        canvas.drawLine(
          Offset(x(previous.$1), y(previous.$2)),
          Offset(x(p.$1), y(midi)),
          path,
        );
      }
      previous = point;
    }
  }

  void _text(
    Canvas canvas,
    String text,
    Offset at,
    double size,
    Color color,
    double maxWidth, {
    bool bold = false,
  }) {
    if (maxWidth <= 0) return;
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: size,
          color: color,
          fontWeight: bold ? FontWeight.bold : null,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    painter.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_HighwayPainter old) => true;
}

class _ResultsDialog extends StatelessWidget {
  const _ResultsDialog({required this.judge, required this.naming});

  final Judge judge;
  final NoteNaming naming;

  @override
  Widget build(BuildContext context) {
    final results = judge.results;
    final counts = {
      for (final g in Grade.values)
        g: results.where((r) => r.grade == g).length,
    };
    final cents = [for (final r in results) ?r.averageCents];
    final tendency = cents.isEmpty
        ? null
        : cents.reduce((a, b) => a + b) / cents.length;
    final max = results.length * 100;
    return AlertDialog(
      title: Text('${judge.score} pontos'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (max > 0) Text('${(100 * judge.score / max).round()}% do máximo'),
          const SizedBox(height: 12),
          for (final g in Grade.values) Text('${g.label}: ${counts[g]}'),
          const SizedBox(height: 12),
          if (tendency != null)
            Text(
              tendency.abs() <= 8
                  ? 'Sua afinação média está ótima.'
                  : tendency > 0
                  ? 'Você tende a ficar alto (${tendency.round()} cents em média).'
                  : 'Você tende a ficar baixo (${tendency.round()} cents em média).',
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Voltar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Tocar de novo'),
        ),
      ],
    );
  }
}
