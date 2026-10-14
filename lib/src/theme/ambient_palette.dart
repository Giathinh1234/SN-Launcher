import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Which look the user has pinned, or "let it follow the sun".
enum NestTheme {
  dynamic('Dynamic'),
  white('White'),
  day('Day'),
  afternoon('Afternoon'),
  night('Night');

  const NestTheme(this.label);
  final String label;
}

/// The ambient colour scheme the Nest Hub paints its whole UI with.
///
/// The real device samples its ambient light sensor and the wall clock to pick
/// a tint, then blends between a warm "daylight" scheme and a cool near-black
/// "night" scheme. Dawn and dusk get an amber wash, midday gets a cool paper
/// white, and late night drops to a soft blue.
///
/// Two ways to pick one:
///  * [at] — continuous, so the background drifts with the sun instead of
///    snapping at hour boundaries. This is [NestTheme.dynamic].
///  * a pinned preset ([of]) — a flat scheme the user chose and it stays put.
///    Pinning matters on a wall display: a screen that changes colour while
///    someone is reading it is worse than one that is consistently dull.
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

  /// Background gradient, top → bottom. Equal values mean "flat", which is
  /// what the pinned presets use.
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

  /// True when there is no gradient to draw.
  bool get isFlat => top == bottom;

  /// ── Pinned presets ───────────────────────────────────────────────────────
  // Flat by design. A pinned theme is a statement that the display should stop
  // changing, so these do not drift with the hour.

  /// Plain white. Google's own paper white, used for maximum legibility in a
  /// bright room or for anyone who simply does not want colour.
  static const AmbientPalette white = AmbientPalette(
    name: 'White',
    top: Color(0xFFFFFFFF),
    bottom: Color(0xFFFFFFFF),
    onSurface: Color(0xFF1F1F1F),
    onSurfaceVariant: Color(0xFF5F6368),
    surface: Color(0xFFF4F4F4),
    onSurfaceStrong: Color(0xFF1F1F1F),
    brightness: Brightness.light,
    isNight: false,
  );

  /// Daylight. The Nest Hub's signature paper white, measured (238, 234, 228)
  /// straight off a rectified photograph of the device's quick-settings sheet.
  /// The faint blue cast at the top is the ambient light sensor's daylight tint.
  static const AmbientPalette day = AmbientPalette(
    name: 'Day',
    top: Color(0xFFC8D8E6),
    bottom: Color(0xFFEDE8DE),
    onSurface: Color(0xFF11151C),
    onSurfaceVariant: Color(0xFF414C5C),
    surface: Color(0xFFEFEDE6),
    onSurfaceStrong: Color(0xFF11151C),
    brightness: Brightness.light,
    isNight: false,
  );

  /// Afternoon. Warmer and lower in contrast than [day] — the light has come
  /// round and the room's own lamps have started to matter.
  static const AmbientPalette afternoon = AmbientPalette(
    name: 'Afternoon',
    top: Color(0xFFE8DCCB),
    bottom: Color(0xFFD8C7B0),
    onSurface: Color(0xFF15181C),
    onSurfaceVariant: Color(0xFF4B5059),
    surface: Color(0xFFF0E9DC),
    onSurfaceStrong: Color(0xFF15181C),
    brightness: Brightness.light,
    isNight: false,
  );

  /// Night. A soft blue-black.
  ///
  /// Deliberately *not* near-black. The previous night schemes ran down to
  /// #070A14, which on an OLED-less e-waste LCD reads as a dead panel — the
  /// screen looks off and the user assumes the device has hung. Lifting the
  /// floor to #121826 keeps the panel visibly alive while still being clearly a
  /// night theme, and it is far kinder to a dark bedroom at 3am.
  static const AmbientPalette night = AmbientPalette(
    name: 'Night',
    top: Color(0xFF121826),
    bottom: Color(0xFF1E2740),
    onSurface: Color(0xFFE9EDF7),
    onSurfaceVariant: Color(0xFF9FAAC4),
    surface: Color(0xFF27304A),
    onSurfaceStrong: Color(0xFFF1F4FA),
    brightness: Brightness.dark,
    isNight: true,
  );

  /// ── Dynamic keyframes ────────────────────────────────────────────────────
  // Used only by [at]. Warm tints at dawn and dusk, cool paper at midday, soft
  // blue at night — the behaviour described in Google's own Ambient EQ copy.

  static const AmbientPalette _midnight = AmbientPalette(
    name: 'Midnight',
    top: Color(0xFF0E1420),
    bottom: Color(0xFF19223A),
    onSurface: Color(0xFFE9EDF7),
    onSurfaceVariant: Color(0xFF9BA6C0),
    surface: Color(0xFF222B44),
    onSurfaceStrong: Color(0xFFF2F5FC),
    brightness: Brightness.dark,
    isNight: true,
  );

  static const AmbientPalette _firstLight = AmbientPalette(
    name: 'First light',
    top: Color(0xFF362A50),
    bottom: Color(0xFF7A4C40),
    onSurface: Color(0xFFF6EDE6),
    onSurfaceVariant: Color(0xFFCAB9B0),
    surface: Color(0xFF574450),
    onSurfaceStrong: Color(0xFFFBF5F0),
    brightness: Brightness.dark,
    isNight: false,
  );

  static const AmbientPalette _sunrise = AmbientPalette(
    name: 'Sunrise',
    top: Color(0xFF7A525D),
    bottom: Color(0xFFD0936C),
    onSurface: Color(0xFFFFF6EE),
    onSurfaceVariant: Color(0xFFE5D0BE),
    surface: Color(0xFFC4947B),
    onSurfaceStrong: Color(0xFFFFFAF4),
    brightness: Brightness.light,
    isNight: false,
  );

  static const AmbientPalette _morning = AmbientPalette(
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

  static const AmbientPalette _daytime = AmbientPalette(
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

  static const AmbientPalette _afternoon = AmbientPalette(
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

  static const AmbientPalette _goldenHour = AmbientPalette(
    name: 'Golden hour',
    top: Color(0xFF96634C),
    bottom: Color(0xFFE09C5C),
    onSurface: Color(0xFFFFF4E8),
    onSurfaceVariant: Color(0xFFE0C9B1),
    surface: Color(0xFFC08A5C),
    onSurfaceStrong: Color(0xFFFFFAF2),
    brightness: Brightness.light,
    isNight: false,
  );

  static const AmbientPalette _dusk = AmbientPalette(
    name: 'Dusk',
    top: Color(0xFF4A3550),
    bottom: Color(0xFF8B5040),
    onSurface: Color(0xFFF6EAE4),
    onSurfaceVariant: Color(0xFFCDB2AD),
    surface: Color(0xFF67474D),
    onSurfaceStrong: Color(0xFFFCF4F0),
    brightness: Brightness.dark,
    isNight: true,
  );

  /// Time-ordered keyframes for a full 24h day.
  static const List<({double hour, AmbientPalette palette})> _timeline = [
    (hour: 0, palette: _midnight),
    (hour: 4.5, palette: _midnight),
    (hour: 6.0, palette: _firstLight),
    (hour: 7.0, palette: _sunrise),
    (hour: 9.0, palette: _morning),
    (hour: 13.0, palette: _daytime),
    (hour: 16.5, palette: _afternoon),
    (hour: 18.5, palette: _goldenHour),
    (hour: 20.0, palette: _dusk),
    (hour: 22.0, palette: night),
    (hour: 24, palette: _midnight),
  ];

  /// The palette for a pinned theme. [NestTheme.dynamic] has no fixed palette —
  /// use [at] for it.
  static AmbientPalette of(NestTheme theme) => switch (theme) {
        NestTheme.white => white,
        NestTheme.day => day,
        NestTheme.afternoon => afternoon,
        NestTheme.night => night,
        // Any caller that reaches here with `dynamic` wanted time-of-day
        // behaviour and will get it from `at`; returning noon is the sanest
        // static stand-in.
        NestTheme.dynamic => _daytime,
      };

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

  /// Resolve the user's choice against the current wall-clock hour.
  static AmbientPalette resolve(NestTheme theme, double hour) =>
      theme == NestTheme.dynamic ? at(hour) : of(theme);

  AmbientPalette adaptToAmbientLight(double level) {
    // Below 0.5 the room is dim: darken and cool. Above: lighten and warm.
    if ((level - 0.5).abs() < 0.02) return this;
    final amount = (level - 0.5) * 0.28;
    final target = amount > 0 ? const Color(0xFFFFF8EE) : const Color(0xFF0A0F1C);
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

  /// True when [onSurface] and [surface] are far enough apart to carry text at
  /// body sizes. Used by the theme picker to render honest previews rather
  /// than pretty swatches that fail contrast.
  bool get hasReadableInk {
    final l1 = onSurface.computeLuminance();
    final l2 = surface.computeLuminance();
    final hi = math.max(l1, l2);
    final lo = math.min(l1, l2);
    return (hi + 0.05) / (lo + 0.05) >= 4.5;
  }

  /// The background as vertical stops plus a soft centre bloom, the way the
  /// Nest washes its panel. Flat palettes get a single stop so the ambient
  /// background does not paint a pointless gradient over a solid fill.
  List<Color> backgroundStops() {
    if (isFlat) return [top];
    return [
      Color.lerp(top, Colors.white, isDark ? 0.03 : 0.06)!,
      Color.lerp(top, bottom, 0.45)!,
      bottom,
    ];
  }
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