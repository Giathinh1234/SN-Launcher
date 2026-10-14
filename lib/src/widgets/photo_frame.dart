import 'package:flutter/material.dart';

import '../theme/ambient_palette.dart';
import '../theme/nest_metrics.dart';

/// The Photo Frame background — the Nest Hub's idle state.
///
/// The device shows a photograph with the clock and weather laid over it in
/// white, sitting on a soft dark scrim so the text stays legible whatever the
/// picture happens to contain. At night it dims the whole frame rather than
/// switching it off.
///
/// Memory matters more here than anywhere else in the app: decoding a
/// 1600x900 photograph straight to full size costs ~5 MB of bitmap on a device
/// that may only have a gigabyte to spare, and the home screen is on screen all
/// day. [cacheWidth] makes Skia decode straight to the on-screen size instead,
/// which is typically a quarter of that.
class PhotoFrameBackground extends StatelessWidget {
  const PhotoFrameBackground({
    super.key,
    required this.metrics,
    required this.palette,
    this.asset = 'assets/photo/landscape.jpg',
  });

  final NestMetrics metrics;
  final AmbientPalette palette;
  final String asset;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            asset,
            fit: BoxFit.cover,
            alignment: Alignment.center,
            // Decode at roughly what we will actually draw, not the file size.
            cacheWidth: (metrics.size.width * metrics.u * MediaQuery.devicePixelRatioOf(context))
                .round()
                .clamp(640, 2560),
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
            // A missing asset must not black out the launcher — fall through to
            // the flat ambient field instead.
            errorBuilder: (_, _, _) => ColoredBox(color: palette.bottom),
          ),

          // Legibility scrim: the device darkens the lower third so the clock
          // never fights the picture.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.18),
                  Colors.black.withValues(alpha: 0.62),
                ],
                stops: const [0.0, 0.45, 1.0],
              ),
            ),
          ),

          // Night dimming. The real Hub drops the photo's brightness rather
          // than blanking the screen.
          if (palette.isNight)
            ColoredBox(color: Colors.black.withValues(alpha: 0.28)),
        ],
      ),
    );
  }
}