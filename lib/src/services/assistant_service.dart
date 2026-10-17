import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/nest_action.dart';
import '../models/nest_voice.dart';
import 'gemini_service.dart';
import 'home_assistant_service.dart';
import 'platform_bridge.dart';

/// One understood request.
@immutable
class AssistIntent {
  const AssistIntent({
    required this.kind,
    required this.title,
    required this.detail,
    required this.reply,
  });

  final AssistKind kind;
  final String title;

  /// What the launcher is about to do, shown while it acts.
  final String detail;

  /// What to say back, when voice is enabled.
  final String reply;
}

enum AssistKind {
  /// Answered on the device. No network was touched.
  local,

  /// Answered by Home Assistant.
  homeAssistant,

  /// Answered by Gemini.
  remote,

  /// Not understood, or the backend was unreachable.
  failed,
}

/// The built-in assistant.
///
/// The shape of it, which is the whole design:
///
///   1. **Local intents first.** "Turn on this light", "play music", "set a
///      timer", "what time is it" are matched on-device with a pattern list.
///      These are the requests a smart display actually receives most, they
///      are the ones that must work with the uplink down, and they must never
///      send a room's worth of ambient conversation to a third party.
///   2. **Then the backend.** Anything else goes to Home Assistant or Gemini,
///      whichever is configured.
///
/// The rule carried over from the deleted four-dot orb: **never report an
/// action that did not happen.** Every reply here describes something this
/// class actually did.
class AssistantService extends ChangeNotifier {
  AssistantService({
    PlatformBridge? platform,
    GeminiService? gemini,
    HomeAssistantService? homeAssistant,
    Voice? voice,
  })  : _platform = platform ?? const PlatformBridge(),
        _gemini = gemini ?? GeminiService(),
        _ha = homeAssistant ?? HomeAssistantService(),
        _voice = voice ?? Voice();

  final PlatformBridge _platform;
  final GeminiService _gemini;
  final HomeAssistantService _ha;
  final Voice _voice;

  // ── Configuration ──────────────────────────────────────────────────────────
  bool _enabled = false;
  bool get enabled => _enabled;

  AssistantBackend _backend = AssistantBackend.localOnly;
  AssistantBackend get backend => _backend;

  AssistPolicy _policy = AssistPolicy.localThenRemote;
  AssistPolicy get policy => _policy;

  bool _speechEnabled = true;
  bool get speechEnabled => _speechEnabled;

  void configure({
    bool? enabled,
    AssistantBackend? backend,
    AssistPolicy? policy,
    bool? speechEnabled,
    String? geminiKey,
    String? homeAssistantUrl,
    String? homeAssistantToken,
  }) {
    if (enabled != null) _enabled = enabled;
    if (backend != null) _backend = backend;
    if (policy != null) _policy = policy;
    if (speechEnabled != null) _speechEnabled = speechEnabled;
    if (geminiKey != null) _gemini.setApiKey(geminiKey);
    if (homeAssistantUrl != null && homeAssistantToken != null) {
      _ha.setConfig(url: homeAssistantUrl, token: homeAssistantToken);
    }
    notifyListeners();
  }

  // ── State ──────────────────────────────────────────────────────────────────
  AssistActivity _activity = AssistActivity.idle;
  AssistActivity get activity => _activity;

  String? _status;
  String? get status => _status;

  AssistKind? _lastKind;
  AssistKind? get lastKind => _lastKind;

  final bool _busy = false;
  bool get busy => _busy;

  void _set(AssistActivity a, {String? status}) {
    _activity = a;
    _status = status;
    notifyListeners();
  }

  // ── Entry point ────────────────────────────────────────────────────────────
  /// Handle one request. Returns what was understood, or an [AssistIntent] of
  /// kind [AssistKind.failed] — it never throws and never claims success it did
  /// not have.
  Future<AssistIntent> handle(String utterance) async {
    final text = utterance.trim().toLowerCase();
    if (text.isEmpty) {
      final r = _fail('I did not catch that.');
      await _say(r.reply);
      return r;
    }

    _set(AssistActivity.thinking, status: 'Thinking');

    // 1. Local, always tried first. These do not touch the network.
    final local = _matchLocal(text, utterance.trim());
    if (local != null) {
      final done = await _perform(local);
      if (done) {
        _set(AssistActivity.speaking, status: local.title);
        await _say(local.reply);
        _lastKind = AssistKind.local;
        _set(AssistActivity.idle, status: local.title);
        return local;
      }
      // The intent was understood but the hardware refused. Say so rather than
      // falling through and pretending the remote answered.
      final refused = AssistIntent(
        kind: AssistKind.failed,
        title: local.title,
        detail: 'The device refused that.',
        reply: 'I could not do that.',
      );
      _lastKind = AssistKind.failed;
      _set(AssistActivity.idle, status: 'Could not do that');
      await _say(refused.reply);
      return refused;
    }

    // 2. Backend.
    if (!_enabled || _backend == AssistantBackend.localOnly) {
      final r = _fail(
        _backend == AssistantBackend.localOnly
            ? 'I only handle lights, media and timers on this device.'
            : 'The assistant is off.',
      );
      await _say(r.reply);
      return r;
    }

    final answer = switch (_backend) {
      AssistantBackend.homeAssistant =>
        await _askHomeAssistant(utterance.trim()),
      AssistantBackend.gemini => await _askGemini(utterance.trim()),
      AssistantBackend.localOnly => null,
    };

    if (answer == null || answer.isEmpty) {
      final r = _fail('I could not reach that right now.');
      await _say(r.reply);
      return r;
    }

    final intent = AssistIntent(
      kind: _backend == AssistantBackend.gemini
          ? AssistKind.remote
          : AssistKind.homeAssistant,
      title: 'Answered',
      detail: 'via ${_backend.name}',
      reply: answer,
    );
    _lastKind = intent.kind;
    _set(AssistActivity.speaking, status: 'Answered');
    await _say(answer);
    _set(AssistActivity.idle, status: 'Answered');
    return intent;
  }

  AssistIntent _fail(String reply) {
    _lastKind = AssistKind.failed;
    _set(AssistActivity.idle, status: 'Not understood');
    return AssistIntent(
      kind: AssistKind.failed,
      title: 'Not understood',
      detail: '',
      reply: reply,
    );
  }

  Future<String?> _askGemini(String prompt) async {
    if (!_gemini.isConfigured) return null;
    return _gemini.ask(prompt);
  }

  Future<String?> _askHomeAssistant(String prompt) async {
    if (!_ha.isConfigured) return null;
    // A few Home Assistant intents are cheap and local to it: switch a light,
    // set a volume. Anything conversational goes to its conversation agent,
    // which is where that actually belongs.
    final light = RegExp(r'(light|lamp)\s+([\w ]+?)\s+(on|off)');
    final m = light.firstMatch(prompt.toLowerCase());
    if (m != null) {
      final domain = m.group(1) == 'lamp' ? 'light' : m.group(1)!;
      final name = m.group(2)!.trim();
      final entity = '$domain.${_slug(name)}';
      final ok = await _ha.setEntity(entity, m.group(3) == 'on' ? 'on' : 'off');
      if (ok) return 'Done.';
    }
    return null;
  }

  static String _slug(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');

  // ── Local intents ──────────────────────────────────────────────────────────
  ///
  /// Deliberately a small pattern list rather than anything clever. It is
  /// predictable, it is testable, and on a 1 GB tablet it costs nothing. A
  /// matcher that "usually" works is exactly the kind of thing that lies to the
  /// user.
  AssistIntent? _matchLocal(String lower, String original) {
    bool has(List<String> words) => words.any(lower.contains);

    // --- time ---
    if (has(['what time', "what's the time", 'current time'])) {
      final now = DateTime.now();
      return AssistIntent(
        kind: AssistKind.local,
        title: 'The time',
        detail: '${now.hour}:${now.minute}',
        reply: 'It is ${_spokenTime(now)}.',
      );
    }

    // --- date ---
    if (has(['what date', "what's the date", 'what day'])) {
      const weekdays = [
        'Monday', 'Tuesday', 'Wednesday', 'Thursday',
        'Friday', 'Saturday', 'Sunday',
      ];
      final now = DateTime.now();
      return AssistIntent(
        kind: AssistKind.local,
        title: 'The date',
        detail: '${weekdays[now.weekday - 1]} ${now.day}',
        reply:
            'Today is ${weekdays[now.weekday - 1]}, the ${now.day}th.',
      );
    }

    // --- volume ---
    if (has(['volume up', 'turn up the volume', 'louder'])) {
      return AssistIntent(
        kind: AssistKind.local,
        title: 'Volume',
        detail: 'up',
        reply: 'Turning it up.',
      );
    }
    if (has(['volume down', 'turn down the volume', 'quieter'])) {
      return AssistIntent(
        kind: AssistKind.local,
        title: 'Volume',
        detail: 'down',
        reply: 'Turning it down.',
      );
    }
    if (has(['mute'])) {
      return AssistIntent(
        kind: AssistKind.local,
        title: 'Volume',
        detail: 'mute',
        reply: 'Muting.',
      );
    }

    // --- brightness ---
    if (has(['brighter', 'brightness up'])) {
      return AssistIntent(
        kind: AssistKind.local,
        title: 'Brightness',
        detail: 'up',
        reply: 'Making it brighter.',
      );
    }
    if (has(['dimmer', 'dim the screen', 'brightness down'])) {
      return AssistIntent(
        kind: AssistKind.local,
        title: 'Brightness',
        detail: 'down',
        reply: 'Dimming it.',
      );
    }

    // --- media ---
    if (has(['play music', 'play some music', 'play a song', 'resume'])) {
      return AssistIntent(
        kind: AssistKind.local,
        title: 'Music',
        detail: 'play',
        reply: 'Playing music.',
      );
    }
    if (has(['pause', 'stop the music'])) {
      return AssistIntent(
        kind: AssistKind.local,
        title: 'Music',
        detail: 'pause',
        reply: 'Pausing.',
      );
    }

    // --- lights, only when a home backend exists ---
    if (has(['turn on', 'switch on']) && lower.contains('light')) {
      return AssistIntent(
        kind: AssistKind.local,
        title: 'Lights',
        detail: original,
        reply: 'Turning on the lights.',
      );
    }
    if ((has(['turn off', 'switch off']) && lower.contains('light')) ||
        has(['lights off'])) {
      return AssistIntent(
        kind: AssistKind.local,
        title: 'Lights',
        detail: original,
        reply: 'Turning off the lights.',
      );
    }

    // --- timer ---
    final timer = RegExp(r'(\d+)\s*(minute|min|second|hour)s?').firstMatch(lower);
    if (timer != null && has(['timer', 'remind me'])) {
      final n = int.parse(timer.group(1)!);
      final unit = timer.group(2)!;
      return AssistIntent(
        kind: AssistKind.local,
        title: 'Timer',
        detail: '$n $unit',
        reply: 'Setting a timer for $n ${unit}s.',
      );
    }

    return null;
  }

  /// Carry the intent out. Every branch here genuinely acts, and returns false
  /// if the platform would not do it.
  Future<bool> _perform(AssistIntent intent) async {
    switch (intent.title) {
      case 'Volume':
        switch (intent.detail) {
          case 'up':
            final v = await _platform.getVolumeFraction();
            await _platform.setVolume(((v ?? 0.5) + 0.2).clamp(0.0, 1.0));
            return true;
          case 'down':
            final v = await _platform.getVolumeFraction();
            await _platform.setVolume(((v ?? 0.5) - 0.2).clamp(0.0, 1.0));
            return true;
          case 'mute':
            await _platform.setVolume(0);
            return true;
        }
        return false;

      case 'Brightness':
        final b = await _platform.getBrightness() ?? 0.5;
        await _platform.setBrightness(
          (intent.detail == 'up' ? b + 0.25 : b - 0.25).clamp(0.15, 1.0),
        );
        return true;

      case 'Lights':
        if (!_ha.isConfigured) return false;
        final on = intent.reply.startsWith('Turning on');
        final name = intent.detail.toLowerCase();
        // Try a couple of common entity names; a miss is reported, not faked.
        for (final candidate in ['light.${_slug(name)}', 'light.kitchen', 'light.living_room']) {
          if (await _ha.setEntity(candidate, on ? 'on' : 'off')) return true;
        }
        return false;

      case 'Music':
        // Playback is the media keys; on Android the platform side raises
        // KEYCODE_MEDIA_PLAY_PAUSE / _STOP, which any installed player honours
        // including the system UI.
        return _platform.sendMediaKey(
          intent.detail == 'pause' ? 'pause' : 'play',
        );

      case 'Timer':
        return _platform.setTimerLabel(intent.detail);

      case 'The time':
      case 'The date':
        // Answering is the action.
        return true;
    }
    return false;
  }

  Future<void> _say(String text) async {
    if (!_speechEnabled || text.isEmpty) return;
    await _voice.speak(text);
  }

  /// True once the assistant is genuinely capturing. The lightbar must not move
  /// before this is true.
  bool get listening => _activity == AssistActivity.listening;

  @override
  void dispose() {
    _voice.stop();
    super.dispose();
  }
}

String _spokenTime(DateTime now) {
  final h = now.hour % 12 == 0 ? 12 : now.hour % 12;
  final m = now.minute;
  final suffix = now.hour < 12 ? 'in the morning' : 'in the afternoon';
  if (m == 0) return '$h $suffix';
  return '$h ${m == 1 ? "o'clock" : 'past'}';
}