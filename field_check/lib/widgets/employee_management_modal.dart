import 'package:flutter/material.dart';
import '../services/employee_location_service.dart';
import '../services/auto_checkout_service.dart';
import '../services/admin_actions_service.dart';

class EmployeeManagementModal extends StatefulWidget {
  final List<EmployeeLocation> employees;
  final Function(String employeeId, EmployeeCheckoutConfig config)?
  onConfigUpdate;

  const EmployeeManagementModal({
    super.key,
    required this.employees,
    this.onConfigUpdate,
  });

  @override
  State<EmployeeManagementModal> createState() =>
      _EmployeeManagementModalState();
}

class _EmployeeManagementModalState extends State<EmployeeManagementModal> {
  late TextEditingController _searchController;
  final String _selectedFilter = 'all'; // all, online, busy, moving, offline
  List<EmployeeLocation> _filteredEmployees = [];
  final Map<String, EmployeeCheckoutConfig> _configs = {};
  final AdminActionsService _adminActions = AdminActionsService();

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _filteredEmployees = widget.employees;
    _applyFilters();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _applyFilters() {
    var filtered = widget.employees;

    // Filter by status
    if (_selectedFilter != 'all') {
      filtered = filtered.where((e) {
        switch (_selectedFilter) {
          case 'online':
            return e.isOnline && e.status != EmployeeStatus.offline;
          case 'busy':
            return e.status == EmployeeStatus.busy;
          case 'moving':
            return e.status == EmployeeStatus.moving;
          case 'offline':
            return e.status == EmployeeStatus.offline;
          default:
            return true;
        }
      }).toList();
    }

    // Filter by search
    final query = _searchController.text.toLowerCase();
    if (query.isNotEmpty) {
      filtered = filtered.where((e) {
        return e.name.toLowerCase().contains(query) ||
            e.employeeId.toLowerCase().contains(query);
      }).toList();
    }

    setState(() {
      _filteredEmployees = filtered;
    });
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

  Future<void> _showEmployeeOptions(EmployeeLocation employee) async {
    // Start from cached or default config
    EmployeeCheckoutConfig config =
        _configs[employee.employeeId] ??
        EmployeeCheckoutConfig(employeeId: employee.employeeId);

    // Attempt to load existing config from backend
    try {
      final remoteConfig = await _adminActions.getEmployeeCheckoutConfig(
        employee.employeeId,
      );
      if (remoteConfig != null) {
        config = remoteConfig;
      }
    } catch (e) {
      debugPrint(
        'Error loading checkout config for ${employee.employeeId}: $e',
      );
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => EmployeeOptionsDialog(
        employee: employee,
        config: config,
        onSave: (updatedConfig) async {
          setState(() {
            _configs[employee.employeeId] = updatedConfig;
          });
          widget.onConfigUpdate?.call(employee.employeeId, updatedConfig);

          Navigator.pop(context);

          // Persist to backend Settings AFTER closing dialog to avoid
          // using this dialog's BuildContext across async gaps.
          final success = await _adminActions.saveEmployeeCheckoutConfig(
            updatedConfig,
          );

          if (!mounted) return;
          // Use the parent modal's context for feedback
          ScaffoldMessenger.of(this.context).showSnackBar(
            SnackBar(
              content: Text(
                success
                    ? '${employee.name} settings updated'
                    : 'Failed to save settings for ${employee.name}',
              ),
              duration: const Duration(seconds: 3),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Employees',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.close, color: Colors.white),
                ),
              ],
            ),
          ),

          // Search bar
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => _applyFilters(),
              decoration: InputDecoration(
                hintText: 'Search by name or ID...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? GestureDetector(
                        onTap: () {
                          _searchController.clear();
                          _applyFilters();
                        },
                        child: const Icon(Icons.clear),
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Employee list
          Expanded(
            child: _filteredEmployees.isEmpty
                ? Center(
                    child: Text(
                      _searchController.text.isEmpty
                          ? 'No employees found'
                          : 'No matching employees',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: _filteredEmployees.length,
                    itemBuilder: (context, index) {
                      final employee = _filteredEmployees[index];
                      final statusColor = _getStatusColor(employee.status);
                      final statusLabel = _getStatusLabel(employee.status);

                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        child: Card(
                          child: ListTile(
                            leading: Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: statusColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            title: Text(employee.name),
                            subtitle: Text(
                              '$statusLabel • ${employee.employeeId}',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.75),
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.info_outline),
                              onPressed: () => _showEmployeeOptions(employee),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // Footer
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Close'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Employee options dialog for admin configuration
class EmployeeOptionsDialog extends StatefulWidget {
  final EmployeeLocation employee;
  final EmployeeCheckoutConfig config;
  final Function(EmployeeCheckoutConfig)? onSave;

  const EmployeeOptionsDialog({
    super.key,
    required this.employee,
    required this.config,
    this.onSave,
  });

  @override
  State<EmployeeOptionsDialog> createState() => _EmployeeOptionsDialogState();
}

class _EmployeeOptionsDialogState extends State<EmployeeOptionsDialog> {
  late int _checkoutMinutes;
  late int _maxTasks;
  late bool _autoCheckoutEnabled;

  @override
  void initState() {
    super.initState();
    _checkoutMinutes = widget.config.autoCheckoutMinutes;
    _maxTasks = widget.config.maxTasksPerDay;
    _autoCheckoutEnabled = widget.config.autoCheckoutEnabled;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Employee Settings',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        widget.employee.name,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),

            // Content
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Auto-checkout toggle
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Auto-Checkout Enabled',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Switch(
                        value: _autoCheckoutEnabled,
                        onChanged: (value) {
                          setState(() => _autoCheckoutEnabled = value);
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Checkout time
                  Text(
                    'Auto-Checkout Time: $_checkoutMinutes minutes',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Slider(
                    value: _checkoutMinutes.toDouble(),
                    min: 15,
                    max: 120,
                    divisions: 21,
                    label: '$_checkoutMinutes min',
                    onChanged: (value) {
                      setState(() => _checkoutMinutes = value.toInt());
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '15 min',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        Text(
                          '120 min',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Max tasks
                  Text(
                    'Max Tasks Per Day: $_maxTasks',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Slider(
                    value: _maxTasks.toDouble(),
                    min: 1,
                    max: 50,
                    divisions: 49,
                    label: '$_maxTasks tasks',
                    onChanged: (value) {
                      setState(() => _maxTasks = value.toInt());
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '1 task',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        Text(
                          '50 tasks',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Info box
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue[200]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Settings Summary',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '• Auto-checkout: ${_autoCheckoutEnabled ? 'Enabled' : 'Disabled'}\n'
                          '• Offline threshold: $_checkoutMinutes minutes\n'
                          '• Max daily tasks: $_maxTasks',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Buttons
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.surface,
                        foregroundColor: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.9),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        final updatedConfig = EmployeeCheckoutConfig(
                          employeeId: widget.employee.employeeId,
                          autoCheckoutMinutes: _checkoutMinutes,
                          maxTasksPerDay: _maxTasks,
                          autoCheckoutEnabled: _autoCheckoutEnabled,
                        );
                        widget.onSave?.call(updatedConfig);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
