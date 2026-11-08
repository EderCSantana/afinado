import 'dart:math' as math;

/// Frequency of A4 (MIDI note 69), the tuning reference.
const double a4Frequency = 440;

/// Frequency in Hz of the (possibly fractional) MIDI note [midi].
double midiToFrequency(num midi) => a4Frequency * math.pow(2, (midi - 69) / 12);

/// MIDI note (fractional: 69.5 is a quarter tone above A4) of [hz].
double frequencyToMidi(double hz) =>
    69 + 12 * math.log(hz / a4Frequency) / math.ln2;

/// How many cents [midi] is above the nearest semitone, in -50..50.
double centsFromNearest(double midi) => (midi - midi.round()) * 100;

/// Cents from [target] to [midi]; with [anyOctave], measured to the nearest
/// octave of [target] (for voices and instruments sounding an octave apart).
double centsFrom(double midi, int target, {bool anyOctave = false}) {
  var diff = midi - target;
  if (anyOctave) diff -= 12 * (diff / 12).round();
  return diff * 100;
}

/// Note naming used in the interface.
enum NoteNaming {
  solfege('Dó Ré Mi'),
  letters('C D E');

  const NoteNaming(this.label);
  final String label;
}

const _solfege = [
  'Dó',
  'Dó♯',
  'Ré',
  'Ré♯',
  'Mi',
  'Fá',
  'Fá♯',
  'Sol',
  'Sol♯',
  'Lá',
  'Lá♯',
  'Si',
];
const _letters = [
  'C',
  'C♯',
  'D',
  'D♯',
  'E',
  'F',
  'F♯',
  'G',
  'G♯',
  'A',
  'A♯',
  'B',
];

/// Name of pitch class [pc] (0 = C).
String pitchClassName(int pc, [NoteNaming naming = NoteNaming.solfege]) =>
    (naming == NoteNaming.solfege ? _solfege : _letters)[pc % 12];

/// Name of [midi] with its octave (60 → "Dó4" / "C4").
String noteName(int midi, [NoteNaming naming = NoteNaming.solfege]) =>
    '${pitchClassName(midi, naming)}${midi ~/ 12 - 1}';
