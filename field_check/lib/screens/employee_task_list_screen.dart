// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import 'package:field_check/models/task_model.dart';
import 'package:field_check/services/task_service.dart';
import 'package:field_check/services/realtime_service.dart';
import 'package:field_check/services/autosave_service.dart';
import 'package:field_check/screens/task_report_screen.dart';
import 'package:field_check/screens/map_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _assignedTasksFuture = TaskService().fetchAssignedTasks(widget.userModelId);
    _initRealtimeService();
    _autosaveService.initialize();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _initRealtimeService() async {
    await _realtimeService.initialize();

    // Listen for any task updates (new, updated, deleted, status_updated)
    _realtimeService.taskStream.listen((event) {
      if (mounted) {
        setState(() {
          _assignedTasksFuture = TaskService().fetchAssignedTasks(
            widget.userModelId,
          );
        });
      }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Tasks'),
        actions: [
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
      body: FutureBuilder<List<Task>>(
        future: _assignedTasksFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No tasks assigned.'));
          } else {
            return ListView.builder(
              itemCount: snapshot.data!.length,
              itemBuilder: (context, index) {
                final task = snapshot.data![index];
                final isCompleted = task.status == 'completed';
                return Card(
                  margin: const EdgeInsets.all(8.0),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Checkbox(
                              value: isCompleted,
                              onChanged: isCompleted
                                  ? null
                                  : (value) async {
                                      if (value == true) {
                                        await _completeTaskWithReport(task);
                                      }
                                    },
                            ),
                            Expanded(
                              child: Text(
                                task.title,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  decoration: isCompleted
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(task.description),
                        const SizedBox(height: 8),
                        Text(
                          'Due Date: ${task.dueDate.toLocal().toString().split(' ')[0]}',
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Text(
                              'Status: ',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Chip(
                              label: Text(task.status),
                              backgroundColor: task.status == 'completed'
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
                          ],
                        ),
                        if (task.assignedToMultiple.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          const Text(
                            'Assigned to:',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Wrap(
                            spacing: 4,
                            children: task.assignedToMultiple
                                .map(
                                  (user) => Chip(
                                    label: Text(user.name),
                                    padding: EdgeInsets.zero,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            );
          }
        },
      ),
    );
  }
}
