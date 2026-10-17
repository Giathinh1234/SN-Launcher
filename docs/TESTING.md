# Testing on new hardware

This launcher targets e-waste: old Android tablets, HDMI sticks, repurposed
phones, and the occasional Raspberry Pi. Every one of those differs in ways that
have broken something before, so this is what to check, in the order that finds
the most.

## Before anything: get it on there

```bash
./tool/deploy.sh                    # finds it via mDNS
./tool/deploy.sh 192.168.1.55       # or tell it where to look
./tool/deploy.sh --scan             # sweep the /24 if you don't know the address
```

`deploy.sh` does the things that are easy to forget and silently invalidate a
test: extends the screen timeout before capturing anything, dismisses the
keyguard, and checks the screenshot is not black. A sleeping tablet's first
screenshot is a black rectangle, and every measurement taken from one is
meaningless.

Wireless debugging assigns an **ephemeral port**. The address that worked last
time may not work now — that is why discovery exists rather than a constant.

## The five checks that matter

**1. Does the geometry match?** `adb logcat -s flutter` prints
`NESTLAUNCH-GEOMETRY size=…x… dpr=… u=…` on launch. Compare `u` against a
known-good device. A wrong first-frame MediaQuery has silently cost 5% of
scale before; it would show up here.

**2. Are the pixels in the right place?**

```bash
./tool/e2e.sh          # installs, exercises every gesture, verifies layout
```

`tool/verify.py` measures the clock block and the badge row against constants
taken off a rectified photograph of a real Nest Hub, and **asserts the screen
state it expected**. That assertion is the point — it is what catches a gesture
that silently did nothing instead of reporting confident numbers measured
against the wrong screen.

```bash
python3 tool/verify.py build/device/dev_home.png home    # 0 = good, 1 = FAIL
python3 tool/verify.py build/device/dev_sheet.png sheet
python3 tool/verify.py build/device/dev_drawer.png drawer
```

**3. Do the quick-settings buttons work on *this* hardware?** Several are
platform capabilities, not app code, and will fail differently on a device
without the feature:

```bash
./tool/test_dock.sh
```

Brightness and volume are the ones that vary most. Volume on a device with no
media volume can report success and change nothing.

**4. Is it smooth?**

```bash
flutter build apk --release --dart-define=PERF_OVERLAY=true
adb shell am force-stop dev.snlauncher.snlauncher
adb shell am start -n dev.snlauncher.snlauncher/.MainActivity
# overlay is top-left; watch it while dragging the sheet
```

Do **not** trust `dumpsys gfxinfo` — it reports zero frames for any Flutter app,
because the app bypasses HWUI, and SurfaceFlinger cannot sample the BLAST
surface. The overlay is the only source of truth.

**5. Memory.** `adb shell dumpsys meminfo dev.snlauncher.snlauncher`. The
reference device was 71 MB PSS / 664 KB GPU. A photo-frame build adds a decoded
bitmap; the decode is clamped to the photo's intrinsic width precisely so a
bigger panel does not silently cost more.

## Known hardware differences

| Difference | What it affects | Where it is handled |
| --- | --- | --- |
| No light sensor | Ambient EQ falls back to clock-only | one-shot `lightLevel`, returns null |
| No camera | Camera button says so rather than claiming success | `hasCamera` gate |
| No audio output | Volume may report success and do nothing | — known gap |
| Low RAM (<1 GB) | Decode width and image cache | clamped to intrinsic width |
| NVIDIA Tegra | Impeller/Vulkan can misbehave; Skia/GL is reliable | `-PenableImpeller=false` |
| Very old GPU drivers | Same | same flag |
| Portrait panel | Layout scales from the 1024x600 design canvas | `NestMetrics` recomputed per frame |

The Impeller flag is the one to reach for if rendering is broken or hangs on a
new chipset:

```bash
flutter build apk --release -PenableImpeller=false
```

Flutter is deprecating that escape hatch, so treat it as a compatibility valve
rather than a plan.

## Linux / Raspberry Pi

Cannot be cross-compiled — build on the machine that will run it:

```bash
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev
./tool/build_all.sh          # or: flutter build linux --release
```

Then:

```bash
./SN-Launcher --kiosk            # undecorated, fullscreen
./SN-Launcher --size=1024x600     # force an exact panel size
```

## What is not finished

* **MCP / remote control** — `ShellController` owns every verb, so the bridge is
  small; the transport and auth are the real work.
* **Windows** — no runner configured.
* The four-dot Assistant orb was deleted once and rebuilt as a rainbow lightbar.
  `docs/DEFERRED.md` explains why, and that reason is the test to write when
  extending it: not "does it hear turn on the lights" but "does it stay silent
  when there is nothing to hear".