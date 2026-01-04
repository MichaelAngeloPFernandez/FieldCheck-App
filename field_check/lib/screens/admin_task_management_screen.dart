// ignore_for_file: use_build_context_synchronously, library_prefixes, unnecessary_null_aware_operator, unnecessary_null_comparison, unnecessary_non_null_assertion
import 'package:flutter/material.dart';
import 'package:field_check/services/task_service.dart';
import 'package:field_check/services/user_service.dart';
import 'package:field_check/services/availability_service.dart';
import 'package:field_check/models/task_model.dart';
import 'package:field_check/models/user_model.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:field_check/config/api_config.dart';

class AdminTaskManagementScreen extends StatefulWidget {
  const AdminTaskManagementScreen({super.key});

  @override
  State<AdminTaskManagementScreen> createState() =>
      _AdminTaskManagementScreenState();
}

class _AdminTaskManagementScreenState extends State<AdminTaskManagementScreen> {
  final TaskService _taskService = TaskService();
  final UserService _userService = UserService();
  final AvailabilityService _availabilityService = AvailabilityService();
  List<Task> _tasks = [];
  List<Task> _archivedTasks = [];
  bool _isLoading = true;
  bool _showArchived = false;
  String _difficultyFilter = 'all';
  String _sortBy = 'dueDate'; // 'dueDate', 'difficulty', 'status'
  late io.Socket _socket;

  // Workload tracking
  final Map<String, int> _employeeActiveTaskCount = {};
  final Map<String, double> _employeeDifficultyWeight = {};
  final Map<String, int> _employeeOverdueCount = {};

  static const int _taskLimitPerEmployee = 5;

  @override
  void initState() {
    super.initState();
    _fetchTasks();
    _initSocket();
  }

  Future<void> _escalateTask(Task task) async {
    try {
      final result = await _taskService.escalateTask(task.id);
      if (!mounted) return;

      final sent = result['sent'];
      String message;
      if (sent is int) {
        if (sent > 0) {
          message = 'Escalation SMS sent to $sent assignee(s).';
        } else {
          message = 'No active assignees to escalate for this task.';
        }
      } else {
        message = 'Escalation request completed.';
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      debugPrint('Error escalating task: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to escalate task: $e')));
      }
    }
  }

  Future<void> _archiveTask(Task task) async {
    try {
      await _taskService.archiveTask(task.id);
      await _fetchTasks();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Task archived')));
      }
    } catch (e) {
      debugPrint('Error archiving task: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to archive task: $e')));
      }
    }
  }

  Future<void> _restoreTask(Task task) async {
    try {
      await _taskService.restoreTask(task.id);
      await _fetchTasks();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Task restored')));
      }
    } catch (e) {
      debugPrint('Error restoring task: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to restore task: $e')));
      }
    }
  }

  @override
  void dispose() {
    _socket.disconnect();
    super.dispose();
  }

  void _initSocket() {
    // Include auth header and robust reconnection/backoff settings
    final baseOptions = io.OptionBuilder()
        .setTransports(['websocket'])
        .enableAutoConnect()
        .setTimeout(20000)
        .build();
    baseOptions['reconnection'] = true;
    baseOptions['reconnectionAttempts'] = 999999;
    baseOptions['reconnectionDelay'] = 500;
    baseOptions['reconnectionDelayMax'] = 10000;
    // Attach Authorization header if available
    _userService.getToken().then((token) {
      final options = Map<String, dynamic>.from(baseOptions);
      if (token != null) {
        options['extraHeaders'] = {'Authorization': 'Bearer $token'};
      }
      _socket = io.io(ApiConfig.baseUrl, options);

      _socket.onConnect((_) => debugPrint('Connected to Socket.IO'));
      _socket.onDisconnect((_) => debugPrint('Disconnected from Socket.IO'));
      _socket.onConnectError(
        (err) => debugPrint('Socket.IO Connect Error: $err'),
      );
      _socket.onError((err) => debugPrint('Socket.IO Error: $err'));
      _socket.on(
        'reconnect_attempt',
        (_) => debugPrint('Socket.IO reconnect attempt'),
      );
      _socket.on('reconnect', (_) => debugPrint('Socket.IO reconnected'));
      _socket.on(
        'reconnect_error',
        (err) => debugPrint('Socket.IO reconnect error: $err'),
      );
      _socket.on(
        'reconnect_failed',
        (_) => debugPrint('Socket.IO reconnect failed'),
      );

      _socket.on('newTask', (data) {
        debugPrint('New task received: $data');
        _fetchTasks();
      });

      _socket.on('updatedTask', (data) {
        debugPrint('Task updated: $data');
        _fetchTasks();
      });

      _socket.on('deletedTask', (data) {
        debugPrint('Task deleted: $data');
        _fetchTasks();
      });
    });
  }

  Future<void> _fetchTasks() async {
    try {
      final current = await _taskService.getCurrentTasks();
      final archived = await _taskService.getArchivedTasks();
      setState(() {
        _tasks = current;
        _archivedTasks = archived;
        _isLoading = false;
        _calculateWorkload();
      });
    } catch (e) {
      // Handle error
      debugPrint('Error fetching tasks: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _sortTasks(List<Task> tasks) {
    switch (_sortBy) {
      case 'difficulty':
        tasks.sort((a, b) {
          final diffMap = {'easy': 1, 'medium': 2, 'hard': 3};
          final aVal = diffMap[a.difficulty?.toLowerCase() ?? 'medium'] ?? 2;
          final bVal = diffMap[b.difficulty?.toLowerCase() ?? 'medium'] ?? 2;
          return aVal.compareTo(bVal);
        });
        break;
      case 'status':
        final statusMap = {'pending': 0, 'in_progress': 1, 'completed': 2};
        tasks.sort((a, b) {
          final aVal = statusMap[a.status] ?? 0;
          final bVal = statusMap[b.status] ?? 0;
          return aVal.compareTo(bVal);
        });
        break;
      case 'dueDate':
      default:
        tasks.sort((a, b) => a.dueDate.compareTo(b.dueDate));
        break;
    }
  }

  void _calculateWorkload() {
    _employeeActiveTaskCount.clear();
    _employeeDifficultyWeight.clear();
    _employeeOverdueCount.clear();

    final now = DateTime.now();

    for (final task in _tasks) {
      // Only count non-completed tasks
      if (task.status == 'completed') continue;

      for (final assignee in task.assignedToMultiple) {
        final userId = assignee.id;

        // Count active tasks
        _employeeActiveTaskCount[userId] =
            (_employeeActiveTaskCount[userId] ?? 0) + 1;

        // Calculate difficulty weight
        double weight = 1.0;
        switch (task.difficulty?.toLowerCase() ?? 'medium') {
          case 'easy':
            weight = 1.0;
            break;
          case 'medium':
            weight = 2.0;
            break;
          case 'hard':
            weight = 3.0;
            break;
          case 'critical':
            weight = 5.0;
            break;
          default:
            weight = 2.0;
        }
        _employeeDifficultyWeight[userId] =
            (_employeeDifficultyWeight[userId] ?? 0.0) + weight;

        // Count overdue tasks
        if (task.dueDate != null) {
          if (task.dueDate!.isBefore(now)) {
            _employeeOverdueCount[userId] =
                (_employeeOverdueCount[userId] ?? 0) + 1;
          }
        }
      }
    }
  }

  Future<void> _addTask() async {
    final TextEditingController titleController = TextEditingController();
    final TextEditingController descriptionController = TextEditingController();
    DateTime? dueDate;
    String taskType = 'general';
    String taskDifficulty = 'medium';

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Add New Task'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: taskType,
                  decoration: const InputDecoration(labelText: 'Task Type'),
                  items: const [
                    DropdownMenuItem(value: 'general', child: Text('General')),
                    DropdownMenuItem(
                      value: 'inspection',
                      child: Text('Inspection'),
                    ),
                    DropdownMenuItem(
                      value: 'maintenance',
                      child: Text('Maintenance'),
                    ),
                    DropdownMenuItem(
                      value: 'delivery',
                      child: Text('Delivery'),
                    ),
                    DropdownMenuItem(value: 'other', child: Text('Other')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    taskType = value;
                  },
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: taskDifficulty,
                  decoration: const InputDecoration(labelText: 'Difficulty'),
                  items: const [
                    DropdownMenuItem(value: 'easy', child: Text('Easy')),
                    DropdownMenuItem(value: 'medium', child: Text('Medium')),
                    DropdownMenuItem(value: 'hard', child: Text('Hard')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    taskDifficulty = value;
                  },
                ),
                ListTile(
                  title: Text(
                    dueDate == null
                        ? 'Select Due Date'
                        : 'Due Date: ${dueDate!.toLocal().toString().split(' ')[0]}',
                  ),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    dueDate = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime.now(),
                      lastDate: DateTime(2100),
                    );
                    // This setState is to update the dialog's UI
                    if (mounted) {
                      setState(() {});
                    }
                  },
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                if (titleController.text.isNotEmpty &&
                    descriptionController.text.isNotEmpty &&
                    dueDate != null) {
                  final newTask = Task(
                    id: '', // ID will be generated by the backend
                    title: titleController.text,
                    description: descriptionController.text,
                    type: taskType,
                    difficulty: taskDifficulty,
                    dueDate: dueDate!,
                    assignedBy: _userService.currentUser?.id ?? 'unknown_admin',
                    createdAt: DateTime.now(),
                    status: 'pending',
                    rawStatus: 'pending',
                    progressPercent: 0,
                    userTaskId: null,
                    assignedTo: null,
                    geofenceId: null,
                    latitude: null,
                    longitude: null,
                  );
                  try {
                    await _taskService.createTask(newTask);
                    _fetchTasks();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Task added successfully!')),
                    );
                    Navigator.of(context).pop();
                  } catch (e) {
                    debugPrint('Error adding task: $e');
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to add task: $e')),
                    );
                  }
                }
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _editTask(Task task) async {
    final TextEditingController titleController = TextEditingController(
      text: task.title,
    );
    final TextEditingController descriptionController = TextEditingController(
      text: task.description,
    );
    DateTime? dueDate = task.dueDate;
    String taskType = task.type ?? 'general';
    String taskDifficulty = task.difficulty ?? 'medium';

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Edit Task'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
                ListTile(
                  title: Text(
                    dueDate == null
                        ? 'Select Due Date'
                        : 'Due Date: ${dueDate!.toLocal().toString().split(' ')[0]}',
                  ),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    dueDate = await showDatePicker(
                      context: context,
                      initialDate: dueDate ?? DateTime.now(),
                      firstDate: DateTime.now(),
                      lastDate: DateTime(2100),
                    );
                    // This setState is to update the dialog's UI
                    if (mounted) {
                      setState(() {});
                    }
                  },
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                if (titleController.text.isNotEmpty &&
                    descriptionController.text.isNotEmpty &&
                    dueDate != null) {
                  final updatedTask = task.copyWith(
                    title: titleController.text,
                    description: descriptionController.text,
                    type: taskType,
                    difficulty: taskDifficulty,
                    dueDate: dueDate!,
                  );
                  try {
                    await _taskService.updateTask(updatedTask);
                    _fetchTasks();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Task updated successfully!'),
                      ),
                    );
                    Navigator.of(context).pop();
                  } catch (e) {
                    debugPrint('Error updating task: $e');
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to update task: $e')),
                    );
                  }
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteTask(String taskId) async {
    final bool confirmDelete =
        await showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('Confirm Delete'),
              content: const Text('Are you sure you want to delete this task?'),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Delete'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (confirmDelete) {
      try {
        await _taskService.deleteTask(taskId);
        _fetchTasks(); // Refresh the task list
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Task deleted successfully!')),
        );
      } catch (e) {
        debugPrint('Error deleting task: $e');
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to delete task: $e')));
      }
    }
  }

  Future<void> _assignTask(Task task) async {
    List<UserModel> employees = [];
    try {
      employees = await _userService.fetchEmployees();
      if (employees.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No employees available')),
          );
        }
        return;
      }
      employees = employees.where((e) => e.id.isNotEmpty).toList();
      if (employees.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No valid employees found')),
          );
        }
        return;
      }
    } catch (e) {
      debugPrint('Error fetching employees: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to fetch employees: $e')),
        );
      }
      return;
    }

    final Map<String, _AvailabilityInfo> availability = {};
    try {
      final nearby = await _availabilityService.getNearbyForTask(task.id);
      for (final item in nearby) {
        final String userId = (item['userId'] ?? '') as String;
        if (userId.isEmpty) continue;
        availability[userId] = _AvailabilityInfo(
          distanceMeters: (item['distanceMeters'] is num)
              ? (item['distanceMeters'] as num).toDouble()
              : 0,
          activeTasksCount: item['activeTasksCount'] is int
              ? item['activeTasksCount'] as int
              : (item['activeTasksCount'] ?? 0) as int,
          overdueTasksCount: item['overdueTasksCount'] is int
              ? item['overdueTasksCount'] as int
              : (item['overdueTasksCount'] ?? 0) as int,
          workloadStatus: (item['workloadStatus'] ?? 'available') as String,
        );
      }
    } catch (e) {
      debugPrint('Error fetching nearby availability: $e');
    }

    final Set<String> selectedEmployeeIds = <String>{};
    final Set<String> overrideEmployeeIds = <String>{};
    if (task.assignedToMultiple.isNotEmpty) {
      selectedEmployeeIds.addAll(task.assignedToMultiple.map((u) => u.id));
    } else if (task.assignedTo != null) {
      selectedEmployeeIds.add(task.assignedTo!.id);
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, dialogSetState) => AlertDialog(
          title: Text('Assign Task: ${task.title}'),
          content: SizedBox(
            width: double.maxFinite,
            child: employees.isEmpty
                ? const Center(child: Text('No employees available'))
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: employees.length,
                    itemBuilder: (context, index) {
                      final employee = employees[index];
                      final isSelected = selectedEmployeeIds.contains(
                        employee.id,
                      );
                      final info = availability[employee.id];

                    final activeCount = info?.activeTasksCount ??
                        (_employeeActiveTaskCount[employee.id] ?? 0);
                    final atLimit = activeCount >= _taskLimitPerEmployee;
                    final isOverridden = overrideEmployeeIds.contains(
                      employee.id,
                    );

                    Color? nameColor;
                    if (info != null) {
                      switch (info.workloadStatus) {
                        case 'overloaded':
                          nameColor = Colors.redAccent;
                          break;
                        case 'busy':
                          nameColor = Colors.orange;
                          break;
                        default:
                          nameColor = Colors.green;
                      }
                    }

                    String subtitle = employee.email;
                    if (info != null) {
                      final parts = <String>[];
                      parts.add(info.workloadStatus);
                      if (info.activeTasksCount > 0) {
                        parts.add('${info.activeTasksCount} active');
                      }
                      if (info.overdueTasksCount > 0) {
                        parts.add('${info.overdueTasksCount} overdue');
                      }
                      if (info.distanceMeters > 0) {
                        if (info.distanceMeters >= 1000) {
                          parts.add(
                            '${(info.distanceMeters / 1000).toStringAsFixed(1)} km',
                          );
                        } else {
                          parts.add(
                            '${info.distanceMeters.toStringAsFixed(0)} m',
                          );
                        }
                      }
                      subtitle = '${employee.email} · ${parts.join(' · ')}';
                    }

                    if (atLimit) {
                      subtitle =
                          '$subtitle · limit reached ($_taskLimitPerEmployee)';
                    }

                      return CheckboxListTile(
                        key: ValueKey('assign:${employee.id}'),
                        title: Text(
                          employee.name,
                          style: TextStyle(color: nameColor),
                        ),
                        subtitle: Text(subtitle),
                        value: isSelected,
                        onChanged: (bool? selected) {
                          if (selected == true && atLimit && !isOverridden) {
                            showDialog<bool>(
                              context: context,
                              builder: (dCtx) => AlertDialog(
                                title: const Text('Employee at task limit'),
                                content: Text(
                                  '${employee.name} already has $activeCount active task(s), which is at/above the limit ($_taskLimitPerEmployee).\n\nOverride and assign anyway?',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(dCtx).pop(false),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(dCtx).pop(true),
                                    child: const Text('Override'),
                                  ),
                                ],
                              ),
                            ).then((allow) {
                              if (allow != true) return;
                              if (!mounted) return;
                              dialogSetState(() {
                                overrideEmployeeIds.add(employee.id);
                                selectedEmployeeIds.add(employee.id);
                              });
                            });
                            return;
                          }

                          dialogSetState(() {
                            if (selected == true) {
                              selectedEmployeeIds.add(employee.id);
                            } else {
                              selectedEmployeeIds.remove(employee.id);
                              overrideEmployeeIds.remove(employee.id);
                            }
                          });
                        },
                      );
                    },
                  ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                if (selectedEmployeeIds.isNotEmpty) {
                  try {
                    final validIds = selectedEmployeeIds
                        .where((id) => id.isNotEmpty)
                        .toList();
                    if (validIds.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Selected employees have invalid IDs'),
                        ),
                      );
                      return;
                    }

                    final blocked = validIds
                        .where((id) {
                          final info = availability[id];
                          final activeCount = info?.activeTasksCount ??
                              (_employeeActiveTaskCount[id] ?? 0);
                          return activeCount >= _taskLimitPerEmployee &&
                              !overrideEmployeeIds.contains(id);
                        })
                        .toList();
                    if (blocked.isNotEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Some selected employees are at the task limit ($_taskLimitPerEmployee). Use Override to assign anyway.',
                          ),
                        ),
                      );
                      return;
                    }

                    final result = await _taskService.assignTaskToMultiple(
                      task.id,
                      validIds,
                    );
                    _fetchTasks();

                    if (!mounted) return;

                    final summary = result['summary'] as Map<String, dynamic>?;
                    final total = summary?['total'] as int?;
                    final successful = summary?['successful'] as int?;
                    final failed = summary?['failed'] as int?;

                    String message;
                    if (summary != null &&
                        total != null &&
                        successful != null &&
                        failed != null) {
                      if (failed == 0) {
                        message =
                            'Task assigned to $successful of $total employees.';
                      } else if (successful == 0) {
                        message =
                            'Failed to assign task to all $total employees (check workload limits).';
                      } else {
                        message =
                            'Task assigned to $successful of $total employees. $failed failed (see workload limits).';
                      }
                    } else {
                      message = 'Task assignment request completed.';
                    }

                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(message)));

                    Navigator.of(ctx).pop();
                  } catch (e) {
                    debugPrint('Error assigning task: $e');
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to assign task: $e')),
                      );
                    }
                  }
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please select at least one employee'),
                    ),
                  );
                }
              },
              child: const Text('Assign'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Task Management'),
        backgroundColor: const Color(0xFF2688d4),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              setState(() => _sortBy = value);
            },
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem(
                value: 'dueDate',
                child: Text('Sort by Due Date'),
              ),
              const PopupMenuItem(
                value: 'difficulty',
                child: Text('Sort by Difficulty'),
              ),
              const PopupMenuItem(
                value: 'status',
                child: Text('Sort by Status'),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Center(
                child: Tooltip(
                  message: 'Sort tasks',
                  child: Icon(Icons.sort, color: Colors.white),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: ElevatedButton.icon(
              onPressed: _addTask,
              icon: const Icon(Icons.add),
              label: const Text('Create Task'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF2688d4),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ChoiceChip(
                  label: const Text('Current Tasks'),
                  selected: !_showArchived,
                  onSelected: (sel) {
                    if (!sel) return;
                    setState(() {
                      _showArchived = false;
                    });
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Archived Tasks'),
                  selected: _showArchived,
                  onSelected: (sel) {
                    if (!sel) return;
                    setState(() {
                      _showArchived = true;
                    });
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('All difficulties'),
                  selected: _difficultyFilter == 'all',
                  onSelected: (sel) {
                    if (!sel) return;
                    setState(() => _difficultyFilter = 'all');
                  },
                ),
                ChoiceChip(
                  label: const Text('Easy'),
                  selected: _difficultyFilter == 'easy',
                  onSelected: (sel) {
                    if (!sel) return;
                    setState(() => _difficultyFilter = 'easy');
                  },
                ),
                ChoiceChip(
                  label: const Text('Medium'),
                  selected: _difficultyFilter == 'medium',
                  onSelected: (sel) {
                    if (!sel) return;
                    setState(() => _difficultyFilter = 'medium');
                  },
                ),
                ChoiceChip(
                  label: const Text('Hard'),
                  selected: _difficultyFilter == 'hard',
                  onSelected: (sel) {
                    if (!sel) return;
                    setState(() => _difficultyFilter = 'hard');
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : () {
                    final source = _showArchived ? _archivedTasks : _tasks;
                    final filtered = source.where((task) {
                      if (_difficultyFilter == 'all') return true;
                      final d = (task.difficulty ?? '').toLowerCase();
                      return d == _difficultyFilter;
                    }).toList();

                    _sortTasks(filtered);

                    if (filtered.isEmpty) {
                      return Center(
                        child: Text(
                          _showArchived
                              ? 'No archived tasks.'
                              : 'No tasks available.',
                        ),
                      );
                    }

                    return ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final task = filtered[index];
                        final isOverdue = task.isOverdue;
                        return Card(
                          margin: const EdgeInsets.all(8.0),
                          child: ListTile(
                            title: Text(
                              task.title,
                              style: TextStyle(
                                color: isOverdue
                                    ? Colors.redAccent
                                    : Colors.black,
                                fontWeight: isOverdue
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(task.description),
                                if ((task.type != null &&
                                        task.type!.isNotEmpty) ||
                                    (task.difficulty != null &&
                                        task.difficulty!.isNotEmpty))
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4.0),
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
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!_showArchived) ...[
                                  IconButton(
                                    icon: const Icon(Icons.edit),
                                    onPressed: () => _editTask(task),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.assignment_ind),
                                    onPressed: () => _assignTask(task),
                                  ),
                                  PopupMenuButton<String>(
                                    icon: const Icon(Icons.more_vert),
                                    onSelected: (value) {
                                      switch (value) {
                                        case 'escalate':
                                          _escalateTask(task);
                                          break;
                                        case 'archive':
                                          _archiveTask(task);
                                          break;
                                      }
                                    },
                                    itemBuilder: (context) {
                                      final items = <PopupMenuEntry<String>>[];

                                      if (isOverdue &&
                                          task.status != 'completed') {
                                        items.add(
                                          const PopupMenuItem<String>(
                                            value: 'escalate',
                                            child: Text('Escalate (SMS)'),
                                          ),
                                        );
                                      }

                                      items.add(
                                        const PopupMenuItem<String>(
                                          value: 'archive',
                                          child: Text('Archive task'),
                                        ),
                                      );

                                      return items;
                                    },
                                  ),
                                ] else ...[
                                  PopupMenuButton<String>(
                                    icon: const Icon(Icons.more_vert),
                                    onSelected: (value) {
                                      switch (value) {
                                        case 'restore':
                                          _restoreTask(task);
                                          break;
                                        case 'delete':
                                          _deleteTask(task.id);
                                          break;
                                      }
                                    },
                                    itemBuilder: (context) =>
                                        <PopupMenuEntry<String>>[
                                          const PopupMenuItem<String>(
                                            value: 'restore',
                                            child: Text('Restore task'),
                                          ),
                                          const PopupMenuItem<String>(
                                            value: 'delete',
                                            child: Text('Delete task'),
                                          ),
                                        ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  }(),
          ),
        ],
      ),
    );
  }
}

class _AvailabilityInfo {
  final double distanceMeters;
  final int activeTasksCount;
  final int overdueTasksCount;
  final String workloadStatus;

  const _AvailabilityInfo({
    required this.distanceMeters,
    required this.activeTasksCount,
    required this.overdueTasksCount,
    required this.workloadStatus,
  });
}
