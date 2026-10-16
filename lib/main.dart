import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/models/nest_action.dart';
import 'src/models/photo_credit.dart';
import 'src/services/calendar_service.dart';
import 'src/services/photo_frame_service.dart';
import 'src/services/frame_stats.dart';
import 'src/screens/nest_shell.dart';
import 'src/services/clock_service.dart';
import 'src/services/weather_service.dart';
import 'src/state/shell_controller.dart';
import 'src/theme/nest_metrics.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Surface build/layout errors on stderr so they land in `adb logcat` with the
  // full stack. Without this a release APK just paints an error box and says
  // nothing useful about what went wrong.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    // ignore: avoid_print
    print('NESTLAUNCH-FRAMEWORK-ERROR: ${details.exceptionAsString()}');
    if (details.stack != null) {
      // ignore: avoid_print
      print('NESTLAUNCH-STACK: ${details.stack}');
    }
  };

  // A launcher lives on a big screen and must never rotate or letterbox
  // unexpectedly — lock to landscape, the orientation the Nest Hub ships in.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Before the first frame, not after it.
  //
  // The photographer's credit is a 350-byte JSON file, but the widget that
  // shows it is `late final` — it reads the credit once and keeps it. Loading
  // post-frame therefore raced it and the name never appeared. Doing it here
  // costs well under a millisecond and makes the first frame final.
  await PhotoCredit.preload();

  runApp(const NestLauncherApp());

  // Go chrome-less *after* the first frame. Setting the system UI mode before
  // the engine has a view attached is silently discarded, which leaves the
  // status and navigation bars sitting on top of the UI forever.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  });
}

class NestLauncherApp extends StatefulWidget {
  const NestLauncherApp({super.key});

  @override
  State<NestLauncherApp> createState() => _NestLauncherAppState();
}

class _NestLauncherAppState extends State<NestLauncherApp>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final ClockService _clock = ClockService();
  late final WeatherService _weather = WeatherService();
  late final CalendarService _calendar = CalendarService();
  late final PhotoFrameService _photos = PhotoFrameService();
  final FrameStats _frameStats = FrameStats();
  bool _weatherConfigured = false;
  ShellController? _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Both of these ask for a runtime permission or do disk IO. Deliberately
    // after the first frame: a launcher that waits on a permission dialog
    // before painting has already lost the race it exists to win.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_controller?.restore());
      unawaited(_calendar.start());
      // Never on the critical path: the bundled photograph is already on
      // screen, and this only upgrades it later.
      unawaited(_photos.start());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // A wall display is usually never backgrounded, but a permission dialog
      // does this. Refresh so a calendar granted mid-session appears.
      unawaited(_calendar.refresh());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _calendar.dispose();
    _photos.dispose();
    _clock.dispose();
    _weather.dispose();
    _frameStats.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SN-Launcher',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        fontFamily: 'GoogleSans',
        // The shell paints everything itself; Material's own theming would
        // only add layers we do not want on a weak GPU.
        scaffoldBackgroundColor: const Color(0xFF000000),
        useMaterial3: true,
      ),

      // A route must exist. Without one, `WidgetsApp` builds no `Navigator`
      // at all (it decides this from `home`/`routes`/`onGenerateRoute`), and
      // `PopScope` — which registers against a `ModalRoute` — silently does
      // nothing. Back then falls through to `SystemNavigator.pop()` and the
      // launcher exits, which is exactly what it used to do.
      home: Builder(builder: (context) {
        final m = NestMetrics.of(context);
        _controller ??= ShellController(metrics: m, vsync: this);
        return Stack(
          children: [
            NestShell(
              controller: _controller!,
              clock: _clock,
              weather: _weather,
              calendar: _calendar,
              photos: _photos,
            ),
            if (FrameStats.enabled) PerfOverlay(stats: _frameStats),
          ],
        );
      }),

      builder: (context, child) {
        // Replace the opaque error box with the actual message, so a failure on
        // a device you cannot attach a debugger to is readable on the screen.
        ErrorWidget.builder = (details) => Directionality(
          textDirection: TextDirection.ltr,
          child: Container(
            color: const Color(0xFFCC0000),
            padding: const EdgeInsets.all(12),
            child: Text(
              details.exceptionAsString(),
              style: const TextStyle(color: Colors.white, fontSize: 20),
            ),
          ),
        );
        final m = NestMetrics.of(context);
        // Logged so on-device geometry can be reconciled with the design
        // canvas: `adb logcat -s flutter`. Catches the case where the first
        // frame reports a different MediaQuery size than the settled one.
        debugPrint('NESTLAUNCH-GEOMETRY size=${m.size.width.toStringAsFixed(1)}'
            'x${m.size.height.toStringAsFixed(1)}'
            ' dpr=${MediaQuery.maybeOf(context)?.devicePixelRatio}'
            ' u=${m.u.toStringAsFixed(4)}');

        // Optional pinned location, so weather works without a runtime location
        // prompt — a real cost on a wall-mounted tablet nobody taps again:
        //   --dart-define=NEST_LAT=-33.86 --dart-define=NEST_LON=151.20
        final lat = double.tryParse(const String.fromEnvironment('NEST_LAT'));
        final lon = double.tryParse(const String.fromEnvironment('NEST_LON'));
        if (lat != null && lon != null && !_weatherConfigured) {
          _weatherConfigured = true;
          _weather.configure(latitude: lat, longitude: lon);
        }

        return MediaQuery.withNoTextScaling(
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle.light,
            // A `Material` is required, not cosmetic: without one the ambient
            // DefaultTextStyle falls back to Flutter's internal error style —
            // 48px monospace with a yellow double underline — and every label
            // in the shell renders in it.
            child: Material(
              color: const Color(0xFF000000),
              // `child` IS the Navigator. Dropping it is what leaves the app
              // with no route stack at all. It has to sit inside the returned
              // subtree so the route inherits this Material's text style.
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// Re-exported so platform shells can reuse the canonical action list.
List<NestAction> get defaultActions => kNestActions;