import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/employee_location_service.dart';
import 'admin_actions_modal.dart';

class EmployeeDetailsModal extends StatefulWidget {
  final EmployeeLocation employee;
  final List<EmployeeLocation> locationHistory;
  final VoidCallback? onReassignTasks;
  final Function(EmployeeStatus)? onStatusChange;
  final VoidCallback? onSendMessage;
  final VoidCallback? onViewReports;
  final VoidCallback? onViewHistory;

  const EmployeeDetailsModal({
    super.key,
    required this.employee,
    required this.locationHistory,
    this.onReassignTasks,
    this.onStatusChange,
    this.onSendMessage,
    this.onViewReports,
    this.onViewHistory,
  });

  @override
  State<EmployeeDetailsModal> createState() => _EmployeeDetailsModalState();
}

class _EmployeeDetailsModalState extends State<EmployeeDetailsModal> {
  late EmployeeStatus _selectedStatus;

  @override
  void initState() {
    super.initState();
    _selectedStatus = widget.employee.status;
  }

  @override
  Widget build(BuildContext context) {
    final employee = widget.employee;
    final statusColor = _getStatusColor(employee.status);
    final statusLabel = _getStatusLabel(employee.status);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with employee info
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [statusColor.withValues(alpha: 0.8), statusColor],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              employee.name,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'ID: ${employee.employeeId}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Status badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white, width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          statusLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Body content
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Employee Status Card (Prominent)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _getStatusColor(
                        employee.status,
                      ).withValues(alpha: 0.1),
                      border: Border.all(
                        color: _getStatusColor(employee.status),
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'Employee Presence Status',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _getStatusColor(
                              employee.status,
                            ).withValues(alpha: 0.2),
                            border: Border.all(
                              color: _getStatusColor(employee.status),
                              width: 2,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              _getStatusEmoji(employee.status),
                              style: const TextStyle(fontSize: 28),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          statusLabel,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Location section
                  _buildSection('Current Location', [
                    _buildInfoRow(
                      'Coordinates',
                      '${employee.latitude.toStringAsFixed(6)}, ${employee.longitude.toStringAsFixed(6)}',
                      Icons.location_on,
                    ),
                    _buildInfoRow(
                      'Accuracy',
                      '${employee.accuracy.toStringAsFixed(1)}m',
                      Icons.my_location,
                    ),
                    if (employee.currentGeofence != null)
                      _buildInfoRow(
                        'Geofence',
                        employee.currentGeofence!,
                        Icons.fence,
                      ),
                  ]),
                  const SizedBox(height: 20),
                  // Status section
                  _buildSection('Status & Activity', [
                    _buildInfoRow(
                      'Online Status',
                      employee.isOnline ? 'Online' : 'Offline',
                      employee.isOnline ? Icons.cloud_done : Icons.cloud_off,
                      color: employee.isOnline ? Colors.green : Colors.red,
                    ),
                    _buildInfoRow(
                      'Active Tasks',
                      employee.activeTaskCount.toString(),
                      Icons.task_alt,
                    ),
                    _buildInfoRow(
                      'Workload Score',
                      '${(employee.workloadScore * 100).toStringAsFixed(0)}%',
                      Icons.trending_up,
                    ),
                    if (employee.speed != null)
                      _buildInfoRow(
                        'Speed',
                        '${(employee.speed! * 3.6).toStringAsFixed(1)} km/h',
                        Icons.speed,
                      ),
                    if (employee.batteryLevel != null)
                      _buildInfoRow(
                        'Battery',
                        '${employee.batteryLevel}%',
                        Icons.battery_full,
                      ),
                  ]),
                  const SizedBox(height: 20),
                  // Movement history
                  if (widget.locationHistory.isNotEmpty)
                    _buildSection(
                      'Movement History (Last ${widget.locationHistory.length} updates)',
                      [
                        SizedBox(
                          height: 150,
                          child: ListView.builder(
                            itemCount: widget.locationHistory.length,
                            itemBuilder: (context, index) {
                              final loc = widget.locationHistory[index];
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      DateFormat(
                                        'HH:mm:ss',
                                      ).format(loc.timestamp),
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    Text(
                                      '${loc.latitude.toStringAsFixed(4)}, ${loc.longitude.toStringAsFixed(4)}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 20),
                  // Status change dropdown
                  _buildSection('Change Status', [
                    DropdownButton<EmployeeStatus>(
                      value: _selectedStatus,
                      isExpanded: true,
                      items: EmployeeStatus.values.map((status) {
                        return DropdownMenuItem(
                          value: status,
                          child: Row(
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: _getStatusColor(status),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(_getStatusLabel(status)),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (status) {
                        if (status != null) {
                          setState(() => _selectedStatus = status);
                        }
                      },
                    ),
                  ]),
                  const SizedBox(height: 24),
                  // Action buttons
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: widget.onReassignTasks,
                          icon: const Icon(Icons.assignment),
                          label: const Text('Reassign Tasks'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: widget.onSendMessage,
                          icon: const Icon(Icons.message),
                          label: const Text('Send Message'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: widget.onViewReports,
                          icon: const Icon(Icons.assessment),
                          label: const Text('View Reports'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (context) => AdminActionsModal(
                                employeeId: employee.employeeId,
                                employeeName: employee.name,
                                onActionComplete: () {
                                  Navigator.pop(context);
                                },
                              ),
                            );
                          },
                          icon: const Icon(Icons.admin_panel_settings),
                          label: const Text('Admin Actions'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            widget.onStatusChange?.call(_selectedStatus);
                            Navigator.pop(context);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.purple,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Update Status'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }

  Widget _buildInfoRow(
    String label,
    String value,
    IconData icon, {
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color ?? Colors.grey),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(EmployeeStatus status) {
    switch (status) {
      case EmployeeStatus.available:
        return Colors.green;
      case EmployeeStatus.moving:
        return Colors.green;
      case EmployeeStatus.busy:
        return Colors.red;
      case EmployeeStatus.offline:
        return Colors.grey;
    }
  }

  String _getStatusLabel(EmployeeStatus status) {
    switch (status) {
      case EmployeeStatus.available:
        return '🟢 Available';
      case EmployeeStatus.moving:
        return '🟢 Moving';
      case EmployeeStatus.busy:
        return '🔴 Busy';
      case EmployeeStatus.offline:
        return '⚫ Offline';
    }
  }

  String _getStatusEmoji(EmployeeStatus status) {
    switch (status) {
      case EmployeeStatus.available:
        return '🟢';
      case EmployeeStatus.moving:
        return '🚗';
      case EmployeeStatus.busy:
        return '🔴';
      case EmployeeStatus.offline:
        return '⚫';
    }
  }
}
