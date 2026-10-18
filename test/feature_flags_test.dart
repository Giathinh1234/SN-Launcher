import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sn_launcher/src/models/nest_action.dart';
import 'package:sn_launcher/src/services/feature_flags.dart';

/// These read the two config files **off disk** rather than through
/// [FeatureFlags.load].
///
/// That distinction is the point. `load` would happily parse a file whose
/// contents are wrong; only reading the shipped bytes can tell us that
/// `assets/features.json` actually says what this project claims it says.
FeatureFlags loadFile(String name) =>
    FeatureFlags.parse(File('assets/$name').readAsStringSync(), 'assets/$name');

void main() {
  group('parsing', () {
    test('reads the features node', () {
      final f = FeatureFlags.parse('{"features":{"assistant":true}}', 't');
      expect(f.isOn('assistant'), isTrue);
      expect(f.isOn('music'), isFalse);
    });

    test('accepts a flat map with no features wrapper', () {
      final f = FeatureFlags.parse('{"assistant":true,"music":false}', 't');
      expect(f.isOn('assistant'), isTrue);
      expect(f.isOn('music'), isFalse);
    });

    test('ignores non-boolean values rather than guessing', () {
      // "yes" is not true. Coercing it would mean a typo silently enables a
      // feature the author meant to disable.
      final f = FeatureFlags.parse('{"features":{"assistant":"yes"}}', 't');
      expect(f.isOn('assistant'), isFalse);
    });

    test('malformed JSON fails closed, not open', () {
      // The whole design rests on this: a broken config must produce a
      // launcher with nothing switched on, never one that invents
      // capabilities it was not built with.
      final f = FeatureFlags.parse('{"features": {', 't');
      expect(f.all, isEmpty);
      expect(f.isOn('assistant'), isFalse);
    });

    test('a JSON array or scalar fails closed', () {
      expect(FeatureFlags.parse('[1,2,3]', 't').all, isEmpty);
      expect(FeatureFlags.parse('42', 't').all, isEmpty);
    });

    test('reports flags this build does not implement', () {
      // Otherwise a typo like "assisstant" is silently ignored and the author
      // spends an afternoon wondering why nothing happens.
      final f = FeatureFlags.parse(
        '{"features":{"assisstant":true,"assistant":true}}',
        't',
      );
      expect(f.unknown, ['assisstant']);
      expect(f.isOn('assistant'), isTrue);
    });

    test('comment keys are documentation, not unknown flags', () {
      final f = loadFile('features.json');
      expect(f.unknown, isEmpty, reason: '_comment must not read as a flag');
    });
  });

  group('the shipped ExtraFeature build', () {
    final f = loadFile('features.ef.json');

    test('enables every feature the build knows how to gate', () {
      // If someone adds a flag to FeatureFlags.known and forgets the ef file,
      // this is the test that says so. Without it the new feature ships
      // switched off in the one build that is supposed to show everything.
      final off = FeatureFlags.known.where((k) => !f.isOn(k)).toList();
      expect(off, isEmpty, reason: 'ef build leaves $off off');
    });

    test('declares no flags the build does not know', () {
      expect(f.unknown, isEmpty);
    });
  });

  group('the shipped reduced build', () {
    final f = loadFile('features.json');

    /// What "reduced" means: a launcher, and nothing else. These two stay on
    /// in both builds because without them it is not a launcher — there is no
    /// way to reach brightness, volume, or configuration.
    const core = {'settings', 'quickSettings'};

    test('keeps the launcher core on', () {
      expect(
        core.where(f.isOn).toSet(),
        core,
        reason: 'reduced build lost a core launcher capability',
      );
    });

    test('has every optional extra switched off', () {
      // The whole point of the reduced build. Guarded explicitly so that
      // flipping a flag on in this file is a deliberate act, not an accident
      // that ships to users.
      final on = FeatureFlags.known
          .where((k) => !core.contains(k))
          .where(f.isOn)
          .toList();
      expect(on, isEmpty, reason: 'reduced build unexpectedly enables $on');
    });

    test('declares no flags the build does not know', () {
      expect(f.unknown, isEmpty);
    });
  });

  group('quick-settings row', () {
    test('is the full measured row when both gates are on', () {
      // Seven. tool/verify.py asserts this badge pitch against a rectified
      // photograph of a real Nest Hub Max, so this count is a measurement and
      // not a preference — a build that silently dropped to six would break
      // the one assertion the pixel audit actually makes.
      final f = FeatureFlags.parse(
        '{"features":{"settings":true,"quickSettings":true}}',
        't',
      );
      expect(quickSettingsFor(f).length, 7);
      expect(
        quickSettingsFor(f).map((q) => q.kind),
        contains(QuickSettingKind.settings),
      );
    });

    test('drops the settings button when settings is off', () {
      final f = FeatureFlags.parse('{"features":{"quickSettings":true}}', 't');
      expect(quickSettingsFor(f).length, 6);
      expect(
        quickSettingsFor(f).map((q) => q.kind),
        isNot(contains(QuickSettingKind.settings)),
      );
    });

    test('is empty when the row itself is off', () {
      final f = FeatureFlags.parse('{"features":{"settings":true}}', 't');
      expect(quickSettingsFor(f), isEmpty);
    });
  });
}