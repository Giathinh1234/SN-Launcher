# The assistant, honestly

What the built-in assistant can and cannot do, and where a request goes when it
leaves the device. Three backends, chosen in Settings:

| Backend | Needs | Leaves the device? |
| --- | --- | --- |
| Local intents only | Nothing | **No, never** |
| Home Assistant | A running HA instance + a long-lived token | Yes — to your HA box on your LAN |
| Gemini | A Google API key + internet | Yes — to Google |

The rule of thumb: the local path is what makes the device useful offline; the
backends are upgrades for homes that asked for them.

## Local intents only

The default, and the only mode that works on a device with no uplink.

Can do: the things this launcher already does itself — lights, media and volume
controls it has wired locally, timers, opening an app, the things on the Nest
action grid. These are matched against a fixed vocabulary in the app.

Cannot do: answer a question it has no fixed match for. "What's the weather like
in Oslo next March" will get nothing, and "turn off the kitchen light" only
works if that command is one it was taught. There is no cloud fallback and there
is no AI here. That is the point of this mode.

**The local path never leaves the device.** No text you say, type or trigger
locally is sent anywhere. This is not a policy that could change with a
settings toggle — in this mode the assistant simply has no network code, and the
other two clients in the app are not called.

## What Home Assistant adds

If the home already runs Home Assistant, this backend turns the assistant into a
thin front end for entities the user already owns.

Can do: read the state of entities (`light.kitchen`, `sensor.outdoor_temp`) and
call services against them (`light.turn_on`, `climate.set_temperature`). The
request and a short transcript of what the user asked go to the Home Assistant
server, which is normally a box on the same LAN.

Cannot do: answer general knowledge, control anything that is not in Home
Assistant, or work when the HA server is off. It also cannot reason about
entities the user never exposed to the API.

Privacy: this traffic stays on the local network with a normal install, but it
does leave this device and reach a server the user controls. If that server is
exposed to the internet, "on the LAN" stops being true. The access token is held
in memory, sent only in the `Authorization` header, and never written to a log.

## What Gemini adds

The only backend that can answer open-ended questions.

Can do: anything a general model can — explanations, translation, "what's the
weather like in Oslo next March". The full request text is sent to Google's
Generative Language API.

Cannot do: change anything on the device or in the home. Gemini here is
question-and-answer only; it has no tool or function access, so it cannot turn a
light on or run a scene. There is no conversation history: each question is a
single, independent call, so it also cannot remember what was asked a moment
ago. It needs an internet connection and a working API key.

Privacy: **the transcript of what you asked is sent off the device to Google**,
over HTTPS, and is subject to Google's terms for that API. The API key is stored
with the rest of the launcher settings and is sent only in the request header.

## The honest summary

* The local path is private and offline, and limited to a fixed vocabulary.
* Home Assistant is a private-ish LAN path for people who already run it, and
  only controls what HA controls.
* Gemini is the only one that can hold a real conversation, and it is the only
  one where a transcript leaves the device to a third party.
* None of them are always on. A backend that is unreachable, unconfigured, rate
  limited or returning an error makes the assistant fall back to what it can do
  locally rather than failing. Nothing is retried in the background or queued.

## Deliberately not implemented

* **Voice recognition.** `voiceEnabled` only governs whether the launcher listens
  for the platform's speech input; transcription is the OS's, not ours.
* **Streaming responses.** Gemini replies arrive whole or not at all. Streaming
  would keep a weak device's radio busy longer for a launcher that only needs a
  sentence.
* **Conversation memory, tool calling, or Home Assistant intent parsing.** The
  Gemini client is single-turn and cannot touch the home; the Home Assistant
  client is entity read/write only. Wiring a model to arbitrary home actions is a
  much larger safety surface than this page is describing.
* **Automatic retries or offline queueing.** A failed request is dropped.
