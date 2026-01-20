import '../models/task_model.dart';
import '../models/user_task_model.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'user_service.dart';
import '../config/api_config.dart';

class TaskService {
  final String _baseUrl = '${ApiConfig.baseUrl}/api/tasks';
  final String _appNotificationsBaseUrl =
      '${ApiConfig.baseUrl}/api/app-notifications';

  Future<Map<String, String>> _headers({bool jsonContent = true}) async {
    final headers = <String, String>{};
    if (jsonContent) headers['Content-Type'] = 'application/json';
    final token = await UserService().getToken();
    if (token != null) headers['Authorization'] = 'Bearer $token';
    return headers;
  }

  Future<Task> getTaskById(String taskId) async {
    final response = await http
        .get(
          Uri.parse('$_baseUrl/$taskId'),
          headers: await _headers(jsonContent: false),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final decoded = json.decode(response.body);
      assert(() {
        try {
          if (decoded is Map) {
            final m = Map<String, dynamic>.from(decoded);
            debugPrint(
              'getTaskById debug: taskId=$taskId keys=${m.keys.toList()}',
            );
            const probeKeys = <String>[
              'assignedToMultiple',
              'assignedTo',
              'teamMembers',
              'userIds',
              'assignees',
              'assignedEmployees',
              'assignedUsers',
              'assignedToMultipleIds',
              'assignedUserIds',
              'userTaskIds',
              'userTasks',
            ];
            for (final k in probeKeys) {
              if (m.containsKey(k)) {
                debugPrint('getTaskById debug: $k=${m[k]}');
              }
            }
          } else {
            debugPrint(
              'getTaskById debug: taskId=$taskId decodedType=${decoded.runtimeType}',
            );
          }
        } catch (e) {
          debugPrint('getTaskById debug: error printing decoded: $e');
        }
        return true;
      }());
      if (decoded is Map<String, dynamic>) {
        return Task.fromJson(decoded);
      }
      if (decoded is Map) {
        return Task.fromJson(Map<String, dynamic>.from(decoded));
      }
      throw Exception('Invalid task response');
    }
    throw Exception('Failed to load task');
  }

  Future<List<String>> getAssigneeIdsForTask(String taskId) async {
    final response = await http
        .get(
          Uri.parse('$_baseUrl/$taskId/assignees'),
          headers: await _headers(jsonContent: false),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 404) {
      return <String>[];
    }

    if (response.statusCode != 200) {
      throw Exception('Failed to load task assignees');
    }

    if (response.body.isEmpty) return <String>[];

    final decoded = json.decode(response.body);
    if (decoded is List) {
      return decoded
          .map((e) => e.toString())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    if (decoded is Map) {
      final m = Map<String, dynamic>.from(decoded);
      final dynamic ids =
          m['userIds'] ?? m['assigneeIds'] ?? m['assignees'] ?? m['employees'];
      if (ids is List) {
        return ids
            .map((e) {
              if (e is Map) {
                final mm = Map<String, dynamic>.from(e);
                return (mm['userId'] ??
                        mm['_id'] ??
                        mm['id'] ??
                        mm['employeeId'] ??
                        '')
                    .toString();
              }
              return e.toString();
            })
            .where((s) => s.isNotEmpty)
            .toList();
      }
    }
    return <String>[];
  }

  /// Fetch non-archived (current) tasks
  Future<List<Task>> getCurrentTasks() async {
    final response = await http
        .get(
          Uri.parse('$_baseUrl?archived=false'),
          headers: await _headers(jsonContent: false),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final Iterable l = json.decode(response.body);
      return List<Task>.from(l.map((model) => Task.fromJson(model)));
    } else {
      throw Exception('Failed to load current tasks');
    }
  }

  Future<void> archiveUserTask(String userTaskId) async {
    final response = await http.put(
      Uri.parse('$_baseUrl/user-task/$userTaskId/archive'),
      headers: await _headers(),
    );

    if (response.statusCode != 200) {
      String message = 'Failed to archive task';
      if (response.body.isNotEmpty) {
        try {
          final decoded = json.decode(response.body);
          if (decoded is Map<String, dynamic> && decoded['message'] is String) {
            message = decoded['message'] as String;
          } else {
            message = response.body;
          }
        } catch (_) {
          message = response.body;
        }
      }
      throw Exception(message);
    }
  }

  Future<void> restoreUserTask(String userTaskId) async {
    final response = await http.put(
      Uri.parse('$_baseUrl/user-task/$userTaskId/restore'),
      headers: await _headers(),
    );

    if (response.statusCode != 200) {
      String message = 'Failed to restore task';
      if (response.body.isNotEmpty) {
        try {
          final decoded = json.decode(response.body);
          if (decoded is Map<String, dynamic> && decoded['message'] is String) {
            message = decoded['message'] as String;
          } else {
            message = response.body;
          }
        } catch (_) {
          message = response.body;
        }
      }
      throw Exception(message);
    }
  }

  /// Fetch archived tasks
  Future<List<Task>> getArchivedTasks() async {
    final response = await http
        .get(
          Uri.parse('$_baseUrl?archived=true'),
          headers: await _headers(jsonContent: false),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final Iterable l = json.decode(response.body);
      return List<Task>.from(l.map((model) => Task.fromJson(model)));
    } else {
      throw Exception('Failed to load archived tasks');
    }
  }

  /// Fetch overdue, non-archived tasks (admin only)
  Future<List<Task>> getOverdueTasks() async {
    // Prefer dedicated backend endpoint when available
    try {
      final response = await http
          .get(
            Uri.parse('$_baseUrl/overdue'),
            headers: await _headers(jsonContent: false),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final Iterable l = json.decode(response.body);
        return List<Task>.from(l.map((model) => Task.fromJson(model)));
      }
    } catch (_) {
      // Ignore and fall back to client-side filtering
    }

    // Fallback: reuse current tasks and filter by isOverdue flag set by backend
    final current = await getCurrentTasks();
    return current.where((t) => t.isOverdue).toList();
  }

  Future<List<Task>> fetchAllTasks() async {
    final response = await http
        .get(Uri.parse(_baseUrl), headers: await _headers(jsonContent: false))
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      Iterable l = json.decode(response.body);
      return List<Task>.from(l.map((model) => Task.fromJson(model)));
    } else {
      throw Exception('Failed to load tasks');
    }
  }

  Future<Task> createTask(Task task) async {
    final payload = {
      'title': task.title,
      'description': task.description,
      'dueDate': task.dueDate.toIso8601String(),
      'status': task.status,
      'geofenceId': task.geofenceId,
      'type': task.type,
      'difficulty': task.difficulty,
    };
    final response = await http.post(
      Uri.parse(_baseUrl),
      headers: await _headers(),
      body: json.encode(payload),
    );

    if (response.statusCode == 201 || response.statusCode == 200) {
      return Task.fromJson(json.decode(response.body));
    } else {
      throw Exception('Failed to create task');
    }
  }

  Future<void> updateTask(Task task) async {
    final payload = {
      'title': task.title,
      'description': task.description,
      'dueDate': task.dueDate.toIso8601String(),
      'status': task.status,
      'geofenceId': task.geofenceId,
      'type': task.type,
      'difficulty': task.difficulty,
    };
    final response = await http.put(
      Uri.parse('$_baseUrl/${task.id}'),
      headers: await _headers(),
      body: json.encode(payload),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to update task');
    }
  }

  Future<void> assignTask(String taskId, String employeeId) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/$taskId/assign/$employeeId'),
      headers: await _headers(),
    );

    if (!(response.statusCode == 201 || response.statusCode == 200)) {
      throw Exception('Failed to assign task');
    }
  }

  Future<Map<String, dynamic>> assignTaskToMultiple(
    String taskId,
    List<String> employeeIds,
  ) async {
    final response = await http
        .post(
          Uri.parse('$_baseUrl/$taskId/assign-multiple'),
          headers: await _headers(),
          body: json.encode({'userIds': employeeIds}),
        )
        .timeout(const Duration(seconds: 30));

    final bool ok = response.statusCode == 201 || response.statusCode == 200;

    dynamic decoded;
    if (response.body.isNotEmpty) {
      try {
        decoded = json.decode(response.body);
      } catch (_) {
        decoded = null;
      }
    }

    if (!ok) {
      String message = 'Failed to assign task to multiple employees';
      if (decoded is Map<String, dynamic>) {
        if (decoded['message'] is String) {
          message = decoded['message'] as String;
        } else if (decoded['summary'] is Map<String, dynamic>) {
          final summary = decoded['summary'] as Map<String, dynamic>;
          final total = summary['total'];
          final failed = summary['failed'];
          if (total is int && failed is int) {
            message =
                'Failed to assign task to $failed of $total employees (see details).';
          }
        }
      } else if (response.body.isNotEmpty) {
        message = response.body;
      }
      throw Exception(message);
    }

    if (decoded is Map<String, dynamic>) {
      return decoded;
    }

    return <String, dynamic>{};
  }

  Future<UserTask> assignTaskToUser(String taskId, String userModelId) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/$taskId/assign/$userModelId'),
      headers: await _headers(),
    );

    if (response.statusCode == 201 || response.statusCode == 200) {
      return UserTask.fromJson(json.decode(response.body));
    } else {
      throw Exception('Failed to assign task to user');
    }
  }

  Future<void> unassignUserFromTask(String taskId, String userId) async {
    final response = await http
        .delete(
          Uri.parse('$_baseUrl/$taskId/unassign/$userId'),
          headers: await _headers(jsonContent: false),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 200 ||
        response.statusCode == 204 ||
        response.statusCode == 404) {
      return;
    }

    String message = 'Failed to unassign user from task';
    if (response.body.isNotEmpty) {
      try {
        final decoded = json.decode(response.body);
        if (decoded is Map<String, dynamic> && decoded['message'] is String) {
          message = decoded['message'] as String;
        } else {
          message = response.body;
        }
      } catch (_) {
        message = response.body;
      }
    }
    throw Exception(message);
  }

  Future<void> deleteTask(String taskId) async {
    final response = await http.delete(
      Uri.parse('$_baseUrl/$taskId'),
      headers: await _headers(jsonContent: false),
    );

    if (response.statusCode != 204) {
      throw Exception('Failed to delete task');
    }
  }

  Future<List<UserTask>> fetchUserTasks(String userModelId) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/user/$userModelId'),
      headers: await _headers(jsonContent: false),
    );

    if (response.statusCode == 200) {
      Iterable l = json.decode(response.body);
      return List<UserTask>.from(l.map((model) => UserTask.fromJson(model)));
    } else {
      throw Exception('Failed to load user tasks');
    }
  }

  Future<List<Task>> fetchAssignedTasks(
    String userModelId, {
    bool archived = false,
  }) async {
    final query = archived ? 'true' : 'false';
    final response = await http
        .get(
          Uri.parse('$_baseUrl/assigned/$userModelId?archived=$query'),
          headers: await _headers(jsonContent: false),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      Iterable l = json.decode(response.body);
      return List<Task>.from(l.map((model) => Task.fromJson(model)));
    } else {
      throw Exception('Failed to load assigned tasks');
    }
  }

  Future<void> updateUserTaskStatus(String userTaskId, String status) async {
    final response = await http.put(
      Uri.parse('$_baseUrl/user-task/$userTaskId/status'),
      headers: await _headers(),
      body: json.encode({'status': status}),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to update user task status');
    }
  }

  Future<void> markTasksScopeRead() async {
    final response = await http.post(
      Uri.parse('$_appNotificationsBaseUrl/mark-read-scope'),
      headers: await _headers(),
      body: json.encode({'scope': 'tasks'}),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to mark tasks read');
    }
  }

  Future<Map<String, dynamic>> fetchUnreadCounts() async {
    final response = await http
        .get(
          Uri.parse('$_appNotificationsBaseUrl/unread-count'),
          headers: await _headers(jsonContent: false),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('Failed to load unread counts');
    }

    final decoded = json.decode(response.body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
    return <String, dynamic>{};
  }

  Future<int> fetchTasksUnreadCount() async {
    final counts = await fetchUnreadCounts();
    final raw = counts['tasks'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }

  Future<DateTime?> markUserTaskViewed(String userTaskId) async {
    final response = await http.put(
      Uri.parse('$_baseUrl/user-task/$userTaskId/view'),
      headers: await _headers(),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to mark task viewed');
    }

    if (response.body.isEmpty) return null;
    final decoded = json.decode(response.body);
    if (decoded is Map<String, dynamic>) {
      final raw = decoded['lastViewedAt']?.toString();
      if (raw == null) return null;
      return DateTime.tryParse(raw);
    }
    return null;
  }

  Future<Task> updateTaskChecklistItem({
    required String taskId,
    required int index,
    required bool isCompleted,
  }) async {
    final response = await http
        .put(
          Uri.parse('$_baseUrl/$taskId/checklist-item'),
          headers: await _headers(),
          body: json.encode({'index': index, 'isCompleted': isCompleted}),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final decoded = json.decode(response.body);
      if (decoded is Map<String, dynamic>) {
        return Task.fromJson(decoded);
      }
      throw Exception('Invalid response when updating checklist item');
    } else {
      throw Exception('Failed to update checklist item');
    }
  }

  Future<void> archiveTask(String taskId) async {
    final response = await http.put(
      Uri.parse('$_baseUrl/$taskId/archive'),
      headers: await _headers(),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to archive task');
    }
  }

  Future<void> restoreTask(String taskId) async {
    final response = await http.put(
      Uri.parse('$_baseUrl/$taskId/restore'),
      headers: await _headers(),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to restore task');
    }
  }

  Future<Task> blockTask(String taskId, String reason) async {
    final response = await http
        .put(
          Uri.parse('$_baseUrl/$taskId/block'),
          headers: await _headers(),
          body: json.encode({'reason': reason}),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final decoded = json.decode(response.body);
      if (decoded is Map<String, dynamic>) {
        return Task.fromJson(decoded);
      }
      throw Exception('Invalid response when blocking task');
    } else {
      throw Exception('Failed to block task');
    }
  }

  Future<Map<String, dynamic>> escalateTask(String taskId) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/$taskId/escalate'),
      headers: await _headers(),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to escalate task');
    }

    if (response.body.isEmpty) {
      return <String, dynamic>{};
    }

    final decoded = json.decode(response.body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }

    return <String, dynamic>{};
  }
}
