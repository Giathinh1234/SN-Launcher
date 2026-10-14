import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/nest_action.dart';

/// Result of a launch attempt, surfaced in the UI as a small toast.
enum LaunchOutcome { launched, notInstalled, failed }

/// Opens real applications from launcher icons.
///
/// One code path covers every target:
///  * **Android** — a deep link (`spotify:`) or an https fallback, opened with
///    [url_launcher]'s platform channel. Nothing heavier is needed, which keeps
///    the APK small and cold-start cheap on 1 GB tablets.
///  * **Linux** — try the native binary first (`spotify`), fall back to
///    `xdg-open`.
///  * **macOS** — `open -a <app>` when we know the bundle id, else `open <url>`.
class ActionLauncher {
  const ActionLauncher();

  /// Custom scheme → macOS bundle identifier, so tapping "Spotify" on a Mac
  /// opens the real app instead of a browser error page.
  static const Map<String, String> _macBundleIds = {
    'spotify:': 'com.spotify.client',
    'https://music.youtube.com': 'com.google.ytmusic',
    'https://www.youtube.com': 'com.google.ytmusic',
  };

  Future<LaunchOutcome> launch(NestAction action) async {
    final url = action.intentUrl;
    if (url != null) {
      try {
        if (await canLaunchUrl(Uri.parse(url))) {
          if (await launchUrl(
            Uri.parse(url),
            mode: LaunchMode.externalApplication,
          )) {
            return LaunchOutcome.launched;
          }
        }
      } catch (e) {
        debugPrint('ActionLauncher: primary launch failed: $e');
      }
    }

    final exec = action.linuxExec;
    if (exec != null && !kIsWeb && Platform.isLinux) {
      try {
        final r = await Process.run('which', [exec]);
        if (r.exitCode == 0) {
          await Process.start(exec, const []);
          return LaunchOutcome.launched;
        }
      } catch (_) {/* fall through */}
      try {
        final r = await Process.run('xdg-open', [exec]);
        if (r.exitCode == 0) return LaunchOutcome.launched;
      } catch (_) {/* fall through */}
    }

    // macOS bundle id route.
    if (!kIsWeb && Platform.isMacOS && url != null) {
      final bundle = _macBundleIds[url];
      if (bundle != null) {
        try {
          final r = await Process.run('open', ['-b', bundle]);
          if (r.exitCode == 0) return LaunchOutcome.launched;
        } catch (_) {/* fall through */}
      }
    }

    // Last resort: hand the deep link to the OS.
    if (url != null && !kIsWeb) {
      try {
        if (Platform.isLinux || Platform.isMacOS) {
          final r = await Process.run('xdg-open', [url]);
          if (r.exitCode == 0) return LaunchOutcome.launched;
        }
      } catch (_) {/* fall through */}
    }

    return url == null ? LaunchOutcome.notInstalled : LaunchOutcome.failed;
  }

  /// Opens an arbitrary web address (settings links, feedback, docs).
  Future<bool> openUrl(String url) async {
    try {
      return await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}