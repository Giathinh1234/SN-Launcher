import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/ambient_palette.dart';

/// The Nest's signature ambient background.
///
/// Deliberately painted as a **single** `CustomPainter` with no child widgets,
/// no images and no blur filters. On a low-end GPU a stack of translucent
/// containers would force an offscreen layer per element; one paint pass with
/// two gradients costs effectively nothing, which is what keeps a 1 GB Android
/// tablet scrolling at 60fps.
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({
    super.key,
    required this.palette,
    required this.brightness,
    this.child,
  });

  final AmbientPalette palette;

  /// 0..1 screen dimming applied on top of the gradient.
  final double brightness;

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _AmbientPainter(palette: palette, brightness: brightness),
        size: Size.infinite,
        isComplex: false,
        willChange: false,
        child: child,
      ),
    );
  }
}

class _AmbientPainter extends CustomPainter {
  _AmbientPainter({required this.palette, required this.brightness});

  final AmbientPalette palette;
  final double brightness;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final stops = palette.backgroundStops();

    // 1. Vertical base gradient.
    //
    // `stops` has to be derived from the colour count. A pinned flat theme
    // returns a single colour, and handing LinearGradient three stops for one
    // colour throws at paint time — which on a device means a red error box
    // where the wallpaper should be.
    final base = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: stops,
        stops: _stopsFor(stops.length),
      ).createShader(rect);
    canvas.drawRect(rect, base);

    // 2. Soft off-centre bloom. The real device's diffuser never produces a
    //    perfectly flat field — there is always a gentle hotspot.
    //
    //    Suppressed on flat palettes. Someone who pinned "White" asked for
    //    white; washing a cream bloom across it is how a UI ends up looking
    //    dirty rather than clean.
    if (!palette.isFlat) {
      final bloomRadius = math.max(size.width, size.height) * 0.75;
      final hotspot = Offset(size.width * 0.5, size.height * 0.42);
      final bloomColor = palette.isDark
          ? const Color(0xFF2A3358)
          : const Color(0xFFFFF6E8);
      canvas.drawCircle(
        hotspot,
        bloomRadius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              bloomColor.withValues(alpha: palette.isDark ? 0.30 : 0.55),
              bloomColor.withValues(alpha: 0.0),
            ],
            stops: const [0.0, 1.0],
          ).createShader(Rect.fromCircle(center: hotspot, radius: bloomRadius)),
      );
    }

    // 3. Brightness dimming (quick-settings slider / night mode).
    if (brightness < 0.999) {
      canvas.drawRect(
        rect,
        Paint()..color = Colors.black.withValues(alpha: (1 - brightness).clamp(0.0, 1.0) * 0.78),
      );
    }
  }

  /// Evenly spread stops, matching the number of colours.
  static List<double> _stopsFor(int n) {
    if (n <= 1) return const [0.0];
    if (n == 2) return const [0.0, 1.0];
    // Three stops: the original shape was [0.0, 0.55, 1.0].
    return const [0.0, 0.55, 1.0];
  }

  @override
  bool shouldRepaint(covariant _AmbientPainter old) =>
      old.brightness != brightness ||
      old.palette.top != palette.top ||
      old.palette.bottom != palette.bottom ||
      old.palette.isDark != palette.isDark;
}

/// The persistent bottom-centre grabber that lives on every screen.
///
/// Measured on the Nest Hub Max: 51 x 7 px on a 1280-wide panel.
class DragHandle extends StatelessWidget {
  const DragHandle({super.key, required this.color, this.scale = 1.0});

  final Color color;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        height: 8 * scale,
        width: 44 * scale,
        child: Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.38),
              borderRadius: BorderRadius.circular(4 * scale),
            ),
            child: SizedBox(width: 41 * scale, height: 5.6 * scale),
          ),
        ),
      ),
    );
  }
}

/// A soft, blurred-free drop shadow used to lift cards off the ambient field.
List<BoxShadow> nestShadow({double elevation = 1, bool dark = false}) {
  final a = (0.06 + elevation * 0.05) * (dark ? 1.6 : 1.0);
  return [
    BoxShadow(
      color: Colors.black.withValues(alpha: a.clamp(0.0, 0.45)),
      blurRadius: 10 * elevation,
      offset: Offset(0, 2 * elevation),
    ),
  ];
}