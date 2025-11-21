import '../models/task_model.dart';
import '../models/user_task_model.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'user_service.dart';
import '../config/api_config.dart';

class TaskService {
  final String _baseUrl = '${ApiConfig.baseUrl}/api/tasks';

  Future<Map<String, String>> _headers({bool jsonContent = true}) async {
    final headers = <String, String>{};
    if (jsonContent) headers['Content-Type'] = 'application/json';
    final token = await UserService().getToken();
    if (token != null) headers['Authorization'] = 'Bearer $token';
    return headers;
  }

  Future<List<Task>> fetchAllTasks() async {
    final response = await http.get(
      Uri.parse(_baseUrl),
      headers: await _headers(jsonContent: false),
    );

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

  Future<List<Task>> fetchAssignedTasks(String userModelId) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/assigned/$userModelId'),
      headers: await _headers(jsonContent: false),
    );

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
}
