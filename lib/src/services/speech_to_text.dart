import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One-shot speech recognition.
///
/// Deliberately not a persistent session. This is a wall display: a running
/// recogniser is both a battery cost and a privacy cost, and the user pressing
/// to speak is a far clearer signal than a microphone left open in a room.
///
/// Returns null for every failure — no permission, no engine, a timeout, a
/// silent room. The caller turns that into "did not catch that", never into a
/// fabricated transcript.
class SpeechToText {
  SpeechToText({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('dev.snlauncher/stt');

  final MethodChannel _channel;

  bool _listening = false;
  bool get listening => _listening;

  Future<bool> get available async {
    try {
      final r = await _channel.invokeMethod<Map<Object?, Object?>>('available');
      return r?['available'] == true;
    } on PlatformException catch (e) {
      debugPrint('STT.available failed: ${e.code} ${e.message}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Listen for one utterance and return what was heard, or null.
  Future<String?> listenOnce({int timeoutMs = 8000}) async {
    if (_listening) return null;
    _listening = true;
    try {
      final r = await _channel
          .invokeMethod<Map<Object?, Object?>>('listen', {'timeoutMs': timeoutMs});
      if (r?['text'] == null) {
        final err = r?['error'];
        if (err != null) debugPrint('STT: $err');
        return null;
      }
      return r!['text']?.toString();
    } on PlatformException catch (e) {
      debugPrint('STT.listen failed: ${e.code} ${e.message}');
      return null;
    } on MissingPluginException {
      return null;
    } finally {
      _listening = false;
    }
  }

  Future<void> stop() async {
    try {
      await _channel.invokeMethod('stop');
    } catch (_) {
      // Nothing useful; the watchdog on the platform side will clean up.
    }
    _listening = false;
  }
}
