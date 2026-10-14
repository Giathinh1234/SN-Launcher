import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../state/shell_controller.dart';

/// The Google Assistant four-dot mark.
///
/// Google publishes exactly four brand colours for this: blue #4285F4,
/// red #EA4335, yellow #FBBC04, green #34A853. Each dot breathes on its own
/// phase and rises as the assistant "hears" more, matching the device's
/// listening animation.
class AssistantOrb extends StatefulWidget {
  const AssistantOrb({
    super.key,
    required this.state,
    required this.size,
    required this.color,
    this.label,
  });

  final AssistantState state;
  final double size;
  final Color color;
  final String? label;

  @override
  State<AssistantOrb> createState() => _AssistantOrbState();
}

class _AssistantOrbState extends State<AssistantOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))
        ..repeat();

  /// Google's published Assistant brand colours, in dot order.
  static const List<Color> kBrandColors = [
    Color(0xFF4285F4), // blue
    Color(0xFFEA4335), // red
    Color(0xFFFBBC04), // yellow
    Color(0xFF34A853), // green
  ];

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final listening = widget.state == AssistantState.listening;
    final processing = widget.state == AssistantState.processing;
    final active = listening || processing;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(
          dimension: widget.size,
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) => CustomPaint(
              painter: _OrbPainter(
                phase: _c.value,
                active: active,
                processing: processing,
                idleColor: widget.color.withValues(alpha: 0.55),
              ),
            ),
          ),
        ),
        if (widget.label != null) ...[
          SizedBox(height: widget.size * 0.22),
          Text(
            widget.label!,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'GoogleSans',
              fontSize: widget.size * 0.20,
              fontWeight: FontWeight.w400,
              color: widget.color.withValues(alpha: 0.85),
            ),
          ),
        ],
      ],
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter({
    required this.phase,
    required this.active,
    required this.processing,
    required this.idleColor,
  });

  final double phase;
  final bool active;
  final bool processing;
  final Color idleColor;

  static const _brandColors = _AssistantOrbState.kBrandColors;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width * 0.17;
    final travel = size.width * 0.26;

    // Dot layout: blue + red on top, green + yellow on the bottom, the classic
    // Google Assistant arrangement.
    const baseOffsets = [
      Offset(-1, -1),
      Offset(1, -1),
      Offset(-1, 1),
      Offset(1, 1),
    ];

    for (var i = 0; i < 4; i++) {
      // Each dot runs its own phase so the mark ripples rather than pulsing in
      // unison.
      final p = (phase + i * 0.25) % 1.0;
      final wave = math.sin(p * math.pi * 2);
      var scale = 1.0;
      var offset = baseOffsets[i];
      var color = idleColor;

      if (active) {
        color = Color.lerp(idleColor, _brandColors[i], 0.25 + 0.75 * (wave + 1) / 2)!;
        scale = 1.0 + 0.45 * (wave + 1) / 2;
      }
      if (processing) {
        // Processing spins the dots around the centre, like the device's
        // "thinking" state.
        final angle = phase * math.pi * 2 + i * math.pi / 2;
        offset = Offset(math.cos(angle), math.sin(angle));
        color = _brandColors[i];
        scale = 1.0;
      }

      final pos = Offset(
        c.dx + offset.dx * travel,
        c.dy + offset.dy * travel - (active ? wave * size.height * 0.05 : 0),
      );
      canvas.drawCircle(pos, r * scale, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _OrbPainter old) =>
      old.phase != phase || old.active != active || old.processing != processing;
}