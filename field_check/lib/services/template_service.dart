import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:field_check/config/api_config.dart';
import 'package:field_check/services/user_service.dart';
import 'package:field_check/models/ticket_template_model.dart';

class TemplateService {
  static Future<Map<String, String>> _headers() async {
    final token = await UserService().getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Fetch all active templates for the current user's company.
  static Future<List<TicketTemplateModel>> getTemplates() async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/templates');
    final res = await http.get(url, headers: await _headers());
    if (res.statusCode == 200) {
      final List data = jsonDecode(res.body);
      return data
          .map((e) =>
              TicketTemplateModel.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw Exception('Failed to load templates: ${res.statusCode}');
  }

  /// Fetch a single template by ID.
  static Future<TicketTemplateModel> getTemplate(String id) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/templates/$id');
    final res = await http.get(url, headers: await _headers());
    if (res.statusCode == 200) {
      return TicketTemplateModel.fromJson(
          jsonDecode(res.body) as Map<String, dynamic>);
    }
    throw Exception('Failed to load template: ${res.statusCode}');
  }

  /// Create a new template (admin only).
  static Future<TicketTemplateModel> createTemplate({
    required String name,
    required String description,
    required Map<String, dynamic> jsonSchema,
    Map<String, dynamic>? workflow,
    int? slaSeconds,
    String? companyId,
  }) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/templates');
    final body = {
      'name': name,
      'description': description,
      'json_schema': jsonSchema,
      if (workflow != null) 'workflow': workflow,
      if (slaSeconds != null) 'sla_seconds': slaSeconds,
      if (companyId != null) 'company': companyId,
    };
    final res = await http.post(url,
        headers: await _headers(), body: jsonEncode(body));
    if (res.statusCode == 201) {
      return TicketTemplateModel.fromJson(
          jsonDecode(res.body) as Map<String, dynamic>);
    }
    final err = jsonDecode(res.body);
    throw Exception(err['message'] ?? 'Failed to create template');
  }

  /// Update a template (admin only).
  static Future<TicketTemplateModel> updateTemplate(
      String id, Map<String, dynamic> updates) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/templates/$id');
    final res = await http.put(url,
        headers: await _headers(), body: jsonEncode(updates));
    if (res.statusCode == 200) {
      return TicketTemplateModel.fromJson(
          jsonDecode(res.body) as Map<String, dynamic>);
    }
    throw Exception('Failed to update template: ${res.statusCode}');
  }

  /// Delete (deactivate) a template (admin only).
  static Future<void> deleteTemplate(String id) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/templates/$id');
    final res = await http.delete(url, headers: await _headers());
    if (res.statusCode != 200) {
      throw Exception('Failed to delete template: ${res.statusCode}');
    }
  }
}
