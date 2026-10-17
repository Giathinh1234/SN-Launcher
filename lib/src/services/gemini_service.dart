import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Single-turn client for Google's Generative Language API.
///
/// **Fail-soft is the entire contract.** Every method returns `null` rather
/// than throwing: no key, no network, a 400, a 429, an unparseable body — all
/// of them come back as `null` with a `debugPrint` explaining why. An assistant
/// that throws takes the UI down with it, and this class runs behind a voice
/// button on a wall display, so it never gets to do that.
///
/// Deliberately **not** a [ChangeNotifier]. The assistant orchestrator owns
/// notifying; this is a plain pipe to the network.
///
/// Uses `dart:io`'s [HttpClient] directly, like the rest of this project — no
/// HTTP package dependency.
class GeminiService {
  GeminiService({String? apiKey}) : _apiKey = _cleanKey(apiKey);

  /// The Generative Language API host. Kept as constants so the endpoint is
  /// readable in one place.
  static const String _host = 'generativelanguage.googleapis.com';
  static const String _model = 'gemini-2.0-flash';

  /// A wall display should not sit on a spinner forever. The connection is
  /// given 15s to establish and the whole call 20s to answer; after that the
  /// assistant falls back to whatever it knows locally.
  static const Duration _connectTimeout = Duration(seconds: 15);
  static const Duration _timeout = Duration(seconds: 20);

  String? _apiKey;

  /// The key currently in use, or `null`. Safe to read; the token is never
  /// logged.
  String? get apiKey => _apiKey;

  /// Whether a usable key is present. The orchestrator uses this to decide
  /// between "answer locally" and "ask Gemini", so it must be truthful without
  /// touching the network.
  bool get isConfigured => _apiKey != null;

  /// Set (or clear) the API key. A blank string clears it, so the settings page
  /// can hand back whatever the field contains without a separate "clear".
  void setApiKey(String key) => _apiKey = _cleanKey(key);

  /// Ask Gemini one question and get one answer.
  ///
  /// Returns the model's text, or `null` on *any* failure — see the class
  /// documentation. The returned string is trimmed and never empty.
  Future<String?> ask(String prompt) async {
    final key = _apiKey;
    final text = prompt.trim();
    if (key == null) {
      debugPrint('GeminiService: no API key configured; answering locally');
      return null;
    }
    if (text.isEmpty) return null;

    final client = HttpClient()..connectionTimeout = _connectTimeout;
    try {
      final uri = Uri.https(_host, '/v1beta/models/$_model:generateContent');
      final req = await client.postUrl(uri);
      req.headers.set('x-goog-api-key', key);
      req.headers.contentType = ContentType.json;
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      req.add(utf8.encode(jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': text},
            ],
          },
        ],
      })));

      final res = await req.close().timeout(_timeout);
      final body = await res
          .transform(utf8.decoder)
          .join()
          .timeout(_timeout);

      if (res.statusCode != 200) {
        // 400 is a bad request, 403 a bad/restricted key, 429 rate limiting.
        // None of them should surface as an exception to the caller.
        final why = _errorMessage(body);
        debugPrint('GeminiService: HTTP ${res.statusCode}'
            '${why == null ? '' : ' — $why'}');
        return null;
      }
      return _extractText(body);
    } catch (e) {
      // Socket errors, TLS failures, DNS, timeouts: all swallowed here.
      debugPrint('GeminiService: request failed — ${e.runtimeType}: $e');
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Pull the concatenated text out of a `generateContent` response.
  ///
  /// Written as nested `as Map?` casts on purpose: Google's success and error
  /// payloads share a shape but vary in detail, and a single `!` anywhere in
  /// here is a crash on a device that has no log to read. Anything unexpected
  /// throws inside the `try`, which turns it into a `null`.
  String? _extractText(String body) {
    try {
      final decoded = jsonDecode(body);
      final candidates = (decoded as Map?)?['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) return null;

      final content = (candidates.first as Map?)?['content'] as Map?;
      final parts = content?['parts'] as List?;
      if (parts == null) return null;

      final buffer = StringBuffer();
      for (final part in parts) {
        final value = (part as Map?)?['text'];
        if (value is String && value.trim().isNotEmpty) {
          if (buffer.isNotEmpty) buffer.write('\n');
          buffer.write(value.trim());
        }
      }
      final out = buffer.toString().trim();
      return out.isEmpty ? null : out;
    } catch (e) {
      debugPrint('GeminiService: could not parse response — $e');
      return null;
    }
  }

  /// A one-line reason from an error payload, for the log only. Returns `null`
  /// whenever the body is not the shape we expect — including when it is
  /// something other than JSON at all.
  String? _errorMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      final error = (decoded as Map?)?['error'] as Map?;
      final message = error?['message'];
      return message is String && message.isNotEmpty ? message : null;
    } catch (_) {
      return null;
    }
  }

  static String? _cleanKey(String? key) {
    final trimmed = key?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }
}
