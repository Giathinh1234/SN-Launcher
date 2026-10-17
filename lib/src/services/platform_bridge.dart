import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Typed wrapper over the Android platform channel.
///
/// Every method answers even on failure. A MethodChannel call that throws
/// leaves the Dart Future in an error state, and a button whose handler throws
/// looks *identical* to a button that does nothing — which is exactly the bug
/// this class exists to stop. `brightness`, `volume` and `settings` were all
/// fake before this existed.
class PlatformBridge {
  const PlatformBridge();

  static const MethodChannel _channel =
      MethodChannel('dev.snlauncher/platform');

  /// Cached probe results. `hasCamera` in particular can be asked on every
  /// rebuild of the quick-settings row, and a package-manager round trip per
  /// frame is not free on a UNISOC.
  static bool? _hasCamera;

  Future<T?> _invoke<T>(String method, [Map<String, dynamic>? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      debugPrint('PlatformBridge.$method failed: ${e.code} ${e.message}');
      return null;
    } on MissingPluginException {
      // Expected on Linux and macOS: the channel has no native side there.
      return null;
    }
  }

  // ── Brightness ────────────────────────────────────────────────────────────
  /// [value] is 0..1. Returns what the platform actually applied, or null on
  /// a platform that cannot do it.
  Future<double?> setBrightness(double value) async {
    final r = await _invoke<Map<Object?, Object?>>(
      'setBrightness',
      {'value': value.clamp(0.0, 1.0)},
    );
    return (r?['value'] as num?)?.toDouble();
  }

  Future<double?> getBrightness() async {
    final r = await _invoke<Map<Object?, Object?>>('getBrightness');
    return (r?['value'] as num?)?.toDouble();
  }

  // ── Volume ────────────────────────────────────────────────────────────────
  Future<int?> setVolume(double value) async {
    final r = await _invoke<Map<Object?, Object?>>(
      'setVolume',
      {'value': value.clamp(0.0, 1.0)},
    );
    return (r?['value'] as num?)?.toInt();
  }

  Future<double?> getVolumeFraction() async {
    final r = await _invoke<Map<Object?, Object?>>('getVolume');
    final v = (r?['value'] as num?)?.toInt();
    final max = (r?['max'] as num?)?.toInt();
    if (v == null || max == null || max <= 0) return null;
    return v / max;
  }

  // ── Apps ──────────────────────────────────────────────────────────────────
  Future<bool> openAppSettings() async {
    final r = await _invoke<Map<Object?, Object?>>('openAppSettings');
    return r?['opened'] == true;
  }

  Future<bool> openCamera() async {
    final r = await _invoke<Map<Object?, Object?>>('openCamera');
    if (r?['opened'] == true) return true;
    final reason = r?['reason'];
    debugPrint('PlatformBridge.openCamera: $reason');
    return false;
  }

  Future<bool> openUrl(String url) async {
    final r = await _invoke<Map<Object?, Object?>>('openUrl', {'url': url});
    return r?['opened'] == true;
  }

  Future<bool> hasCamera() async {
    final cached = _hasCamera;
    if (cached != null) return cached;
    final r = await _invoke<Map<Object?, Object?>>('hasCamera');
    final v = r?['available'] == true;
    _hasCamera = v;
    return v;
  }

  // ── Permissions ───────────────────────────────────────────────────────────
  /// Returns false when the user declined, and null on a platform with no
  /// permission model for it (desktop).
  Future<bool?> requestPermission(String permission) async {
    final r = await _invoke<Map<Object?, Object?>>(
      'requestPermission',
      {'permission': permission},
    );
    return r?['granted'] as bool?;
  }

  // ── Media keys ────────────────────────────────────────────────────────────
  /// Raise a hardware media key so any installed player responds, including the
  /// system media UI. Returns false if the platform refused — the assistant
  /// reports that rather than claiming it started playing.
  Future<bool> sendMediaKey(String action) async {
    final r = await _invoke<Map<Object?, Object?>>(
      'mediaKey',
      {'action': action},
    );
    return r?['ok'] == true;
  }

  /// Shows a countdown label. Used by the timer intent.
  Future<bool> setTimerLabel(String label) async {
    final r = await _invoke<Map<Object?, Object?>>(
      'setTimerLabel',
      {'label': label},
    );
    return r?['ok'] == true;
  }

  // ── Ambient light ─────────────────────────────────────────────────────────
  /// One-shot lux reading. Not a continuous subscription: this is a 1-4 GB
  /// device and an always-on light sensor is a battery cost a mostly-wall-
  /// powered launcher should not pay. Returns null when there is no sensor.
  Future<double?> lightLevel() async {
    final r = await _invoke<Map<Object?, Object?>>('lightLevel');
    if (r?['available'] != true) return null;
    return (r?['lux'] as num?)?.toDouble();
  }

  Future<bool> hasLightSensor() async {
    final r = await _invoke<Map<Object?, Object?>>('hasLightSensor');
    return r?['available'] == true;
  }

  // ── Calendar ──────────────────────────────────────────────────────────────
  Future<List<CalendarEvent>> upcomingEvents({
    required int limit,
    required DateTime from,
  }) async {
    final r = await _invoke<Map<Object?, Object?>>('upcomingEvents', {
      'limit': limit,
      'fromMillis': from.millisecondsSinceEpoch,
    });
    final raw = r?['events'];
    if (raw is! List) return const [];
    final out = <CalendarEvent>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final title = e['title']?.toString().trim() ?? '';
      if (title.isEmpty) continue;
      final start = (e['start'] as num?)?.toInt();
      if (start == null) continue;
      out.add(CalendarEvent(
        title: title,
        start: DateTime.fromMillisecondsSinceEpoch(start),
        end: (e['end'] as num?) != null
            ? DateTime.fromMillisecondsSinceEpoch((e['end'] as num).toInt())
            : null,
        location: e['location']?.toString() ?? '',
        allDay: e['allDay'] == true,
        color: (e['color'] as num?)?.toInt(),
      ));
    }
    return out;
  }
}

/// One calendar instance, already flattened by the platform side.
@immutable
class CalendarEvent {
  const CalendarEvent({
    required this.title,
    required this.start,
    this.end,
    this.location = '',
    this.allDay = false,
    this.color,
  });

  final String title;
  final DateTime start;
  final DateTime? end;
  final String location;
  final bool allDay;
  final int? color;

  bool get isNow {
    final e = end;
    final now = DateTime.now();
    return !start.isAfter(now) && (e == null || e.isAfter(now));
  }
}