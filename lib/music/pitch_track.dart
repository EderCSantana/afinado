import 'chords.dart';

/// One pitch heard at time [t] (seconds), as a fractional MIDI note.
typedef PitchPoint = ({double t, double midi});

/// A chord heard from [start] to [end] (seconds).
class ChordSpan {
  ChordSpan(this.chord, this.start, this.end);

  final Chord chord;
  final double start;
  double end;

  double get duration => end - start;
}

/// The history drawn by the pitch monitor: every pitch heard and the chords
/// recognized, for the last [keepSeconds].
///
/// Pitches go through a 3-point median filter: a one-off octave error of
/// the detector vanishes, a real note change shows one reading (~50 ms)
/// later. Chords become spans, extended while the same
/// chord keeps coming and closed by silence or another chord.
class PitchTrack {
  PitchTrack({this.keepSeconds = 120});

  final double keepSeconds;
  final List<PitchPoint> points = [];
  final List<ChordSpan> chords = [];
  final List<PitchPoint> _raw = [];

  /// Two readings further apart than this are not joined by a line.
  static const gapSeconds = 0.15;

  /// A chord coming back within this time continues its span.
  static const chordHoldSeconds = 0.4;

  /// Spans shorter than this are dropped when closed (passing noise).
  static const minChordSeconds = 0.25;

  void addPitch(double t, double midi) {
    if (_raw.isNotEmpty && t - _raw.last.t > gapSeconds) _raw.clear();
    _raw.add((t: t, midi: midi));
    if (_raw.length > 3) _raw.removeAt(0);
    final sorted = [for (final p in _raw) p.midi]..sort();
    points.add((t: t, midi: sorted[sorted.length ~/ 2]));
    _trim(t);
  }

  /// The chord heard at [t], or null for none.
  void addChord(double t, Chord? chord) {
    final last = chords.isEmpty ? null : chords.last;
    if (chord == null) {
      _closeIfShort();
      return;
    }
    if (last != null && last.chord == chord && t - last.end <= chordHoldSeconds) {
      last.end = t;
    } else {
      _closeIfShort();
      chords.add(ChordSpan(chord, t, t));
    }
    _trim(t);
  }

  void _closeIfShort() {
    if (chords.isNotEmpty && chords.last.duration < minChordSeconds) {
      chords.removeLast();
    }
  }

  void _trim(double now) {
    final from = now - keepSeconds;
    points.removeWhere((p) => p.t < from);
    chords.removeWhere((c) => c.end < from);
  }

  /// Pitches between [from] and [to].
  Iterable<PitchPoint> between(double from, double to) =>
      points.where((p) => p.t >= from && p.t <= to);

  /// Chord spans that overlap [from]..[to].
  Iterable<ChordSpan> chordsBetween(double from, double to) =>
      chords.where((c) => c.end >= from && c.start <= to);

  /// The notes to show (low and high MIDI note, inclusive) for the pitches
  /// between [from] and [to]: all of them plus a margin, at least
  /// [minSpan] semitones, [fallback] when nothing was heard.
  (int, int) rangeFor(
    double from,
    double to, {
    int minSpan = 14,
    int margin = 2,
    (int, int) fallback = (55, 72),
  }) {
    final heard = [for (final p in between(from, to)) p.midi];
    if (heard.isEmpty) return fallback;
    heard.sort();
    // Ignore the extreme 2% (stray readings) on each side.
    final cut = heard.length ~/ 50;
    var low = heard[cut].floor() - margin;
    var high = heard[heard.length - 1 - cut].ceil() + margin;
    if (high - low < minSpan) {
      final extra = minSpan - (high - low);
      low -= extra ~/ 2;
      high += extra - extra ~/ 2;
    }
    return (low, high);
  }

  void clear() {
    points.clear();
    chords.clear();
    _raw.clear();
  }
}

/// Smooths chroma frames and names the chord they suggest, like the tuner.
class ChordFollower {
  List<double> chroma = List.filled(12, 0);

  /// The chord of the smoothed [frame], or null when nothing clear sounds.
  /// [loud] says whether the frame has real sound (not just noise).
  Chord? update(List<double> frame, {required bool loud}) {
    chroma = [
      for (var i = 0; i < 12; i++) chroma[i] * 0.6 + (loud ? frame[i] : 0) * 0.4,
    ];
    if (!loud) return null;
    final best = bestChord(chroma);
    return best != null && best.$2 >= 0.6 ? best.$1 : null;
  }
}
