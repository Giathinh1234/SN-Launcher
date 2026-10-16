import 'package:flutter_test/flutter_test.dart';
import 'package:sn_launcher/src/services/photo_frame_service.dart';

/// The licence gate decides whether a photograph gets installed onto a user's
/// device. A bug here is silent and unlawful, and nothing about the happy path
/// would ever surface it — so it is tested directly.
///
/// "CC BY 4.0 SA" is the case that matters most: Commons returns that exact
/// string for some files, with no hyphen, and because it also contains "cc by"
/// any naive allow-list test lets it straight through.
void main() {
  const allowed = <String>[
    'Public domain',
    'CC0',
    'CC BY',
    'CC BY 2.0',
    'CC BY 3.0',
    'CC BY 4.0',
    'cc0 1.0',
    'public domain, attribution required',
  ];

  const refused = <String>[
    // Share-alike: a launcher cannot honour the viral-licensing obligation.
    'CC BY-SA 4.0',
    'CC BY-SA 2.0',
    'CC BY-SA 3.0',
    'CC BY 4.0 SA', // <- no hyphen; found by this test
    'CC BY 2.5 SA',
    'ShareAlike 3.0',
    'share alike',
    'Share-alike',
    // Non-commercial / no-derivatives.
    'CC BY-NC 4.0',
    'CC BY-NC-ND 4.0',
    'CC BY-ND 4.0',
    'NonCommercial',
    // Not redistributable at all.
    'Fair use',
    'Non-free',
    'All rights reserved',
    // Nonsense and empty must fail closed.
    '',
    '   ',
    'unknown',
  ];

  test('accepts genuinely redistributable licences', () {
    for (final l in allowed) {
      expect(licenceAllowsRedistribution(l), isTrue, reason: 'should allow "$l"');
    }
  });

  test('refuses everything else', () {
    for (final l in refused) {
      expect(
        licenceAllowsRedistribution(l),
        isFalse,
        reason: 'should refuse "${l.isEmpty ? "(empty)" : l}"',
      );
    }
  });

  test('is case-insensitive and tolerates padding', () {
    expect(licenceAllowsRedistribution('  cc by 4.0  '), isTrue);
    expect(licenceAllowsRedistribution('PUBLIC DOMAIN'), isTrue);
    expect(licenceAllowsRedistribution('CC BY-SA 4.0'), isFalse);
  });
}