import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sn_launcher/src/screens/nest_shell.dart';
import 'package:sn_launcher/src/services/assistant_service.dart';
import 'package:sn_launcher/src/services/clock_service.dart';
import 'package:sn_launcher/src/services/feature_flags.dart';
import 'package:sn_launcher/src/services/weather_service.dart';
import 'package:sn_launcher/src/state/shell_controller.dart';
import 'package:sn_launcher/src/theme/ambient_palette.dart';
import 'package:sn_launcher/src/theme/nest_icons.dart';
import 'package:sn_launcher/src/theme/nest_metrics.dart';
import 'package:sn_launcher/src/widgets/assistant_lightbar.dart';

/// The point of these: [feature_flags_test.dart] proves the *config files* are
/// right, which is not the same thing as proving the *GUI* honours them. A flag
/// that parses and is then never read is a plausible, silent failure — and one
/// already happened here, with `quickSettings`, which was declared in both
/// JSON files and gated nowhere.
///
/// So: render the real shell with each shipped config and assert on what is
/// actually on screen.
FeatureFlags efFlags() =>
    FeatureFlags.parse(File('assets/features.ef.json').readAsStringSync(), 'ef');

FeatureFlags reducedFlags() => FeatureFlags.parse(
  File('assets/features.json').readAsStringSync(),
  'reduced',
);

const _size = Size(1280, 800);

class _Harness extends StatefulWidget {
  const _Harness({
    required this.controller,
    required this.clock,
    required this.weather,
    required this.assistant,
  });

  final ShellController controller;
  final ClockService clock;
  final WeatherService weather;

  /// A real AssistantService, not a stub. The lightbar gate reads
  /// `assist != null`, so passing null here would make "absent in the reduced
  /// build" pass for entirely the wrong reason.
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

Future<_Harness> _pump(
  WidgetTester tester, {
  required ShellPage page,
}) async {
  final clock = ClockService(showSeconds: true, autoTick: false);
  final weather = WeatherService();
  // Constructed but never asked to listen: constructing touches no platform
  // channel, and _startListening is never invoked in these tests.
  final assistant = AssistantService();
  final controller = ShellController(
    metrics: NestMetrics.forSize(_size),
    vsync: tester,
  );
  controller.setPaletteForTest(AmbientPalette.at(12));
  controller.setSheetForTest(0);
  controller.goToPage(page);
  clock.overrideForTesting(DateTime(2022, 5, 26, 12, 0, 0));

  await tester.pumpWidget(
    _Harness(
      controller: controller,
      clock: clock,
      weather: weather,
      assistant: assistant,
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return _Harness(
    controller: controller,
    clock: clock,
    weather: weather,
    assistant: assistant,
  );
}

void main() {
  final ef = efFlags();
  final reduced = reducedFlags();

  tearDown(() {
    // Leave the static as the reduced build, so one test cannot hand another
    // a configuration it did not set up.
    FeatureFlags.forTesting = reduced;
  });

  group('the settings gear', () {
    testWidgets('is on screen in the ef build', (tester) async {
      FeatureFlags.forTesting = ef;
      await _pump(tester, page: ShellPage.home);
      expect(find.byIcon(NestIcons.Settings), findsOneWidget);
    });

    testWidgets('is on screen in the reduced build too', (tester) async {
      // This is the capability the user asked to keep in both.
      FeatureFlags.forTesting = reduced;
      await _pump(tester, page: ShellPage.home);
      expect(find.byIcon(NestIcons.Settings), findsOneWidget);
    });

    testWidgets('disappears when the feature is off', (tester) async {
      // Neither shipped config has settings off, so the two tests above cannot
      // tell whether this gate works at all — deleting it would change nothing
      // and they would both still pass. This third configuration is what makes
      // the gate real.
      FeatureFlags.forTesting = FeatureFlags.parse('{"features":{}}', 'none');
      await _pump(tester, page: ShellPage.home);
      expect(find.byIcon(NestIcons.Settings), findsNothing);
    });
  });

  group('the assistant lightbar', () {
    testWidgets('is on screen in the ef build', (tester) async {
      FeatureFlags.forTesting = ef;
      await _pump(tester, page: ShellPage.home);
      expect(find.byType(AssistantLightbar), findsOneWidget);
    });

    testWidgets('is absent in the reduced build', (tester) async {
      // The rule this repo is built on: never show an affordance for something
      // this build cannot do. A reduced build with a listening bar that does
      // nothing is the same lie as the old four-dot orb.
      FeatureFlags.forTesting = reduced;
      await _pump(tester, page: ShellPage.home);
      expect(find.byType(AssistantLightbar), findsNothing);
    });
  });

  group('the digest page', () {
    testWidgets('renders cards in the ef build', (tester) async {
      FeatureFlags.forTesting = ef;
      await _pump(tester, page: ShellPage.digest);
      expect(find.textContaining('Good'), findsOneWidget);
      expect(find.text('Weather'), findsOneWidget);
      expect(find.text('Theme'), findsOneWidget);
      expect(find.text('Calendar'), findsOneWidget);
    });

    testWidgets('collapses entirely in the reduced build', (tester) async {
      // Asserted on the greeting, not on the cards.
      //
      // The cards are individually gated too, so checking that they are absent
      // passes even with this page's own gate deleted — the row is empty either
      // way and the test proves nothing. The greeting is the part that only
      // this gate controls, so it is the part worth asserting on.
      FeatureFlags.forTesting = reduced;
      await _pump(tester, page: ShellPage.digest);
      expect(find.textContaining('Good'), findsNothing);
      expect(find.text('Weather'), findsNothing);
      expect(find.text('Theme'), findsNothing);
      expect(find.text('Calendar'), findsNothing);
      expect(find.text('Photos'), findsNothing);
    });
  });

  group('the home page is unaffected by any of it', () {
    // The ef build must look exactly like the current app — that was the
    // point of shipping it with no GUI change, so the test on real hardware
    // would be about whether it runs, not about how it looks.
    for (final entry in {'ef': ef, 'reduced': reduced}.entries) {
      testWidgets('${entry.key} build renders the clock', (tester) async {
        FeatureFlags.forTesting = entry.value;
        await _pump(tester, page: ShellPage.home);
        expect(find.text('12:00'), findsOneWidget);
        expect(find.byType(AssistantLightbar), entry.key == 'ef' ? findsOneWidget : findsNothing);
      });
    }
  });
}