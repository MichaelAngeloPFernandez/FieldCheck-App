import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:field_check/services/attendance_service.dart';
import 'package:field_check/services/realtime_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final AttendanceService _attendanceService = AttendanceService();
  final RealtimeService _realtimeService = RealtimeService();
  final TextEditingController _searchController = TextEditingController();
  StreamSubscription? _attendanceSub;

  bool _isLoading = true;
  String? _error;
  List<AttendanceRecord> _allRecords = [];
  String _searchQuery = '';
  final Set<String> _expandedMonths = <String>{};

  @override
  void initState() {
    super.initState();
    _loadHistory();
    // Expand the current month by default
    final now = DateTime.now();
    final currentMonthKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}';
    _expandedMonths.add(currentMonthKey);

    // Subscribe to realtime attendance updates and refresh history
    _attendanceSub = _realtimeService.attendanceStream.listen((event) {
      if (mounted) {
        _loadHistory();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _attendanceSub?.cancel();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final records = await _attendanceService.getAttendanceHistory();
      // Sort records by check-in time in descending order (latest first)
      records.sort((a, b) => b.checkInTime.compareTo(a.checkInTime));
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
    if (_searchQuery.trim().isEmpty) return _allRecords;
    final q = _searchQuery.toLowerCase();

    return _allRecords.where((record) {
      final dt = record.checkInTime.toLocal();
      final dateStr = DateFormat('yyyy-MM-dd').format(dt);
      final timeStr = TimeOfDay.fromDateTime(dt).format(context);
      final locationName = record.geofenceName ?? 'Unknown location';
      final typeLabel = record.status == 'out' ? 'Check-out' : 'Check-in';

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
      final dt = record.checkInTime.toLocal();
      final key = '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
      grouped.putIfAbsent(key, () => <AttendanceRecord>[]).add(record);
    }

    for (final list in grouped.values) {
      list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    }

    return grouped;
  }

  Future<void> _confirmDeleteRecord(AttendanceRecord record) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete Entry'),
            content: const Text(
              'Are you sure you want to delete this attendance entry?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    try {
      await _attendanceService.deleteMyAttendanceRecord(record.id);
      setState(() {
        _allRecords.removeWhere((r) => r.id == record.id);
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Entry deleted')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to delete entry: $e')));
      }
    }
  }

  Future<void> _confirmDeleteMonth(int year, int month, String monthKey) async {
    final label = DateFormat('MMMM yyyy').format(DateTime(year, month));

    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete Month History'),
            content: Text(
              'Delete all attendance entries for $label? This cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    try {
      final deletedCount = await _attendanceService
          .deleteMyAttendanceHistoryForMonth(year, month);

      if (deletedCount >= 0) {
        setState(() {
          _allRecords = _allRecords.where((record) {
            final dt = record.timestamp.toLocal();
            final key = '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
            return key != monthKey;
          }).toList();
          _expandedMonths.remove(monthKey);
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted $deletedCount entries for $label')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to delete month: $e')));
      }
    }
  }

  void _showRecordInfo(AttendanceRecord record) {
    final dtIn = record.checkInTime.toLocal();
    final dateStr = DateFormat('yyyy-MM-dd').format(dtIn);
    final timeInStr = TimeOfDay.fromDateTime(dtIn).format(context);

    String? timeOutStr;
    String? elapsedStr;
    if (record.checkOutTime != null) {
      final dtOut = record.checkOutTime!.toLocal();
      timeOutStr = TimeOfDay.fromDateTime(dtOut).format(context);
      if (record.elapsedHours != null) {
        final hours = record.elapsedHours!.toStringAsFixed(2);
        elapsedStr = '$hours hours';
      }
    }

    final locationName = record.geofenceName?.isNotEmpty ?? false
        ? record.geofenceName!
        : 'Unknown location';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Attendance Details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Date: $dateStr',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.login, size: 16, color: Colors.green),
                const SizedBox(width: 8),
                Text(
                  'Check-in: $timeInStr',
                  style: const TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            if (timeOutStr != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.logout, size: 16, color: Colors.red),
                  const SizedBox(width: 8),
                  Text(
                    'Check-out: $timeOutStr',
                    style: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
            if (elapsedStr != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  border: Border.all(color: Colors.purple.shade200),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.timer, size: 16, color: Colors.purple),
                    const SizedBox(width: 6),
                    Text(
                      'Duration: $elapsedStr',
                      style: const TextStyle(
                        color: Colors.purple,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text('Location: $locationName'),
            const SizedBox(height: 8),
            Text('Status: ${record.status == 'out' ? 'Completed' : 'Open'}'),
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
    final dtIn = record.checkInTime.toLocal();
    final dateStr = DateFormat('yyyy-MM-dd').format(dtIn);
    final timeInStr = TimeOfDay.fromDateTime(dtIn).format(context);
    final locationName = record.geofenceName ?? 'Unknown location';

    // Determine if completed (has checkout)
    final isCompleted = record.checkOutTime != null;
    final typeLabel = isCompleted ? 'Completed' : 'Checked In';

    Color chipBg;
    Color chipFg;

    if (record.isVoid && record.autoCheckout) {
      chipBg = Colors.red.shade100;
      chipFg = Colors.red.shade900;
    } else if (record.isVoid) {
      chipBg = Colors.grey.shade300;
      chipFg = Colors.grey.shade900;
    } else if (isCompleted) {
      chipBg = Colors.blue.shade100;
      chipFg = Colors.blue.shade900;
    } else {
      chipBg = Colors.green.shade100;
      chipFg = Colors.green.shade900;
    }

    // Format elapsed time - use actual values from backend
    String elapsedTimeStr = 'N/A';
    if (record.checkOutTime != null && record.elapsedHours != null) {
      final totalHours = record.elapsedHours!;
      final hours = totalHours.floor();
      final minutes = ((totalHours - hours) * 60).toInt();

      if (hours > 0) {
        elapsedTimeStr = '$hours h $minutes m';
      } else if (minutes > 0) {
        elapsedTimeStr = '$minutes m';
      } else {
        elapsedTimeStr = 'Just now';
      }
    } else if (record.checkOutTime != null && record.elapsedHours == null) {
      // If checkout exists but no elapsed hours, calculate it
      final duration = record.checkOutTime!.difference(record.checkInTime);
      final hours = duration.inHours;
      final minutes = duration.inMinutes.remainder(60);

      if (hours > 0) {
        elapsedTimeStr = '$hours h $minutes m';
      } else if (minutes > 0) {
        elapsedTimeStr = '$minutes m';
      } else {
        elapsedTimeStr = 'Just now';
      }
    }

    // Get checkout time if exists
    String? timeOutStr;
    if (record.checkOutTime != null) {
      timeOutStr = TimeOfDay.fromDateTime(
        record.checkOutTime!.toLocal(),
      ).format(context);
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
            // Check-in tag (GREEN)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                border: Border.all(color: Colors.green.shade200),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.login, size: 14, color: Colors.green),
                  const SizedBox(width: 4),
                  Text(
                    'Checked In: $timeInStr',
                    style: const TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            // Check-out tag (RED) - if exists, else show as not checked out
            if (timeOutStr != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  border: Border.all(color: Colors.red.shade200),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.logout, size: 14, color: Colors.red),
                    const SizedBox(width: 4),
                    Text(
                      'Checked Out: $timeOutStr',
                      style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.logout, size: 14, color: Colors.grey),
                    const SizedBox(width: 4),
                    const Text(
                      'Not Checked Out',
                      style: TextStyle(
                        color: Colors.grey,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 6),
            // Elapsed time prominently displayed
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.purple.shade50,
                border: Border.all(color: Colors.purple.shade200),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  const Icon(Icons.timer, size: 16, color: Colors.purple),
                  const SizedBox(width: 4),
                  Text(
                    'Elapsed: $elapsedTimeStr',
                    style: const TextStyle(
                      color: Colors.purple,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.location_on, size: 16),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    locationName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.info_outline),
              tooltip: 'Details',
              onPressed: () => _showRecordInfo(record),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              tooltip: 'Delete entry',
              onPressed: () => _confirmDeleteRecord(record),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool hasVoidOrAuto = _allRecords.any(
      (r) => r.isVoid || r.autoCheckout,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Attendance History')),
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
                          'Note: Entries marked as VOID or Auto checkout were either cancelled by an admin or automatically checked out when your device was offline for too long. These entries may not be counted as normal attendance.',
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
                                  title: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          label,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.delete_forever,
                                          color: Colors.red,
                                        ),
                                        tooltip:
                                            'Delete all entries for this month',
                                        onPressed: () => _confirmDeleteMonth(
                                          year,
                                          month,
                                          key,
                                        ),
                                      ),
                                    ],
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
}
