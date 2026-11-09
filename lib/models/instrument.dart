import 'song.dart';

/// An instrument (or voice) to play along with.
class Instrument {
  const Instrument({
    required this.name,
    required this.icon,
    required this.low,
    required this.high,
    this.chords = false,
    this.anyOctave = false,
    this.transposition = 0,
    this.stems = const ['vocals'],
  });

  /// Separated instruments (stems) whose part suits it best, in order.
  final List<String> stems;

  final String name;

  /// An emoji shown in the picker.
  final String icon;

  /// Lowest and highest MIDI notes it sounds.
  final int low;
  final int high;

  /// Whether it plays chords (guitar, piano...).
  final bool chords;

  /// Accept the right note in any octave (voices: men sing melodies an
  /// octave below women).
  final bool anyOctave;

  /// Semitones from the sounding note to the written one: transposing
  /// instruments read their parts higher (B♭ trumpet +2, E♭ alto sax +9).
  final int transposition;

  /// [part] moved by whole octaves so that most of it fits the range.
  Part fit(Part part) {
    final notes = [for (final e in part.events) ...e.midi]..sort();
    if (notes.isEmpty) return part;
    final median = notes[notes.length ~/ 2];
    final center = (low + high) ~/ 2;
    final octaves = ((center - median) / 12).round();
    if (octaves == 0) return part;
    return Part(
      name: part.name,
      kind: part.kind,
      program: part.program,
      stem: part.stem,
      events: [for (final e in part.events) e.transposed(12 * octaves)],
    );
  }
}

const instruments = [
  Instrument(name: 'Voz', icon: '🎤', low: 40, high: 81, anyOctave: true),
  Instrument(
    name: 'Violão',
    icon: '🎸',
    low: 40,
    high: 84,
    chords: true,
    stems: ['guitar'],
  ),
  Instrument(
    name: 'Guitarra',
    icon: '🎸',
    low: 40,
    high: 88,
    chords: true,
    stems: ['guitar'],
  ),
  Instrument(name: 'Ukulele', icon: '🪕', low: 60, high: 81, chords: true),
  Instrument(
    name: 'Piano / Teclado',
    icon: '🎹',
    low: 21,
    high: 108,
    chords: true,
    stems: ['piano', 'other'],
  ),
  Instrument(
    name: 'Contrabaixo',
    icon: '🎸',
    low: 28,
    high: 60,
    stems: ['bass'],
  ),
  Instrument(name: 'Violino', icon: '🎻', low: 55, high: 100),
  Instrument(
    name: 'Violoncelo',
    icon: '🎻',
    low: 36,
    high: 76,
    stems: ['vocals', 'bass'],
  ),
  Instrument(name: 'Flauta', icon: '🪈', low: 60, high: 96),
  Instrument(
    name: 'Saxofone alto (Mi♭)',
    icon: '🎷',
    low: 49,
    high: 81,
    transposition: 9,
  ),
  Instrument(
    name: 'Saxofone tenor (Si♭)',
    icon: '🎷',
    low: 44,
    high: 76,
    transposition: 14,
  ),
  Instrument(
    name: 'Trompete (Si♭)',
    icon: '🎺',
    low: 52,
    high: 82,
    transposition: 2,
  ),
  Instrument(
    name: 'Clarinete (Si♭)',
    icon: '🎶',
    low: 50,
    high: 91,
    transposition: 2,
  ),
  Instrument(
    name: 'Gaita / Escaleta',
    icon: '🎶',
    low: 53,
    high: 89,
    anyOctave: true,
  ),
];
