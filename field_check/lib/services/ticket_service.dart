import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:field_check/config/api_config.dart';
import 'package:field_check/services/user_service.dart';
import 'package:field_check/models/ticket_model.dart';

class TicketService {
  static Future<Map<String, String>> _headers() async {
    final token = await UserService().getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Fetch all tickets (admin sees all; employee sees only assigned).
  static Future<List<TicketModel>> getTickets({
    String? status,
    String? templateId,
    bool archived = false,
  }) async {
    final params = <String, String>{};
    if (status != null) params['status'] = status;
    if (templateId != null) params['template'] = templateId;
    if (archived) params['archived'] = 'true';

    final url = Uri.parse(
      '${ApiConfig.baseUrl}/api/tickets',
    ).replace(queryParameters: params.isNotEmpty ? params : null);
    final res = await http.get(url, headers: await _headers());
    if (res.statusCode == 200) {
      final List data = jsonDecode(res.body);
      return data
          .map((e) => TicketModel.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw Exception('Failed to load tickets: ${res.statusCode}');
  }

  /// Fetch a single ticket.
  static Future<TicketModel> getTicket(String id) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/tickets/$id');
    final res = await http.get(url, headers: await _headers());
    if (res.statusCode == 200) {
      return TicketModel.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
    }
    throw Exception('Failed to load ticket: ${res.statusCode}');
  }

  /// Create a new ticket from a template.
  static Future<TicketModel> createTicket({
    required String templateId,
    required Map<String, dynamic> data,
    String? assigneeId,
    Map<String, double>? gps,
    String? geofenceId,
    String? notes,
  }) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/tickets');
    final body = {
      'template_id': templateId,
      'data': data,
      if (assigneeId != null) 'assignee_id': assigneeId,
      if (gps != null) 'gps': gps,
      if (geofenceId != null) 'geofence_id': geofenceId,
      if (notes != null) 'notes': notes,
    };
    final res = await http.post(
      url,
      headers: await _headers(),
      body: jsonEncode(body),
    );
    if (res.statusCode == 201) {
      return TicketModel.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
    }
    final err = jsonDecode(res.body);
    throw Exception(err['message'] ?? 'Failed to create ticket');
  }

  /// Update ticket data.
  static Future<TicketModel> updateTicket(
    String id,
    Map<String, dynamic> updates,
  ) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/tickets/$id');
    final res = await http.patch(
      url,
      headers: await _headers(),
      body: jsonEncode(updates),
    );
    if (res.statusCode == 200) {
      return TicketModel.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
    }
    final err = jsonDecode(res.body);
    throw Exception(err['message'] ?? 'Failed to update ticket');
  }

  /// Change ticket status.
  static Future<TicketModel> changeStatus(String id, String status) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/tickets/$id/status');
    final res = await http.patch(
      url,
      headers: await _headers(),
      body: jsonEncode({'status': status}),
    );
    if (res.statusCode == 200) {
      return TicketModel.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
    }
    final err = jsonDecode(res.body);
    throw Exception(err['message'] ?? 'Failed to change status');
  }

  /// Get audit trail for a ticket.
  static Future<List<Map<String, dynamic>>> getAuditTrail(
    String ticketId,
  ) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/audit/ticket/$ticketId');
    final res = await http.get(url, headers: await _headers());
    if (res.statusCode == 200) {
      final List data = jsonDecode(res.body);
      return data.cast<Map<String, dynamic>>();
    }
    return [];
  }
}
