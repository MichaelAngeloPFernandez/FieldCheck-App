import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:field_check/services/attendance_service.dart';
import 'package:field_check/services/realtime_service.dart';
import 'package:field_check/utils/manila_time.dart';

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
    final now = manilaNow();
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
      final dt = toManilaTime(record.checkInTime);
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
      final dt = toManilaTime(record.checkInTime);
      final key = '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
      grouped.putIfAbsent(key, () => <AttendanceRecord>[]).add(record);
    }

    for (final list in grouped.values) {
      list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    }

    return grouped;
  }

  Widget _buildSectionHeader(
    String title, {
    String? subtitle,
    Widget? trailing,
  }) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  Widget _buildSurfaceCard({
    required Widget child,
    EdgeInsetsGeometry? padding,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildStatusPill({
    required String label,
    required Color color,
    IconData? icon,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBanner({
    required String message,
    required IconData icon,
    Color? color,
  }) {
    final theme = Theme.of(context);
    final accent = color ?? Colors.orange.shade700;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStateCard({
    required IconData icon,
    required String title,
    required String message,
    Widget? action,
  }) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: _buildSurfaceCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: theme.colorScheme.primary),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                ),
                textAlign: TextAlign.center,
              ),
              if (action != null) ...[const SizedBox(height: 12), action],
            ],
          ),
        ),
      ),
    );
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
            final dt = toManilaTime(record.timestamp);
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
    final dtIn = toManilaTime(record.checkInTime);
    final dateStr = DateFormat('yyyy-MM-dd').format(dtIn);
    final timeInStr = TimeOfDay.fromDateTime(dtIn).format(context);

    String? timeOutStr;
    String? elapsedStr;
    if (record.checkOutTime != null) {
      final dtOut = toManilaTime(record.checkOutTime!);
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
            Text('Date: $dateStr'),
            Text('Location: $locationName'),
            Text('Check-in Time: $timeInStr'),
            if (timeOutStr != null) ...[
              const SizedBox(height: 8),
              Text('Check-out Time: $timeOutStr'),
            ],
            if (elapsedStr != null) ...[
              const SizedBox(height: 8),
              Text('Duration: $elapsedStr'),
            ],
            const SizedBox(height: 8),
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
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final dtIn = toManilaTime(record.checkInTime);
    final dateStr = DateFormat('yyyy-MM-dd').format(dtIn);
    final timeInStr = TimeOfDay.fromDateTime(dtIn).format(context);
    final locationName = record.geofenceName ?? 'Unknown location';

    // Determine if completed (has checkout)
    final isCompleted = record.checkOutTime != null;
    final typeLabel = isCompleted ? 'Completed' : 'Checked In';

    Color chipFg;
    IconData chipIcon;

    if (record.isVoid && record.autoCheckout) {
      chipFg = Colors.red.shade900;
      chipIcon = Icons.warning_amber_rounded;
    } else if (record.isVoid) {
      chipFg = onSurface.withValues(alpha: 0.85);
      chipIcon = Icons.block;
    } else if (isCompleted) {
      chipFg = Colors.blue.shade900;
      chipIcon = Icons.check_circle_outline;
    } else {
      chipFg = Colors.green.shade900;
      chipIcon = Icons.login;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: _buildSurfaceCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 46,
              width: 46,
              decoration: BoxDecoration(
                color: chipFg.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(chipIcon, color: chipFg, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          dateStr,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      _buildStatusPill(label: typeLabel, color: chipFg),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 16,
                        color: onSurface.withValues(alpha: 0.6),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'In: $timeInStr',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  if (record.checkOutTime != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.logout,
                          size: 16,
                          color: onSurface.withValues(alpha: 0.6),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Out: ${TimeOfDay.fromDateTime(toManilaTime(record.checkOutTime!)).format(context)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    if (record.elapsedHours != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Duration: ${record.elapsedHours!.toStringAsFixed(2)} hours',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: onSurface.withValues(alpha: 0.7),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.location_on,
                        size: 16,
                        color: onSurface.withValues(alpha: 0.6),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          locationName,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              children: [
                IconButton(
                  icon: Icon(
                    Icons.info_outline,
                    color: theme.colorScheme.primary,
                  ),
                  tooltip: 'Details',
                  onPressed: () => _showRecordInfo(record),
                ),
                IconButton(
                  icon: Icon(
                    Icons.delete_outline,
                    color: theme.colorScheme.error,
                  ),
                  tooltip: 'Delete entry',
                  onPressed: () => _confirmDeleteRecord(record),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool hasVoidOrAuto = _allRecords.any(
      (r) => r.isVoid || r.autoCheckout,
    );
    final totalCount = _allRecords.length;
    final filteredCount = _filteredRecords.length;
    final countLabel = _searchQuery.trim().isEmpty
        ? '$totalCount entries'
        : '$filteredCount of $totalCount';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Attendance History',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: _buildSurfaceCard(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionHeader(
                      'Search history',
                      subtitle: 'Find entries by date, time, or location.',
                      trailing: _buildStatusPill(
                        label: countLabel,
                        color: theme.colorScheme.primary,
                        icon: Icons.event_available,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search by date, time, or location',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close),
                                tooltip: 'Clear search',
                                onPressed: () {
                                  setState(() {
                                    _searchQuery = '';
                                    _searchController.clear();
                                  });
                                },
                              )
                            : null,
                      ),
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
            if (hasVoidOrAuto)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: _buildInfoBanner(
                  icon: Icons.info_outline,
                  message:
                      'Note: Entries marked as VOID or Auto checkout were either cancelled by an admin or automatically checked out when your device was offline for too long. These entries may not be counted as normal attendance.',
                ),
              ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? _buildStateCard(
                      icon: Icons.error_outline,
                      title: 'Unable to load history',
                      message: _error ?? 'Something went wrong.',
                      action: FilledButton.icon(
                        onPressed: _loadHistory,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    )
                  : _filteredRecords.isEmpty
                  ? _buildStateCard(
                      icon: Icons.event_busy,
                      title: 'No attendance history',
                      message:
                          'Your check-ins will show up here once recorded.',
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

                              return _buildSurfaceCard(
                                padding: EdgeInsets.zero,
                                child: Theme(
                                  data: theme.copyWith(
                                    dividerColor: Colors.transparent,
                                  ),
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
                                    tilePadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 4,
                                    ),
                                    childrenPadding: const EdgeInsets.fromLTRB(
                                      16,
                                      0,
                                      16,
                                      8,
                                    ),
                                    title: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            label,
                                            style: theme.textTheme.titleSmall
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                        ),
                                        _buildStatusPill(
                                          label: '${list.length} entries',
                                          color: theme.colorScheme.primary,
                                          icon: Icons.event_note,
                                        ),
                                        const SizedBox(width: 8),
                                        IconButton(
                                          icon: Icon(
                                            Icons.delete_forever,
                                            color: theme.colorScheme.error,
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
                                    children: list
                                        .map(_buildRecordTile)
                                        .toList(),
                                  ),
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
