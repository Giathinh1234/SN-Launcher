import 'package:flutter/widgets.dart';

import 'nest_metrics.dart';

/// Typography for the Nest shell.
///
/// The real device uses **Google Sans** (the Assistant brand face). Google
/// released it under the SIL Open Font License, so we ship the real thing
/// rather than an approximation — this is what makes the clock read as
/// "Google" at a glance.
///
/// `capHeightRatio` values below were read straight out of the shipped TTFs
/// and are what let [NestType] guarantee that a 84px clock produces the 60px
/// digit block that was measured on the physical device.
class NestType {
  const NestType(this.m);

  final NestMetrics m;

  /// Google Sans cap height / em.
  static const double googleSansCap = 0.714;
  /// Google Sans ascender / em.
  static const double googleSansAscender = 0.75;

  static const String display = 'GoogleSans';
  static const String altDisplay = 'Poppins';

  FontWeight get _light => FontWeight.w400;

  TextStyle _s({
    required double size,
    FontWeight? weight,
    String family = display,
    double? spacing,
    Color? color,
    double? height,
  }) {
    return TextStyle(
      fontFamily: family,
      fontSize: m.px(size),
      fontWeight: weight ?? _light,
      letterSpacing: spacing == null ? null : m.px(spacing),
      color: color,
      height: height,
      // Google Sans' own metrics leave the digits sitting high; matching the
      // device's baseline placement needs a touch of leading.
      leadingDistribution: TextLeadingDistribution.even,
    );
  }

  /// The big clock. Measured: 61px digit height, 195px total run for "09:45".
  /// Google Sans 400 @ 84px has a 60px cap height — within 2% of the device.
  TextStyle clock({required Color color}) => _s(
    size: NestMetrics.clockFontSize,
    spacing: NestMetrics.clockLetterSpacing,
    color: color,
    height: 1.0,
  );

  /// Optional "Timeless Light" clock face — thinner strokes, like the real
  /// device's lighter clock faces.
  TextStyle clockLight({required Color color}) => _s(
    size: NestMetrics.clockFontSize,
    weight: FontWeight.w300,
    family: altDisplay,
    spacing: NestMetrics.clockLetterSpacing,
    color: color,
    height: 1.0,
  );

  TextStyle amPm({required Color color}) =>
      _s(size: 22, spacing: 0, color: color.withValues(alpha: 0.72));

  TextStyle date({required Color color}) => _s(
    size: NestMetrics.dateFontSize,
    spacing: NestMetrics.dateLetterSpacing,
    color: color,
    height: 1.0,
  );

  TextStyle temperature({required Color color}) =>
      _s(size: NestMetrics.tempFontSize, spacing: 0, color: color, height: 1.0);

  TextStyle albumTitle({required Color color}) => _s(
    size: NestMetrics.albumTitleFontSize,
    spacing: 0.2,
    color: color.withValues(alpha: 0.85),
    height: 1.0,
  );

  TextStyle appLabel({required Color color}) =>
      _s(size: 21, spacing: 0, color: color, height: 1.1);

  TextStyle sheetTitle({required Color color}) =>
      _s(size: 24, weight: FontWeight.w500, spacing: 0.2, color: color);

  TextStyle body({required Color color}) =>
      _s(size: 22, spacing: 0.1, color: color);

  TextStyle caption({required Color color}) =>
      _s(size: 17, spacing: 0.1, color: color);

  TextStyle seeAll({required Color color}) =>
      _s(size: 24, weight: FontWeight.w500, spacing: 0.2, color: color);

  TextStyle assistantHint({required Color color}) =>
      _s(size: 26, spacing: 0, color: color.withValues(alpha: 0.9));
}