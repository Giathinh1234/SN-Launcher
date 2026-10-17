import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Speech output and the listening state machine.
///
/// The *voice* brief was "the most natural female voice ever available", and
/// that cannot be honestly answered from Dart — it depends entirely on what
/// engines the device has installed. So this does the honest thing:
///
///  * asks the platform for the list of installed English voices, with their
///    quality and whether they are network-backed;
///  * picks the best one it can find, preferring high quality and network
///    voices, which on a stock Android device are Google's neural voices;
///  * exposes the list so the settings page can offer a choice, because
///    "most natural" is partly a matter of taste and partly of what the user
///    has downloaded.
///
/// Rate is 0.95 rather than 1.0. Android's default is a little rushed; real
/// assistants read slightly slower than that and it reads as more confident.
class Voice {
  Voice({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('dev.snlauncher/speech');

  final MethodChannel _channel;

  /// Null on desktop, where there is no TTS engine. Every method is a no-op
  /// rather than an error.
  static const bool _available = !kIsWeb;

  List<VoiceOption> _voices = const [];
  List<VoiceOption> get voices => _voices;

  VoiceOption? _chosen;
  VoiceOption? get chosen => _chosen;

  bool get available => _available;

  Future<void> init() async {
    if (!_available) return;
    try {
      final raw = await _channel.invokeMethod<List<Object?>>('listVoices');
      final parsed = <VoiceOption>[];
      for (final v in raw ?? const []) {
        if (v is! Map) continue;
        parsed.add(VoiceOption(
          id: v['id']?.toString() ?? '',
          name: v['name']?.toString() ?? '',
          locale: v['locale']?.toString() ?? '',
          veryHighQuality: v['quality']?.toString() == '2',
          network: v['network'] == true,
        ));
      }
      _voices = parsed;
      _chosen = _pick(parsed);
    } on PlatformException catch (e) {
      debugPrint('Voice.init failed: ${e.code} ${e.message}');
    } on MissingPluginException {
      // Desktop. Nothing to do.
    }
  }

  /// Best available voice.
  ///
  /// Ranking, and why:
  ///   1. `QUALITY_VERY_HIGH` — the platform's own signal that a voice is the
  ///      good variant rather than the fallback one.
  ///   2. network-backed — Google's neural voices are downloaded/streamed and
  ///      are audibly more natural than any on-device voice.
  ///   3. en-US over en-GB — arbitrary but stable; the user can override in
  ///      settings.
  ///
  /// Note this does **not** try to detect "female" from the voice name. Doing
  /// so would be guessing from a display string, and picking the wrong one is
  /// worse than offering the list.
  static VoiceOption? _pick(List<VoiceOption> all) {
    if (all.isEmpty) return null;
    final ranked = [...all]..sort((a, b) {
        int s(VoiceOption v) {
          var n = 0;
          if (v.veryHighQuality) n += 4;
          if (v.network) n += 2;
          if (v.locale.startsWith('en-US')) n += 1;
          return n;
        }

        return s(b).compareTo(s(a));
      });
    return ranked.first;
  }

  void select(String id) {
    final match = _voices.where((v) => v.id == id).firstOrNull;
    if (match != null) _chosen = match;
  }

  Future<bool> speak(String text, {bool interrupt = true}) async {
    if (!_available || text.trim().isEmpty) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('speak', {
        'text': text,
        'voiceId': _chosen?.id,
        'rate': 0.95,
        'pitch': 1.0,
        'interrupt': interrupt,
      });
      return ok ?? false;
    } on PlatformException catch (e) {
      debugPrint('Voice.speak failed: ${e.code} ${e.message}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> stop() async {
    if (!_available) return;
    try {
      await _channel.invokeMethod('stopSpeaking');
    } catch (_) {
      // Nothing useful to do; the utterance will end on its own.
    }
  }

  Future<bool> get isSpeaking async {
    if (!_available) return false;
    try {
      return await _channel.invokeMethod<bool>('isSpeaking') ?? false;
    } catch (_) {
      return false;
    }
  }
}

@immutable
class VoiceOption {
  const VoiceOption({
    required this.id,
    required this.name,
    required this.locale,
    required this.veryHighQuality,
    required this.network,
  });

  final String id;
  final String name;
  final String locale;
  final bool veryHighQuality;
  final bool network;

  /// "Amy (en-US, high quality, downloaded)" — enough for a picker row.
  String get label {
    final bits = <String>[
      if (name.isNotEmpty) name else id,
      locale,
      if (veryHighQuality) 'high quality',
      if (network) 'downloaded',
    ];
    return bits.join(' · ');
  }
}