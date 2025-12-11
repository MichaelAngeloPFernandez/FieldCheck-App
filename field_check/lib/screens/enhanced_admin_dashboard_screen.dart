import 'package:flutter/material.dart';
import 'dart:async';
import '../services/employee_location_service.dart';
import '../services/checkout_notification_service.dart';
import '../widgets/employee_status_view.dart';
import '../widgets/live_employee_map.dart';
import '../widgets/employee_management_modal.dart';

class EnhancedAdminDashboardScreen extends StatefulWidget {
  const EnhancedAdminDashboardScreen({super.key});

  @override
  State<EnhancedAdminDashboardScreen> createState() =>
      _EnhancedAdminDashboardScreenState();
}

class _EnhancedAdminDashboardScreenState
    extends State<EnhancedAdminDashboardScreen> {
  final EmployeeLocationService _locationService = EmployeeLocationService();
  List<EmployeeLocation> _employees = [];
  bool _isLoading = true;
  Timer? _refreshTimer;
  final CheckoutNotificationService _checkoutService =
      CheckoutNotificationService();
  StreamSubscription<CheckoutWarning>? _warningSub;
  StreamSubscription<AutoCheckoutEvent>? _autoCheckoutSub;

  @override
  void initState() {
    super.initState();
    _initializeLocationService();
    // Auto-refresh every 5 seconds for real-time updates
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) {
        setState(() {});
      }
    });

    _initCheckoutNotifications();
  }

  Future<void> _initializeLocationService() async {
    try {
      await _locationService.initialize();
      _locationService.employeeLocationsStream.listen((locations) {
        if (mounted) {
          setState(() {
            _employees = locations;
            _isLoading = false;
          });
        }
      });
    } catch (e) {
      debugPrint('Error initializing location service: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _locationService.dispose();
    _warningSub?.cancel();
    _autoCheckoutSub?.cancel();
    super.dispose();
  }

  Future<void> _initCheckoutNotifications() async {
    try {
      await _checkoutService.initialize();

      _warningSub = _checkoutService.warningStream.listen((warning) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Warning: ${warning.employeeName} will be auto-checked out '
              'in ${warning.minutesRemaining} minutes.',
            ),
            duration: const Duration(seconds: 4),
            backgroundColor: Colors.orange[700],
          ),
        );
      });

      _autoCheckoutSub = _checkoutService.checkoutStream.listen((autoEvent) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${autoEvent.employeeName} was auto-checked out '
              '(attendance voided).',
            ),
            duration: const Duration(seconds: 5),
            backgroundColor: Colors.red[700],
          ),
        );
      });
    } catch (e) {
      debugPrint('Error initializing checkout notifications: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => _isLoading = true);
              Future.delayed(const Duration(seconds: 1), () {
                if (mounted) setState(() => _isLoading = false);
              });
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Dashboard stats
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          'Employees',
                          _employees.length.toString(),
                          Icons.people,
                          Colors.blue,
                          onTap: () => _showTotalEmployeesView(context),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildStatCard(
                          'Online',
                          _employees.where((e) => e.isOnline).length.toString(),
                          Icons.cloud_done,
                          Colors.green,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildStatCard(
                          'Busy',
                          _employees
                              .where((e) => e.status == EmployeeStatus.busy)
                              .length
                              .toString(),
                          Icons.schedule,
                          Colors.red,
                        ),
                      ),
                    ],
                  ),
                ),
                // Status breakdown
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatusBadge(
                        '🟢 Available',
                        _employees
                            .where((e) => e.status == EmployeeStatus.available)
                            .length,
                        Colors.green,
                      ),
                      _buildStatusBadge(
                        '🔵 Moving',
                        _employees
                            .where((e) => e.status == EmployeeStatus.moving)
                            .length,
                        Colors.blue,
                      ),
                      _buildStatusBadge(
                        '🔴 Busy',
                        _employees
                            .where((e) => e.status == EmployeeStatus.busy)
                            .length,
                        Colors.red,
                      ),
                      _buildStatusBadge(
                        '⚫ Offline',
                        _employees
                            .where((e) => e.status == EmployeeStatus.offline)
                            .length,
                        Colors.grey,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Real-time location updates indicator
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue[200]!),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Real-time location tracking active',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.blue,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${_employees.where((e) => e.isOnline).length} online',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.blue,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(),
                // Live employee map
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: LiveEmployeeMap(
                    employees: _employees,
                    height: 300,
                    onStatusChange: (employeeId, newStatus) {
                      _locationService.requestStatusUpdate(
                        employeeId,
                        newStatus,
                      );
                    },
                    onRefresh: () {
                      setState(() => _isLoading = true);
                      Future.delayed(const Duration(seconds: 1), () {
                        if (mounted) setState(() => _isLoading = false);
                      });
                    },
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(),
                // Employee status view
                Expanded(
                  child: EmployeeStatusView(
                    employees: _employees,
                    onStatusChange: (employeeId, newStatus) {
                      _locationService.requestStatusUpdate(
                        employeeId,
                        newStatus,
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Status updated for $employeeId'),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildStatCard(
    String label,
    String value,
    IconData icon,
    Color color, {
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String label, int count, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            count.toString(),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOptionCard(
    String title,
    String subtitle,
    IconData icon,
    Color color, {
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward, color: color),
          ],
        ),
      ),
    );
  }

  void _showTotalEmployeesView(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => EmployeeManagementModal(
        employees: _employees,
        onConfigUpdate: (employeeId, config) {
          debugPrint(
            'Updated config for $employeeId: '
            'checkout=${config.autoCheckoutMinutes}min, '
            'maxTasks=${config.maxTasksPerDay}',
          );
        },
      ),
    );
  }
}
