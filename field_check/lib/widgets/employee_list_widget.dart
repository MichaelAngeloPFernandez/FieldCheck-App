import 'package:flutter/material.dart';
import 'package:field_check/models/user_model.dart';
import 'package:field_check/services/employee_tracking_service.dart';
import 'package:field_check/widgets/employee_tracking_card.dart';

class EmployeeListWidget extends StatefulWidget {
  final List<UserModel> employees;
  final Function(UserModel)? onEmployeeSelected;
  final bool showOnlineOnly;
  final bool showWorkload;

  const EmployeeListWidget({
    super.key,
    required this.employees,
    this.onEmployeeSelected,
    this.showOnlineOnly = false,
    this.showWorkload = true,
  });

  @override
  State<EmployeeListWidget> createState() => _EmployeeListWidgetState();
}

class _EmployeeListWidgetState extends State<EmployeeListWidget> {
  final EmployeeTrackingService _trackingService = EmployeeTrackingService();
  final Map<String, EmployeeStats?> _statsCache = {};

  @override
  void initState() {
    super.initState();
    _loadEmployeeStats();
  }

  Future<void> _loadEmployeeStats() async {
    if (!widget.showWorkload) return;

    for (final employee in widget.employees) {
      try {
        final stats = await _trackingService.getEmployeeStats(employee.id);
        if (mounted) {
          setState(() {
            _statsCache[employee.id] = stats;
          });
        }
      } catch (e) {
        debugPrint('Error loading stats for ${employee.id}: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    var filteredEmployees = widget.employees;

    // Filter by online status if needed
    if (widget.showOnlineOnly) {
      filteredEmployees = filteredEmployees
          .where((e) => e.isOnline ?? false)
          .toList();
    }

    // Sort by workload (busy first)
    filteredEmployees.sort((a, b) {
      final aWorkload = a.workloadWeight ?? 0.0;
      final bWorkload = b.workloadWeight ?? 0.0;
      return bWorkload.compareTo(aWorkload);
    });

    if (filteredEmployees.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            widget.showOnlineOnly
                ? 'No online employees'
                : 'No employees found',
            style: const TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: filteredEmployees.length,
      itemBuilder: (context, index) {
        final employee = filteredEmployees[index];
        return EmployeeTrackingCard(
          employee: employee,
          onTap: () => widget.onEmployeeSelected?.call(employee),
          showLocation: widget.showWorkload,
        );
      },
    );
  }
}
