import 'package:flutter/foundation.dart';

class ReportSummary {
  final DateTime date;
  final int totalTasks;
  final int completedTasks;
  final int pendingTasks;
  final int checkIns;
  final int checkOuts;
  final int incompleteAttendance;

  ReportSummary({
    required this.date,
    required this.totalTasks,
    required this.completedTasks,
    required this.pendingTasks,
    required this.checkIns,
    required this.checkOuts,
    required this.incompleteAttendance,
  });
}

class WeeklySummary {
  final DateTime weekStart;
  final Map<String, ReportSummary> dailyReports;
  final int totalTasks;
  final int completedTasks;
  final int totalCheckIns;

  WeeklySummary({
    required this.weekStart,
    required this.dailyReports,
    required this.totalTasks,
    required this.completedTasks,
    required this.totalCheckIns,
  });
}

class MonthlySummary {
  final DateTime month;
  final int completedTasks;
  final int incompleteTasks;
  final int onTimeCheckIns;
  final int lateCheckIns;
  final int incompleteAttendance;
  final Map<String, int> tasksPerEmployee;
  final Map<DateTime, int> dailyActivityHeatmap;

  MonthlySummary({
    required this.month,
    required this.completedTasks,
    required this.incompleteTasks,
    required this.onTimeCheckIns,
    required this.lateCheckIns,
    required this.incompleteAttendance,
    required this.tasksPerEmployee,
    required this.dailyActivityHeatmap,
  });
}

class ReportsAggregatorService {
  static final ReportsAggregatorService _instance =
      ReportsAggregatorService._internal();

  factory ReportsAggregatorService() {
    return _instance;
  }

  ReportsAggregatorService._internal();

  /// Get today's report summary
  Future<ReportSummary> getTodayReport() async {
    try {
      final today = DateTime.now();
      return getDailyReport(today);
    } catch (e) {
      debugPrint('❌ Error getting today report: $e');
      return _emptyDailyReport(DateTime.now());
    }
  }

  /// Get daily report for specific date
  Future<ReportSummary> getDailyReport(DateTime date) async {
    try {
      // This would fetch from backend in production
      // For now, return mock data structure
      return ReportSummary(
        date: date,
        totalTasks: 12,
        completedTasks: 8,
        pendingTasks: 4,
        checkIns: 15,
        checkOuts: 12,
        incompleteAttendance: 3,
      );
    } catch (e) {
      debugPrint('❌ Error getting daily report: $e');
      return _emptyDailyReport(date);
    }
  }

  /// Get weekly report
  Future<WeeklySummary> getWeeklyReport({DateTime? weekStart}) async {
    try {
      final start = weekStart ?? _getWeekStart(DateTime.now());
      final dailyReports = <String, ReportSummary>{};

      int totalTasks = 0;
      int completedTasks = 0;
      int totalCheckIns = 0;

      for (int i = 0; i < 7; i++) {
        final date = start.add(Duration(days: i));
        final report = await getDailyReport(date);

        dailyReports[_dateToString(date)] = report;
        totalTasks += report.totalTasks;
        completedTasks += report.completedTasks;
        totalCheckIns += report.checkIns;
      }

      return WeeklySummary(
        weekStart: start,
        dailyReports: dailyReports,
        totalTasks: totalTasks,
        completedTasks: completedTasks,
        totalCheckIns: totalCheckIns,
      );
    } catch (e) {
      debugPrint('❌ Error getting weekly report: $e');
      return _emptyWeeklySummary(DateTime.now());
    }
  }

  /// Get monthly report
  Future<MonthlySummary> getMonthlyReport({DateTime? month}) async {
    try {
      final targetMonth = month ?? DateTime.now();
      final daysInMonth = _getDaysInMonth(targetMonth);

      int completedTasks = 0;
      int incompleteTasks = 0;
      int onTimeCheckIns = 0;
      int lateCheckIns = 0;
      int incompleteAttendance = 0;

      final tasksPerEmployee = <String, int>{};
      final dailyActivityHeatmap = <DateTime, int>{};

      // Generate daily heatmap
      for (int day = 1; day <= daysInMonth; day++) {
        final date = DateTime(targetMonth.year, targetMonth.month, day);
        final report = await getDailyReport(date);

        completedTasks += report.completedTasks;
        incompleteTasks += report.pendingTasks;
        onTimeCheckIns += (report.checkIns ~/ 2); // Mock calculation
        lateCheckIns += (report.checkIns - (report.checkIns ~/ 2));
        incompleteAttendance += report.incompleteAttendance;

        dailyActivityHeatmap[date] = report.totalTasks;
      }

      // Mock tasks per employee
      tasksPerEmployee['emp_001'] = 45;
      tasksPerEmployee['emp_002'] = 38;
      tasksPerEmployee['emp_003'] = 52;

      return MonthlySummary(
        month: DateTime(targetMonth.year, targetMonth.month, 1),
        completedTasks: completedTasks,
        incompleteTasks: incompleteTasks,
        onTimeCheckIns: onTimeCheckIns,
        lateCheckIns: lateCheckIns,
        incompleteAttendance: incompleteAttendance,
        tasksPerEmployee: tasksPerEmployee,
        dailyActivityHeatmap: dailyActivityHeatmap,
      );
    } catch (e) {
      debugPrint('❌ Error getting monthly report: $e');
      return _emptyMonthlySummary(DateTime.now());
    }
  }

  /// Helper: Get week start (Monday)
  DateTime _getWeekStart(DateTime date) {
    final dayOfWeek = date.weekday;
    return date.subtract(Duration(days: dayOfWeek - 1));
  }

  /// Helper: Convert date to string
  String _dateToString(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// Helper: Get days in month
  int _getDaysInMonth(DateTime date) {
    return DateTime(date.year, date.month + 1, 0).day;
  }

  /// Empty report generators
  ReportSummary _emptyDailyReport(DateTime date) {
    return ReportSummary(
      date: date,
      totalTasks: 0,
      completedTasks: 0,
      pendingTasks: 0,
      checkIns: 0,
      checkOuts: 0,
      incompleteAttendance: 0,
    );
  }

  WeeklySummary _emptyWeeklySummary(DateTime date) {
    return WeeklySummary(
      weekStart: _getWeekStart(date),
      dailyReports: {},
      totalTasks: 0,
      completedTasks: 0,
      totalCheckIns: 0,
    );
  }

  MonthlySummary _emptyMonthlySummary(DateTime date) {
    return MonthlySummary(
      month: DateTime(date.year, date.month, 1),
      completedTasks: 0,
      incompleteTasks: 0,
      onTimeCheckIns: 0,
      lateCheckIns: 0,
      incompleteAttendance: 0,
      tasksPerEmployee: {},
      dailyActivityHeatmap: {},
    );
  }
}
