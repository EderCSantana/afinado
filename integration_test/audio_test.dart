import 'dart:io';

import 'package:afinado/audio/mic_listener.dart';
import 'package:afinado/models/song.dart';
import 'package:afinado/models/instrument.dart';
import 'package:afinado/song_loader.dart';
import 'package:afinado/app_state.dart';
import 'package:afinado/ui/play_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Runs on the real platform audio stack:
/// `flutter test integration_test -d windows --dart-define=AUDIO=<file.wav>`
/// with a file playing C D E F G (0.6 s each) then the chords C, Am, G (2 s each).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const audio = String.fromEnvironment('AUDIO');

  testWidgets('decodes an audio file and finds its melody and chords', (
    tester,
  ) async {
    if (audio.isEmpty || !File(audio).existsSync()) {
      markTestSkipped('Pass --dart-define=AUDIO=<file>');
      return;
    }
    final song = await tester.runAsync(() => loadSong(audio));
    expect(song!.duration, closeTo(9, 0.1));
    final melody = song.parts.firstWhere((p) => p.kind == PartKind.melody);
    final chords = song.parts.firstWhere((p) => p.kind == PartKind.chords);
    final notes = [
      for (final e in melody.events.where((e) => e.start < 3)) e.midi.single,
    ];
    expect(notes, [60, 62, 64, 65, 67]);
    expect(
      [
        for (final e in chords.events.where((e) => e.start > 2.9))
          e.chord!.name(),
      ],
      ['C', 'Am', 'G'],
    );
  });

  testWidgets('opens the microphone and streams readings', (tester) async {
    if (MicListener.devices().isEmpty) {
      markTestSkipped('No capture device');
      return;
    }
    final mic = MicListener(analyzeChords: true);
    final readings = await tester.runAsync(() async {
      await mic.start();
      final got = await mic.readings
          .take(5)
          .toList()
          .timeout(const Duration(seconds: 5));
      await mic.dispose();
      return got;
    });
    expect(readings, hasLength(5));
  });

  testWidgets('a screen closing does not cut off the next one\'s microphone', (
    tester,
  ) async {
    if (MicListener.devices().isEmpty) {
      markTestSkipped('No capture device');
      return;
    }
    final readings = await tester.runAsync(() async {
      // As when switching tabs: the new screen starts before the old one
      // is disposed.
      final old = MicListener();
      await old.start();
      final next = MicListener(analyzeChords: true);
      final started = next.start();
      final closed = old.dispose();
      await Future.wait([started, closed]);
      final got = await next.readings
          .take(5)
          .toList()
          .timeout(const Duration(seconds: 5));
      await next.dispose();
      return got;
    });
    expect(readings, hasLength(5));
  });

  testWidgets('plays a short song to the end and shows the results', (
    tester,
  ) async {
    if (MicListener.devices().isEmpty) {
      markTestSkipped('No capture device');
      return;
    }
    const song = Song(
      title: 'Teste',
      duration: 1.5,
      parts: [
        Part(
          name: 'Melodia',
          kind: PartKind.melody,
          events: [
            NoteEvent(start: 0, duration: 0.5, midi: [60]),
            NoteEvent(start: 0.5, duration: 0.5, midi: [64, 67]),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PlayPage(
          song: song,
          part: song.parts.single,
          instrument: instruments.first,
          settings: PlaySettings()..guideTone = true,
        ),
      ),
    );
    // Countdown (3 s) + song + 1 s, in real time.
    for (
      var i = 0;
      i < 70 && find.text('Tocar de novo').evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    expect(find.text('Tocar de novo'), findsOneWidget);
    expect(find.textContaining('Errou: '), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
