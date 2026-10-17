import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// One entity as Home Assistant reports it, flattened for the launcher.
///
/// Only the three fields an assistant can actually act on are kept: the id it
/// calls services with, a human name to read aloud, and the current state.
/// A raw HA state object carries dozens of attributes, timestamps and a
/// context blob; parsing all of it on a 1 GB device would be wasted work.
@immutable
class HaEntity {
  const HaEntity({required this.id, required this.name, required this.state});

  /// e.g. `light.kitchen`.
  final String id;

  /// Usually `attributes.friendly_name`, falling back to [id] when absent.
  final String name;

  /// e.g. `on`, `off`, `unavailable`.
  final String state;

  @override
  String toString() => 'HaEntity($id, $name, $state)';
}

/// Client for a Home Assistant instance's REST API.
///
/// **Fail-soft is the contract**, same as the Gemini client. Nothing here
/// throws:
/// a missing config, a refused connection, a 401, a 500 or a body that is not
/// JSON all degrade to `false`/`null`/an empty list with a `debugPrint` saying
/// why. The settings page's "Test connection" and the assistant both call into
/// this, and neither can afford an unhandled exception.
///
/// Deliberately **not** a [ChangeNotifier]; the orchestrator owns notifying.
///
/// The access token is held in memory only. It is never written to a
/// `debugPrint`, never included in any exception message, and never echoed in
/// a URI — it travels solely in the `Authorization` header.
class HomeAssistantService {
  HomeAssistantService({String? url, String? token}) {
    setConfig(url: url ?? '', token: token ?? '');
  }

  /// LAN values: a Home Assistant box on the same network should answer fast,
  /// and a wrong/absent host should fail well before a user gives up waiting.
  static const Duration _connectTimeout = Duration(seconds: 8);
  static const Duration _timeout = Duration(seconds: 12);

  /// A large install can report thousands of entities. This runs on a weak
  /// device and the list is fed to a voice/assistant layer that only ever
  /// reasons about a handful, so parsing stops at the first 200.
  static const int _maxEntities = 200;

  String? _baseUrl;
  String? _token;

  /// The normalised base URL (scheme included, no trailing slash), or `null`.
  /// Safe to display; contains no secret.
  String? get baseUrl => _baseUrl;

  /// Whether both a URL and a token are present. True does not imply the
  /// server is reachable — use [ping] for that.
  bool get isConfigured => _baseUrl != null && _token != null;

  /// Replace the connection settings.
  ///
  /// A blank `url` or `token` disables the client, which is how the settings
  /// page turns it off without a separate flag.
  void setConfig({required String url, required String token}) {
    _baseUrl = normalizeBaseUrl(url);
    final trimmed = token.trim();
    _token = trimmed.isEmpty ? null : trimmed;
  }

  /// "Test connection" for the settings page: is this a reachable HA instance
  /// that accepts the token? A 401 answers `false` just like a timeout.
  Future<bool> ping() async {
    final base = _baseUrl;
    if (base == null || _token == null) return false;
    final res = await _send(Uri.parse('$base/api/'));
    return res?.status == 200;
  }

  /// The entity list, capped at 200 entries. Returns an empty list on any
  /// failure, never `null`, so callers can iterate without a null check.
  Future<List<HaEntity>> listEntities() async {
    final base = _baseUrl;
    if (base == null || _token == null) return const [];
    final res = await _send(Uri.parse('$base/api/states'));
    if (res == null || res.status != 200) return const [];

    try {
      final decoded = jsonDecode(res.body);
      if (decoded is! List) return const [];
      final out = <HaEntity>[];
      for (final item in decoded) {
        if (out.length >= _maxEntities) break;
        // Nested `as Map?` casts, deliberately: an entity that is not shaped
        // like an entity is skipped, not allowed to abort the whole list.
        final map = item as Map?;
        final id = map?['entity_id']?.toString();
        if (id == null || id.isEmpty) continue;
        final attributes = map?['attributes'] as Map?;
        final name = attributes?['friendly_name']?.toString().trim();
        out.add(HaEntity(
          id: id,
          name: (name == null || name.isEmpty) ? id : name,
          state: map?['state']?.toString() ?? '',
        ));
      }
      return out;
    } catch (e) {
      debugPrint('HomeAssistantService: could not parse states — $e');
      return const [];
    }
  }

  /// Set an entity's state directly (e.g. `light.kitchen` -> `off`).
  Future<bool> setEntity(String entityId, String state) async {
    final base = _baseUrl;
    if (base == null || _token == null) return false;
    final res = await _send(
      Uri.parse('$base/api/states/$entityId'),
      post: true,
      body: {'state': state},
    );
    return _ok(res);
  }

  /// Call a service (e.g. `light`/`turn_on` with `{"entity_id": "light.kitchen"}`).
  ///
  /// This is the verb Home Assistant is actually built around; [setEntity] is
  /// the blunter instrument kept for completeness.
  Future<bool> callService(
    String domain,
    String service,
    Map<String, dynamic> data,
  ) async {
    final base = _baseUrl;
    if (base == null || _token == null) return false;
    final res = await _send(
      Uri.parse('$base/api/services/$domain/$service'),
      post: true,
      body: data,
    );
    return _ok(res);
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  static bool _ok(_HaResponse? res) =>
      res != null && (res.status == 200 || res.status == 201);

  /// One HTTP round trip. Returns `null` on any error.
  ///
  /// Logs the method and path only — never [uri] including query, and never the
  /// token. Home Assistant accepts 200 and 201 for a successful write.
  Future<_HaResponse?> _send(
    Uri uri, {
    bool post = false,
    Map<String, dynamic>? body,
  }) async {
    final token = _token;
    if (token == null) return null;

    final client = HttpClient()..connectionTimeout = _connectTimeout;
    try {
      final req = post ? await client.postUrl(uri) : await client.getUrl(uri);
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.add(utf8.encode(jsonEncode(body)));
      }

      final res = await req.close().timeout(_timeout);
      final text = await res
          .transform(utf8.decoder)
          .join()
          .timeout(_timeout);
      return _HaResponse(res.statusCode, text);
    } catch (e) {
      // Includes timeouts, refused connections and DNS failures.
      debugPrint('HomeAssistantService: '
          '${post ? 'POST' : 'GET'} ${uri.path} failed — ${e.runtimeType}');
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Turn whatever a user typed into a usable base URL, or `null` if there is
  /// nothing usable in it.
  ///
  /// Users type `192.168.1.50:8123`, not a scheme. If there is no real
  /// `http`/`https` scheme the host is parsed as absent, so `http://` is
  /// prepended — default http, which is what a LAN Home Assistant serves.
  /// Trailing slashes are stripped so `<base>/api/` never doubles up, and a
  /// pasted trailing `/api` (the URL the Home Assistant docs show) is removed
  /// for the same reason.
  static String? normalizeBaseUrl(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;

    final parsed = Uri.tryParse(s);
    final hasHttpScheme = parsed != null &&
        (parsed.scheme == 'http' || parsed.scheme == 'https') &&
        parsed.host.isNotEmpty;
    // Note `homeassistant.local:8123` parses as the *scheme*
    // `homeassistant.local` with no host; the host check above catches it and
    // it gets a scheme prepended like any other bare host.
    if (!hasHttpScheme) {
      // "http://" with nothing after it has an http scheme but no host, so
      // prepending one would only build `http://http:`. There is nothing
      // usable here.
      if (parsed != null &&
          (parsed.scheme == 'http' || parsed.scheme == 'https')) {
        return null;
      }
      s = 'http://$s';
    }

    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    if (s.endsWith('/api')) {
      s = s.substring(0, s.length - '/api'.length);
    }

    final check = Uri.tryParse(s);
    if (check == null || check.host.isEmpty) return null;
    return s;
  }
}

/// Response status and body, carried out of [_send] without a nullable pair.
class _HaResponse {
  const _HaResponse(this.status, this.body);
  final int status;
  final String body;
}
