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
          Image(
            // Decode at exactly what we will draw — the panel's physical width
            // — but never wider than the file actually is.
            //
            // `metrics.size` is already in logical px; multiplying by
            // `metrics.u` as well double-counts the design scale and
            // over-allocates by that factor. And `allowUpscaling: false` stops
            // it going further: this asset is 1600px wide on a 2000px panel,
            // so decoding at 2000 would spend ~3 MB of extra bitmap on detail
            // that does not exist. `ResizeImage` knows the intrinsic size, so
            // letting it clamp is more robust than hardcoding the dimensions —
            // swap the photo for a 4K one and it still does the right thing.
            image: ResizeImage(
              AssetImage(asset),
              width: (metrics.size.width * MediaQuery.devicePixelRatioOf(context))
                  .round()
                  .clamp(640, 4096),
              // allowUpscaling defaults to false, which is the behaviour we
              // want; stated here because relying on a default for a memory
              // decision is how the 3MB regression above happened.
              allowUpscaling: false,
            ),
            fit: BoxFit.cover,
            alignment: Alignment.center,
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