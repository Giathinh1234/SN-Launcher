# Deferred

Things that were built and then deliberately turned off, or not built at all.
Kept here so a future session picks them up instead of rediscovering the
reasoning.

Read this before touching `kAssistantEnabled`.

---

## 1. Tap-to-talk / the Assistant orb — DISABLED

**Status:** off. `const bool kAssistantEnabled = false` in
`lib/src/state/shell_controller.dart`. Flip it to `true` to bring the mock back.

**What it did when on:** tapping anywhere on the home screen (or pressing
Space/Enter on a remote) started a four-dot orb that played a looping
"breathing" animation, captioned **"Listening…"**, which after a beat became
**"Thinking…"**, then timed itself back to idle on its own.

**Why it is off — two separate reasons.**

*It was a lie.* There is no microphone. No audio is captured, nothing is
transcribed, no request goes anywhere. The caption said "Listening…" and then
"Thinking…" while the device did absolutely nothing in between. A user who
tapped it was told the launcher understood them. That is worse than the feature
being absent, because it destroys trust in every other status message on the
device — if "Listening…" is fake, is the weather fake?

*The animation was visibly broken.* `_OrbPainter` did **not** respect
`animateDecorations`. Its `AnimationController` called `..repeat()` in its field
initialiser, unconditionally, so there was no static frame to ever capture. Two
concrete consequences:

- Each dot scaled up to **1.45x** on its own phase offset, so at any instant the
  four dots were four visibly different sizes.
- Each dot's colour lerped from a **muddy grey-blue** (`idleColor`, the palette
  ink at 55% alpha) up to its brand colour. Caught mid-lerp, Google's yellow
  `#FBBC04` rendered as dark olive and its green `#34A853` as dark forest. The
  mark looked like a mistake rather than a logo.

This was only found by rendering it and *looking* — see
`build/shots/assistant_1024x600.png` in the commit that disabled it. The unit
tests passed the whole time.

**What a real implementation needs, in order:**

1. `RECORD_AUDIO` permission and a runtime request, with a real refusal path.
2. An actual capture path. Android: `SpeechRecognizer` or a `MediaRecorder`
   push-to-talk button. Both need a user gesture; neither works hands-off.
3. A wake word. `SpeechRecognizer` can do hotword recognition on some devices,
   but not reliably, and not at all on the low-end hardware this project
   targets. On a 1 GB tablet a continuous hotword loop is likely to cost more
   battery than the whole rest of the app.
4. A transport. On-device intent fulfilment needs a local model or a backend
   call; on a LAN-only smart display, neither is free.
5. An honest failure surface. If it cannot hear you it must say so, not animate.

**Point 5 is the real lesson.** The feature failed not because it was hard but
because it was allowed to *claim* capability it did not have. Whatever replaces
it should never reach a state where the UI asserts something that is not true.

---

## 2. MCP / remote control — NOT STARTED

The user asked for this early, then deferred it. Nothing is built.

It is cheap when it is time: `ShellController` already owns every verb the shell
can perform (`goToPage`, `openAction`, `setTheme`, `setBrightness`,
`setVolume`, `toggleSheet`, `cycleTheme`). A bridge only needs to call those
public methods and serialise the arguments; no UI work is required.

The hard part is not the bridge, it is the transport and the auth model — and
neither should be built before the thing it drives is stable.

---

## 3. Ambient light sensor — NOT STARTED

`AmbientPalette.adaptToAmbientLight()` exists and works, but `_ambientLight` in
`ShellController` is pinned at `0.5`, so the Dynamic theme follows the **clock
only**. The room's actual light level is never read.

This is a deliberate omission, not an oversight: the Nest Hub has a light sensor
and this most likely does not, so the behaviour would be wrong on the hardware
being targeted. It needs a `SensorManager` bridge method returning
`TYPE_LIGHT` in lux, and a sensible fallback (probably "stay at 0.5 and do not
lie about it") on devices without the sensor.

---

## 4. Weather location — BUILD-TIME ONLY

`WeatherService` works and is verified against the live Open-Meteo API, but
location is pinned at compile time:

```
--dart-define=NEST_LAT=-33.86 --dart-define=NEST_LON=151.20
```

There is no runtime location picker, because a runtime location prompt on a
wall-mounted tablet that nobody taps again is a real cost, and an IP-based
fallback is a privacy decision that has not been made yet.

`SettingsStore` is already in place, so persisting a chosen location is small —
the missing piece is the UI and the decision about how the first location is
acquired.