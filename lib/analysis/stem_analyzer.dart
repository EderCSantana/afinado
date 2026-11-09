import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// One transcribed note: seconds, MIDI note and loudness (0..1).
typedef StemNote = ({double start, double end, int midi, double amplitude});

/// The notes found in one instrument of a song.
class StemPart {
  const StemPart(this.stem, this.notes);

  /// Demucs source name: vocals, bass, guitar, piano or other.
  final String stem;
  final List<StemNote> notes;
}

/// Result of separating a song into instruments and transcribing them.
class StemAnalysis {
  const StemAnalysis({
    required this.duration,
    required this.stems,
    required this.parts,
  });

  final double duration;

  /// Source name → WAV file with that instrument alone.
  final Map<String, String> stems;
  final List<StemPart> parts;

  factory StemAnalysis.fromJson(Map<String, dynamic> json, String dir) =>
      StemAnalysis(
        duration: (json['duration'] as num).toDouble(),
        stems: {
          for (final MapEntry(:key, :value)
              in (json['stems'] as Map<String, dynamic>).entries)
            key: '$dir${Platform.pathSeparator}$value',
        },
        parts: [
          for (final p in json['parts'] as List)
            StemPart(p['stem'] as String, [
              for (final n in p['notes'] as List)
                (
                  start: (n[0] as num).toDouble(),
                  end: (n[1] as num).toDouble(),
                  midi: n[2] as int,
                  amplitude: (n[3] as num).toDouble(),
                ),
            ]),
        ],
      );
}

class AnalyzerException implements Exception {
  AnalyzerException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Runs tools/analyzer/analyze.py (Demucs + Basic Pitch) in its own Python
/// environment, caching the results per file.
class StemAnalyzer {
  static String get _localAppData =>
      Platform.environment['LOCALAPPDATA'] ??
      '${Platform.environment['HOME']}/.local/share';

  /// The analyzer's Python: AFINADO_PYTHON, or the environment made by
  /// tools/analyzer/setup.ps1.
  static String get python =>
      Platform.environment['AFINADO_PYTHON'] ??
      (Platform.isWindows
          ? '$_localAppData\\afinado\\analyzer\\Scripts\\python.exe'
          : '$_localAppData/afinado/analyzer/bin/python');

  /// analyze.py: next to the app (bundled as an asset) or in the source tree.
  static String? get script {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final candidates = [
      ?Platform.environment['AFINADO_ANALYZER'],
      '$exeDir/data/flutter_assets/tools/analyzer/analyze.py',
      '${Directory.current.path}/tools/analyzer/analyze.py',
    ];
    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    return null;
  }

  static bool get available => script != null && File(python).existsSync();

  /// Where the analysis of [audioPath] is kept: changes with the file.
  static Directory cacheFor(String audioPath) {
    final file = File(audioPath);
    final stat = file.statSync();
    final key = _hash('${file.absolute.path}|${stat.size}|${stat.modified}');
    return Directory('$_localAppData/afinado/analysis/$key');
  }

  static StemAnalysis? cached(String audioPath) {
    final dir = cacheFor(audioPath);
    final json = File('${dir.path}/analysis.json');
    if (!json.existsSync()) return null;
    return StemAnalysis.fromJson(
      jsonDecode(json.readAsStringSync()) as Map<String, dynamic>,
      dir.path,
    );
  }

  /// Separates and transcribes [audioPath], reporting progress (0..1) and
  /// what is being done. Takes minutes on a CPU; the result is cached.
  static Future<StemAnalysis> analyze(
    String audioPath, {
    void Function(double progress, String message)? onProgress,
  }) async {
    final hit = cached(audioPath);
    if (hit != null) return hit;
    final script = StemAnalyzer.script;
    if (script == null || !File(python).existsSync()) {
      throw AnalyzerException(
        'O analisador de instrumentos não está instalado '
        '(rode tools/analyzer/setup.ps1).',
      );
    }
    final dir = cacheFor(audioPath)..createSync(recursive: true);
    final process = await Process.start(
      python,
      ['-u', script, audioPath, dir.path],
      environment: {'PYTHONIOENCODING': 'utf-8'},
    );
    final errors = <String>[];
    final stderr = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          errors.add(line);
          if (errors.length > 30) errors.removeAt(0);
        });
    await process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach((line) {
          try {
            final p = jsonDecode(line) as Map<String, dynamic>;
            onProgress?.call(
              (p['progress'] as num).toDouble(),
              p['message'] as String,
            );
          } on FormatException {
            // Not a progress line.
          }
        });
    final code = await process.exitCode;
    await stderr.cancel();
    final result = cached(audioPath);
    if (code != 0 || result == null) {
      throw AnalyzerException(
        'A análise falhou (código $code):\n${errors.join('\n')}',
      );
    }
    return result;
  }
}

/// FNV-1a, 64 bits, as hex: a short stable name for a cache folder.
String _hash(String text) {
  var h = BigInt.parse('cbf29ce484222325', radix: 16);
  final prime = BigInt.parse('100000001b3', radix: 16);
  final mask = (BigInt.one << 64) - BigInt.one;
  for (final unit in utf8.encode(text)) {
    h = ((h ^ BigInt.from(unit)) * prime) & mask;
  }
  return h.toRadixString(16).padLeft(16, '0');
}
