import '../music/chords.dart';

/// One thing to play: a note, or a chord, from [start] for [duration]
/// seconds.
class NoteEvent {
  const NoteEvent({
    required this.start,
    required this.duration,
    required this.midi,
    this.chord,
  });

  final double start;
  final double duration;

  /// MIDI notes sounding (one for a melody note, several for a chord).
  final List<int> midi;

  /// The chord, when this event is a chord to strum rather than notes.
  final Chord? chord;

  double get end => start + duration;
  bool get isChord => chord != null || midi.length > 1;

  NoteEvent transposed(int semitones) => NoteEvent(
    start: start,
    duration: duration,
    midi: [for (final m in midi) m + semitones],
    chord: chord == null
        ? null
        : Chord((chord!.root + semitones) % 12, chord!.quality),
  );
}

/// What a part contains.
enum PartKind { melody, chords }

/// One line of a song: a MIDI track, the melody or the chords extracted from
/// audio.
class Part {
  const Part({
    required this.name,
    required this.kind,
    required this.events,
    this.program,
  });

  final String name;
  final PartKind kind;

  /// Sorted by start time.
  final List<NoteEvent> events;

  /// General MIDI program of a MIDI track, if known.
  final int? program;

  bool get isEmpty => events.isEmpty;

  /// Lowest and highest MIDI note.
  (int, int)? get range {
    if (events.isEmpty) return null;
    var low = 127, high = 0;
    for (final e in events) {
      for (final m in e.midi) {
        if (m < low) low = m;
        if (m > high) high = m;
      }
    }
    return (low, high);
  }
}

/// A song ready to play along with.
class Song {
  const Song({
    required this.title,
    required this.duration,
    required this.parts,
    this.audioPath,
  });

  final String title;

  /// Seconds.
  final double duration;

  /// Audio played as accompaniment (null for MIDI files).
  final String? audioPath;

  final List<Part> parts;
}
