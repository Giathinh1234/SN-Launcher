import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/nest_action.dart';
import '../services/action_launcher.dart';
import '../services/platform_bridge.dart';
import '../services/settings_store.dart';
import '../theme/ambient_palette.dart';
import '../theme/nest_metrics.dart';

/// Material 1 standard easing — the curve the Nest's Flutter UI uses.
const Curve kNestEase = Cubic(0.4, 0.0, 0.2, 1);
const Curve kNestDecelerate = Cubic(0.4, 0.0, 0.6, 1);
const Curve kNestAccelerate = Cubic(0.4, 0.0, 1.0, 1);

const Duration kNestFast = Duration(milliseconds: 200);
const Duration kNestMedium = Duration(milliseconds: 300);
const Duration kNestSlow = Duration(milliseconds: 420);

/// The four top-level pages of the shell, in the device's carousel order.
enum ShellPage {
  /// Photo Frame / clock — far left.
  home,

  /// "Your morning / afternoon / evening" suggestion carousel.
  digest,

  /// Home control.
  homeControl,

  /// Discover / launcher grid.
  discover,
}

/// How far the bottom launcher sheet is dragged, 0 = closed, 1 = fully open.
class SheetState {
  const SheetState(this.progress);
  final double progress;

  static const SheetState closed = SheetState(0);
  static const SheetState open = SheetState(1);
  bool get isOpen => progress > 0.995;
  bool get isClosed => progress < 0.005;
}

/// Assistant listening state, mirroring the device's 4-dot animation.
enum AssistantState { idle, listening, processing, speaking, error }

/// Global shell state: page carousel, bottom sheet, assistant, brightness,
/// volume and DND. Everything the gesture recogniser touches lives here so the
/// widget tree can stay declarative and cheap.
class ShellController extends ChangeNotifier {
  ShellController({
    required this.metrics,
    required TickerProvider vsync,
    PlatformBridge platform = const PlatformBridge(),
    SettingsStore? settings,
    // ignore: prefer_initializing_formals
  })  : _platform = platform,
        _settings = settings ?? SettingsStore() {
    _palette = AmbientPalette.of(_theme);

    _pageAnim = AnimationController(vsync: vsync, duration: kNestSlow);
    _sheetAnim = AnimationController(vsync: vsync, duration: kNestMedium);
  }

  final NestMetrics metrics;

  final ActionLauncher _launcher = const ActionLauncher();

  /// Exposed so the quick-settings row can fall back to the plugin's URL path
  /// when the native one is unavailable (desktop, or an older Android build).
  ActionLauncher get actionLauncher => _launcher;
  /// Private with a public getter: the constructor takes a named parameter for
  /// testability but the field name must stay private.
  final PlatformBridge _platform;
  final SettingsStore _settings;

  /// Set by [attachClock] so the palette can drift with the wall clock.
  ClockTicker? _clockTicker;

  bool _disposed = false;

  /// Restore persisted settings, then match the real device state. Both are
  /// best-effort and must not delay the first frame — the launcher paints
  /// immediately and corrects itself a moment later if the platform answers.
  Future<void> restore() async {
    await _settings.load();
    if (_disposed) return;
    final stored = _settings.get(SettingKeys.theme);
    if (stored != null) {
      _theme = NestTheme.values.firstWhere(
        (t) => t.name == stored,
        orElse: () => NestTheme.dynamic,
      );
    }
    _recomputePalette(force: true);
    notifyListeners();
    unawaited(syncWithDeviceState());
  }

  SettingsStore get settings => _settings;
  PlatformBridge get platform => _platform;

  late final AnimationController _pageAnim;
  late final AnimationController _sheetAnim;

  // ── Page carousel ────────────────────────────────────────────────────────
  ShellPage _page = ShellPage.home;
  ShellPage get page => _page;

  /// Live carousel offset in "pages", animated with a controller so swipes
  /// settle with the Material curve rather than snapping.
  Animation<double> get pageAnim => _pageAnim;

  // ── Bottom sheet ─────────────────────────────────────────────────────────
  Animation<double> get sheetAnim => _sheetAnim;
  double get sheetProgress => _sheetAnim.value;

  /// True while a finger is dragging the sheet, so release can decide snap.
  bool _draggingSheet = false;
  double _dragStart = 0;

  // ── Assistant ────────────────────────────────────────────────────────────
  AssistantState _assistant = AssistantState.idle;
  AssistantState get assistant => _assistant;
  Timer? _assistantTimer;

  // ── Settings ─────────────────────────────────────────────────────────────
  double _brightness = 0.8;
  double get brightness => _brightness;

  double _volume = 0.5;
  double get volume => _volume;

  NestTheme _theme = NestTheme.dynamic;
  NestTheme get theme => _theme;

  /// True when the current look came from the clock rather than a pinned
  /// choice — the theme picker labels this row "follows the sun".
  bool get themeIsDynamic => _theme == NestTheme.dynamic;

  bool get darkThemeEnabled => _palette.isDark;

  bool _doNotDisturb = false;
  bool get doNotDisturb => _doNotDisturb;

  bool _ambientEq = true;
  bool get ambientEq => _ambientEq;

  double _ambientLight = 0.5;
  double get ambientLight => _ambientLight;

  bool _use24Hour = true;
  bool get use24Hour => _use24Hour;

  bool _showSeconds = false;
  bool get showSeconds => _showSeconds;

  String _albumTitle = 'Recent highlights';
  String get albumTitle => _albumTitle;

  double _zoom = 1.0;
  double get zoom => _zoom;
  set zoom(double v) {
    if (_zoom == v) return;
    _zoom = v.clamp(1.0, 2.0);
    notifyListeners();
  }

  // ── Ambient palette ──────────────────────────────────────────────────────
  late AmbientPalette _palette;
  AmbientPalette get palette => _palette;

  // ── Toast ────────────────────────────────────────────────────────────────
  String? _toast;
  Timer? _toastTimer;

  // ─────────────────────────────────────────────────────────────────────────
  void attachClock(ClockTicker ticker) {
    _clockTicker = ticker;
    _onClockTick();
    ticker.addListener(_onClockTick);
  }

  void _onClockTick() {
    _recomputePalette();
  }

  /// Recompute [palette] from the theme choice and the wall clock.
  ///
  /// A pinned theme ignores the clock entirely — that is the point of pinning
  /// it. Only [NestTheme.dynamic] drifts, and it only notifies when the colour
  /// actually moved, because this runs on every minute tick and a wall display
  /// must not wake up repainting when nothing changed.
  void _recomputePalette({bool force = false}) {
    final t = _clockTicker?.now ?? DateTime.now();
    final next = AmbientPalette.resolve(
      _theme,
      t.hour.toDouble() + t.minute / 60.0,
    );
    if (force ||
        next.top != _palette.top ||
        next.bottom != _palette.bottom ||
        next.surface != _palette.surface) {
      _palette = next;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _pageAnim.dispose();
    _sheetAnim.dispose();
    _assistantTimer?.cancel();
    _toastTimer?.cancel();
    super.dispose();
  }

  // ── Page navigation ──────────────────────────────────────────────────────
  void goToPage(ShellPage p, {Duration? duration}) {
    if (_page == p && _pageAnim.isAnimating) return;
    _page = p;
    _pageAnim.animateTo(p.index.toDouble(),
        duration: duration ?? kNestMedium, curve: kNestEase);
    notifyListeners();
  }

  /// Horizontal swipe moves the page carousel; small flicks advance one page.
  void onHorizontalDragEnd(double velocity, double delta, double width) {
    if (width <= 0) return;
    final threshold = width * 0.18;
    var target = _pageAnim.value;
    if (velocity.abs() > 260) {
      target = velocity > 0 ? target - 1 : target + 1;
    } else if (delta.abs() > threshold) {
      target = delta < 0 ? target + 1 : target - 1;
    }
    target = target.clamp(0, ShellPage.values.length - 1);
    goToPage(ShellPage.values[target.round()]);
  }

  // ── Bottom sheet gesture ─────────────────────────────────────────────────
  /// Where the sheet settles when released: anything above this stays open.
  static const double sheetOpenThreshold = 0.45;

  /// Velocity (px/s, positive = downward) past which a fling wins over
  /// position, in either direction.
  static const double sheetFlingVelocity = 600;

  /// How much of a full sheet-height of travel a single frame of fling is
  /// projected to carry the sheet.
  static const double _flingProjection = 0.25;

  /// Begin a drag from a known starting [progress].
  ///
  /// Explicit rather than inferred lazily on the first move: inferring it let
  /// the widget layer and this layer disagree about whether a drag was
  /// happening, which froze the sheet mid-drag.
  void onSheetDragStart(double progress) {
    _draggingSheet = true;
    _dragStart = progress;
  }

  /// [dyFromStart] is finger travel since the drag began; [travelHeight] is the
  /// distance the sheet covers going 0 → 1, i.e. its own height — **not** the
  /// screen height.
  ///
  /// Dividing by the screen height made the sheet track the finger at half
  /// speed, which is the "it appears slowly" half of the report.
  void onSheetDragUpdate(double dyFromStart, double travelHeight) {
    if (!_draggingSheet) return;
    _sheetAnim.value =
        (_dragStart - dyFromStart / math.max(1.0, travelHeight)).clamp(0.0, 1.0);
  }

  /// Release settles the sheet. Called on pointer-up *and* pointer-cancel —
  /// Android claims bottom-edge drags for its own gesture, so a cancel is the
  /// normal way a drag ends here.
  void onSheetDragEnd(double velocity, double travelHeight, {required bool isDiscover}) {
    _draggingSheet = false;
    final travel = math.max(1.0, travelHeight);
    final projected =
        (_sheetAnim.value - velocity / travel * _flingProjection).clamp(0.0, 1.0);

    final bool shouldOpen;
    if (velocity < -sheetFlingVelocity) {
      shouldOpen = true; // flung upward
    } else if (velocity > sheetFlingVelocity) {
      shouldOpen = false; // flung downward
    } else {
      shouldOpen = projected > sheetOpenThreshold;
    }

    if (shouldOpen) {
      goToPage(isDiscover ? ShellPage.discover : _page, duration: kNestFast);
      _sheetAnim.animateTo(1, duration: kNestMedium, curve: kNestDecelerate);
    } else {
      _sheetAnim.animateTo(0, duration: kNestMedium, curve: kNestAccelerate);
      // Match closeSheet(): leaving the drawer also returns to the first page.
      if (_page == ShellPage.discover) goToPage(ShellPage.home);
    }
  }

  void toggleSheet() {
    if (_sheetAnim.value > sheetOpenThreshold) {
      _sheetAnim.animateBack(0, duration: kNestMedium, curve: kNestAccelerate);
    } else {
      _sheetAnim.animateTo(1, duration: kNestMedium, curve: kNestDecelerate);
    }
  }

  void closeSheet() {
    _sheetAnim.animateTo(0, duration: kNestMedium, curve: kNestAccelerate);
    if (_page == ShellPage.discover) {
      goToPage(ShellPage.home);
    }
  }

  // ── Quick settings ───────────────────────────────────────────────────────
  //
  // These drive the *hardware*, not just a number in this class. That is the
  // whole difference from the version that only mutated private fields and
  // told the user it had dimmed the screen: nothing on the panel changed.
  //
  // Each setter therefore (a) updates local state immediately so the UI is
  // responsive, and (b) pushes to the platform. The platform call is fire and
  // forget — a drag must never await a channel round trip, or the brightness
  // arc stutters. The resulting value is reconciled back when the platform
  // answers, because Android clamps to its own range.

  void setBrightness(double v, {bool notify = true}) {
    final next = v.clamp(0.0, 1.0);
    if ((next - _brightness).abs() < 0.001) return;
    _brightness = next;
    if (notify) notifyListeners();
    _platform.setBrightness(next).then((applied) {
      if (applied == null || _disposed) return;
      // Android quantises to its own steps; adopt what it really did rather
      // than showing the user a number the panel is not at.
      if ((applied - _brightness).abs() > 0.005) {
        _brightness = applied;
        notifyListeners();
      }
    });
  }

  void nudgeBrightness(double delta) => setBrightness(_brightness + delta);

  void setVolume(double v) {
    final next = v.clamp(0.0, 1.0);
    if ((next - _volume).abs() < 0.001) return;
    _volume = next;
    notifyListeners();
    _platform.setVolume(next);
  }

  void nudgeVolume(double delta) => setVolume(_volume + delta);

  /// Adopt the device's real brightness/volume on launch, so the launcher does
  /// not open showing 80% while the panel is actually at 40%.
  Future<void> syncWithDeviceState() async {
    final b = await _platform.getBrightness();
    final v = await _platform.getVolumeFraction();
    if (_disposed) return;
    if (b != null) _brightness = b.clamp(0.0, 1.0);
    if (v != null) _volume = v.clamp(0.0, 1.0);
    notifyListeners();
  }

  /// Switch the look. Persisted, because a wall display that forgets its theme
  /// every reboot is worse than one that never had themes.
  void setTheme(NestTheme t) {
    if (_theme == t) return;
    _theme = t;
    _recomputePalette(force: true);
    _settings.put(SettingKeys.theme, t.name);
    notifyListeners();
  }

  /// The theme picker walks the list, so a single button cycles rather than
  /// dead-ending on the last entry.
  void cycleTheme() {
    final values = NestTheme.values;
    setTheme(values[(values.indexOf(_theme) + 1) % values.length]);
  }

  void toggleDoNotDisturb() {
    _doNotDisturb = !_doNotDisturb;
    showToast(_doNotDisturb ? 'Do Not Disturb on' : 'Do Not Disturb off');
    notifyListeners();
  }

  void toggleAmbientEq() {
    _ambientEq = !_ambientEq;
    _onClockTick();
    showToast(_ambientEq ? 'Ambient EQ on' : 'Ambient EQ off');
    notifyListeners();
  }

  void setAmbientLight(double v) {
    _ambientLight = v.clamp(0.0, 1.0);
    _onClockTick();
    notifyListeners();
  }

  void toggleUse24Hour() {
    _use24Hour = !_use24Hour;
    notifyListeners();
  }

  void toggleShowSeconds() {
    _showSeconds = !_showSeconds;
    notifyListeners();
  }

  void setAlbumTitle(String t) {
    _albumTitle = t;
    notifyListeners();
  }

  // ── Assistant ────────────────────────────────────────────────────────────
  void beginListening() {
    _assistant = AssistantState.listening;
    _assistantTimer?.cancel();
    _assistantTimer = Timer(const Duration(seconds: 3), () {
      _assistant = AssistantState.processing;
      notifyListeners();
      _assistantTimer = Timer(const Duration(milliseconds: 1200), () {
        _assistant = AssistantState.idle;
        notifyListeners();
      });
    });
    notifyListeners();
  }

  void stopListening() {
    _assistantTimer?.cancel();
    _assistant = AssistantState.idle;
    notifyListeners();
  }

  // ── Launching ────────────────────────────────────────────────────────────
  Future<void> openAction(NestAction action) async {
    closeSheet();
    final outcome = await _launcher.launch(action);
    if (outcome != LaunchOutcome.launched) {
      showToast(outcome == LaunchOutcome.notInstalled
          ? '${action.label} is not installed'
          : "Couldn't open ${action.label}");
    }
  }

  Future<void> openUrl(String url) async {
    final ok = await _launcher.openUrl(url);
    if (!ok) showToast("Couldn't open $url");
  }

  void showToast(String message) {
    _toast = message;
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(seconds: 2), () {
      _toast = null;
      notifyListeners();
    });
    notifyListeners();
  }

  String? get toast => _toast;

  // ── Test hooks ───────────────────────────────────────────────────────────
  /// Forces the sheet position without animating (screenshot capture).
  @visibleForTesting
  void setSheetForTest(double v) {
    _sheetAnim.value = v;
    _page = v > 0.99 ? ShellPage.discover : _page;
  }

  /// Forces a specific ambient palette (deterministic screenshots).
  @visibleForTesting
  void setPaletteForTest(AmbientPalette p) {
    _palette = p;
    notifyListeners();
  }

  /// Pins the theme *and* its palette together.
  ///
  /// [setPaletteForTest] alone leaves `_theme` as `dynamic`, so the Digest
  /// page would report "follows the time of day" while rendering a pinned
  /// palette — a caption that contradicts what is on screen. Screenshots have
  /// already caught that once; keep the two in step.
  void setThemeForTest(NestTheme t) {
    _theme = t;
    _palette = AmbientPalette.of(t);
    notifyListeners();
  }
}

/// Minimal clock abstraction so the controller can be driven by tests without
/// a real timer.
class ClockTicker extends ChangeNotifier {
  ClockTicker(this._now);
  DateTime _now;
  DateTime get now => _now;
  void set(DateTime t) {
    _now = t;
    notifyListeners();
  }
}