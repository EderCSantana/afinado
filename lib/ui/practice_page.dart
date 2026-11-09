import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../audio/mic_listener.dart';
import '../audio/playback.dart';
import '../game/judge.dart';
import '../game/practice.dart';
import '../models/instrument.dart';
import '../models/song.dart';
import '../music/chords.dart';
import '../music/pitch.dart';
import 'widgets/cents_meter.dart';
import 'widgets/staff.dart';

/// The practice tab: the selected song, read note by note with the tuner.
class PracticeTab extends StatelessWidget {
  const PracticeTab({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final song = state.song, part = state.part;
    if (song == null || part == null || part.events.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.queue_music, size: 64),
            const SizedBox(height: 16),
            const Text('Escolha uma música para praticar.'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => state.goTo(AppTab.songs),
              child: const Text('Ver músicas'),
            ),
          ],
        ),
      );
    }
    return PracticeView(
      key: ValueKey((song, state.partIndex, state.instrument)),
      song: song,
      part: part,
      instrument: state.instrument,
      settings: state.settings,
      onSettingsChanged: state.save,
    );
  }
}

/// Shows the part on a staff and waits on each note or chord until it is
/// played right; says what was heard and how to fix it.
class PracticeView extends StatefulWidget {
  const PracticeView({
    super.key,
    required this.song,
    required this.part,
    required this.instrument,
    required this.settings,
    this.onSettingsChanged,
  });

  final Song song;
  final Part part;
  final Instrument instrument;
  final PlaySettings settings;
  final VoidCallback? onSettingsChanged;

  @override
  State<PracticeView> createState() => _PracticeViewState();
}

class _PracticeViewState extends State<PracticeView> {
  late final PracticeCoach _coach = PracticeCoach(
    widget.part,
    anyOctave: widget.instrument.anyOctave,
    strictCents: widget.settings.strictTuning ? 25 : null,
  );
  final _mic = MicListener();
  StreamSubscription<MicReading>? _readings;
  GuideTone? _guide;
  String? _error;

  PracticeFeedback _feedback = const PracticeFeedback(heard: Heard.silence);
  double? _heardMidi;

  /// Grade of the step just finished, shown for a moment.
  (Grade, DateTime)? _flash;

  /// Readings are ignored while the app plays the note itself.
  DateTime _mutedUntil = DateTime(0);
  bool _summaryShown = false;

  PlaySettings get settings => widget.settings;
  int get _transposition => widget.instrument.transposition;

  @override
  void initState() {
    super.initState();
    _mic.analyzeChords = widget.part.events.any((e) => e.isChord);
    _start();
  }

  Future<void> _start() async {
    try {
      await _mic.start(deviceId: settings.deviceId);
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
    _guide?.dispose();
    super.dispose();
  }

  void _onReading(MicReading r) {
    if (!mounted || r.at.isBefore(_mutedUntil) || _coach.finished) return;
    final feedback = _coach.hear(
      time: r.at.microsecondsSinceEpoch / 1e6,
      midi: r.midi,
      chroma: r.chroma,
      tuningCents: r.tuningCents,
    );
    final completed = feedback.completed;
    setState(() {
      _feedback = feedback;
      _heardMidi = r.midi;
      if (completed != null) {
        _flash = (_coach.results[completed].grade!, DateTime.now());
      }
    });
    if (_coach.finished && !_summaryShown) {
      _summaryShown = true;
      _showSummary();
    }
  }

  /// Plays the current note (or arpeggiates the chord) on the guide tone.
  Future<void> _listen() async {
    final event = _coach.current;
    if (event == null) return;
    final guide = _guide ??= await GuideTone.create();
    guide.volume = 0.35;
    final notes = event.isChord ? event.midi : [event.midi.first];
    final each = event.isChord ? 350 : 900;
    _mutedUntil = DateTime.now().add(
      Duration(milliseconds: each * notes.length + 300),
    );
    for (final m in notes) {
      guide.set(m);
      await Future<void>.delayed(Duration(milliseconds: each));
      if (!mounted) return;
    }
    guide.set(null);
  }

  void _goTo(int i) => setState(() {
    _coach.goTo(i);
    _summaryShown = false;
    _feedback = const PracticeFeedback(heard: Heard.silence);
  });

  void _restart() => setState(() {
    _coach.restart();
    _summaryShown = false;
    _feedback = const PracticeFeedback(heard: Heard.silence);
  });

  Future<void> _chooseLoop() async {
    final n = widget.part.events.length;
    var range = RangeValues(
      (_coach.loop ? _coach.loopStart : _coach.index).toDouble(),
      (_coach.loop ? _coach.loopEnd : (_coach.index + 7).clamp(0, n - 1))
          .toDouble(),
    );
    final result = await showDialog<RangeValues?>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('Repetir um trecho'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Da nota ${range.start.round() + 1} (${_stepName(range.start.round())}) '
                  'até a ${range.end.round() + 1} (${_stepName(range.end.round())})',
                ),
                RangeSlider(
                  values: range,
                  max: (n - 1).toDouble(),
                  divisions: n > 1 ? n - 1 : null,
                  onChanged: (v) => setDialog(() => range = v),
                ),
              ],
            ),
          ),
          actions: [
            if (_coach.loop)
              TextButton(
                onPressed: () =>
                    Navigator.pop(context, const RangeValues(-1, -1)),
                child: const Text('Parar de repetir'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, range),
              child: const Text('Repetir'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    setState(() {
      if (result.start < 0) {
        _coach.clearLoop();
      } else {
        _coach.setLoop(result.start.round(), result.end.round());
      }
    });
  }

  String _stepName(int i) {
    final e = widget.part.events[i];
    return _eventName(e);
  }

  String _eventName(NoteEvent e, {bool octave = false}) {
    final naming = settings.naming;
    final chord = e.chord ?? (e.midi.length > 1 ? chordOfNotes(e.midi) : null);
    if (chord != null) {
      return Chord(
        (chord.root + _transposition) % 12,
        chord.quality,
      ).name(naming);
    }
    return e.midi
        .map(
          (m) => octave
              ? noteName(m + _transposition, naming)
              : pitchClassName(m + _transposition, naming),
        )
        .join(' ');
  }

  Future<void> _showSummary() async {
    final again = await showDialog<_Next>(
      context: context,
      builder: (_) => _SummaryDialog(
        coach: _coach,
        describe: (i) => _eventName(widget.part.events[i], octave: true),
        naming: settings.naming,
        transposition: _transposition,
      ),
    );
    if (!mounted) return;
    switch (again) {
      case _Next.again:
        _restart();
      case _Next.hardest:
        final h = _coach.hardest(1).first;
        final n = widget.part.events.length;
        setState(() {
          _coach.setLoop((h - 2).clamp(0, n - 1), (h + 2).clamp(0, n - 1));
          _coach.restart();
          _summaryShown = false;
        });
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final n = widget.part.events.length;
    if (_error != null) {
      return Center(
        child: Text(_error!, style: TextStyle(color: colors.error)),
      );
    }
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): _listen,
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _goTo(_coach.index + 1),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _goTo(_coach.index - 1),
      },
      child: Focus(
        autofocus: true,
        child: Column(
          children: [
            _toolbar(theme, n),
            const Divider(height: 1),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: StaffView(
                  part: widget.part,
                  current: _coach.finished ? n : _coach.index,
                  grades: [for (final r in _coach.results) r.grade],
                  naming: settings.naming,
                  transposition: _transposition,
                  showNames: settings.showNames,
                  hold: _feedback.hold,
                  loop: _coach.loop ? (_coach.loopStart, _coach.loopEnd) : null,
                  onTapStep: _goTo,
                ),
              ),
            ),
            _feedbackPanel(theme),
          ],
        ),
      ),
    );
  }

  Widget _toolbar(ThemeData theme, int n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          Text(
            '${widget.song.title} · ${widget.part.name} · '
            '${widget.instrument.icon} ${widget.instrument.name}',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(width: 8),
          Text(
            '${_coach.doneCount}/$n'
            '${_coach.loop ? ' · repetição ${_coach.laps + 1}' : ''}',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(width: 16),
          IconButton(
            tooltip: 'Recomeçar',
            onPressed: _restart,
            icon: const Icon(Icons.restart_alt),
          ),
          IconButton(
            tooltip: 'Nota anterior (←)',
            onPressed: () => _goTo(_coach.index - 1),
            icon: const Icon(Icons.skip_previous),
          ),
          FilledButton.tonalIcon(
            onPressed: _listen,
            icon: const Icon(Icons.volume_up),
            label: const Text('Ouvir (espaço)'),
          ),
          IconButton(
            tooltip: 'Pular nota (→)',
            onPressed: () => _goTo(_coach.index + 1),
            icon: const Icon(Icons.skip_next),
          ),
          IconButton(
            tooltip: 'Repetir um trecho',
            isSelected: _coach.loop,
            onPressed: _chooseLoop,
            icon: const Icon(Icons.repeat),
            selectedIcon: const Icon(Icons.repeat_on),
          ),
          FilterChip(
            label: const Text('Nomes das notas'),
            selected: settings.showNames,
            onSelected: (v) {
              setState(() => settings.showNames = v);
              widget.onSettingsChanged?.call();
            },
          ),
          FilterChip(
            label: const Text('Afinação rigorosa'),
            tooltip: 'Só avança com a nota a menos de 25 cents',
            selected: settings.strictTuning,
            onSelected: (v) {
              setState(() {
                settings.strictTuning = v;
                _coach.strictCents = v ? 25 : null;
              });
              widget.onSettingsChanged?.call();
            },
          ),
        ],
      ),
    );
  }

  Widget _feedbackPanel(ThemeData theme) {
    final colors = theme.colorScheme;
    final naming = settings.naming;
    final event = _coach.current;
    final f = _feedback;
    final flash = _flash;
    final flashing =
        flash != null &&
        DateTime.now().difference(flash.$2) < const Duration(milliseconds: 700);

    final String message;
    Color messageColor = colors.onSurface;
    if (event == null) {
      message = 'Fim! Muito bem.';
    } else if (flashing) {
      message = '${flash.$1.label} Próxima…';
      messageColor = gradeColor(flash.$1, colors);
    } else {
      switch (f.heard) {
        case Heard.silence:
          message = 'Toque ${_eventName(event, octave: !event.isChord)}';
        case Heard.playAgain:
          message = 'A próxima é a mesma — toque de novo';
        case Heard.right:
          message = 'Isso! Segure…';
          messageColor = tuningColor(f.cents, colors);
        case Heard.outOfTune:
          message = f.cents! > 0
              ? 'Nota certa, mas alta: abaixe um pouco'
              : 'Nota certa, mas baixa: suba um pouco';
          messageColor = Colors.amber;
        case Heard.wrong:
          final chord = f.heardChord;
          final toGo = f.semitonesToGo;
          if (chord != null) {
            message =
                'Ouvi ${Chord((chord.root + _transposition) % 12, chord.quality).name(naming)}'
                ' — o acorde é ${_eventName(event)}';
          } else if (toGo != null && f.heardMidi != null) {
            final name = noteName(f.heardMidi! + _transposition, naming);
            final steps = toGo.abs() == 1
                ? '1 semitom'
                : '${toGo.abs()} semitons';
            message = toGo > 0
                ? 'Isso é $name — suba $steps'
                : 'Isso é $name — desça $steps';
          } else {
            message = 'Ouvindo outras notas';
          }
          messageColor = Colors.deepOrange.shade300;
      }
    }

    final heard = event != null && event.isChord
        ? null
        : _heardMidi == null
        ? '—'
        : noteName(_heardMidi!.round() + _transposition, naming);
    final showCents = f.heard == Heard.right || f.heard == Heard.outOfTune
        ? f.cents
        : null;

    return Container(
      color: colors.surfaceContainerHigh,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: [
          _label(
            theme,
            'Toque',
            event == null ? '—' : _eventName(event, octave: !event.isChord),
          ),
          const SizedBox(width: 32),
          if (heard != null) ...[
            _label(theme, 'Ouvindo', heard),
            const SizedBox(width: 32),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        message,
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: messageColor,
                        ),
                      ),
                    ),
                    if (showCents != null)
                      Text(
                        '${showCents > 0 ? '+' : ''}${showCents.round()} cents',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: tuningColor(showCents, colors),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                CentsMeter(cents: showCents),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(ThemeData theme, String title, String value) => Column(
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

enum _Next { again, hardest }

class _SummaryDialog extends StatelessWidget {
  const _SummaryDialog({
    required this.coach,
    required this.describe,
    required this.naming,
    required this.transposition,
  });

  final PracticeCoach coach;
  final String Function(int step) describe;
  final NoteNaming naming;
  final int transposition;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hardest = coach.hardest();
    final tendency = coach.tendency;
    final minutes = coach.totalSeconds ~/ 60;
    final seconds = (coach.totalSeconds % 60).round();
    return AlertDialog(
      title: const Text('Música completa!'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tempo: ${minutes > 0 ? '$minutes min ' : ''}$seconds s'),
            const SizedBox(height: 8),
            for (final g in [Grade.perfect, Grade.good, Grade.outOfTune])
              Text('${g.label}: ${coach.count(g)}'),
            if (tendency != null) ...[
              const SizedBox(height: 8),
              Text(
                tendency.abs() <= 8
                    ? 'Sua afinação média está ótima.'
                    : tendency > 0
                    ? 'Você tende a ficar alto (${tendency.round()} cents em média).'
                    : 'Você tende a ficar baixo (${tendency.round()} cents em média).',
              ),
            ],
            if (hardest.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Onde teve mais dificuldade',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              for (final i in hardest) Text('• ${_describeTrouble(i)}'),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fechar'),
        ),
        if (hardest.isNotEmpty)
          TextButton(
            onPressed: () => Navigator.pop(context, _Next.hardest),
            child: const Text('Treinar o trecho mais difícil'),
          ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _Next.again),
          child: const Text('De novo'),
        ),
      ],
    );
  }

  String _describeTrouble(int i) {
    final r = coach.results[i];
    final parts = <String>['nota ${i + 1}, ${describe(i)}'];
    if (r.wrongTries > 0) {
      final common = r.wrongNotes.entries.isEmpty
          ? null
          : r.wrongNotes.entries
                .reduce((a, b) => a.value >= b.value ? a : b)
                .key;
      parts.add(
        '${r.wrongTries} tentativa${r.wrongTries > 1 ? 's' : ''} errada${r.wrongTries > 1 ? 's' : ''}'
        '${common != null ? ' (tocou ${noteName(common + transposition, naming)})' : ''}',
      );
    }
    if (r.seconds > 3) parts.add('${r.seconds.round()} s');
    final c = r.cents;
    if (c != null && c.abs() > 12) {
      parts.add('${c > 0 ? '+' : ''}${c.round()} cents');
    }
    return parts.join(' · ');
  }
}
