import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/nest_action.dart';
import '../theme/nest_icons.dart';

/// Every launcher glyph is drawn as vector geometry instead of shipped as a
/// PNG.
///
/// This matters twice over on e-waste hardware:
///  * no bitmap decode — a 24-icon PNG set costs several MB of decoded texture
///    memory that the GPU has to hold resident, which is exactly what a 1–2 GB
///    device cannot spare;
///  * resolution-independent, so the same icons are pixel-sharp on a 7" Nest
///    Hub panel *and* a 4K desktop monitor with no extra assets.
///
/// Glyph geometry is modelled on the shapes visible in the device's own
/// launcher: rounded-square containers, filled brand discs, monoline strokes.
///
/// Shared by both painters so the settings gear in the quick-settings row and
/// the one in the app drawer are the same shape rather than two hand-written
/// approximations that slowly drift apart.
///
/// Four points per tooth, not two, so the tips are *flat*. Two points gives
/// triangular teeth, which reads as a star or a flower rather than a gear.
Path _gearPath({
  int teeth = 8,
  double outer = 0.46,
  double inner = 0.33,
  double tip = 0.42,
}) {
  final path = Path();
  final step = math.pi * 2 / teeth;
  for (var i = 0; i < teeth; i++) {
    final a = i * step;
    final half = step / 2;
    final halfTip = half * tip;
    for (final (angle, radius) in [
      (a - half, inner),
      (a - halfTip, outer),
      (a + halfTip, outer),
      (a + half, inner),
    ]) {
      final p = Offset(math.cos(angle) * radius, math.sin(angle) * radius);
      if (i == 0 && angle == a - half) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
  }
  return path..close();
}

class NestGlyphPainter extends CustomPainter {
  NestGlyphPainter({
    required this.kind,
    required this.color,
    this.backdrop,
    this.strokeScale = 1.0,
  });

  final NestIconKind kind;
  final Color color;

  /// Colour of the disc the glyph sits on. Interior detail (the ruled lines on
  /// News, the tick inside Reminders) is knocked out in this colour, otherwise
  /// white-on-white detail simply disappears.
  final Color? backdrop;

  final double strokeScale;

  Color get _knockout => backdrop ?? color;

  /// The generic (non-brand) launcher icons now come from Material Symbols.
  ///
  /// Brand marks are deliberately left as drawn paths: Spotify, Netflix and
  /// YouTube have their own logos, and substituting an approximation of a logo
  /// with another approximation of a logo is strictly worse than either. But a
  /// generic "Calendar" or "Settings" has no identity to protect, and Google's
  /// own glyph for it is better than anything hand-plotted — that mismatch
  /// between Google's brand tiles and everything else was most of what made
  /// the grid read as cheap.
  ///
  /// `null` means "draw it here instead".
  static IconData? symbolFor(NestIconKind kind) => switch (kind) {
        NestIconKind.calendar => NestIcons.CalendarMonth,
        NestIconKind.camera => NestIcons.PhotoCamera,
        NestIconKind.cast => NestIcons.Cast,
        NestIconKind.clock => NestIcons.Schedule,
        NestIconKind.contacts => NestIcons.Person,
        NestIconKind.games => NestIcons.SportsEsports,
        NestIconKind.home => NestIcons.Home,
        NestIconKind.meet => NestIcons.Videocam,
        NestIconKind.music => NestIcons.MusicNote,
        NestIconKind.news => NestIcons.Article,
        NestIconKind.photos => NestIcons.Collections,
        NestIconKind.podcasts => NestIcons.Podcasts,
        NestIconKind.reminders => NestIcons.EventAvailable,
        NestIconKind.settings => NestIcons.Settings,
        NestIconKind.stories => NestIcons.PhotoAlbum,
        NestIconKind.timer => NestIcons.Timer,
        NestIconKind.weather => NestIcons.WbSunny,
        NestIconKind.youtube => NestIcons.PlayArrow,
        NestIconKind.youtubeTv => NestIcons.Tv,
        NestIconKind.assistant => NestIcons.AutoAwesome,
        NestIconKind.broadcast => NestIcons.CastConnected,
        NestIconKind.zoom => NestIcons.Videocam,
        // Netflix and Pandora are wordmarks, not glyphs; they keep their paths.
        NestIconKind.netflix => null,
        NestIconKind.pandora => null,
      };

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);
    final c = Offset(size.width / 2, size.height / 2);

    final symbol = symbolFor(kind);
    if (symbol != null) {
      _paintSymbol(canvas, c, s, symbol);
      return;
    }

    canvas.save();
    canvas.translate(c.dx, c.dy);

    // NOTE: the canvas below is scaled by `s`, so stroke widths are expressed
    // in the glyph's local units. Scaling them by `s` as well would square the
    // factor and balloon every stroked glyph.
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.072 * strokeScale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    void fill(Path p) {
      canvas.drawPath(p, Paint()..color = color);
    }

    // All glyphs are authored in a -0.5..0.5 box then scaled.
    canvas.scale(s, s);

    switch (kind) {
      case NestIconKind.assistant:
        // Four-dot Assistant mark.
        final r = 0.105;
        final d = 0.205;
        for (final o in [Offset(-d, -d), Offset(d, -d), Offset(-d, d), Offset(d, d)]) {
          canvas.drawCircle(o, r, Paint()..color = color);
        }

      case NestIconKind.broadcast:
        final r = 0.06;
        canvas.drawCircle(Offset.zero, r, Paint()..color = color);
        for (final rad in [0.19, 0.31]) {
          canvas.drawArc(
            Rect.fromCircle(center: Offset.zero, radius: rad),
            -math.pi / 2 - 0.9, 1.8, false, stroke..strokeWidth = 0.055,
          );
          canvas.drawArc(
            Rect.fromCircle(center: Offset.zero, radius: rad),
            math.pi / 2 - 0.9, 1.8, false, stroke..strokeWidth = 0.055,
          );
        }

      case NestIconKind.calendar:
        final r = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: 0.78, height: 0.72),
          const Radius.circular(0.13),
        );
        fill(Path()..addRRect(r));
        // Binder rings on top of the date block.
        for (final x in [-0.2, 0.2]) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(x - 0.045, -0.42, 0.09, 0.22), const Radius.circular(0.045)),
            Paint()..color = color,
          );
        }

      case NestIconKind.camera:
        fill(Path()
          ..addRRect(RRect.fromRectAndRadius(
              Rect.fromCenter(center: Offset.zero, width: 0.88, height: 0.62),
              const Radius.circular(0.13))));
        // Lens cone on the trailing edge.
        fill(Path()
          ..moveTo(0.30, -0.31)
          ..lineTo(0.44, -0.31)
          ..lineTo(0.50, -0.14)
          ..lineTo(0.30, -0.14)
          ..close());

      case NestIconKind.cast:
        // Chromecast-style: filled screen with a signal arc from the corner.
        fill(Path()
          ..addRRect(RRect.fromRectAndRadius(
              Rect.fromCenter(center: const Offset(0, 0.02), width: 0.86, height: 0.58),
              const Radius.circular(0.1))));
        // Signal arcs radiating from the lower-left corner.
        for (final r in [0.22, 0.36, 0.50]) {
          canvas.drawArc(
            Rect.fromCircle(center: const Offset(-0.46, 0.46), radius: r),
            math.pi, math.pi / 2, false,
            stroke..strokeWidth = 0.075,
          );
        }
        canvas.drawCircle(const Offset(-0.46, 0.46), 0.09,
            Paint()..color = color);

      case NestIconKind.clock:
        canvas.drawCircle(Offset.zero, 0.42, stroke..strokeWidth = 0.075);
        canvas.drawLine(const Offset(0, -0.22), const Offset(0, 0.02), stroke);
        canvas.drawLine(const Offset(0, 0.02), const Offset(0.19, 0.12), stroke);

      case NestIconKind.contacts:
        canvas.drawCircle(const Offset(0, -0.16), 0.19, Paint()..color = color);
        fill(Path()
          ..moveTo(-0.42, 0.44)
          ..cubicTo(-0.42, 0.08, -0.22, -0.02, 0, -0.02)
          ..cubicTo(0.22, -0.02, 0.42, 0.08, 0.42, 0.44)
          ..close());

      case NestIconKind.games:
        // D-pad + two action buttons.
        fill(Path()
          ..addRRect(RRect.fromRectAndRadius(
              Rect.fromCenter(center: const Offset(-0.18, 0), width: 0.18, height: 0.6),
              const Radius.circular(0.05)))
          ..addRRect(RRect.fromRectAndRadius(
              Rect.fromCenter(center: const Offset(-0.18, 0), width: 0.6, height: 0.18),
              const Radius.circular(0.05))));
        canvas.drawCircle(const Offset(0.26, -0.18), 0.1, Paint()..color = color);
        canvas.drawCircle(const Offset(0.26, 0.18), 0.1, Paint()..color = color);

      case NestIconKind.home:
        fill(Path()
          ..moveTo(0, -0.42)
          ..lineTo(0.46, 0.02)
          ..lineTo(0.30, 0.02)
          ..lineTo(0.30, 0.42)
          ..lineTo(-0.30, 0.42)
          ..lineTo(-0.30, 0.02)
          ..lineTo(-0.46, 0.02)
          ..close());

      case NestIconKind.meet:
        // Video camera: rounded body + lens wedge.
        fill(Path()
          ..addRRect(RRect.fromRectAndRadius(
              Rect.fromCenter(center: const Offset(-0.12, 0), width: 0.62, height: 0.46),
              const Radius.circular(0.1))));
        fill(Path()
          ..moveTo(0.22, -0.14)
          ..lineTo(0.46, -0.30)
          ..lineTo(0.46, 0.30)
          ..lineTo(0.22, 0.14)
          ..close());

      case NestIconKind.music:
        // Spotify-style three arcs, drawn as strokes.
        for (final inset in [0.16, 0.04, -0.08]) {
          final p = Path()
            ..moveTo(-0.46, inset + 0.12)
            ..cubicTo(-0.1, inset - 0.10, 0.18, inset - 0.06, 0.46, inset + 0.14);
          canvas.drawPath(p, stroke..strokeWidth = 0.085);
        }
        canvas.drawCircle(const Offset(-0.42, 0.30), 0.075, Paint()..color = color);
        canvas.drawCircle(const Offset(0.40, 0.33), 0.075, Paint()..color = color);

      case NestIconKind.netflix:
        // The mark is an N. The previous path was two upright bars, which read
        // as a pause glyph — the diagonal is what makes it an N.
        canvas.drawCircle(Offset.zero, 0.42, stroke..strokeWidth = 0.055);
        const double w = 0.085;
        const double top = -0.24, bottom = 0.24;
        for (final x in [-0.17, 0.17]) {
          canvas.drawLine(
            Offset(x, top),
            Offset(x, bottom),
            stroke..strokeWidth = w,
          );
        }
        canvas.drawLine(
          const Offset(-0.17, -0.24),
          const Offset(0.17, 0.24),
          stroke..strokeWidth = w * 0.82,
        );

      case NestIconKind.news:
        fill(Path()
          ..addRRect(RRect.fromRectAndRadius(
              Rect.fromCenter(center: const Offset(0, 0), width: 0.82, height: 0.74),
              const Radius.circular(0.09))));
        for (final dy in [-0.20, 0.02, 0.24]) {
          canvas.drawLine(Offset(-0.26, dy), Offset(0.26, dy),
              stroke..color = _knockout..strokeWidth = 0.07);
        }

      case NestIconKind.pandora:
        canvas.drawCircle(const Offset(-0.1, 0.06), 0.30, stroke..strokeWidth = 0.08);
        canvas.drawCircle(const Offset(0.02, -0.06), 0.30, stroke..strokeWidth = 0.08);
        canvas.drawCircle(const Offset(0.14, 0.06), 0.30, stroke..strokeWidth = 0.08);

      case NestIconKind.photos:
        // Four-blade pinwheel, each blade a teardrop swung off the centre.
        for (var i = 0; i < 4; i++) {
          canvas.save();
          canvas.rotate(i * math.pi / 2);
          fill(Path()
            ..moveTo(0, 0)
            ..cubicTo(0.20, -0.05, 0.32, -0.18, 0.30, -0.34)
            ..cubicTo(0.12, -0.28, 0.01, -0.15, 0, 0)
            ..close());
          canvas.restore();
        }

      case NestIconKind.podcasts:
        canvas.drawCircle(const Offset(0, -0.30), 0.09, Paint()..color = color);
        fill(Path()
          ..moveTo(-0.17, -0.12)
          ..quadraticBezierTo(0, -0.22, 0.17, -0.12)
          ..lineTo(0.17, 0.02)
          ..cubicTo(0.17, 0.30, 0.09, 0.34, 0, 0.42)
          ..cubicTo(-0.09, 0.34, -0.17, 0.30, -0.17, 0.02)
          ..close());

      case NestIconKind.reminders:
        fill(Path()
          ..addRRect(RRect.fromRectAndRadius(
              Rect.fromCenter(center: Offset.zero, width: 0.72, height: 0.78),
              const Radius.circular(0.16)))
          ..addRRect(RRect.fromRectAndRadius(
              Rect.fromCenter(center: const Offset(0, -0.36), width: 0.26, height: 0.14),
              const Radius.circular(0.07))));
        for (final dy in [-0.12, 0.06]) {
          canvas.drawLine(Offset(-0.18, dy), Offset(0.18, dy),
              stroke..color = _knockout..strokeWidth = 0.07);
        }
        canvas.drawCircle(const Offset(0, -0.18), 0.035,
            Paint()..color = _knockout);

      case NestIconKind.settings:
        // Toothed silhouette, not a sun. A circle plus radiating spokes is
        // indistinguishable from the brightness tile sitting beside it.
        fill(_gearPath());
        // Punch the hub out in the badge colour so it reads as a ring.
        canvas.drawCircle(Offset.zero, 0.16, Paint()..color = _knockout);

      case NestIconKind.stories:
        fill(Path()
          ..addRRect(RRect.fromRectAndRadius(
              Rect.fromCenter(center: Offset.zero, width: 0.78, height: 0.78),
              const Radius.circular(0.12))));
        final p = Path()
          ..moveTo(-0.14, -0.02)
          ..lineTo(-0.02, -0.14)
          ..lineTo(0.14, 0.12)
          ..lineTo(0.02, 0.22)
          ..close();
        canvas.drawPath(p, Paint()..color = _knockout);

      case NestIconKind.timer:
        canvas.drawCircle(Offset.zero, 0.36, stroke);
        canvas.drawLine(const Offset(0, -0.36), const Offset(0, 0.02), stroke);
        canvas.drawLine(const Offset(0, 0.02), const Offset(-0.2, -0.14), stroke);
        canvas.drawLine(const Offset(-0.16, -0.44), const Offset(0.16, -0.44),
            stroke..strokeWidth = 0.06);

      case NestIconKind.weather:
        _sun(canvas, s, color, const Offset(-0.1, -0.12), 0.17);
        fill(Path()
          ..moveTo(-0.36, 0.26)
          ..arcToPoint(const Offset(-0.18, 0.02),
              radius: const Radius.circular(0.19), clockwise: false)
          ..arcToPoint(const Offset(0.10, 0.02),
              radius: const Radius.circular(0.26), clockwise: true)
          ..arcToPoint(const Offset(0.34, 0.26),
              radius: const Radius.circular(0.18), clockwise: true)
          ..close());

      case NestIconKind.youtube:
      case NestIconKind.youtubeTv:
        fill(Path()
          ..addRRect(RRect.fromRectAndRadius(
              Rect.fromCenter(center: Offset.zero, width: 0.9, height: 0.64),
              const Radius.circular(0.18))));
        fill(Path()
          ..moveTo(-0.16, -0.19)
          ..lineTo(0.20, 0)
          ..lineTo(-0.16, 0.19)
          ..close());

      case NestIconKind.zoom:
        canvas.drawCircle(const Offset(-0.06, 0), 0.36, stroke);
        fill(Path()
          ..moveTo(0.16, 0.16)
          ..lineTo(0.44, 0.44)
          ..lineTo(0.44, 0.20)
          ..lineTo(0.22, -0.02)
          ..close());
    }
    canvas.restore();
  }

  void _sun(Canvas canvas, double s, Color color, Offset at, double r) {
    canvas.drawCircle(at, r, Paint()..color = color);
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      // Local glyph units — the canvas is already scaled by `s`.
      ..strokeWidth = 0.05
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4;
      canvas.drawLine(
        at + Offset(math.cos(a), math.sin(a)) * (r + 0.07),
        at + Offset(math.cos(a), math.sin(a)) * (r + 0.17),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(covariant NestGlyphPainter old) =>
      old.kind != kind || old.color != color || old.strokeScale != strokeScale;

  /// Draw a Material Symbols glyph centred in an `s`-sized box.
  ///
  /// A TextPainter rather than an `Icon` widget because this class is a
  /// CustomPainter invoked from the badge's own paint pass — wrapping it in
  /// another widget would add a layer to each of the 31 badges.
  void _paintSymbol(Canvas canvas, Offset centre, double s, IconData icon) {
    final painter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          // 20 of the 24-unit em box, matching Material's own optical margin.
          fontSize: s / 24 * 20,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    painter.paint(
      canvas,
      centre - Offset(painter.width / 2, painter.height / 2),
    );
  }
}

/// Draws the circular brand badge + glyph used throughout the launcher.
class NestAppBadge extends StatelessWidget {
  const NestAppBadge({
    super.key,
    required this.action,
    required this.size,
    this.foreground = Colors.white,
  });

  final NestAction action;
  final double size;

  /// Colour used for the glyph drawn on top of [NestAction.tint].
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: action.tint,
          shape: action.badgeShape == NestBadgeShape.squircle
              ? BoxShape.rectangle
              : BoxShape.circle,
          borderRadius: action.badgeShape == NestBadgeShape.squircle
              ? BorderRadius.circular(size * 0.24)
              : null,
        ),
        child: Center(
          child: CustomPaint(
            size: Size.square(size * 0.62),
            painter: NestGlyphPainter(
              kind: action.icon,
              color: action.badgeColor ?? foreground,
              backdrop: action.tint,
            ),
          ),
        ),
      ),
    );
  }
}

/// Monoline glyph for the quick-settings row (no badge — the device draws
/// these as bare outline icons).
class QuickSettingGlyph extends StatelessWidget {
  const QuickSettingGlyph({super.key, required this.kind, required this.color, required this.size});

  final QuickSettingKind kind;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _QuickSettingPainter(kind, color)),
    );
  }
}

class _QuickSettingPainter extends CustomPainter {
  _QuickSettingPainter(this.kind, this.color);
  final QuickSettingKind kind;
  final Color color;

  /// Google's own glyph for each quick setting.
  ///
  /// These replace hand-drawn paths. The hand-drawn set read as generic
  /// Android: its strokes were uniformly 4.2% of the box with round caps,
  /// which is no real design system's optical weight, and the gear was the
  /// only one that had any character at all. Material Symbols are drawn on a
  /// 24-unit grid with tuned terminals, so the whole row picks up Google's
  /// corner and weight language for free — and the row is now unmistakably
  /// Google rather than "an icon set".
  static IconData iconFor(QuickSettingKind kind) => switch (kind) {
        QuickSettingKind.brightness => NestIcons.Brightness7,
        QuickSettingKind.volume => NestIcons.VolumeUp,
        QuickSettingKind.camera => NestIcons.PhotoCamera,
        // The theme button, not a dark-mode toggle. A sun reads as "make it
        // light"; the sun/moon pair in Google's iconography is a much more
        // recognisable way to say "this changes the look".
        QuickSettingKind.darkTheme => NestIcons.LightMode,
        QuickSettingKind.zoomIn => NestIcons.AutoAwesome,
        QuickSettingKind.feedback => NestIcons.Feedback,
        QuickSettingKind.settings => NestIcons.Settings,
      };

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);
    final c = Offset(size.width / 2, size.height / 2);

    // Material Symbols are authored on a 24x24 em box, so scale that rather
    // than the -0.5..0.5 space the old painters used. 0.86 leaves the optical
    // margin Google's own layouts assume.
    final icon = iconFor(kind);
    final painter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: s / 24 * 20,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    painter.paint(
      canvas,
      c - Offset(painter.width / 2, painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _QuickSettingPainter old) =>
      old.kind != kind || old.color != color;
}