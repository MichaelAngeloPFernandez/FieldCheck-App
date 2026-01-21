import 'package:flutter/material.dart';
import '../services/employee_location_service.dart';
import '../screens/admin_reports_screen.dart';
import '../screens/admin_employee_history_screen.dart';
import 'employee_details_modal.dart';
import 'admin_actions_modal.dart';

class EmployeeStatusView extends StatefulWidget {
  final List<EmployeeLocation> employees;
  final Function(String, EmployeeStatus)? onStatusChange;
  final VoidCallback? onRefresh;

  const EmployeeStatusView({
    super.key,
    required this.employees,
    this.onStatusChange,
    this.onRefresh,
  });

  @override
  State<EmployeeStatusView> createState() => _EmployeeStatusViewState();
}

class _EmployeeStatusViewState extends State<EmployeeStatusView> {
  late List<EmployeeLocation> _filteredEmployees;
  String _selectedFilter = 'all'; // all, online, offline, busy, available

  @override
  void initState() {
    super.initState();
    _applyFilter();
  }

  @override
  void didUpdateWidget(EmployeeStatusView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _applyFilter();
  }

  void _applyFilter() {
    _filteredEmployees = widget.employees.where((emp) {
      switch (_selectedFilter) {
        case 'online':
          return emp.isOnline;
        case 'offline':
          return !emp.isOnline;
        case 'busy':
          return emp.status == EmployeeStatus.busy;
        case 'available':
          return emp.status == EmployeeStatus.available;
        default:
          return true;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    return Column(
      children: [
        // Filter chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _buildFilterChip('All', 'all'),
                const SizedBox(width: 8),
                _buildFilterChip('Online', 'online'),
                const SizedBox(width: 8),
                _buildFilterChip('Offline', 'offline'),
                const SizedBox(width: 8),
                _buildFilterChip('Busy', 'busy'),
                const SizedBox(width: 8),
                _buildFilterChip('Available', 'available'),
              ],
            ),
          ),
        ),
        // Employee list
        Expanded(
          child: _filteredEmployees.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.person_off,
                        size: 48,
                        color: onSurface.withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No employees found',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: onSurface.withValues(alpha: 0.75),
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _filteredEmployees.length,
                  itemBuilder: (context, index) {
                    final employee = _filteredEmployees[index];
                    return _buildEmployeeCard(context, employee);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _selectedFilter == value;
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _selectedFilter = value;
          _applyFilter();
        });
      },
      backgroundColor: theme.colorScheme.surface,
      selectedColor: Colors.blue[300],
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : onSurface.withValues(alpha: 0.9),
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildEmployeeCard(BuildContext context, EmployeeLocation employee) {
    final statusColor = _getStatusColor(employee.status);
    final statusIcon = _getStatusIcon(employee.status);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                // Status indicator
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                // Employee info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        employee.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(statusIcon, size: 14, color: statusColor),
                          const SizedBox(width: 4),
                          Text(
                            _getStatusLabel(employee.status),
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  color: statusColor,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(width: 12),
                          if (!employee.isOnline)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red[100],
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Offline',
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(
                                      color: Colors.red,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Details button
                ElevatedButton.icon(
                  onPressed: () => _showEmployeeDetails(context, employee),
                  icon: const Icon(Icons.info, size: 16),
                  label: const Text('Details'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Quick info row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildQuickInfo(
                  context,
                  'Tasks',
                  employee.activeTaskCount.toString(),
                  Icons.task_alt,
                ),
                _buildQuickInfo(
                  context,
                  'Workload',
                  '${(employee.workloadScore * 100).toStringAsFixed(0)}%',
                  Icons.trending_up,
                ),
                if (employee.currentGeofence != null)
                  _buildQuickInfo(
                    context,
                    'Location',
                    employee.currentGeofence!,
                    Icons.location_on,
                  ),
                if (employee.distanceToNearestTask != null)
                  _buildQuickInfo(
                    context,
                    'Distance',
                    '${employee.distanceToNearestTask!.toStringAsFixed(0)}m',
                    Icons.straighten,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickInfo(
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) {
    return Row(
      children: [
        Icon(
          icon,
          size: 14,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
        ),
        const SizedBox(width: 4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ],
    );
  }

  void _showEmployeeDetails(BuildContext context, EmployeeLocation employee) {
    showDialog(
      context: context,
      builder: (context) => EmployeeDetailsModal(
        employee: employee,
        locationHistory: [], // Location history from service
        onReassignTasks: () {
          // Open admin actions modal for task reassignment
          Navigator.pop(context);
          showDialog(
            context: context,
            builder: (context) => AdminActionsModal(
              employeeId: employee.employeeId,
              employeeName: employee.name,
              onActionComplete: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Task reassignment completed')),
                );
              },
            ),
          );
        },
        onStatusChange: (newStatus) {
          widget.onStatusChange?.call(employee.employeeId, newStatus);
        },
        onSendMessage: () {
          // Open admin actions modal for messaging
          Navigator.pop(context);
          showDialog(
            context: context,
            builder: (context) => AdminActionsModal(
              employeeId: employee.employeeId,
              employeeName: employee.name,
              onActionComplete: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Message sent successfully')),
                );
              },
            ),
          );
        },
        onViewReports: () {
          // Navigate to reports screen with employee filter
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  AdminReportsScreen(employeeId: employee.employeeId),
            ),
          );
        },
        onViewHistory: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AdminEmployeeHistoryScreen(
                employeeId: employee.employeeId,
                employeeName: employee.name,
              ),
            ),
          );
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
        return 'Checked In';
      case EmployeeStatus.moving:
        return 'Online';
      case EmployeeStatus.busy:
        return 'Busy';
      case EmployeeStatus.offline:
        return 'Offline';
    }
  }
}
