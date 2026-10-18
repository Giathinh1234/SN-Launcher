import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Which features are compiled into this build.
///
/// Two builds exist and they are the *same code* — the difference is one JSON
/// file chosen at build time:
///
///   assets/features.ef.json      every feature on  (the "ExtraFeature" build)
///   assets/features.json         the reduced build
///
///   flutter build apk --release --dart-define=SN_FEATURES=assets/features.ef.json
///   flutter build apk --release                       # reduced, the default
///
/// A JSON file rather than `--dart-define` flags because it is readable,
/// diffable, and can be swapped on a device without a rebuild.
class FeatureFlags {
  FeatureFlags._(this._map, this.source);

  final Map<String, bool> _map;

  /// Where these came from, for the settings page and for logs. If this is a
  /// file that does not exist, everything is off — never silently "on", because
  /// a missing config should not produce a launcher that claims capabilities
  /// the build does not have.
  final String source;

  static const String defaultAsset = 'assets/features.json';

  static final FeatureFlags empty =
      FeatureFlags._({}, '(none — every feature disabled)');

  /// Every feature this build knows how to gate. Adding one here without
  /// gating it is harmless; adding one to the JSON without adding it here means
  /// the flag is ignored, which is why `unknown` is reported.
  static const Set<String> known = {
    'settings',
    'assistant',
    'music',
    'photoRotation',
    'themePicker',
    'calendar',
    'digestPage',
    'weather',
    'quickSettings',
  };

  /// Which build this is, for the settings page and the about screen.
  ///
  /// Set with `--dart-define=SN_BUILD_NAME=ef`. Falls back to the config
  /// filename, because an APK that cannot say which of two builds it is forces
  /// the reader to guess from behaviour — and two builds of the same app is
  /// exactly the situation where guessing is wrong.
  String get buildName {
    const n = String.fromEnvironment('SN_BUILD_NAME');
    if (n.isNotEmpty) return n;
    return source.split('/').last.replaceAll('.json', '');
  }

  /// Raw map, for diagnostics.
  Map<String, bool> get all => Map.unmodifiable(_map);

  bool isOn(String feature) => _map[feature] ?? false;

  /// Flags in the JSON that this build does not implement. Surfaced rather than
  /// ignored, so a typo in a config file is visible instead of mysterious.
  List<String> get unknown {
    final u = _map.keys.where((k) => !known.contains(k)).toList()..sort();
    return u;
  }

  static FeatureFlags _loaded = empty;

  /// The build's flags. Safe to read synchronously from build() — that is the
  /// whole reason the config is bundled rather than fetched.
  static FeatureFlags get current => _loaded;

  /// Reads the JSON asset named by `SN_FEATURES`, defaulting to the reduced
  /// build's file. Must complete before the first frame.
  static Future<FeatureFlags> load() async {
    final path = const String.fromEnvironment(
      'SN_FEATURES',
      defaultValue: defaultAsset,
    );
    try {
      final raw = await rootBundle.loadString(path);
      _loaded = parse(raw, path);
    } catch (_) {
      // No config: a launcher with nothing switched on, rather than one that
      // invents capabilities.
      debugPrint('FeatureFlags: could not read $path; all features off');
      _loaded = empty;
    }
    final unknown = _loaded.unknown;
    if (unknown.isNotEmpty) {
      debugPrint('FeatureFlags: ignoring unknown entries $unknown');
    }
    debugPrint('FeatureFlags($path): ${_loaded._map}');
    return _loaded;
  }

  /// Overrides the loaded flags.
  ///
  /// The shell reads [current] synchronously from build(), so a widget test has
  /// no other way to exercise two configurations in one process — [load] is
  /// called once in main() and reads a compile-time constant path.
  @visibleForTesting
  static set forTesting(FeatureFlags f) => _loaded = f;

  /// Parses a config document.
  ///
  /// Public only so the shipped files can be tested directly, read off disk,
  /// rather than through [load] — a test that goes through rootBundle and a
  /// dart-define cannot tell you whether `assets/features.json` is correct.
  @visibleForTesting
  static FeatureFlags parse(String raw, String path) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return FeatureFlags._({}, path);
      final node = decoded['features'];
      final src = node is Map ? node : decoded;
      final out = <String, bool>{};
      src.forEach((k, v) {
        if (v is bool) out[k.toString()] = v;
      });
      return FeatureFlags._(out, path);
    } catch (e) {
      debugPrint('FeatureFlags: $path is malformed — $e');
      return FeatureFlags._({}, path);
    }
  }
}