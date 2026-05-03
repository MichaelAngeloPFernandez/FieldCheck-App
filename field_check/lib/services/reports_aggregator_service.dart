import 'package:flutter/foundation.dart';
import 'package:field_check/services/attendance_service.dart';
import 'package:field_check/services/report_service.dart';
import 'package:field_check/models/report_model.dart';

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

class DetailedDateReport {
  final DateTime date;
  final List<AttendanceRecord> attendances;
  final List<ReportModel> taskReports;

  DetailedDateReport({
    required this.date,
    required this.attendances,
    required this.taskReports,
  });
}

class ReportsAggregatorService {
  static final ReportsAggregatorService _instance =
      ReportsAggregatorService._internal();

  final AttendanceService _attendanceService = AttendanceService();
  final ReportService _reportService = ReportService();

  factory ReportsAggregatorService() {
    return _instance;
  }

  ReportsAggregatorService._internal();

  /// Get detailed report for a specific date (attendances and task reports)
  Future<DetailedDateReport> getDateReport(DateTime date) async {
    try {
      final startOfDay = DateTime(date.year, date.month, date.day);
      final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59);

      final attendances = await _attendanceService.getAttendanceRecords(
        date: date, // backwards compatible query in AttendanceService
      );

      final taskReports = await _reportService.listReportsRange(
        startDate: startOfDay,
        endDate: endOfDay,
      );

      return DetailedDateReport(
        date: date,
        attendances: attendances,
        taskReports: taskReports,
      );
    } catch (e) {
      debugPrint('❌ Error getting detailed date report: $e');
      return DetailedDateReport(date: date, attendances: [], taskReports: []);
    }
  }

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
      final detail = await getDateReport(date);

      final checkIns = detail.attendances.where((a) => a.isCheckIn).length;
      final checkOuts = detail.attendances.where((a) => !a.isCheckIn).length;

      final completedTasks = detail.taskReports
          .where((r) => r.status == 'approved' || r.status == 'graded' || r.status == 'completed')
          .length;
      final pendingTasks = detail.taskReports.length - completedTasks;

      return ReportSummary(
        date: date,
        totalTasks: detail.taskReports.length,
        completedTasks: completedTasks,
        pendingTasks: pendingTasks,
        checkIns: checkIns,
        checkOuts: checkOuts,
        incompleteAttendance: checkIns > checkOuts ? checkIns - checkOuts : 0,
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

      // Optimization: Fetch all data for the week in single requests
      final end = start.add(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59));
      final attendances = await _attendanceService.getAttendanceRecords(
        startDate: start,
        endDate: end,
      );
      final reports = await _reportService.listReportsRange(
        startDate: start,
        endDate: end,
      );

      for (int i = 0; i < 7; i++) {
        final date = start.add(Duration(days: i));
        
        final dayAttendances = attendances.where((a) => 
            a.checkInTime.year == date.year && 
            a.checkInTime.month == date.month && 
            a.checkInTime.day == date.day).toList();
            
        final dayReports = reports.where((r) => 
            r.submittedAt.year == date.year && 
            r.submittedAt.month == date.month && 
            r.submittedAt.day == date.day).toList();

        final checkIns = dayAttendances.where((a) => a.isCheckIn).length;
        final checkOuts = dayAttendances.where((a) => !a.isCheckIn).length;
        final dCompletedTasks = dayReports.where((r) => 
            r.status == 'approved' || r.status == 'graded' || r.status == 'completed').length;
        
        final reportSummary = ReportSummary(
          date: date,
          totalTasks: dayReports.length,
          completedTasks: dCompletedTasks,
          pendingTasks: dayReports.length - dCompletedTasks,
          checkIns: checkIns,
          checkOuts: checkOuts,
          incompleteAttendance: checkIns > checkOuts ? checkIns - checkOuts : 0,
        );

        dailyReports[_dateToString(date)] = reportSummary;
        totalTasks += reportSummary.totalTasks;
        completedTasks += reportSummary.completedTasks;
        totalCheckIns += reportSummary.checkIns;
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

  /// Get month activity map, specifically for calendars
  Future<Map<DateTime, DetailedDateReport>> getMonthActivity(int year, int month) async {
      final startOfMonth = DateTime(year, month, 1);
      final daysInMonth = _getDaysInMonth(startOfMonth);
      final endOfMonth = DateTime(year, month, daysInMonth, 23, 59, 59);

      final attendances = await _attendanceService.getAttendanceRecords(
        startDate: startOfMonth,
        endDate: endOfMonth,
      );

      final reports = await _reportService.listReportsRange(
        startDate: startOfMonth,
        endDate: endOfMonth,
      );

      final result = <DateTime, DetailedDateReport>{};

      for (int day = 1; day <= daysInMonth; day++) {
        final date = DateTime(year, month, day);
        final dayAttendances = attendances.where((a) => 
            a.checkInTime.year == date.year && 
            a.checkInTime.month == date.month && 
            a.checkInTime.day == date.day).toList();
        final dayReports = reports.where((r) => 
            r.submittedAt.year == date.year && 
            r.submittedAt.month == date.month && 
            r.submittedAt.day == date.day).toList();

        result[date] = DetailedDateReport(
          date: date,
          attendances: dayAttendances,
          taskReports: dayReports,
        );
      }
      return result;
  }

  /// Get monthly report
  Future<MonthlySummary> getMonthlyReport({DateTime? month}) async {
    try {
      final targetMonth = month ?? DateTime.now();
      
      final monthActivity = await getMonthActivity(targetMonth.year, targetMonth.month);

      int completedTasks = 0;
      int incompleteTasks = 0;
      int onTimeCheckIns = 0;
      int lateCheckIns = 0;
      int incompleteAttendance = 0;

      final tasksPerEmployee = <String, int>{};
      final dailyActivityHeatmap = <DateTime, int>{};

      for (final entry in monthActivity.entries) {
        final date = entry.key;
        final detail = entry.value;

        int dCompleted = detail.taskReports.where((r) => 
            r.status == 'approved' || r.status == 'graded' || r.status == 'completed').length;
        int dIncomplete = detail.taskReports.length - dCompleted;

        completedTasks += dCompleted;
        incompleteTasks += dIncomplete;

        int checkIns = detail.attendances.where((a) => a.isCheckIn).length;
        int checkOuts = detail.attendances.where((a) => !a.isCheckIn).length;

        // Note: For real "on-time" we'd need employee schedules. We'll simplify.
        onTimeCheckIns += checkIns; 
        incompleteAttendance += (checkIns > checkOuts ? checkIns - checkOuts : 0);

        dailyActivityHeatmap[date] = detail.taskReports.length + detail.attendances.length;

        for (var report in detail.taskReports) {
          final empName = report.employeeName ?? 'Unknown';
          tasksPerEmployee[empName] = (tasksPerEmployee[empName] ?? 0) + 1;
        }
      }

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
