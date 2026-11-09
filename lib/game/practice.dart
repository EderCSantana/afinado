import '../models/song.dart';
import '../music/chords.dart';
import '../music/pitch.dart';
import 'judge.dart';

/// How one note (or chord) of the practice went.
class StepResult {
  /// Wrong notes held long enough to count as an attempt.
  int wrongTries = 0;

  /// Seconds from being asked until it was played right.
  double seconds = 0;

  /// Average deviation in cents while it was held (positive = sharp).
  double? cents;

  /// Wrong notes played (MIDI) and how often, for the summary.
  final wrongNotes = <int, int>{};

  bool get done => cents != null;

  Grade? get grade {
    final c = cents?.abs();
    if (c == null) return null;
    if (c <= 12) return Grade.perfect;
    if (c <= 25) return Grade.good;
    return Grade.outOfTune;
  }

  /// Higher is harder: wrong attempts weigh more than slowness.
  double get difficulty => wrongTries * 2 + seconds + (cents?.abs() ?? 0) / 25;
}

/// What the coach thinks of the latest sound.
enum Heard {
  /// Nothing (or noise).
  silence,

  /// The right note, being held.
  right,

  /// The right note, but too far out of tune for strict mode.
  outOfTune,

  /// Another note or chord.
  wrong,

  /// The next note repeats the last one: let it go and play it again.
  playAgain,
}

class PracticeFeedback {
  const PracticeFeedback({
    required this.heard,
    this.cents,
    this.hold = 0,
    this.heardMidi,
    this.semitonesToGo,
    this.heardChord,
    this.completed,
  });

  final Heard heard;

  /// Deviation from the target, when the right note is heard.
  final double? cents;

  /// How much of the hold is done, 0..1.
  final double hold;

  /// The note heard, rounded, for single notes.
  final int? heardMidi;

  /// For a wrong note: semitones to move to reach the target (+ = go up).
  final int? semitonesToGo;

  /// The chord that best matches what is heard, for chord steps.
  final Chord? heardChord;

  /// Index of the step just completed by this sound.
  final int? completed;
}

/// Practice by reading: waits on each note or chord until it is played
/// right (and held for a moment), then moves on. No clock, no misses.
class PracticeCoach {
  PracticeCoach(
    this.part, {
    this.anyOctave = false,
    this.noteHold = 0.25,
    this.chordHold = 0.4,
    this.toleranceCents = 50,
    this.strictCents,
  }) : results = [for (final _ in part.events) StepResult()],
       loopEnd = part.events.length - 1;

  final Part part;
  final bool anyOctave;

  /// Seconds the right note (or chord) must be held to count.
  final double noteHold;
  final double chordHold;

  /// A pitch within this of the target is the right note.
  final double toleranceCents;

  /// When set, the note only counts when held within this many cents:
  /// intonation practice.
  double? strictCents;

  final List<StepResult> results;

  int index = 0;
  bool finished = false;

  /// Repeat the steps loopStart..loopEnd (inclusive) until stopped.
  bool loop = false;
  int loopStart = 0;
  int loopEnd;
  int laps = 0;

  double _held = 0;
  double _missing = 0;
  final _cents = <double>[];
  double? _lastTime;
  double? _stepStart;
  bool _needRelease = false;
  int? _wrongNote;
  double _wrongSince = 0;
  bool _wrongCounted = false;

  NoteEvent? get current => finished ? null : part.events[index];

  /// Jumps to step [i], forgetting the hold in progress.
  void goTo(int i) {
    index = i.clamp(0, part.events.length - 1);
    finished = false;
    _resetStep(null);
  }

  void restart() {
    for (var i = 0; i < results.length; i++) {
      results[i] = StepResult();
    }
    laps = 0;
    goTo(loop ? loopStart : 0);
  }

  void setLoop(int start, int end) {
    loop = true;
    loopStart = start;
    loopEnd = end;
    laps = 0;
    if (index < start || index > end) goTo(start);
  }

  void clearLoop() {
    loop = false;
    loopStart = 0;
    loopEnd = part.events.length - 1;
  }

  /// Steps with trouble, hardest first.
  List<int> hardest([int count = 5]) {
    final done = [
      for (final (i, r) in results.indexed)
        if (r.done &&
            (r.wrongTries > 0 || r.seconds > 3 || r.grade != Grade.perfect))
          i,
    ];
    done.sort((a, b) => results[b].difficulty.compareTo(results[a].difficulty));
    return done.take(count).toList();
  }

  void _resetStep(double? now) {
    _held = 0;
    _missing = 0;
    _cents.clear();
    _stepStart = now;
    _wrongNote = null;
    _wrongCounted = false;
    _needRelease = false;
  }

  /// Takes in what the microphone heard at [time] (seconds, any clock that
  /// only moves forward).
  PracticeFeedback hear({
    required double time,
    double? midi,
    List<double>? chroma,
    double? tuningCents,
  }) {
    final event = current;
    if (event == null) return const PracticeFeedback(heard: Heard.silence);
    final dt = _lastTime == null
        ? 0.0
        : (time - _lastTime!).clamp(0.0, 0.2).toDouble();
    _lastTime = time;
    _stepStart ??= time;
    final result = results[index];

    // Matching.
    double? cents;
    Chord? heardChord;
    int? heardMidi;
    int? toGo;
    if (event.isChord) {
      if (chroma != null && chroma.any((c) => c > 0)) {
        if (chordEventHeard(event, chroma)) {
          cents = tuningCents ?? 0;
        } else {
          final best = bestChord(chroma);
          if (best != null && best.$2 >= 0.5) heardChord = best.$1;
        }
      }
    } else if (midi != null) {
      heardMidi = midi.round();
      final c = centsFrom(midi, event.midi.first, anyOctave: anyOctave);
      if (c.abs() <= toleranceCents) {
        cents = c;
      } else {
        toGo = -(c / 100).round();
      }
    }

    if (_needRelease) {
      if (cents == null) {
        _needRelease = false;
      } else {
        return PracticeFeedback(heard: Heard.playAgain, cents: cents);
      }
    }

    final hold = event.isChord ? chordHold : noteHold;
    if (cents != null) {
      _missing = 0;
      _wrongNote = null;
      final strict = strictCents;
      if (strict != null && cents.abs() > strict) {
        return PracticeFeedback(
          heard: Heard.outOfTune,
          cents: cents,
          hold: _held / hold,
          heardMidi: heardMidi,
        );
      }
      _held += dt;
      _cents.add(cents);
      if (_held < hold) {
        return PracticeFeedback(
          heard: Heard.right,
          cents: cents,
          hold: _held / hold,
          heardMidi: heardMidi,
        );
      }
      // Done: the middle of the samples, to leave out attack and release.
      final sorted = [..._cents]..sort();
      result.cents = sorted[sorted.length ~/ 2];
      result.seconds = time - _stepStart!;
      final completed = index;
      _advance(time);
      return PracticeFeedback(
        heard: Heard.right,
        cents: result.cents,
        hold: 1,
        heardMidi: heardMidi,
        completed: completed,
      );
    }

    // Not the right sound: forget the hold after a short dropout.
    _missing += dt;
    if (_missing > 0.15) {
      _held = 0;
      _cents.clear();
    }
    final wrong = heardMidi ?? heardChord?.root;
    if (wrong != null) {
      if (wrong != _wrongNote) {
        _wrongNote = wrong;
        _wrongSince = time;
        _wrongCounted = false;
      } else if (!_wrongCounted && time - _wrongSince >= 0.2) {
        _wrongCounted = true;
        result.wrongTries++;
        if (heardMidi != null) {
          result.wrongNotes[heardMidi] =
              (result.wrongNotes[heardMidi] ?? 0) + 1;
        }
      }
      if (toGo != null && anyOctave) {
        toGo = toGo - 12 * (toGo / 12).round();
      }
      return PracticeFeedback(
        heard: Heard.wrong,
        heardMidi: heardMidi,
        semitonesToGo: toGo,
        heardChord: heardChord,
        hold: _held / hold,
      );
    }
    _wrongNote = null;
    return PracticeFeedback(heard: Heard.silence, hold: _held / hold);
  }

  void _advance(double now) {
    final previous = part.events[index];
    if (loop && index >= loopEnd) {
      index = loopStart;
      laps++;
    } else if (index + 1 >= part.events.length) {
      finished = true;
      return;
    } else {
      index++;
    }
    _resetStep(now);
    final next = part.events[index];
    // The same sound again must be played again, not just kept ringing.
    _needRelease =
        next.midi.length == previous.midi.length &&
        next.chord == previous.chord &&
        [
          for (var i = 0; i < next.midi.length; i++)
            next.midi[i] == previous.midi[i],
        ].every((same) => same);
  }

  /// Seconds spent practicing, from the results.
  double get totalSeconds => results.fold(0.0, (sum, r) => sum + r.seconds);

  /// Average cents of the steps played (positive = tends sharp).
  double? get tendency {
    final cents = [for (final r in results) ?r.cents];
    if (cents.isEmpty) return null;
    return cents.reduce((a, b) => a + b) / cents.length;
  }

  int count(Grade grade) => results.where((r) => r.grade == grade).length;

  /// Number of steps already played right.
  int get doneCount => results.where((r) => r.done).length;
}
