import 'package:flutter/material.dart';

import 'ambient_palette.dart';
import 'nest_type.dart';

/// Material 3 `ColorScheme` derived from the live [AmbientPalette].
///
/// The shell paints itself — background gradient, sheets, glyphs — so it never
/// needed a ThemeData. But every Material widget that *does* appear (toasts,
/// text fields, scrollbars, the permission dialog's fallback) reaches for
/// `Theme.of(context).colorScheme`, and without this it gets Flutter's default
/// purple-and-grey, which is exactly the "generic Android" look we are trying
/// to avoid.
///
/// Cheap: one object per palette change, and palettes change once a minute at
/// most.
ColorScheme nestColorScheme(AmbientPalette p) {
  // Google blue is the one accent that is unambiguously "Google" across every
  // product. On a dark scheme it needs lifting to keep contrast; on light it
  // is already right.
  final primary = p.isDark
      ? const Color(0xFF8AB4F8)
      : const Color(0xFF1A73E8);
  final onPrimary = p.isDark ? const Color(0xFF0A1220) : Colors.white;

  return ColorScheme(
    brightness: p.brightness,
    primary: primary,
    onPrimary: onPrimary,
    primaryContainer: Color.lerp(primary, p.surface, 0.72)!,
    onPrimaryContainer: p.isDark ? primary : const Color(0xFF0B3B78),

    secondary: p.onSurfaceVariant,
    onSecondary: p.surface,
    secondaryContainer: Color.lerp(p.onSurfaceVariant, p.surface, 0.78)!,
    onSecondaryContainer: p.onSurface,

    tertiary: p.isDark ? const Color(0xFF7FD1AE) : const Color(0xFF137333),
    onTertiary: p.isDark ? const Color(0xFF07201A) : Colors.white,

    error: p.isDark ? const Color(0xFFF2B8B5) : const Color(0xFFB3261E),
    onError: p.isDark ? const Color(0xFF3B0A09) : Colors.white,

    surface: p.surface,
    onSurface: p.onSurfaceStrong,
    surfaceContainerHighest: Color.lerp(p.surface, p.onSurface, 0.10)!,
    surfaceContainerHigh: Color.lerp(p.surface, p.onSurface, 0.06)!,
    surfaceContainerLow: Color.lerp(p.surface, p.onSurface, 0.03)!,

    onSurfaceVariant: p.onSurfaceVariant,
    outline: p.onSurfaceVariant.withValues(alpha: 0.45),
    outlineVariant: p.onSurfaceVariant.withValues(alpha: 0.22),

    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: p.isDark ? const Color(0xFFE9EDF7) : const Color(0xFF1F1F1F),
    onInverseSurface: p.isDark ? const Color(0xFF1F1F1F) : const Color(0xFFE9EDF7),
    inversePrimary: p.isDark ? const Color(0xFF1A73E8) : const Color(0xFF8AB4F8),
  );
}

/// The app's `ThemeData`, rebuilt whenever the ambient palette changes.
ThemeData nestTheme(AmbientPalette p, NestType type) {
  final scheme = nestColorScheme(p);

  return ThemeData(
    useMaterial3: true,
    brightness: p.brightness,
    colorScheme: scheme,
    fontFamily: 'GoogleSans',
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: Colors.transparent,
    splashFactory: NoSplash.splashFactory,
    // Google's corner language: generous, consistently rounded. Note that
    // `ThemeData.shape` no longer exists in this Flutter version, so the
    // radius has to be set on the component themes that actually use it.
    cardTheme: CardThemeData(
      color: p.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    dividerColor: scheme.outlineVariant,
    iconTheme: IconThemeData(color: p.onSurface, size: 24),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.isDark ? const Color(0xFF2C3550) : const Color(0xFF2B2B2B),
      contentTextStyle: type.body(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      insetPadding: const EdgeInsets.all(16),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: scheme.primary,
      selectionColor: scheme.primary.withValues(alpha: 0.28),
    ),
  );
}