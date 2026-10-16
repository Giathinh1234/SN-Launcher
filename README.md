# SN-Launcher

**v0.1.0**

A Google Nest Hub style launcher that runs on **Android** and **Unix/Linux/macOS**
desktops from a single Flutter codebase, built to look like the real device and
to stay smooth on e-waste hardware.

> The real Nest Hub UI is itself written in Flutter ("Dragonglass", shipped on
> both Cast OS and Fuchsia), so this is the same technology stack Google chose —
> which is what makes matching its rendering and animation behaviour realistic.

---

## Where the numbers come from

Google has never published a single dp metric, font size, colour value or
animation duration for the Nest launcher. Every constant in
`lib/src/theme/nest_metrics.dart` was therefore **measured**, not guessed:

1. Real photographs of a Nest Hub and a Nest Hub Max were downloaded.
2. The four display corners were found in each photo.
3. A homography was solved and the photo was rectified onto the device's flat
   native canvas — `1024x600` for the Hub, `1280x800` for the Max.
4. Pixel runs for each glyph, icon and hairline were read off the rectified
   image with NumPy.

The rectified references live in `refs/`. The result is verified by rendering
the app headlessly at device resolutions and diffing the two — see
[Verification](#verification) for the measured error.

### Two things the naive approach gets wrong

**The two devices are not the same shape.** The Nest Hub is 1024x600
(1.707 aspect) and the Hub Max is 1280x800 (**1.600**). They share a 1.25x
width scale but a 1.333x height scale. Copying the Max's pixel offsets onto the
Hub's canvas with one uniform factor lands the sheet rows about 24px too low.
Everything inside the bottom sheet is therefore positioned as a **fraction of
the sheet's own height**, which is stable across both devices and across any
odd-shaped screen.

**Google Sans sets its digits far wider than the Nest's clock.** Its digit
advance is 0.643 em, rendering `09:45` at 220px where the device measures
**195px**. The tracking has to be pulled in (`letterSpacing: -2.15`) to match.

### Measured geometry (1024x600 design canvas)

| Element | Measured on device | In this build |
| --- | --- | --- |
| Clock digit block | 61 px tall, y 461–521 | **61 px, y 461–521** |
| `"09:45"` run width | 195 px, x 69–264 | **194 px, x 69–262** |
| Date line | 120 px wide, cap top y 422 | **123 px, y 424** |
| Temperature | 42 px wide, 26 px cap | **42 px, 26 px** |
| Album title | 119 px wide, right edge x 973 | **117 px, x 970** |
| Drag handle | 41 x 5.6 px | matches |
| Sheet top | 49.6 % of screen height | matches |
| App badge | 100 px across (Max) | matches |
| App row pitch | ~148 px (Max) | **147 px** |
| Sheet surface colour | `#EFEDE6` | matches |

Max residual error is **9 px on a 1280-wide canvas (0.7 %)**.

### Typography

The device uses **Google Sans**. Google released it under the SIL Open Font
License, so the genuine face is bundled rather than an approximation — it is
the single biggest reason the clock reads as "Google" instantly. Poppins is
included at weight 300 for the device's thinner "Timeless Light" clock face.

---

## Hybrid CPU / GPU

The two halves are used deliberately, and neither is asked to do the other's job.

**GPU does everything spatial.** Rasterisation and compositing run on Impeller
over Vulkan — every gradient, glyph path, badge and the sheet itself. The
ambient background is one `CustomPaint`; the launcher sheet is a `RepaintBoundary`
so it rasterises once and is then only blitted while it slides. Measured GPU
memory on the T20 is **564 KB**.

**CPU does everything blocking.** Anything that can stall — a socket read, a JSON
decode — runs on a worker isolate, never the UI thread:

```dart
// top-level, deliberately: inside a method the AOT compiler folds `this` into
// the closure context and Isolate.run refuses to send it.
Future<_WeatherReading?> _fetchOnWorker(double lat, double lon) =>
    Isolate.run(() => _fetchAndParse(lat: lat, lon: lon));
```

Frame *cost* stays on the UI thread where it belongs: layout, hit testing and the
gesture state machine.

**The GPU path can be swapped at build time.** Some older or badly-finned
Mali/Adreno drivers misbehave under Vulkan, and there the engine's Skia/OpenGL
backend is the reliable one:

```bash
flutter build apk --release -PenableImpeller=false
```

The switch is a Gradle property (`enableImpeller` in `android/gradle.properties`)
resolved into the manifest placeholder. Confirmed working on the T20 — the engine
logs `Impeller opt-out deprecated… opted out of Impeller`. Note that Flutter is
deprecating this escape hatch, so treat it as a compatibility valve rather than a
long-term strategy.

**Frame timing is measurable on-device**, which matters because `dumpsys gfxinfo`
reports zero frames for any Flutter app (Flutter bypasses Android's HWUI
pipeline) and SurfaceFlinger cannot sample a BLAST-backed surface:

```bash
flutter build apk --release --dart-define=PERF_OVERLAY=true
```

It adds a corner readout of average/worst frame cost and a jank count. Off by
default, so it costs nothing in a normal build.

---

## Running on weak hardware

This is a 1–2 GB device target, so the architecture is built around cost, not
around convenience.

**Vector icons, not PNGs.** All 24 launcher glyphs and the 7 quick-settings
glyphs are `CustomPainter` paths (`lib/src/widgets/nest_glyphs.dart`). A PNG
icon set would cost several MB of decoded texture resident on the GPU, which is
precisely what a 1 GB tablet cannot spare — and it would be blurry on a 4K
monitor. Paths cost nothing to load and are sharp everywhere.

**One paint pass for the background.** The ambient gradient plus its centre
bloom is a single `CustomPainter`. A stack of translucent containers would
force an offscreen compositing layer each; this is effectively free.

**Minute-resolution clock by default.** `ClockService` only wakes on the minute
boundary unless seconds are enabled, and it aligns to the wall clock so digits
never stutter. The clock block sits behind its own `RepaintBoundary`, so a tick
repaints ~200 px² instead of the whole screen.

**Layer hygiene.** The drawer sets `addRepaintBoundaries: false` and
`addAutomaticKeepAlives: false` — 24 cells do not each need a retained layer on
a device with a small GPU memory budget.

**No blur, ever.** `BackdropFilter` is the single most expensive primitive in
Flutter on low-end GPUs. The real Nest does not blur its sheet either; it uses
a flat scrim, so there is nothing to lose.

**Right-sized heap.** `android:largeHeap="false"` plus conservative Gradle JVM
args keeps the build and the app inside a small memory envelope. `minSdk` is
21, which covers essentially every e-waste Android tablet still in circulation.

---

## Input

| | |
| --- | --- |
| Touch | Swipe up from the bottom to open the launcher, past the detent for the full grid; swipe left/right for the page carousel; tap the centre to talk |
| Keyboard / D-pad / Android TV remote | Arrow up opens, down closes, left/right move pages, Esc backs out, Space toggles listening |
| Microphone | **Removed.** Tap-to-talk claimed "Listening…" with no microphone attached and its animation was visibly broken, so the code was deleted rather than switched off. See [docs/DEFERRED.md](docs/DEFERRED.md) |
| MCP / remote | The whole shell is driven through `ShellController`, so a remote or MCP bridge only needs to call its public verbs |

---

## The quick-settings row actually does things

Four of the seven buttons used to be theatre. Brightness mutated a private
field that nothing read; camera printed a toast reading "Camera toggled" and
settings printed "Settings" — claiming an action neither had performed, which is
worse than doing nothing because the user believes the device responded.

Every button is now wired to a real platform capability over one MethodChannel
(`dev.snlauncher/platform`), implemented in `PlatformBridge.kt`:

| Button | What it does | Verified on the T20 |
| --- | --- | --- |
| Brightness | `window.attributes.screenBrightness`, plus `SCREEN_BRIGHTNESS_MODE_MANUAL` when the app is allowed to write it | panel mean luma 206 → 75 |
| Volume | `AudioManager.setStreamVolume(STREAM_MUSIC, …)` | `dumpsys audio` logs `setStreamVolume index:13` from this package |
| Camera | `ACTION_IMAGE_CAPTURE`, falling back through the other camera intents | foreground became `com.android.camera2/.CaptureActivity` |
| Theme | Cycles Dynamic → White → Day → Afternoon → Night, persisted | survives a cold restart |
| Digest | Closes the sheet, then opens the digest | sheet luma changed |
| Feedback | Opens the Nest support page | foreground became Chrome |
| Settings | `Settings.ACTION_SETTINGS` | foreground became `com.android.settings` |

`tool/test_dock.sh` runs this whole table against a connected device. The one
rule the implementation follows: **never report an action that did not happen.**
If the platform refuses, the toast names the failure ("No camera on this
device") rather than claiming success.

Two details worth keeping in mind if you extend it:

* The Dart setters update local state *first* and push to the platform
  fire-and-forget. Awaiting the channel inside a drag handler makes the
  brightness arc stutter. The platform's answer is then reconciled back,
  because Android quantises to its own steps and will not be where you asked.
* `WRITE_SETTINGS` is deliberately **not** declared. The system brightness write
  degrades gracefully; the window brightness needs no permission at all.

---

## Themes

Five, selectable from the digest page or by tapping the theme button:

| | |
| --- | --- |
| **Dynamic** | Follows the clock — the old 24-keyframe Ambient EQ ramp, continuously interpolated |
| **White** | Flat paper white |
| **Day** | The Nest's measured daylight paper (238, 234, 228) with a cool cast |
| **Afternoon** | Warmer and lower contrast |
| **Night** | Soft blue-black |

Two things changed deliberately:

**The dark themes are lighter.** The old night palette ran down to `#070A14`.
On an OLED-less e-waste LCD that does not read as "dark" — it reads as *off*,
and the user assumes the device has hung. The floor is now `#121826`, which
still clearly says night but leaves the panel visibly alive.

**A pinned theme is flat and does not drift.** Someone who pinned White asked
for white. A wall display that changes colour while someone is reading it is
worse than one that is consistently dull. The bloom is also suppressed on flat
palettes — a cream hotspot across a white background reads as dirt.

Persistence is a 60-line `SettingsBridge.kt` over `SharedPreferences` rather
than the `shared_preferences` plugin, because this project's Android build is
already fragile (AGP shells out to `sdkmanager` during configuration, which is
why the Gradle configuration cache has to stay off) and one more plugin is one
more thing to go wrong for the sake of a dozen strings.

---

## Icons: Google's, not ours

The launcher grid used to be 31 hand-plotted `CustomPainter` paths. The stroke
weight was uniformly 4.2% of the box with round caps, which is no real design
system's optical weight, and that mismatch is most of what made it read as
generic Android.

They are now Google's own Material Symbols, subsetted by `tool/build_icons.py`:

* **15.2 MB → 35 KB.** The upstream variable font carries four axes (FILL,
  GRAD, opsz, wght) that Flutter's `IconData` cannot address, so three of them
  are dead weight. The build subsets to the 172 glyphs actually used and freezes
  the axes to one static instance. Flutter then tree-shakes the result to 7 KB.
* **Codepoints come from Google's authoritative `.codepoints` file**, never
  guessed, and are cross-checked against the subset's own cmap before
  `nest_icons.dart` is written. A wrong codepoint renders as the wrong icon or a
  blank box and neither is obvious until you look at it.
* **Licence is Apache 2.0**, not OFL — easy to get wrong when every other asset
  in the project is OFL.
* **Brand marks stay as paths.** Spotify, Netflix, Pandora and YouTube have
  their own logos; substituting one approximation of a logo with another is
  strictly worse than either. Only the generic icons were replaced.

`test/icon_probe_test.dart` renders a labelled contact sheet and
`flutter_test` renders everything else with Ahem unless the real font is loaded
by hand — so a screenshot can show a grid of boxes and still "pass". Both the
probe and `render_shell_test.dart` load the font explicitly for that reason.

---

## The photo frame rotates

The background changes every 10 minutes. Controls are on the digest page:
**Rotate** on/off, **Next now**, and 5 / 10 / 30 / 60 min / 6h.

Four constraints shaped it, all from the hardware it has to survive:

* **The bundled photograph paints at launch.** Anything downloaded is a later
  upgrade, so cold start never waits on the network and stays at 0.8s.
* **`FileImage`, not `MemoryImage(File.readAsBytesSync())`.** Reading the file
  inside `build()` defeats the image cache and costs a full JPEG decode per
  frame on a UNISOC.
* **The API is asked for a 1600px thumbnail**, which is already the right size.
  Re-encoding would only convert a 300 KB JPEG into a 2 MB PNG — `dart:ui` has
  no JPEG encoder.
* **Plain `dart:io` HttpClient.** One less dependency on a 1 GB tablet.

### The pool is verified, not remembered

The first version hand-wrote twelve Wikimedia Commons filenames from memory.
**Four of them resolved.** Five were 404 and one was CC BY-SA — share-alike,
which a launcher may not install — so the rotation would have silently skipped
most of its own pool, every cycle, forever.

It was rebuilt properly: search Commons, keep only PD / CC0 / CC-BY with no
SA/NC/ND, download the candidates, and **look at all thirty**. Rejected a
satellite map with baked-in labels, two paintings, one carrying a visible gallery
watermark, one containing people, and the washed-out and over-saturated strays.

`tool/verify_photo_pool.py` confirms every entry still resolves and is still
licence-clean against the live API. It exits non-zero, so it belongs in CI.

This is a deliberate choice over "fetch something random". A photo frame on a
wall is looked at constantly; a random image search will eventually put a
portrait, a chart, or a screenshot of someone's desktop on it.

---

## Music

The digest page opens YouTube or Spotify in an in-app WebView. **The WebView is
constructed only when you tap one** — building one at app start would add a
WebView and its first page load to a cold start that measures 0.8s.

### Ad blocking: what it actually does

Being straight about this, because "ad-block capable" oversells it:

| Source | Ads blocked? | Why |
| --- | --- | --- |
| **YouTube** | **Yes** | Ads are separate DOM elements and media requests, so a URL filter plus a DOM scrubber removes them |
| **Spotify** | **No, and it cannot be** | The ad break is inserted *server-side into the audio stream*. There is nothing on the client to filter. The web player also needs you to log in. |

The filter is a host/path blocklist over `doubleclick.net`,
`googlesyndication.com`, `adsystem.com`, `scorecardresearch.com`, `adnxs.com`,
`crwdcntrl.net` and similar, plus injected JavaScript that removes ad
containers and stubs `window.adsbygoogle`.

This is **best-effort cosmetic filtering, not privacy**. It does not stop
tracking beacons, does not survive a site redesign, and is not a substitute for
uBlock Origin. See `docs/MUSIC.md`.

---

## Calendar, weather and the photograph

**Calendar** reads `CalendarContract.Instances` through the platform channel,
asks for `READ_CALENDAR` once, and refreshes every five minutes and on resume.
The card distinguishes "permission not granted" from "nothing else today" —
the first version said "No more events today" in both cases, which claims you
have a free day when in fact nothing was ever read.

**Weather** is unchanged: Open-Meteo, no key, degrades offline. It still needs a
pinned location (`--dart-define=NEST_LAT=… --dart-define=NEST_LON=…`), because a
runtime location prompt is a real cost on a wall-mounted tablet nobody taps
again.

**The background is a real photograph** — *Cub Lake at dawn in Rocky Mountain
National Park* by **Debra Miller**, public domain as a work of the US National
Park Service. Fetched and licence-verified by `tool/fetch_photo.py`, which
fails closed: if the live licence is not public domain, CC0 or plain CC-BY, it
writes nothing.

The photographer's name is rendered on screen next to "Recent highlights",
which is what the licence and plain decency both ask for. Commons' `Artist`
field for that file reads "NPS Natural Resources" — the owning agency, not the
person who took the photograph — so the fetcher prefers the real name.

The photo decodes at its intrinsic width, never wider: on a 2000px panel a
1600px file decoded at 2000 would spend ~3 MB of extra bitmap on detail that
does not exist.

---

## Layout

```
lib/
  main.dart                          app entry, orientation lock, immersive mode
  src/
    theme/
      nest_metrics.dart              every measured constant, design-canonical
      ambient_palette.dart           the five themes + 24h time-of-day keyframes
      nest_type.dart                 Google Sans type scale
      nest_theme.dart                Material 3 ColorScheme from the palette
      nest_icons.dart                GENERATED Material Symbols subset
    models/
      nest_action.dart               the 21 "Actions on Google" + quick settings
      photo_credit.dart              licence metadata for the bundled photograph
    services/
      clock_service.dart             aligned, minute-resolution ticking
      weather_service.dart           Open-Meteo, no key, degrades offline
      calendar_service.dart          CalendarContract feed, permission-aware
      platform_bridge.dart           typed MethodChannel wrapper
      settings_store.dart            tiny persistence, no plugin
      action_launcher.dart           Android intents / Linux binaries / macOS bundles
    state/shell_controller.dart      pages, sheet, assistant, theme, brightness, volume
    widgets/
      ambient_background.dart        one-pass ambient gradient + drag handle
      nest_glyphs.dart               vector icon painters
      clock_block.dart               date / clock / weather / album title
      launcher_sheet.dart            app row + quick settings
      app_drawer.dart                six-column "See all" grid
      assistant_orb.dart             Google four-dot Assistant mark
    screens/nest_shell.dart          gesture layer and z-order
test/render_shell_test.dart          renders the shell to PNG at device resolutions
refs/                                rectified reference photographs
```

---

## Verified on real hardware

Tested on a **Nokia T20** (Android 13, 3.8 GB RAM, UNISOC T610 / Mali-G52,
1200x2000, 60 Hz) — squarely inside the e-waste target. Impeller/Vulkan, release
build, arm64.

| | measured | expected |
| --- | --- | --- |
| Clock block, left edge | 135 px | 135 px |
| Clock block, digit height | 116 px | 119 px |
| App badge pitch (sheet + drawer) | 118.0 px | 118 px |
| Sheet app-row centre | 810 px | 811 px |
| Sheet top edge | 605 px | 604 px |
| Frame cost, idle | 10.9 ms | ≤ 16.7 ms |
| Frame cost, sheet animation | 11.0 ms | ≤ 16.7 ms |
| Total PSS | 65 MB | — |
| **GPU memory** | **564 KB** | — |

The GPU figure is the one worth keeping: it is the payoff for drawing every icon
as vector paths. A PNG icon set would have cost several MB of resident texture.

Four bugs only real hardware could surface:

1. **First-frame MediaQuery.** The first frame reported a smaller size than the
   settled one, and `late final` locked the shell to the wrong scale for its
   whole life — everything rendered 5% small. Metrics are now recomputed per
   frame.
2. **Animation controllers weren't in the listen list.** The shell listened to
   `ShellController` (a `ChangeNotifier`) but the sheet and carousel animate
   *separate* `AnimationController`s, which notify their own listeners. The UI
   only repainted by accident whenever the clock ticked; the sheet froze
   part-way through opening.
3. **Bottom-edge swipes arrive as cancels.** Android claims a swipe that starts
   on the very bottom edge for its own gesture. Without settling on cancel the
   sheet stuck at ~65% open.
4. **Immutable frame cost.** The sheet animation ran at 17.2 ms — over budget.
   Every frame of the drag was rebuilding the clock, the carousel and the whole
   bottom sheet. Scoping the sheet to its own `AnimatedBuilder` and giving it a
   `RepaintBoundary` brought it to 11.0 ms.

Back is also handled now: it backs out one level instead of quitting the app,
because a launcher should never be dismissed by Back.

---

## Verification

```bash
flutter test test/render_shell_test.dart     # writes build/shots/*.png
```

Renders the shell headlessly at 1024x600 and 1280x800 across the day/night
palette, the launcher sheet and the drawer, so the layout can be diffed against
`refs/`.

Two things the harness has to handle, both discovered the hard way:

- `toImage()` / `toByteData()` do real async work on the raster thread and only
  progress inside `tester.runAsync()`.
- `ClockService(autoTick:)` and `NestShell(animateDecorations:)` exist purely so
  screenshots can disable the self-rescheduling clock timer and the looping
  weather/Assistant animations — otherwise the fake-async zone never quiesces.

---

## Build

```bash
flutter pub get
flutter build apk --release          # Android, per-ABI splits
flutter build linux --release        # Linux kiosk
flutter build macos --release        # macOS
```

### Raspberry Pi / Linux kiosk

The Linux runner understands two flags:

```bash
nestlaunch --kiosk            # undecorated, fullscreen
nestlaunch --size=1024x600    # force an exact panel size
```

---

## Deliberately deferred

Four things, written up in full in [`docs/DEFERRED.md`](docs/DEFERRED.md):

1. **Tap-to-talk / listening** — *removed*, not deferred. Documented so a
   rebuild does not repeat it, but there is no flag left to flip.
2. **MCP / remote control** — `ShellController` already exposes every verb, so
   the bridge is small; the transport and auth model are the real work.
3. **Ambient light sensor** — `adaptToAmbientLight()` works but nothing feeds it.
   Most target hardware has no light sensor, and faking it would be worse.
4. **Weather location** — build-time `--dart-define` only. The store is already
   there; the missing part is a UI and a decision about first acquisition.

### Detail on the deferred list

### MCP / remote control — put down for now

Originally this had MCP (Model Context Protocol) in the input table: driving the
launcher from an AI assistant or another device. **That has been taken out and
parked deliberately.** It is not half-built and not broken — it was cut before
any protocol code was written, to keep v1 focused on the launcher itself.

It can be picked up later, and it will be cheap when it is, because the work is
already done: `ShellController` is the single owner of page navigation, the
sheet, the assistant state, brightness, volume and DND, and every one of those is
already a public method. A remote or MCP bridge needs to call those methods and
nothing else — there is no UI state to reverse-engineer, and no platform channel
to add. The only genuinely new pieces would be the transport and an auth story.

### Other known gaps

- Microphone wake word and speech-to-text are not wired up; the Assistant
  animation is driven by a timer.
- Launching apps is implemented (deep links / native binaries) but untested on
  a real device.
- The photo-frame background is a flat ambient gradient — wiring up a real photo
  library is the next visual milestone.
- Quick-settings tiles currently show state but do not yet change system volume
  or brightness.
- The nested `_DigestPage` / `_HomeControlPage` cards are placeholder content,
  not wired to real calendar or device data.
- Weather works, but only via the pinned-coordinate build flag — there is no
  runtime location prompt or geocoding yet.