import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

import '../models/nest_action.dart';
import '../models/photo_credit.dart';
import '../services/calendar_service.dart';
import '../services/clock_service.dart';
import '../services/weather_service.dart';
import '../state/shell_controller.dart';
import '../theme/ambient_palette.dart';
import '../theme/nest_metrics.dart';
import '../theme/nest_theme.dart';
import '../theme/nest_type.dart';
import '../widgets/ambient_background.dart';
import '../widgets/app_drawer.dart';
import '../widgets/assistant_orb.dart';
import '../widgets/clock_block.dart';
import '../widgets/launcher_sheet.dart';
import '../widgets/photo_frame.dart';

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
    this.calendar,
    this.suggested,
    this.actions,
    this.animateDecorations = true,
  });

  final ShellController controller;
  final ClockService clock;
  final WeatherService weather;

  /// Optional. When supplied the Digest page shows the user's real calendar
  /// instead of "No more events today".
  final CalendarService? calendar;

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

  /// Licence credit for the bundled photograph. Loaded once.
  late final PhotoCredit _credit = PhotoCredit.load();

  /// The pointer currently dragging the sheet, if any. Single-owner so a
  /// second finger cannot cancel the drag in progress.
  int? _dragPointer;
  double _dragStartY = 0;
  late VelocityTracker _velocity = VelocityTracker.withKind(PointerDeviceKind.touch);

  /// Shared tail for pointer-up and pointer-cancel.
  void _settleSheet(PointerEvent e) {
    if (e.pointer != _dragPointer) return;
    _dragPointer = null;
    _velocity.addPosition(e.timeStamp, e.position);
    // Positive is downward.
    final v = _velocity.getVelocityEstimate()?.pixelsPerSecond.dy ?? 0;
    _c.onSheetDragEnd(v, _m.sheetHeight, isDiscover: _c.sheetProgress > 0.92);
  }

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
      widget.actions ??
      (List<NestAction>.from(kNestActions)..sort((a, b) => a.label.compareTo(b.label)));

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
              _c.assistant == AssistantState.idle ? _c.beginListening() : _c.stopListening();
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
          animation: Listenable.merge([_c, _c.pageAnim, widget.clock, widget.weather]),
          builder: (context, _) {
            final palette = _c.palette;

            return Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (e) {
                // One finger owns the drag. A second finger landing mid-drag
                // used to clear the state flag, leaving the controller
                // dragging with a stale origin.
                if (_dragPointer != null) return;

                // Grabbable from the bottom edge, or anywhere on the sheet
                // while it is already showing. Restricting this to the bottom
                // strip is what made the sheet impossible to pull back down.
                final sheetTop = _m.size.height - _c.sheetProgress * _m.sheetHeight;
                final onSheet = _c.sheetProgress > 0.02 && e.position.dy > sheetTop;
                if (!onSheet && e.position.dy < _m.size.height * 0.72) return;

                _dragPointer = e.pointer;
                _dragStartY = e.position.dy;
                _velocity = VelocityTracker.withKind(e.kind)..addPosition(e.timeStamp, e.position);
                _c.onSheetDragStart(_c.sheetProgress);
              },
              onPointerMove: (e) {
                if (e.pointer != _dragPointer) return;
                _velocity.addPosition(e.timeStamp, e.position);
                // Normalised by the sheet's own travel, so it tracks the
                // finger 1:1.
                _c.onSheetDragUpdate(e.position.dy - _dragStartY, _m.sheetHeight);
              },
              onPointerUp: (e) => _settleSheet(e),
              onPointerCancel: (e) {
                // A swipe starting on the very bottom edge is claimed by
                // Android's home gesture part-way through, so a cancel is a
                // normal ending. Without settling here the sheet froze
                // wherever the finger happened to stop.
                _settleSheet(e);
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _c.assistant == AssistantState.idle ? _c.beginListening : _c.stopListening,
                onHorizontalDragEnd: (d) =>
                    _c.onHorizontalDragEnd(d.primaryVelocity ?? 0, 0, _m.size.width),
                child: SizedBox.expand(
                  child: Theme(
                    // Follows the ambient palette, so any Material widget that
                    // appears inside the shell picks up Google's own colour
                    // roles instead of Flutter's default purple.
                    data: nestTheme(palette, type),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        AmbientBackground(palette: palette, brightness: _c.brightness),

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
                                      onBrightnessDrag: (d) => _c.setBrightness(_c.brightness + d),
                                      onVolumeDrag: (d) => _c.setVolume(_c.volume + d),
                                    ),
                                  // The home-screen grabber fades out as the sheet
                                  // takes over the bottom edge.
                                  if (progress < 0.5)
                                    Positioned(
                                      left: 0,
                                      right: 0,
                                      bottom:
                                          _m.size.height - _m.px(NestMetrics.homeHandleCenterY) - 4,
                                      child: Opacity(
                                        opacity: 1 - progress * 2,
                                        child: Center(
                                          child: DragHandle(
                                            // White on the photo frame, palette
                                            // ink elsewhere.
                                            color: _c.page == ShellPage.home
                                                ? const Color(0xFFFFFFFF)
                                                : palette.onSurface,
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
                          _AssistantOverlay(
                            state: _c.assistant,
                            palette: palette,
                            size: _m.px(160),
                          ),

                        // ── Toast ──────────────────────────────────────────
                        if (_c.toast != null)
                          _Toast(text: _c.toast!, palette: palette, metrics: _m),
                      ],
                    ),
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
        return Stack(
          fit: StackFit.expand,
          children: [
            PhotoFrameBackground(metrics: _m, palette: palette),
            // Over a photograph the clock is always white, like the device — the
            // scrim in PhotoFrameBackground is what keeps it legible.
            ClockBlock(
              metrics: _m,
              type: type,
              palette: palette,
              weather: widget.weather.current,
              now: now,
              use24Hour: _c.use24Hour,
              showSeconds: _c.showSeconds,
              animateWeather: widget.animateDecorations,
              forceLightText: true,
              albumTitle: _c.albumTitle,
              photoCredit: _credit.displayCredit,
            ),
          ],
        );
      case ShellPage.digest:
        return _DigestPage(
          metrics: _m,
          type: type,
          palette: palette,
          now: now,
          weather: widget.weather.current,
          weatherEnabled: widget.weather.enabled,
          weatherLoading: widget.weather.loading,
          calendar: widget.calendar,
          theme: _c.theme,
          onThemePick: _c.setTheme,
        );
      case ShellPage.homeControl:
        return _HomeControlPage(metrics: _m, type: type, palette: palette);
      case ShellPage.discover:
        return const SizedBox.shrink();
    }
  }

  /// Every quick-settings button does something real.
  ///
  /// This is the second version. The first one was four fakes out of seven:
  /// brightness changed a private field that nothing read, and camera and
  /// settings printed a toast *claiming* an action they had not performed —
  /// "Camera toggled", "Settings" — which is worse than doing nothing, because
  /// the user believes the device responded.
  ///
  /// The rule applied here: never report an action that did not happen. If the
  /// platform refuses, say so in words that name the failure.
  Future<void> _handleQuickSetting(QuickSettingKind kind) async {
    final c = _c;
    switch (kind) {
      case QuickSettingKind.brightness:
        // Two taps is a dim/bright pair, matching the Nest's own single-tap
        // behaviour. The setter drives the real panel.
        c.setBrightness(c.brightness > 0.5 ? 0.25 : 0.9);

      case QuickSettingKind.volume:
        c.setVolume(c.volume > 0.05 ? 0.0 : 0.5);
        c.showToast('Volume ${(c.volume * 100).round()}%');

      case QuickSettingKind.camera:
        if (!await c.platform.hasCamera()) {
          c.showToast('No camera on this device');
        } else if (!await c.platform.openCamera()) {
          c.showToast('No camera app available');
        }

      case QuickSettingKind.darkTheme:
        // This is the theme button now, not a dark-mode toggle. It cycles
        // Dynamic → White → Day → Afternoon → Night and back.
        c.cycleTheme();
        c.showToast(
          c.theme == NestTheme.dynamic ? 'Theme: follows the sun' : 'Theme: ${c.theme.label}',
        );

      case QuickSettingKind.zoomIn:
        // Close the sheet first. Navigating behind an open sheet is a button
        // that does nothing the user can see — the row covers the page you
        // were just sent to.
        c.closeSheet();
        c.goToPage(ShellPage.digest);

      case QuickSettingKind.feedback:
        final opened = await c.platform.openUrl('https://support.google.com/googlenest/');
        if (!opened) {
          // ActionLauncher has an independent path; only complain if both fail.
          final viaLauncher = await c.actionLauncher.openUrl(
            'https://support.google.com/googlenest/',
          );
          if (!viaLauncher) c.showToast('Could not open a browser');
        }

      case QuickSettingKind.settings:
        if (!await c.platform.openAppSettings()) {
          c.showToast('Settings unavailable on this device');
        }
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
    required this.weather,
    required this.weatherEnabled,
    required this.weatherLoading,
    required this.calendar,
    required this.theme,
    required this.onThemePick,
  });

  final NestMetrics metrics;
  final NestType type;
  final AmbientPalette palette;
  final DateTime now;
  final WeatherNow weather;
  final bool weatherEnabled;
  final bool weatherLoading;
  final CalendarService? calendar;
  final NestTheme theme;
  final void Function(NestTheme) onThemePick;

  /// The calendar column, as real content.
  ///
  /// Every branch is honest about why it is empty. "No more events today" when
  /// permission was never granted is a lie — it claims the user has a free day
  /// when in fact nothing was ever read.
  Widget _calendarCard(NestMetrics m) {
    final cal = calendar;
    if (cal == null || !cal.available) {
      return _Card(
        title: 'Calendar',
        body: 'Calendar permission not granted',
        metrics: m,
        palette: palette,
        type: type,
      );
    }
    final events = cal.today.take(3).toList();
    if (events.isEmpty) {
      return _Card(
        title: 'Calendar',
        body: 'Nothing else today',
        metrics: m,
        palette: palette,
        type: type,
      );
    }

    return _Card(
      title: 'Calendar',
      metrics: m,
      palette: palette,
      type: type,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final e in events)
            Padding(
              padding: EdgeInsets.only(bottom: m.px(8)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: m.px(62),
                    child: Text(
                      e.allDay ? 'All day' : _clockTime(e.start),
                      style: type.caption(color: palette.onSurfaceVariant),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: type.caption(color: palette.onSurfaceStrong),
                        ),
                        if (e.location.isNotEmpty)
                          Text(
                            e.location,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: type.caption(color: palette.onSurfaceVariant),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _clockTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

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
                Expanded(flex: 3, child: _calendarCard(m)),
                SizedBox(width: m.px(14)),
                Expanded(
                  flex: 2,
                  child: _Card(
                    title: 'Weather',
                    metrics: m,
                    palette: palette,
                    type: type,
                    body: weatherLoading
                        ? 'Checking…'
                        : !weatherEnabled
                        ? 'Set NEST_LAT / NEST_LON to enable'
                        : '${weather.condition.label} · '
                              '${weather.shortLabel}',
                  ),
                ),
                SizedBox(width: m.px(14)),
                Expanded(
                  flex: 2,
                  child: _Card(
                    title: 'Theme',
                    metrics: m,
                    palette: palette,
                    type: type,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(theme.label, style: type.caption(color: palette.onSurfaceStrong)),
                        const SizedBox(height: 4),
                        Text(
                          theme == NestTheme.dynamic ? 'Follows the time of day' : 'Pinned',
                          style: type.caption(color: palette.onSurfaceVariant),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final t in NestTheme.values)
                              _ThemeSwatch(
                                theme: t,
                                selected: t == theme,
                                metrics: m,
                                type: type,
                                onTap: () => onThemePick(t),
                              ),
                          ],
                        ),
                      ],
                    ),
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

/// A tappable preview of one pinned theme.
///
/// Renders the palette's own surface with its own ink, so the swatch is the
/// truth rather than a decorative approximation — you can see whether the text
/// is legible before you pick it.
class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({
    required this.theme,
    required this.selected,
    required this.metrics,
    required this.type,
    required this.onTap,
  });

  final NestTheme theme;
  final bool selected;
  final NestMetrics metrics;
  final NestType type;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    // Dynamic has no single colour to preview, so show the current live one.
    final preview = theme == NestTheme.dynamic
        ? AmbientPalette.at(DateTime.now().hour.toDouble() + DateTime.now().minute / 60)
        : AmbientPalette.of(theme);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: m.px(96),
        padding: EdgeInsets.symmetric(vertical: m.px(5)),
        decoration: BoxDecoration(
          color: preview.surface,
          borderRadius: BorderRadius.circular(m.px(9)),
          border: Border.all(
            color: selected
                ? const Color(0xFF4285F4)
                : preview.onSurfaceVariant.withValues(alpha: 0.28),
            width: selected ? m.px(2) : m.px(1),
          ),
        ),
        child: Text(
          theme == NestTheme.dynamic ? 'Sun' : theme.label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: type.caption(color: preview.onSurfaceStrong),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.title,
    required this.metrics,
    required this.palette,
    required this.type,
    this.body,
    this.child,
  }) : assert(body != null || child != null, 'a card needs something in it');

  final String title;

  /// Plain-text content. Ignored when [child] is given.
  final String? body;

  /// Rich content — an event list, a swatch grid. Ignored when [body] is given.
  final Widget? child;

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
            child: child ?? Text(body ?? '', style: type.body(color: palette.onSurfaceVariant)),
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
    'Lights',
    'Locks',
    'Speakers & TVs',
    'Connectivity',
    'Cameras',
    'Routines',
    'Climate',
    'Rooms',
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
          padding: EdgeInsets.symmetric(horizontal: metrics.px(22), vertical: metrics.px(12)),
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
