import '../models/song.dart';
import '../music/chords.dart';
import '../music/pitch.dart';

/// What the microphone heard at one moment.
class Hearing {
  const Hearing({required this.time, this.midi, this.chroma, this.tuningCents});

  /// Song time (seconds) the sound was produced at, latency already removed.
  final double time;

  /// Detected pitch as a fractional MIDI note, for single notes.
  final double? midi;

  /// Pitch-class energy, for chords.
  final List<double>? chroma;

  /// Deviation of the strongest spectral peaks from equal temperament.
  final double? tuningCents;
}

/// How a note went.
enum Grade {
  perfect('Perfeito!'),
  good('Bom'),
  outOfTune('Desafinado'),
  missed('Errou');

  const Grade(this.label);
  final String label;
}

/// Result of one event, filled in while it plays.
class EventResult {
  int frames = 0;
  int hits = 0;
  double centsSum = 0;
  int centsCount = 0;

  /// Share of the note's time that the right note was heard.
  double get hitRatio => frames == 0 ? 0 : hits / frames;

  /// Average deviation in cents while it was right (positive = sharp).
  double? get averageCents => centsCount == 0 ? null : centsSum / centsCount;

  Grade get grade {
    if (hitRatio < 0.35) return Grade.missed;
    final cents = averageCents?.abs() ?? 0;
    if (cents > 25) return Grade.outOfTune;
    return hitRatio >= 0.6 && cents <= 12 ? Grade.perfect : Grade.good;
  }

  int get points => switch (grade) {
    Grade.perfect => 100,
    Grade.good => 70,
    Grade.outOfTune => 35,
    Grade.missed => 0,
  };
}

/// Compares what is heard with the part being played.
class Judge {
  Judge(this.part, {this.anyOctave = false, this.toleranceCents = 50});

  final Part part;
  final bool anyOctave;

  /// A pitch within this of the target counts as the right note.
  final double toleranceCents;

  late final List<EventResult> results = [
    for (final _ in part.events) EventResult(),
  ];
  int _cursor = 0;

  /// Index of the event playing at [time], or null between events.
  int? eventAt(double time) {
    while (_cursor > 0 && part.events[_cursor].start > time) {
      _cursor--;
    }
    while (_cursor < part.events.length - 1 &&
        part.events[_cursor].end <= time) {
      _cursor++;
    }
    final e = part.events.isEmpty ? null : part.events[_cursor];
    return e != null && e.start <= time && time < e.end ? _cursor : null;
  }

  /// Scores [hearing] against the event playing at its time. Returns the
  /// deviation in cents when the right note or chord was heard.
  double? listen(Hearing hearing) {
    final index = eventAt(hearing.time);
    if (index == null) return null;
    final event = part.events[index];
    final result = results[index];
    // Skip the attack: the first 80 ms of a note are rarely stable.
    if (hearing.time - event.start < 0.08 && event.duration > 0.25) return null;
    result.frames++;

    double? cents;
    if (event.isChord) {
      final chroma = hearing.chroma;
      if (chroma != null && chordEventHeard(event, chroma)) {
        cents = hearing.tuningCents ?? 0;
      }
    } else if (hearing.midi != null) {
      final c = centsFrom(
        hearing.midi!,
        event.midi.first,
        anyOctave: anyOctave,
      );
      if (c.abs() <= toleranceCents) cents = c;
    }
    if (cents == null) return null;
    result.hits += 1;
    result.centsSum += cents;
    result.centsCount += 1;
    return cents;
  }

  int get score => results.fold(0, (sum, r) => sum + r.points);

  /// Results of events that already ended at [time].
  Iterable<EventResult> finishedBy(double time) sync* {
    for (var i = 0; i < part.events.length && part.events[i].end <= time; i++) {
      yield results[i];
    }
  }
}

/// Whether [chroma] (from the microphone) sounds like [event]'s chord.
bool chordEventHeard(NoteEvent event, List<double> chroma) {
  final chord =
      event.chord ??
      // Notes played together from a MIDI file: match their pitch classes.
      chordOfNotes(event.midi);
  if (chord != null) {
    final best = bestChord(chroma);
    return best != null &&
        (best.$1 == chord || chordMatch(chroma, chord) >= 0.7);
  }
  final classes = {for (final m in event.midi) m % 12};
  final inside = classes.fold(0.0, (sum, pc) => sum + chroma[pc]);
  return inside >= 0.7 && classes.every((pc) => chroma[pc] > 0.04);
}

/// The named chord made of exactly the pitch classes of [midi], if any.
Chord? chordOfNotes(List<int> midi) {
  final classes = {for (final m in midi) m % 12};
  for (final chord in allChords) {
    if (chord.pitchClasses.length == classes.length &&
        chord.pitchClasses.containsAll(classes)) {
      return chord;
    }
  }
  return null;
}
