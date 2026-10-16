import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Licence metadata for the bundled background photograph.
///
/// Every photograph that ships with software needs its licence to travel with
/// it, and a CC-BY photo legally requires the author's name to be displayed.
/// So this is not decoration: `tool/fetch_photo.py` writes
/// `assets/photo/landscape.json`, and the shell renders [author] next to the
/// album title on screen.
///
/// Fails soft. A missing or malformed file leaves [author] null and the UI
/// simply omits the credit — which would be a licence violation, so the file is
/// committed and the loader logs loudly if it ever goes missing.
class PhotoCredit {
  const PhotoCredit({
    this.title,
    this.author,
    this.license,
    this.licenseUrl,
    this.sourceUrl,
    this.imageUrl,
  });

  final String? title;
  final String? author;
  final String? license;
  final String? licenseUrl;
  final String? sourceUrl;

  /// Where to fetch the full-size image. Null for the bundled photograph, which
  /// is already in the APK.
  final String? imageUrl;

  static const PhotoCredit empty = PhotoCredit();

  /// The photographer's name — what sits next to the album title.
  String? get displayCredit {
    final a = author?.trim();
    if (a == null || a.isEmpty) return null;
    return a;
  }

  /// Populated by [preload], which `main()` awaits **before** `runApp`. That
  /// ordering matters: the shell caches this in a `late final`, so a load that
  /// lands after the first frame would never be picked up and the credit would
  /// silently not render.
  static String? _assetCache;
  static PhotoCredit? _parsed;

  /// Synchronous. Returns [empty] if [preload] has not run or the asset is
  /// missing.
  static PhotoCredit load() {
    final cached = _parsed;
    if (cached != null) return cached;
    final raw = _assetCache;
    if (raw == null) return empty;
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return empty;
      return _parsed = PhotoCredit(
        title: map['title']?.toString(),
        author: map['author']?.toString(),
        license: map['license']?.toString(),
        licenseUrl: map['licenseUrl']?.toString(),
        sourceUrl: map['sourceUrl']?.toString(),
      );
    } catch (e) {
      debugPrint('PhotoCredit: landscape.json is malformed: $e');
      return empty;
    }
  }

  static Future<void> preload() async {
    try {
      _assetCache = await rootBundle.loadString('assets/photo/landscape.json');
      _parsed = null; // force a re-parse
      load();
    } catch (_) {
      _assetCache = null;
      debugPrint(
        'PhotoCredit: assets/photo/landscape.json missing — the bundled photo '
        'will show no author credit, which its licence may require.',
      );
    }
  }
}