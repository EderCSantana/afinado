import 'dart:math' as math;

import '../models/song.dart';
import 'chords.dart';
import 'pitch.dart';
import 'yin.dart';

/// Finds the main melody of mono [samples]: the pitch of each frame, joined
/// into notes. Works best when one voice or instrument stands out (a solo, a
/// cappella, a clear lead); in a dense mix it follows whatever is loudest.
Part extractMelody(
  List<double> samples,
  int sampleRate, {
  double minNote = 0.12,
}) {
  final yin = YinDetector(
    sampleRate: sampleRate,
    minFrequency: 70,
    maxFrequency: 1200,
  );
  final frameSize = yin.frameSize;
  final hop = (sampleRate * 0.02).round(); // 20 ms
  final frameSeconds = hop / sampleRate;

  // Pitch per frame (fractional MIDI), null where there is none.
  final pitches = <double?>[];
  for (var start = 0; start + frameSize <= samples.length; start += hop) {
    final reading = yin.detect(samples.sublist(start, start + frameSize));
    pitches.add(
      reading != null && reading.confidence > 0.75
          ? frequencyToMidi(reading.frequency)
          : null,
    );
  }

  final smooth = _medianFilter(pitches, 5);
  final events = <NoteEvent>[];
  int? startFrame;
  final current = <double>[];

  void close(int endFrame) {
    if (startFrame == null) return;
    final duration = (endFrame - startFrame!) * frameSeconds;
    if (duration >= minNote) {
      final sorted = [...current]..sort();
      events.add(
        NoteEvent(
          // The frame covers the window, centered on its middle.
          start: startFrame! * frameSeconds + frameSize / sampleRate / 2,
          duration: duration,
          midi: [sorted[sorted.length ~/ 2].round()],
        ),
      );
    }
    startFrame = null;
    current.clear();
  }

  for (var i = 0; i < smooth.length; i++) {
    final p = smooth[i];
    if (p == null) {
      close(i);
      continue;
    }
    if (startFrame != null) {
      final sorted = [...current]..sort();
      // A jump of more than ~half a semitone from the note so far starts a new note.
      if ((p - sorted[sorted.length ~/ 2]).abs() > 0.6) close(i);
    }
    startFrame ??= i;
    current.add(p);
  }
  close(smooth.length);

  return Part(
    name: 'Melodia (do áudio)',
    kind: PartKind.melody,
    events: _mergeRepeats(events),
  );
}

/// Finds the chords of mono [samples], one per [step] seconds at most.
Part extractChords(List<double> samples, int sampleRate, {double step = 0.5}) {
  const frameSize = 8192; // ~0.37 s at 22 kHz: enough resolution for bass notes
  final hop = (sampleRate * step / 2).round();
  final frames = <(double, Chord?)>[];
  var maxRms = 0.0;
  final rmsList = <double>[];
  for (var start = 0; start + frameSize <= samples.length; start += hop) {
    final frame = samples.sublist(start, start + frameSize);
    var energy = 0.0;
    for (final s in frame) {
      energy += s * s;
    }
    final rms = math.sqrt(energy / frameSize);
    rmsList.add(rms);
    maxRms = math.max(maxRms, rms);
    final best = bestChord(
      Spectrum.of(frame, sampleRate).chroma(minHz: 60, maxHz: 1500),
    );
    frames.add((
      (start + frameSize / 2) / sampleRate,
      best != null && best.$2 > 0.45 ? best.$1 : null,
    ));
  }
  for (var i = 0; i < frames.length; i++) {
    if (rmsList[i] < maxRms * 0.05) frames[i] = (frames[i].$1, null);
  }

  // Majority vote over 3 frames, then join equal neighbours.
  final voted = <Chord?>[
    for (var i = 0; i < frames.length; i++)
      _majority([
        for (var j = i - 1; j <= i + 1; j++)
          if (j >= 0 && j < frames.length) frames[j].$2,
      ]),
  ];
  final events = <NoteEvent>[];
  final hopSeconds = hop / sampleRate;
  for (var i = 0; i < voted.length;) {
    var j = i + 1;
    while (j < voted.length && voted[j] == voted[i]) {
      j++;
    }
    final chord = voted[i];
    final duration = (j - i) * hopSeconds;
    if (chord != null && duration >= step) {
      events.add(
        NoteEvent(
          start: frames[i].$1 - hopSeconds / 2,
          duration: duration,
          midi: chord.voicing(),
          chord: chord,
        ),
      );
    }
    i = j;
  }
  return Part(
    name: 'Acordes (do áudio)',
    kind: PartKind.chords,
    events: events,
  );
}

Chord? _majority(List<Chord?> values) {
  final counts = <Chord?, int>{};
  for (final v in values) {
    counts[v] = (counts[v] ?? 0) + 1;
  }
  final best = counts.entries.reduce((a, b) => b.value > a.value ? b : a);
  return best.value * 2 > values.length ? best.key : values[values.length ~/ 2];
}

List<double?> _medianFilter(List<double?> values, int width) {
  final half = width ~/ 2;
  return [
    for (var i = 0; i < values.length; i++)
      if (values[i] == null)
        null
      else
        () {
          final window = [
            for (
              var j = math.max(0, i - half);
              j <= math.min(values.length - 1, i + half);
              j++
            )
              ?values[j],
          ]..sort();
          return window[window.length ~/ 2];
        }(),
  ];
}

/// Joins a note with the next one when it is the same pitch with almost no
/// gap (a vibrato or a short dropout split it).
List<NoteEvent> _mergeRepeats(List<NoteEvent> events) {
  final merged = <NoteEvent>[];
  for (final e in events) {
    final last = merged.isEmpty ? null : merged.last;
    if (last != null &&
        last.midi.first == e.midi.first &&
        e.start - last.end < 0.06) {
      merged[merged.length - 1] = NoteEvent(
        start: last.start,
        duration: e.end - last.start,
        midi: last.midi,
      );
    } else {
      merged.add(e);
    }
  }
  return merged;
}
