# Deferred

Things that were built and then deliberately turned off, or not built at all.
Kept here so a future session picks them up instead of rediscovering the
reasoning.

Item 1 is the reason this file exists: the listening feature was **deleted**, not
flagged off, because it lied to the user about what the device could do.

---

## 1. Tap-to-talk / listening — REBUILT

**Status: done.** It was deleted once and then rebuilt properly. This entry is
the record of why it was deleted, because the reason is the whole design brief
for what replaced it.

### Why the first version was deleted

It claimed capability it did not have. Tapping the screen played a looping
four-dot mark captioned "Listening…", which became "Thinking…", then timed
itself back to idle. No microphone was attached, nothing was transcribed, and
no request went anywhere. A user who tapped it was told the launcher understood
them.

The animation was separately broken: `AnimationController.repeat()` was called
in a field initialiser, so it ignored `animateDecorations` entirely — there was
no static frame to ever capture, which is why the unit tests passed throughout
and only rendering it revealed that each dot scaled to 1.45x on its own phase
and Google's yellow lerped through olive.

### Why that matters for the replacement

The feature failed not because speech is hard but because **the UI was
permitted to assert something untrue.** Every rule below exists to stop that
happening again:

* The lightbar only moves after recognition has genuinely started.
* A silent room, a denied permission, a missing engine and a timeout all
  produce "did not catch that" — never a fabricated transcript.
* A local intent that is *understood* but which the hardware refuses reports
  the refusal, rather than falling through to the remote and implying the
  remote answered.
* Recognition is **one-shot**. A leaked `SpeechRecognizer` holds the
  microphone, which is visible in `dumpsys media.audio_flinger` and is exactly
  the always-listening behaviour this app exists to avoid.

If you extend this, the test to write is not "does it recognise 'turn on the
lights'" — it is "does it stay silent when there is nothing to hear".

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