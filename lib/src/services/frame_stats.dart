
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Live frame timing, fed by the engine's own [FrameTiming] callbacks.
///
/// This is the only trustworthy way to measure a Flutter app on a device:
/// `dumpsys gfxinfo` reports zero frames because Flutter bypasses Android's
/// HWUI pipeline entirely, and SurfaceFlinger cannot sample a `SurfaceView`
/// backed by BLAST buffers.
///
/// Off unless the app is built with `--dart-define=PERF_OVERLAY=true`, so it
/// costs nothing in a normal build.
class FrameStats {
  FrameStats() {
    // `addTimingsCallback` returns void; hold the callback so it can be
    // detached in dispose().
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  static const bool enabled = bool.fromEnvironment('PERF_OVERLAY');

  final List<FrameTiming> _recent = [];

  /// Busiest single frame seen since the last [reset].
  double worstFrameMs = 0;

  /// Frames that took longer than one 60 Hz frame budget.
  int jankCount = 0;

  double _frameCount = 0;

  /// Called roughly once a second by [_onTimings].
  VoidCallback? onSample;

  double get fps => _frameCount;
  double get averageFrameMs {
    if (_recent.isEmpty) return 0;
    var total = 0.0;
    for (final t in _recent) {
      total += t.buildDuration.inMicroseconds + t.rasterDuration.inMicroseconds;
    }
    return total / _recent.length / 1000.0;
  }

  void _onTimings(List<FrameTiming> timings) {
    if (timings.isEmpty) return;
    _recent.addAll(timings);
    if (_recent.length > 120) _recent.removeRange(0, _recent.length - 120);

    for (final t in timings) {
      final ms = (t.buildDuration.inMicroseconds + t.rasterDuration.inMicroseconds) / 1000.0;
      if (ms > worstFrameMs) worstFrameMs = ms;
      // 16.7 ms is the 60 Hz budget; anything over it is a dropped frame.
      if (ms > 16.7) jankCount++;
    }
    _frameCount += timings.length;

    // A new batch usually means at least one vsync elapsed.
    if (onSample != null) {
      onSample!();
      _frameCount = 0;
    }
  }

  void reset() {
    _recent.clear();
    _frameCount = 0;
    jankCount = 0;
    worstFrameMs = 0;
  }

  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
  }
}

/// Compact corner readout, so frame numbers can be read off a screenshot
/// without attaching a debugger.
class PerfOverlay extends StatefulWidget {
  const PerfOverlay({super.key, required this.stats});

  final FrameStats stats;

  @override
  State<PerfOverlay> createState() => _PerfOverlayState();
}

class _PerfOverlayState extends State<PerfOverlay> {
  int _tick = 0;

  @override
  void initState() {
    super.initState();
    widget.stats.onSample = () {
      if (mounted) setState(() => _tick++);
    };
  }

  @override
  void dispose() {
    widget.stats.onSample = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.stats;
    final avg = s.averageFrameMs;
    final fps = avg > 0 ? (1000 / avg).clamp(0, 999) : 0.0;
    final bad = avg > 16.7;

    return Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xB0000000),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '${fps.toStringAsFixed(0)} fps  ${avg.toStringAsFixed(1)}ms'
            '  worst ${s.worstFrameMs.toStringAsFixed(0)}ms'
            '  jank ${s.jankCount}  #$_tick',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: bad ? const Color(0xFFFF5252) : const Color(0xFF69F0AE),
            ),
          ),
        ),
      ),
    );
  }
}