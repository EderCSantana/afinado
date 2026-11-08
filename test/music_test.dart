import 'dart:math' as math;
import 'dart:typed_data';

import 'package:afinado/game/judge.dart';
import 'package:afinado/models/instrument.dart';
import 'package:afinado/models/song.dart';
import 'package:afinado/music/audio_analysis.dart';
import 'package:afinado/music/chords.dart';
import 'package:afinado/music/midi_file.dart';
import 'package:afinado/music/pitch.dart';
import 'package:afinado/music/yin.dart';
import 'package:flutter_test/flutter_test.dart';

const rate = 22050;

/// [seconds] of a tone at [hz] with a few harmonics, like a real instrument.
List<double> tone(double hz, double seconds, {double amp = 0.4}) => [
  for (var i = 0; i < (seconds * rate).round(); i++)
    amp *
        (math.sin(2 * math.pi * hz * i / rate) +
            0.5 * math.sin(4 * math.pi * hz * i / rate) +
            0.25 * math.sin(6 * math.pi * hz * i / rate)) /
        1.75,
];

List<double> mix(List<List<double>> tones) => [
  for (var i = 0; i < tones.first.length; i++)
    tones.fold(0.0, (s, t) => s + t[i]) / tones.length,
];

void main() {
  test('names notes and measures cents', () {
    expect(noteName(60), 'Dó4');
    expect(noteName(69, NoteNaming.letters), 'A4');
    expect(midiToFrequency(69), 440);
    expect(frequencyToMidi(261.63), closeTo(60, 0.01));
    expect(centsFrom(60.2, 60), closeTo(20, 1e-9));
    expect(centsFrom(72.1, 60, anyOctave: true), closeTo(10, 1e-9));
    expect(centsFrom(72.1, 60), closeTo(1210, 1e-9));
  });

  test('YIN finds the pitch of voices and instruments', () {
    final yin = YinDetector(sampleRate: rate);
    for (final midi in [40, 52, 60, 69, 76, 88]) {
      final hz = midiToFrequency(midi);
      final reading = yin.detect(tone(hz, 0.1).sublist(0, yin.frameSize));
      expect(reading, isNotNull, reason: 'midi $midi');
      expect(
        centsFrom(frequencyToMidi(reading!.frequency), midi).abs(),
        lessThan(5),
        reason: 'midi $midi',
      );
    }
    // 30 cents sharp is measured as such.
    final sharp = yin.detect(
      tone(midiToFrequency(64.3), 0.1).sublist(0, yin.frameSize),
    )!;
    expect(centsFrom(frequencyToMidi(sharp.frequency), 64), closeTo(30, 3));
    // Silence and noise have no pitch.
    expect(yin.detect(List.filled(yin.frameSize, 0)), isNull);
    final random = math.Random(1);
    expect(
      yin.detect([
        for (var i = 0; i < yin.frameSize; i++) random.nextDouble() - 0.5,
      ]),
      isNull,
    );
  });

  test('recognizes chords and their tuning from the spectrum', () {
    List<double> chord(List<int> notes, {double cents = 0}) => mix([
      for (final n in notes) tone(midiToFrequency(n + cents / 100), 0.4),
    ]).sublist(0, 8192);

    expect(
      bestChord(Spectrum.of(chord([48, 52, 55]), rate).chroma())!.$1,
      const Chord(0, ChordQuality.major),
    );
    expect(
      bestChord(Spectrum.of(chord([57, 60, 64]), rate).chroma())!.$1,
      const Chord(9, ChordQuality.minor),
    );
    expect(
      bestChord(Spectrum.of(chord([43, 47, 50, 53]), rate).chroma())!.$1,
      const Chord(7, ChordQuality.dominant7),
    );
    expect(
      Spectrum.of(chord([48, 52, 55], cents: 20), rate).tuningCents(),
      closeTo(20, 6),
    );
    expect(const Chord(1, ChordQuality.minor).name(NoteNaming.solfege), 'Dó♯m');
  });

  test('reads a MIDI file with tempo changes and chords', () {
    // Format 1: tempo track + one piano track. 96 ticks per quarter note.
    List<int> track(List<int> events) => [
      ...'MTrk'.codeUnits,
      0, 0, 0, events.length + 4,
      ...events,
      0, 0xFF, 0x2F, 0, // end of track
    ];
    final bytes = Uint8List.fromList([
      ...'MThd'.codeUnits, 0, 0, 0, 6, 0, 1, 0, 2, 0, 96,
      // 120 bpm (500000 µs), then 60 bpm (1000000 µs) after one quarter.
      ...track([
        0,
        0xFF,
        0x51,
        3,
        0x07,
        0xA1,
        0x20,
        96,
        0xFF,
        0x51,
        3,
        0x0F,
        0x42,
        0x40,
      ]),
      ...track([
        0, 0xFF, 0x03, 5, ...'Piano'.codeUnits,
        0, 0xC0, 0, // program 0
        0, 0x90, 60, 100, // C4 on
        96, 0x80, 60, 0, // off after a quarter (0.5 s)
        0, 0x90, 64, 100, // E4 + G4 together (running status for G4)
        0, 67, 100,
        96, 64, 0, // note-on with velocity 0 = off (1 s at 60 bpm)
        0, 67, 0,
      ]),
    ]);
    final song = parseMidi(bytes, title: 'teste');
    expect(song.parts, hasLength(1));
    final part = song.parts.single;
    expect(part.name, 'Piano');
    expect(part.events, hasLength(2));
    expect(part.events[0].midi, [60]);
    expect(part.events[0].duration, closeTo(0.5, 1e-9));
    expect(part.events[1].midi, [64, 67]);
    expect(part.events[1].start, closeTo(0.5, 1e-9));
    expect(part.events[1].duration, closeTo(1.0, 1e-9));
    expect(song.duration, closeTo(1.5, 1e-9));
    expect(
      () => parseMidi(Uint8List.fromList([1, 2, 3]), title: 'x'),
      throwsA(isA<MidiFormatException>()),
    );
  });

  test('extracts a melody from audio', () {
    final samples = [
      ...tone(midiToFrequency(60), 0.5),
      ...List.filled(rate ~/ 10, 0.0),
      ...tone(midiToFrequency(64), 0.5),
      ...tone(midiToFrequency(67), 0.5),
    ];
    final part = extractMelody(samples, rate);
    expect([for (final e in part.events) e.midi.single], [60, 64, 67]);
    expect(part.events.first.start, closeTo(0, 0.08));
    expect(part.events.first.duration, closeTo(0.5, 0.1));
    expect(part.events[1].start, closeTo(0.6, 0.08));
  });

  test('extracts chords from audio', () {
    List<double> chord(List<int> notes) =>
        mix([for (final n in notes) tone(midiToFrequency(n), 2)]);
    final samples = [
      ...chord([48, 52, 55]),
      ...chord([45, 48, 52]),
      ...chord([43, 47, 50]),
    ];
    final part = extractChords(samples, rate);
    expect([for (final e in part.events) e.chord!.name()], ['C', 'Am', 'G']);
    expect(part.events[1].start, closeTo(2, 0.4));
  });

  test('judges notes: right, out of tune, wrong and in any octave', () {
    final part = Part(
      name: 'p',
      kind: PartKind.melody,
      events: const [
        NoteEvent(start: 0, duration: 1, midi: [60]),
        NoteEvent(start: 1, duration: 1, midi: [62]),
        NoteEvent(start: 2, duration: 1, midi: [64]),
        NoteEvent(start: 3, duration: 1, midi: [65]),
      ],
    );
    final judge = Judge(part, anyOctave: true);
    for (var t = 0.0; t < 4; t += 0.05) {
      final midi = switch (t) {
        < 1 => 60.05, // in tune
        < 2 => 62.35, // 35 cents sharp
        < 3 => 67.0, // wrong note
        _ => 77.02, // right note, an octave up
      };
      judge.listen(Hearing(time: t, midi: midi));
    }
    expect(
      [for (final r in judge.results) r.grade],
      [Grade.perfect, Grade.outOfTune, Grade.missed, Grade.perfect],
    );
    expect(judge.results[1].averageCents, closeTo(35, 1e-6));
    expect(Judge(part).eventAt(2.5), 2);
    expect(Judge(part).eventAt(5), isNull);
  });

  test('judges chords from the microphone spectrum', () {
    const c = Chord(0, ChordQuality.major);
    final part = Part(
      name: 'c',
      kind: PartKind.chords,
      events: [NoteEvent(start: 0, duration: 1, midi: c.voicing(), chord: c)],
    );
    final judge = Judge(part);
    final right = Spectrum.of(
      mix([
        for (final n in [48, 52, 55]) tone(midiToFrequency(n), 0.4),
      ]).sublist(0, 8192),
      rate,
    );
    final wrong = Spectrum.of(
      mix([
        for (final n in [50, 53, 57]) tone(midiToFrequency(n), 0.4),
      ]).sublist(0, 8192),
      rate,
    );
    expect(
      judge.listen(
        Hearing(
          time: 0.5,
          chroma: right.chroma(),
          tuningCents: right.tuningCents(),
        ),
      ),
      isNotNull,
    );
    expect(judge.listen(Hearing(time: 0.6, chroma: wrong.chroma())), isNull);
  });

  test('moves a part into the instrument range', () {
    final part = Part(
      name: 'p',
      kind: PartKind.melody,
      events: const [
        NoteEvent(start: 0, duration: 1, midi: [84]),
        NoteEvent(start: 1, duration: 1, midi: [88]),
      ],
    );
    final bass = instruments.firstWhere((i) => i.name == 'Contrabaixo');
    expect(bass.fit(part).events.map((e) => e.midi.single), [36, 40]);
  });
}
