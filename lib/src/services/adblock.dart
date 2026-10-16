/// Best-effort URL filter for the in-app music WebView.
///
/// ## What this is — and is not
///
/// This is **best-effort cosmetic filtering, not a privacy-grade blocker**.
/// It is a hand-maintained list of ~22 ad-network host suffixes and a host
/// comparison. It has none of the machinery that makes uBlock Origin or
/// AdGuard trustworthy:
///
///  * No filter-list syntax (`||example.com^$third-party,xmlhttprequest`).
///    A suffix match is the whole engine.
///  * No first/third-party distinction, no resource-type classification,
///    no exception rules (`@@` allowlists). If a needed script happens to be
///    hosted on a blocked domain, this filter breaks it with no way to
///    un-break it short of editing the list.
///  * No cosmetic HTML filtering beyond the handful of selectors injected by
///    the widget (see `music_player.dart`), and no support for Adblock Plus
///    "generic hide" rules.
///  * It cannot see requests made *inside* the media stack: an ad whose audio
///    is spliced into the same stream as the content (which is exactly how
///    Spotify serves ads) is invisible to any URL filter.
///
/// Do not present this as an ad blocker to the user. It removes a useful
/// subset of ad requests on YouTube's web player and hides leftover ad
/// containers; it does not make browsing private, does not stop tracking on
/// its own, and will silently fall behind ad networks that change domains.
///
/// The list below deliberately targets the networks that actually appear on
/// YouTube and Spotify web, so it stays small enough to reason about.
library;

/// Host suffixes that are blocked, as plain lowercase domain suffixes.
///
/// A host matches when it equals a suffix or ends with `.<suffix>`, so
/// `'doubleclick.net'` also blocks `ad.doubleclick.net` and
/// `'googleadservices.com'` also blocks `pagead2.googlesyndication.com`-style
/// subdomains of the same parent.
const List<String> kBlockedHostSuffixes = <String>[
  // Google's own ad stack (YouTube web leans on all of these).
  'doubleclick.net',
  'googlesyndication.com',
  'googleadservices.com',
  'googletagservices.com',
  'adservice.google.com',
  'adsystem.com',
  'amazon-adsystem.com',
  // Analytics / measurement that ride along with ad calls.
  'scorecardresearch.com',
  'quantserve.com',
  'crwdcntrl.net',
  // Third-party exchanges and SSPs.
  'adnxs.com',
  'rubiconproject.com',
  'pubmatic.com',
  'openx.net',
  'casalemedia.com',
  '33across.com',
  'adform.net',
  'teads.tv',
  'moatads.com',
  // Not ads strictly, but the same tracking/redirect machinery. Sentry is
  // error reporting, not advertising — blocked only because this is an
  // always-on display that should not phone home on every page error.
  'sentry.io',
  'segment.io',
  'branch.io',
  'hotjar.com',
];

/// Pure-Dart host filter used by the music WebView's [NavigationDelegate].
///
/// See the library documentation above: this is cosmetic filtering with a
/// small hand-written list, not a privacy tool.
class AdBlock {
  const AdBlock._();

  /// Whether [uri]'s host is on the block list.
  ///
  /// Only `http`/`https` URLs with a non-empty host can be blocked; every
  /// other scheme (notably `data:`, which the WebView uses for its own
  /// internals) passes through unblocked.
  static bool shouldBlock(Uri uri) {
    final String scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return false;

    final String host = uri.host.toLowerCase();
    if (host.isEmpty) return false;

    for (final String suffix in kBlockedHostSuffixes) {
      if (host == suffix || host.endsWith('.$suffix')) return true;
    }
    return false;
  }
}
