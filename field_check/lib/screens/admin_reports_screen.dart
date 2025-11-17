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
  String _viewMode = 'attendance'; // 'attendance' | 'task'
  bool _hasNewTaskReports = false;

  String _filterDate = 'All Dates';
  String _filterLocation = 'All Locations';
  String _filterStatus = 'All Status';
  String _reportStatusFilter = 'All';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _fetchGeofences();
    _fetchAttendanceRecords();
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
    _socket.onConnectError((err) => debugPrint('Socket.IO Connect Error: $err'));
    _socket.onError((err) => debugPrint('Socket.IO Error: $err'));
    _socket.on('reconnect_attempt', (_) => debugPrint('Reports socket reconnect attempt'));
    _socket.on('reconnect', (_) => debugPrint('Reports socket reconnected'));
    _socket.on('reconnect_error', (err) => debugPrint('Reports socket reconnect error: $err'));
    _socket.on('reconnect_failed', (_) => debugPrint('Reports socket reconnect failed'));

    _socket.on('newAttendanceRecord', (data) {
      debugPrint('New attendance record: $data');
      _fetchAttendanceRecords();
    });

    _socket.on('updatedAttendanceRecord', (data) {
      debugPrint('Attendance record updated: $data');
      _fetchAttendanceRecords();
    });

    _socket.on('newReport', (_) {
      setState(() { _hasNewTaskReports = true; });
      if (_viewMode == 'task') {
        _fetchTaskReports();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('New report received')));
        }
        setState(() { _hasNewTaskReports = false; });
      }
    });

    _socket.on('updatedReport', (_) {
      if (_viewMode == 'task') {
        _fetchTaskReports();
      } else {
        setState(() { _hasNewTaskReports = true; });
      }
    });

    _socket.on('deletedReport', (_) {
      if (_viewMode == 'task') {
        _fetchTaskReports();
      } else {
        setState(() { _hasNewTaskReports = true; });
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
      final records = await AttendanceService().getAttendanceRecords(
        date: _filterDate != 'All Dates' ? DateTime.parse(_filterDate) : null,
        locationId: _filterLocation != 'All Locations'
            ? (_geofences.where((g) => g.name == _filterLocation).toList().isNotEmpty
                ? _geofences.where((g) => g.name == _filterLocation).toList().first.id
                : null)
            : null,
        status: _filterStatus != 'All Status' ? _filterStatus : null,
      );
      setState(() {
        _attendanceRecords = records;
      });
    } catch (e) {
      debugPrint('Error fetching attendance records: $e');
      // Optionally show an error message to the user
    }
  }

  Future<void> _fetchTaskReports() async {
    try {
      final reports = await ReportService().fetchReports(type: 'task');
      setState(() {
        _taskReports = reports;
      });
    } catch (e) {
      debugPrint('Error fetching task reports: $e');
    }
  }

  List<ReportModel> _filteredTaskReports() {
    if (_reportStatusFilter == 'All') return _taskReports;
    return _taskReports
        .where((r) => r.status.toLowerCase() == _reportStatusFilter.toLowerCase())
        .toList();
  }

  void _scheduleFetchAttendance() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _fetchAttendanceRecords();
    });
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
      ..._attendanceRecords.map((a) => a.isCheckIn ? 'Checked In' : 'Checked Out'),
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
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
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
                              setState(() { _viewMode = 'attendance'; });
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
                                        decoration: BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            selected: _viewMode == 'task',
                            onSelected: (sel) async {
                              if (!sel) return;
                              setState(() { _viewMode = 'task'; _hasNewTaskReports = false; });
                              await _fetchTaskReports();
                            },
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      if (_viewMode == 'attendance')
                        Card(
                          elevation: 2,
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Wrap(
                              spacing: 16,
                              runSpacing: 12,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                SizedBox(
                                  width: 220,
                                  child: _buildFilterDropdown(
                                    label: 'Date',
                                    value: _filterDate,
                                    items: dateItems,
                                    onChanged: (val) {
                                      if (val == null) return;
                                      setState(() { _filterDate = val; });
                                      _scheduleFetchAttendance();
                                    },
                                    onTap: () => _selectDate(context),
                                  ),
                                ),
                                SizedBox(
                                  width: 220,
                                  child: _buildFilterDropdown(
                                    label: 'Location',
                                    value: _filterLocation,
                                    items: locationItems,
                                    onChanged: (val) {
                                      if (val == null) return;
                                      setState(() { _filterLocation = val; });
                                      _scheduleFetchAttendance();
                                    },
                                  ),
                                ),
                                SizedBox(
                                  width: 220,
                                  child: _buildFilterDropdown(
                                    label: 'Status',
                                    value: _filterStatus,
                                    items: statusItems,
                                    onChanged: (val) {
                                      if (val == null) return;
                                      setState(() { _filterStatus = val; });
                                      _scheduleFetchAttendance();
                                    },
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: _fetchAttendanceRecords,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Refresh'),
                                ),
                              ],
                            ),
                          ),
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
                          ],
                        ),

                      if (_viewMode == 'attendance')
                        const SizedBox(height: 12),

                      Expanded(
                        child: _viewMode == 'attendance'
                            ? (_attendanceRecords.isEmpty
                                ? const Center(child: Text('No attendance records'))
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
                                                DataColumn(label: Text('Check In')),
                                                DataColumn(label: Text('Check Out')),
                                                DataColumn(label: Text('Status')),
                                                DataColumn(label: Text('Actions')),
                                              ],
                                              rows: _attendanceRecords.map((rec) {
                                                final dateStr =
                                                    DateFormat('yyyy-MM-dd').format(rec.timestamp.toLocal());
                                                return DataRow(
                                                  cells: [
                                                    DataCell(Text(rec.userId)),
                                                    DataCell(Text(rec.geofenceName ?? 'N/A')),
                                                    DataCell(Text(dateStr)),
                                                    DataCell(Text(rec.isCheckIn ? formatTime(rec.timestamp) : 'N/A')),
                                                    DataCell(Text(rec.isCheckIn ? 'N/A' : formatTime(rec.timestamp))),
                                                    DataCell(Text(rec.isCheckIn ? 'Checked In' : 'Checked Out')),
                                                    DataCell(
                                                      IconButton(
                                                        tooltip: 'Details',
                                                        icon: const Icon(Icons.info_outline),
                                                        onPressed: () => _showAttendanceDetails(rec),
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
                                  ))
                            : (_taskReports.isEmpty
                                ? const Center(child: Text('No task reports'))
                                : Card(
                                    elevation: 2,
                                    child: Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: [
                                              ChoiceChip(
                                                label: const Text('All'),
                                                selected: _reportStatusFilter == 'All',
                                                onSelected: (sel) {
                                                  if (!sel) return;
                                                  setState(() { _reportStatusFilter = 'All'; });
                                                },
                                              ),
                                              ChoiceChip(
                                                label: const Text('Submitted'),
                                                selected: _reportStatusFilter == 'submitted',
                                                onSelected: (sel) {
                                                  if (!sel) return;
                                                  setState(() { _reportStatusFilter = 'submitted'; });
                                                },
                                              ),
                                              ChoiceChip(
                                                label: const Text('Reviewed'),
                                                selected: _reportStatusFilter == 'reviewed',
                                                onSelected: (sel) {
                                                  if (!sel) return;
                                                  setState(() { _reportStatusFilter = 'reviewed'; });
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
                                                final submitted = DateFormat('yyyy-MM-dd HH:mm').format(r.submittedAt.toLocal());
                                                return DataRow(cells: [
                                                  DataCell(Text(r.employeeName ?? r.employeeId)),
                                                  DataCell(Text(r.taskTitle ?? (r.taskId ?? '-'))),
                                                  DataCell(Text(submitted)),
                                                  DataCell(Text(r.status)),
                                                  DataCell(Text(r.content)),
                                                  DataCell(Row(
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
                                                              await ReportService().updateReportStatus(r.id, 'reviewed');
                                                              await _fetchTaskReports();
                                                              if (mounted) {
                                                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Marked as reviewed')));
                                                              }
                                                            } catch (e) {
                                                              if (mounted) {
                                                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
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
                                                              content: const Text('Are you sure you want to delete this report?'),
                                                              actions: [
                                                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                                                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
                                                              ],
                                                            ),
                                                          );
                                                          if (ok == true) {
                                                            try {
                                                              await ReportService().deleteReport(r.id);
                                                              await _fetchTaskReports();
                                                              if (mounted) {
                                                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report deleted')));
                                                              }
                                                            } catch (e) {
                                                              if (mounted) {
                                                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
                                                              }
                                                            }
                                                          }
                                                        },
                                                        child: const Text('Delete'),
                                                      ),
                                                    ],
                                                  )),
                                                ]);
                                              }).toList(),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
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
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
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
                  child: Text(label == 'Date' && item != 'All Dates' ? DateFormat('yyyy-MM-dd').format(DateTime.parse(item)) : item),
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
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
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
        title: Text('${data.userId} - ${data.timestamp.toLocal().toString().split(' ')[0]}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow('Check In Time:', data.isCheckIn ? data.timestamp.toLocal().toString().split(' ')[1].substring(0, 5) : 'N/A'),
            _buildDetailRow('Check Out Time:', !data.isCheckIn ? data.timestamp.toLocal().toString().split(' ')[1].substring(0, 5) : 'N/A'),
          _buildDetailRow('Location:', data.geofenceName ?? 'N/A'),
            _buildDetailRow('Status:', data.isCheckIn ? 'Checked In' : 'Checked Out'),
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
              _buildDetailRow('Submitted:', DateFormat('yyyy-MM-dd HH:mm').format(r.submittedAt.toLocal())),
              if (r.content.isNotEmpty) _buildDetailRow('Content:', r.content),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
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
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }
}