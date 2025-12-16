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

  @override
  void initState() {
    super.initState();
    _initializeTimer();
  }

  void _initializeTimer() {
    if (widget.isCheckedIn) {
      _timerService.startCheckInTimer(
        widget.employeeId,
        checkInTime: widget.checkInTimestamp,
      );

      // Listen to timer updates
      _timerService.timerStream.listen((event) {
        if (event.employeeId == widget.employeeId && mounted) {
          setState(() {
            _elapsedTime = event.elapsedTime;
          });
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
                  const Text(
                    'Time Since Check-In',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
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
          const Text(
            'Elapsed time since you checked in',
            style: TextStyle(fontSize: 10, color: timerColor),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
