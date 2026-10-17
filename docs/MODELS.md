# Model routing

How work gets spread across the available models, and why.

## The problem this solves

Running several agents in parallel on the *same* model looks efficient and is
not: they share one rate-limit bucket. Four concurrent `space-bunny` tasks is
four times the RPM against one ceiling, so the whole batch slows down together
and retries collide. Spreading the same four tasks across four models means each
one sits at a quarter of its own limit.

The rule: **never run two concurrent agents on the same model.**

## Tiers

Assign by what the task needs, cheapest model that can actually do it.

| Model | Use for | Do not use for |
| --- | --- | --- |
| `big-pickle` | Architecture, multi-file design, anything where a wrong call is expensive to undo | Mechanical edits — it is the scarcest and strongest, waste it on nothing |
| `deepseek-v4.1-flash` | Writing new code across several files; test suites; anything needing real reasoning | — |
| `glm-5.3-flash` | Bulk mechanical edits, renames, codegen from a template, wide refactors | Judgement calls |
| `space-bunny-free` | The session's own model. Reviews, verification, talking to you | — |
| `mimo-v2.6-flash` | Parallel side-work that touches disjoint files | Anything that must match existing style closely |
| `longcat-2.5-preview-free` | Second opinion, exploration, reading unfamiliar code | Writing |
| `nemotron-3.5-super-vl-free` | Vision and image analysis — reading screenshots, contact sheets, renders | Text-only work |
| `beam-free` | Overflow capacity when everything else is busy | Work that needs care |

## File partitioning is the real discipline

Spreading models is worthless if two agents edit the same file. Every parallel
task this project has run got a **strict file allowlist** in its prompt, and the
parent merged the results. That is what actually prevented lost work — the model
choice only stops the rate limiter complaining.

Rules that held up:

* One owner per file. If two tasks need the same file, one of them does it.
* Agents that touch `pubspec.yaml` run alone; nothing else edits it concurrently.
* Never two agents in `android/` at once — Gradle output collides and AGP is
  already the fragile part of this build.
* Anything that runs `flutter build` runs alone; `flutter test` is safe in
  parallel with it.

## Worked example — the eight-task pass

The largest parallel run so far used six models across six disjoint file sets:

| Task | Model | Files |
| --- | --- | --- |
| Android platform layer | `codex exec` (external) | `android/**/MainActivity.kt`, `PlatformBridge.kt` |
| Photo sourcing | `step-5-preview-free` | `assets/photo/**`, `tool/fetch_photo.py` |
| Material Symbols | `ling-3.1-flash-free` | `assets/fonts/**`, `pubspec.yaml`, `lib/src/theme/nest_icons.dart` |
| Music player | `mimo-v2.6-flash` | `lib/src/widgets/music_player.dart`, `lib/src/services/adblock.dart`, `docs/MUSIC.md` |
| Themes + dock wiring | `space-bunny-free` (parent) | `lib/src/theme/**`, `lib/src/state/**`, `lib/src/screens/**` |
| Photo rotation | `space-bunny-free` (parent) | `lib/src/services/photo_frame_service.dart` |
| Icon probe / renders | parent | `test/**` |

The music agent was told explicitly not to touch `nest_shell.dart`, which the
parent owned — it shipped an unwired widget as a result, and the parent wired
it. That is the accepted trade: orphan work is cheap to fix, a lost merge is not.

## Independent agents

`codex exec` runs outside the OpenCode rate limiter entirely and accepts a file
allowlist in its prompt, so it is the right tool for a chunk of work you want
*guaranteed* not to hit a limit. It is slower (own agent loop) but it never
competes for a slot.