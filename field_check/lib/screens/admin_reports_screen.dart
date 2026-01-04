// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:field_check/services/geofence_service.dart';
import 'package:field_check/services/report_service.dart';
import 'package:field_check/models/report_model.dart';
import 'package:field_check/services/attendance_service.dart';
import 'package:intl/intl.dart';
import 'package:field_check/config/api_config.dart';
import 'package:field_check/services/user_service.dart';
import 'package:field_check/screens/report_export_preview_screen.dart';
import 'package:field_check/screens/admin_employee_history_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';

class AdminReportsScreen extends StatefulWidget {
  final String? employeeId;

  const AdminReportsScreen({super.key, this.employeeId});

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> {
  List<ReportModel> _attendanceRecords = [];
  List<ReportModel> _archivedAttendanceRecords = [];
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

  final AttendanceService _attendanceService = AttendanceService();
  Set<String> _locallyArchivedAttendanceIds = <String>{};

  static const String _prefsArchivedAttendanceIdsKey =
      'adminReports.archivedAttendanceIds.v1';

  Future<void> _loadLocallyArchivedAttendanceIds() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_prefsArchivedAttendanceIdsKey) ?? <String>[];
    setState(() {
      _locallyArchivedAttendanceIds = list.toSet();
    });
  }

  String _normalizeAttachmentUrl(String rawPath) {
    final p = rawPath.trim();
    if (p.isEmpty) return p;
    if (p.startsWith('http://') || p.startsWith('https://')) return p;
    if (p.startsWith('/')) return '${ApiConfig.baseUrl}$p';
    return '${ApiConfig.baseUrl}/$p';
  }

  String _ensureUrlEncoded(String url) {
    try {
      var uri = Uri.parse(url);
      if (uri.host.isEmpty) return url;
      // Encode each path segment (handles spaces and special chars in filenames)
      uri = uri.replace(
        pathSegments: uri.pathSegments.map(Uri.encodeComponent).toList(),
      );
      return uri.toString();
    } catch (_) {
      return url;
    }
  }

  bool _isImagePath(String url) {
    final lower = url.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.gif');
  }

  String _filenameFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final segs = uri.pathSegments;
      if (segs.isEmpty) return url;
      return Uri.decodeComponent(segs.last);
    } catch (_) {
      return url;
    }
  }

  Future<void> _openUrlExternal(String url) async {
    final safeUrl = _ensureUrlEncoded(url);
    Uri uri;
    try {
      uri = Uri.parse(safeUrl);
      if (uri.host.isEmpty) {
        throw const FormatException('Invalid URL');
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Invalid attachment URL'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
      return;
    }

    // Keep URL encoded; decoding path segments can break URLs with spaces.

    final can = await canLaunchUrl(uri);
    if (!can) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('No app found to open attachment'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
      return;
    }

    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Unable to open attachment'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  void _showImagePreview(String title, String url) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(
                  bottom: BorderSide(
                    color: Theme.of(context).dividerColor.withValues(alpha: 0.35),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Open',
                    onPressed: () => _openUrlExternal(url),
                    icon: const Icon(Icons.open_in_new),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Flexible(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 5,
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stack) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('Failed to load image: $error'),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _setAttendanceArchivedLocal(String attendanceId, bool archived) async {
    final prefs = await SharedPreferences.getInstance();
    final next = _locallyArchivedAttendanceIds.toSet();
    if (archived) {
      next.add(attendanceId);
    } else {
      next.remove(attendanceId);
    }
    await prefs.setStringList(_prefsArchivedAttendanceIdsKey, next.toList());
    setState(() {
      _locallyArchivedAttendanceIds = next;
    });
    await _fetchAttendanceRecords();
  }

  ReportModel _attendanceToReportModel(AttendanceRecord r) {
    final DateTime submittedAt = r.isCheckIn ? r.checkInTime : (r.checkOutTime ?? r.checkInTime);

    final String content;
    if (r.isVoid && r.autoCheckout) {
      content = 'Auto Checkout (Void)';
    } else if (r.isVoid) {
      content = 'Void';
    } else {
      content = r.isCheckIn ? 'Check In' : 'Check Out';
    }

    return ReportModel(
      id: r.id,
      type: 'attendance',
      attendanceId: r.id,
      employeeId: r.userId,
      geofenceId: r.geofenceId,
      content: content,
      status: 'submitted',
      submittedAt: submittedAt,
      employeeName: r.employeeName,
      employeeEmail: r.employeeEmail,
      geofenceName: r.geofenceName,
      isArchived: _locallyArchivedAttendanceIds.contains(r.id),
    );
  }

  Future<void> _openFiltersSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateSheet) {
            Widget buildAttendanceFilters() {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ChoiceChip(
                        label: const Text('Current'),
                        selected: !_showArchivedAttendance,
                        onSelected: (sel) {
                          if (!sel) return;
                          setStateSheet(() {
                            _showArchivedAttendance = false;
                          });
                          _fetchAttendanceRecords();
                        },
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('Archived'),
                        selected: _showArchivedAttendance,
                        onSelected: (sel) {
                          if (!sel) return;
                          setStateSheet(() {
                            _showArchivedAttendance = true;
                          });
                          _fetchAttendanceRecords();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
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
                  const SizedBox(height: 12),
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
                          setStateSheet(() {});
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
                          setStateSheet(() {});
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
                          setStateSheet(() {});
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
                          setStateSheet(() {});
                        },
                      ),
                    ],
                  ),
                ],
              );
            }

            Widget buildTaskFilters() {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ChoiceChip(
                        label: const Text('Current'),
                        selected: !_showArchivedReports,
                        onSelected: (sel) async {
                          if (!sel) return;
                          setStateSheet(() {
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
                          setStateSheet(() {
                            _showArchivedReports = true;
                          });
                          await _fetchTaskReports();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
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
                          setStateSheet(() {});
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
                          setStateSheet(() {});
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
                          setStateSheet(() {});
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
                          setStateSheet(() {});
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
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
                          setStateSheet(() {});
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
                          setStateSheet(() {});
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
                          setStateSheet(() {});
                        },
                      ),
                    ],
                  ),
                ],
              );
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 8,
                  bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Filters',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _attendanceDateFilter = 'all';
                              _attendanceStartDate = null;
                              _attendanceEndDate = null;
                              _filterDate = 'All Dates';
                              _attendanceStatusFilter = 'All';
                              _reportStatusFilter = 'All';
                              _taskDifficultyFilter = 'All';
                            });
                            setStateSheet(() {});
                            _fetchAttendanceRecords();
                            _fetchTaskReports();
                          },
                          child: const Text('Reset'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_viewMode == 'attendance') buildAttendanceFilters() else buildTaskFilters(),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Done'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    // Set employee filter if provided
    if (widget.employeeId != null) {
      _filterEmployeeId = widget.employeeId;
    }
    _loadLocallyArchivedAttendanceIds();
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
      // ignore: unused_local_variable
      final _ = geofences;
    } catch (e) {
      debugPrint('Error fetching geofences: $e');
    }
  }

  Future<void> _fetchAttendanceRecords() async {
    try {
      debugPrint(
        'Fetching attendance records with filters: date=$_filterDate, location=$_filterLocation, status=$_filterStatus',
      );
      final records = await _attendanceService.getAttendanceRecords(
        employeeId: _filterEmployeeId,
      );
      final adapted = records.map(_attendanceToReportModel).toList();
      final current = adapted.where((r) => !_locallyArchivedAttendanceIds.contains(r.id)).toList();
      final archived = adapted.where((r) => _locallyArchivedAttendanceIds.contains(r.id)).toList();

      debugPrint('✓ Fetched ${adapted.length} attendance records (current=${current.length}, archived=${archived.length})');
      setState(() {
        _attendanceRecords = current;
        _archivedAttendanceRecords = archived;
      });
    } catch (e) {
      debugPrint('✗ Error fetching attendance records: $e');
      setState(() {
        _attendanceRecords = [];
        _archivedAttendanceRecords = [];
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
    final Map<String, List<ReportModel>> recordsByEmployee = {};

    for (final record in _attendanceRecords) {
      final employeeId = record.employeeId;
      recordsByEmployee.putIfAbsent(employeeId, () => []);
      recordsByEmployee[employeeId]!.add(record);
    }

    // Count employees who only have check-in but no check-out (incomplete day)
    int incompleteCount = 0;
    for (final records in recordsByEmployee.values) {
      final hasCheckIn = records.any((r) => r.content.toLowerCase().contains('check in'));
      final hasCheckOut = records.any((r) => r.content.toLowerCase().contains('check out'));

      // If employee has check-in but no check-out, they didn't complete their day
      if (hasCheckIn && !hasCheckOut) {
        incompleteCount++;
      }
    }

    return incompleteCount;
  }

  List<ReportModel> get _filteredAttendanceRecords {
    final base = _showArchivedAttendance
        ? _archivedAttendanceRecords
        : _attendanceRecords;

    Iterable<ReportModel> result = base;

    if (_attendanceStartDate != null || _attendanceEndDate != null) {
      result = result.where((record) {
        final dt = record.submittedAt.toLocal();

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
          return !record.content.toLowerCase().contains('void');
        case 'Void':
          return record.content.toLowerCase().contains('void') && 
                 !record.content.toLowerCase().contains('auto');
        case 'Auto':
          return record.content.toLowerCase().contains('void') && 
                 record.content.toLowerCase().contains('auto');
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
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  foregroundColor: Theme.of(context).colorScheme.error,
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
                backgroundColor: Theme.of(context).colorScheme.surface,
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
                                Padding(
                                  padding: EdgeInsets.only(left: 6.0),
                                  child: SizedBox(
                                    width: 8,
                                    height: 8,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).colorScheme.error,
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

                    Row(
                      children: [
                        FilledButton.icon(
                          onPressed: _openFiltersSheet,
                          icon: const Icon(Icons.tune),
                          label: const Text('Filters'),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _viewMode == 'attendance'
                                ? 'Showing: ${_showArchivedAttendance ? 'Archived' : 'Current'} • $_filterDate • $_attendanceStatusFilter'
                                : 'Showing: ${_showArchivedReports ? 'Archived' : 'Current'} • $_taskDifficultyFilter • $_reportStatusFilter',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),

                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text(
                        'Quick filters',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      childrenPadding: const EdgeInsets.only(bottom: 8),
                      children: [
                        if (_viewMode == 'attendance')
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ChoiceChip(
                                label: const Text('Current'),
                                selected: !_showArchivedAttendance,
                                onSelected: (sel) {
                                  if (!sel) return;
                                  setState(() {
                                    _showArchivedAttendance = false;
                                  });
                                  _fetchAttendanceRecords();
                                },
                              ),
                              ChoiceChip(
                                label: const Text('Archived'),
                                selected: _showArchivedAttendance,
                                onSelected: (sel) {
                                  if (!sel) return;
                                  setState(() {
                                    _showArchivedAttendance = true;
                                  });
                                  _fetchAttendanceRecords();
                                },
                              ),
                              ChoiceChip(
                                label: const Text('All time'),
                                selected: _attendanceDateFilter == 'all',
                                onSelected: (sel) {
                                  if (!sel) return;
                                  _setAttendanceQuickDateFilter('all');
                                },
                              ),
                              ChoiceChip(
                                label: const Text('Today'),
                                selected: _attendanceDateFilter == 'today',
                                onSelected: (sel) {
                                  if (!sel) return;
                                  _setAttendanceQuickDateFilter('today');
                                },
                              ),
                              ChoiceChip(
                                label: const Text('This week'),
                                selected: _attendanceDateFilter == 'week',
                                onSelected: (sel) {
                                  if (!sel) return;
                                  _setAttendanceQuickDateFilter('week');
                                },
                              ),
                              ChoiceChip(
                                label: const Text('This month'),
                                selected: _attendanceDateFilter == 'month',
                                onSelected: (sel) {
                                  if (!sel) return;
                                  _setAttendanceQuickDateFilter('month');
                                },
                              ),
                            ],
                          )
                        else
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
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
                              color: Theme.of(context).colorScheme.tertiary,
                            ),
                          ),
                        ],
                      ),

                    if (_viewMode == 'attendance') const SizedBox(height: 12),

                    if (_viewMode == 'attendance')
                      (!_showArchivedAttendance
                                  ? _attendanceRecords.isEmpty
                                  : _archivedAttendanceRecords.isEmpty)
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
                                          DataColumn(label: Text('Time')),
                                          DataColumn(label: Text('Status')),
                                          DataColumn(label: Text('Actions')),
                                        ],
                                        rows: _filteredAttendanceRecords.map((
                                          record,
                                        ) {
                                          final time = formatTime(
                                            record.submittedAt,
                                          );
                                          String status;
                                          Color? chipBg;
                                          Color? chipFg;

                                          if (record.content.toLowerCase().contains('void') &&
                                              record.content.toLowerCase().contains('auto')) {
                                            status = 'Auto Checkout (Void)';
                                            chipBg = Theme.of(context)
                                                .colorScheme
                                                .error
                                                .withValues(alpha: 0.12);
                                            chipFg = Theme.of(context).colorScheme.error;
                                          } else if (record.content.toLowerCase().contains('void')) {
                                            status = 'Void';
                                            chipBg = Theme.of(context)
                                                .colorScheme
                                                .onSurface
                                                .withValues(alpha: 0.12);
                                            chipFg = Theme.of(context)
                                                .colorScheme
                                                .onSurface
                                                .withValues(alpha: 0.85);
                                          } else if (record.content.toLowerCase().contains('check in')) {
                                            status = 'Checked In';
                                            chipBg = Theme.of(context)
                                                .colorScheme
                                                .primary
                                                .withValues(alpha: 0.12);
                                            chipFg = Theme.of(context).colorScheme.primary;
                                          } else {
                                            status = 'Checked Out';
                                            chipBg = Theme.of(context)
                                                .colorScheme
                                                .secondary
                                                .withValues(alpha: 0.12);
                                            chipFg = Theme.of(context).colorScheme.secondary;
                                          }
                                          final date = record.submittedAt
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
                                                Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    IconButton(
                                                      icon: const Icon(Icons.history),
                                                      tooltip: 'View history for this employee',
                                                      onPressed: () {
                                                        final employeeId = record.employeeId;
                                                        Navigator.push(
                                                          context,
                                                          MaterialPageRoute(
                                                            builder: (context) =>
                                                                AdminEmployeeHistoryScreen(
                                                              employeeId: employeeId,
                                                              employeeName: record.employeeName ??
                                                                  'Unknown',
                                                            ),
                                                          ),
                                                        );
                                                      },
                                                    ),
                                                    IconButton(
                                                      icon: Icon(
                                                        _showArchivedAttendance
                                                            ? Icons.unarchive
                                                            : Icons.archive,
                                                      ),
                                                      tooltip: _showArchivedAttendance
                                                          ? 'Restore (remove from archive)'
                                                          : 'Archive (hide from current)',
                                                      onPressed: () async {
                                                        await _setAttendanceArchivedLocal(
                                                          record.id,
                                                          !_showArchivedAttendance,
                                                        );
                                                      },
                                                    ),
                                                  ],
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
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.7),
              ),
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
              if (r.content.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text(
                  'Content',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(context).dividerColor.withValues(alpha: 0.35),
                    ),
                  ),
                  child: SelectableText(
                    r.content,
                    style: const TextStyle(fontSize: 13, height: 1.35),
                  ),
                ),
              ],
              if (r.attachments.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text(
                  'Attachments:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: r.attachments.map((rawPath) {
                    final normalized = _normalizeAttachmentUrl(rawPath);
                    final url = _ensureUrlEncoded(normalized);
                    final filename = _filenameFromUrl(url);
                    final isImage = _isImagePath(url);

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: InkWell(
                        onTap: () {
                          if (isImage) {
                            _showImagePreview(filename, url);
                          } else {
                            _openUrlExternal(url);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Theme.of(context).dividerColor.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isImage ? Icons.image : Icons.insert_drive_file,
                                color: isImage
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.8),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      filename,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      url,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.7),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (isImage)
                                IconButton(
                                  tooltip: 'Preview',
                                  onPressed: () => _showImagePreview(filename, url),
                                  icon: const Icon(Icons.visibility),
                                ),
                              IconButton(
                                tooltip: 'Copy link',
                                onPressed: () async {
                                  await Clipboard.setData(ClipboardData(text: url));
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Link copied')),
                                  );
                                },
                                icon: const Icon(Icons.copy),
                              ),
                              IconButton(
                                tooltip: 'Open',
                                onPressed: () => _openUrlExternal(url),
                                icon: const Icon(Icons.open_in_new),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
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

  Color _reportStatusBg(String status) {
    final s = status.toLowerCase();
    if (s == 'reviewed') {
      return Theme.of(context).colorScheme.primary.withValues(alpha: 0.12);
    }
    if (s == 'submitted') {
      return Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.14);
    }
    return Theme.of(context).colorScheme.surface;
  }

  Color _reportStatusFg(String status) {
    final s = status.toLowerCase();
    if (s == 'reviewed') return Theme.of(context).colorScheme.primary;
    if (s == 'submitted') return Theme.of(context).colorScheme.tertiary;
    return Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.85);
  }

  Widget _buildReportStatusChip(String status) {
    return Chip(
      label: Text(status),
      backgroundColor: _reportStatusBg(status),
      labelStyle: TextStyle(color: _reportStatusFg(status)),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }

  String _contentPreview(String content, {int maxChars = 140}) {
    final c = content.trim();
    if (c.isEmpty) return '-';
    if (c.length <= maxChars) return c;
    return '${c.substring(0, maxChars)}…';
  }

  Future<void> _confirmAndDeleteReport(ReportModel r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Report'),
        content: const Text('Are you sure you want to delete this report?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await ReportService().deleteReport(r.id);
      await _fetchTaskReports();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Report deleted')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    }
  }

  Future<void> _markReportReviewed(ReportModel r) async {
    try {
      await ReportService().updateReportStatus(r.id, 'reviewed');
      await _fetchTaskReports();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Marked as reviewed')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    }
  }

  Future<void> _toggleArchiveReport(ReportModel r) async {
    try {
      if (_showArchivedReports) {
        await ReportService().restoreReport(r.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Report restored')),
          );
        }
      } else {
        await ReportService().archiveReport(r.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Report archived')),
          );
        }
      }
      await _fetchTaskReports();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    }
  }

  Widget _buildTaskReportCard(ReportModel r) {
    final submitted = DateFormat('yyyy-MM-dd HH:mm').format(r.submittedAt.toLocal());
    final attachmentCount = r.attachments.length;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.35),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showReportDetails(r),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.taskTitle ?? (r.taskId ?? 'Task'),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          r.employeeName ?? r.employeeId,
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.7),
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  PopupMenuButton<String>(
                    tooltip: 'Actions',
                    onSelected: (value) {
                      switch (value) {
                        case 'view':
                          _showReportDetails(r);
                          return;
                        case 'review':
                          _markReportReviewed(r);
                          return;
                        case 'archive':
                          _toggleArchiveReport(r);
                          return;
                        case 'delete':
                          _confirmAndDeleteReport(r);
                          return;
                      }
                    },
                    itemBuilder: (ctx) => <PopupMenuEntry<String>>[
                      const PopupMenuItem(
                        value: 'view',
                        child: Text('View details'),
                      ),
                      if (r.status.toLowerCase() != 'reviewed')
                        const PopupMenuItem(
                          value: 'review',
                          child: Text('Mark as reviewed'),
                        ),
                      PopupMenuItem(
                        value: 'archive',
                        child: Text(_showArchivedReports ? 'Restore' : 'Archive'),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _buildReportStatusChip(r.status),
                  if ((r.taskDifficulty ?? '').isNotEmpty)
                    Chip(
                      label: Text(r.taskDifficulty!),
                      backgroundColor: Theme.of(context).colorScheme.surface,
                      labelStyle: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.85),
                      ),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  Chip(
                    label: Text(submitted),
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    labelStyle: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.85),
                    ),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  Chip(
                    label: Text('Attachments: $attachmentCount'),
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    labelStyle: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.85),
                    ),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                _contentPreview(r.content),
                style: const TextStyle(fontSize: 13, height: 1.35),
              ),
            ],
          ),
        ),
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
              Icon(
                Icons.error_outline,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                _taskReportsError!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
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
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _filteredTaskReports().length,
              itemBuilder: (context, index) {
                final r = _filteredTaskReports()[index];
                return _buildTaskReportCard(r);
              },
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
