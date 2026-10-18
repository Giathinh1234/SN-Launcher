# The two builds

There are **two** versions of SN-Launcher in existence. They are the same Dart
source. The only difference is which JSON file the `SN_FEATURES` define points
at, so any behavioural difference between them is a gating bug and never a
change in code.

| | `ef` — ExtraFeature | reduced |
|---|---|---|
| What it is | Everything switched on. For finding out what actually happens. | A launcher and nothing else. This is the one that ships. |
| Config | `assets/features.ef.json` | `assets/features.json` |
| Features on | all 9 | 2 — `settings`, `quickSettings` |
| Build | `./tool/build_variants.sh ef` | `./tool/build_variants.sh reduced` |

Both keep settings and quick settings. A launcher you cannot configure, and
cannot change the brightness of, is not a launcher — and you asked for settings
to survive in both.

## Telling them apart on a device

They share an `applicationId` (`dev.snlauncher.snlauncher`), so **installing one
replaces the other** and the launcher icon looks the same either way. They
cannot sit side by side on one device.

Open **Settings → Build**. It names the variant, the config file, and how many
features are on. Read it rather than inferring the build from behaviour.

They can, however, sit on *two different devices* at once, which is the
comparison this was built for.

## Changing what is in a build

Edit the JSON and rebuild. Nothing else needs touching.

```jsonc
{
  "features": {
    "assistant": true,     // lightbar, centre-tap listener, voice
    "music": true,         // WebView player card
    "photoRotation": true, // rotating background + Photos card
    "themePicker": true,   // Theme card on the digest page
    "calendar": true,      // Calendar card
    "digestPage": true,    // the whole second page
    "weather": true,       // Weather card
    "settings": true,      // the gear, and the Settings button in the dock
    "quickSettings": true  // the dock row itself
  }
}
```

`settings` and `quickSettings` are what "a launcher" means here; everything else
is an extra.

## How it behaves when the config is wrong

Deliberately, in every case the same way: **off**.

- missing file, unreadable, malformed JSON, a JSON array instead of an object
- a value that is not a boolean — `"yes"` is not `true`
- a flag this build does not implement — ignored, and reported on the console

A broken config must never produce a launcher that *claims* capabilities it was
not built with. That is the rule that killed the four-dot Assistant orb, and it
is why a typo fails visibly instead of quietly enabling something.

If a key is misspelled, `FeatureFlags.unknown` reports it and the console prints
the name. A silently ignored typo is how an afternoon disappears.

## The tests that hold this up

`test/feature_flags_test.dart` reads the two JSON files **off disk** rather than
through `FeatureFlags.load`, because a test that goes through the loader cannot
tell you whether `assets/features.json` is correct.

`test/feature_gate_widget_test.dart` renders the real shell under each shipped
config and asserts on what is actually on screen.

Every gate in `nest_shell.dart` was mutation-checked: delete the gate and a
named test fails. Two of these tests originally passed for the wrong reason and
were rewritten after the mutation check caught it —

- the lightbar test passed because the harness supplied no `AssistantService`,
  so the bar was absent in both builds regardless of the flag
- the digest test passed because the per-card gates already emptied the card
  row, so deleting the page-level gate changed nothing observable

Neither shipped config has `settings` off, which meant the gear gate was
untested until a third configuration was added that switches it off.