import 'dart:typed_data';

import '../models/song.dart';

/// General MIDI instrument families (program ~/ 8).
const gmFamilies = [
  'Piano',
  'Percussão cromática',
  'Órgão',
  'Violão/Guitarra',
  'Baixo',
  'Cordas',
  'Conjunto de cordas/Coro',
  'Metais',
  'Palhetas (sax, clarinete)',
  'Flautas',
  'Sintetizador (solo)',
  'Sintetizador (pad)',
  'Sintetizador (efeitos)',
  'Étnicos',
  'Percussão',
  'Efeitos sonoros',
];

class MidiFormatException implements Exception {
  MidiFormatException(this.message);
  final String message;
  @override
  String toString() => 'Arquivo MIDI inválido: $message';
}

/// Reads a Standard MIDI File into a [Song] with one [Part] per track and
/// channel (drums excluded). Notes that start together become one event.
Song parseMidi(Uint8List bytes, {required String title}) {
  final reader = _Reader(bytes);
  if (reader.string(4) != 'MThd') {
    throw MidiFormatException('cabeçalho MThd ausente');
  }
  final headerLength = reader.uint32();
  reader.uint16(); // format
  final trackCount = reader.uint16();
  final division = reader.uint16();
  reader.pos += headerLength - 6;

  final tempoChanges = <(int, int)>[(0, 500000)]; // (tick, µs per quarter)
  final rawNotes =
      <
        (int, int),
        List<(int, int, int)>
      >{}; // (track, ch) → (startTick, endTick, key)
  final names = <int, String>{};
  final programs = <(int, int), int>{};

  for (var track = 0; track < trackCount && reader.remaining >= 8; track++) {
    final id = reader.string(4);
    final length = reader.uint32();
    final end = reader.pos + length;
    if (id != 'MTrk') {
      reader.pos = end;
      continue;
    }
    var tick = 0;
    var status = 0;
    final open = <(int, int), List<int>>{}; // (ch, key) → start ticks
    while (reader.pos < end) {
      tick += reader.varLen();
      var byte = reader.uint8();
      if (byte < 0x80) {
        // Running status: reuse the previous status, this was a data byte.
        reader.pos--;
        byte = status;
      } else if (byte < 0xF0) {
        status = byte;
      }
      if (byte == 0xFF) {
        final type = reader.uint8();
        final len = reader.varLen();
        final data = reader.bytes(len);
        if (type == 0x51 && len == 3) {
          tempoChanges.add((tick, data[0] << 16 | data[1] << 8 | data[2]));
        } else if (type == 0x03 && len > 0) {
          names[track] = String.fromCharCodes(data).trim();
        }
      } else if (byte == 0xF0 || byte == 0xF7) {
        reader.pos += reader.varLen();
      } else {
        final kind = byte & 0xF0;
        final channel = byte & 0x0F;
        final a = reader.uint8();
        final b = kind == 0xC0 || kind == 0xD0 ? 0 : reader.uint8();
        if (channel == 9) continue; // Drums have no pitch to play.
        if (kind == 0x90 && b > 0) {
          (open[(channel, a)] ??= []).add(tick);
        } else if (kind == 0x80 || kind == 0x90) {
          final starts = open[(channel, a)];
          if (starts != null && starts.isNotEmpty) {
            (rawNotes[(track, channel)] ??= []).add((
              starts.removeAt(0),
              tick,
              a,
            ));
          }
        } else if (kind == 0xC0) {
          programs[(track, channel)] ??= a;
        }
      }
    }
    reader.pos = end;
  }

  final seconds = _TempoMap(tempoChanges, division);
  final parts = <Part>[];
  var duration = 0.0;
  final keys = rawNotes.keys.toList()
    ..sort((x, y) => x.$1 != y.$1 ? x.$1 - y.$1 : x.$2 - y.$2);
  final channelsPerTrack = <int, int>{};
  for (final (track, _) in keys) {
    channelsPerTrack[track] = (channelsPerTrack[track] ?? 0) + 1;
  }
  for (final key in keys) {
    final (track, channel) = key;
    final notes = [
      for (final (s, e, k) in rawNotes[key]!) (seconds.at(s), seconds.at(e), k),
    ]..sort((x, y) => x.$1.compareTo(y.$1));
    final events = <NoteEvent>[];
    for (var i = 0; i < notes.length;) {
      // Notes starting within 30 ms are played together.
      var j = i + 1;
      while (j < notes.length && notes[j].$1 - notes[i].$1 < 0.03) {
        j++;
      }
      final group = notes.sublist(i, j);
      final end = group.map((n) => n.$2).reduce((a, b) => a > b ? a : b);
      events.add(
        NoteEvent(
          start: notes[i].$1,
          duration: end - notes[i].$1,
          midi: ({for (final n in group) n.$3}.toList()..sort()),
        ),
      );
      if (end > duration) duration = end;
      i = j;
    }
    final program = programs[key];
    final base =
        names[track] ??
        (program != null ? gmFamilies[program ~/ 8] : 'Faixa ${track + 1}');
    parts.add(
      Part(
        name: channelsPerTrack[track]! > 1
            ? '$base (canal ${channel + 1})'
            : base,
        kind: PartKind.melody,
        events: events,
        program: program,
      ),
    );
  }
  return Song(title: title, duration: duration, parts: parts);
}

class _TempoMap {
  _TempoMap(List<(int, int)> changes, this.division) {
    changes.sort((a, b) => a.$1.compareTo(b.$1));
    var seconds = 0.0;
    var lastTick = 0;
    var tempo = changes.first.$2;
    for (final (tick, value) in changes) {
      seconds += (tick - lastTick) * _secondsPerTick(tempo);
      _points.add((tick, seconds, value));
      lastTick = tick;
      tempo = value;
    }
  }

  final int division;
  final _points = <(int, double, int)>[]; // (tick, seconds, tempo)

  double _secondsPerTick(int tempo) {
    if (division & 0x8000 != 0) {
      // SMPTE: frames per second × ticks per frame.
      final fps = 256 - (division >> 8);
      return 1 / (fps * (division & 0xFF));
    }
    return tempo / 1e6 / division;
  }

  double at(int tick) {
    var point = _points.first;
    for (final p in _points) {
      if (p.$1 > tick) break;
      point = p;
    }
    return point.$2 + (tick - point.$1) * _secondsPerTick(point.$3);
  }
}

class _Reader {
  _Reader(this.data);

  final Uint8List data;
  int pos = 0;

  int get remaining => data.length - pos;

  void _need(int n) {
    if (pos + n > data.length) {
      throw MidiFormatException('fim inesperado do arquivo');
    }
  }

  int uint8() {
    _need(1);
    return data[pos++];
  }

  int uint16() => uint8() << 8 | uint8();
  int uint32() => uint16() << 16 | uint16();

  int varLen() {
    var value = 0;
    for (var i = 0; i < 4; i++) {
      final b = uint8();
      value = value << 7 | (b & 0x7F);
      if (b & 0x80 == 0) return value;
    }
    throw MidiFormatException('número de tamanho variável inválido');
  }

  Uint8List bytes(int n) {
    _need(n);
    return Uint8List.sublistView(data, pos, pos += n);
  }

  String string(int n) => String.fromCharCodes(bytes(n));
}
