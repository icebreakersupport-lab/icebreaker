import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

/// A live countdown display that ticks down from [initialSeconds].
///
/// Uses the display text style — intended for large urgency contexts
/// (Meetup find timer, conversation timer, icebreaker expiry).
///
/// When 30 seconds remain the colour transitions to [AppColors.warning].
/// When time expires [onExpired] is called once.
///
/// **Background-resilient by design.**  iOS / Android suspend Dart timers
/// when the app moves to the background, so a naive `Timer.periodic` that
/// decrements a local counter drifts every time the user locks their phone
/// — the 10-minute Meetup talk timer would still read "5:00" after the
/// user spent 5 minutes with the app backgrounded.  This widget instead
/// stores the absolute end time at mount and recomputes the remaining
/// seconds on every tick, AND on app resume via a [WidgetsBindingObserver]
/// — so the display jumps to the correct value the instant the user
/// returns.  If the timer expired while in background, [onExpired] fires
/// on the next foreground tick.
class CountdownTimerWidget extends StatefulWidget {
  const CountdownTimerWidget({
    super.key,
    required this.initialSeconds,
    this.onExpired,
    this.style,
    this.warningThresholdSeconds = 30,
  });

  final int initialSeconds;
  final VoidCallback? onExpired;

  /// Override the text style. Defaults to [AppTextStyles.display].
  final TextStyle? style;

  /// Seconds remaining at which the timer text turns [AppColors.warning].
  final int warningThresholdSeconds;

  @override
  State<CountdownTimerWidget> createState() => _CountdownTimerWidgetState();
}

class _CountdownTimerWidgetState extends State<CountdownTimerWidget>
    with WidgetsBindingObserver {
  /// Absolute moment the timer hits zero.  All "remaining seconds" reads
  /// derive from `_endTime - DateTime.now()`, so suspended-app drift is
  /// impossible — the worst case is the UI text lags by up to one tick
  /// (corrected on the next 1 s tick or on app resume).
  late DateTime _endTime;
  late int _remaining;
  Timer? _timer;
  bool _expiredFired = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _endTime = DateTime.now().add(Duration(seconds: widget.initialSeconds));
    _remaining = widget.initialSeconds;
    _startTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // App returning from background or inactive → recompute immediately so
    // the display jumps to the correct value instead of waiting up to a
    // full second for the next periodic tick.
    if (state == AppLifecycleState.resumed) {
      _tick();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  /// Single source of truth — derives [_remaining] from the absolute end
  /// time.  Fires [widget.onExpired] exactly once when the timer reaches 0
  /// (or comes back already past 0 after backgrounding).
  void _tick() {
    if (!mounted) return;
    final remaining =
        _endTime.difference(DateTime.now()).inSeconds.clamp(0, 1 << 30);
    if (remaining <= 0) {
      _timer?.cancel();
      if (_remaining != 0) {
        setState(() => _remaining = 0);
      }
      if (!_expiredFired) {
        _expiredFired = true;
        widget.onExpired?.call();
      }
      return;
    }
    if (remaining != _remaining) {
      setState(() => _remaining = remaining);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  String get _formatted {
    final m = _remaining ~/ 60;
    final s = _remaining % 60;
    return '${m.toString().padLeft(1, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isWarning = _remaining <= widget.warningThresholdSeconds;
    final baseStyle = widget.style ?? AppTextStyles.display;
    final color = isWarning ? AppColors.warning : AppColors.textPrimary;

    return AnimatedDefaultTextStyle(
      duration: const Duration(milliseconds: 300),
      style: baseStyle.copyWith(color: color),
      child: Text(_formatted),
    );
  }
}
