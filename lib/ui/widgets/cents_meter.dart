import 'package:flutter/material.dart';

/// Color for a deviation in cents: green in tune, amber close, orange off.
Color tuningColor(double? cents, ColorScheme colors) {
  if (cents == null) return colors.outline;
  final c = cents.abs();
  if (c <= 12) return Colors.greenAccent;
  if (c <= 25) return Colors.amber;
  return Colors.deepOrange;
}

/// A -50..+50 cents scale with a needle (a dot).
class CentsMeter extends StatelessWidget {
  const CentsMeter({super.key, required this.cents, this.height = 24});

  final double? cents;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      height: height,
      child: CustomPaint(
        size: Size.infinite,
        painter: _NeedlePainter(
          cents,
          tuningColor(cents, colors),
          colors.outline,
          colors.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _NeedlePainter extends CustomPainter {
  _NeedlePainter(this.cents, this.color, this.scale, this.labels);

  final double? cents;
  final Color color;
  final Color scale;
  final Color labels;

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.width / 2;
    final lineY = size.height / 2;
    final big = size.height > 40;
    final line = Paint()
      ..color = scale
      ..strokeWidth = big ? 2 : 1;
    // The in-tune zone.
    canvas.drawRect(
      Rect.fromLTRB(mid - 12 / 50 * mid, 0, mid + 12 / 50 * mid, size.height),
      Paint()..color = Colors.greenAccent.withValues(alpha: 0.08),
    );
    canvas.drawLine(Offset(0, lineY), Offset(size.width, lineY), line);
    for (final c in [-50, -25, -12, 0, 12, 25, 50]) {
      final x = mid + c / 50 * mid;
      final h = c == 0 ? size.height : size.height / 2;
      canvas.drawLine(
        Offset(x, (size.height - h) / 2),
        Offset(x, (size.height + h) / 2),
        line,
      );
      if (big && c != 0) {
        final text = TextPainter(
          text: TextSpan(
            text: c > 0 ? '+$c' : '$c',
            style: TextStyle(color: labels, fontSize: 11),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        text.paint(
          canvas,
          Offset(
            (x - text.width / 2).clamp(0, size.width - text.width).toDouble(),
            size.height - text.height,
          ),
        );
      }
    }
    final value = cents;
    if (value == null) return;
    final x = mid + value.clamp(-50, 50) / 50 * mid;
    if (big) {
      canvas.drawLine(
        Offset(x, 4),
        Offset(x, size.height - 16),
        Paint()
          ..color = color
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round,
      );
    } else {
      canvas.drawCircle(Offset(x, lineY), 8, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_NeedlePainter old) =>
      old.cents != cents || old.color != color;
}
