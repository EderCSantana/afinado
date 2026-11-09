import '../models/song.dart';
import 'chords.dart';

/// Songs that come with the app: exercises and public-domain melodies, so
/// there is something to practice right away.
final List<Song> builtinSongs = [
  _song(
    'Escala de Dó maior',
    bpm: 80,
    melody: '''
    C4 D4 E4 F4 G4 A4 B4 C5:2 B4 A4 G4 F4 E4 D4 C4:2''',
  ),
  _song(
    'Notas longas (afinação)',
    bpm: 60,
    melody: '''
    C4:4 E4:4 G4:4 C5:4 G4:4 E4:4 C4:4''',
  ),
  _song(
    'Brilha, brilha, estrelinha',
    bpm: 90,
    melody: '''
      C4 C4 G4 G4 A4 A4 G4:2 F4 F4 E4 E4 D4 D4 C4:2
      G4 G4 F4 F4 E4 E4 D4:2 G4 G4 F4 F4 E4 E4 D4:2
      C4 C4 G4 G4 A4 A4 G4:2 F4 F4 E4 E4 D4 D4 C4:2''',
    chords: '''
      C:4 F:2 C:2 F:2 C:2 G:2 C:2
      C:2 F:2 C:2 G:2 C:2 F:2 C:2 G:2
      C:4 F:2 C:2 F:2 C:2 G:2 C:2''',
  ),
  _song(
    'Ode à Alegria (Beethoven)',
    bpm: 100,
    melody: '''
      E4 E4 F4 G4 G4 F4 E4 D4 C4 C4 D4 E4 E4:1.5 D4:.5 D4:2
      E4 E4 F4 G4 G4 F4 E4 D4 C4 C4 D4 E4 D4:1.5 C4:.5 C4:2
      D4 D4 E4 C4 D4 E4:.5 F4:.5 E4 C4 D4 E4:.5 F4:.5 E4 D4 C4 D4 G3:2
      E4 E4 F4 G4 G4 F4 E4 D4 C4 C4 D4 E4 D4:1.5 C4:.5 C4:2''',
    chords: '''
      C:4 G:4 C:4 G:4 C:4 G:4 C:4 G:2 C:2
      G:4 C:4 G:8 C:4 G:4 C:4 G:2 C:2''',
  ),
  _song(
    'Frei Martinho (Frère Jacques)',
    bpm: 100,
    melody: '''
      C4 D4 E4 C4 C4 D4 E4 C4 E4 F4 G4:2 E4 F4 G4:2
      G4:.5 A4:.5 G4:.5 F4:.5 E4 C4 G4:.5 A4:.5 G4:.5 F4:.5 E4 C4
      C4 G3 C4:2 C4 G3 C4:2''',
  ),
  _song(
    'Acordes: C – Am – F – G',
    bpm: 80,
    chords: '''
    C:4 Am:4 F:4 G:4 C:4 Am:4 F:4 G:4 C:4''',
  ),
  _song(
    'Acordes: G – Em – C – D',
    bpm: 80,
    chords: '''
    G:4 Em:4 C:4 D:4 G:4 Em:4 C:4 D:4 G:4''',
  ),
  _song(
    'Acordes: Am – Dm – E7 – Am',
    bpm: 80,
    chords: '''
    Am:4 Dm:4 E7:4 Am:4 Dm:4 Am:4 E7:4 Am:4''',
  ),
];

Song _song(
  String title, {
  required double bpm,
  String? melody,
  String? chords,
}) {
  final beat = 60 / bpm;
  final parts = [
    if (melody != null)
      Part(
        name: 'Melodia',
        kind: PartKind.melody,
        events: _notes(melody, beat),
      ),
    if (chords != null)
      Part(
        name: 'Acordes',
        kind: PartKind.chords,
        events: _chords(chords, beat),
      ),
  ];
  final duration = parts
      .map((p) => p.events.last.end)
      .reduce((a, b) => a > b ? a : b);
  return Song(title: title, duration: duration + 0.5, parts: parts);
}

const _pitchClasses = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11};

/// "E4:1.5" → (64, 1.5 beats); the length defaults to one beat.
(String, double) _token(String token) {
  final colon = token.indexOf(':');
  if (colon < 0) return (token, 1);
  return (token.substring(0, colon), double.parse(token.substring(colon + 1)));
}

List<NoteEvent> _notes(String text, double beat) {
  final events = <NoteEvent>[];
  var time = 0.0;
  for (final token in text.split(RegExp(r'\s+')).where((t) => t.isNotEmpty)) {
    final (name, beats) = _token(token);
    final sharp = name.contains('#') ? 1 : 0;
    final octave = int.parse(name.substring(1 + sharp));
    final midi = (octave + 1) * 12 + _pitchClasses[name[0]]! + sharp;
    events.add(
      NoteEvent(start: time, duration: beats * beat * 0.95, midi: [midi]),
    );
    time += beats * beat;
  }
  return events;
}

const _qualities = {
  '': ChordQuality.major,
  'm': ChordQuality.minor,
  '7': ChordQuality.dominant7,
  'm7': ChordQuality.minor7,
  '7M': ChordQuality.major7,
};

List<NoteEvent> _chords(String text, double beat) {
  final events = <NoteEvent>[];
  var time = 0.0;
  for (final token in text.split(RegExp(r'\s+')).where((t) => t.isNotEmpty)) {
    final (name, beats) = _token(token);
    final sharp = name.length > 1 && name[1] == '#' ? 1 : 0;
    final chord = Chord(
      (_pitchClasses[name[0]]! + sharp) % 12,
      _qualities[name.substring(1 + sharp)]!,
    );
    final length = beats * beat;
    if (events.isNotEmpty && events.last.chord == chord) {
      // The same chord continues.
      final last = events.removeLast();
      events.add(
        NoteEvent(
          start: last.start,
          duration: last.duration + length,
          midi: last.midi,
          chord: chord,
        ),
      );
    } else {
      events.add(
        NoteEvent(
          start: time,
          duration: length * 0.98,
          midi: chord.voicing(),
          chord: chord,
        ),
      );
    }
    time += length;
  }
  return events;
}
