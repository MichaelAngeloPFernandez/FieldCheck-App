import 'package:flutter/material.dart';
import '../services/employee_location_service.dart';
import 'employee_details_modal.dart';

class LiveEmployeeMap extends StatefulWidget {
  final List<EmployeeLocation> employees;
  final Function(String, EmployeeStatus)? onStatusChange;
  final VoidCallback? onRefresh;
  final double height;

  const LiveEmployeeMap({
    super.key,
    required this.employees,
    this.onStatusChange,
    this.onRefresh,
    this.height = 400,
  });

  @override
  State<LiveEmployeeMap> createState() => _LiveEmployeeMapState();
}

class _LiveEmployeeMapState extends State<LiveEmployeeMap> {
  final Map<String, List<Map<String, dynamic>>> _trails = {};
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _initializeTrails();
  }

  void _initializeTrails() {
    for (final employee in widget.employees) {
      _trails[employee.employeeId] = [
        {
          'lat': employee.latitude,
          'lng': employee.longitude,
          'timestamp': employee.timestamp,
        },
      ];
    }
  }

  @override
  void didUpdateWidget(LiveEmployeeMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateTrails();
  }

  void _updateTrails() {
    for (final employee in widget.employees) {
      final key = employee.employeeId;
      if (!_trails.containsKey(key)) {
        _trails[key] = [];
      }

      final currentTrail = _trails[key]!;
      final newPoint = {
        'lat': employee.latitude,
        'lng': employee.longitude,
        'timestamp': employee.timestamp,
      };

      // Only add if position changed
      if (currentTrail.isEmpty ||
          currentTrail.last['lat'] != newPoint['lat'] ||
          currentTrail.last['lng'] != newPoint['lng']) {
        currentTrail.add(newPoint);

        // Keep trail size manageable (max 50 points per employee)
        if (currentTrail.length > 50) {
          currentTrail.removeAt(0);
        }
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    if (widget.employees.isEmpty) {
      return Container(
        height: widget.height,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.location_off,
                size: 48,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.55),
              ),
              const SizedBox(height: 16),
              Text(
                'No employees online',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: onSurface.withValues(alpha: 0.82),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.35),
        ),
      ),
      child: Stack(
        children: [
          // Map visualization (grid-based)
          _buildMapVisualization(),
          // Top controls
          Positioned(
            top: 12,
            right: 12,
            child: Column(
              children: [
                FloatingActionButton.small(
                  onPressed: widget.onRefresh,
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  child: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          // Legend
          Positioned(
            bottom: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.12),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildLegendItem('🟢', 'Available / Standby', Colors.green),
                  _buildLegendItem('🔵', 'Moving / On the go', Colors.blue),
                  _buildLegendItem('🔴', 'Busy', Colors.red),
                  _buildLegendItem('⚫', 'Offline', Colors.grey),
                ],
              ),
            ),
          ),
          // Employee count
          Positioned(
            top: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.12),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.people,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${widget.employees.length} Online',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: onSurface.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapVisualization() {
    // Create a grid-based visualization of employee locations
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: SingleChildScrollView(
        controller: _scrollController,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Employee Locations',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              // Grid of employee location cards
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 1.5,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: widget.employees.length,
                itemBuilder: (context, index) {
                  final employee = widget.employees[index];
                  return _buildEmployeeLocationCard(employee);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmployeeLocationCard(EmployeeLocation employee) {
    final statusColor = _getStatusColor(employee.status);
    final statusIcon = _getStatusIcon(employee.status);
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final displayName =
        (employee.username != null && employee.username!.trim().isNotEmpty)
        ? employee.username!.trim()
        : employee.name;

    return GestureDetector(
      onTap: () => _showEmployeeDetails(employee),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: statusColor.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.08),
              blurRadius: 2,
            ),
          ],
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with status
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    displayName,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: onSurface.withValues(alpha: 0.9),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Location info
            Row(
              children: [
                Icon(
                  Icons.location_on,
                  size: 14,
                  color: onSurface.withValues(alpha: 0.65),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '${employee.latitude.toStringAsFixed(4)}, ${employee.longitude.toStringAsFixed(4)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: onSurface.withValues(alpha: 0.7),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Status and tasks
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(statusIcon, size: 14, color: statusColor),
                    const SizedBox(width: 4),
                    Text(
                      _getStatusLabel(employee.status),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${employee.activeTaskCount} tasks',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(String emoji, String label, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.82),
            ),
          ),
        ],
      ),
    );
  }

  void _showEmployeeDetails(EmployeeLocation employee) {
    showDialog(
      context: context,
      builder: (context) => EmployeeDetailsModal(
        employee: employee,
        locationHistory: [],
        onReassignTasks: () {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Task reassignment coming soon')),
          );
        },
        onStatusChange: (newStatus) {
          widget.onStatusChange?.call(employee.employeeId, newStatus);
        },
        onSendMessage: () {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Messaging coming soon')),
          );
        },
        onViewReports: () {
          Navigator.pop(context);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Reports coming soon')));
        },
      ),
    );
  }

  Color _getStatusColor(EmployeeStatus status) {
    switch (status) {
      case EmployeeStatus.available:
        return Colors.green;
      case EmployeeStatus.moving:
        return Colors.blue;
      case EmployeeStatus.busy:
        return Colors.red;
      case EmployeeStatus.offline:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(EmployeeStatus status) {
    switch (status) {
      case EmployeeStatus.available:
        return Icons.check_circle;
      case EmployeeStatus.moving:
        return Icons.directions_run;
      case EmployeeStatus.busy:
        return Icons.schedule;
      case EmployeeStatus.offline:
        return Icons.cloud_off;
    }
  }

  String _getStatusLabel(EmployeeStatus status) {
    switch (status) {
      case EmployeeStatus.available:
        return 'Available';
      case EmployeeStatus.moving:
        return 'Moving';
      case EmployeeStatus.busy:
        return 'Busy';
      case EmployeeStatus.offline:
        return 'Offline';
    }
  }
}
