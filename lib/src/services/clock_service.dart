import 'dart:async';

import 'package:flutter/foundation.dart';

/// Ticks the shell with wall-clock time.
///
/// Performance matters a lot here: the real device is an Amlogic S905D with
/// 1–2 GB of RAM, and a naive 1 Hz rebuild of the whole widget tree is a
/// visible waste. So:
///  * the clock exposes a [ValueNotifier] that only the clock widgets listen to
///  * by default it only wakes up on the *minute* boundary unless seconds are
///    being displayed
///  * updates are aligned to the wall clock so digits never visibly stutter
class ClockService extends ChangeNotifier {
  ClockService({this.showSeconds = false, this.autoTick = true}) {
    if (autoTick) _schedule();
  }

  /// When false the service never arms a timer and simply reports whatever
  /// [overrideForTesting] set. Golden/screenshot rendering depends on this: a
  /// self-rescheduling timer never lets the test's fake-async zone quiesce.
  final bool autoTick;

  /// Whether seconds are drawn on the big clock. Off by default: a
  /// minute-resolution clock lets the shell skip 59 of every 60 rebuilds.
  bool showSeconds;

  DateTime _now = DateTime.now();
  DateTime get now => _now;

  Timer? _timer;

  void setShowSeconds(bool value) {
    if (showSeconds == value) return;
    showSeconds = value;
    if (autoTick) _schedule();
    notifyListeners();
  }

  /// Manual override for testing / screenshot capture.
  @visibleForTesting
  void overrideForTesting(DateTime t) {
    _now = t;
    notifyListeners();
  }

  void _schedule() {
    _timer?.cancel();
    final now = DateTime.now();
    final step = showSeconds ? 1 : 60;
    // Align to the next boundary so the display flips exactly on the second /
    // minute rather than drifting.
    final remainder = now.millisecondsSinceEpoch % (step * 1000);
    final delay = Duration(milliseconds: step * 1000 - remainder);

    _timer = Timer(delay, () {
      _now = DateTime.now();
      notifyListeners();
      _schedule();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  static const List<String> _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June', //
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  static const List<String> _dayNames = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', //
    'Friday', 'Saturday', 'Sunday',
  ];

  /// The device renders the date as e.g. "Thu, May 26" — abbreviated weekday,
  /// abbreviated month, day of month.
  static String nestDate(DateTime t) {
    final dow = _dayNames[t.weekday - 1].substring(0, 3);
    final mon = _monthNames[t.month - 1].substring(0, 3);
    return '$dow, $mon ${t.day}';
  }

  static String longDate(DateTime t) =>
      '${_dayNames[t.weekday - 1]}, ${_monthNames[t.month - 1]} ${t.day}';

  /// 24-hour clock by default, matching the device's "Use 24-hour format"
  /// setting (on by default in most locales).
  static String time(DateTime t, {bool use24Hour = true, bool withSeconds = false}) {
    final h = use24Hour
        ? t.hour
        : (t.hour % 12 == 0 ? 12 : t.hour % 12);
    final mm = t.minute.toString().padLeft(2, '0');
    if (!withSeconds) {
      return '${use24Hour ? h.toString().padLeft(2, '0') : h.toString()}:$mm';
    }
    final ss = t.second.toString().padLeft(2, '0');
    return '${use24Hour ? h.toString().padLeft(2, '0') : h.toString()}:$mm:$ss';
  }

  static String meridiem(DateTime t) {
    if (t.hour < 12) return 'AM';
    return 'PM';
  }

  /// Greeting used by the "Your morning/afternoon/evening" pages.
  static String greeting(DateTime t) {
    final h = t.hour;
    if (h < 5) return 'Good night';
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    if (h < 22) return 'Good evening';
    return 'Good night';
  }
}