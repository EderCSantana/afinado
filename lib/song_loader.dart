import 'dart:io';

import 'package:flutter/foundation.dart';

import 'analysis/stem_analyzer.dart';
import 'analysis/stems_to_song.dart';
import 'audio/playback.dart';
import 'models/song.dart';
import 'music/audio_analysis.dart';
import 'music/midi_file.dart';

const midiExtensions = ['mid', 'midi'];
const audioExtensions = ['mp3', 'wav', 'ogg', 'flac'];

/// Opens a MIDI file (exact notes per track) or an audio file (melody and
/// chords estimated from the sound).
Future<Song> loadSong(String path, {void Function(String)? onProgress}) async {
  final file = File(path);
  final name = file.uri.pathSegments.last;
  final dot = name.lastIndexOf('.');
  final title = dot > 0 ? name.substring(0, dot) : name;
  final extension = dot > 0 ? name.substring(dot + 1).toLowerCase() : '';

  if (midiExtensions.contains(extension)) {
    final song = parseMidi(await file.readAsBytes(), title: title);
    if (song.parts.isEmpty) {
      throw const FormatException('O arquivo MIDI não tem notas.');
    }
    return song;
  }

  // The real thing: split the instruments apart and read each one.
  String? notice;
  if (StemAnalyzer.available || StemAnalyzer.cached(path) != null) {
    try {
      final analysis = await StemAnalyzer.analyze(
        path,
        onProgress: (p, message) =>
            onProgress?.call('$message ${(p * 100).round()}%'),
      );
      final parts = partsFromStems(analysis);
      if (parts.isNotEmpty) {
        return Song(
          title: title,
          duration: analysis.duration,
          audioPath: path,
          parts: parts,
          stems: analysis.stems,
        );
      }
      notice = 'A separação não encontrou instrumentos com notas.';
    } on AnalyzerException catch (e) {
      notice = e.message;
    }
  } else {
    notice =
        'Análise simples: o analisador de instrumentos (Demucs + Basic Pitch) '
        'não está instalado — veja tools/analyzer/setup.ps1.';
  }

  // Fallback: one melody and the chords from the whole mix.
  onProgress?.call('Decodificando o áudio…');
  const rate = 22050;
  final (samples, seconds) = await Playback.instance.decode(
    path,
    sampleRate: rate,
  );
  onProgress?.call('Procurando a melodia e os acordes…');
  final parts = await compute(_analyze, samples);
  return Song(
    title: title,
    duration: seconds,
    audioPath: path,
    notice: notice,
    parts: [
      for (final p in parts)
        if (!p.isEmpty) p,
    ],
  );
}

List<Part> _analyze(List<double> samples) => [
  extractMelody(samples, 22050),
  extractChords(samples, 22050),
];
