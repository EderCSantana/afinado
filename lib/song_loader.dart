import 'dart:io';

import 'package:flutter/foundation.dart';

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
