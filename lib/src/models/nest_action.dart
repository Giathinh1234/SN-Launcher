import 'package:flutter/material.dart';

import '../theme/ambient_palette.dart';

/// One entry in the Nest "Actions on Google" launcher.
///
/// The real list (Cast firmware 1.56) is 21 entries, reproduced here verbatim.
/// First-party entries deliberately carry **no** "Google" prefix, matching the
/// device.
enum NestIconKind {
  assistant,
  broadcast,
  calendar,
  camera,
  cast,
  clock,
  contacts,
  games,
  home,
  meet,
  music,
  netflix,
  news,
  pandora,
  photos,
  podcasts,
  reminders,
  settings,
  stories,
  timer,
  weather,
  youtube,
  youtubeTv,
  zoom,
}

@immutable
class NestAction {
  const NestAction({
    required this.id,
    required this.label,
    required this.icon,
    required this.tint,
    this.badgeShape = NestBadgeShape.circle,
    this.badgeColor,
    this.badgeGlyph,
    this.intentUrl,
    this.intentPackage,
    this.linuxExec,
  });

  final String id;
  final String label;
  final NestIconKind icon;

  /// Brand colour used for the badge background.
  final Color tint;

  /// Circle or rounded square.
  final NestBadgeShape badgeShape;

  /// Optional contrasting glyph drawn on top of [tint] (Netflix, YouTube...).
  final Color? badgeColor;
  final String? badgeGlyph;

  /// Android deep link, e.g. `spotify:`.
  final String? intentUrl;
  final String? intentPackage;

  /// Linux/Android fallback: an executable or desktop file.
  final String? linuxExec;

  bool get isThirdParty =>
      intentUrl != null || intentPackage != null || linuxExec != null;
}

/// The 21 built-in "Actions on Google" entries, in the device's alphabetical
/// grid order.
const List<NestAction> kNestActions = [
  NestAction(id: 'assistant', label: 'Assistant', icon: NestIconKind.assistant, tint: Color(0xFF4285F4), badgeColor: Colors.white, badgeGlyph: 'A'),
  NestAction(id: 'broadcast', label: 'Broadcast', icon: NestIconKind.broadcast, tint: Color(0xFF7E57C2), badgeColor: Colors.white, badgeGlyph: '((·))'),
  NestAction(id: 'calendar', label: 'Calendar', icon: NestIconKind.calendar, tint: Color(0xFF4285F4), badgeShape: NestBadgeShape.squircle),
  NestAction(id: 'camera', label: 'Camera', icon: NestIconKind.camera, tint: Color(0xFF5F6368)),
  NestAction(id: 'cast', label: 'Cast', icon: NestIconKind.cast, tint: Color(0xFF4285F4)),
  NestAction(id: 'clock', label: 'Clock', icon: NestIconKind.clock, tint: Color(0xFF5F6368)),
  NestAction(id: 'contacts', label: 'Contacts', icon: NestIconKind.contacts, tint: Color(0xFF4285F4), badgeColor: Colors.white, badgeGlyph: '👤'),
  NestAction(id: 'games', label: 'Games', icon: NestIconKind.games, tint: Color(0xFF9AA0A6)),
  NestAction(id: 'home', label: 'Home', icon: NestIconKind.home, tint: Color(0xFF34A853)),
  NestAction(id: 'meet', label: 'Meet', icon: NestIconKind.meet, tint: Color(0xFF00897B)),
  NestAction(id: 'netflix', label: 'Netflix', icon: NestIconKind.netflix, tint: Color(0xFF0F0F0F), badgeColor: Color(0xFFE50914), badgeGlyph: 'N'),
  NestAction(id: 'news', label: 'News', icon: NestIconKind.news, tint: Color(0xFF5F6368)),
  NestAction(id: 'pandora', label: 'Pandora', icon: NestIconKind.pandora, tint: Color(0xFF1B1B1B), badgeColor: Color(0xFF00A0DE), badgeGlyph: 'P'),
  NestAction(id: 'photos', label: 'Photos', icon: NestIconKind.photos, tint: Color(0xFFEA4335)),
  NestAction(id: 'podcasts', label: 'Podcasts', icon: NestIconKind.podcasts, tint: Color(0xFF5F6368)),
  NestAction(id: 'reminders', label: 'Reminders', icon: NestIconKind.reminders, tint: Color(0xFF4285F4)),
  NestAction(id: 'settings', label: 'Settings', icon: NestIconKind.settings, tint: Color(0xFF5F6368)),
  NestAction(id: 'spotify', label: 'Spotify', icon: NestIconKind.music, tint: Color(0xFF1DB954), badgeColor: Colors.black, badgeGlyph: '≋',
      intentUrl: 'spotify:', intentPackage: 'com.spotify.music', linuxExec: 'spotify'),
  NestAction(id: 'stories', label: 'Stories', icon: NestIconKind.stories, tint: Color(0xFF4285F4)),
  NestAction(id: 'timer', label: 'Timer', icon: NestIconKind.timer, tint: Color(0xFF4285F4), badgeColor: Colors.white, badgeGlyph: '⧗'),
  NestAction(id: 'weather', label: 'Weather', icon: NestIconKind.weather, tint: Color(0xFF5B9BD5)),
  NestAction(id: 'youtubemusic', label: 'YT Music', icon: NestIconKind.youtube, tint: Color(0xFFFF0000), badgeColor: Colors.white, badgeGlyph: '▶',
      intentUrl: 'https://music.youtube.com', intentPackage: 'com.google.android.apps.youtube.music', linuxExec: 'youtube-music'),
  NestAction(id: 'youtubetv', label: 'YT TV', badgeShape: NestBadgeShape.squircle, icon: NestIconKind.youtubeTv, tint: Color(0xFF9AA0A6)),
  NestAction(id: 'youtube', label: 'YouTube', badgeShape: NestBadgeShape.squircle, icon: NestIconKind.youtube, tint: Color(0xFFFF0000), badgeColor: Colors.white, badgeGlyph: '▶',
      intentUrl: 'https://www.youtube.com', intentPackage: 'com.google.android.youtube', linuxExec: 'youtube'),
  NestAction(id: 'zoom', label: 'Zoom', icon: NestIconKind.zoom, tint: Color(0xFF2D8CFF)),
];

/// Quick-settings row contents. Seven entries on the Hub Max, matching the
/// icons measured in the rectified photograph.
/// The device does not force every badge into a circle — it keeps each
/// brand's own silhouette (YouTube's squircle, Calendar's rounded square) and
/// only uses discs for apps that are genuinely round.
enum NestBadgeShape { circle, squircle }

/// The seven buttons in the quick-settings row.
///
/// [darkTheme] is no longer a dark-mode toggle — it is the **theme** button,
/// cycling Dynamic → White → Day → Afternoon → Night. [zoomIn] no longer goes
/// to home control; it opens the Digest, which is where the calendar and
/// weather cards live.
enum QuickSettingKind { brightness, volume, camera, darkTheme, zoomIn, feedback, settings }

@immutable
class QuickSetting {
  const QuickSetting(this.kind, {this.enabled = true, this.supportsCamera = true});

  final QuickSettingKind kind;
  final bool enabled;
  final bool supportsCamera;

  String get semanticsLabel => switch (kind) {
    QuickSettingKind.brightness => 'Brightness',
    QuickSettingKind.volume => 'Volume',
    QuickSettingKind.camera => 'Camera',
    QuickSettingKind.darkTheme => 'Theme',
    QuickSettingKind.zoomIn => 'Digest',
    QuickSettingKind.feedback => 'Send feedback',
    QuickSettingKind.settings => 'Settings',
  };

  /// One line of explanation for the a11y tooltip, naming what will actually
  /// happen. A label that lies ("Camera") on a button that does nothing is the
  /// defect this whole row was rebuilt to remove.
  String get description => switch (kind) {
    QuickSettingKind.brightness => 'Dim or restore the screen',
    QuickSettingKind.volume => 'Mute or restore the volume',
    QuickSettingKind.camera => 'Open the camera',
    QuickSettingKind.darkTheme => 'Change the theme',
    QuickSettingKind.zoomIn => 'Open your digest',
    QuickSettingKind.feedback => 'Send feedback',
    QuickSettingKind.settings => 'Open device settings',
  };
}

const List<QuickSetting> kQuickSettings = [
  QuickSetting(QuickSettingKind.brightness),
  QuickSetting(QuickSettingKind.volume),
  QuickSetting(QuickSettingKind.camera),
  QuickSetting(QuickSettingKind.darkTheme),
  QuickSetting(QuickSettingKind.zoomIn),
  QuickSetting(QuickSettingKind.feedback),
  QuickSetting(QuickSettingKind.settings),
];

/// Quick re-colour of an [AmbientPalette] used by the bottom sheet so it always
/// stays legible over the current ambient background.
Color sheetFill(AmbientPalette p) => p.surface;