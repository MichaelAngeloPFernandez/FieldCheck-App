// ignore_for_file: avoid_print
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:field_check/models/task_model.dart';
import 'package:field_check/services/task_service.dart';
import 'package:field_check/services/realtime_service.dart';
import 'package:field_check/services/autosave_service.dart';
import 'package:field_check/screens/task_report_screen.dart';
import 'package:field_check/screens/employee_task_details_screen.dart';
import 'package:field_check/screens/map_screen.dart';
import 'package:field_check/screens/employee_reports_screen.dart';

class EmployeeTaskListScreen extends StatefulWidget {
  final String userModelId;

  const EmployeeTaskListScreen({super.key, required this.userModelId});

  @override
  State<EmployeeTaskListScreen> createState() => _EmployeeTaskListScreenState();
}

class _EmployeeTaskListScreenState extends State<EmployeeTaskListScreen> {
  late Future<List<Task>> _assignedTasksFuture;
  final RealtimeService _realtimeService = RealtimeService();
  final AutosaveService _autosaveService = AutosaveService();

  StreamSubscription<Map<String, dynamic>>? _taskSub;
  Timer? _taskRefreshDebounce;

  String _statusFilter = 'all'; // all, pending, in_progress, completed

  @override
  void initState() {
    super.initState();
    // ignore: unnecessary_statements
    _completeTaskWithReport;
    _assignedTasksFuture = TaskService().fetchAssignedTasks(widget.userModelId);
    _initRealtimeService();
    _autosaveService.initialize();
  }

  Future<void> _openTaskDetails(Task task) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => EmployeeTaskDetailsScreen(
          task: task,
          employeeId: widget.userModelId,
        ),
      ),
    );

    if (result == true && mounted) {
      setState(() {
        _assignedTasksFuture = TaskService().fetchAssignedTasks(
          widget.userModelId,
        );
      });
    }
  }

  @override
  void dispose() {
    _taskRefreshDebounce?.cancel();
    _taskSub?.cancel();
    super.dispose();
  }

  Future<void> _initRealtimeService() async {
    await _realtimeService.initialize();

    _taskSub?.cancel();
    _taskSub = _realtimeService.taskStream.listen((event) {
      // Conservative strategy: refresh on any task-related event.
      // Server payload shapes vary, so avoid brittle filtering.
      _taskRefreshDebounce?.cancel();
      _taskRefreshDebounce = Timer(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        setState(() {
          _assignedTasksFuture = TaskService().fetchAssignedTasks(
            widget.userModelId,
          );
        });
      });
    });
  }

  Future<void> _completeTaskWithReport(Task task) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) =>
            TaskReportScreen(task: task, employeeId: widget.userModelId),
      ),
    );

    if (result == true && mounted) {
      setState(() {
        _assignedTasksFuture = TaskService().fetchAssignedTasks(
          widget.userModelId,
        );
      });
    }
  }

  Future<void> _refreshTasks() async {
    setState(() {
      _assignedTasksFuture = TaskService().fetchAssignedTasks(
        widget.userModelId,
      );
    });
  }

  double _taskProgressValue(Task task) {
    if (task.checklist.isNotEmpty) {
      final clamped = task.progressPercent.clamp(0, 100);
      return clamped / 100.0;
    }

    switch (task.status) {
      case 'completed':
        return 1.0;
      case 'in_progress':
        return 0.5;
      case 'pending':
      default:
        return 0.0;
    }
  }

  String _taskProgressLabel(Task task) {
    if (task.checklist.isNotEmpty) {
      final clamped = task.progressPercent.clamp(0, 100);
      return '$clamped%';
    }

    switch (task.status) {
      case 'completed':
        return '100%';
      case 'in_progress':
        return '50%';
      case 'pending':
      default:
        return '0%';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Tasks'),
        actions: [
          IconButton(
            tooltip: 'My Reports',
            icon: const Icon(Icons.description_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => EmployeeReportsScreen(
                    employeeId: widget.userModelId,
                  ),
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'Refresh Tasks',
            icon: const Icon(Icons.refresh),
            onPressed: _refreshTasks,
          ),
          IconButton(
            tooltip: 'Open Map',
            icon: const Icon(Icons.map),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MapScreen()),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshTasks,
        child: FutureBuilder<List<Task>>(
          future: _assignedTasksFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            } else if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return const Center(child: Text('No tasks assigned.'));
            }

            final tasks = snapshot.data!
                .where((t) => !t.isArchived)
                .where(
                  (t) =>
                      _statusFilter == 'all' ? true : t.status == _statusFilter,
                )
                .toList();

            tasks.sort((a, b) {
              // In-progress first
              final aInProgress = a.status == 'in_progress';
              final bInProgress = b.status == 'in_progress';
              if (aInProgress != bInProgress) {
                return aInProgress ? -1 : 1;
              }

              // Then due date (soonest first)
              final byDue = a.dueDate.compareTo(b.dueDate);
              if (byDue != 0) return byDue;

              // Then title
              return a.title.compareTo(b.title);
            });

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('All'),
                        selected: _statusFilter == 'all',
                        onSelected: (sel) {
                          if (!sel) return;
                          setState(() => _statusFilter = 'all');
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Pending'),
                        selected: _statusFilter == 'pending',
                        onSelected: (sel) {
                          if (!sel) return;
                          setState(() => _statusFilter = 'pending');
                        },
                      ),
                      ChoiceChip(
                        label: const Text('In Progress'),
                        selected: _statusFilter == 'in_progress',
                        onSelected: (sel) {
                          if (!sel) return;
                          setState(() => _statusFilter = 'in_progress');
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Completed'),
                        selected: _statusFilter == 'completed',
                        onSelected: (sel) {
                          if (!sel) return;
                          setState(() => _statusFilter = 'completed');
                        },
                      ),
                    ],
                  ),
                ),
                if (tasks.isEmpty)
                  const Expanded(
                    child: Center(
                      child: Text(
                        'No tasks match this filter.\nPull down to refresh.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: ListView.builder(
                      itemCount: tasks.length,
                      itemBuilder: (context, index) {
                        final task = tasks[index];
                        final isCompleted = task.status == 'completed';
                        return GestureDetector(
                          onTap:
                              isCompleted ? null : () => _openTaskDetails(task),
                          child: Card(
                            margin: const EdgeInsets.all(8.0),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    task.title,
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      decoration: isCompleted
                                          ? TextDecoration.lineThrough
                                          : null,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(task.description),
                                  const SizedBox(height: 8),
                                  if ((task.type != null &&
                                          task.type!.isNotEmpty) ||
                                      (task.difficulty != null &&
                                          task.difficulty!.isNotEmpty))
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 8.0,
                                      ),
                                      child: Row(
                                        children: [
                                          if (task.type != null &&
                                              task.type!.isNotEmpty)
                                            Chip(
                                              label: Text(task.type!),
                                              visualDensity:
                                                  VisualDensity.compact,
                                            ),
                                          if (task.difficulty != null &&
                                              task.difficulty!.isNotEmpty) ...[
                                            const SizedBox(width: 4),
                                            Chip(
                                              label: Text(task.difficulty!),
                                              visualDensity:
                                                  VisualDensity.compact,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  Text(
                                    'Due Date: ${task.dueDate.toLocal().toString().split(' ')[0]}',
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      const Text(
                                        'Status: ',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Chip(
                                        label: Text(task.status),
                                        backgroundColor:
                                            task.status == 'completed'
                                            ? Colors.green[100]
                                            : (task.status == 'in_progress'
                                                  ? Colors.orange[100]
                                                  : Colors.blue[100]),
                                        labelStyle: TextStyle(
                                          color: task.status == 'completed'
                                              ? Colors.green[900]
                                              : (task.status == 'in_progress'
                                                    ? Colors.orange[900]
                                                    : Colors.blue[900]),
                                        ),
                                      ),
                                      if (task.rawStatus == 'blocked') ...[
                                        const SizedBox(width: 8),
                                        Chip(
                                          label: const Text('Blocked'),
                                          backgroundColor: Colors.red[100],
                                          labelStyle: TextStyle(
                                            color: Colors.red[900],
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  LinearProgressIndicator(
                                    value: _taskProgressValue(task),
                                    backgroundColor: Colors.grey[200],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Progress: ${_taskProgressLabel(task)}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.black54,
                                    ),
                                  ),
                                  if (task.assignedToMultiple.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    const Text(
                                      'Assigned to:',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Wrap(
                                      spacing: 4,
                                      children: task.assignedToMultiple
                                          .map(
                                            (user) => Chip(
                                              label: Text(user.name),
                                              padding: EdgeInsets.zero,
                                              visualDensity:
                                                  VisualDensity.compact,
                                            ),
                                          )
                                          .toList(),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
