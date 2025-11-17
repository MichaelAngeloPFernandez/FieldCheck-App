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
    
    _realtimeService.taskStream.listen((event) {
      if (mounted) {
        setState(() {
          _assignedTasksFuture = TaskService().fetchAssignedTasks(widget.userModelId);
        });
      }
    });
  }

  Future<void> _updateTaskStatus(String userTaskId, String status) async {
    try {
      await TaskService().updateUserTaskStatus(userTaskId, status);
      setState(() {
        _assignedTasksFuture = TaskService().fetchAssignedTasks(widget.userModelId);
      });
    } catch (e) {
      // Handle error, e.g., show a SnackBar
      debugPrint('Error updating task status: $e');
    }
  }

  Future<void> _completeTaskWithReport(Task task) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => TaskReportScreen(
          task: task,
          employeeId: widget.userModelId,
        ),
      ),
    );

    if (result == true && mounted) {
      setState(() {
        _assignedTasksFuture = TaskService().fetchAssignedTasks(widget.userModelId);
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
                return Card(
                  margin: const EdgeInsets.all(8.0),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(task.description),
                        const SizedBox(height: 8),
                        Text('Due Date: ${task.dueDate.toLocal().toString().split(' ')[0]}'),
                        const SizedBox(height: 8),
                        Text('Status: ${task.status}'),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            ElevatedButton(
                              onPressed: task.status == 'pending'
                                  ? () => _updateTaskStatus(task.userTaskId!, 'in_progress')
                                  : null,
                              child: const Text('Start Task'),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: task.status == 'in_progress'
                                  ? () => _completeTaskWithReport(task)
                                  : null,
                              child: const Text('Complete Task'),
                            ),
                          ],
                        ),
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