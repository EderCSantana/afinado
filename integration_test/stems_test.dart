import 'dart:io';

import 'package:afinado/analysis/stem_analyzer.dart';
import 'package:afinado/models/song.dart';
import 'package:afinado/song_loader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Separates and transcribes a real song with the installed analyzer
/// (minutes on a CPU; cached after):
/// `flutter test integration_test/stems_test.dart -d windows --dart-define=SONG=song.mp3`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const path = String.fromEnvironment('SONG');

  testWidgets('splits a song into instruments and reads their notes', (
    tester,
  ) async {
    if (path.isEmpty || !File(path).existsSync() || !StemAnalyzer.available) {
      markTestSkipped(
        'Pass --dart-define=SONG=<file> and install the analyzer',
      );
      return;
    }
    final progress = <String>[];
    final song = await tester.runAsync(
      () => loadSong(path, onProgress: progress.add),
    );
    expect(song!.notice, isNull, reason: song.notice);
    expect(song.stems.keys, containsAll(['vocals', 'bass', 'guitar']));
    final names = song.parts.map((p) => p.name).toList();
    expect(names, containsAll(['Voz', 'Baixo', 'Acordes']));
    for (final part in song.parts) {
      expect(part.events.length, greaterThan(20), reason: part.name);
      for (var i = 1; i < part.events.length; i++) {
        expect(
          part.events[i].start,
          greaterThanOrEqualTo(part.events[i - 1].start),
        );
      }
    }
    final chords = song.parts.firstWhere((p) => p.kind == PartKind.chords);
    // Voice notes in a singing range.
    final voice = song.parts.firstWhere((p) => p.stem == 'vocals');
    expect(voice.range!.$1, greaterThanOrEqualTo(36));
    expect(voice.range!.$2, lessThanOrEqualTo(90));
    // ignore: avoid_print
    print(
      '${song.title}: ${[for (final p in song.parts) '${p.name} ${p.events.length}']}'
      ' · ${chords.events.take(12).map((e) => e.chord!.name()).join(' ')}'
      ' · ${progress.length} progress messages',
    );
  }, timeout: const Timeout(Duration(minutes: 20)));
}
