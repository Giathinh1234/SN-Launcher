import 'package:flutter/material.dart';

import '../services/weather_service.dart';

/// The animated condition glyph that sits to the right of the clock.
///
/// The real device runs Google's "weather frog" — a little animated character.
/// This is a vector approximation in the same spirit: a sun/moon disc with
/// rays, a cloud body, and precipitation strokes, all drawn in one paint pass
/// so it costs nothing to animate on weak hardware.
class WeatherGlyph extends StatefulWidget {
  const WeatherGlyph({
    super.key,
    required this.condition,
    required this.color,
    this.size = const Size(30, 44),
    this.animate = true,
  });

  final WeatherCondition condition;
  final Color color;
  final Size size;

  /// Off for deterministic screenshots — an always-repeating controller keeps
  /// the test's fake-async zone from ever going idle.
  final bool animate;

  @override
  State<WeatherGlyph> createState() => _WeatherGlyphState();
}

class _WeatherGlyphState extends State<WeatherGlyph>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size.width,
      height: widget.size.height,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          painter: _WeatherGlyphPainter(
            condition: widget.condition,
            color: widget.color,
            t: _c.value,
          ),
        ),
      ),
    );
  }
}

class _WeatherGlyphPainter extends CustomPainter {
  _WeatherGlyphPainter({required this.condition, required this.color, required this.t});

  final WeatherCondition condition;
  final Color color;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final paint = Paint()..color = color;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.075
      ..strokeCap = StrokeCap.round;

    switch (condition) {
      case WeatherCondition.clear:
        final pulse = 1.0 + 0.03 * _wave(t * 2);
        final c = Offset(w / 2, h / 2);
        canvas.drawCircle(c, w * 0.26 * pulse, paint);
        for (var i = 0; i < 8; i++) {
          final a = i * 0.785398 + t * 0.25;
          canvas.drawLine(
            c + Offset.fromDirection(a, w * 0.36),
            c + Offset.fromDirection(a, w * 0.49),
            stroke,
          );
        }

      case WeatherCondition.partlyCloudy:
      case WeatherCondition.cloudy:
      case WeatherCondition.fog:
      case WeatherCondition.drizzle:
      case WeatherCondition.rain:
      case WeatherCondition.snow:
      case WeatherCondition.thunder:
        final cloudy = condition != WeatherCondition.partlyCloudy;
        if (!cloudy) {
          final c = Offset(w * 0.66, h * 0.30);
          canvas.drawCircle(c, w * 0.20, paint);
          for (var i = 0; i < 6; i++) {
            final a = i * 1.047 + t * 0.2;
            canvas.drawLine(
              c + Offset.fromDirection(a, w * 0.26),
              c + Offset.fromDirection(a, w * 0.35),
              stroke,
            );
          }
        }
        final dy = cloudy ? h * 0.30 : h * 0.44;
        canvas.drawCircle(Offset(w * 0.34, h * dy), w * 0.24, paint);
        canvas.drawCircle(Offset(w * 0.62, h * dy), w * 0.28, paint);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.16, h * dy, w * 0.72, w * 0.26),
            Radius.circular(w * 0.13),
          ),
          paint,
        );

        if (condition == WeatherCondition.rain || condition == WeatherCondition.drizzle) {
          final phase = t * 12;
          for (var i = 0; i < 3; i++) {
            final x = w * (0.30 + i * 0.20);
            final y = h * dy + w * 0.30 + ((phase + i * 2.1) % 4.0) * w * 0.06;
            canvas.drawLine(Offset(x, y), Offset(x - w * 0.07, y + w * 0.17), stroke);
          }
        }
        if (condition == WeatherCondition.snow) {
          final phase = t * 6;
          for (var i = 0; i < 3; i++) {
            final x = w * (0.30 + i * 0.20);
            final y = h * dy + w * 0.34 + ((phase + i) % 2.0) * w * 0.12;
            canvas.drawCircle(Offset(x, y), w * 0.055, paint);
          }
        }
        if (condition == WeatherCondition.thunder) {
          final p = Path()
            ..moveTo(w * 0.56, h * dy + w * 0.30)
            ..lineTo(w * 0.40, h * dy + w * 0.58)
            ..lineTo(w * 0.54, h * dy + w * 0.58)
            ..lineTo(w * 0.42, h * dy + w * 0.82);
          canvas.drawPath(p, stroke..strokeWidth = w * 0.09);
        }
        if (condition == WeatherCondition.fog) {
          for (var i = 0; i < 3; i++) {
            final y = h * dy + w * 0.30 + i * w * 0.14;
            canvas.drawLine(Offset(w * 0.14, y), Offset(w * 0.86, y), stroke);
          }
        }

      case WeatherCondition.unknown:
        canvas.drawCircle(Offset(w / 2, h / 2), w * 0.24, stroke);
    }
  }

  static double _wave(double x) => (x % 6.28318 - 3.14159).abs() / 3.14159 - 1;

  @override
  bool shouldRepaint(covariant _WeatherGlyphPainter old) =>
      old.condition != condition || old.color != color || old.t != t;
}