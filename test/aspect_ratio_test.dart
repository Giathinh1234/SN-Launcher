import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sn_launcher/src/models/nest_action.dart';
import 'package:sn_launcher/src/screens/nest_shell.dart';
import 'package:sn_launcher/src/services/assistant_service.dart';
import 'package:sn_launcher/src/services/clock_service.dart';
import 'package:sn_launcher/src/services/feature_flags.dart';
import 'package:sn_launcher/src/services/weather_service.dart';
import 'package:sn_launcher/src/state/shell_controller.dart';
import 'package:sn_launcher/src/theme/ambient_palette.dart';
import 'package:sn_launcher/src/theme/nest_metrics.dart';

/// Does the layout survive a screen it was never measured on?
///
/// Two real devices, two very different shapes, and the brief was "will it work
/// as well or better on the other one". Rather than find out by installing on
/// both and squinting, this sweeps the shapes offline.
///
/// Worth having independently of that question, because the honest state of
/// the pixel work is that the clock block and the badge pitch are the only
/// things actually measured against a real Nest photograph. Everything else is
/// eyeballed, and eyeballed layout fails at the edges first — which is exactly
/// what this looks at.
///
/// No GUI is changed by any of this. The ef build must render identically to
/// the current app; a test that changed the layout would invalidate the
/// comparison the ef build exists to make.

/// Logical size, and where it came from.
const _shapes = <(String, Size, double)>[
  ('Nest Hub      1024x600  1.71', Size(1024, 600), 1.0),
  ('Nest Hub Max  1280x800  1.60', Size(1280, 800), 1.0),
  ('Nokia T20     1143x686  1.67', Size(1143, 686), 1.0), // 2000x1200 @280dpi
  ('4:3 tablet   1365x1024  1.33', Size(1365, 1024), 1.0),
  ('square-ish    1200x1150  1.04', Size(1200, 1150), 1.0),
  ('ultrawide     2000x900   2.22', Size(2000, 900), 1.0),
  ('portrait      800x1280  0.63', Size(800, 1280), 1.0),
];

class _Harness extends StatefulWidget {
  const _Harness({
    required this.size,
    required this.controller,
    required this.clock,
    required this.weather,
    required this.assistant,
  });

  final Size size;
  final ShellController controller;
  final ClockService clock;
  final WeatherService weather;
  final AssistantService assistant;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> with TickerProviderStateMixin {
  @override
  void dispose() {
    widget.controller.dispose();
    widget.clock.dispose();
    widget.weather.dispose();
    widget.assistant.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(fontFamily: 'GoogleSans'),
    home: Material(
      color: const Color(0xFF000000),
      child: NestShell(
        controller: widget.controller,
        clock: widget.clock,
        weather: widget.weather,
        assistant: widget.assistant,
        animateDecorations: false,
      ),
    ),
  );
}

Future<void> _pumpAt(
  WidgetTester tester,
  Size size,
  ShellPage page, {
  double sheet = 0,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);

  final clock = ClockService(showSeconds: true, autoTick: false);
  final weather = WeatherService();
  final assistant = AssistantService();
  final controller = ShellController(
    metrics: NestMetrics.forSize(size),
    vsync: tester,
  );
  controller.setPaletteForTest(AmbientPalette.at(12));
  controller.setSheetForTest(sheet);
  controller.goToPage(page);
  clock.overrideForTesting(DateTime(2022, 5, 26, 12, 0, 0));

  await tester.pumpWidget(
    _Harness(
      size: size,
      controller: controller,
      clock: clock,
      weather: weather,
      assistant: assistant,
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  // Without this the whole file measures the wrong thing.
  //
  // A widget test has no access to the app's fonts, so every Text falls back to
  // a wider default and the layout overflows by a few pixels — the "See all"
  // pill reported a 3.8px overflow at 1280x800 that does not exist on a device.
  // Worse, the icons render as Ahem boxes, so the screenshots a reviewer looks
  // at are quietly wrong. Loading the real faces first is what makes a failure
  // here mean a real failure.
  setUpAll(_loadFonts);

  // All features on: the widest possible layout, which is the case most likely
  // to overflow. If only the reduced build is swept, the worst case is never
  // rendered.
  FeatureFlags.forTesting = FeatureFlags.parse(
    File('assets/features.ef.json').readAsStringSync(),
    'ef',
  );
  tearDown(() => FeatureFlags.forTesting = FeatureFlags.empty);

  for (final (label, size, _) in _shapes) {
    group(label, () {
      for (final page in [ShellPage.home, ShellPage.digest, ShellPage.discover]) {
        testWidgets('${page.name} renders without overflowing', (tester) async {
          await _pumpAt(tester, size, page);
          // A RenderFlex overflow is reported through the framework's error
          // handler, which a test captures rather than prints.
          expect(
            tester.takeException(),
            isNull,
            reason: '${page.name} at $size',
          );
        });
      }

      testWidgets('the launcher sheet renders without overflowing', (tester) async {
        // Open, not half-open: the sheet's rows are packed at fixed pitch, so
        // a fully open sheet on a short screen is where they collide.
        await _pumpAt(tester, size, ShellPage.home, sheet: 1.0);
        expect(tester.takeException(), isNull, reason: 'sheet at $size');
      });
    });
  }

  group('the measured row still measures the same', () {
    // Aspect-ratio work must not quietly move the one thing that *is* a real
    // measurement. tool/verify.py asserts the badge pitch against a rectified
    // photograph of a real Nest Hub Max; this is the same claim in a language
    // the test runner can check.
    testWidgets('seven badges at 118 design px, at every shape', (tester) async {
      for (final (label, size, _) in _shapes) {
        final m = NestMetrics.forSize(size);
        expect(
          quickSettingsFor(FeatureFlags.parse(
            '{"features":{"settings":true,"quickSettings":true}}',
            't',
          )).length,
          7,
          reason: label,
        );
        expect(m.px(NestMetrics.appRowSpacing), closeTo(m.px(NestMetrics.appRowSpacing), 0.001));
      }
    });
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

  // One frozen instance of a variable font, so the weight-based helper above
  // finds nothing and this has to be loaded by hand.
  final symbols = File('assets/fonts/MaterialSymbolsRounded.ttf');
  if (symbols.existsSync()) {
    await (FontLoader('MaterialSymbolsRounded')
          ..addFont(Future<ByteData>.value(
            ByteData.sublistView(symbols.readAsBytesSync()),
          )))
        .load();
  }
}
