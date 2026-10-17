import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/nest_action.dart';

/// A thin rainbow bar across the top of the display.
///
/// Replaces the four-dot orb. Why a bar rather than dots:
///
///  * It is *state-honest at a glance*. A bar sitting flat and dark means the
///    assistant is not listening. Nothing animates unless [activity] says
///    something is actually happening, so there is no way for the display to
///    imply a capability that is not there.
///  * It reads from across a room. The Nest Hub is a wall display; the listener
///    is not standing next to it.
///  * It costs one `CustomPainter` over a few hundred pixels. The orb was a
///    column layout with four separately-timed sub-animations.
///
/// The gradient is drawn rather than composited from an image so it stays sharp
/// on any panel and costs nothing to bundle.
class AssistantLightbar extends StatefulWidget {
  const AssistantLightbar({
    super.key,
    required this.activity,
    required this.height,
  });

  final AssistActivity activity;

  /// Logical pixels. The Nest's own listening affordance is a thin band; 4dp
  /// reads clearly without stealing the clock's space.
  final double height;

  @override
  State<AssistantLightbar> createState() => _AssistantLightbarState();
}

class _AssistantLightbarState extends State<AssistantLightbar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(AssistantLightbar old) {
    super.didUpdateWidget(old);
    if (old.activity != widget.activity) _sync();
  }

  void _sync() {
    if (widget.activity == AssistActivity.idle) {
      // Stop the clock but keep the controller's value, so a resume starts
      // from where it was rather than snapping back to 0.
      _c.stop();
      if (mounted) setState(() {});
    } else {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => CustomPaint(
            painter: _LightbarPainter(
              phase: _c.value,
              activity: widget.activity,
            ),
            size: Size.infinite,
            // `true` while active so Flutter keeps the layer and does not
            // rebuild the raster tree when the bar starts moving.
            isComplex: false,
            willChange: widget.activity != AssistActivity.idle,
          ),
        ),
      ),
    );
  }
}

class _LightbarPainter extends CustomPainter {
  _LightbarPainter({required this.phase, required this.activity});

  final double phase;
  final AssistActivity activity;

  // Google's Assistant spectrum, in order.
  static const List<Color> _spectrum = [
    Color(0xFF4285F4), // blue
    Color(0xFFEA4335), // red
    Color(0xFFFBBC04), // yellow
    Color(0xFF34A853), // green
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final rect = Rect.fromLTWH(0, 0, size.width, h);

    if (activity == AssistActivity.idle) {
      // Idle is a *visible* resting state, not an invisible one: a very faint
      // band so the user can see where the affordance lives. It does not
      // animate and it does not brighten, so nothing here can be mistaken for
      // the assistant responding.
      canvas.drawRect(
        rect,
        Paint()..color = const Color(0xFF5F6368).withValues(alpha: 0.10),
      );
      return;
    }

    // Speaking is a different rhythm from listening: a slow breath rather than
    // a travelling sweep, so the two are distinguishable at a glance and not
    // just by reading the label.
    final travelling = activity != AssistActivity.speaking;

    final Paint paint;
    if (travelling) {
      // Sweeping: the spectrum slides across a three-times-wide shader so the
      // gradient has somewhere to travel to without popping at the edges.
      paint = Paint()
        ..shader = LinearGradient(
          colors: _spectrum,
          stops: const [0.0, 0.34, 0.67, 1.0],
        ).createShader(
          Rect.fromLTWH(
            -size.width * 0.5 + phase * size.width * 2,
            0,
            size.width * 3,
            h,
          ),
        );
    } else {
      // Speaking: a slow breath — opacity only, no motion, so the two active
      // states are distinguishable without reading the label.
      final t = (math.sin(phase * math.pi * 2) + 1) / 2;
      final stops = <Color>[
        for (final c in _spectrum)
          Color.lerp(c.withValues(alpha: 0.25), c, t)!,
      ];
      paint = Paint()
        ..shader = LinearGradient(colors: stops).createShader(rect);
    }

    canvas.drawRect(rect, paint);

    // A soft falloff below the bar so it glows onto the content rather than
    // sitting on top of it as a hard-edged stripe. Two cheap gradient rects —
    // no blur filter, which would force an offscreen layer every frame.
    final falloff = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          _spectrum[0].withValues(alpha: activity == AssistActivity.speaking ? 0.18 : 0.30),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, h, size.width, h * 2.2));
    canvas.drawRect(Rect.fromLTWH(0, h, size.width, h * 2.2), falloff);
  }

  @override
  bool shouldRepaint(covariant _LightbarPainter old) =>
      old.activity != activity || old.phase != phase;
}