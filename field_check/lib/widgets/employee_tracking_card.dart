import 'package:flutter/material.dart';
import 'package:field_check/models/user_model.dart';
import 'package:field_check/widgets/workload_indicator_widget.dart';
import 'package:field_check/config/api_config.dart';

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
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final isOnline = employee.isOnline ?? false;
    final taskCount = employee.activeTaskCount ?? 0;
    final workload = employee.workloadWeight ?? 0.0;

    final rawAvatar = employee.avatarUrl?.trim() ?? '';
    final hasAvatar = rawAvatar.isNotEmpty;
    final avatarUrl = !hasAvatar
        ? ''
        : (rawAvatar.startsWith('http://') || rawAvatar.startsWith('https://'))
        ? rawAvatar
        : rawAvatar.startsWith('/')
        ? '${ApiConfig.baseUrl}$rawAvatar'
        : '${ApiConfig.baseUrl}/$rawAvatar';

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
                    backgroundImage: hasAvatar ? NetworkImage(avatarUrl) : null,
                    child: hasAvatar
                        ? null
                        : Text(
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
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: onSurface.withValues(alpha: 0.9),
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
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: isOnline
                                    ? Colors.green
                                    : onSurface.withValues(alpha: 0.65),
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
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: onSurface.withValues(alpha: 0.72),
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
                  _buildInfoChip(context, 'Tasks', taskCount.toString()),
                  _buildInfoChip(
                    context,
                    'Workload',
                    workload.toStringAsFixed(1),
                  ),
                  if (employee.lastLocationUpdate != null)
                    _buildInfoChip(
                      context,
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

  Widget _buildInfoChip(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: onSurface.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$label: $value',
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: onSurface.withValues(alpha: 0.82),
        ),
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
