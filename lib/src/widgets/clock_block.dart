import 'package:flutter/material.dart';

import '../services/clock_service.dart';
import '../services/weather_service.dart';
import '../theme/ambient_palette.dart';
import '../theme/nest_metrics.dart';
import '../theme/nest_type.dart';
import 'weather_glyph.dart';

/// The clock / photo-frame home block.
///
/// Every number below was measured off a perspective-corrected photograph of a
/// real Nest Hub, rectified onto its native 1024x600 panel:
///
///   * clock digit block ......... 61 px tall
///   * "09:45" total run ........ 195 px
///   * date line ................. cap height 18 px
///   * temperature ............... cap height 25 px
///   * left margin ............... 60 px
///
/// Google Sans' cap height is 0.714 em, so 84 px lands within 2% of the
/// device's 61 px digit block.
class ClockBlock extends StatelessWidget {
  const ClockBlock({
    super.key,
    required this.metrics,
    required this.type,
    required this.palette,
    required this.weather,
    required this.now,
    this.use24Hour = true,
    this.showSeconds = false,
    this.lightFace = false,
    this.animateWeather = true,
    this.albumTitle,
  });

  final NestMetrics metrics;
  final NestType type;
  final AmbientPalette palette;
  final WeatherNow weather;
  final DateTime now;
  final bool use24Hour;
  final bool showSeconds;

  /// "Timeless Light" clock face — thinner strokes, like the device's lighter
  /// faces.
  final bool lightFace;

  /// Whether the weather glyph animates. Disabled for screenshots.
  final bool animateWeather;

  /// Bottom-right album / photo-frame title.
  final String? albumTitle;

  @override
  Widget build(BuildContext context) {
    final color = palette.onSurface;
    final timeText =
        ClockService.time(now, use24Hour: use24Hour, withSeconds: showSeconds);

    // Wrap the whole block so the once-a-minute clock tick repaints only this
    // subtree instead of the entire screen.
    return RepaintBoundary(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Date line. Positioned independently of the clock rather than
          // stacked in a Column, so each can be calibrated against the device
          // without the other's metrics moving it.
          Positioned(
            left: metrics.marginX,
            bottom: metrics.size.height - metrics.px(NestMetrics.dateTextBoxBottomY),
            child: Text(ClockService.nestDate(now), style: type.date(color: color)),
          ),

          // Big clock + weather, baseline-aligned on one row.
          Positioned(
            left: metrics.marginX,
            bottom: metrics.size.height - metrics.px(NestMetrics.clockTextBoxBottomY),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  timeText,
                  style: lightFace
                      ? type.clockLight(color: color)
                      : type.clock(color: color),
                ),
                if (!use24Hour) ...[
                  SizedBox(width: metrics.px(6)),
                  Text(ClockService.meridiem(now), style: type.amPm(color: color)),
                ],
                SizedBox(width: metrics.px(NestMetrics.clockToWeatherGap)),
                WeatherGlyph(
                  condition: weather.condition,
                  color: color,
                  animate: animateWeather,
                  size: Size(
                    metrics.px(NestMetrics.weatherIconW),
                    metrics.px(NestMetrics.weatherIconH * 2.0),
                  ),
                ),
                SizedBox(width: metrics.px(NestMetrics.weatherToTempGap)),
                Text(weather.shortLabel, style: type.temperature(color: color)),
              ],
            ),
          ),
          if (albumTitle != null && albumTitle!.isNotEmpty)
            Positioned(
              right: metrics.px(NestMetrics.albumTitleMarginX),
              bottom:
                  metrics.size.height - metrics.px(NestMetrics.albumTitleBaselineY),
              child: Text(
                albumTitle!,
                style: type.albumTitle(color: color),
                textAlign: TextAlign.right,
              ),
            ),
        ],
      ),
    );
  }
}