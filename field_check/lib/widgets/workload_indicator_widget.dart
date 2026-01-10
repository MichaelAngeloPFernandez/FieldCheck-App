import 'package:flutter/material.dart';

enum WorkloadStatus { free, available, busy, overloaded, overdue }

class WorkloadIndicatorWidget extends StatelessWidget {
  final WorkloadStatus status;
  final int activeTaskCount;
  final double difficultyWeight;
  final int overdueCount;
  final bool showDetails;
  final double size;

  const WorkloadIndicatorWidget({
    super.key,
    required this.status,
    required this.activeTaskCount,
    required this.difficultyWeight,
    this.overdueCount = 0,
    this.showDetails = true,
    this.size = 24.0,
  });

  @override
  Widget build(BuildContext context) {
    final color = _getStatusColor();
    final icon = _getStatusIcon();
    final label = _getStatusLabel();

    if (!showDetails) {
      return Tooltip(
        message: label,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.2),
            border: Border.all(color: color, width: 2),
          ),
          child: Icon(icon, color: color, size: size * 0.6),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color, width: 1.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: color,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailChip(context, 'Tasks', activeTaskCount.toString()),
              const SizedBox(width: 8),
              _buildDetailChip(
                context,
                'Weight',
                difficultyWeight.toStringAsFixed(1),
              ),
              if (overdueCount > 0) ...[
                const SizedBox(width: 8),
                _buildDetailChip(
                  context,
                  'Overdue',
                  overdueCount.toString(),
                  isAlert: true,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailChip(
    BuildContext context,
    String label,
    String value, {
    bool isAlert = false,
  }) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isAlert
            ? Colors.red.withValues(alpha: 0.2)
            : onSurface.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$label: $value',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: isAlert ? Colors.red : onSurface.withValues(alpha: 0.78),
        ),
      ),
    );
  }

  Color _getStatusColor() {
    switch (status) {
      case WorkloadStatus.overdue:
        return Colors.red;
      case WorkloadStatus.overloaded:
        return Colors.deepOrange;
      case WorkloadStatus.busy:
        return Colors.orange;
      case WorkloadStatus.available:
        return Colors.green;
      case WorkloadStatus.free:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon() {
    switch (status) {
      case WorkloadStatus.overdue:
        return Icons.error;
      case WorkloadStatus.overloaded:
        return Icons.warning;
      case WorkloadStatus.busy:
        return Icons.schedule;
      case WorkloadStatus.available:
        return Icons.check_circle;
      case WorkloadStatus.free:
        return Icons.sentiment_satisfied;
    }
  }

  String _getStatusLabel() {
    switch (status) {
      case WorkloadStatus.overdue:
        return 'Overdue';
      case WorkloadStatus.overloaded:
        return 'Overloaded';
      case WorkloadStatus.busy:
        return 'Busy';
      case WorkloadStatus.available:
        return 'Available';
      case WorkloadStatus.free:
        return 'Free';
    }
  }
}
