import 'package:afinado/analysis/stem_analyzer.dart';
import 'package:afinado/analysis/stems_to_song.dart';
import 'package:afinado/models/song.dart';
import 'package:afinado/music/chords.dart';
import 'package:flutter_test/flutter_test.dart';

StemNote _n(double start, double end, int midi, [double amplitude = 0.8]) =>
    (start: start, end: end, midi: midi, amplitude: amplitude);

void main() {
  test('reads the analyzer output', () {
    final analysis = StemAnalysis.fromJson({
      'duration': 10.0,
      'stems': {'vocals': 'vocals.wav'},
      'parts': [
        {
          'stem': 'vocals',
          'notes': [
            [0.0, 0.5, 60, 0.9],
          ],
        },
      ],
    }, 'dir');
    expect(analysis.parts.single.notes.single.midi, 60);
    expect(analysis.stems['vocals'], endsWith('vocals.wav'));
  });

  test('one part per instrument, chords from the harmony', () {
    // Guitar strums C (0-4 s) then G (4-8 s); the singer sings E D C D E.
    final guitar = [
      for (var t = 0.0; t < 4; t += 1) ...[
        _n(t, t + 0.9, 48),
        _n(t + 0.01, t + 0.9, 52),
        _n(t + 0.02, t + 0.9, 55),
      ],
      for (var t = 4.0; t < 8; t += 1) ...[
        _n(t, t + 0.9, 43),
        _n(t + 0.01, t + 0.9, 47),
        _n(t + 0.02, t + 0.9, 50),
      ],
    ];
    final vocals = [
      for (final (i, m) in [64, 62, 60, 62, 64].indexed)
        _n(i * 1.0, i * 1.0 + 0.8, m),
    ];
    final parts = partsFromStems(
      StemAnalysis(
        duration: 8,
        stems: const {},
        parts: [StemPart('vocals', vocals), StemPart('guitar', guitar)],
      ),
    );
    expect(parts.map((p) => p.name), [
      'Voz',
      'Guitarra / violão',
      'Acordes',
    ]);
    expect(parts[0].stem, 'vocals');
    expect(parts[0].events.map((e) => e.midi.single), [64, 62, 60, 62, 64]);
    // Strums grouped into one event each.
    expect(parts[1].events, hasLength(8));
    expect(parts[1].events.first.midi, [48, 52, 55]);
    final chords = parts[2].events;
    expect(parts[2].kind, PartKind.chords);
    expect(chords.map((e) => e.chord), const [
      Chord(0, ChordQuality.major),
      Chord(7, ChordQuality.major),
    ]);
    expect(chords.first.start, 0);
    expect(chords.last.start, closeTo(4, 0.5));
  });

  test('quiet notes are left out of polyphonic parts', () {
    final parts = partsFromStems(
      StemAnalysis(
        duration: 4,
        stems: const {},
        parts: [
          StemPart('piano', [
            for (var i = 0; i < 6; i++) _n(i * 0.5, i * 0.5 + 0.4, 60 + i),
            _n(0.2, 0.3, 90, 0.1),
          ]),
        ],
      ),
    );
    final piano = parts.firstWhere((p) => p.stem == 'piano');
    expect(piano.events.expand((e) => e.midi), isNot(contains(90)));
  });
}
