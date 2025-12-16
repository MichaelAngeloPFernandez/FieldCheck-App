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
import 'package:field_check/screens/admin_employee_history_screen.dart';

class AdminReportsScreen extends StatefulWidget {
  final String? employeeId;

  const AdminReportsScreen({super.key, this.employeeId});

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> {
  List<AttendanceRecord> _attendanceRecords = [];
  final List<AttendanceRecord> _archivedAttendanceRecords = [];
  List<Geofence> _geofences = [];
  late io.Socket _socket;
  List<ReportModel> _taskReports = [];
  List<ReportModel> _archivedTaskReports = [];
  String _viewMode = 'attendance'; // 'attendance' | 'task'
  bool _hasNewTaskReports = false;
  bool _isLoadingTaskReports = false;
  String? _taskReportsError;
  bool _showArchivedReports = false;
  bool _showArchivedAttendance = false;

  String _filterDate = 'All Dates';
  final String _filterLocation = 'All Locations';
  final String _filterStatus = 'All Status';
  String _reportStatusFilter = 'All';
  String _attendanceStatusFilter = 'All';
  String _taskDifficultyFilter = 'All';
  String _attendanceDateFilter = 'all'; // all, today, week, month, custom
  DateTime? _attendanceStartDate;
  DateTime? _attendanceEndDate;
  String? _filterEmployeeId;
  String? _filterEmployeeName;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    // Set employee filter if provided
    if (widget.employeeId != null) {
      _filterEmployeeId = widget.employeeId;
    }
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
    var filtered = base;

    // Filter by employee if specified
    if (_filterEmployeeId != null) {
      filtered = filtered
          .where((r) => r.employeeId == _filterEmployeeId)
          .toList();
      _filterEmployeeName = filtered.isNotEmpty
          ? filtered.first.employeeName
          : null;
    }

    // Filter by report status
    if (_reportStatusFilter != 'All') {
      filtered = filtered
          .where(
            (r) => r.status.toLowerCase() == _reportStatusFilter.toLowerCase(),
          )
          .toList();
    }

    // Filter by task difficulty (for task reports)
    if (_taskDifficultyFilter != 'All') {
      final target = _taskDifficultyFilter.toLowerCase();
      filtered = filtered
          .where((r) => (r.taskDifficulty ?? '').toLowerCase() == target)
          .toList();
    }

    return filtered;
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

  List<AttendanceRecord> get _filteredAttendanceRecords {
    final base = _showArchivedAttendance
        ? _archivedAttendanceRecords
        : _attendanceRecords;

    Iterable<AttendanceRecord> result = base;

    if (_attendanceStartDate != null || _attendanceEndDate != null) {
      result = result.where((record) {
        final dt = record.timestamp.toLocal();

        if (_attendanceStartDate != null &&
            dt.isBefore(_attendanceStartDate!)) {
          return false;
        }
        if (_attendanceEndDate != null && !dt.isBefore(_attendanceEndDate!)) {
          return false;
        }
        return true;
      });
    }

    return result.where((record) {
      switch (_attendanceStatusFilter) {
        case 'Normal':
          return !record.isVoid;
        case 'Void':
          return record.isVoid && !record.autoCheckout;
        case 'Auto':
          return record.isVoid && record.autoCheckout;
        default:
          return true;
      }
    }).toList();
  }

  void _setAttendanceQuickDateFilter(String value) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);

    DateTime? start;
    DateTime? endExclusive;
    String label = 'All Dates';

    switch (value) {
      case 'today':
        start = todayStart;
        endExclusive = todayStart.add(const Duration(days: 1));
        label = DateFormat('yyyy-MM-dd').format(todayStart);
        break;
      case 'week':
        final weekday = todayStart.weekday; // Monday = 1
        start = todayStart.subtract(Duration(days: weekday - 1));
        endExclusive = start.add(const Duration(days: 7));
        final endInclusive = endExclusive.subtract(const Duration(days: 1));
        label =
            'Week of ${DateFormat('yyyy-MM-dd').format(start)} - ${DateFormat('yyyy-MM-dd').format(endInclusive)}';
        break;
      case 'month':
        start = DateTime(todayStart.year, todayStart.month, 1);
        final nextMonth = todayStart.month == 12
            ? DateTime(todayStart.year + 1, 1, 1)
            : DateTime(todayStart.year, todayStart.month + 1, 1);
        endExclusive = nextMonth;
        label = DateFormat('MMMM yyyy').format(start);
        break;
      case 'all':
      default:
        start = null;
        endExclusive = null;
        label = 'All Dates';
        break;
    }

    setState(() {
      _attendanceDateFilter = value;
      _attendanceStartDate = start;
      _attendanceEndDate = endExclusive;
      _filterDate = label;
    });
  }

  Future<void> _pickAttendanceCustomDateRange() async {
    final now = DateTime.now();
    final baseStart = _attendanceStartDate ?? DateTime(now.year, now.month, 1);
    final baseEnd = _attendanceEndDate != null
        ? _attendanceEndDate!.subtract(const Duration(days: 1))
        : DateTime(now.year, now.month, now.day);

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1),
      initialDateRange: DateTimeRange(start: baseStart, end: baseEnd),
    );

    if (picked == null) return;

    final start = DateTime(
      picked.start.year,
      picked.start.month,
      picked.start.day,
    );
    final endExclusive = DateTime(
      picked.end.year,
      picked.end.month,
      picked.end.day,
    ).add(const Duration(days: 1));

    setState(() {
      _attendanceDateFilter = 'custom';
      _attendanceStartDate = start;
      _attendanceEndDate = endExclusive;
      _filterDate =
          '${DateFormat('yyyy-MM-dd').format(picked.start)} - ${DateFormat('yyyy-MM-dd').format(picked.end)}';
    });
  }

  @override
  Widget build(BuildContext context) {
    const brandColor = Color(0xFF2688d4);

    String formatTime(DateTime? dt) =>
        dt == null ? '-' : DateFormat('HH:mm').format(dt.toLocal());

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Admin Reports'),
            if (_filterEmployeeId != null)
              Text(
                'Filtered: ${_filterEmployeeName ?? _filterEmployeeId}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.normal,
                ),
              ),
          ],
        ),
        backgroundColor: brandColor,
        actions: [
          if (_filterEmployeeId != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _filterEmployeeId = null;
                    _filterEmployeeName = null;
                  });
                },
                icon: const Icon(Icons.clear),
                label: const Text('Clear Filter'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.red,
                ),
              ),
            ),
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
                      Row(
                        children: [
                          ChoiceChip(
                            label: const Text('Current'),
                            selected: !_showArchivedAttendance,
                            onSelected: (sel) {
                              if (!sel) return;
                              setState(() {
                                _showArchivedAttendance = false;
                              });
                            },
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('Archived'),
                            selected: _showArchivedAttendance,
                            onSelected: (sel) {
                              if (!sel) return;
                              setState(() {
                                _showArchivedAttendance = true;
                              });
                            },
                          ),
                        ],
                      ),

                    if (_viewMode == 'attendance') const SizedBox(height: 8),

                    if (_viewMode == 'attendance')
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            ChoiceChip(
                              label: const Text('All time'),
                              selected: _attendanceDateFilter == 'all',
                              onSelected: (sel) {
                                if (!sel) return;
                                _setAttendanceQuickDateFilter('all');
                              },
                            ),
                            const SizedBox(width: 8),
                            ChoiceChip(
                              label: const Text('Today'),
                              selected: _attendanceDateFilter == 'today',
                              onSelected: (sel) {
                                if (!sel) return;
                                _setAttendanceQuickDateFilter('today');
                              },
                            ),
                            const SizedBox(width: 8),
                            ChoiceChip(
                              label: const Text('This week'),
                              selected: _attendanceDateFilter == 'week',
                              onSelected: (sel) {
                                if (!sel) return;
                                _setAttendanceQuickDateFilter('week');
                              },
                            ),
                            const SizedBox(width: 8),
                            ChoiceChip(
                              label: const Text('This month'),
                              selected: _attendanceDateFilter == 'month',
                              onSelected: (sel) {
                                if (!sel) return;
                                _setAttendanceQuickDateFilter('month');
                              },
                            ),
                            const SizedBox(width: 8),
                            ChoiceChip(
                              label: const Text('Custom'),
                              selected: _attendanceDateFilter == 'custom',
                              onSelected: (sel) async {
                                if (!sel) return;
                                await _pickAttendanceCustomDateRange();
                              },
                            ),
                          ],
                        ),
                      ),

                    if (_viewMode == 'attendance') const SizedBox(height: 8),

                    if (_viewMode == 'attendance')
                      Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('All'),
                            selected: _attendanceStatusFilter == 'All',
                            onSelected: (sel) {
                              if (!sel) return;
                              setState(() {
                                _attendanceStatusFilter = 'All';
                              });
                            },
                          ),
                          ChoiceChip(
                            label: const Text('Normal'),
                            selected: _attendanceStatusFilter == 'Normal',
                            onSelected: (sel) {
                              if (!sel) return;
                              setState(() {
                                _attendanceStatusFilter = 'Normal';
                              });
                            },
                          ),
                          ChoiceChip(
                            label: const Text('Void'),
                            selected: _attendanceStatusFilter == 'Void',
                            onSelected: (sel) {
                              if (!sel) return;
                              setState(() {
                                _attendanceStatusFilter = 'Void';
                              });
                            },
                          ),
                          ChoiceChip(
                            label: const Text('Auto Checkout'),
                            selected: _attendanceStatusFilter == 'Auto',
                            onSelected: (sel) {
                              if (!sel) return;
                              setState(() {
                                _attendanceStatusFilter = 'Auto';
                              });
                            },
                          ),
                        ],
                      ),

                    if (_viewMode == 'attendance') const SizedBox(height: 12),

                    if (_viewMode == 'attendance')
                      _attendanceRecords.isEmpty && !_showArchivedAttendance
                          ? const Center(child: Text('No attendance records'))
                          : _archivedAttendanceRecords.isEmpty &&
                                _showArchivedAttendance
                          ? const Center(
                              child: Text('No archived attendance records'),
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
                                          DataColumn(label: Text('Employee')),
                                          DataColumn(label: Text('Location')),
                                          DataColumn(label: Text('Date')),
                                          DataColumn(label: Text('Time')),
                                          DataColumn(label: Text('Status')),
                                          DataColumn(label: Text('Actions')),
                                        ],
                                        rows: _filteredAttendanceRecords.map((
                                          record,
                                        ) {
                                          final time = formatTime(
                                            record.timestamp,
                                          );
                                          String status;
                                          Color? chipBg;
                                          Color? chipFg;

                                          if (record.isVoid &&
                                              record.autoCheckout) {
                                            status = 'Auto Checkout (Void)';
                                            chipBg = Colors.red[100];
                                            chipFg = Colors.red[900];
                                          } else if (record.isVoid) {
                                            status = 'Void';
                                            chipBg = Colors.grey[300];
                                            chipFg = Colors.grey[900];
                                          } else if (record.isCheckIn) {
                                            status = 'Checked In';
                                            chipBg = Colors.green[100];
                                            chipFg = Colors.green[900];
                                          } else {
                                            status = 'Checked Out';
                                            chipBg = Colors.blue[100];
                                            chipFg = Colors.blue[900];
                                          }
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
                                                  record.geofenceName ?? 'N/A',
                                                ),
                                              ),
                                              DataCell(Text(date)),
                                              DataCell(Text(time)),
                                              DataCell(
                                                Chip(
                                                  label: Text(status),
                                                  backgroundColor: chipBg,
                                                  labelStyle: TextStyle(
                                                    color: chipFg,
                                                  ),
                                                ),
                                              ),
                                              DataCell(
                                                IconButton(
                                                  icon: const Icon(
                                                    Icons.history,
                                                  ),
                                                  tooltip:
                                                      'View history for this employee',
                                                  onPressed: () {
                                                    final employeeId =
                                                        record.userId;

                                                    Navigator.push(
                                                      context,
                                                      MaterialPageRoute(
                                                        builder: (context) =>
                                                            AdminEmployeeHistoryScreen(
                                                              employeeId:
                                                                  employeeId,
                                                              employeeName:
                                                                  record
                                                                      .employeeName ??
                                                                  'Unknown',
                                                            ),
                                                      ),
                                                    );
                                                  },
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
              if (r.attachments.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text(
                  'Attachments:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: r.attachments
                      .map(
                        (path) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: SelectableText(
                            path,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.blueGrey,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
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
                  label: const Text('All difficulties'),
                  selected: _taskDifficultyFilter == 'All',
                  onSelected: (sel) {
                    if (!sel) return;
                    setState(() {
                      _taskDifficultyFilter = 'All';
                    });
                  },
                ),
                ChoiceChip(
                  label: const Text('Easy'),
                  selected: _taskDifficultyFilter == 'easy',
                  onSelected: (sel) {
                    if (!sel) return;
                    setState(() {
                      _taskDifficultyFilter = 'easy';
                    });
                  },
                ),
                ChoiceChip(
                  label: const Text('Medium'),
                  selected: _taskDifficultyFilter == 'medium',
                  onSelected: (sel) {
                    if (!sel) return;
                    setState(() {
                      _taskDifficultyFilter = 'medium';
                    });
                  },
                ),
                ChoiceChip(
                  label: const Text('Hard'),
                  selected: _taskDifficultyFilter == 'hard',
                  onSelected: (sel) {
                    if (!sel) return;
                    setState(() {
                      _taskDifficultyFilter = 'hard';
                    });
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
                  DataColumn(label: Text('Difficulty')),
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
                      DataCell(Text(r.taskDifficulty ?? '-')),
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
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text('Report archived'),
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
                                child: const Text('Archive'),
                              )
                            else
                              TextButton(
                                onPressed: () async {
                                  try {
                                    await ReportService().restoreReport(r.id);
                                    await _fetchTaskReports();
                                    if (mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text('Report restored'),
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
      final recordsToExport = _filteredAttendanceRecords;

      if (recordsToExport.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No attendance records to export for selected filters',
            ),
          ),
        );
        return;
      }

      DateTime? inclusiveStart;
      DateTime? inclusiveEnd;

      if (_attendanceStartDate != null || _attendanceEndDate != null) {
        inclusiveStart = _attendanceStartDate;
        if (_attendanceEndDate != null) {
          inclusiveEnd = _attendanceEndDate!.subtract(const Duration(days: 1));
        }
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ReportExportPreviewScreen(
            records: recordsToExport,
            reportType: _viewMode,
            taskReports: _filteredTaskReports(),
            startDate: inclusiveStart,
            endDate: inclusiveEnd,
            locationFilter: _filterLocation != 'All Locations'
                ? _filterLocation
                : null,
            statusFilter: _filterStatus != 'All Status' ? _filterStatus : null,
            employeeIdFilter: _filterEmployeeId,
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
