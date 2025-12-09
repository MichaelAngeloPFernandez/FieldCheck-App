import 'package:flutter/material.dart';
import 'package:field_check/models/user_model.dart';
import 'package:field_check/widgets/workload_indicator_widget.dart';

class EmployeeTrackingCard extends StatelessWidget {
  final UserModel employee;
  final VoidCallback? onTap;
  final bool showLocation;

  const EmployeeTrackingCard({
    super.key,
    required this.employee,
    this.onTap,
    this.showLocation = true,
  });

  @override
  Widget build(BuildContext context) {
    final isOnline = employee.isOnline ?? false;
    final taskCount = employee.activeTaskCount ?? 0;
    final workload = employee.workloadWeight ?? 0.0;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with name and status
              Row(
                children: [
                  // Avatar
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: isOnline ? Colors.green : Colors.grey,
                    child: Text(
                      employee.name.isNotEmpty
                          ? employee.name[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Name and status
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          employee.name,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isOnline ? Colors.green : Colors.grey,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isOnline ? 'Online' : 'Offline',
                              style: TextStyle(
                                fontSize: 12,
                                color: isOnline ? Colors.green : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Workload indicator
                  WorkloadIndicatorWidget(
                    status: _getWorkloadStatus(taskCount, workload),
                    activeTaskCount: taskCount,
                    difficultyWeight: workload,
                    showDetails: false,
                    size: 28,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Location info
              if (showLocation && employee.lastLatitude != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.location_on,
                        size: 14,
                        color: Colors.blue,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '${employee.lastLatitude!.toStringAsFixed(4)}, ${employee.lastLongitude!.toStringAsFixed(4)}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              // Task info
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildInfoChip('Tasks', taskCount.toString()),
                  _buildInfoChip('Workload', workload.toStringAsFixed(1)),
                  if (employee.lastLocationUpdate != null)
                    _buildInfoChip(
                      'Updated',
                      _formatTime(employee.lastLocationUpdate!),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
      ),
    );
  }

  WorkloadStatus _getWorkloadStatus(int taskCount, double workload) {
    if (taskCount == 0) {
      return WorkloadStatus.free;
    } else if (workload > 10.0) {
      return WorkloadStatus.overloaded;
    } else if (taskCount > 5) {
      return WorkloadStatus.busy;
    } else {
      return WorkloadStatus.available;
    }
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inSeconds < 60) {
      return 'now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h';
    } else {
      return '${diff.inDays}d';
    }
  }
}
