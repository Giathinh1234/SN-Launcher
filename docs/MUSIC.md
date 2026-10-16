# In-app music player

`lib/src/widgets/music_player.dart` runs a music service's web player inside
the system WebView, with best-effort ad filtering from
`lib/src/services/adblock.dart`.

## The laziness contract

The `WebViewController` is created in `MusicPlayer.initState` — the moment the
widget is mounted, never earlier. Cold start on the target tablet (Nokia T20)
is ~0.8 s idle; an eagerly-created WebView costs several hundred MB of address
space and a live Chromium compositor thread, which would regress that. **Only
build `MusicPlayer` when the music page is actually opened**, and dispose it
(or stop playback) when the page closes.

## What ad blocking can do

The filter has two halves:

1. **Request blocking.** `NavigationDelegate.onNavigationRequest` cancels any
   request whose host equals or is a subdomain of one of the ~22 suffixes in
   `kBlockedHostSuffixes` (doubleclick.net, googlesyndication.com, adnxs.com,
   rubiconproject.com, …). The request never leaves the device.
2. **Cosmetic filtering.** A small JS payload injected on every page start and
   finish removes known ad containers (`ins.adsbygoogle`, `.ytp-ad-module`,
   `.ytp-ad-overlay`, `.video-ads`, `[id^="google_ads"]`, `.ad-container`,
   `#player-ads`, `.promoted-video-renderer`) via a coalesced MutationObserver,
   and stubs `window.adsbygoogle` so ad scripts that check for it find a no-op
   instead of throwing.

On **YouTube web** (`youtube.com`, `music.youtube.com`) this is effective:
pre-roll video ads, overlays and sidebar promoted videos are fetched from
Google's ad domains and live in identifiable DOM nodes, so both halves of the
filter reach them. The `MusicPlayer.canBlockAds` flag is `true` for the YouTube
family and the header says so.

## What ad blocking cannot do

- **Spotify web: ads are not blocked and never will be, with this approach.**
  Spotify inserts its ad break into the *same audio stream* as the content,
  server-side. No URL filter can see that request because it is not a separate
  request — the media segments just change. On top of that, the web player
  requires a login. `canBlockAds` is `false` for Spotify and the header states
  "Ad filtering unavailable — ads are inside the stream". Do not claim
  otherwise in copy, screenshots or commit messages. (Removing Spotify's ads
  legitimately requires a Premium subscription.)
- **It is not a privacy tool.** This is a hand-written list of ~22 suffixes
  with no filter-list syntax, no first/third-party logic, no exception rules
  and no resource-type classification. It will fall behind ad networks that
  change domains, and it does nothing about tracking that happens on
  first-party endpoints. See the library doc comment on `AdBlock`.
- **A broken ad slot can break the page.** There is no allowlist mechanism, so
  if a needed resource happens to live on a blocked domain the only fix is
  editing `kBlockedHostSuffixes`.
- **Error swallowing is deliberate.** Subframe/subresource load failures and
  aborted requests (including the aborts our own blocking causes) are hidden;
  only a main-frame failure shows the error card. Because the WebView plugin
  can drop error codes it does not recognise (DNS failure, connection
  refused), a 45-second watchdog backstops any load that neither finishes nor
  reports a clean error, so the spinner can never hang forever on a dead
  network — worst case the error card appears a little late.

## Data / bandwidth

Every blocked request is a request that is never sent: on an ad-heavy YouTube
session that is dozens of tracking beacons and, more importantly, entire
pre-roll video files (commonly multiple MB each) that are never downloaded.
On a tablet metered by mobile data or a flaky Wi-Fi link that is real money
and real minutes. It also reduces peak memory — no ad video decode buffers.

The trade-off is the WebView itself: loading a full web player costs far more
RAM and battery than a native audio client would, and none of the filter's
savings change that. That is the accepted cost of "music from an adblock
capable browser" on this hardware, paid only while the page is open.

## Adding a source

A source is just a URL plus four parameters:

```dart
MusicPlayer(
  url: 'https://music.youtube.com',
  title: 'YouTube Music',
  backgroundColor: Colors.black,
  foregroundColor: Colors.white,
  // omit canBlockAds: it is inferred — true for the YouTube family,
  // false otherwise.
)
```

- **If the source's ads are real requests from third-party ad domains** (like
  YouTube's), add those domains to `kBlockedHostSuffixes` in
  `lib/src/services/adblock.dart` and add DOM selectors for leftover ad
  containers to `_cosmeticFilterJs` in `music_player.dart`, then pass
  `canBlockAds: true` (or extend `_canBlockAdsForHost` so it is inferred).
- **If the source's ads are inside the media stream** (Spotify's model), leave
  it alone: add the source with `canBlockAds` false or omitted, and let the
  header tell the truth.
- Keep `kBlockedHostSuffixes` short and typed by hand. It is meant to be
  auditable, not comprehensive — for a real blocker this would be a
  subscription to a maintained list, and this app deliberately is not one.
