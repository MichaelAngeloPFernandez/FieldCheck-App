import 'package:field_check/config/api_config.dart';
import 'package:field_check/models/task_model.dart';
import 'package:field_check/models/task_template_model.dart';
import 'package:field_check/services/user_service.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class TaskTemplateService {
  final UserService _userService = UserService();

  Future<String?> _getToken() async {
    return await _userService.getToken();
  }

  Future<Map<String, String>> _getHeaders() async {
    final token = await _getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Create a new task template for a service
  Future<TaskTemplate> createTemplate({
    required String serviceId,
    required String title,
    String? description,
    String type = 'general',
    String difficulty = 'medium',
    List<TaskChecklistItem> checklist = const [],
  }) async {
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/services/$serviceId/templates'),
        headers: headers,
        body: jsonEncode({
          'title': title,
          'description': description,
          'type': type,
          'difficulty': difficulty,
          'checklist': checklist.map((c) => c.toJson()).toList(),
        }),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return TaskTemplate.fromJson(data['data'] ?? data);
      } else {
        throw Exception('Failed to create template: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error creating template: $e');
    }
  }

  /// Get all templates for a service
  Future<List<TaskTemplate>> getTemplatesForService(String serviceId) async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/services/$serviceId/templates'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> templates = data['data'] ?? data;
        return templates
            .map((t) => TaskTemplate.fromJson(t as Map<String, dynamic>))
            .toList();
      } else {
        throw Exception('Failed to fetch templates: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error fetching templates: $e');
    }
  }

  /// Get a specific template by ID
  Future<TaskTemplate> getTemplateById(String templateId) async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/templates/$templateId'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return TaskTemplate.fromJson(data['data'] ?? data);
      } else {
        throw Exception('Failed to fetch template: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error fetching template: $e');
    }
  }

  /// Update a template
  Future<TaskTemplate> updateTemplate({
    required String templateId,
    required String title,
    String? description,
    String? type,
    String? difficulty,
    List<TaskChecklistItem>? checklist,
    bool? isActive,
  }) async {
    try {
      final headers = await _getHeaders();
      final response = await http.put(
        Uri.parse('${ApiConfig.baseUrl}/api/templates/$templateId'),
        headers: headers,
        body: jsonEncode({
          'title': title,
          'description': description,
          'type': type,
          'difficulty': difficulty,
          'checklist': checklist?.map((c) => c.toJson()).toList(),
          'isActive': isActive,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return TaskTemplate.fromJson(data['data'] ?? data);
      } else {
        throw Exception('Failed to update template: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error updating template: $e');
    }
  }

  /// Delete a template
  Future<void> deleteTemplate(String templateId) async {
    try {
      final headers = await _getHeaders();
      final response = await http.delete(
        Uri.parse('${ApiConfig.baseUrl}/api/templates/$templateId'),
        headers: headers,
      );

      if (response.statusCode != 200 && response.statusCode != 204) {
        throw Exception('Failed to delete template: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error deleting template: $e');
    }
  }
}
