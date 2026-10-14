import 'dart:io';

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sn_launcher/src/screens/nest_shell.dart';
import 'package:sn_launcher/src/services/clock_service.dart';
import 'package:sn_launcher/src/services/weather_service.dart';
import 'package:sn_launcher/src/state/shell_controller.dart';
import 'package:sn_launcher/src/theme/ambient_palette.dart';
import 'package:sn_launcher/src/theme/nest_metrics.dart';

/// Renders the shell at exact device resolutions and writes PNGs under
/// `build/shots/`, so the layout can be compared side-by-side against the
/// rectified photographs of a real Nest Hub in `refs/`.
class _Harness extends StatefulWidget {
  const _Harness({
    required this.size,
    required this.hour,
    required this.sheet,
    required this.page,
    required this.out,
    this.theme,
  });

  final Size size;
  final double hour;
  final double sheet;
  final ShellPage page;
  final String out;

  /// Pin a theme instead of deriving one from [hour]. Null = dynamic.
  final NestTheme? theme;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> with TickerProviderStateMixin {
  // autoTick/animate off: an always-rescheduling timer or a repeating
  // controller stops the test harness from ever settling.
  late final ClockService _clock =
      ClockService(showSeconds: true, autoTick: false);
  late final WeatherService _weather = WeatherService();
  late final ShellController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ShellController(metrics: NestMetrics.forSize(widget.size), vsync: this);
    if (widget.theme == null) {
      _controller.setPaletteForTest(AmbientPalette.at(widget.hour));
    } else {
      _controller.setThemeForTest(widget.theme!);
    }
    _controller.setSheetForTest(widget.sheet);
    _controller.goToPage(widget.page);
    _clock.overrideForTesting(DateTime(2022, 5, 26, 9, 45, 0));
  }

  @override
  void dispose() {
    _controller.dispose();
    _clock.dispose();
    _weather.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'GoogleSans'),
      home: RepaintBoundary(
        key: const ValueKey('capture'),
        // Without a Material the ambient DefaultTextStyle is Flutter's internal
        // error style (yellow double-underlined monospace), which ruins the
        // capture.
        child: Material(
          color: const Color(0xFF000000),
          child: NestShell(
            controller: _controller,
            clock: _clock,
            weather: _weather,
            animateDecorations: false,
          ),
        ),
      ),
    );
  }
}

Future<void> _capture(
  WidgetTester tester,
  _Harness harness,
) async {
  await tester.pumpWidget(harness);
  // The weather glyph + Assistant orb are disabled here, so a couple of fixed
  // pumps are enough; pumpAndSettle is not usable against endless animations.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));

  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('capture')),
  );

  // toImage/toByteData do real async work on the raster thread, which only
  // progresses inside runAsync.
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File('build/shots/${harness.out}.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(data!.buffer.asUint8List());
    image.dispose();
  });

  // Tear the tree down explicitly so every AnimationController is disposed
  // before the harness looks for leaked tickers.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}


void main() {
  setUpAll(_loadFonts);
  // One contact sheet of every pinned theme, so the set can be judged as a set
  // rather than one at a time. Dynamic is rendered at 20:30, where the sun is
  // low and the palette is at its most different from plain Night.
  for (final t in NestTheme.values) {
    testWidgets('theme: ${t.name} @ 1280x800', (tester) async {
      tester.view
        ..physicalSize = const Size(1280, 800)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await _capture(
        tester,
        _Harness(
          size: const Size(1280, 800),
          hour: 20.5,
          theme: t,
          sheet: 1,
          page: ShellPage.digest,
          out: 'theme_${t.name}_1280x800',
        ),
      );
    });
  }


  setUp(() {
    // The test binding enables both of these, and `debugPaintSizeEnabled`
    // strokes a pure-yellow (#FFFF00) box around every render object — which
    // lands directly under each text run and poisons pixel measurements.
    debugPaintSizeEnabled = false;
    debugPaintBaselinesEnabled = false;
  });

  testWidgets('home @ 1024x600 — Nest Hub', (tester) async {
    tester.view
      ..physicalSize = const Size(1024, 600)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await _capture(
      tester,
      const _Harness(
        size: Size(1024, 600),
        hour: 9.75,
        sheet: 0,
        page: ShellPage.home,
        out: 'home_1024x600',
      ),
    );
  });

  testWidgets('home @ 1280x800 — Nest Hub Max', (tester) async {
    tester.view
      ..physicalSize = const Size(1280, 800)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await _capture(
      tester,
      const _Harness(
        size: Size(1280, 800),
        hour: 9.75,
        sheet: 0,
        page: ShellPage.home,
        out: 'home_1280x800',
      ),
    );
  });

  testWidgets('night home @ 1024x600', (tester) async {
    tester.view
      ..physicalSize = const Size(1024, 600)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await _capture(
      tester,
      const _Harness(
        size: Size(1024, 600),
        hour: 23.0,
        sheet: 0,
        page: ShellPage.home,
        out: 'home_night_1024x600',
      ),
    );
  });

  testWidgets('launcher sheet @ 1280x800', (tester) async {
    tester.view
      ..physicalSize = const Size(1280, 800)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await _capture(
      tester,
      const _Harness(
        size: Size(1280, 800),
        hour: 9.75,
        sheet: 1,
        page: ShellPage.home,
        out: 'sheet_1280x800',
      ),
    );
  });

  testWidgets('app drawer @ 1280x800', (tester) async {
    tester.view
      ..physicalSize = const Size(1280, 800)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await _capture(
      tester,
      const _Harness(
        size: Size(1280, 800),
        hour: 9.75,
        sheet: 1,
        page: ShellPage.discover,
        out: 'drawer_1280x800',
      ),
    );
  });
}

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> weights) async {
    final loader = FontLoader(family);
    var any = false;
    for (final w in weights) {
      final f = File('assets/fonts/$family-$w.ttf');
      if (!f.existsSync()) continue;
      any = true;
      loader.addFont(
        Future<ByteData>.value(ByteData.sublistView(f.readAsBytesSync())),
      );
    }
    if (any) await loader.load();
  }

  await load('GoogleSans', ['400', '500', '600', '700']);
  await load('Poppins', ['300', '400', '500']);

  // Material Symbols has no weight variants — it is one frozen instance of a
  // variable font — so the helper above, which looks for `$family-$weight.ttf`,
  // finds nothing. Without loading it here every icon renders as an Ahem box
  // and the screenshots quietly lie about the drawer's appearance.
  final symbols = File('assets/fonts/MaterialSymbolsRounded.ttf');
  if (symbols.existsSync()) {
    await (FontLoader('MaterialSymbolsRounded')
          ..addFont(Future<ByteData>.value(
            ByteData.sublistView(symbols.readAsBytesSync()),
          )))
        .load();
  } else {
    throw StateError(
      'assets/fonts/MaterialSymbolsRounded.ttf is missing — run '
      'tool/build_icons.py. Icons would render as empty boxes.',
    );
  }
}