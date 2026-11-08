import 'dart:math' as math;

/// A detected pitch.
class PitchReading {
  const PitchReading(this.frequency, this.confidence);

  /// Fundamental frequency in Hz.
  final double frequency;

  /// 0..1; how periodic the frame is (1 = perfectly periodic).
  final double confidence;
}

/// YIN fundamental frequency estimator (de Cheveigné & Kawahara, 2002), for
/// one voice or one instrument line.
class YinDetector {
  YinDetector({
    required this.sampleRate,
    this.minFrequency = 60,
    this.maxFrequency = 1600,
    this.threshold = 0.15,
    this.minRms = 0.01,
  });

  final int sampleRate;
  final double minFrequency;
  final double maxFrequency;

  /// Dips of the normalized difference below this are taken as the period.
  final double threshold;

  /// Frames quieter than this (RMS, samples in -1..1) have no pitch.
  final double minRms;

  /// Frame length needed to find [minFrequency] (two periods).
  int get frameSize => (2 * sampleRate / minFrequency).ceil();

  /// The pitch of [frame], or null if it is silent or not periodic.
  PitchReading? detect(List<double> frame) {
    var energy = 0.0;
    for (final s in frame) {
      energy += s * s;
    }
    if (math.sqrt(energy / frame.length) < minRms) return null;

    final maxTau = math.min(
      frame.length ~/ 2,
      (sampleRate / minFrequency).ceil(),
    );
    final minTau = math.max(2, (sampleRate / maxFrequency).floor());
    final window = frame.length - maxTau;
    if (maxTau <= minTau + 2 || window <= 0) return null;

    // Cumulative mean normalized difference function.
    final d = List<double>.filled(maxTau + 1, 1);
    var running = 0.0;
    for (var tau = 1; tau <= maxTau; tau++) {
      var sum = 0.0;
      for (var i = 0; i < window; i++) {
        final delta = frame[i] - frame[i + tau];
        sum += delta * delta;
      }
      running += sum;
      d[tau] = running == 0 ? 1 : sum * tau / running;
    }

    // First dip under the threshold, else the global minimum if it is clear.
    var tau = -1;
    for (var t = minTau; t < maxTau; t++) {
      if (d[t] < threshold) {
        while (t + 1 < maxTau && d[t + 1] < d[t]) {
          t++;
        }
        tau = t;
        break;
      }
    }
    if (tau == -1) {
      var best = minTau;
      for (var t = minTau; t < maxTau; t++) {
        if (d[t] < d[best]) best = t;
      }
      if (d[best] > 0.35) return null;
      tau = best;
    }

    // Parabolic interpolation for sub-sample precision.
    var period = tau.toDouble();
    if (tau > 1 && tau < maxTau) {
      final a = d[tau - 1], b = d[tau], c = d[tau + 1];
      final denom = a + c - 2 * b;
      if (denom.abs() > 1e-12) period += 0.5 * (a - c) / denom;
    }
    final frequency = sampleRate / period;
    if (frequency < minFrequency || frequency > maxFrequency) return null;
    return PitchReading(frequency, (1 - d[tau]).clamp(0, 1).toDouble());
  }
}
