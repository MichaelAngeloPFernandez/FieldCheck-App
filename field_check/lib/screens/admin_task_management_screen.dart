// ignore_for_file: use_build_context_synchronously, library_prefixes
import 'package:flutter/material.dart';
import 'package:field_check/services/task_service.dart';
import 'package:field_check/services/user_service.dart';
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
  List<Task> _tasks = [];
  bool _isLoading = true;
  late io.Socket _socket;

  @override
  void initState() {
    super.initState();
    _fetchTasks();
    _initSocket();
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
      final tasks = await _taskService.fetchAllTasks();
      setState(() {
        _tasks = tasks;
        _isLoading = false;
      });
    } catch (e) {
      // Handle error
      debugPrint('Error fetching tasks: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _addTask() async {
    final TextEditingController titleController = TextEditingController();
    final TextEditingController descriptionController = TextEditingController();
    DateTime? dueDate;

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
                    dueDate: dueDate!,
                    assignedBy: _userService.currentUser?.id ?? 'unknown_admin',
                    createdAt: DateTime.now(),
                    status: 'pending',
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
    } catch (e) {
      debugPrint('Error fetching employees: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to fetch employees: $e')));
      return;
    }

    UserModel? selectedEmployee = task.assignedTo;

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Assign Task'),
          content: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButton<UserModel>(
                    value: selectedEmployee,
                    hint: const Text('Select Employee'),
                    onChanged: (UserModel? newValue) {
                      setState(() {
                        selectedEmployee = newValue;
                      });
                    },
                    items: employees.map<DropdownMenuItem<UserModel>>((
                      UserModel user,
                    ) {
                      return DropdownMenuItem<UserModel>(
                        value: user,
                        child: Text(user.name),
                      );
                    }).toList(),
                  ),
                ],
              );
            },
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                if (selectedEmployee != null) {
                  try {
                    await _taskService.assignTask(
                      task.id,
                      selectedEmployee!.id,
                    );
                    _fetchTasks(); // Refresh the task list
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Task assigned successfully!'),
                      ),
                    );
                    Navigator.of(context).pop();
                  } catch (e) {
                    debugPrint('Error assigning task: $e');
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to assign task: $e')),
                    );
                  }
                }
              },
              child: const Text('Assign'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin Task Management')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _tasks.isEmpty
          ? const Center(child: Text('No tasks available.'))
          : ListView.builder(
              itemCount: _tasks.length,
              itemBuilder: (context, index) {
                final task = _tasks[index];
                return Card(
                  margin: const EdgeInsets.all(8.0),
                  child: ListTile(
                    title: Text(task.title),
                    subtitle: Text(task.description),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () => _editTask(task),
                        ),
                        IconButton(
                          icon: const Icon(Icons.assignment_ind),
                          onPressed: () => _assignTask(task),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete),
                          onPressed: () => _deleteTask(task.id),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'admin_tasks_fab',
        onPressed: _addTask,
        child: const Icon(Icons.add),
      ),
    );
  }
}
