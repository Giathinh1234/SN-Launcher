import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Tiny persistent key/value store for launcher settings.
///
/// Deliberately not `shared_preferences`. That plugin would add a Gradle
/// dependency to a project whose Android build has already been fragile (AGP
/// shells out to `sdkmanager` during configuration, which is why the Gradle
/// configuration cache has to stay off). One tiny channel method and a JSON
/// file are worth less than the build risk.
///
/// Everything is best-effort: a launcher that cannot remember your theme should
/// still start, so every failure path degrades to the default value.
class SettingsStore {
  SettingsStore();

  static const MethodChannel _channel =
      MethodChannel('dev.snlauncher/settings');

  /// Desktop fallback. `Directory.systemTemp` is the app-private cache dir on
  /// Android and `/tmp` elsewhere, so this needs no plugin and no permission.
  final File _fallback =
      File('${Directory.systemTemp.path}/sn_launcher_settings.json');

  // In-memory mirror so the UI never awaits a disk round trip to render.
  final Map<String, String> _cache = {};

  String? get(String key) => _cache[key];

  Future<void> load() async {
    try {
      final raw = await _channel.invokeMethod<String>('getAll');
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          _cache
            ..clear()
            ..addAll(decoded.map((k, v) => MapEntry('$k', '$v')));
          return;
        }
      }
    } on PlatformException catch (e) {
      debugPrint('SettingsStore: channel unavailable (${e.code}), '
          'falling back to a file');
    } on MissingPluginException {
      // Desktop: no native side, use the file below.
    } catch (e) {
      debugPrint('SettingsStore: load failed: $e');
    }

    try {
      if (await _fallback.exists()) {
        final decoded = jsonDecode(await _fallback.readAsString());
        if (decoded is Map) {
          _cache
            ..clear()
            ..addAll(decoded.map((k, v) => MapEntry('$k', '$v')));
        }
      }
    } catch (_) {
      // No persisted settings. Defaults apply.
    }
  }

  Future<void> put(String key, String value) async {
    _cache[key] = value;
    try {
      await _channel.invokeMethod('put', {'key': key, 'value': value});
      return;
    } on PlatformException catch (_) {
      // fall through to the file
    } on MissingPluginException {
      // fall through to the file
    }

    try {
      await _fallback.parent.create(recursive: true);
      await _fallback.writeAsString(jsonEncode(_cache));
    } catch (e) {
      debugPrint('SettingsStore: write failed: $e');
    }
  }

  T read<T extends Object>(String key, T fallback, T Function(String) parse) {
    final raw = _cache[key];
    if (raw == null) return fallback;
    try {
      return parse(raw);
    } catch (_) {
      return fallback;
    }
  }
}

/// Keys, so the string literals exist in exactly one place.
abstract final class SettingKeys {
  static const theme = 'theme';
  static const weatherEnabled = 'weatherEnabled';
  static const latitude = 'latitude';
  static const longitude = 'longitude';
  static const placeName = 'placeName';
  static const rotatePhotos = 'rotatePhotos';
  static const rotateMinutes = 'rotateMinutes';

  // ── Assistant ──────────────────────────────────────────────────────────────
  // Where the assistant sends hard requests. Kept as a name, not an enum, so a
  // value written by a newer build is not silently discarded by an older one.
  static const assistantBackend = 'assistantBackend';
  static const assistantEnabled = 'assistantEnabled';
  static const geminiApiKey = 'geminiApiKey';
  static const haUrl = 'haUrl';
  static const haToken = 'haToken';
  static const voiceEnabled = 'voiceEnabled';
}