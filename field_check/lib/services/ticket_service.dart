import 'package:http/http.dart' as http;
import 'dart:convert';

class TicketService {
  final String apiBaseUrl;
  String? _authToken;

  TicketService({required this.apiBaseUrl});

  /// Initialize with auth token
  Future<void> init() async {
    // Get token from secure storage or SharedPreferences
    // This is a placeholder - implement per your auth strategy
    _authToken = null;
  }

  /// Update auth token (call after login)
  void updateAuthToken(String token) {
    _authToken = token;
  }

  /// Get all templates
  Future<Map<String, dynamic>> getTemplates({String? serviceType}) async {
    if (_authToken == null) throw Exception('Not authenticated');

    try {
      String url = '$apiBaseUrl/api/templates';
      if (serviceType != null) {
        url += '?serviceType=$serviceType';
      }

      final response = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $_authToken'},
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to get templates: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Get templates error: $e');
    }
  }

  /// Get single template with full schema
  Future<Map<String, dynamic>> getTemplate(String templateId) async {
    if (_authToken == null) throw Exception('Not authenticated');

    try {
      final response = await http.get(
        Uri.parse('$apiBaseUrl/api/templates/$templateId'),
        headers: {'Authorization': 'Bearer $_authToken'},
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else if (response.statusCode == 404) {
        throw Exception('Template not found');
      } else {
        throw Exception('Failed to get template: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Get template error: $e');
    }
  }

  /// Create new ticket
  /// 
  /// Returns: { _id, ticketNumber, status, slaDueAt }
  Future<Map<String, dynamic>> createTicket({
    required String templateId,
    required Map<String, dynamic> data,
    String? requesterName,
    String? requesterEmail,
    String? requesterPhone,
    Map<String, dynamic>? gpsLocation,
    List<String>? attachmentIds,
  }) async {
    if (_authToken == null) throw Exception('Not authenticated');

    try {
      final body = {
        'templateId': templateId,
        'data': data,
        if (requesterName != null) 'requesterName': requesterName,
        if (requesterEmail != null) 'requesterEmail': requesterEmail,
        if (requesterPhone != null) 'requesterPhone': requesterPhone,
        if (gpsLocation != null) 'gpsLocation': gpsLocation,
        if (attachmentIds != null && attachmentIds.isNotEmpty)
          'attachmentIds': attachmentIds,
      };

      final response = await http.post(
        Uri.parse('$apiBaseUrl/api/tickets'),
        headers: {
          'Authorization': 'Bearer $_authToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode == 201) {
        return jsonDecode(response.body);
      } else if (response.statusCode == 400) {
        // Validation error
        final error = jsonDecode(response.body);
        throw ValidationException(
          message: error['error'] ?? 'Validation failed',
          errors: error['details'] ?? [],
        );
      } else {
        throw Exception('Failed to create ticket: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Create ticket error: $e');
    }
  }

  /// Get ticket details
  Future<Map<String, dynamic>> getTicket(String ticketId) async {
    if (_authToken == null) throw Exception('Not authenticated');

    try {
      final response = await http.get(
        Uri.parse('$apiBaseUrl/api/tickets/$ticketId'),
        headers: {'Authorization': 'Bearer $_authToken'},
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to get ticket: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Get ticket error: $e');
    }
  }

  /// List tickets
  Future<Map<String, dynamic>> listTickets({
    String? status,
    String? templateId,
    String? assignedTo,
    int limit = 20,
    int skip = 0,
  }) async {
    if (_authToken == null) throw Exception('Not authenticated');

    try {
      final params = {
        'limit': limit.toString(),
        'skip': skip.toString(),
        if (status != null) 'status': status,
        if (templateId != null) 'templateId': templateId,
        if (assignedTo != null) 'assignedTo': assignedTo,
      };

      final uri = Uri.parse('$apiBaseUrl/api/tickets').replace(
        queryParameters: params,
      );

      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $_authToken'},
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to list tickets: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('List tickets error: $e');
    }
  }

  /// Update ticket status
  Future<Map<String, dynamic>> updateStatus(
    String ticketId,
    String newStatus, {
    String? reason,
  }) async {
    if (_authToken == null) throw Exception('Not authenticated');

    try {
      final response = await http.patch(
        Uri.parse('$apiBaseUrl/api/tickets/$ticketId/status'),
        headers: {
          'Authorization': 'Bearer $_authToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'status': newStatus,
          if (reason != null) 'reason': reason,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to update status: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Update status error: $e');
    }
  }
}

/// Custom exception for validation errors
class ValidationException implements Exception {
  final String message;
  final List<dynamic> errors;

  ValidationException({required this.message, required this.errors});

  @override
  String toString() => message;
}
