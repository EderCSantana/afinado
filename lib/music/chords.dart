import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fftea/fftea.dart';

import 'pitch.dart';

/// Chord qualities recognized, with their intervals from the root.
enum ChordQuality {
  major('', [0, 4, 7]),
  minor('m', [0, 3, 7]),
  dominant7('7', [0, 4, 7, 10]),
  minor7('m7', [0, 3, 7, 10]),
  major7('7M', [0, 4, 7, 11]),
  sus4('sus4', [0, 5, 7]),
  diminished('°', [0, 3, 6]),
  power('5', [0, 7]);

  const ChordQuality(this.suffix, this.intervals);
  final String suffix;
  final List<int> intervals;
}

/// A chord: root pitch class (0 = C) and quality.
class Chord {
  const Chord(this.root, this.quality);

  final int root;
  final ChordQuality quality;

  Set<int> get pitchClasses => {
    for (final i in quality.intervals) (root + i) % 12,
  };

  /// Notes to show for the chord, from [baseMidi] up (root position).
  List<int> voicing([int baseMidi = 48]) {
    final rootMidi = baseMidi + (root - baseMidi % 12 + 12) % 12;
    return [for (final i in quality.intervals) rootMidi + i];
  }

  /// Chord symbol, e.g. "Am", "G7", "Dó♯m".
  String name([NoteNaming naming = NoteNaming.letters]) =>
      '${pitchClassName(root, naming)}${quality.suffix}';

  @override
  bool operator ==(Object other) =>
      other is Chord && other.root == root && other.quality == quality;

  @override
  int get hashCode => Object.hash(root, quality);

  @override
  String toString() => name();
}

/// Spectrum of a frame, with the frequency of each bin.
class Spectrum {
  Spectrum(this.magnitudes, this.binHz);

  final Float64List magnitudes;
  final double binHz;

  /// Hann-windowed magnitude spectrum of [frame] (length a power of two
  /// gives the fastest FFT).
  factory Spectrum.of(List<double> frame, int sampleRate) {
    final n = frame.length;
    final windowed = Float64List(n);
    for (var i = 0; i < n; i++) {
      windowed[i] =
          frame[i] * (0.5 - 0.5 * math.cos(2 * math.pi * i / (n - 1)));
    }
    final fft = FFT(n).realFft(windowed).discardConjugates();
    return Spectrum(fft.magnitudes(), sampleRate / n);
  }

  /// Energy per pitch class (12 values summing to 1, or all zero for
  /// silence), from bins between [minHz] and [maxHz]. Peaks are weighted by
  /// how close they are to an equal-tempered note.
  List<double> chroma({double minHz = 70, double maxHz = 2000}) {
    final chroma = List<double>.filled(12, 0);
    final first = math.max(1, (minHz / binHz).floor());
    final last = math.min(magnitudes.length - 2, (maxHz / binHz).ceil());
    for (var k = first; k <= last; k++) {
      final m = magnitudes[k];
      // Only local maxima (spectral peaks), to ignore leakage.
      if (m <= magnitudes[k - 1] || m < magnitudes[k + 1]) continue;
      final midi = frequencyToMidi(_peakFrequency(k));
      final distance = (midi - midi.round()).abs(); // 0..0.5 semitone
      chroma[midi.round() % 12] += m * m * (1 - distance);
    }
    final total = chroma.fold(0.0, (a, b) => a + b);
    return total == 0 ? chroma : [for (final c in chroma) c / total];
  }

  /// Average deviation in cents of the strongest peaks from equal
  /// temperament: positive means sharp. Null if there are no clear peaks.
  double? tuningCents({double minHz = 70, double maxHz = 2000, int peaks = 6}) {
    final found = <(double, double)>[]; // (magnitude, cents)
    final first = math.max(1, (minHz / binHz).floor());
    final last = math.min(magnitudes.length - 2, (maxHz / binHz).ceil());
    for (var k = first; k <= last; k++) {
      final m = magnitudes[k];
      if (m <= magnitudes[k - 1] || m < magnitudes[k + 1]) continue;
      found.add((m, centsFromNearest(frequencyToMidi(_peakFrequency(k)))));
    }
    if (found.isEmpty) return null;
    found.sort((a, b) => b.$1.compareTo(a.$1));
    final top = found.take(peaks).where((p) => p.$1 > found.first.$1 * 0.2);
    var sum = 0.0, weight = 0.0;
    for (final (m, cents) in top) {
      sum += m * cents;
      weight += m;
    }
    return sum / weight;
  }

  /// Frequency of the peak at bin [k], refined by parabolic interpolation.
  double _peakFrequency(int k) {
    final a = magnitudes[k - 1], b = magnitudes[k], c = magnitudes[k + 1];
    final denom = a - 2 * b + c;
    final offset = denom == 0 ? 0.0 : 0.5 * (a - c) / denom;
    return (k + offset) * binHz;
  }
}

/// All chords recognized, for matching.
final List<Chord> allChords = [
  for (final quality in ChordQuality.values)
    for (var root = 0; root < 12; root++) Chord(root, quality),
];

/// How well [chroma] matches [chord], 0..1: the share of energy on the
/// chord's notes, penalized for missing chord notes.
double chordMatch(List<double> chroma, Chord chord) {
  final notes = chord.pitchClasses;
  var inside = 0.0;
  var missing = 0;
  for (final pc in notes) {
    inside += chroma[pc];
    if (chroma[pc] < 0.04) missing++;
  }
  return inside * (1 - 0.25 * missing);
}

/// The chord that best explains [chroma] and its match score; null for
/// silence. Simpler chords win ties (a triad over its seventh chord).
(Chord, double)? bestChord(List<double> chroma, {Iterable<Chord>? candidates}) {
  if (chroma.every((c) => c == 0)) return null;
  Chord? best;
  var bestScore = -1.0;
  for (final chord in candidates ?? allChords) {
    // Each extra note must earn its place.
    final score =
        chordMatch(chroma, chord) - 0.03 * chord.quality.intervals.length;
    if (score > bestScore + 1e-9) {
      best = chord;
      bestScore = score;
    }
  }
  return (best!, chordMatch(chroma, best));
}
