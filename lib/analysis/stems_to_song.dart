import '../models/song.dart';
import '../music/chords.dart';
import 'stem_analyzer.dart';

/// Names of the instruments Demucs separates.
const stemNames = {
  'vocals': 'Voz',
  'bass': 'Baixo',
  'guitar': 'Guitarra / violão',
  'piano': 'Piano',
  'other': 'Outros (teclados, cordas, sopros…)',
};

/// Harmony instruments, for working out the chords.
const _harmonic = {'guitar', 'piano', 'other'};

/// Turns the transcribed instruments into parts to play: one per
/// instrument plus the song's chords.
List<Part> partsFromStems(StemAnalysis analysis) {
  final parts = <Part>[];
  for (final stem in stemNames.keys) {
    final found = analysis.parts.where((p) => p.stem == stem);
    if (found.isEmpty) continue;
    final notes = found.first.notes;
    final events = switch (stem) {
      'vocals' => _single(notes),
      // Repeated bass notes are real: only join pieces that touch.
      'bass' => _single(notes, mergeGap: 0.02),
      _ => _grouped(notes),
    };
    if (events.length < 4) continue;
    parts.add(
      Part(
        name: stemNames[stem]!,
        kind: PartKind.melody,
        events: events,
        stem: stem,
      ),
    );
  }
  final chords = chordsFromNotes([
    for (final p in analysis.parts)
      if (_harmonic.contains(p.stem)) ...p.notes,
    // The bass helps find the root, with less weight.
    for (final p in analysis.parts)
      if (p.stem == 'bass')
        for (final n in p.notes)
          (
            start: n.start,
            end: n.end,
            midi: n.midi,
            amplitude: n.amplitude * 0.5,
          ),
  ]);
  if (chords.length >= 2) {
    parts.add(Part(name: 'Acordes', kind: PartKind.chords, events: chords));
  }
  return parts;
}

/// One note at a time. Basic Pitch often splits a held note in pieces and
/// adds short octave slips: pieces of the same note closer than [mergeGap]
/// are joined, and short notes an octave away from both neighbors dropped.
List<NoteEvent> _single(List<StemNote> notes, {double mergeGap = 0.12}) {
  final kept = <StemNote>[];
  for (var i = 0; i < notes.length; i++) {
    final n = notes[i];
    if (n.end - n.start < 0.15 && i > 0 && i + 1 < notes.length) {
      final a = notes[i - 1].midi, b = notes[i + 1].midi;
      if ((n.midi - a).abs() == 12 && (n.midi - b).abs() == 12) continue;
    }
    final last = kept.isEmpty ? null : kept.last;
    if (last != null && last.midi == n.midi && n.start - last.end < mergeGap) {
      kept[kept.length - 1] = (
        start: last.start,
        end: n.end,
        midi: n.midi,
        amplitude: last.amplitude > n.amplitude ? last.amplitude : n.amplitude,
      );
    } else {
      kept.add(n);
    }
  }
  return [
    for (final n in kept)
      if (n.end - n.start >= 0.1)
        NoteEvent(start: n.start, duration: n.end - n.start, midi: [n.midi]),
  ];
}

/// Notes starting together (within 60 ms) become one event; quiet notes
/// are left out.
List<NoteEvent> _grouped(List<StemNote> notes) {
  final loud = notes.where((n) => n.amplitude >= 0.3).toList()
    ..sort((a, b) => a.start.compareTo(b.start));
  final groups = <List<StemNote>>[];
  for (final n in loud) {
    if (groups.isNotEmpty && n.start - groups.last.first.start < 0.06) {
      groups.last.add(n);
    } else {
      groups.add([n]);
    }
  }
  final events = <NoteEvent>[];
  for (final (i, g) in groups.indexed) {
    final start = g.first.start;
    var end = g.map((n) => n.end).reduce((a, b) => a > b ? a : b);
    if (i + 1 < groups.length && groups[i + 1].first.start < end) {
      end = groups[i + 1].first.start;
    }
    if (end - start < 0.06) continue;
    final midi = {for (final n in g) n.midi}.toList()..sort();
    events.add(NoteEvent(start: start, duration: end - start, midi: midi));
  }
  return events;
}

/// Chord qualities proposed for songs: the common ones, so noise does not
/// turn into exotic chords.
final _candidates = [
  for (final q in [
    ChordQuality.major,
    ChordQuality.minor,
    ChordQuality.dominant7,
    ChordQuality.minor7,
  ])
    for (var root = 0; root < 12; root++) Chord(root, q),
];

/// Chords over time from the notes of the harmony instruments: the notes
/// sounding in each half second, matched against chord shapes, smoothed and
/// joined.
List<NoteEvent> chordsFromNotes(List<StemNote> notes, {double step = 0.5}) {
  if (notes.isEmpty) return const [];
  final end = notes.map((n) => n.end).reduce((a, b) => a > b ? a : b);
  final windows = (end / step).ceil();
  final chroma = List.generate(windows, (_) => List<double>.filled(12, 0));
  for (final n in notes) {
    final first = (n.start / step).floor();
    final last = ((n.end - 1e-6) / step).floor().clamp(0, windows - 1);
    for (var w = first; w <= last; w++) {
      final overlap =
          (n.end < (w + 1) * step ? n.end : (w + 1) * step) -
          (n.start > w * step ? n.start : w * step);
      if (overlap > 0) chroma[w][n.midi % 12] += overlap * n.amplitude;
    }
  }

  final smooth = _bestPath(chroma);

  final events = <NoteEvent>[];
  for (var i = 0; i < smooth.length; i++) {
    final chord = smooth[i];
    if (chord == null) continue;
    if (events.isNotEmpty &&
        events.last.chord == chord &&
        (events.last.end - i * step).abs() < 1e-6) {
      final last = events.removeLast();
      events.add(
        NoteEvent(
          start: last.start,
          duration: last.duration + step,
          midi: last.midi,
          chord: chord,
        ),
      );
    } else {
      events.add(
        NoteEvent(
          start: i * step,
          duration: step,
          midi: chord.voicing(),
          chord: chord,
        ),
      );
    }
  }
  // Drop chords too short to play (passing notes); the chord before
  // continues through them.
  final kept = <NoteEvent>[];
  for (final e in events.where((e) => e.duration >= 1.0)) {
    final last = kept.isEmpty ? null : kept.last;
    if (last != null && last.chord == e.chord && e.start - last.end < 1.5) {
      kept[kept.length - 1] = NoteEvent(
        start: last.start,
        duration: e.end - last.start,
        midi: last.midi,
        chord: last.chord,
      );
    } else {
      kept.add(e);
    }
  }
  return kept;
}

/// The most likely chord sequence (Viterbi): each window scores how well
/// each chord explains its notes, and changing chord costs [changeCost], so
/// the chord only changes when the music clearly does. Null = no chord.
List<Chord?> _bestPath(List<List<double>> chroma, {double changeCost = 0.6}) {
  final states = <Chord?>[null, ..._candidates];
  const noChord = 0.3;
  var score = List<double>.filled(states.length, 0);
  final back = <List<int>>[];
  for (final c in chroma) {
    final total = c.fold(0.0, (a, b) => a + b);
    final emission = [
      for (final state in states)
        total < 0.05
            ? (state == null ? 1.0 : 0.0)
            : state == null
            ? noChord
            : chordMatch([for (final v in c) v / total], state) -
                  0.03 * state.quality.intervals.length,
    ];
    var best = 0;
    for (var i = 1; i < score.length; i++) {
      if (score[i] > score[best]) best = i;
    }
    final next = List<double>.filled(states.length, 0);
    final from = List<int>.filled(states.length, 0);
    for (var i = 0; i < states.length; i++) {
      final stay = score[i], change = score[best] - changeCost;
      if (stay >= change) {
        next[i] = stay + emission[i];
        from[i] = i;
      } else {
        next[i] = change + emission[i];
        from[i] = best;
      }
    }
    score = next;
    back.add(from);
  }
  var state = 0;
  for (var i = 1; i < score.length; i++) {
    if (score[i] > score[state]) state = i;
  }
  final path = List<Chord?>.filled(chroma.length, null);
  for (var w = chroma.length - 1; w >= 0; w--) {
    path[w] = states[state];
    state = back[w][state];
  }
  return path;
}
