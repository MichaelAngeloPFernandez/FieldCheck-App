import 'dart:async';
import 'package:flutter/material.dart';
import 'package:field_check/services/checkin_timer_service.dart';

class CheckInTimerWidget extends StatefulWidget {
  final String employeeId;
  final bool isCheckedIn;
  final DateTime? checkInTimestamp;

  const CheckInTimerWidget({
    super.key,
    required this.employeeId,
    required this.isCheckedIn,
    this.checkInTimestamp,
  });

  @override
  State<CheckInTimerWidget> createState() => _CheckInTimerWidgetState();
}

class _CheckInTimerWidgetState extends State<CheckInTimerWidget> {
  final CheckInTimerService _timerService = CheckInTimerService();
  Duration _elapsedTime = Duration.zero;
  StreamSubscription<CheckInTimerEvent>? _subscription;
  String? _activeEmployeeId;

  @override
  void initState() {
    super.initState();
    _initializeTimer();
  }

  void _initializeTimer() {
    _subscription?.cancel();

    if (_activeEmployeeId != null) {
      _timerService.stopCheckInTimer(_activeEmployeeId!);
      _activeEmployeeId = null;
    }

    if (!widget.isCheckedIn) {
      _elapsedTime = Duration.zero;
      return;
    }

    _activeEmployeeId = widget.employeeId;

    // Always start timer from the provided checkInTimestamp
    // This ensures timer resets to 0 on each new check-in
    _timerService.startCheckInTimer(
      _activeEmployeeId!,
      checkInTime: widget.checkInTimestamp,
    );

    _subscription = _timerService.timerStream.listen((event) {
      if (!mounted) return;
      if (event.employeeId != _activeEmployeeId) return;
      setState(() {
        _elapsedTime = event.elapsedTime;
      });
    });
  }

  @override
  void didUpdateWidget(CheckInTimerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bool checkInStateChanged =
        widget.isCheckedIn != oldWidget.isCheckedIn;
    final bool employeeChanged = widget.employeeId != oldWidget.employeeId;
    final bool timestampChanged =
        widget.checkInTimestamp != oldWidget.checkInTimestamp;

    if (checkInStateChanged || employeeChanged || timestampChanged) {
      _initializeTimer();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    if (_activeEmployeeId != null) {
      _timerService.stopCheckInTimer(_activeEmployeeId!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isCheckedIn) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    final timerText = CheckInTimerService.formatDuration(_elapsedTime);
    const Color timerColor = Colors.green;

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
                  Text(
                    'Time Since Check-In',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: timerColor,
                    ),
                  ),
                ],
              ),
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
            'Elapsed time since you checked in',
            style: theme.textTheme.bodySmall?.copyWith(
              color: timerColor,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
