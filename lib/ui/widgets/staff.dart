import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../game/judge.dart';
import '../../models/song.dart';
import '../../music/chords.dart';
import '../../music/pitch.dart';

/// Color of a finished step by its grade.
Color gradeColor(Grade? grade, ColorScheme colors) => switch (grade) {
  Grade.perfect => Colors.greenAccent.shade400,
  Grade.good => Colors.lightGreen,
  Grade.outOfTune => Colors.amber.shade600,
  Grade.missed => Colors.red.shade400,
  null => colors.onSurface,
};

/// Where each step of a part goes on the page: rows of staves, like a
/// sheet of music, scrolled so the current row stays near the top.
class StaffLayout {
  StaffLayout(this.size, this.count, this.current);

  final Size size;
  final int count;
  final int current;

  static const gap = 11.0; // Between staff lines.
  static const slot = 66.0; // Width of each note.
  static const margin = 64.0; // Left, for the clef.
  static const rowHeight = gap * 4 + 128;

  int get perRow => math.max(1, ((size.width - margin - 16) / slot).floor());
  int get rows => math.max(1, (size.height / rowHeight).floor());

  /// First row shown: the current one, with the previous above it when
  /// there is room.
  int get firstRow {
    final row = current ~/ perRow;
    return math.max(0, row - (rows >= 3 ? 1 : 0));
  }

  /// Top of the staff (top line) for screen row [r].
  double staffTop(int r) => r * rowHeight + 58;

  /// Slot of step [i], or null when off screen.
  Rect? slotOf(int i) {
    final r = i ~/ perRow - firstRow;
    if (r < 0 || r >= rows) return null;
    final x = margin + (i % perRow) * slot;
    return Rect.fromLTWH(x, r * rowHeight, slot, rowHeight);
  }

  int? stepAt(Offset p) {
    final r = (p.dy / rowHeight).floor();
    final c = ((p.dx - margin) / slot).floor();
    if (r < 0 || r >= rows || c < 0 || c >= perRow) return null;
    final i = (firstRow + r) * perRow + c;
    return i < count ? i : null;
  }
}

/// A part shown as notes on a staff, with the current step highlighted,
/// the finished ones colored by how they went.
class StaffView extends StatelessWidget {
  const StaffView({
    super.key,
    required this.part,
    required this.current,
    required this.grades,
    required this.naming,
    required this.transposition,
    this.showNames = true,
    this.hold = 0,
    this.loop,
    this.onTapStep,
  });

  final Part part;
  final int current;

  /// Grade of each step played so far (null = not yet).
  final List<Grade?> grades;
  final NoteNaming naming;
  final int transposition;
  final bool showNames;

  /// Progress of holding the current note, 0..1.
  final double hold;
  final (int, int)? loop;
  final void Function(int step)? onTapStep;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = StaffLayout(
          constraints.biggest,
          part.events.length,
          current,
        );
        return GestureDetector(
          onTapUp: (d) {
            final i = layout.stepAt(d.localPosition);
            if (i != null) onTapStep?.call(i);
          },
          child: CustomPaint(
            size: constraints.biggest,
            painter: _StaffPainter(
              layout: layout,
              part: part,
              grades: grades,
              naming: naming,
              transposition: transposition,
              showNames: showNames,
              hold: hold,
              loop: loop,
              colors: colors,
            ),
          ),
        );
      },
    );
  }
}

/// Letter (0 = C .. 6 = B) and sharp for each pitch class.
const _spelling = [
  (0, false),
  (0, true),
  (1, false),
  (1, true),
  (2, false),
  (3, false),
  (3, true),
  (4, false),
  (4, true),
  (5, false),
  (5, true),
  (6, false),
];

/// Diatonic position: C4 = 28, D4 = 29...
int _step(int midi) => (midi ~/ 12 - 1) * 7 + _spelling[midi % 12].$1;

class _StaffPainter extends CustomPainter {
  _StaffPainter({
    required this.layout,
    required this.part,
    required this.grades,
    required this.naming,
    required this.transposition,
    required this.showNames,
    required this.hold,
    required this.loop,
    required this.colors,
  });

  final StaffLayout layout;
  final Part part;
  final List<Grade?> grades;
  final NoteNaming naming;
  final int transposition;
  final bool showNames;
  final double hold;
  final (int, int)? loop;
  final ColorScheme colors;

  static const _gap = StaffLayout.gap;

  @override
  void paint(Canvas canvas, Size size) {
    final notes = [
      for (final e in part.events) ...e.midi.map((m) => m + transposition),
    ]..sort();
    if (notes.isEmpty) return;
    final treble = notes[notes.length ~/ 2] >= 57;
    // Bottom line: E4 in treble clef, G2 in bass clef.
    final bottomStep = treble ? _step(64) : _step(43);

    final ink = Paint()
      ..color = colors.onSurfaceVariant
      ..strokeWidth = 1.2;
    final loopRange = loop;

    for (var r = 0; r < layout.rows; r++) {
      final first = (layout.firstRow + r) * layout.perRow;
      if (first >= part.events.length) break;
      final last = math.min(first + layout.perRow, part.events.length) - 1;
      final top = layout.staffTop(r);
      final bottom = top + 4 * _gap;
      final right =
          StaffLayout.margin + (last - first + 1) * StaffLayout.slot + 8;

      // The repeated passage.
      if (loopRange != null) {
        final a = math.max(first, loopRange.$1),
            b = math.min(last, loopRange.$2);
        if (a <= b) {
          final ra = layout.slotOf(a)!, rb = layout.slotOf(b)!;
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTRB(ra.left, top - 40, rb.right, bottom + 40),
              const Radius.circular(10),
            ),
            Paint()..color = colors.tertiary.withValues(alpha: 0.12),
          );
        }
      }

      // The current step.
      final cur = layout.slotOf(layout.current);
      if (cur != null && layout.current >= first && layout.current <= last) {
        final box = Rect.fromLTRB(
          cur.left + 2,
          top - 44,
          cur.right - 2,
          bottom + 48,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(box, const Radius.circular(10)),
          Paint()..color = colors.primary.withValues(alpha: 0.18),
        );
        if (hold > 0) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(
                box.left + 6,
                box.bottom - 8,
                (box.width - 12) * hold.clamp(0, 1),
                4,
              ),
              const Radius.circular(2),
            ),
            Paint()..color = Colors.greenAccent,
          );
        }
      }

      for (var l = 0; l < 5; l++) {
        canvas.drawLine(
          Offset(8, top + l * _gap),
          Offset(right, top + l * _gap),
          ink,
        );
      }
      canvas.drawLine(Offset(right, top), Offset(right, bottom), ink);
      _text(
        canvas,
        treble ? '𝄞' : '𝄢',
        Offset(10, treble ? top - 2.2 * _gap : top - 0.6 * _gap),
        treble ? _gap * 6.2 : _gap * 3.6,
        colors.onSurfaceVariant,
      );

      for (var i = first; i <= last; i++) {
        _paintStep(canvas, i, layout.slotOf(i)!, top, bottom, bottomStep);
      }
    }
  }

  void _paintStep(
    Canvas canvas,
    int i,
    Rect slot,
    double top,
    double bottom,
    int bottomStep,
  ) {
    final event = part.events[i];
    final color = i == layout.current
        ? colors.primary
        : grades[i] != null
        ? gradeColor(grades[i], colors)
        : colors.onSurface.withValues(alpha: i < layout.current ? 0.5 : 0.9);
    final cx = slot.center.dx;
    double y(int step) => bottom - (step - bottomStep) * _gap / 2;

    final heads = [...event.midi.map((m) => m + transposition)]..sort();
    int? previousStep;
    var shift = false;
    for (final m in heads) {
      final step = _step(m);
      // Seconds in a chord sit side by side.
      shift = previousStep != null && step - previousStep == 1 && !shift;
      previousStep = step;
      final x = cx + (shift ? _gap * 1.1 : 0) - (heads.length > 1 ? 4 : 0);
      final hy = y(step);

      // Ledger lines.
      final ledger = Paint()
        ..color = colors.onSurfaceVariant
        ..strokeWidth = 1.2;
      for (var s = bottomStep - 2; s >= step; s -= 2) {
        canvas.drawLine(
          Offset(x - _gap * 1.1, y(s)),
          Offset(x + _gap * 1.1, y(s)),
          ledger,
        );
      }
      for (var s = bottomStep + 10; s <= step; s += 2) {
        canvas.drawLine(
          Offset(x - _gap * 1.1, y(s)),
          Offset(x + _gap * 1.1, y(s)),
          ledger,
        );
      }

      canvas.save();
      canvas.translate(x, hy);
      canvas.rotate(-0.35);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset.zero,
          width: _gap * 1.45,
          height: _gap * 1.0,
        ),
        Paint()..color = color,
      );
      canvas.restore();
      if (_spelling[m % 12].$2) {
        _text(
          canvas,
          '♯',
          Offset(x - _gap * 2.3, hy - _gap * 1.05),
          _gap * 1.6,
          color,
        );
      }
    }

    // Chord symbol above, note names below.
    final chord = event.chord ?? chordOfNotes(event.midi);
    if (chord != null || event.midi.length > 1) {
      final name = chord != null
          ? Chord((chord.root + transposition) % 12, chord.quality).name(naming)
          : heads.map((m) => pitchClassName(m, naming)).join(' ');
      _text(
        canvas,
        name,
        Offset(slot.left + 6, top - 40),
        17,
        color,
        bold: true,
        maxWidth: slot.width - 6,
      );
    } else if (showNames) {
      _text(
        canvas,
        pitchClassName(heads.first, naming),
        Offset(slot.left + 8, bottom + 24),
        15,
        color,
        bold: i == layout.current,
        maxWidth: slot.width - 8,
      );
    }
  }

  void _text(
    Canvas canvas,
    String text,
    Offset at,
    double size,
    Color color, {
    bool bold = false,
    double maxWidth = 200,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: size,
          color: color,
          height: 1,
          fontWeight: bold ? FontWeight.bold : null,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    painter.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_StaffPainter old) => true;
}
