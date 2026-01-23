// ignore_for_file: use_build_context_synchronously, library_prefixes, unnecessary_null_aware_operator, unnecessary_null_comparison, unnecessary_non_null_assertion
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:field_check/services/task_service.dart';
import 'package:field_check/services/user_service.dart';
import 'package:field_check/services/availability_service.dart';
import 'package:field_check/models/task_model.dart';
import 'package:field_check/models/user_model.dart';
import 'package:field_check/services/settings_service.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:field_check/config/api_config.dart';
import 'package:field_check/utils/manila_time.dart';

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
  String _tab = 'current';
  String _difficultyFilter = 'all';
  String _sortBy = 'dueDate'; // 'dueDate', 'difficulty', 'status'
  late io.Socket _socket;

  // Workload tracking
  final Map<String, int> _employeeActiveTaskCount = {};
  final Map<String, double> _employeeDifficultyWeight = {};
  final Map<String, int> _employeeOverdueCount = {};

  static const int _taskLimitMin = 1;
  static const int _taskLimitMax = 50;

  int _taskLimitPerEmployee = 10;
  final Map<String, Set<String>> _taskAssignmentOverrides = {};

  Timer? _fetchDebounce;

  int _clampTaskLimit(int value) {
    return value.clamp(_taskLimitMin, _taskLimitMax);
  }

  String _canonicalUserId(UserModel user) {
    if (user.id.isNotEmpty) return user.id;
    final fallback = user.employeeId;
    return (fallback ?? '').trim();
  }

  @override
  void initState() {
    super.initState();
    _fetchTasks();
    _loadTaskLimit();
    _initSocket();
  }

  Future<void> _loadTaskLimit() async {
    try {
      final raw = await SettingsService().getSetting(
        'task.maxActivePerEmployee',
      );

      int? parsed;
      if (raw is num) {
        parsed = raw.toInt();
      } else if (raw is String) {
        parsed = int.tryParse(raw);
      } else if (raw is Map) {
        final m = Map<String, dynamic>.from(raw);
        final dynamic inner = m['maxActivePerEmployee'];
        if (inner is num) {
          parsed = inner.toInt();
        } else if (inner is String) {
          parsed = int.tryParse(inner);
        }
      }

      if (parsed != null && mounted) {
        final normalized = _clampTaskLimit(parsed);
        setState(() {
          _taskLimitPerEmployee = normalized;
        });
      }
    } catch (e) {
      debugPrint('Error loading task limit setting: $e');
    }
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
    _fetchDebounce?.cancel();
    _socket.disconnect();
    super.dispose();
  }

  void _scheduleFetchTasks() {
    _fetchDebounce?.cancel();
    _fetchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      _fetchTasks();
    });
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
        _scheduleFetchTasks();
      });

      _socket.on('updatedTask', (data) {
        debugPrint('Task updated: $data');
        _scheduleFetchTasks();
      });

      _socket.on('deletedTask', (data) {
        debugPrint('Task deleted: $data');
        _scheduleFetchTasks();
      });

      _socket.on('taskAssignedToMultiple', (data) {
        debugPrint('Task assigned to multiple: $data');
        _scheduleFetchTasks();
      });

      _socket.on('taskUnassigned', (data) {
        debugPrint('Task unassigned: $data');
        _scheduleFetchTasks();
      });

      _socket.on('userTaskArchived', (data) {
        debugPrint('User task archived: $data');
        _scheduleFetchTasks();
      });

      _socket.on('userTaskRestored', (data) {
        debugPrint('User task restored: $data');
        _scheduleFetchTasks();
      });
    });
  }

  Future<void> _fetchTasks() async {
    try {
      final current = await _taskService.getCurrentTasks();
      final archived = await _taskService.getArchivedTasks();
      if (!mounted) return;
      setState(() {
        _tasks = current;
        _archivedTasks = archived;
        _isLoading = false;
        _calculateWorkload();
      });
    } catch (e) {
      // Handle error
      debugPrint('Error fetching tasks: $e');
      if (!mounted) return;
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

      final Set<String> assigneeIds = <String>{
        ...task.assignedToMultiple
            .map(_canonicalUserId)
            .where((id) => id.isNotEmpty),
        ...?task.teamMembers?.where((id) => id.trim().isNotEmpty),
      };

      for (final userId in assigneeIds) {
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
    String? dialogError;
    bool isSubmitting = false;

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter dialogSetState) {
            return AlertDialog(
              title: const Text('Add New Task'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (dialogError != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: Colors.red.shade700,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                dialogError!,
                                style: TextStyle(color: Colors.red.shade800),
                              ),
                            ),
                          ],
                        ),
                      ),
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(labelText: 'Title'),
                      onChanged: (_) {
                        if (dialogError != null) {
                          dialogSetState(() => dialogError = null);
                        }
                      },
                    ),
                    TextField(
                      controller: descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                      ),
                      onChanged: (_) {
                        if (dialogError != null) {
                          dialogSetState(() => dialogError = null);
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: taskType,
                      decoration: const InputDecoration(labelText: 'Task Type'),
                      items: const [
                        DropdownMenuItem(
                          value: 'general',
                          child: Text('General'),
                        ),
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
                        dialogSetState(() {
                          taskType = value;
                          dialogError = null;
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: taskDifficulty,
                      decoration: const InputDecoration(
                        labelText: 'Difficulty',
                      ),
                      items: const [
                        DropdownMenuItem(value: 'easy', child: Text('Easy')),
                        DropdownMenuItem(
                          value: 'medium',
                          child: Text('Medium'),
                        ),
                        DropdownMenuItem(value: 'hard', child: Text('Hard')),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        dialogSetState(() {
                          taskDifficulty = value;
                          dialogError = null;
                        });
                      },
                    ),
                    ListTile(
                      title: Text(
                        dueDate == null
                            ? 'Due Date: (required)'
                            : 'Due Date: ${formatManila(dueDate, 'yyyy-MM-dd')}',
                      ),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: () async {
                        final DateTime? selected = await showDatePicker(
                          context: context,
                          initialDate: dueDate ?? DateTime.now(),
                          firstDate: DateTime.now(),
                          lastDate: DateTime(2100),
                        );
                        if (selected != null) {
                          dialogSetState(() {
                            dueDate = selected;
                            dialogError = null;
                          });
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final String title = titleController.text.trim();
                          final String description = descriptionController.text
                              .trim();

                          if (title.isEmpty) {
                            dialogSetState(() {
                              dialogError = 'Title is required.';
                            });
                            return;
                          }
                          if (description.isEmpty) {
                            dialogSetState(() {
                              dialogError = 'Description is required.';
                            });
                            return;
                          }
                          if (dueDate == null) {
                            dialogSetState(() {
                              dialogError = 'Due date is required.';
                            });
                            return;
                          }

                          dialogSetState(() {
                            dialogError = null;
                            isSubmitting = true;
                          });

                          final newTask = Task(
                            id: '', // ID will be generated by the backend
                            title: title,
                            description: description,
                            type: taskType,
                            difficulty: taskDifficulty,
                            dueDate: dueDate!,
                            assignedBy:
                                _userService.currentUser?.id ?? 'unknown_admin',
                            createdAt: DateTime.now(),
                            updatedAt: DateTime.now(),
                            lastViewedAt: null,
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
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Task added successfully!'),
                                ),
                              );
                            }
                            Navigator.of(context).pop();
                          } catch (e) {
                            debugPrint('Error adding task: $e');
                            dialogSetState(() {
                              dialogError = 'Failed to add task: $e';
                              isSubmitting = false;
                            });
                          }
                        },
                  child: const Text('Add'),
                ),
              ],
            );
          },
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
    String? dialogError;
    bool isSubmitting = false;

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter dialogSetState) {
            return AlertDialog(
              title: const Text('Edit Task'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (dialogError != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: Colors.red.shade700,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                dialogError!,
                                style: TextStyle(color: Colors.red.shade800),
                              ),
                            ),
                          ],
                        ),
                      ),
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(labelText: 'Title'),
                      onChanged: (_) {
                        if (dialogError != null) {
                          dialogSetState(() => dialogError = null);
                        }
                      },
                    ),
                    TextField(
                      controller: descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                      ),
                      onChanged: (_) {
                        if (dialogError != null) {
                          dialogSetState(() => dialogError = null);
                        }
                      },
                    ),
                    ListTile(
                      title: Text(
                        dueDate == null
                            ? 'Due Date: (required)'
                            : 'Due Date: ${formatManila(dueDate, 'yyyy-MM-dd')}',
                      ),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: () async {
                        final DateTime? selected = await showDatePicker(
                          context: context,
                          initialDate: dueDate ?? DateTime.now(),
                          firstDate: DateTime.now(),
                          lastDate: DateTime(2100),
                        );
                        if (selected != null) {
                          dialogSetState(() {
                            dueDate = selected;
                            dialogError = null;
                          });
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final String title = titleController.text.trim();
                          final String description = descriptionController.text
                              .trim();

                          if (title.isEmpty) {
                            dialogSetState(() {
                              dialogError = 'Title is required.';
                            });
                            return;
                          }
                          if (description.isEmpty) {
                            dialogSetState(() {
                              dialogError = 'Description is required.';
                            });
                            return;
                          }
                          if (dueDate == null) {
                            dialogSetState(() {
                              dialogError = 'Due date is required.';
                            });
                            return;
                          }

                          dialogSetState(() {
                            dialogError = null;
                            isSubmitting = true;
                          });

                          final updatedTask = task.copyWith(
                            title: title,
                            description: description,
                            type: taskType,
                            difficulty: taskDifficulty,
                            dueDate: dueDate!,
                          );
                          try {
                            await _taskService.updateTask(updatedTask);
                            _fetchTasks();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Task updated successfully!'),
                                ),
                              );
                            }
                            Navigator.of(context).pop();
                          } catch (e) {
                            debugPrint('Error updating task: $e');
                            dialogSetState(() {
                              dialogError = 'Failed to update task: $e';
                              isSubmitting = false;
                            });
                          }
                        },
                  child: const Text('Save'),
                ),
              ],
            );
          },
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

    final Map<String, String> assigneeIdToEmployeeModelId = {};
    for (final e in employees) {
      if (e.id.isNotEmpty) {
        assigneeIdToEmployeeModelId[e.id] = e.id;
      }
      final empId = e.employeeId;
      if (empId != null && empId.trim().isNotEmpty) {
        assigneeIdToEmployeeModelId[empId] = e.id;
      }
    }

    final Map<String, _AvailabilityInfo> availability = {};
    final Set<String> availabilityAssignedIds = <String>{};
    try {
      final nearby = await _availabilityService.getNearbyForTask(task.id);
      assert(() {
        if (nearby.isNotEmpty) {
          try {
            final first = nearby.first;
            debugPrint(
              'Assign dialog debug: availability first keys=${first.keys.toList()}',
            );
          } catch (_) {}
        }
        return true;
      }());
      for (final item in nearby) {
        final dynamic rawId =
            item['userId'] ?? item['employeeId'] ?? item['_id'] ?? item['id'];
        final String idStr = (rawId ?? '').toString();
        if (idStr.isEmpty) continue;
        final String normalizedId = assigneeIdToEmployeeModelId[idStr] ?? idStr;

        final dynamic assignedValue =
            item['isAssigned'] ??
            item['assigned'] ??
            item['assignedToTask'] ??
            item['isAssignedToTask'] ??
            item['alreadyAssigned'] ??
            item['hasTask'] ??
            item['hasThisTask'];
        final bool isAssignedFlag =
            assignedValue == true || assignedValue == 'true';
        if (isAssignedFlag) {
          availabilityAssignedIds.add(normalizedId);
        }

        availability[normalizedId] = _AvailabilityInfo(
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

    Task serverTask = task;
    try {
      serverTask = await _taskService.getTaskById(task.id);
    } catch (e) {
      debugPrint('Error fetching task details for assignment: $e');
    }

    List<String> serverAssigneeIdsFromApi = <String>[];
    try {
      serverAssigneeIdsFromApi = await _taskService.getAssigneeIdsForTask(
        task.id,
      );
    } catch (e) {
      debugPrint('Error fetching task assignees for assignment: $e');
    }

    assert(() {
      final assignedIds = serverTask.assignedToMultiple
          .map(_canonicalUserId)
          .where((id) => id.isNotEmpty)
          .toList();
      debugPrint(
        'Assign dialog debug: taskId=${task.id} assignedToMultipleIds=$assignedIds teamMembers=${serverTask.teamMembers}',
      );
      final sampleEmployees = employees
          .take(5)
          .map((e) => 'id=${e.id}, employeeId=${e.employeeId}')
          .toList();
      debugPrint('Assign dialog debug: sample employees: $sampleEmployees');
      debugPrint(
        'Assign dialog debug: assigneeIdToEmployeeModelId keys sample: ${assigneeIdToEmployeeModelId.keys.take(10).toList()}',
      );
      return true;
    }());

    final selectedEmployeeIds = <String>{};
    final overrideEmployeeIds = _taskAssignmentOverrides[task.id] ?? <String>{};

    if (serverAssigneeIdsFromApi.isNotEmpty) {
      selectedEmployeeIds.addAll(
        serverAssigneeIdsFromApi
            .map((raw) => assigneeIdToEmployeeModelId[raw] ?? raw)
            .where((id) => id.isNotEmpty),
      );
    }

    final initialSelectedEmployeeIds = <String>{...selectedEmployeeIds};

    assert(() {
      if (availabilityAssignedIds.isNotEmpty) {
        debugPrint(
          'Assign dialog debug: availabilityAssignedIds=$availabilityAssignedIds',
        );
      }
      debugPrint(
        'Assign dialog debug: selectedEmployeeIds(initial)=${selectedEmployeeIds.toList()} (count=${selectedEmployeeIds.length})',
      );
      return true;
    }());

    _taskAssignmentOverrides[task.id] = overrideEmployeeIds;

    if (!mounted) return;

    bool replaceAssignees = false;

    String? dialogNotice;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, dialogSetState) {
          void showDialogNotice(String message) {
            dialogSetState(() {
              dialogNotice = message;
            });
          }

          return AlertDialog(
            title: Text('Assign Task: ${task.title}'),
            content: SizedBox(
              width: double.maxFinite,
              height: 520,
              child: Column(
                children: [
                  if (dialogNotice != null)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.orange.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.orange,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Action needed',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: Colors.orange,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  dialogNotice!,
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.85),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Dismiss',
                            onPressed: () {
                              dialogSetState(() {
                                dialogNotice = null;
                              });
                            },
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                  SwitchListTile(
                    title: const Text('Replace assignees'),
                    subtitle: const Text(
                      'When enabled, unchecking an employee will unassign them from this task.',
                    ),
                    value: replaceAssignees,
                    onChanged: (val) {
                      dialogSetState(() {
                        replaceAssignees = val;
                      });
                    },
                  ),
                  const Divider(height: 1),
                  Expanded(
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

                              final int activeCount = [
                                info?.activeTasksCount ?? 0,
                                _employeeActiveTaskCount[employee.id] ?? 0,
                                employee.activeTaskCount ?? 0,
                              ].reduce((a, b) => a > b ? a : b);
                              final atLimit =
                                  activeCount >= _taskLimitPerEmployee;
                              final isOverridden = overrideEmployeeIds.contains(
                                employee.id,
                              );
                              final isAlreadyAssigned =
                                  initialSelectedEmployeeIds.contains(
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
                                  parts.add(
                                    '${info.overdueTasksCount} overdue',
                                  );
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
                                subtitle =
                                    '${employee.email} · ${parts.join(' · ')}';
                              }

                              if (atLimit &&
                                  !(isAlreadyAssigned && isSelected)) {
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
                                  final isNewlySelecting =
                                      selected == true && !isAlreadyAssigned;

                                  if (isNewlySelecting &&
                                      atLimit &&
                                      !isOverridden) {
                                    showDialogNotice(
                                      '${employee.name} is already at/above the max active tasks ($_taskLimitPerEmployee). Use Override to assign anyway, or unassign/archive some tasks first.',
                                    );
                                    showDialog<bool>(
                                      context: context,
                                      builder: (dCtx) => AlertDialog(
                                        title: const Text(
                                          'Employee at task limit',
                                        ),
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
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: initialSelectedEmployeeIds.isEmpty
                    ? null
                    : () async {
                        final bool confirm =
                            await showDialog<bool>(
                              context: context,
                              builder: (dCtx) => AlertDialog(
                                title: const Text('Unassign all assignees?'),
                                content: const Text(
                                  'This will remove all current assignees from this task.',
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
                                    child: const Text('Unassign all'),
                                  ),
                                ],
                              ),
                            ) ??
                            false;

                        if (!confirm) return;

                        try {
                          await Future.wait(
                            initialSelectedEmployeeIds.map(
                              (id) => _taskService.unassignUserFromTask(
                                task.id,
                                id,
                              ),
                            ),
                          );

                          selectedEmployeeIds.clear();
                          overrideEmployeeIds.clear();

                          _fetchTasks();

                          if (!mounted) return;
                          Navigator.of(ctx).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('All assignees unassigned.'),
                            ),
                          );
                        } catch (e) {
                          debugPrint('Error unassigning all: $e');
                          if (!mounted) return;
                          showDialogNotice(
                            'Failed to unassign all assignees: $e',
                          );
                        }
                      },
                child: const Text('Unassign all'),
              ),
              TextButton(
                onPressed: () async {
                  if (selectedEmployeeIds.isNotEmpty || replaceAssignees) {
                    try {
                      final validIds = selectedEmployeeIds
                          .where((id) => id.isNotEmpty)
                          .toList();
                      if (validIds.isEmpty && !replaceAssignees) {
                        showDialogNotice('Selected employees have invalid IDs');
                        return;
                      }

                      final idsToAssign = replaceAssignees
                          ? validIds
                                .where(
                                  (id) =>
                                      !initialSelectedEmployeeIds.contains(id),
                                )
                                .toList()
                          : validIds;
                      final idsToUnassign = replaceAssignees
                          ? initialSelectedEmployeeIds
                                .where(
                                  (id) => !selectedEmployeeIds.contains(id),
                                )
                                .toList()
                          : <String>[];

                      final blocked = idsToAssign.where((id) {
                        final info = availability[id];
                        final employee = employees
                            .where((e) => e.id == id)
                            .cast<UserModel?>()
                            .firstWhere((_) => true, orElse: () => null);
                        final activeCount = [
                          info?.activeTasksCount ?? 0,
                          _employeeActiveTaskCount[id] ?? 0,
                          employee?.activeTaskCount ?? 0,
                        ].reduce((a, b) => a > b ? a : b);
                        return activeCount >= _taskLimitPerEmployee &&
                            !overrideEmployeeIds.contains(id);
                      }).toList();
                      if (blocked.isNotEmpty) {
                        showDialogNotice(
                          'Some selected employees are at the task limit ($_taskLimitPerEmployee). Tap the employee again and choose Override, or deselect them.',
                        );
                        return;
                      }

                      Map<String, dynamic> result = <String, dynamic>{};
                      if (idsToAssign.isNotEmpty) {
                        result = await _taskService.assignTaskToMultiple(
                          task.id,
                          idsToAssign,
                        );
                      }

                      if (idsToUnassign.isNotEmpty) {
                        await Future.wait(
                          idsToUnassign.map(
                            (id) =>
                                _taskService.unassignUserFromTask(task.id, id),
                          ),
                        );
                      }
                      _fetchTasks();

                      if (!mounted) return;

                      _taskAssignmentOverrides.remove(task.id);

                      final summary =
                          result['summary'] as Map<String, dynamic>?;
                      final total = summary?['total'] as int?;
                      final successful = summary?['successful'] as int?;
                      final failed = summary?['failed'] as int?;

                      String message;
                      if (replaceAssignees) {
                        final assignedCount = idsToAssign.length;
                        final unassignedCount = idsToUnassign.length;
                        if (assignedCount == 0 && unassignedCount == 0) {
                          message = 'No changes to task assignees.';
                        } else if (assignedCount > 0 && unassignedCount > 0) {
                          message =
                              'Assignees updated. Added $assignedCount, removed $unassignedCount.';
                        } else if (assignedCount > 0) {
                          message = 'Assignees updated. Added $assignedCount.';
                        } else {
                          message =
                              'Assignees updated. Removed $unassignedCount.';
                        }
                      } else if (summary != null &&
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

                      if (!replaceAssignees &&
                          summary != null &&
                          total != null &&
                          successful != null &&
                          failed != null &&
                          failed > 0) {
                        showDialogNotice(message);
                        return;
                      }

                      Navigator.of(ctx).pop();
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text(message)));
                      });
                    } catch (e) {
                      debugPrint('Error assigning task: $e');
                      if (mounted) {
                        showDialogNotice('Failed to assign task: $e');
                      }
                    }
                  } else {
                    showDialogNotice('Please select at least one employee');
                  }
                },
                child: Text(replaceAssignees ? 'Apply' : 'Assign'),
              ),
            ],
          );
        },
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
                  selected: _tab == 'current',
                  onSelected: (sel) {
                    if (!sel) return;
                    setState(() {
                      _tab = 'current';
                    });
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Overdue Tasks'),
                  selected: _tab == 'expired',
                  onSelected: (sel) {
                    if (!sel) return;
                    setState(() {
                      _tab = 'expired';
                    });
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Archived Tasks'),
                  selected: _tab == 'archived',
                  onSelected: (sel) {
                    if (!sel) return;
                    setState(() {
                      _tab = 'archived';
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
                    final List<Task> source;
                    if (_tab == 'archived') {
                      source = _archivedTasks;
                    } else {
                      source = _tasks;
                    }

                    final filtered = source.where((task) {
                      // Tab filtering
                      if (_tab == 'current' && task.isOverdue) {
                        return false;
                      }
                      if (_tab == 'expired' && !task.isOverdue) {
                        return false;
                      }

                      // Difficulty filtering
                      if (_difficultyFilter == 'all') return true;
                      final d = (task.difficulty ?? '').toLowerCase();
                      return d == _difficultyFilter;
                    }).toList();

                    _sortTasks(filtered);

                    if (filtered.isEmpty) {
                      return Center(
                        child: Text(
                          _tab == 'archived'
                              ? 'No archived tasks.'
                              : _tab == 'expired'
                              ? 'No expired tasks.'
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
                                if (_tab == 'current') ...[
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
                                ] else if (_tab == 'expired') ...[
                                  IconButton(
                                    icon: const Icon(Icons.edit),
                                    onPressed: () => _editTask(task),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.assignment_ind),
                                    onPressed: () => _assignTask(task),
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      Icons.delete,
                                      color: Colors.redAccent,
                                    ),
                                    tooltip: 'Delete task',
                                    onPressed: () => _deleteTask(task.id),
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
                                  IconButton(
                                    icon: const Icon(Icons.restore),
                                    tooltip: 'Restore task',
                                    onPressed: () => _restoreTask(task),
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      Icons.delete,
                                      color: Colors.redAccent,
                                    ),
                                    tooltip: 'Delete task',
                                    onPressed: () => _deleteTask(task.id),
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
