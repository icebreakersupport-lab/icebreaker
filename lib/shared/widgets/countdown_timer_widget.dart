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

class _CountdownTimerWidgetState extends State<CountdownTimerWidget> {
  late int _remaining;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _remaining = widget.initialSeconds;
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_remaining <= 0) {
        _timer?.cancel();
        widget.onExpired?.call();
        return;
      }
      setState(() => _remaining--);
    });
  }

  @override
  void dispose() {
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
