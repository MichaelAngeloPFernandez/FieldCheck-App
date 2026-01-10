import 'dart:async';
import 'package:field_check/models/task_model.dart' as task_model;
import 'package:field_check/services/task_service.dart';
import 'package:field_check/services/notification_service.dart';
import 'package:flutter/foundation.dart';

class TaskMonitoringService {
  static final TaskMonitoringService _instance =
      TaskMonitoringService._internal();

  factory TaskMonitoringService() {
    return _instance;
  }

  TaskMonitoringService._internal();

  final TaskService _taskService = TaskService();
  final NotificationService _notificationService = NotificationService();

  Timer? _monitoringTimer;
  final Map<String, DateTime> _lastNotificationTime = {};
  final Duration _notificationCooldown = const Duration(hours: 1);

  /// Start monitoring tasks for overdue status
  void startMonitoring({Duration checkInterval = const Duration(minutes: 5)}) {
    _monitoringTimer?.cancel();
    _monitoringTimer = Timer.periodic(checkInterval, (_) {
      _checkForOverdueTasks();
    });
    debugPrint(
      '🔍 Task monitoring started (interval: ${checkInterval.inMinutes} min)',
    );
  }

  /// Stop monitoring
  void stopMonitoring() {
    _monitoringTimer?.cancel();
    _monitoringTimer = null;
    debugPrint('⏹️ Task monitoring stopped');
  }

  /// Check for overdue tasks and notify
  Future<void> _checkForOverdueTasks() async {
    try {
      final tasks = await _taskService.getCurrentTasks();
      final now = DateTime.now();

      for (final task in tasks) {
        if (task.status == 'completed') continue;

        final isOverdue = task.dueDate.isBefore(now);
        if (!isOverdue) continue;

        // Check if we've already notified recently
        final lastNotif = _lastNotificationTime[task.id];
        if (lastNotif != null &&
            now.difference(lastNotif) < _notificationCooldown) {
          continue;
        }

        // Calculate hours overdue
        final hoursOverdue = now.difference(task.dueDate).inHours;

        // Send SMS notification
        try {
          final employeeId = task.assignedTo?.id ?? 'unassigned';
          await _notificationService.sendOverdueTaskSms(
            employeeId: employeeId,
            taskTitle: task.title,
            hoursOverdue: hoursOverdue,
          );
          _lastNotificationTime[task.id] = now;
          debugPrint('📱 Overdue notification sent for task: ${task.title}');
        } catch (e) {
          debugPrint('❌ Failed to send overdue notification: $e');
        }
      }
    } catch (e) {
      debugPrint('❌ Error checking for overdue tasks: $e');
    }
  }

  /// Get overdue tasks for an employee
  Future<List<task_model.Task>> getOverdueTasksForEmployee(
    String employeeId,
  ) async {
    try {
      final tasks = await _taskService.fetchAssignedTasks(
        employeeId,
        archived: false,
      );
      final now = DateTime.now();

      return tasks.where((task) {
        return task.dueDate.isBefore(now) && task.status != 'completed';
      }).toList();
    } catch (e) {
      debugPrint('❌ Error fetching overdue tasks: $e');
      return [];
    }
  }

  /// Get all overdue tasks across all employees
  Future<Map<String, List<task_model.Task>>> getAllOverdueTasks() async {
    try {
      final tasks = await _taskService.getCurrentTasks();
      final now = DateTime.now();
      final overdueTasks = <String, List<task_model.Task>>{};

      for (final task in tasks) {
        if (task.status == 'completed') continue;
        if (!task.dueDate.isBefore(now)) continue;

        final employeeId = task.assignedTo?.id ?? 'unassigned';
        overdueTasks.putIfAbsent(employeeId, () => []);
        overdueTasks[employeeId]!.add(task);
      }

      return overdueTasks;
    } catch (e) {
      debugPrint('❌ Error fetching all overdue tasks: $e');
      return {};
    }
  }

  /// Flag a task as overdue (admin action)
  Future<void> flagTaskAsOverdue(String taskId, String reason) async {
    try {
      // This would typically call an API endpoint to flag the task
      debugPrint('🚩 Task $taskId flagged as overdue: $reason');
    } catch (e) {
      debugPrint('❌ Error flagging task: $e');
    }
  }

  /// Get task statistics
  Future<TaskStatistics> getTaskStatistics() async {
    try {
      final tasks = await _taskService.getCurrentTasks();
      final now = DateTime.now();

      int totalTasks = 0;
      int completedTasks = 0;
      int overdueTasks = 0;
      int activeTasks = 0;
      double totalDifficultyWeight = 0;

      for (final task in tasks) {
        totalTasks++;

        if (task.status == 'completed') {
          completedTasks++;
        } else {
          activeTasks++;

          // Add difficulty weight
          totalDifficultyWeight += _getDifficultyWeight(
            task.difficulty ?? 'medium',
          );

          // Check if overdue
          if (task.dueDate.isBefore(now)) {
            overdueTasks++;
          }
        }
      }

      return TaskStatistics(
        totalTasks: totalTasks,
        completedTasks: completedTasks,
        activeTasks: activeTasks,
        overdueTasks: overdueTasks,
        completionRate: totalTasks > 0 ? (completedTasks / totalTasks) : 0,
        totalDifficultyWeight: totalDifficultyWeight,
      );
    } catch (e) {
      debugPrint('❌ Error getting task statistics: $e');
      return TaskStatistics.empty();
    }
  }

  double _getDifficultyWeight(String difficulty) {
    switch (difficulty.toLowerCase()) {
      case 'easy':
        return 1.0;
      case 'medium':
        return 2.0;
      case 'hard':
        return 3.0;
      case 'critical':
        return 5.0;
      default:
        return 2.0;
    }
  }

  /// Dispose resources
  void dispose() {
    stopMonitoring();
  }
}

class TaskStatistics {
  final int totalTasks;
  final int completedTasks;
  final int activeTasks;
  final int overdueTasks;
  final double completionRate;
  final double totalDifficultyWeight;

  TaskStatistics({
    required this.totalTasks,
    required this.completedTasks,
    required this.activeTasks,
    required this.overdueTasks,
    required this.completionRate,
    required this.totalDifficultyWeight,
  });

  factory TaskStatistics.empty() {
    return TaskStatistics(
      totalTasks: 0,
      completedTasks: 0,
      activeTasks: 0,
      overdueTasks: 0,
      completionRate: 0,
      totalDifficultyWeight: 0,
    );
  }
}
