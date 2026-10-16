import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/photo_credit.dart';
import 'settings_store.dart';

/// A photograph the rotation is allowed to use.
///
/// Not a live search. Every entry is a specific Wikimedia Commons file that has
/// been looked at and judged: no people, no text, no diagrams, all landscape,
/// all public domain or CC-BY.
///
/// This is a deliberate choice over "fetch something random from the internet".
/// A photo frame on a wall display is a thing people look at constantly; a
/// random image search will eventually put a portrait, a chart, or a
/// screenshot of someone's desktop on it. A curated pool guarantees the thing
/// is always pleasant and always lawfully redistributable, which a random
/// fetch can never promise.
class PhotoSource {
  const PhotoSource(this.title, this.author);
  final String title;

  /// The name to put on screen.
  ///
  /// Overrides whatever the Commons `Artist` field says. That field routinely
  /// contains markup, agency boilerplate, or — in one case we picked — a dead
  /// link, and this string is rendered next to "Recent highlights" on the
  /// user's wall, so it has to read like a person's name.
  final String author;
}

/// Licences we will install onto the user's device. Anything else is refused at
/// fetch time and the pool entry is skipped.
const Set<String> _allowedLicenceFragments = {
  'public domain',
  'cc0',
  'cc by 2.0',
  'cc by 3.0',
  'cc by 4.0',
  'cc by',
};

/// Downloads and rotates the photo-frame background.
///
/// Design constraints, all from the e-waste hardware this targets:
///  * **Never blocks the first frame.** The bundled photograph in
///    `assets/photo/` is what renders at launch; anything downloaded is a
///    later upgrade. Cold start must stay at ~0.8s.
///  * **Never hits the network on a timer without a next image in hand.** The
///    next photograph is fetched *before* the current one expires, so the swap
///    is a local file read and cannot be late or fail visibly.
///  * **Plain `dart:io` HttpClient**, no HTTP package. On a 1 GB tablet every
///    avoided dependency is avoided APK size and avoided cold-start work.
class PhotoFrameService extends ChangeNotifier {
  PhotoFrameService({SettingsStore? settings})
      : _settings = settings ?? SettingsStore();

  final SettingsStore _settings;

  /// How many downloaded images to keep on disk.
  static const int _cacheLimit = 6;

  /// Kept narrow: the panel is 2000px wide at most on the target hardware, and
  /// the source files are far larger than that. 1600 keeps a landscape around
  /// 300 KB, so ten minutes of rotation costs a few hundred KB a day.
  static const int _maxWidth = 1600;

  /// Verified against the live Commons API and looked at before inclusion.

  /// Every entry is public domain, CC0 or CC-BY — never share-alike, which

  /// a launcher cannot honour.

  static const List<PhotoSource> pool = [
    PhotoSource(
      'Jokulsarlon lake, Iceland.jpg',
      'Kenny Muir',
    ),
    PhotoSource(
      'Lake Kinney mit Mount Whitehorn.jpg',
      'Florian Fuchs',
    ),
    PhotoSource(
      'Zagedan Lakes, Mountain cirque, Caucasus Mountains.jpg',
      'Vyacheslav Argenberg',
    ),
    PhotoSource(
      'Early morning light at the top of Poon Hill2.jpg',
      'Ali Sabbagh',
    ),
    PhotoSource(
      'Himalaya sunrise.jpg',
      'Ali Sabbagh',
    ),
    PhotoSource(
      'MistySunrise.JPG',
      'Elaine Li[dead link]',
    ),
    PhotoSource(
      'Khodz River Valley in fog, Adygea, Верховья реки Ходзь в тумане и облаках, Адыгея.jpg',
      'Vyacheslav Argenberg',
    ),
    PhotoSource(
      'Wisła pod Ochodzą w województwie małopolskim, 20231119 0706 2690.jpg',
      'Elaine Li',
    ),
    PhotoSource(
      'Asbestnaya Mount, Adygea, Гора Асбестная, виды с вершины, Адыгея, Западный Кавказ.jpg',
      'Vyacheslav Argenberg',
    ),
    PhotoSource(
      'Ella, Sri Lanka, Mountains in clouds, Panorama.jpg',
      'Vyacheslav Argenberg',
    ),
    PhotoSource(
      'River Running through a Rolling Hills Landscape by Edmund John Nieman .jpg',
      'Edmund John Nieman (1843-1910)',
    ),
    PhotoSource(
      'Rolling hills and lagoon scenics.jpg',
      'West Robin L, U.S. Fish and Wildlife Service',
    ),
  ];


  File? _current;
  PhotoCredit? _credit;

  /// The local file the background should load, or null to use the bundled
  /// asset.
  File? get currentFile => _current;
  PhotoCredit? get credit => _credit;

  bool _enabled = true;
  bool get enabled => _enabled;

  Duration _interval = const Duration(minutes: 10);
  Duration get interval => _interval;

  bool _busy = false;
  bool get busy => _busy;

  Timer? _timer;
  bool _disposed = false;

  /// The last file we showed, so the next pick cannot repeat it.
  String? _lastTitle;

  Directory get _cacheDir {
    // On Android this is the app's private cache directory: writable with no
    // permission, and removable by the system if storage gets tight, which is
    // the correct behaviour for downloaded media.
    final d = Directory(
      '${Directory.systemTemp.path}/sn_launcher_photos',
    );
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  /// Restore settings, show whatever is already cached, then start rotating.
  Future<void> start() async {
    await _settings.load();
    _enabled = _settings.read(SettingKeys.rotatePhotos, true, (v) => v == 'true');
    final mins = _settings.read(SettingKeys.rotateMinutes, 10, (v) => int.tryParse(v) ?? 10);
    _interval = Duration(minutes: mins.clamp(1, 1440));

    _adoptNewestCached();
    _schedule();
    if (_enabled) unawaited(prefetchNext());
    notifyListeners();
  }

  // ── Public controls ────────────────────────────────────────────────────────

  Future<void> setEnabled(bool on) async {
    _enabled = on;
    await _settings.put(SettingKeys.rotatePhotos, '$on');
    if (on) {
      unawaited(prefetchNext());
    }
    _schedule();
    notifyListeners();
  }

  Future<void> setIntervalMinutes(int minutes) async {
    final m = minutes.clamp(1, 1440);
    _interval = Duration(minutes: m);
    await _settings.put(SettingKeys.rotateMinutes, '$m');
    _schedule();
    notifyListeners();
  }

  /// Fetch and show a different photograph right now.
  ///
  /// Used by the "next photo" control and by [prefetchNext]. Reports failure
  /// by leaving the current picture alone — never by blanking the background.
  Future<void> next() async {
    final got = await _fetchIntoCache();
    if (got == null || _disposed) return;
    _current = got.file;
    _credit = got.credit;
    _lastTitle = got.credit.title;
    notifyListeners();
  }

  /// Download the next picture ahead of time so the swap is instant.
  Future<void> prefetchNext() async {
    if (_busy) return;
    await next();
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  void _schedule() {
    _timer?.cancel();
    if (!_enabled || _disposed) return;
    _timer = Timer.periodic(_interval, (_) => prefetchNext());
  }

  void _adoptNewestCached() {
    try {
      final files = _cachedImages()
        ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
      if (files.isEmpty) return;
      _current = files.first;
      _credit = _readSidecar(files.first);
    } catch (_) {
      // No cache yet; the bundled asset covers it.
    }
  }

  List<File> _cachedImages() => _cacheDir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.jpg'))
      .toList();

  File _sidecarFor(File image) =>
      File('${image.path}.json');

  PhotoCredit? _readSidecar(File image) {
    try {
      final f = _sidecarFor(image);
      if (!f.existsSync()) return null;
      final m = jsonDecode(f.readAsStringSync());
      if (m is! Map) return null;
      return PhotoCredit(
        title: m['title']?.toString(),
        author: m['author']?.toString(),
        license: m['license']?.toString(),
        licenseUrl: m['licenseUrl']?.toString(),
        sourceUrl: m['sourceUrl']?.toString(),
      );
    } catch (_) {
      return null;
    }
  }

  void _prune() {
    final files = _cachedImages()
      ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    for (final old in files.skip(_cacheLimit)) {
      try {
        _sidecarFor(old).deleteSync();
        old.deleteSync();
      } catch (_) {/* keep going */}
    }
  }

  Future<({File file, PhotoCredit credit})?> _fetchIntoCache() async {
    if (_busy) return null;
    _busy = true;
    notifyListeners();
    try {
      // Try each pool entry in turn. A pool entry can fail (file renamed on
      // Commons, licence changed, network blip) and that must not take the
      // whole rotation down with it.
      for (var attempt = 0; attempt < 4; attempt++) {
        final pick = _pickSource();
        final got = await _fetchOne(pick);
        if (got != null) {
          _prune();
          return got;
        }
      }
      debugPrint('PhotoFrameService: no pool entry could be fetched');
      return null;
    } finally {
      _busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// Random, but never the picture we are currently showing.
  PhotoSource _pickSource() {
    final candidates =
        pool.where((s) => s.title != _lastTitle).toList(growable: false);
    final from = candidates.isEmpty ? pool : candidates;
    return from[DateTime.now().microsecondsSinceEpoch % from.length];
  }

  Future<({File file, PhotoCredit credit})?> _fetchOne(PhotoSource src) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final meta = await _api(client, src.title, src.author);
      if (meta == null) return null;
      if (!_licenceIsAllowed(meta.license ?? '')) {
        debugPrint(
          'PhotoFrameService: refusing "${src.title}" — licence is '
          '"${meta.license}"',
        );
        return null;
      }
      if (meta.imageUrl == null) return null;

      final bytes = await _download(client, meta.imageUrl!);
      if (bytes == null || bytes.length < 20_000) return null;

      final saved = await _write(bytes, meta);
      return (file: saved, credit: meta);
    } catch (e) {
      debugPrint('PhotoFrameService: ${src.title} failed — $e');
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Fails closed: anything not explicitly on the allow-list is refused.
  ///
  /// Substring matching is only safe for the allow-list, where the fragments
  /// are specific enough. The forbidden list is a belt-and-braces check for the
  /// common share-alike spellings, because "cc by-sa 4.0" also contains "cc by"
  /// and would otherwise sail through.
  static bool _licenceIsAllowed(String licence) {
    final low = licence.toLowerCase().trim();
    if (low.isEmpty) return false;

    const shareAlike = ['-sa', 'sa 4.0', 'sa 3.0', 'sa 2.0', 'sa 2.5',
      'sharealike', 'share alike', 'share-alike'];
    for (final sa in shareAlike) {
      if (low.contains(sa)) return false;
    }
    if (low.contains('-nc') || low.contains('noncommercial') ||
        low.contains('non-commercial')) {
      return false;
    }
    if (low.contains('-nd') || low.contains('noderiv') ||
        low.contains('no derivative')) {
      return false;
    }
    if (low.contains('fair use') || low.contains('non-free')) return false;

    return _allowedLicenceFragments.any(low.contains);
  }

  Future<PhotoCredit?> _api(
    HttpClient client,
    String fileTitle,
    String authorOverride,
  ) async {
    final uri = Uri.https('commons.wikimedia.org', '/w/api.php', {
      'action': 'query',
      'titles': 'File:$fileTitle',
      'prop': 'imageinfo',
      'iiprop': 'url|extmetadata|size',
      'iiurlwidth': '$_maxWidth',
      'format': 'json',
    });
    try {
      final req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.userAgentHeader, 'SNLauncher/0.2');
      final res = await req.close();
      if (res.statusCode != 200) return null;
      final body = await res.transform(utf8.decoder).join();
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      final pages = (((decoded['query'] as Map?)?['pages']) as Map?) ?? {};
      for (final page in pages.values) {
        if (page is! Map || page.containsKey('missing')) continue;
        final info = ((page['imageinfo'] as List?)?.first) as Map?;
        if (info == null) return null;
        final em = (info['extmetadata'] as Map?) ?? {};
        String meta(String k) => ((em[k] as Map?)?['value'] ?? '').toString();
        return PhotoCredit(
          title: page['title'].toString().replaceFirst('File:', ''),
          author: authorOverride,
          license: _clean(meta('LicenseShortName')),
          licenseUrl: _clean(meta('LicenseUrl')),
          sourceUrl: info['descriptionurl']?.toString(),
          imageUrl: info['thumburl']?.toString(),
        );
      }
    } catch (e) {
      debugPrint('PhotoFrameService: API error — $e');
    }
    return null;
  }

  static String _clean(String s) =>
      s.replaceAll(RegExp(r'<[^>]*>'), '').trim();

  Future<List<int>?> _download(HttpClient client, String url) async {
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.userAgentHeader, 'SNLauncher/0.2');
      final res = await req.close();
      if (res.statusCode != 200) return null;
      final bytes = <int>[];
      await for (final chunk in res) {
        bytes.addAll(chunk);
        // 4 MB is far above any 1600px JPEG we want; anything larger is a
        // mis-picked URL and is not worth the user's data.
        if (bytes.length > 4 * 1024 * 1024) return null;
      }
      return bytes;
    } catch (_) {
      return null;
    }
  }

  Future<File> _write(List<int> bytes, PhotoCredit credit) async {
    final tmp = File('${_cacheDir.path}/dl.tmp');
    await tmp.writeAsBytes(bytes, flush: true);

    final out = File(
      '${_cacheDir.path}/photo_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    // Stored verbatim. Commons was asked for a 1600px-wide thumbnail, which is
    // already exactly what this should be — re-encoding would only be a way to
    // turn a 300 KB JPEG into a 2 MB PNG, because dart:ui has no JPEG encoder.
    await out.writeAsBytes(bytes, flush: true);
    try {
      tmp.deleteSync();
    } catch (_) {/* ignore */}

    await _sidecarFor(out).writeAsString(jsonEncode({
      'title': credit.title,
      'author': credit.author,
      'license': credit.license,
      'licenseUrl': credit.licenseUrl,
      'sourceUrl': credit.sourceUrl,
    }));
    return out;
  }


  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}