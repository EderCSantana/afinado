import 'dart:typed_data';

import 'package:flutter_soloud/flutter_soloud.dart';

import '../music/pitch.dart';

/// Audio output: the song's accompaniment and a guide tone playing the notes.
class Playback {
  Playback._();
  static final instance = Playback._();

  SoLoud get _soloud => SoLoud.instance;

  Future<void> ensureInitialized() async {
    if (!_soloud.isInitialized) await _soloud.init();
  }

  /// Decodes [path] (MP3, WAV, OGG, FLAC) to mono samples at [sampleRate],
  /// for analysis. Returns the samples and the duration in seconds.
  Future<(Float32List, double)> decode(
    String path, {
    int sampleRate = 22050,
  }) async {
    await ensureInitialized();
    final source = await _soloud.loadFile(path);
    final seconds = _soloud.getLength(source).inMicroseconds / 1e6;
    await _soloud.disposeSource(source);
    // Read at twice the rate and average pairs: a simple low-pass filter
    // against aliasing. (SoLoud's own `average` averages absolute values,
    // for waveform drawing, which destroys the signal.)
    final doubled = await _soloud.readSamplesFromFile(
      path,
      (seconds * sampleRate * 2).floor(),
    );
    final samples = Float32List(doubled.length ~/ 2);
    for (var i = 0; i < samples.length; i++) {
      samples[i] = (doubled[2 * i] + doubled[2 * i + 1]) / 2;
    }
    return (samples, seconds);
  }
}

/// The song's audio, with a clock to follow it.
class SongPlayer {
  SongPlayer._(this._source);

  final AudioSource _source;
  SoundHandle? _handle;

  static Future<SongPlayer> load(String path) async {
    await Playback.instance.ensureInitialized();
    return SongPlayer._(await SoLoud.instance.loadFile(path));
  }

  void play({double volume = 0.8}) {
    final h = _handle;
    if (h != null && SoLoud.instance.getIsValidVoiceHandle(h)) {
      SoLoud.instance.setPause(h, false);
    } else {
      _handle = SoLoud.instance.play(_source, volume: volume);
    }
  }

  void pause() {
    final h = _handle;
    if (h != null && SoLoud.instance.getIsValidVoiceHandle(h)) {
      SoLoud.instance.setPause(h, true);
    }
  }

  void setVolume(double volume) {
    final h = _handle;
    if (h != null && SoLoud.instance.getIsValidVoiceHandle(h)) {
      SoLoud.instance.setVolume(h, volume);
    }
  }

  /// Playback position in seconds, or null once the song ended.
  double? get position {
    final h = _handle;
    if (h == null) return 0;
    if (!SoLoud.instance.getIsValidVoiceHandle(h)) return null;
    return SoLoud.instance.getPosition(h).inMicroseconds / 1e6;
  }

  Future<void> dispose() async {
    final h = _handle;
    if (h != null && SoLoud.instance.getIsValidVoiceHandle(h)) {
      await SoLoud.instance.stop(h);
    }
    await SoLoud.instance.disposeSource(_source);
  }
}

/// A soft tone that plays the note to be played, as a guide.
class GuideTone {
  GuideTone._(this._source, this._handle);

  final AudioSource _source;
  final SoundHandle _handle;
  int? _note;
  double volume = 0.25;

  static Future<GuideTone> create() async {
    await Playback.instance.ensureInitialized();
    final source = await SoLoud.instance.loadWaveform(
      WaveForm.triangle,
      false,
      0.25,
      0,
    );
    final handle = SoLoud.instance.play(source, volume: 0);
    return GuideTone._(source, handle);
  }

  /// Plays [midi], or silence for null.
  void set(int? midi) {
    if (midi == _note) return;
    _note = midi;
    if (midi == null) {
      SoLoud.instance.setVolume(_handle, 0);
    } else {
      SoLoud.instance.setWaveformFreq(_source, midiToFrequency(midi));
      SoLoud.instance.setVolume(_handle, volume);
    }
  }

  Future<void> dispose() async {
    await SoLoud.instance.stop(_handle);
    await SoLoud.instance.disposeSource(_source);
  }
}
