import 'dart:async';

import 'package:flutter/foundation.dart';

import 'platform_bridge.dart';

/// The calendar feed shown on the Digest page and on the home screen.
///
/// Kept deliberately dumb: it holds the latest list, refreshes on a timer and
/// a resume, and never blocks the UI. A launcher must paint in 0.8s even if the
/// calendar provider is slow or the user declined the permission — so every
/// failure leaves [events] empty and [available] false rather than throwing.
class CalendarService extends ChangeNotifier {
  CalendarService({this.bridge = const PlatformBridge()});

  final PlatformBridge bridge;

  List<CalendarEvent> _events = const [];
  List<CalendarEvent> get events => _events;

  bool _available = false;
  /// Whether the platform gave us permission and any calendar at all.
  bool get available => _available;

  bool _loading = false;
  bool get loading => _loading;

  bool _asked = false;

  Timer? _timer;
  bool _disposed = false;

  /// Ask once, then start polling. Safe to call repeatedly.
  Future<void> start() async {
    if (_asked) return;
    _asked = true;

    if (!await _ensurePermission()) return;

    await refresh();
    // Five minutes is the Nest's own cadence and is enough for a wall display;
    // faster just burns battery on a device that is on all day.
    _timer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => refresh(),
    );
  }

  Future<bool> _ensurePermission() async {
    try {
      final granted = await bridge.requestPermission('calendar');
      if (granted == null) {
        // No permission model on this platform — not an error, just no data.
        return false;
      }
      if (granted) return true;
      debugPrint('CalendarService: calendar permission declined');
      return false;
    } catch (e) {
      debugPrint('CalendarService: permission request failed: $e');
      return false;
    }
  }

  Future<void> refresh() async {
    if (_loading || _disposed) return;
    _loading = true;
    try {
      final next = await bridge.upcomingEvents(
        limit: 8,
        from: DateTime.now(),
      );
      if (_disposed) return;
      _events = next;
      _available = true;
      debugPrint('CalendarService: ${next.length} upcoming -> '
          '${next.take(4).map((e) => "${e.start.toIso8601String()} ${e.title}").join(" | ")}');
    } catch (e) {
      debugPrint('CalendarService: refresh failed: $e');
    } finally {
      _loading = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// The next event that has not finished yet, if any.
  ///
  /// The list arrives already ordered by start time, so this is a walk until
  /// something is still live. An event with no end time counts as still live —
  /// better to show an all-day event than to hide one that has no DTEND.
  CalendarEvent? get next {
    final now = DateTime.now();
    for (final e in _events) {
      final end = e.end;
      if (end != null && end.isBefore(now)) continue;
      return e;
    }
    return null;
  }

  /// Everything left today, for the "Today" card.
  List<CalendarEvent> get today {
    final end = DateTime.now().add(const Duration(hours: 24));
    return _events.where((e) => e.start.isBefore(end)).toList();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}