# Deferred

Things that were built and then deliberately turned off, or not built at all.
Kept here so a future session picks them up instead of rediscovering the
reasoning.

Item 1 is the reason this file exists: the listening feature was **deleted**, not
flagged off, because it lied to the user about what the device could do.

---

## 1. Tap-to-talk / listening — REMOVED, not deferred

**Status: the code is gone.** Not flagged off — deleted. `AssistantState`,
`kAssistantEnabled`, `beginListening`/`stopListening`, `assistant_orb.dart` and
the overlay are all removed. Nothing is left to switch back on by accident.

The user asked for it to be removed outright rather than parked, so this entry
exists only to record *why*, in case it is ever rebuilt.

It was removed for two reasons, both confirmed by rendering it and looking:

1. **It claimed capability it did not have.** Tapping the screen played a
   looping four-dot mark captioned "Listening…", which became "Thinking…", then
   timed itself back to idle. No microphone was attached, no audio was
   captured, and nothing was transcribed. A user who tapped it was told the
   launcher understood them.

2. **The animation was visibly broken.** `AnimationController.repeat()` was
   called in a field initialiser, so it ignored `animateDecorations` entirely —
   there was no static frame to ever capture, which is why the unit tests passed
   throughout and nobody noticed. Each of the four dots scaled to 1.45x on its
   own phase, so they were four different sizes at any instant, and each lerped
   from a muddy grey-blue to its brand colour. Caught mid-lerp, Google's yellow
   `#FBBC04` rendered as dark olive. The mark read as a mistake, not a logo.

The lesson, worth keeping: this failed not because speech is hard but because
the UI was permitted to assert something untrue. Whatever replaces it must not
be able to reach a "listening" state without a real microphone behind it.

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