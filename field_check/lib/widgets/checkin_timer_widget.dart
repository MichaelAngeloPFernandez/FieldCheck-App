import 'package:flutter/material.dart';
import 'package:field_check/services/checkin_timer_service.dart';

class CheckInTimerWidget extends StatefulWidget {
  final String employeeId;
  final bool isCheckedIn;
  final Duration? customTimeout;
  final Function(String employeeId)? onTimerExpired;

  const CheckInTimerWidget({
    super.key,
    required this.employeeId,
    required this.isCheckedIn,
    this.customTimeout,
    this.onTimerExpired,
  });

  @override
  State<CheckInTimerWidget> createState() => _CheckInTimerWidgetState();
}

class _CheckInTimerWidgetState extends State<CheckInTimerWidget> {
  final CheckInTimerService _timerService = CheckInTimerService();
  Duration _remainingTime = Duration.zero;

  @override
  void initState() {
    super.initState();
    _initializeTimer();
  }

  void _initializeTimer() {
    if (widget.isCheckedIn) {
      _timerService.startCheckInTimer(
        widget.employeeId,
        customTimeout: widget.customTimeout,
      );

      // Listen to timer updates
      _timerService.timerStream.listen((event) {
        if (event.employeeId == widget.employeeId && mounted) {
          setState(() {
            _remainingTime = event.remainingTime;
          });
        }
      });

      // Listen to expiration
      _timerService.expirationStream.listen((employeeId) {
        if (employeeId == widget.employeeId) {
          widget.onTimerExpired?.call(employeeId);
          if (mounted) {
            _showExpirationDialog();
          }
        }
      });
    }
  }

  @override
  void didUpdateWidget(CheckInTimerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isCheckedIn && !oldWidget.isCheckedIn) {
      _initializeTimer();
    } else if (!widget.isCheckedIn && oldWidget.isCheckedIn) {
      _timerService.stopCheckInTimer(widget.employeeId);
    }
  }

  void _showExpirationDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Check-In Timer Expired'),
        content: const Text(
          'The check-in timer has expired. Your attendance has been marked as incomplete. '
          'Please check out or contact your administrator.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _timerService.stopCheckInTimer(widget.employeeId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isCheckedIn) {
      return const SizedBox.shrink();
    }

    final timerText = CheckInTimerService.formatDuration(_remainingTime);
    final isWarning = _remainingTime.inMinutes < 30;
    final isExpired = _remainingTime.inSeconds <= 0;

    Color timerColor;
    if (isExpired) {
      timerColor = Colors.red;
    } else if (isWarning) {
      timerColor = Colors.orange;
    } else {
      timerColor = Colors.green;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: timerColor.withValues(alpha: 0.1),
        border: Border.all(color: timerColor, width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.timer, color: timerColor, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'Check-In Timer',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              if (isWarning && !isExpired)
                const Icon(Icons.warning, color: Colors.orange, size: 16),
              if (isExpired)
                const Icon(Icons.error, color: Colors.red, size: 16),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            timerText,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: timerColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            isExpired
                ? 'Timer Expired - Attendance Incomplete'
                : isWarning
                ? 'Warning: Less than 30 minutes remaining'
                : 'Time remaining for check-out',
            style: TextStyle(fontSize: 10, color: timerColor),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
