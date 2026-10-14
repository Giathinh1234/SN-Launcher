import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/nest_action.dart';
import '../theme/ambient_palette.dart';
import '../theme/nest_metrics.dart';
import '../theme/nest_type.dart';
import 'ambient_background.dart';
import 'nest_glyphs.dart';

/// The swipe-up bottom sheet: a row of circular app badges plus the quick
/// settings strip.
///
/// Geometry is pinned to the device, measured on a rectified 1280x800 Nest Hub
/// Max photograph and divided by 1.25 to land on the 1024x600 canvas:
///
///   sheet top .................. 49.6% of screen height
///   app badge diameter ........ 80
///   app row centre ............ 126 below the sheet top
///   divider .................... 204 below the sheet top
///   quick-setting glyph ....... 40, centres 285 below the sheet top
///   side padding .............. 48
class LauncherSheet extends StatelessWidget {
  const LauncherSheet({
    super.key,
    required this.metrics,
    required this.palette,
    required this.progress,
    required this.suggested,
    required this.quickSettings,
    required this.brightness,
    required this.volume,
    required this.cameraEnabled,
    required this.onActionTap,
    required this.onSeeAll,
    required this.onQuickSettingTap,
    required this.onBrightnessDrag,
    required this.onVolumeDrag,
  });

  final NestMetrics metrics;
  final AmbientPalette palette;

  /// 0 = fully closed, 1 = fully open.
  final double progress;

  final List<NestAction> suggested;
  final List<QuickSetting> quickSettings;
  final double brightness;
  final double volume;
  final bool cameraEnabled;

  final ValueChanged<NestAction> onActionTap;
  final VoidCallback onSeeAll;
  final void Function(QuickSettingKind) onQuickSettingTap;
  final ValueChanged<double> onBrightnessDrag;
  final ValueChanged<double> onVolumeDrag;

  @override
  Widget build(BuildContext context) {
    final badge = metrics.px(NestMetrics.appBadgeSize);
    final glyph = metrics.px(NestMetrics.qsGlyphSize);
    final padding = metrics.px(NestMetrics.sheetPaddingX);
    final sheetH = metrics.sheetHeight;

    // The sheet tracks the finger 1:1 and slides back off the bottom edge when
    // dismissed. Translating (rather than fading) is what the real device does,
    // and it keeps the closed state costing literally nothing to composite.
    final lift = (1 - progress.clamp(0.0, 1.0)) * sheetH;

    return IgnorePointer(
      ignoring: progress < 0.02,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          height: sheetH,
          width: metrics.size.width,
          child: Transform.translate(
            offset: Offset(0, lift),
            // The sheet's contents rasterise once into their own layer and are
            // then only blitted. Without this the badge row, the divider and
            // the seven quick-setting glyphs all re-rasterise on every frame of
            // the drag, which is what tipped the animation over the 60 Hz frame
            // budget on a UNISOC T610.
            child: RepaintBoundary(
              child: ClipRRect(
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(metrics.px(28)),
                topRight: Radius.circular(metrics.px(28)),
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(color: palette.surface),
                child: Stack(
                  children: [
                    // Drag handle, 23 design px below the sheet top.
                    Positioned(
                      top: metrics.sheetLocalHandleY,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: DragHandle(
                          color: palette.onSurfaceStrong,
                          scale: metrics.u,
                        ),
                      ),
                    ),

                    // App row. Offsets are sheet-relative because this Stack
                    // already lives inside the sheet's own coordinate space.
                    Positioned(
                      top: metrics.sheetLocalAppRowCenter - badge / 2,
                      left: padding,
                      right: padding,
                      height: badge,
                      child: Row(
                        children: [
                          // The device spaces the six badges at a fixed pitch
                          // (~148px on the Max) rather than stretching them to
                          // fill the row; the "See all" pill then sits hard
                          // against the right edge.
                          for (var i = 0; i < suggested.length && i < 6; i++) ...[
                            if (i > 0)
                              SizedBox(
                                width: (metrics.px(NestMetrics.appRowSpacing) - badge)
                                    .clamp(0.0, double.infinity),
                              ),
                            _PressableBadge(
                              action: suggested[i],
                              size: badge,
                              onTap: () => onActionTap(suggested[i]),
                            ),
                          ],
                          const Spacer(),
                          _SeeAllPill(
                            width: metrics.px(NestMetrics.seeAllWidth),
                            height: metrics.px(NestMetrics.seeAllHeight),
                            scale: metrics.u,
                            palette: palette,
                            onTap: onSeeAll,
                          ),
                        ],
                      ),
                    ),

                    // Hairline divider.
                    Positioned(
                      top: metrics.sheetLocalDividerY,
                      left: padding,
                      right: padding,
                      child: SizedBox(
                        height: 1,
                        child: ColoredBox(
                          color: palette.onSurfaceStrong.withValues(alpha: 0.10),
                        ),
                      ),
                    ),

                    // Quick settings.
                    Positioned(
                      top: metrics.sheetLocalQsRowCenter - glyph / 2,
                      left: 0,
                      right: 0,
                      height: glyph,
                      child: Row(
                        children: [
                          for (final qs in quickSettings)
                            Expanded(
                              child: Center(
                                child: _QuickTile(
                                  kind: qs.kind,
                                  size: glyph,
                                  color: palette.onSurfaceStrong,
                                  brightness: brightness,
                                  volume: volume,
                                  cameraEnabled: cameraEnabled,
                                  onTap: () => onQuickSettingTap(qs.kind),
                                  onSlide: (delta) => switch (qs.kind) {
                                    QuickSettingKind.brightness =>
                                      onBrightnessDrag(delta),
                                    QuickSettingKind.volume => onVolumeDrag(delta),
                                    _ => onQuickSettingTap(qs.kind),
                                  },
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The 3x3 dot grid on the "See all" pill, drawn to match the device rather
/// than borrowing a Material icon.
class _GridDotsPainter extends CustomPainter {
  _GridDotsPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width * 0.085;
    final step = size.width * 0.31;
    final c = Offset(size.width / 2, size.height / 2);
    final paint = Paint()..color = color;
    for (var x = 0; x < 3; x++) {
      for (var y = 0; y < 3; y++) {
        canvas.drawCircle(
          c + Offset((x - 1) * step, (y - 1) * step),
          r,
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GridDotsPainter old) => old.color != color;
}

/// The rounded "See all" pill that opens the full alphabetical grid.
/// Google blue 500 — the label colour the device uses on the See all pill.
const Color kSeeAllBlue = Color(0xFF4285F4);

class _SeeAllPill extends StatelessWidget {
  const _SeeAllPill({
    required this.width,
    required this.height,
    required this.scale,
    required this.palette,
    required this.onTap,
  });

  final double width;
  final double height;
  final double scale;
  final AmbientPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = palette.onSurfaceStrong;
    return PressableScale(
      onTap: onTap,
      child: Container(
        width: width,
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fg.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(height / 2),
          border: Border.all(color: fg.withValues(alpha: 0.10)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            CustomPaint(
              size: Size.square(22 * scale),
              painter: _GridDotsPainter(fg),
            ),
            SizedBox(width: 10 * scale),
            Text(
              'See all',
              style: TextStyle(
                fontFamily: NestType.display,
                fontSize: 24 * scale,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.2 * scale,
                color: palette.isDark ? const Color(0xFF8AB4F8) : kSeeAllBlue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Press-scale feedback. Cheaper and calmer than a Material ripple and closer
/// to how the device actually responds.
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    required this.onTap,
    this.pressedScale = 0.9,
    this.onPan,
  });

  final Widget child;
  final VoidCallback onTap;
  final double pressedScale;
  final void Function(double dx)? onPan;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      onHorizontalDragUpdate:
          widget.onPan == null ? null : (d) => widget.onPan!(d.delta.dx),
      child: AnimatedScale(
        scale: _down ? widget.pressedScale : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

class _PressableBadge extends StatelessWidget {
  const _PressableBadge({required this.action, required this.size, required this.onTap});

  final NestAction action;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: NestAppBadge(action: action, size: size),
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({
    required this.kind,
    required this.size,
    required this.color,
    required this.brightness,
    required this.volume,
    required this.cameraEnabled,
    required this.onTap,
    required this.onSlide,
  });

  final QuickSettingKind kind;
  final double size;
  final Color color;
  final double brightness;
  final double volume;
  final bool cameraEnabled;
  final VoidCallback onTap;
  final void Function(double dx) onSlide;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      pressedScale: 0.86,
      onPan: onSlide,
      child: Stack(
        alignment: Alignment.center,
        children: [
          QuickSettingGlyph(kind: kind, color: color, size: size),
          if (kind == QuickSettingKind.brightness)
            _LevelRing(level: brightness, color: color, size: size),
          if (kind == QuickSettingKind.volume)
            _LevelRing(level: volume, color: color, size: size),
        ],
      ),
    );
  }
}

/// Thin arc that fills as a slider is dragged.
class _LevelRing extends StatelessWidget {
  const _LevelRing({required this.level, required this.color, required this.size});

  final double level;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox.square(
        dimension: size * 1.3,
        child: CustomPaint(painter: _RingPainter(level: level, color: color)),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.level, required this.color});
  final double level;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - size.width * 0.03;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.035
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(
      center,
      radius,
      stroke..color = color.withValues(alpha: 0.20),
    );

    if (level > 0.001) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        math.pi * 2 * level.clamp(0.0, 1.0),
        false,
        stroke..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.level != level;
}