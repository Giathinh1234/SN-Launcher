import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// All geometry in this app is authored against the Google Nest Hub's native
/// canvas: **1024 x 600 logical pixels** (1st gen / 2nd gen Nest Hub).
///
/// The Nest Hub Max is 1280 x 800 — exactly 1.25x — so every constant measured
/// on one device scales identically onto the other. Everything below was
/// extracted by perspective-correcting real photographs of the device back onto
/// the flat 1024x600 / 1280x800 canvas and measuring pixel runs.
///
/// [NestMetrics.of] turns those design constants into real pixels for whatever
/// screen the app lands on, so the same build is correct on a 7" Nest Hub, a
/// Raspberry Pi kiosk, a 4GB Android tablet and a 27" desktop monitor.
class NestMetrics {
  /// Native design canvas of the reference device.
  static const Size designSize = Size(1024, 600);

  final Size size;

  /// Uniform scale that makes the design canvas fit. Element sizes, font sizes
  /// and paddings all multiply by this so the UI keeps its proportions.
  final double u;

  /// Height of the home content block, in design units.
  static const double homeContentHeight = 600;

  // ───────────────────────────────────────────────────────────── HOME SCREEN
  /// Distance from the left edge to the clock block.
  ///
  /// Calibrated so the rendered "0" of "09:45" starts at x=69, matching the
  /// device (the glyph itself carries a small left sidebearing on top of this).
  static const double homeMarginX = 66;

  /// The photo-frame title is right-aligned slightly closer to the edge than
  /// the clock is on the left — measured right edge x=973 on the device.
  static const double albumTitleMarginX = 52;

  /// Bottom edge of the clock's text line box.
  ///
  /// Calibrated against rendered output rather than derived: the digit block
  /// measures 61px and its baseline sits 13px above the bottom of the line box
  /// (Google Sans' ascent is 0.966 em, which is *taller* than the 1.0 em line
  /// height forced on it, so the box bottom sits below the baseline).
  ///
  /// Chosen so the digit block lands at y=461..521, exactly where the device's
  /// clock sits.
  static const double clockTextBoxBottomY = 534;

  /// Cap height of the big clock digits measured 61px.
  ///
  /// Solved empirically against rendered output: at 85px Google Sans produced a
  /// 64px digit block, so the size is scaled by 61/64.
  static const double clockFontSize = 81;

  /// Google Sans sets its digits at 0.643 em advance, which is wider than the
  /// Nest's clock. Solving `ink = 2.513 * fontSize + 4 * letterSpacing = 195`
  /// (the device's measured run for "09:45") gives the tracking below.
  static const double clockLetterSpacing = -2.15;

  /// Date line.
  ///
  /// Measured: "Thu, May 26" spans x=84..203 (**120px**) with a cap block of
  /// y=422..~440. Google Sans sets that string at 5.333 em advance, so the size
  /// falls out at ~23px — noticeably smaller than it looks at a glance.
  static const double dateFontSize = 23;
  static const double dateLetterSpacing = 0.2;

  /// Bottom edge of the date's text line box, calibrated so the cap block lands
  /// at y=422 as on the device.
  static const double dateTextBoxBottomY = 445;

  /// Gap between the end of "09:45" and the weather glyph.
  static const double clockToWeatherGap = 26;
  /// Weather glyph box: measured 30 x 22px.
  static const double weatherIconW = 30;
  static const double weatherIconH = 22;
  /// Gap between the weather glyph and the temperature text.
  static const double weatherToTempGap = 9;
  /// Temperature cap height measured 25px -> ~35px em.
  static const double tempFontSize = 35;
  static const double tempLetterSpacing = 0;

  /// Photo-frame album title, bottom right.
  ///
  /// Measured "Recent highlights" spans x=855..973 — **119px** wide. Google
  /// Sans sets that string at 7.746 em advance, which puts it at ~15.5px.
  /// It is markedly smaller than it looks; 25px overshoots by 60%.
  static const double albumTitleFontSize = 15;
  /// Baseline of the album title. Measured y=541.
  static const double albumTitleBaselineY = 541;

  // ────────────────────────────────────────────────────── DRAG HANDLE / PILL
  /// The persistent bottom-centre "grabber". Measured on the 1280x800 Max:
  /// 51 x 7 px -> 41 x 5.6 on the 1024x600 canvas.
  static const double handleW = 41;
  static const double handleH = 5.6;
  /// On the home screen the handle centre measured at y=563.5 (+5.5) -> 569.
  static const double homeHandleCenterY = 569;

  // ────────────────────────────────────────────────── QUICK SETTINGS SHEET
  /// The sheet's top edge sits at 397/800 of the Max screen = 49.6%.
  static const double sheetTopFraction = 0.496;

  /// Positions *inside* the sheet are expressed as fractions of the sheet's
  /// own height, not as absolute offsets.
  ///
  /// This matters: the Nest Hub is 1024x600 (1.707) and the Hub Max is
  /// 1280x800 (1.600) — they share a 1.25x width scale but a 1.333x height
  /// scale. Copying the Max's pixel offsets onto the Hub's canvas with a single
  /// uniform factor lands the rows ~24px too low. Fractions are stable across
  /// both, and across any odd-shaped screen this runs on.
  static const double appRowCenterFraction = 0.347;
  static const double sheetDividerFraction = 0.573;
  static const double qsRowCenterFraction = 0.824;
  static const double handleFraction = 0.072;

  /// App row: circular badges measured 100px across on the Max.
  static const double appBadgeSize = 80;
  /// Measured spacing between adjacent app slots: 148px on the Max.
  static const double appRowSpacing = 118;
  /// Side padding of the sheet content. The first app badge's left edge
  /// measures x=51 on the Max -> ~41 design px.
  static const double sheetPaddingX = 41;
  /// Width reserved for the "See all" pill. Measured x=965..1215 on the Max.
  static const double seeAllWidth = 200;
  static const double seeAllHeight = 56;

  /// Quick-settings glyphs measured 50px on the Max.
  static const double qsGlyphSize = 40;

  // ──────────────────────────────────────────────────────── LAUNCHER GRID
  /// "See all" opens the full grid: 6 columns on the Max.
  static const int gridColumns = 6;
  static const double gridCellHeight = 118;
  static const double gridLabelFontSize = 21;
  static const double gridIconSize = 68;


  const NestMetrics._(this.size, this.u);

  factory NestMetrics.of(BuildContext context) {
    final mq = MediaQuery.maybeOf(context);
    final size = mq?.size ?? designSize;
    return NestMetrics.forSize(size);
  }

  factory NestMetrics.forSize(Size size) {
    final u = math.min(
      size.width / designSize.width,
      size.height / designSize.height,
    );
    return NestMetrics._(size, u);
  }

  /// Extra horizontal breathing room on screens that are wider (relative to
  /// height) than 16:9. Keeps the grid from stretching absurdly on a monitor.
  double get aspectExtra =>
      math.max(0, (size.width / size.height) - (designSize.width / designSize.height));

  double px(double designValue) => designValue * u;

  double get marginX => px(homeMarginX);
  double get clockFontSizePx => px(clockFontSize);
  double get dateFontSizePx => px(dateFontSize);
  double get tempFontSizePx => px(tempFontSize);
  double get albumTitleFontSizePx => px(albumTitleFontSize);

  double get sheetHeight => size.height * sheetTopFraction;
  double get sheetTop => size.height - sheetHeight;

  // ── Sheet-local coordinates ──────────────────────────────────────────────
  // The sheet's contents sit in a Stack that is itself placed at [sheetTop],
  // so everything inside it is measured *down from the sheet's own top edge*,
  // not from the top of the screen.

  double get sheetLocalAppRowCenter => sheetHeight * appRowCenterFraction;
  double get sheetLocalDividerY => sheetHeight * sheetDividerFraction;
  double get sheetLocalQsRowCenter => sheetHeight * qsRowCenterFraction;
  double get sheetLocalHandleY => sheetHeight * handleFraction;

}