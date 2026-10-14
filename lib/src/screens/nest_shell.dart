import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

import '../models/nest_action.dart';
import '../services/clock_service.dart';
import '../services/weather_service.dart';
import '../state/shell_controller.dart';
import '../theme/ambient_palette.dart';
import '../theme/nest_metrics.dart';
import '../theme/nest_type.dart';
import '../widgets/ambient_background.dart';
import '../widgets/app_drawer.dart';
import '../widgets/assistant_orb.dart';
import '../widgets/clock_block.dart';
import '../widgets/launcher_sheet.dart';

/// The Nest launcher shell.
///
/// Layout, in z-order:
///   0  ambient background (one paint pass)
///   1  page carousel  — photo frame · digest · home control · discover
///   2  bottom sheet   — app row + quick settings + drag handle
///   3  app drawer     — the six-column "See all" grid
///   4  assistant overlay
///   5  toast
///
/// Gestures follow the device:
///   * swipe up from the bottom .... open the launcher sheet (follows finger)
///   * swipe up past the detent ... open the full app drawer
///   * swipe down ................. close
///   * swipe left / right ......... move through the page carousel
///   * tap centre ................. begin listening
///   * three-finger up/down ....... open / close quick settings
class NestShell extends StatefulWidget {
  const NestShell({
    super.key,
    required this.controller,
    required this.clock,
    required this.weather,
    this.suggested,
    this.actions,
    this.animateDecorations = true,
  });

  final ShellController controller;
  final ClockService clock;
  final WeatherService weather;

  /// Overrides the six badges in the sheet's app row.
  final List<NestAction>? suggested;

  /// Overrides the drawer contents.
  final List<NestAction>? actions;

  /// When false, every continuously-animating decoration (weather glyph,
  /// Assistant orb) renders a single static frame. Required for screenshot /
  /// golden tests, which cannot settle against an infinite animation.
  final bool animateDecorations;

  @override
  State<NestShell> createState() => _NestShellState();
}

class _NestShellState extends State<NestShell> {
  /// Recomputed every frame, deliberately *not* `late final`.
  ///
  /// The first frame on a real device reports a MediaQuery size that is smaller
  /// than the settled one — the display metrics are still being resolved while
  /// the activity attaches. Caching the first value locks the whole shell to
  /// the wrong scale for its entire life (measured 1.063 vs the settled 1.116,
  /// a 5% error across every icon, font and offset).
  NestMetrics get _m => NestMetrics.of(context);

  late final ShellController _c = widget.controller;

  double _dragStartY = 0;
  bool _draggingSheet = false;

  /// Suggested six: the device ships most-used actions, and these are the
  /// defaults observed on a freshly-provisioned Hub.
  /// The device's default six, in the order a freshly-provisioned Hub shows
  /// them (read off the rectified Max photo): weather, YouTube, Spotify,
  /// timer, calendar, broadcast.
  late final List<NestAction> _suggested = widget.suggested ?? _defaultSuggested();

  static List<NestAction> _defaultSuggested() {
    const order = ['weather', 'youtube', 'spotify', 'timer', 'calendar', 'broadcast'];
    return [
      for (final id in order)
        if (kNestActions.any((a) => a.id == id)) kNestActions.firstWhere((a) => a.id == id),
    ];
  }

  late final List<NestAction> _actions =
      widget.actions ?? (List<NestAction>.from(kNestActions)..sort((a, b) => a.label.compareTo(b.label)));

  @override
  Widget build(BuildContext context) {
    final type = NestType(_m);

    return PopScope(
      // A launcher must never be dismissed by Back. On the real device Back
      // backs out one level: drawer → sheet → first page. On the first page it
      // is swallowed, because leaving the app is never what the user meant.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_c.page == ShellPage.discover) {
          _c.closeSheet();
        } else if (_c.sheetProgress > 0.01) {
          _c.closeSheet();
        } else if (_c.page != ShellPage.home) {
          _c.goToPage(ShellPage.home);
        }
      },
      child: Focus(
      autofocus: true,
      // Keyboard / D-pad / remote control. The device is touch-first, but
      // Android TV remotes, USB keyboards and MCP bridges all funnel through
      // the same handful of verbs.
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        switch (event.logicalKey) {
          case LogicalKeyboardKey.arrowUp:
            _c.toggleSheet();
          case LogicalKeyboardKey.arrowDown:
            _c.closeSheet();
          case LogicalKeyboardKey.arrowRight:
            _c.onHorizontalDragEnd(-320, 0, _m.size.width);
          case LogicalKeyboardKey.arrowLeft:
            _c.onHorizontalDragEnd(320, 0, _m.size.width);
          case LogicalKeyboardKey.escape:
            _c.closeSheet();
            _c.stopListening();
          case LogicalKeyboardKey.space:
          case LogicalKeyboardKey.enter:
            _c.assistant == AssistantState.idle
                ? _c.beginListening()
                : _c.stopListening();
          default:
            return KeyEventResult.ignored;
        }
        return KeyEventResult.handled;
      },
      child: AnimatedBuilder(
          // The shell must also listen to the two animation controllers directly.
          //
          // `ShellController` is a ChangeNotifier, but driving the sheet or the
          // carousel animates a separate AnimationController — which notifies
          // its own listeners, *not* the controller. Without these in the list
          // the UI only repaints by accident, whenever the clock ticks.
          animation: Listenable.merge([
            _c,
            _c.pageAnim,
            widget.clock,
            widget.weather,
          ]),
          builder: (context, _) {
            final palette = _c.palette;

            return Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (e) {
                _dragStartY = e.position.dy;
                _draggingSheet = e.position.dy > _m.size.height * 0.72;
              },
              onPointerMove: (e) {
                if (!_draggingSheet) return;
                _c.onSheetDragUpdate(e.position.dy - _dragStartY, _m.size.height);
              },
              onPointerUp: (e) {
                if (_draggingSheet) {
                  _c.onSheetDragEnd(
                    0,
                    _m.size.height,
                    isDiscover: _c.sheetProgress > 0.92,
                  );
                }
                _draggingSheet = false;
              },
              onPointerCancel: (_) {
                // A swipe that begins on the very bottom edge is claimed by
                // Android's home gesture part-way through, so the drag arrives
                // here as a cancel rather than an up. Without settling on
                // cancel the sheet simply freezes wherever the finger got to —
                // which on a real tablet left it stuck ~65% open.
                if (_draggingSheet) {
                  _c.onSheetDragEnd(0, _m.size.height, isDiscover: false);
                }
                _draggingSheet = false;
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _c.assistant == AssistantState.idle
                    ? _c.beginListening
                    : _c.stopListening,
                onHorizontalDragEnd: (d) => _c.onHorizontalDragEnd(
                  d.primaryVelocity ?? 0,
                  0,
                  _m.size.width,
                ),
                child: SizedBox.expand(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      AmbientBackground(
                        palette: palette,
                        brightness: _c.brightness,
                      ),

                      // ── Page carousel ───────────────────────────────────
                      AnimatedBuilder(
                        animation: _c.pageAnim,
                        builder: (context, _) => _buildCarousel(palette, type),

                      ),

                      // ── Launcher sheet ──────────────────────────────────
                      // Driven by its own AnimatedBuilder rather than the
                      // shell's. Sliding the sheet must not rebuild the clock,
                      // the carousel or the ambient background — re-laying-out
                      // the big clock text on every frame of a 300 ms drag is
                      // what pushed this animation over the 60 Hz budget on a
                      // UNISOC T610.
                      if (_c.page != ShellPage.discover)
                        AnimatedBuilder(
                          animation: _c.sheetAnim,
                          builder: (context, _) {
                            final progress = _c.sheetProgress;
                            return Stack(
                              fit: StackFit.expand,
                              children: [
                                if (progress > 0.005)
                                  LauncherSheet(
                                    metrics: _m,
                                    palette: palette,
                                    progress: progress,
                                    suggested: _suggested,
                                    quickSettings: kQuickSettings,
                                    brightness: _c.brightness,
                                    volume: _c.volume,
                                    cameraEnabled: true,
                                    onActionTap: _c.openAction,
                                    onSeeAll: () => _c.goToPage(ShellPage.discover),
                                    onQuickSettingTap: _handleQuickSetting,
                                    onBrightnessDrag: (d) =>
                                        _c.setBrightness(_c.brightness + d),
                                    onVolumeDrag: (d) =>
                                        _c.setVolume(_c.volume + d),
                                  ),
                                // The home-screen grabber fades out as the sheet
                                // takes over the bottom edge.
                                if (progress < 0.5)
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    bottom: _m.size.height -
                                        _m.px(NestMetrics.homeHandleCenterY) -
                                        4,
                                    child: Opacity(
                                      opacity: 1 - progress * 2,
                                      child: Center(
                                        child: DragHandle(
                                          color: palette.onSurface,
                                          scale: _m.u,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),

                      // ── Drawer ─────────────────────────────────────────
                      if (_c.page == ShellPage.discover)
                        AnimatedBuilder(
                          animation: _c.sheetAnim,
                          builder: (context, _) => AppDrawer(
                            metrics: _m,
                            palette: palette,
                            actions: _actions,
                            reveal: _c.sheetProgress,
                            onActionTap: _c.openAction,
                          ),
                        ),

                      // ── Assistant ───────────────────────────────────────
                      if (_c.assistant != AssistantState.idle)
                        _AssistantOverlay(state: _c.assistant, palette: palette, size: _m.px(160)),

                      // ── Toast ──────────────────────────────────────────
                      if (_c.toast != null)
                        _Toast(text: _c.toast!, palette: palette, metrics: _m),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildCarousel(AmbientPalette palette, NestType type) {
    return AnimatedBuilder(
      animation: _c.pageAnim,
      builder: (context, child) {
        final value = _c.pageAnim.value;
        final index = value.round().clamp(0, ShellPage.values.length - 1);
        // Parallax: neighbouring pages sit at ~30% offset and scale down a
        // touch, which is what gives the Nest carousel its depth.
        return Stack(
          fit: StackFit.expand,
          children: [
            for (var i = 0; i < ShellPage.values.length; i++)
              if (i != index || true)
                _PageLayer(
                  visible: i == index,
                  offset: (i - value),
                  child: _pageContent(ShellPage.values[i], palette, type),
                ),
          ],
        );
      },
    );
  }

  Widget _pageContent(ShellPage page, AmbientPalette palette, NestType type) {
    final now = widget.clock.now;
    switch (page) {
      case ShellPage.home:
        return ClockBlock(
          metrics: _m,
          type: type,
          palette: palette,
          weather: widget.weather.current,
          now: now,
          use24Hour: _c.use24Hour,
          showSeconds: _c.showSeconds,
          animateWeather: widget.animateDecorations,
          albumTitle: _c.albumTitle,
        );
      case ShellPage.digest:
        return _DigestPage(
          metrics: _m,
          type: type,
          palette: palette,
          now: now,
          weatherLabel: '${widget.weather.current.condition.label} · '
              '${widget.weather.current.shortLabel}',
        );
      case ShellPage.homeControl:
        return _HomeControlPage(metrics: _m, type: type, palette: palette);
      case ShellPage.discover:
        return const SizedBox.shrink();
    }
  }

  void _handleQuickSetting(QuickSettingKind kind) {
    switch (kind) {
      case QuickSettingKind.brightness:
        _c.setBrightness(_c.brightness > 0.5 ? 0.25 : 0.9);
      case QuickSettingKind.volume:
        _c.showToast('Volume ${(_c.volume * 100).round()}%');
      case QuickSettingKind.camera:
        _c.showToast('Camera toggled');
      case QuickSettingKind.darkTheme:
        _c.toggleDarkTheme();
      case QuickSettingKind.zoomIn:
        _c.goToPage(ShellPage.homeControl);
      case QuickSettingKind.feedback:
        _c.openUrl('https://support.google.com/googlenest/');
      case QuickSettingKind.settings:
        _c.showToast('Settings');
    }
  }
}

/// A single carousel page with the Nest's parallax + scale treatment.
/// A single carousel page with the Nest's parallax + scale treatment.
class _PageLayer extends StatelessWidget {
  const _PageLayer({required this.offset, required this.child, required this.visible});

  final double offset;
  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final d = offset.clamp(-1.6, 1.6);
    final scale = 1 - d.abs() * 0.06;
    final opacity = (1 - d.abs() * 1.25).clamp(0.0, 1.0);
    return IgnorePointer(
      ignoring: opacity < 0.02,
      child: Opacity(
        opacity: opacity,
        child: Transform.translate(
          offset: Offset(d * 90, 0),
          child: Transform.scale(scale: scale, child: child),
        ),
      ),
    );
  }
}

/// "Your morning / afternoon / evening" page — greeting plus a row of cards.
class _DigestPage extends StatelessWidget {
  const _DigestPage({
    required this.metrics,
    required this.type,
    required this.palette,
    required this.now,
    required this.weatherLabel,
  });

  final NestMetrics metrics;
  final NestType type;
  final AmbientPalette palette;
  final DateTime now;
  final String weatherLabel;

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    return Padding(
      padding: EdgeInsets.fromLTRB(m.px(48), m.px(44), m.px(48), m.px(60)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(ClockService.greeting(now), style: type.sheetTitle(color: palette.onSurface)),
          SizedBox(height: m.px(22)),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: _Card(
                    title: 'Calendar',
                    body: 'No more events today',
                    metrics: m,
                    palette: palette,
                    type: type,
                  ),
                ),
                SizedBox(width: m.px(14)),
                Expanded(
                  child: _Card(
                    title: 'Weather',
                    body: weatherLabel,
                    metrics: m,
                    palette: palette,
                    type: type,
                  ),
                ),
                SizedBox(width: m.px(14)),
                Expanded(
                  child: _Card(
                    title: 'Music',
                    body: 'Your evening rotation',
                    metrics: m,
                    palette: palette,
                    type: type,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.body, required this.metrics, required this.palette, required this.type});

  final String title;
  final String body;
  final NestMetrics metrics;
  final AmbientPalette palette;
  final NestType type;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(metrics.px(18)),
      decoration: BoxDecoration(
        color: palette.onSurface.withValues(alpha: palette.isDark ? 0.10 : 0.06),
        borderRadius: BorderRadius.circular(metrics.px(18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: type.sheetTitle(color: palette.onSurface)),
          SizedBox(height: metrics.px(8)),
          Expanded(
            child: Text(body, style: type.body(color: palette.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}

/// Home control page — the room/device grid reached by swiping down.
class _HomeControlPage extends StatelessWidget {
  const _HomeControlPage({required this.metrics, required this.type, required this.palette});

  final NestMetrics metrics;
  final NestType type;
  final AmbientPalette palette;

  static const _categories = [
    'Lights', 'Locks', 'Speakers & TVs', 'Connectivity',
    'Cameras', 'Routines', 'Climate', 'Rooms',
  ];

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    return Padding(
      padding: EdgeInsets.fromLTRB(m.px(48), m.px(40), m.px(48), m.px(60)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Home', style: type.sheetTitle(color: palette.onSurface)),
          SizedBox(height: m.px(18)),
          Expanded(
            child: Wrap(
              spacing: m.px(12),
              runSpacing: m.px(12),
              children: [
                for (final c in _categories)
                  Container(
                    width: (m.size.width - m.px(96) - m.px(12) * 3) / 4,
                    height: m.px(76),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: palette.onSurface.withValues(alpha: palette.isDark ? 0.10 : 0.06),
                      borderRadius: BorderRadius.circular(m.px(16)),
                    ),
                    child: Text(c, style: type.body(color: palette.onSurface)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AssistantOverlay extends StatelessWidget {
  const _AssistantOverlay({required this.state, required this.palette, required this.size});

  final AssistantState state;
  final AmbientPalette palette;
  final double size;

  @override
  Widget build(BuildContext context) {
    final label = switch (state) {
      AssistantState.listening => 'Listening…',
      AssistantState.processing => 'Thinking…',
      AssistantState.speaking => 'Speaking…',
      AssistantState.error => 'Sorry, I missed that',
      AssistantState.idle => null,
    };
    return IgnorePointer(
      child: Center(
        child: AssistantOrb(state: state, size: size, color: palette.onSurface, label: label),
      ),
    );
  }
}

class _Toast extends StatelessWidget {
  const _Toast({required this.text, required this.palette, required this.metrics});

  final String text;
  final AmbientPalette palette;
  final NestMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Align(
        alignment: const Alignment(0, -0.72),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: metrics.px(22),
            vertical: metrics.px(12),
          ),
          decoration: BoxDecoration(
            color: palette.onSurfaceStrong,
            borderRadius: BorderRadius.circular(metrics.px(22)),
            boxShadow: nestShadow(elevation: 1.4, dark: palette.isDark),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontFamily: NestType.display,
              fontSize: metrics.px(21),
              color: palette.surface,
            ),
          ),
        ),
      ),
    );
  }
}