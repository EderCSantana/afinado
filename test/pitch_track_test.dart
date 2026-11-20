import 'dart:ui' as ui;

import 'package:afinado/music/chords.dart';
import 'package:afinado/music/pitch.dart';
import 'package:afinado/music/pitch_track.dart';
import 'package:afinado/ui/monitor_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const c = Chord(0, ChordQuality.major);
  const am = Chord(9, ChordQuality.minor);

  test('a stray octave error is filtered out', () {
    final track = PitchTrack();
    for (final (i, midi) in [60.0, 60.1, 72.0, 60.0, 59.9].indexed) {
      track.addPitch(i * 0.05, midi);
    }
    expect(track.points, hasLength(5));
    expect(track.points.every((p) => (p.midi - 60).abs() < 0.2), isTrue);
  });

  test('a real note change follows one reading later', () {
    final track = PitchTrack();
    for (final (i, midi) in [60.0, 60.0, 62.0, 62.0, 62.0].indexed) {
      track.addPitch(i * 0.05, midi);
    }
    expect([for (final p in track.points) p.midi], [60, 60, 60, 62, 62]);
  });

  test('median of three while the note holds', () {
    final track = PitchTrack()
      ..addPitch(0, 60.0)
      ..addPitch(0.05, 60.4)
      ..addPitch(0.1, 60.1);
    expect(track.points.last.midi, 60.1);
  });

  test('chords become spans; short ones are dropped', () {
    final track = PitchTrack();
    for (var i = 0; i <= 20; i++) {
      track.addChord(i * 0.05, c);
    }
    track.addChord(1.05, null);
    // A flicker of Am.
    track
      ..addChord(1.1, am)
      ..addChord(1.15, null);
    // C again, after a gap longer than the hold.
    for (var i = 0; i <= 10; i++) {
      track.addChord(2 + i * 0.05, c);
    }
    expect(track.chords.map((s) => s.chord), [c, c]);
    expect(track.chords.first.duration, closeTo(1.0, 0.01));
  });

  test('the same chord continues across a short break', () {
    final track = PitchTrack()
      ..addChord(0, am)
      ..addChord(0.3, am)
      ..addChord(0.6, am);
    expect(track.chords, hasLength(1));
    expect(track.chords.single.end, 0.6);
  });

  test('range follows the notes heard, with a minimum span', () {
    final track = PitchTrack();
    expect(track.rangeFor(0, 10), (55, 72));
    for (var i = 0; i < 20; i++) {
      track.addPitch(i * 0.1, 64 + (i % 3) * 0.1);
    }
    final (low, high) = track.rangeFor(0, 10);
    expect(high - low, 14);
    expect(low, lessThan(64));
    expect(high, greaterThan(65));
    // A wide melody widens it.
    track
      ..addPitch(3, 48)
      ..addPitch(3.2, 84);
    final wide = track.rangeFor(0, 10, minSpan: 12);
    expect(wide.$1, lessThanOrEqualTo(46));
    expect(wide.$2, greaterThanOrEqualTo(86));
  });

  test('old history is dropped', () {
    final track = PitchTrack(keepSeconds: 5)
      ..addPitch(0, 60)
      ..addChord(0, c)
      ..addChord(0.5, c)
      ..addPitch(10, 62);
    expect(track.points.map((p) => p.t), [10]);
    track.addChord(10, am);
    expect(track.chords.map((s) => s.chord), [am]);
  });

  test('chord follower names a clean C major chroma', () {
    final follower = ChordFollower();
    final frame = List<double>.filled(12, 0)
      ..[0] = 1
      ..[4] = 0.8
      ..[7] = 0.9;
    Chord? chord;
    for (var i = 0; i < 5; i++) {
      chord = follower.update(frame, loud: true);
    }
    expect(chord, c);
    expect(follower.update(frame, loud: false), isNull);
  });

  test('note labels carry the octave', () {
    expect(noteLabel(69, NoteNaming.letters), 'A4');
    expect(noteLabel(60, NoteNaming.letters), 'C4');
  });

  test('the chart paints a sung phrase with chords', () {
    final track = PitchTrack();
    for (var i = 0; i < 200; i++) {
      final t = i * 0.05;
      if (i % 50 > 45) continue; // breaths
      track.addPitch(t, 60 + (i ~/ 50) * 2 + 0.2 * (i % 7) / 7);
      track.addChord(t, i < 100 ? c : am);
    }
    final painter = MonitorPainter(
      track: track,
      end: 10,
      window: 10,
      low: 55,
      high: 72,
      label: (m) => noteLabel(m, NoteNaming.letters),
      chordLabel: (chord) => chord.name(),
      colors: ColorScheme.fromSeed(seedColor: Colors.teal),
      text: Typography.material2021().black,
    );
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), const Size(900, 420));
    expect(recorder.endRecording(), isNotNull);
    expect(track.chordsBetween(0, 10).map((s) => s.chord), [c, am]);
  });
}
