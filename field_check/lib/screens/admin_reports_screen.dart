// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:field_check/services/attendance_service.dart';
import 'package:field_check/services/geofence_service.dart';
import 'package:field_check/models/geofence_model.dart';
import 'package:field_check/services/report_service.dart';
import 'package:field_check/models/report_model.dart';
import 'package:intl/intl.dart';
import 'package:field_check/config/api_config.dart';
import 'package:field_check/services/user_service.dart';
import 'package:field_check/screens/report_export_preview_screen.dart';

class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> {
  List<AttendanceRecord> _attendanceRecords = [];
  List<Geofence> _geofences = [];
  late io.Socket _socket;
  List<ReportModel> _taskReports = [];
  List<ReportModel> _archivedTaskReports = [];
  String _viewMode = 'attendance'; // 'attendance' | 'task'
  bool _hasNewTaskReports = false;
  bool _isLoadingTaskReports = false;
  String? _taskReportsError;
  bool _showArchivedReports = false;

  String _filterDate = 'All Dates';
  String _filterLocation = 'All Locations';
  String _filterStatus = 'All Status';
  String _reportStatusFilter = 'All';
  String _dateRangePreset =
      'All Time'; // 'All Time', 'Last 7 Days', 'Last 30 Days', 'Custom'
  DateTime? _customStartDate;
  DateTime? _customEndDate;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _fetchGeofences();
    _fetchAttendanceRecords();
    _fetchTaskReports();
    _initSocket();
  }

  @override
  void dispose() {
    _socket.disconnect();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _initSocket() async {
    final base = ApiConfig.baseUrl;
    final token = await UserService().getToken();
    final options = io.OptionBuilder()
        .setTransports(['websocket'])
        .enableAutoConnect()
        .setTimeout(20000)
        .build();
    if (token != null) {
      options['extraHeaders'] = {'Authorization': 'Bearer $token'};
    }
    options['reconnection'] = true;
    options['reconnectionAttempts'] = 999999;
    options['reconnectionDelay'] = 500;
    options['reconnectionDelayMax'] = 10000;
    _socket = io.io(base, options);

    _socket.onConnect((_) => debugPrint('Connected to Socket.IO'));
    _socket.onDisconnect((_) => debugPrint('Disconnected from Socket.IO'));
    _socket.onConnectError(
      (err) => debugPrint('Socket.IO Connect Error: $err'),
    );
    _socket.onError((err) => debugPrint('Socket.IO Error: $err'));
    _socket.on(
      'reconnect_attempt',
      (_) => debugPrint('Reports socket reconnect attempt'),
    );
    _socket.on('reconnect', (_) => debugPrint('Reports socket reconnected'));
    _socket.on(
      'reconnect_error',
      (err) => debugPrint('Reports socket reconnect error: $err'),
    );
    _socket.on(
      'reconnect_failed',
      (_) => debugPrint('Reports socket reconnect failed'),
    );

    _socket.on('newAttendanceRecord', (data) {
      debugPrint('New attendance record: $data');
      _fetchAttendanceRecords();
    });

    _socket.on('updatedAttendanceRecord', (data) {
      debugPrint('Attendance record updated: $data');
      _fetchAttendanceRecords();
    });

    _socket.on('newReport', (_) {
      setState(() {
        _hasNewTaskReports = true;
      });
      // Always fetch reports in real-time for all admins
      _fetchTaskReports();
    });

    _socket.on('updatedReport', (_) {
      // Always fetch reports in real-time for all admins
      _fetchTaskReports();
    });

    _socket.on('deletedReport', (_) {
      // Always fetch reports in real-time for all admins
      _fetchTaskReports();
    });

    _socket.on('taskCompleted', (data) {
      debugPrint('Task completed event: $data');
      _fetchAttendanceRecords();
      if (_viewMode == 'task') {
        _fetchTaskReports();
      }
    });
  }

  Future<void> _fetchGeofences() async {
    try {
      final geofences = await GeofenceService().fetchGeofences();
      setState(() {
        _geofences = geofences;
      });
    } catch (e) {
      debugPrint('Error fetching geofences: $e');
    }
  }

  Future<void> _fetchAttendanceRecords() async {
    try {
      debugPrint(
        'Fetching attendance records with filters: date=$_filterDate, location=$_filterLocation, status=$_filterStatus',
      );
      final records = await AttendanceService().getAttendanceRecords(
        date: _filterDate != 'All Dates' ? DateTime.parse(_filterDate) : null,
        locationId: _filterLocation != 'All Locations'
            ? (_geofences
                      .where((g) => g.name == _filterLocation)
                      .toList()
                      .isNotEmpty
                  ? _geofences
                        .where((g) => g.name == _filterLocation)
                        .toList()
                        .first
                        .id
                  : null)
            : null,
        status: _filterStatus != 'All Status' ? _filterStatus : null,
      );
      debugPrint('✓ Fetched ${records.length} attendance records');
      setState(() {
        _attendanceRecords = records;
      });
    } catch (e) {
      debugPrint('✗ Error fetching attendance records: $e');
      setState(() {
        _attendanceRecords = [];
      });
    }
  }

  Future<void> _fetchTaskReports() async {
    setState(() {
      _isLoadingTaskReports = true;
      _taskReportsError = null;
    });
    try {
      if (_showArchivedReports) {
        final reports = await ReportService().getArchivedReports(type: 'task');
        setState(() {
          _archivedTaskReports = reports;
          _isLoadingTaskReports = false;
        });
      } else {
        final reports = await ReportService().getCurrentReports(type: 'task');
        setState(() {
          _taskReports = reports;
          _isLoadingTaskReports = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching task reports: $e');
      setState(() {
        _isLoadingTaskReports = false;
        _taskReportsError = 'Failed to load reports: $e';
      });
    }
  }

  List<ReportModel> _filteredTaskReports() {
    final base = _showArchivedReports ? _archivedTaskReports : _taskReports;
    if (_reportStatusFilter == 'All') return base;
    return base
        .where(
          (r) => r.status.toLowerCase() == _reportStatusFilter.toLowerCase(),
        )
        .toList();
  }

  void _scheduleFetchAttendance() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _fetchAttendanceRecords();
    });
  }

  void _applyDateRangePreset(String preset) {
    setState(() {
      _dateRangePreset = preset;
      final now = DateTime.now();

      switch (preset) {
        case 'Last 7 Days':
          _customStartDate = now.subtract(const Duration(days: 7));
          _customEndDate = now;
          _filterDate = _customStartDate.toString().split(' ')[0];
          break;
        case 'Last 30 Days':
          _customStartDate = now.subtract(const Duration(days: 30));
          _customEndDate = now;
          _filterDate = _customStartDate.toString().split(' ')[0];
          break;
        case 'All Time':
          _customStartDate = null;
          _customEndDate = null;
          _filterDate = 'All Dates';
          break;
        default:
          break;
      }
    });
    _scheduleFetchAttendance();
  }

  /// Get count of employees with no check-in/out records
  /// This identifies employees who should have checked in but didn't
  int _getNoCheckInOutCount() {
    // Group records by employee ID to find those with incomplete check-in/out
    final Map<String, List<AttendanceRecord>> recordsByEmployee = {};
    
    for (final record in _attendanceRecords) {
      final employeeId = record.userId;
      recordsByEmployee.putIfAbsent(employeeId, () => []);
      recordsByEmployee[employeeId]!.add(record);
    }

    // Count employees who only have check-in but no check-out (incomplete day)
    int incompleteCount = 0;
    for (final records in recordsByEmployee.values) {
      final hasCheckIn = records.any((r) => r.isCheckIn);
      final hasCheckOut = records.any((r) => !r.isCheckIn);
      
      // If employee has check-in but no check-out, they didn't complete their day
      if (hasCheckIn && !hasCheckOut) {
        incompleteCount++;
      }
    }
    
    return incompleteCount;
  }

  @override
  Widget build(BuildContext context) {
    const brandColor = Color(0xFF2688d4);

    final List<String> locationItems = [
      'All Locations',
      ..._geofences.map((g) => g.name),
    ];

    final Set<String> statusSet = {
      'All Status',
      ..._attendanceRecords.map(
        (a) => a.isCheckIn ? 'Checked In' : 'Checked Out',
      ),
    };
    final List<String> statusItems = statusSet.toList();

    // Keep date dropdown simple: show "All Dates" and the currently picked date
    final List<String> dateItems = [
      'All Dates',
      if (_filterDate != 'All Dates') _filterDate,
    ];

    String formatTime(DateTime? dt) =>
        dt == null ? '-' : DateFormat('HH:mm').format(dt.toLocal());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Reports'),
        backgroundColor: brandColor,
        actions: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: ElevatedButton.icon(
              onPressed: _exportReport,
              icon: const Icon(Icons.download),
              label: const Text('Export'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: brandColor,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                      // View toggle
                      Row(
                        children: [
                          ChoiceChip(
                            label: const Text('Attendance'),
                            selected: _viewMode == 'attendance',
                            onSelected: (sel) {
                              if (!sel) return;
                              setState(() {
                                _viewMode = 'attendance';
                              });
                            },
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('Task Reports'),
                                if (_hasNewTaskReports)
                                  const Padding(
                                    padding: EdgeInsets.only(left: 6.0),
                                    child: SizedBox(
                                      width: 8,
                                      height: 8,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: Colors.red,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            selected: _viewMode == 'task',
                            onSelected: (sel) async {
                              if (!sel) return;
                              setState(() {
                                _viewMode = 'task';
                                _hasNewTaskReports = false;
                              });
                              await _fetchTaskReports();
                            },
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      if (_viewMode == 'attendance')
                        Row(
                          children: [
                            Expanded(
                              child: _buildStatCard(
                                title: 'Total Records',
                                value: _attendanceRecords.length.toString(),
                                icon: Icons.list_alt,
                                color: brandColor,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildStatCard(
                                title: 'No Check-in/out',
                                value: _getNoCheckInOutCount().toString(),
                                icon: Icons.warning_amber,
                                color: Colors.orange,
                              ),
                            ),
                          ],
                        ),

                      if (_viewMode == 'attendance') const SizedBox(height: 12),

                      if (_viewMode == 'attendance')
                        _attendanceRecords.isEmpty
                            ? const Center(
                                child: Text('No attendance records'),
                              )
                            : Card(
                                      elevation: 2,
                                      child: Padding(
                                        padding: const EdgeInsets.all(8.0),
                                        child: LayoutBuilder(
                                          builder: (context, constraints) {
                                            return SingleChildScrollView(
                                              scrollDirection: Axis.horizontal,
                                              child: DataTable(
                                                columns: const [
                                                  DataColumn(
                                                    label: Text('Employee'),
                                                  ),
                                                  DataColumn(
                                                    label: Text('Location'),
                                                  ),
                                                  DataColumn(
                                                    label: Text('Date'),
                                                  ),
                                                  DataColumn(
                                                    label: Text('Time'),
                                                  ),
                                                  DataColumn(
                                                    label: Text('Status'),
                                                  ),
                                                ],
                                                rows: _attendanceRecords.map((
                                                  record,
                                                ) {
                                                  final time = formatTime(
                                                    record.timestamp,
                                                  );
                                                  final status =
                                                      record.isCheckIn
                                                      ? 'Checked In'
                                                      : 'Checked Out';
                                                  final date = record.timestamp
                                                      .toLocal()
                                                      .toString()
                                                      .split(' ')[0];

                                                  return DataRow(
                                                    cells: [
                                                      DataCell(
                                                        Text(
                                                          record.employeeName ??
                                                              'Unknown',
                                                        ),
                                                      ),
                                                      DataCell(
                                                        Text(
                                                          record.geofenceName ??
                                                              'N/A',
                                                        ),
                                                      ),
                                                      DataCell(Text(date)),
                                                      DataCell(Text(time)),
                                                      DataCell(
                                                        Chip(
                                                          label: Text(status),
                                                          backgroundColor:
                                                              record.isCheckIn
                                                              ? Colors
                                                                    .green[100]
                                                              : Colors.red[100],
                                                          labelStyle: TextStyle(
                                                            color:
                                                                record.isCheckIn
                                                                ? Colors
                                                                      .green[900]
                                                                : Colors
                                                                      .red[900],
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  );
                                                }).toList(),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ),

                      if (_viewMode == 'task') _buildTaskReportsView(),
                    ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );
    if (picked != null && picked.toString().split(' ')[0] != _filterDate) {
      setState(() {
        _filterDate = picked.toString().split(' ')[0];
      });
      _scheduleFetchAttendance();
    }
  }

  Widget _buildFilterDropdown({
    required String label,
    required String value,
    required List<String> items,
    required void Function(String?) onChanged,
    VoidCallback? onTap, // Add onTap parameter
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: onTap, // Use GestureDetector to trigger onTap
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(4),
            ),
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              underline: Container(),
              items: items.map((item) {
                return DropdownMenuItem<String>(
                  value: item,
                  child: Text(
                    label == 'Date' && item != 'All Dates'
                        ? DateFormat('yyyy-MM-dd').format(DateTime.parse(item))
                        : item,
                  ),
                );
              }).toList(),
              onChanged: onChanged,
              // Disable dropdown if onTap is provided to prevent default dropdown behavior
              // when a custom date picker is used.
              // This might need adjustment based on desired UX.
              // For now, we'll keep it enabled but the onTap will take precedence.
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  void _showAttendanceDetails(AttendanceRecord data) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          '${data.userId} - ${data.timestamp.toLocal().toString().split(' ')[0]}',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow(
              'Check In Time:',
              data.isCheckIn
                  ? data.timestamp
                        .toLocal()
                        .toString()
                        .split(' ')[1]
                        .substring(0, 5)
                  : 'N/A',
            ),
            _buildDetailRow(
              'Check Out Time:',
              !data.isCheckIn
                  ? data.timestamp
                        .toLocal()
                        .toString()
                        .split(' ')[1]
                        .substring(0, 5)
                  : 'N/A',
            ),
            _buildDetailRow('Location:', data.geofenceName ?? 'N/A'),
            _buildDetailRow(
              'Status:',
              data.isCheckIn ? 'Checked In' : 'Checked Out',
            ),
            // _buildDetailRow('Total Hours:', '8.25'), // Calculate total hours based on check-in/out times
            // _buildDetailRow('Notes:', 'Regular attendance'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showReportDetails(ReportModel r) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(r.taskTitle ?? 'Report Details'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow('Employee:', r.employeeName ?? r.employeeId),
              _buildDetailRow('Task:', r.taskTitle ?? (r.taskId ?? '-')),
              _buildDetailRow('Status:', r.status),
              _buildDetailRow(
                'Submitted:',
                DateFormat('yyyy-MM-dd HH:mm').format(r.submittedAt.toLocal()),
              ),
              if (r.content.isNotEmpty) _buildDetailRow('Content:', r.content),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _buildTaskReportsView() {
    if (_isLoadingTaskReports) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_taskReportsError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                _taskReportsError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _fetchTaskReports,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    final reports = _showArchivedReports ? _archivedTaskReports : _taskReports;
    if (reports.isEmpty) {
      return Center(
        child: Text(
          _showArchivedReports ? 'No archived reports' : 'No task reports',
        ),
      );
    }
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ChoiceChip(
                  label: const Text('Current'),
                  selected: !_showArchivedReports,
                  onSelected: (sel) async {
                    if (!sel) return;
                    setState(() {
                      _showArchivedReports = false;
                    });
                    await _fetchTaskReports();
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Archived'),
                  selected: _showArchivedReports,
                  onSelected: (sel) async {
                    if (!sel) return;
                    setState(() {
                      _showArchivedReports = true;
                    });
                    await _fetchTaskReports();
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('All'),
                  selected: _reportStatusFilter == 'All',
                  onSelected: (sel) {
                    if (!sel) return;
                    setState(() {
                      _reportStatusFilter = 'All';
                    });
                  },
                ),
                ChoiceChip(
                  label: const Text('Submitted'),
                  selected: _reportStatusFilter == 'submitted',
                  onSelected: (sel) {
                    if (!sel) return;
                    setState(() {
                      _reportStatusFilter = 'submitted';
                    });
                  },
                ),
                ChoiceChip(
                  label: const Text('Reviewed'),
                  selected: _reportStatusFilter == 'reviewed',
                  onSelected: (sel) {
                    if (!sel) return;
                    setState(() {
                      _reportStatusFilter = 'reviewed';
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Employee')),
                  DataColumn(label: Text('Task')),
                  DataColumn(label: Text('Submitted')),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Content')),
                  DataColumn(label: Text('Actions')),
                ],
                rows: _filteredTaskReports().map((r) {
                  final submitted = DateFormat(
                    'yyyy-MM-dd HH:mm',
                  ).format(r.submittedAt.toLocal());
                  return DataRow(
                    cells: [
                      DataCell(Text(r.employeeName ?? r.employeeId)),
                      DataCell(Text(r.taskTitle ?? (r.taskId ?? '-'))),
                      DataCell(Text(submitted)),
                      DataCell(Text(r.status)),
                      DataCell(Text(r.content)),
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'View',
                              icon: const Icon(Icons.info_outline),
                              onPressed: () => _showReportDetails(r),
                            ),
                            if (r.status != 'reviewed')
                              TextButton(
                                onPressed: () async {
                                  try {
                                    await ReportService().updateReportStatus(
                                      r.id,
                                      'reviewed',
                                    );
                                    await _fetchTaskReports();
                                    if (mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text('Marked as reviewed'),
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(content: Text('Failed: $e')),
                                      );
                                    }
                                  }
                                },
                                child: const Text('Review'),
                              ),
                            TextButton(
                              onPressed: () async {
                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Delete Report'),
                                    content: const Text(
                                      'Are you sure you want to delete this report?',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, false),
                                        child: const Text('Cancel'),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
                                        child: const Text('Delete'),
                                      ),
                                    ],
                                  ),
                                );
                                if (ok == true) {
                                  try {
                                    await ReportService().deleteReport(r.id);
                                    await _fetchTaskReports();
                                    if (mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text('Report deleted'),
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(content: Text('Failed: $e')),
                                      );
                                    }
                                  }
                                }
                              },
                              child: const Text('Delete'),
                            ),
                            if (!_showArchivedReports)
                              TextButton(
                                onPressed: () async {
                                  try {
                                    await ReportService().archiveReport(r.id);
                                    await _fetchTaskReports();
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Report archived')),
                                      );
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Failed: $e')),
                                      );
                                    }
                                  }
                                },
                                child: const Text('Archive'),
                              )
                            else
                              TextButton(
                                onPressed: () async {
                                  try {
                                    await ReportService().restoreReport(r.id);
                                    await _fetchTaskReports();
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Report restored')),
                                      );
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Failed: $e')),
                                      );
                                    }
                                  }
                                },
                                child: const Text('Restore'),
                              ),
                          ],
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportReport() async {
    // Show export preview with filters applied
    if (_viewMode == 'attendance') {
      if (_attendanceRecords.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No attendance records to export')),
        );
        return;
      }
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ReportExportPreviewScreen(
            records: _attendanceRecords,
            reportType: _viewMode,
            taskReports: _filteredTaskReports(),
            startDate: _filterDate != 'All Dates'
                ? DateTime.parse(_filterDate)
                : null,
            endDate: null,
            locationFilter: _filterLocation != 'All Locations'
                ? _filterLocation
                : null,
            statusFilter: _filterStatus != 'All Status' ? _filterStatus : null,
          ),
        ),
      );
    } else {
      if (_taskReports.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No task reports to export')),
        );
        return;
      }
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ReportExportPreviewScreen(
            records: _attendanceRecords,
            reportType: _viewMode,
            taskReports: _filteredTaskReports(),
            startDate: _filterDate != 'All Dates'
                ? DateTime.parse(_filterDate)
                : null,
            endDate: null,
            locationFilter: _filterLocation != 'All Locations'
                ? _filterLocation
                : null,
            statusFilter: _reportStatusFilter != 'All'
                ? _reportStatusFilter
                : null,
          ),
        ),
      );
    }
  }
}
