import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sn_launcher/src/theme/nest_icons.dart';

void main() {
  // flutter_test renders text with Ahem (a font of solid boxes) unless the
  // real font is loaded by hand. Without this the probe below would show a
  // grid of squares and would happily "pass" while proving nothing.
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final loader = FontLoader('MaterialSymbolsRounded')
      ..addFont(rootBundle.load('assets/fonts/MaterialSymbolsRounded.ttf'));
    await loader.load();
  });

  testWidgets('material symbols render the right shapes', (tester) async {
    // The names here double as labels under each glyph, so the contact sheet
    // is self-checking: if brightness_7 renders as a rain cloud, you can see it.
    const probe = <String, IconData>{
      'brightness_7': NestIcons.Brightness7,
      'volume_up': NestIcons.VolumeUp,
      'photo_camera': NestIcons.PhotoCamera,
      'dark_mode': NestIcons.DarkMode,
      'light_mode': NestIcons.LightMode,
      'calendar_month': NestIcons.CalendarMonth,
      'cloud': NestIcons.Cloud,
      'wb_sunny': NestIcons.WbSunny,
      'settings': NestIcons.Settings,
      'zoom_in': NestIcons.ZoomIn,
      'feedback': NestIcons.Feedback,
      'info': NestIcons.Info,
      'add': NestIcons.Add,
      'remove': NestIcons.Remove,
      'close': NestIcons.Close,
      'check': NestIcons.Check,
      'chevron_right': NestIcons.ChevronRight,
      'wifi': NestIcons.Wifi,
      'nightlight': NestIcons.Nightlight,
      'star': NestIcons.Star,
      'favorite': NestIcons.Favorite,
      'search': NestIcons.Search,
      'refresh': NestIcons.Refresh,
      'today': NestIcons.Today,
      'map': NestIcons.Map,
      'location_on': NestIcons.LocationOn,
      'home': NestIcons.Home,
      'sports_esports': NestIcons.SportsEsports,
      'videocam': NestIcons.Videocam,
      'cast': NestIcons.Cast,
      'music_note': NestIcons.MusicNote,
      'podcasts': NestIcons.Podcasts,
      'news': NestIcons.News,
      'person': NestIcons.Person,
      'access_time': NestIcons.AccessTime,
      'landscape': NestIcons.Landscape,
      'play_arrow': NestIcons.PlayArrow,
      'mic': NestIcons.Mic,
      'palette': NestIcons.Palette,
      'bolt': NestIcons.Bolt,
      'grid_view': NestIcons.GridView,
      'tv': NestIcons.Tv,
    };

    const cell = 78.0;
    const cols = 8;
    await tester.pumpWidget(MaterialApp(
      home: RepaintBoundary(
        key: const Key('probe'),
        child: ColoredBox(
        color: Colors.white,
        child: SizedBox(
          width: cell * cols,
          height: cell * 6,
          child: Wrap(
            children: [
              for (final e in probe.entries)
                SizedBox(
                  width: cell,
                  height: cell,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(e.value, size: 44, color: Colors.black),
                      Text(e.key,
                          style: const TextStyle(fontSize: 7, color: Colors.black)),
                    ],
                  ),
                ),
            ],
          ),
        ),
        ),
      ),
    ));
    await tester.runAsync(() async {
      final el = find.byKey(const Key('probe'));
      final boundary = el.evaluate().first.renderObject! as dynamic;
      final img = await boundary.toImage(pixelRatio: 1.6);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      File('/tmp/icons_probe.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  });
}
