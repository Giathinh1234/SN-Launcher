import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The ambient colour scheme the Nest Hub paints its whole UI with.
///
/// The real device samples its ambient light sensor and the wall clock to pick
/// a tint, then blends between a warm "daylight" scheme and a cool near-black
/// "night" scheme. Dawn and dusk get an amber wash, midday gets a cool paper
/// white, and late night drops to deep blue.
///
/// [AmbientPalette.at] interpolates continuously so the background drifts with
/// the sun instead of snapping at hour boundaries.
@immutable
class AmbientPalette {
  const AmbientPalette({
    required this.name,
    required this.top,
    required this.bottom,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.surface,
    required this.onSurfaceStrong,
    required this.brightness,
    required this.isNight,
  });

  final String name;

  /// Background gradient, top → bottom.
  final Color top;
  final Color bottom;

  /// Primary foreground (clock, icons).
  final Color onSurface;

  /// Secondary foreground (labels, hints).
  final Color onSurfaceVariant;

  /// Bottom-sheet / card fill.
  final Color surface;

  /// Foreground on top of [surface].
  final Color onSurfaceStrong;

  final Brightness brightness;
  final bool isNight;

  bool get isDark => brightness == Brightness.dark;

  // ── Keyframes ────────────────────────────────────────────────────────────
  // Values chosen by eye against real Nest Hub photographs and Google's own
  // Ambient EQ description ("warm tints at dawn/dusk, cool paper at midday,
  // deep blue at night").

  static const AmbientPalette midnight = AmbientPalette(
    name: 'Midnight',
    top: Color(0xFF070A14),
    bottom: Color(0xFF121A2E),
    onSurface: Color(0xFFEDF1FA),
    onSurfaceVariant: Color(0xFF98A4C0),
    surface: Color(0xFF161E33),
    onSurfaceStrong: Color(0xFFF2F5FC),
    brightness: Brightness.dark,
    isNight: true,
  );

  static const AmbientPalette lateNight = AmbientPalette(
    name: 'Late night',
    top: Color(0xFF0B0F1C),
    bottom: Color(0xFF1B2038),
    onSurface: Color(0xFFE8EDF8),
    onSurfaceVariant: Color(0xFF8E9BB8),
    surface: Color(0xFF1E243C),
    onSurfaceStrong: Color(0xFFEFF3FB),
    brightness: Brightness.dark,
    isNight: true,
  );

  static const AmbientPalette firstLight = AmbientPalette(
    name: 'First light',
    top: Color(0xFF2A2140),
    bottom: Color(0xFF6B4238),
    onSurface: Color(0xFFF6EDE6),
    onSurfaceVariant: Color(0xFFC8B6AE),
    surface: Color(0xFF4A3A45),
    onSurfaceStrong: Color(0xFFFBF5F0),
    brightness: Brightness.dark,
    isNight: false,
  );

  static const AmbientPalette sunrise = AmbientPalette(
    name: 'Sunrise',
    top: Color(0xFF6E4A55),
    bottom: Color(0xFFC98A64),
    onSurface: Color(0xFFFFF6EE),
    onSurfaceVariant: Color(0xFFE3CDBA),
    surface: Color(0xFFB98A72),
    onSurfaceStrong: Color(0xFFFFFAF4),
    brightness: Brightness.light,
    isNight: false,
  );

  static const AmbientPalette morning = AmbientPalette(
    name: 'Morning',
    top: Color(0xFFB9CBDC),
    bottom: Color(0xFFDFE3E4),
    onSurface: Color(0xFF16202E),
    onSurfaceVariant: Color(0xFF4A5768),
    surface: Color(0xFFEFEDE6),
    onSurfaceStrong: Color(0xFF16202E),
    brightness: Brightness.light,
    isNight: false,
  );

  /// The Nest Hub's signature daylight paper white. The quick-settings sheet in
  /// daylight measured (238, 234, 228) straight off a rectified photo.
  static const AmbientPalette daytime = AmbientPalette(
    name: 'Daytime',
    top: Color(0xFFC8D8E6),
    bottom: Color(0xFFEDE8DE),
    onSurface: Color(0xFF11151C),
    onSurfaceVariant: Color(0xFF414C5C),
    surface: Color(0xFFEFEDE6),
    onSurfaceStrong: Color(0xFF11151C),
    brightness: Brightness.light,
    isNight: false,
  );

  static const AmbientPalette afternoon = AmbientPalette(
    name: 'Afternoon',
    top: Color(0xFFCBD5DA),
    bottom: Color(0xFFE8DCCB),
    onSurface: Color(0xFF15181C),
    onSurfaceVariant: Color(0xFF4B5059),
    surface: Color(0xFFF0E9DC),
    onSurfaceStrong: Color(0xFF15181C),
    brightness: Brightness.light,
    isNight: false,
  );

  static const AmbientPalette goldenHour = AmbientPalette(
    name: 'Golden hour',
    top: Color(0xFF8A5A48),
    bottom: Color(0xFFD99456),
    onSurface: Color(0xFFFFF4E8),
    onSurfaceVariant: Color(0xFFDEC5AC),
    surface: Color(0xFFB4794F),
    onSurfaceStrong: Color(0xFFFFFAF2),
    brightness: Brightness.light,
    isNight: false,
  );

  static const AmbientPalette dusk = AmbientPalette(
    name: 'Dusk',
    top: Color(0xFF3A2740),
    bottom: Color(0xFF7B4437),
    onSurface: Color(0xFFF6EAE4),
    onSurfaceVariant: Color(0xFFC5A9A4),
    surface: Color(0xFF53383E),
    onSurfaceStrong: Color(0xFFFCF4F0),
    brightness: Brightness.dark,
    isNight: true,
  );

  static const AmbientPalette night = AmbientPalette(
    name: 'Night',
    top: Color(0xFF141129),
    bottom: Color(0xFF2C2038),
    onSurface: Color(0xFFE9E7F5),
    onSurfaceVariant: Color(0xFF9A94B4),
    surface: Color(0xFF241C33),
    onSurfaceStrong: Color(0xFFF2F0FA),
    brightness: Brightness.dark,
    isNight: true,
  );

  /// Time-ordered keyframes for a full 24h day.
  static const List<({double hour, AmbientPalette palette})> _timeline = [
    (hour: 0, palette: midnight),
    (hour: 4.5, palette: midnight),
    (hour: 6.0, palette: firstLight),
    (hour: 7.0, palette: sunrise),
    (hour: 9.0, palette: morning),
    (hour: 13.0, palette: daytime),
    (hour: 16.5, palette: afternoon),
    (hour: 18.5, palette: goldenHour),
    (hour: 20.0, palette: dusk),
    (hour: 22.0, palette: night),
    (hour: 24, palette: midnight),
  ];

  /// Smoothly interpolated palette for a given wall-clock hour (0..24).
  static AmbientPalette at(double hour, {double ambientBrightness = 0.5}) {
    final h = ((hour % 24) + 24) % 24;
    var i = 0;
    while (i < _timeline.length - 2 && _timeline[i + 1].hour <= h) {
      i++;
    }
    final a = _timeline[i];
    final b = _timeline[i + 1];
    final span = b.hour - a.hour;
    // Smootherstep gives a gentler, more organic ramp than a linear blend.
    final raw = span <= 0 ? 0.0 : (h - a.hour) / span;
    final t = raw * raw * raw * (raw * (raw * 6 - 15) + 10);
    var p = lerpPalette(a.palette, b.palette, t);

    // Ambient light sensor: in a bright room Nest pushes the UI lighter, in a
    // dark room it pushes it darker. `ambientBrightness` is 0 (pitch dark) .. 1.
    p = p.adaptToAmbientLight(ambientBrightness);
    return p;
  }

  /// Overrides the time-of-day tint entirely (Dark theme setting).
  static const AmbientPalette forcedDark = AmbientPalette(
    name: 'Dark',
    top: Color(0xFF000000),
    bottom: Color(0xFF0B0B0F),
    onSurface: Color(0xFFF2F2F5),
    onSurfaceVariant: Color(0xFF9A9AA6),
    surface: Color(0xFF17171C),
    onSurfaceStrong: Color(0xFFFFFFFF),
    brightness: Brightness.dark,
    isNight: true,
  );

  AmbientPalette adaptToAmbientLight(double level) {
    // Below 0.5 the room is dim: darken and cool. Above: lighten and warm.
    if ((level - 0.5).abs() < 0.02) return this;
    final amount = (level - 0.5) * 0.28;
    final target = amount > 0 ? const Color(0xFFFFF8EE) : const Color(0xFF04060C);
    final mix = amount.abs();
    return copyWith(
      top: Color.lerp(top, target, mix)!,
      bottom: Color.lerp(bottom, target, mix * 0.85)!,
      surface: Color.lerp(surface, target, mix * 0.7)!,
    );
  }

  AmbientPalette copyWith({
    Color? top,
    Color? bottom,
    Color? onSurface,
    Color? onSurfaceVariant,
    Color? surface,
    Color? onSurfaceStrong,
    Brightness? brightness,
    bool? isNight,
  }) {
    return AmbientPalette(
      name: name,
      top: top ?? this.top,
      bottom: bottom ?? this.bottom,
      onSurface: onSurface ?? this.onSurface,
      onSurfaceVariant: onSurfaceVariant ?? this.onSurfaceVariant,
      surface: surface ?? this.surface,
      onSurfaceStrong: onSurfaceStrong ?? this.onSurfaceStrong,
      brightness: brightness ?? this.brightness,
      isNight: isNight ?? this.isNight,
    );
  }

  /// Builds the ambient background as a vertical gradient plus a soft radial
  /// "glow" that mimics the Nest's warm centre-bloom.
  List<Color> backgroundStops() => [
    Color.lerp(top, Colors.white, isDark ? 0.03 : 0.06)!,
    Color.lerp(top, bottom, 0.45)!,
    bottom,
  ];
}

/// Component-wise colour blend that keeps hue sane (naive lerp through sRGB
/// would grey out saturated brand colours).
AmbientPalette lerpPalette(AmbientPalette a, AmbientPalette b, double t) {
  t = math.max(0.0, math.min(1.0, t));
  return AmbientPalette(
    name: t < 0.5 ? a.name : b.name,
    top: Color.lerp(a.top, b.top, t)!,
    bottom: Color.lerp(a.bottom, b.bottom, t)!,
    onSurface: Color.lerp(a.onSurface, b.onSurface, t)!,
    onSurfaceVariant: Color.lerp(a.onSurfaceVariant, b.onSurfaceVariant, t)!,
    surface: Color.lerp(a.surface, b.surface, t)!,
    onSurfaceStrong: Color.lerp(a.onSurfaceStrong, b.onSurfaceStrong, t)!,
    brightness: t < 0.5 ? a.brightness : b.brightness,
    isNight: t < 0.5 ? a.isNight : b.isNight,
  );
}