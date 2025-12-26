import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:field_check/services/attendance_service.dart';
import 'package:field_check/screens/report_export_preview_screen.dart';
import 'package:field_check/models/report_model.dart';

class AdminEmployeeHistoryScreen extends StatefulWidget {
  final String employeeId;
  final String employeeName;

  const AdminEmployeeHistoryScreen({
    super.key,
    required this.employeeId,
    required this.employeeName,
  });

  @override
  State<AdminEmployeeHistoryScreen> createState() =>
      _AdminEmployeeHistoryScreenState();
}

class _AdminEmployeeHistoryScreenState
    extends State<AdminEmployeeHistoryScreen> {
  final AttendanceService _attendanceService = AttendanceService();
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  String? _error;
  List<AttendanceRecord> _allRecords = [];
  String _searchQuery = '';
  final Set<String> _expandedMonths = <String>{};
  String _dateFilter = 'all'; // all, today, week, month, custom
  DateTime? _startDateFilter;
  DateTime? _endDateFilter;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final records = await _attendanceService.getAttendanceRecords(
        employeeId: widget.employeeId,
      );
      setState(() {
        _allRecords = records;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  List<AttendanceRecord> get _filteredRecords {
    Iterable<AttendanceRecord> base = _allRecords;

    if (_startDateFilter != null || _endDateFilter != null) {
      base = base.where((record) {
        final dt = record.timestamp.toLocal();

        if (_startDateFilter != null && dt.isBefore(_startDateFilter!)) {
          return false;
        }
        if (_endDateFilter != null && !dt.isBefore(_endDateFilter!)) {
          return false;
        }
        return true;
      });
    }

    final List<AttendanceRecord> dateFiltered = base.toList();

    if (_searchQuery.trim().isEmpty) return dateFiltered;
    final q = _searchQuery.toLowerCase();

    return dateFiltered.where((record) {
      final dt = record.timestamp.toLocal();
      final dateStr = DateFormat('yyyy-MM-dd').format(dt);
      final timeStr = TimeOfDay.fromDateTime(dt).format(context);
      final locationName = record.geofenceName ?? 'Unknown location';
      final typeLabel = record.isCheckIn ? 'Check-in' : 'Check-out';

      final parts = <String>[dateStr, timeStr, locationName, typeLabel];

      if (record.isVoid) {
        parts.add('void');
        if (record.autoCheckout) {
          parts.add('auto');
          parts.add('auto checkout');
        }
      }
      if (record.voidReason != null) {
        parts.add(record.voidReason!);
      }

      final haystack = parts.join(' ').toLowerCase();
      return haystack.contains(q);
    }).toList();
  }

  Map<String, List<AttendanceRecord>> _groupByMonth(
    List<AttendanceRecord> records,
  ) {
    final Map<String, List<AttendanceRecord>> grouped = {};

    for (final record in records) {
      final dt = record.timestamp.toLocal();
      final key = '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
      grouped.putIfAbsent(key, () => <AttendanceRecord>[]).add(record);
    }

    for (final list in grouped.values) {
      list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    }

    return grouped;
  }

  void _setQuickDateFilter(String value) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);

    DateTime? start;
    DateTime? endExclusive;

    switch (value) {
      case 'today':
        start = todayStart;
        endExclusive = todayStart.add(const Duration(days: 1));
        break;
      case 'week':
        final weekday = todayStart.weekday; // Monday = 1
        start = todayStart.subtract(Duration(days: weekday - 1));
        endExclusive = start.add(const Duration(days: 7));
        break;
      case 'month':
        start = DateTime(todayStart.year, todayStart.month, 1);
        final nextMonth = todayStart.month == 12
            ? DateTime(todayStart.year + 1, 1, 1)
            : DateTime(todayStart.year, todayStart.month + 1, 1);
        endExclusive = nextMonth;
        break;
      case 'all':
      default:
        start = null;
        endExclusive = null;
        break;
    }

    setState(() {
      _dateFilter = value;
      _startDateFilter = start;
      _endDateFilter = endExclusive;
    });
  }

  Future<void> _pickCustomDateRange() async {
    final now = DateTime.now();
    final baseStart = _startDateFilter ?? DateTime(now.year, now.month, 1);
    final baseEnd = _endDateFilter != null
        ? _endDateFilter!.subtract(const Duration(days: 1))
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
      _dateFilter = 'custom';
      _startDateFilter = start;
      _endDateFilter = endExclusive;
    });
  }

  void _showRecordInfo(AttendanceRecord record) {
    final dt = record.timestamp.toLocal();
    final dateStr = DateFormat('yyyy-MM-dd').format(dt);
    final timeStr = TimeOfDay.fromDateTime(dt).format(context);
    final locationName = record.geofenceName ?? 'Unknown location';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Attendance Details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Employee: ${widget.employeeName}'),
            const SizedBox(height: 4),
            Text('Date: $dateStr'),
            Text('Time: $timeStr'),
            const SizedBox(height: 8),
            Text('Location: $locationName'),
            const SizedBox(height: 8),
            Text('Type: ${record.isCheckIn ? 'Check-in' : 'Check-out'}'),
            if (record.isVoid) ...[
              const SizedBox(height: 8),
              const Text('Status: VOID'),
              if (record.autoCheckout)
                const Text('Reason: Auto checkout (offline too long)'),
              if (record.voidReason != null)
                Text('Details: ${record.voidReason}'),
            ],
          ],
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

  Widget _buildRecordTile(AttendanceRecord record) {
    final dt = record.timestamp.toLocal();
    final dateStr = DateFormat('yyyy-MM-dd').format(dt);
    final timeStr = TimeOfDay.fromDateTime(dt).format(context);
    final locationName = record.geofenceName ?? 'Unknown location';
    final typeLabel = record.isCheckIn ? 'Check-in' : 'Check-out';

    Color chipBg;
    Color chipFg;

    if (record.isVoid && record.autoCheckout) {
      chipBg = Colors.red.shade100;
      chipFg = Colors.red.shade900;
    } else if (record.isVoid) {
      chipBg = Colors.grey.shade300;
      chipFg = Colors.grey.shade900;
    } else if (record.isCheckIn) {
      chipBg = Colors.green.shade100;
      chipFg = Colors.green.shade900;
    } else {
      chipBg = Colors.red.shade100;
      chipFg = Colors.red.shade900;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(dateStr, style: const TextStyle(fontWeight: FontWeight.bold)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: chipBg,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                typeLabel,
                style: TextStyle(color: chipFg, fontSize: 12),
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.access_time, size: 16),
                const SizedBox(width: 4),
                Text(timeStr),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.location_on, size: 16),
                const SizedBox(width: 4),
                Expanded(child: Text(locationName)),
              ],
            ),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.info_outline),
          tooltip: 'Details',
          onPressed: () => _showRecordInfo(record),
        ),
      ),
    );
  }

  Future<void> _exportHistoryForEmployee() async {
    final recordsToExport = _filteredRecords.map((record) => ReportModel(
      id: record.id,
      type: 'attendance',
      attendanceId: record.id,
      employeeId: record.userId,
      content: record.isCheckIn ? 'Check In' : 'Check Out',
      status: record.isVoid ? 'void' : 'submitted',
      submittedAt: record.timestamp,
      employeeName: widget.employeeName,
      geofenceName: record.geofenceName,
    )).toList();

    if (recordsToExport.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No attendance history to export for selected range'),
        ),
      );
      return;
    }

    DateTime? inclusiveStart;
    DateTime? inclusiveEnd;

    if (_startDateFilter != null || _endDateFilter != null) {
      inclusiveStart = _startDateFilter;
      if (_endDateFilter != null) {
        inclusiveEnd = _endDateFilter!.subtract(const Duration(days: 1));
      }
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ReportExportPreviewScreen(
          records: recordsToExport,
          reportType: 'attendance',
          employeeIdFilter: widget.employeeId,
          startDate: inclusiveStart,
          endDate: inclusiveEnd,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredRecords;
    final int totalCount = filtered.length;
    final int normalCount = filtered.where((r) => !r.isVoid).length;
    final int voidCount = filtered
        .where((r) => r.isVoid && !r.autoCheckout)
        .length;
    final int autoCount = filtered
        .where((r) => r.isVoid && r.autoCheckout)
        .length;
    final bool showSummary =
        !_isLoading && _error == null && filtered.isNotEmpty;
    final bool hasVoidOrAuto = _allRecords.any(
      (r) => r.isVoid || r.autoCheckout,
    );

    int daysTotal = 0;
    int daysComplete = 0;
    int daysIncomplete = 0;
    int daysVoidOnly = 0;

    if (showSummary) {
      final Map<String, List<AttendanceRecord>> byDay = {};
      for (final record in filtered) {
        final dt = record.timestamp.toLocal();
        final key = DateFormat('yyyy-MM-dd').format(dt);
        byDay.putIfAbsent(key, () => <AttendanceRecord>[]).add(record);
      }

      daysTotal = byDay.length;

      for (final dayRecords in byDay.values) {
        final hasNonVoidCheckIn = dayRecords.any(
          (r) => !r.isVoid && r.isCheckIn,
        );
        final hasNonVoidCheckOut = dayRecords.any(
          (r) => !r.isVoid && !r.isCheckIn,
        );
        final hasNonVoid = dayRecords.any((r) => !r.isVoid);
        final allVoidOrAuto = dayRecords.isNotEmpty && !hasNonVoid;

        if (allVoidOrAuto) {
          daysVoidOnly++;
        } else if (hasNonVoidCheckIn && hasNonVoidCheckOut) {
          daysComplete++;
        } else if (hasNonVoidCheckIn && !hasNonVoidCheckOut) {
          daysIncomplete++;
        }
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('History - ${widget.employeeName}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Export history',
            onPressed: _exportHistoryForEmployee,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  labelText: 'Search history',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            setState(() {
                              _searchQuery = '';
                              _searchController.clear();
                            });
                          },
                        )
                      : null,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ChoiceChip(
                      label: const Text('All time'),
                      selected: _dateFilter == 'all',
                      onSelected: (selected) {
                        if (!selected) return;
                        _setQuickDateFilter('all');
                      },
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('Today'),
                      selected: _dateFilter == 'today',
                      onSelected: (selected) {
                        if (!selected) return;
                        _setQuickDateFilter('today');
                      },
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('This week'),
                      selected: _dateFilter == 'week',
                      onSelected: (selected) {
                        if (!selected) return;
                        _setQuickDateFilter('week');
                      },
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('This month'),
                      selected: _dateFilter == 'month',
                      onSelected: (selected) {
                        if (!selected) return;
                        _setQuickDateFilter('month');
                      },
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('Custom'),
                      selected: _dateFilter == 'custom',
                      onSelected: (selected) async {
                        if (!selected) return;
                        await _pickCustomDateRange();
                      },
                    ),
                  ],
                ),
              ),
            ),
            if (showSummary) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  children: [
                    _buildSummaryItem('Total', totalCount, Colors.blue),
                    const SizedBox(width: 8),
                    _buildSummaryItem('Normal', normalCount, Colors.green),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  children: [
                    _buildSummaryItem('Void', voidCount, Colors.grey),
                    const SizedBox(width: 8),
                    _buildSummaryItem('Auto checkout', autoCount, Colors.red),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  children: [
                    _buildSummaryItem('Days', daysTotal, Colors.blueGrey),
                    const SizedBox(width: 8),
                    _buildSummaryItem(
                      'Complete days',
                      daysComplete,
                      Colors.green,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  children: [
                    _buildSummaryItem(
                      'Incomplete days',
                      daysIncomplete,
                      Colors.orange,
                    ),
                    const SizedBox(width: 8),
                    _buildSummaryItem(
                      'Void/auto-only days',
                      daysVoidOnly,
                      Colors.red,
                    ),
                  ],
                ),
              ),
            ],
            if (hasVoidOrAuto)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, size: 16, color: Colors.orange),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Note: Entries marked as VOID or Auto checkout were either cancelled by an admin or automatically checked out when the employee\'s device was offline for too long. These entries may be excluded from normal attendance totals.',
                          style: TextStyle(fontSize: 12, color: Colors.black87),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Error loading history: $_error'),
                            const SizedBox(height: 8),
                            ElevatedButton(
                              onPressed: _loadHistory,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : _filteredRecords.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text('No attendance history available.'),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadHistory,
                      child: Builder(
                        builder: (context) {
                          final grouped = _groupByMonth(_filteredRecords);
                          final monthKeys = grouped.keys.toList()
                            ..sort((a, b) => b.compareTo(a));

                          return ListView.builder(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            itemCount: monthKeys.length,
                            itemBuilder: (context, index) {
                              final key = monthKeys[index];
                              final list = grouped[key] ?? <AttendanceRecord>[];
                              if (list.isEmpty) {
                                return const SizedBox.shrink();
                              }

                              final parts = key.split('-');
                              final year = int.parse(parts[0]);
                              final month = int.parse(parts[1]);
                              final label = DateFormat(
                                'MMMM yyyy',
                              ).format(DateTime(year, month));

                              final isExpanded = _expandedMonths.contains(key);

                              return Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                child: ExpansionTile(
                                  initiallyExpanded: isExpanded,
                                  onExpansionChanged: (expanded) {
                                    setState(() {
                                      if (expanded) {
                                        _expandedMonths.add(key);
                                      } else {
                                        _expandedMonths.remove(key);
                                      }
                                    });
                                  },
                                  title: Text(
                                    label,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  children: list.map(_buildRecordTile).toList(),
                                ),
                              );
                            },
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

  Widget _buildSummaryItem(String label, int value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value.toString(),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
