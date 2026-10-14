import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

/// Conditions the launcher knows how to draw a glyph for.
enum WeatherCondition {
  clear,
  partlyCloudy,
  cloudy,
  fog,
  drizzle,
  rain,
  snow,
  thunder,
  unknown,
}

extension WeatherConditionX on WeatherCondition {
  String get label => switch (this) {
    WeatherCondition.clear => 'Clear',
    WeatherCondition.partlyCloudy => 'Partly cloudy',
    WeatherCondition.cloudy => 'Cloudy',
    WeatherCondition.fog => 'Fog',
    WeatherCondition.drizzle => 'Drizzle',
    WeatherCondition.rain => 'Rain',
    WeatherCondition.snow => 'Snow',
    WeatherCondition.thunder => 'Thunderstorm',
    WeatherCondition.unknown => '',
  };
}

@immutable
class WeatherNow {
  const WeatherNow({
    required this.temperatureC,
    required this.condition,
    this.feelsLikeC,
    this.highC,
    this.lowC,
    this.humidity,
    this.location = '',
    this.updatedAt,
  });

  final double temperatureC;
  final WeatherCondition condition;
  final double? feelsLikeC;
  final double? highC;
  final double? lowC;
  final int? humidity;
  final String location;
  final DateTime? updatedAt;

  /// Display string in the device's locale-independent form, e.g. `12°`.
  String get shortLabel {
    final v = temperatureC.round();
    return '$v°';
  }

  static const WeatherNow placeholder = WeatherNow(
    temperatureC: 21,
    condition: WeatherCondition.partlyCloudy,
  );
}

/// Plain result record. Deliberately not a Flutter type, so it crosses the
/// isolate boundary as ordinary data.
typedef _WeatherReading =
    ({WeatherCondition condition, double temp, double? feels, double? high, double? low, int? humidity});

/// WMO weather interpretation codes -> our condition enum.
///
/// Pure data, so it can run inside the worker isolate without dragging Flutter
/// types across the boundary.
_WeatherReading _decodeOpenMeteo(String body) {
  final json = jsonDecode(body) as Map<String, dynamic>;
  final cur = json['current'] as Map<String, dynamic>?;
  if (cur == null) {
    return (
      condition: WeatherCondition.unknown,
      temp: 0.0,
      feels: null,
      high: null,
      low: null,
      humidity: null,
    );
  }
  final daily = json['daily'] as Map<String, dynamic>?;
  double? first(List? l) =>
      (l != null && l.isNotEmpty && l.first is num) ? (l.first as num).toDouble() : null;

  WeatherCondition decode(int code) => switch (code) {
    0 => WeatherCondition.clear,
    1 || 2 => WeatherCondition.partlyCloudy,
    3 => WeatherCondition.cloudy,
    45 || 48 => WeatherCondition.fog,
    51 || 53 || 55 || 56 || 57 => WeatherCondition.drizzle,
    61 || 63 || 65 || 66 || 67 || 80 || 81 || 82 => WeatherCondition.rain,
    71 || 73 || 75 || 77 || 85 || 86 => WeatherCondition.snow,
    95 || 96 || 99 => WeatherCondition.thunder,
    _ => WeatherCondition.unknown,
  };

  return (
    condition: decode((cur['weather_code'] as num?)?.toInt() ?? -1),
    temp: (cur['temperature_2m'] as num?)?.toDouble() ?? 0,
    feels: (cur['apparent_temperature'] as num?)?.toDouble(),
    high: first(daily?['temperature_2m_max'] as List?),
    low: first(daily?['temperature_2m_min'] as List?),
    humidity: (cur['relative_humidity_2m'] as num?)?.toInt(),
  );
}

/// Runs on a **worker isolate**, never the UI thread.
///
/// This is the CPU half of the hybrid split. Socket reads and JSON decoding
/// both block for tens of milliseconds on a weak radio and a slow UNISOC CPU —
/// more than a full frame at 60 Hz — and doing them inline is what produces the
/// visible hitch when weather first arrives.
Future<_WeatherReading?> _fetchAndParse({required double lat, required double lon}) async {
  final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
    'latitude': lat.toStringAsFixed(3),
    'longitude': lon.toStringAsFixed(3),
    'current': 'temperature_2m,apparent_temperature,relative_humidity_2m,weather_code',
    'daily': 'temperature_2m_max,temperature_2m_min',
    'temperature_unit': 'celsius',
    'timezone': 'auto',
    'forecast_days': '1',
  });

  final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
  final req = await client.getUrl(uri);
  final res = await req.close().timeout(const Duration(seconds: 8));
  if (res.statusCode != 200) {
    client.close();
    return null;
  }
  final body = await res.transform(utf8.decoder).join();
  client.close();
  return _decodeOpenMeteo(body);
}

/// Spawns the fetch onto a **worker isolate** — the CPU half of the hybrid
/// split. Socket reads and JSON decoding block for tens of milliseconds on a
/// slow radio and a slow UNISOC CPU, which is several frames at 60 Hz.
///
/// Deliberately a *top-level* function: if the spawn lived inside a method,
/// the AOT compiler folds the enclosing object into the closure's context and
/// `Isolate.run` then refuses to send it ("Illegal argument in isolate message:
/// object is unsendable"). From out here the closure captures two doubles and
/// nothing else.
Future<_WeatherReading?> _fetchOnWorker(double lat, double lon) {
  return Isolate.run(() => _fetchAndParse(lat: lat, lon: lon));
}

/// Weather source. Uses Open-Meteo (no API key, no tracking, small payloads).
/// Falls back to the placeholder when offline rather than blocking the UI.
class WeatherService extends ChangeNotifier {
  static const Duration refreshInterval = Duration(minutes: 15);

  Timer? _timer;
  Timer? _inFlight;
  WeatherNow _current = WeatherNow.placeholder;
  bool _loading = false;
  double? _latitude;
  double? _longitude;
  bool _enabled = true;

  WeatherNow get current => _current;
  bool get loading => _loading;
  bool get enabled => _enabled;

  void configure({double? latitude, double? longitude, bool enabled = true}) {
    _latitude = latitude;
    _longitude = longitude;
    if (_enabled != enabled) {
      _enabled = enabled;
      notifyListeners();
    }
    if (_enabled && _latitude != null) refresh();
  }

  Future<void> refresh() async {
    if (!_enabled || _latitude == null || _inFlight != null) return;
    _inFlight = Timer(const Duration(seconds: 12), () => _inFlight = null);
    _loading = true;
    try {
      final result = await _fetchOnWorker(_latitude!, _longitude!);
      if (result == null) return;
      _current = WeatherNow(
        temperatureC: result.temp,
        condition: result.condition,
        feelsLikeC: result.feels,
        highC: result.high,
        lowC: result.low,
        humidity: result.humidity,
        updatedAt: DateTime.now(),
      );
      notifyListeners();
    } catch (e) {
      // Offline / blocked network: keep showing the last good reading.
      debugPrint('WeatherService: refresh failed -> ${e.runtimeType}: $e');
    } finally {
      _loading = false;
      _inFlight = null;
    }
  }

  void startAutoRefresh() {
    _timer?.cancel();
    _timer = Timer.periodic(refreshInterval, (_) => refresh());
    refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _inFlight?.cancel();
    super.dispose();
  }
}