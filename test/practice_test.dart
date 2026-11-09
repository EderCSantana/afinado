import 'package:afinado/game/judge.dart';
import 'package:afinado/game/practice.dart';
import 'package:afinado/models/song.dart';
import 'package:afinado/music/builtin_songs.dart';
import 'package:afinado/music/chords.dart';
import 'package:flutter_test/flutter_test.dart';

const _melody = Part(
  name: 'Melodia',
  kind: PartKind.melody,
  events: [
    NoteEvent(start: 0, duration: 1, midi: [60]),
    NoteEvent(start: 1, duration: 1, midi: [62]),
    NoteEvent(start: 2, duration: 1, midi: [62]),
  ],
);

/// Feeds [midi] to [coach] for [seconds], 20 readings per second, from
/// [from]; returns the time after.
double _play(PracticeCoach coach, double? midi, double from, double seconds) {
  var t = from;
  for (; t < from + seconds; t += 0.05) {
    coach.hear(time: t, midi: midi);
  }
  return t;
}

void main() {
  test('waits on each note until it is held, then moves on', () {
    final coach = PracticeCoach(_melody);
    var t = _play(coach, null, 0, 2); // Silence: no clock, still on note 1.
    expect(coach.index, 0);
    t = _play(coach, 60.05, t, 0.4); // C, 5 cents sharp.
    expect(coach.index, 1);
    expect(coach.results[0].cents, closeTo(5, 0.5));
    expect(coach.results[0].grade, Grade.perfect);
    expect(coach.results[0].seconds, greaterThan(2));
  });

  test('says which way to go on a wrong note and counts the attempt', () {
    final coach = PracticeCoach(_melody);
    late PracticeFeedback f;
    for (var t = 0.0; t < 0.5; t += 0.05) {
      f = coach.hear(time: t, midi: 64); // E instead of C.
    }
    expect(f.heard, Heard.wrong);
    expect(f.semitonesToGo, -4);
    expect(coach.results[0].wrongTries, 1);
    expect(coach.results[0].wrongNotes, {64: 1});
    expect(coach.index, 0);
  });

  test('a repeated note must be played again', () {
    final coach = PracticeCoach(_melody)..goTo(1);
    var t = _play(coach, 62, 0, 0.4);
    expect(coach.index, 2);
    // Still ringing: not accepted as the second D.
    final f = coach.hear(time: t, midi: 62);
    expect(f.heard, Heard.playAgain);
    t = _play(coach, 62, t, 0.5);
    expect(coach.index, 2);
    t = _play(coach, null, t, 0.1); // Let go...
    _play(coach, 62, t, 0.4); // ...and play it again.
    expect(coach.finished, isTrue);
  });

  test('strict tuning only accepts notes within 25 cents', () {
    final coach = PracticeCoach(_melody, strictCents: 25);
    var t = _play(coach, 60.35, 0, 1);
    expect(coach.index, 0);
    expect(coach.hear(time: t, midi: 60.35).heard, Heard.outOfTune);
    _play(coach, 60.1, t, 0.4);
    expect(coach.index, 1);
  });

  test('loops a passage', () {
    final coach = PracticeCoach(_melody)..setLoop(0, 1);
    var t = _play(coach, 60, 0, 0.4);
    t = _play(coach, 62, t, 0.4);
    expect(coach.index, 0);
    expect(coach.laps, 1);
  });

  test('recognizes chords from the chroma', () {
    const part = Part(
      name: 'Acordes',
      kind: PartKind.chords,
      events: [
        NoteEvent(
          start: 0,
          duration: 2,
          midi: [57, 60, 64],
          chord: Chord(9, ChordQuality.minor),
        ),
        NoteEvent(
          start: 2,
          duration: 2,
          midi: [55, 59, 62],
          chord: Chord(7, ChordQuality.major),
        ),
      ],
    );
    final coach = PracticeCoach(part);
    List<double> chroma(Set<int> classes) => [
      for (var pc = 0; pc < 12; pc++) classes.contains(pc) ? 1 / 3 : 0,
    ];
    late PracticeFeedback f;
    for (var t = 0.0; t < 0.5; t += 0.05) {
      f = coach.hear(time: t, chroma: chroma({0, 4, 7})); // C, not Am.
    }
    expect(f.heard, Heard.wrong);
    expect(f.heardChord, const Chord(0, ChordQuality.major));
    for (var t = 0.5; t < 1.1; t += 0.05) {
      coach.hear(time: t, chroma: chroma({9, 0, 4}), tuningCents: -3);
    }
    expect(coach.index, 1);
    expect(coach.results[0].cents, -3);
  });

  test('built-in songs are well formed', () {
    expect(builtinSongs, isNotEmpty);
    for (final song in builtinSongs) {
      expect(song.parts, isNotEmpty, reason: song.title);
      for (final part in song.parts) {
        for (var i = 1; i < part.events.length; i++) {
          expect(
            part.events[i].start,
            greaterThanOrEqualTo(part.events[i - 1].end - 1e-9),
            reason: '${song.title} ${part.name} $i',
          );
        }
      }
    }
    final ode = builtinSongs.firstWhere((s) => s.title.startsWith('Ode'));
    expect(ode.parts.first.events.take(4).map((e) => e.midi.single), [
      64,
      64,
      65,
      67,
    ]);
    // Melody and chords end together.
    expect(
      ode.parts[0].events.last.start,
      closeTo(ode.parts[1].events.last.start, 0.01),
    );
  });
}
