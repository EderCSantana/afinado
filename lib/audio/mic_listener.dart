import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_recorder/flutter_recorder.dart';

import '../music/chords.dart';
import '../music/pitch.dart';
import '../music/yin.dart';

/// What the microphone heard in the last window.
class MicReading {
  const MicReading({
    required this.at,
    required this.windowSeconds,
    this.midi,
    this.confidence = 0,
    this.chroma,
    this.tuningCents,
  });

  /// When the last sample of the window arrived.
  final DateTime at;

  /// Length of the analyzed window; the sound is centered half of it before [at].
  final double windowSeconds;

  /// Detected pitch (fractional MIDI note), if one note was heard.
  final double? midi;
  final double confidence;

  /// Pitch-class energy and tuning, when chord analysis is on.
  final List<double>? chroma;
  final double? tuningCents;
}

/// Listens to the microphone and reports pitch (and chords) ~20 times a
/// second.
class MicListener {
  MicListener({this.analyzeChords = false});

  static const sampleRate = 22050;
  static const _chordWindow = 8192;
  static const _hop = 1024;

  /// Also compute chroma for chord recognition (more CPU).
  bool analyzeChords;

  final _yin = YinDetector(
    sampleRate: sampleRate,
    minFrequency: 60,
    maxFrequency: 1500,
  );
  final _buffer = Float32List(_chordWindow);
  int _filled = 0;
  int _sinceLast = 0;
  StreamSubscription<AudioDataContainer>? _subscription;
  final _readings = StreamController<MicReading>.broadcast();

  Stream<MicReading> get readings => _readings.stream;

  /// Capture devices, for the settings.
  static List<CaptureDevice> devices() {
    try {
      return Recorder.instance.listCaptureDevices();
    } catch (_) {
      return const [];
    }
  }

  /// The recorder is one for the whole app: starts and stops run one at a
  /// time, and only the listener that started it last may stop it (a screen
  /// being closed must not cut off the one replacing it).
  static Future<void> _queue = Future.value();
  static MicListener? _owner;

  Future<void> start({int deviceId = -1}) {
    final done = _queue.then((_) async {
      final recorder = Recorder.instance;
      if (recorder.isInitialized) {
        recorder.stopStreamingData();
        recorder.stop();
        recorder.deinit();
      }
      await recorder.init(
        deviceID: deviceId,
        format: PCMFormat.f32le,
        sampleRate: sampleRate,
        channels: RecorderChannels.mono,
      );
      recorder.start();
      _owner = this;
      _subscription = recorder.uint8ListStream.listen(_onData);
      recorder.startStreamingData();
    });
    _queue = done.catchError((_) {});
    return done;
  }

  Future<void> stop() {
    final done = _queue.then((_) async {
      await _subscription?.cancel();
      _subscription = null;
      if (_owner != this) return;
      _owner = null;
      final recorder = Recorder.instance;
      if (recorder.isInitialized) {
        recorder.stopStreamingData();
        recorder.stop();
        recorder.deinit();
      }
    });
    _queue = done.catchError((_) {});
    return done;
  }

  Future<void> dispose() async {
    await stop();
    await _readings.close();
  }

  void _onData(AudioDataContainer data) {
    // Copy: the view may not be aligned to 4 bytes.
    final samples = Uint8List.fromList(data.rawData).buffer.asFloat32List();
    final n = samples.length;
    if (n >= _buffer.length) {
      _buffer.setRange(0, _buffer.length, samples, n - _buffer.length);
      _filled = _buffer.length;
    } else {
      // Drop the oldest samples to make room, then append.
      final overflow = _filled + n - _buffer.length;
      if (overflow > 0) {
        _buffer.setRange(0, _filled - overflow, _buffer, overflow);
        _filled -= overflow;
      }
      _buffer.setRange(_filled, _filled + n, samples);
      _filled += n;
    }
    _sinceLast += samples.length;
    if (_sinceLast >= _hop) {
      _sinceLast = 0;
      _analyze();
    }
  }

  void _analyze() {
    final now = DateTime.now();
    final pitchSize = _yin.frameSize;
    if (_filled < pitchSize) return;
    final recent = _buffer.sublist(_filled - pitchSize, _filled);
    final reading = _yin.detect(recent);
    final pitched = reading != null && reading.confidence > 0.8;

    List<double>? chroma;
    double? tuning;
    if (analyzeChords && _filled == _buffer.length) {
      final spectrum = Spectrum.of(_buffer, sampleRate);
      chroma = spectrum.chroma();
      tuning = spectrum.tuningCents();
    }
    _readings.add(
      MicReading(
        at: now,
        windowSeconds: (chroma != null ? _chordWindow : pitchSize) / sampleRate,
        midi: pitched ? frequencyToMidi(reading.frequency) : null,
        confidence: reading?.confidence ?? 0,
        chroma: chroma,
        tuningCents: tuning,
      ),
    );
  }
}
