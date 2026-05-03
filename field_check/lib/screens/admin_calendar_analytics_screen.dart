import 'package:field_check/services/attendance_service.dart';
import 'package:field_check/services/report_service.dart';
import 'package:field_check/services/task_service.dart';
import 'package:field_check/models/task_model.dart';
import 'package:field_check/models/report_model.dart';
import 'package:field_check/utils/app_theme.dart';
import 'package:field_check/utils/manila_time.dart';
import 'package:field_check/widgets/app_page.dart';
import 'package:flutter/material.dart';

class AdminCalendarAnalyticsScreen extends StatefulWidget {
  const AdminCalendarAnalyticsScreen({super.key});

  @override
  State<AdminCalendarAnalyticsScreen> createState() =>
      _AdminCalendarAnalyticsScreenState();
}

class _AdminCalendarAnalyticsScreenState
    extends State<AdminCalendarAnalyticsScreen>
    with SingleTickerProviderStateMixin {
  final AttendanceService _attendanceService = AttendanceService();
  final TaskService _taskService = TaskService();
  final ReportService _reportService = ReportService();

  late final TabController _tabController;
  int _tabIndex = 0;

  bool _loading = true;
  String? _error;

  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);

  final Map<DateTime, _DayAttendanceSummary> _attendanceByDay =
      <DateTime, _DayAttendanceSummary>{};
  final Map<DateTime, _DayTaskSummary> _tasksByDay =
      <DateTime, _DayTaskSummary>{};
  final Map<DateTime, _DayReportSummary> _reportsByDay =
      <DateTime, _DayReportSummary>{};

  DateTime _dayKey(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime _firstDayInGrid(DateTime month) {
    // Monday-based grid
    final first = DateTime(month.year, month.month, 1);
    final delta = first.weekday - DateTime.monday;
    return first.subtract(Duration(days: delta < 0 ? 6 : delta));
  }

  DateTime _lastDayInGrid(DateTime month) {
    final last = DateTime(month.year, month.month + 1, 0);
    final delta = DateTime.sunday - last.weekday;
    return last.add(Duration(days: delta < 0 ? 0 : delta));
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging && mounted) {
        setState(() {
          _tabIndex = _tabController.index;
        });
      }
    });
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _attendanceByDay.clear();
      _tasksByDay.clear();
      _reportsByDay.clear();
    });

    try {
      final rangeStart = DateTime(_month.year, _month.month, 1);
      final rangeEnd = DateTime(_month.year, _month.month + 1, 1);

      final results = await Future.wait([
        _attendanceService.getAttendanceRecords(
          startDate: rangeStart,
          endDate: rangeEnd,
          archived: false,
        ),
        _taskService.listTasks(
          archived: false,
          startDate: rangeStart,
          endDate: rangeEnd,
        ),
        _reportService.listReportsRange(
          archived: false,
          startDate: rangeStart,
          endDate: rangeEnd,
        ),
      ]);

      final attendanceRecords = (results[0] as List<AttendanceRecord>);
      final tasks = (results[1] as List<Task>);
      final reports = (results[2] as List<ReportModel>);

      final nextAttendance = <DateTime, _DayAttendanceSummary>{};
      for (final r in attendanceRecords) {
        final key = _dayKey(r.checkInTime);
        final s = nextAttendance.putIfAbsent(
          key,
          () => _DayAttendanceSummary(),
        );
        s.checkIns += 1;
        if (r.checkOutTime != null) {
          s.checkOuts += 1;
        } else {
          s.incomplete += 1;
        }
      }

      final nextTasks = <DateTime, _DayTaskSummary>{};
      for (final t in tasks) {
        final createdKey = _dayKey(t.createdAt);
        final s = nextTasks.putIfAbsent(createdKey, () => _DayTaskSummary());
        s.created += 1;
        if (t.isOverdue) {
          s.overdue += 1;
        }
        if (t.status == 'completed') {
          final completedKey = _dayKey(t.updatedAt);
          final c = nextTasks.putIfAbsent(
            completedKey,
            () => _DayTaskSummary(),
          );
          c.completed += 1;
        }
      }

      final nextReports = <DateTime, _DayReportSummary>{};
      for (final r in reports) {
        final key = _dayKey(r.submittedAt);
        final s = nextReports.putIfAbsent(key, () => _DayReportSummary());
        s.submitted += 1;
        if (r.status == 'reviewed') {
          s.reviewed += 1;
        }
      }

      if (!mounted) return;
      setState(() {
        _attendanceByDay.addAll(nextAttendance);
        _tasksByDay.addAll(nextTasks);
        _reportsByDay.addAll(nextReports);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _setMonth(DateTime month) async {
    setState(() {
      _month = DateTime(month.year, month.month, 1);
    });
    await _load();
  }

  void _openDayDetails(DateTime day) {
    final key = _dayKey(day);
    final attendance = _attendanceByDay[key] ?? _DayAttendanceSummary();
    final tasks = _tasksByDay[key] ?? _DayTaskSummary();
    final reports = _reportsByDay[key] ?? _DayReportSummary();

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatManila(day, 'MMMM d, yyyy'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                if (_tabIndex == 0) ...[
                  _metricRow('Check-ins', attendance.checkIns),
                  const SizedBox(height: 6),
                  _metricRow('Check-outs', attendance.checkOuts),
                  const SizedBox(height: 6),
                  _metricRow('Incomplete', attendance.incomplete),
                ] else if (_tabIndex == 1) ...[
                  _metricRow('Created', tasks.created),
                  const SizedBox(height: 6),
                  _metricRow('Completed', tasks.completed),
                  const SizedBox(height: 6),
                  _metricRow('Overdue', tasks.overdue),
                ] else ...[
                  _metricRow('Submitted', reports.submitted),
                  const SizedBox(height: 6),
                  _metricRow('Reviewed', reports.reviewed),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _metricRow(String label, int value) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Text(
          value.toString(),
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final first = _firstDayInGrid(_month);
    final last = _lastDayInGrid(_month);
    final days = last.difference(first).inDays + 1;
    final totalCheckIns = _attendanceByDay.values.fold<int>(
      0,
      (a, b) => a + b.checkIns,
    );
    final totalCheckOuts = _attendanceByDay.values.fold<int>(
      0,
      (a, b) => a + b.checkOuts,
    );
    final totalIncomplete = _attendanceByDay.values.fold<int>(
      0,
      (a, b) => a + b.incomplete,
    );

    final totalTasksCreated = _tasksByDay.values.fold<int>(
      0,
      (a, b) => a + b.created,
    );
    final totalTasksCompleted = _tasksByDay.values.fold<int>(
      0,
      (a, b) => a + b.completed,
    );
    final totalTasksOverdue = _tasksByDay.values.fold<int>(
      0,
      (a, b) => a + b.overdue,
    );

    final totalReportsSubmitted = _reportsByDay.values.fold<int>(
      0,
      (a, b) => a + b.submitted,
    );
    final totalReportsReviewed = _reportsByDay.values.fold<int>(
      0,
      (a, b) => a + b.reviewed,
    );

    return AppPage(
      appBarTitle: 'Calendar Analytics',
      showBack: true,
      padding: const EdgeInsets.fromLTRB(
        AppTheme.lg,
        AppTheme.lg,
        AppTheme.lg,
        AppTheme.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Attendance'),
              Tab(text: 'Tasks'),
              Tab(text: 'Reports'),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              IconButton(
                tooltip: 'Previous month',
                onPressed: _loading
                    ? null
                    : () =>
                          _setMonth(DateTime(_month.year, _month.month - 1, 1)),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  formatManila(_month, 'MMMM yyyy'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Next month',
                onPressed: _loading
                    ? null
                    : () =>
                          _setMonth(DateTime(_month.year, _month.month + 1, 1)),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: theme.dividerColor.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              children: [
                if (_tabIndex == 0) ...[
                  Expanded(child: _statPill('In', totalCheckIns, Colors.green)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _statPill('Out', totalCheckOuts, Colors.blue),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _statPill(
                      'Open',
                      totalIncomplete,
                      theme.colorScheme.error,
                    ),
                  ),
                ] else if (_tabIndex == 1) ...[
                  Expanded(
                    child: _statPill(
                      'Created',
                      totalTasksCreated,
                      theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _statPill('Done', totalTasksCompleted, Colors.green),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _statPill(
                      'Overdue',
                      totalTasksOverdue,
                      theme.colorScheme.error,
                    ),
                  ),
                ] else ...[
                  Expanded(
                    child: _statPill(
                      'Submitted',
                      totalReportsSubmitted,
                      theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _statPill(
                      'Reviewed',
                      totalReportsReviewed,
                      Colors.green,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _statPill(
                      'Pending',
                      (totalReportsSubmitted - totalReportsReviewed),
                      theme.colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_error != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: theme.colorScheme.error.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: theme.colorScheme.error),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _error!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(onPressed: _load, child: const Text('Retry')),
                ],
              ),
            )
          else
            Column(
              children: [
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 1.08,
                  ),
                  itemCount: 7,
                  itemBuilder: (context, index) {
                    const labels = [
                      'Mon',
                      'Tue',
                      'Wed',
                      'Thu',
                      'Fri',
                      'Sat',
                      'Sun',
                    ];
                    return Center(
                      child: Text(
                        labels[index],
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.8,
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 1.08,
                  ),
                  itemCount: days,
                  itemBuilder: (context, index) {
                    final d = first.add(Duration(days: index));
                    final inMonth = d.month == _month.month;
                    int activity = 0;
                    int a = 0;
                    int b = 0;
                    int c = 0;

                    if (_tabIndex == 0) {
                      final s =
                          _attendanceByDay[_dayKey(d)] ??
                          _DayAttendanceSummary();
                      a = s.checkIns;
                      b = s.checkOuts;
                      c = s.incomplete;
                      activity = a + b + c;
                    } else if (_tabIndex == 1) {
                      final s = _tasksByDay[_dayKey(d)] ?? _DayTaskSummary();
                      a = s.created;
                      b = s.completed;
                      c = s.overdue;
                      activity = a + b + c;
                    } else {
                      final s =
                          _reportsByDay[_dayKey(d)] ?? _DayReportSummary();
                      a = s.submitted;
                      b = s.reviewed;
                      c = s.submitted - s.reviewed;
                      activity = a + b;
                    }

                    final bg = activity == 0
                        ? theme.colorScheme.surface
                        : theme.colorScheme.primary.withValues(
                            alpha: (0.08 + (activity.clamp(0, 12) / 12) * 0.25),
                          );

                    return InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: inMonth ? () => _openDayDetails(d) : null,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: bg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: theme.dividerColor.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${d.day}',
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: inMonth
                                    ? theme.colorScheme.onSurface
                                    : theme.colorScheme.onSurface.withValues(
                                        alpha: 0.35,
                                      ),
                              ),
                            ),
                            const Spacer(),
                            if (inMonth && activity > 0)
                              Row(
                                children: [
                                  _dot(
                                    _tabIndex == 0
                                        ? Colors.green
                                        : theme.colorScheme.primary,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    a.toString(),
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  _dot(
                                    _tabIndex == 0 ? Colors.blue : Colors.green,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    b.toString(),
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            if (inMonth && c > 0) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  _dot(theme.colorScheme.error),
                                  const SizedBox(width: 4),
                                  Text(
                                    c.toString(),
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: theme.colorScheme.error,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _dot(Color color) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  Widget _statPill(String label, int value, Color color) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value.toString(),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _DayAttendanceSummary {
  int checkIns = 0;
  int checkOuts = 0;
  int incomplete = 0;
}

class _DayTaskSummary {
  int created = 0;
  int completed = 0;
  int overdue = 0;
}

class _DayReportSummary {
  int submitted = 0;
  int reviewed = 0;
}
