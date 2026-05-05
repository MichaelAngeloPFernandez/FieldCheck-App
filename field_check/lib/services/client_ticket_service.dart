import 'package:field_check/utils/http_util.dart';
import 'package:field_check/services/user_service.dart';
import 'dart:convert';
import 'dart:async';

class ClientTicketService {
  static const String _basePath = '/api/client-tickets';
  static const String _contactPath = '/api/contact';

  Future<Map<String, String>> _getHeaders({String? emailToken}) async {
    final token = await UserService().getToken();
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
      if (emailToken != null) 'X-Ticket-Token': emailToken,
    };
    return headers;
  }

  /// Submit a new client support ticket (public - no auth required)
  /// Returns: { success: bool, ticketNumber: string, message: string, trackingLink: string? }
  Future<Map<String, dynamic>> submitClientTicket({
    required String clientName,
    required String clientEmail,
    required String serviceType,
    required String description,
    String? otherServiceDetails,
    List<Map<String, String>>? attachments, // [{ fileName, fileUrl, fileType }]
    bool signupForTracking = false,
  }) async {
    // Input validation
    if (clientName.trim().isEmpty || clientName.trim().length < 2) {
      throw Exception('Client name must be at least 2 characters');
    }

    final emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    if (!emailRegex.hasMatch(clientEmail)) {
      throw Exception('Invalid email address');
    }

    final validServiceTypes = [
      'facility_inspection',
      'maintenance',
      'equipment_check',
      'cleaning',
      'security_audit',
      'aircon_cleaning',
      'other'
    ];
    if (!validServiceTypes.contains(serviceType)) {
      throw Exception('Invalid service type');
    }

    if (description.trim().isEmpty || description.trim().length < 10) {
      throw Exception('Description must be at least 10 characters');
    }

    if (serviceType == 'other' &&
        (otherServiceDetails == null ||
            otherServiceDetails.trim().isEmpty ||
            otherServiceDetails.trim().length < 5)) {
      throw Exception(
          'Please provide service details for "Other" service type (min 5 characters)');
    }

    if (attachments != null && attachments.length > 5) {
      throw Exception('Maximum 5 file attachments allowed');
    }

    final body = {
      'clientName': clientName.trim(),
      'clientEmail': clientEmail.trim(),
      'serviceType': serviceType,
      'description': description.trim(),
      if (otherServiceDetails != null && otherServiceDetails.trim().isNotEmpty)
        'otherServiceDetails': otherServiceDetails.trim(),
      if (attachments != null) 'attachments': attachments,
      'signupForTracking': signupForTracking,
    };

    try {
      final response = await HttpUtil()
          .post(
            _basePath,
            body: body,
            headers: await _getHeaders(),
          )
          .timeout(const Duration(seconds: 30), onTimeout: () {
        throw TimeoutException('Request timed out');
      });

      if (response.statusCode == 201 || response.statusCode == 200) {
        try {
          final decoded = jsonDecode(response.body);
          return decoded is Map<String, dynamic>
              ? decoded
              : {'success': false, 'error': 'Invalid response format'};
        } catch (_) {
          return {'success': false, 'error': 'Failed to parse response'};
        }
      } else {
        try {
          final error = jsonDecode(response.body);
          throw Exception(error['error'] ?? 'Failed to submit ticket');
        } catch (_) {
          throw Exception('Failed to submit ticket (Status: ${response.statusCode})');
        }
      }
    } on TimeoutException {
      throw Exception('Request timeout. Please check your connection and try again.');
    } catch (e) {
      rethrow;
    }
  }

  /// Get ticket details by ticket number (public tracking)
  /// Returns: ticket data or error
  /// Fetch a client ticket by ticket number (public - optional email token)
  /// emailToken: Token provided via email link for authentication
  /// Returns: { data: {...ticket details...}, ... } or throws Exception
  Future<Map<String, dynamic>> getClientTicket(String ticketNumber,
      {String? emailToken}) async {
    if (!RegExp(r'^RNG-\d{8}-[A-Z0-9]{4}$').hasMatch(ticketNumber)) {
      throw Exception('Invalid ticket number format');
    }

    try {
      final response = await HttpUtil()
          .get(
            '$_basePath/$ticketNumber',
            headers: await _getHeaders(emailToken: emailToken),
          )
          .timeout(const Duration(seconds: 30), onTimeout: () {
        throw TimeoutException('Request timed out');
      });

      if (response.statusCode == 200) {
        try {
          final decoded = jsonDecode(response.body);
          return decoded is Map<String, dynamic>
              ? decoded
              : {'error': 'Invalid response format'};
        } catch (_) {
          return {'error': 'Failed to parse response'};
        }
      } else if (response.statusCode == 404) {
        throw Exception('Ticket not found');
      } else if (response.statusCode == 401) {
        throw Exception('Invalid or expired ticket link');
      } else {
        throw Exception('Failed to fetch ticket (Status: ${response.statusCode})');
      }
    } on TimeoutException {
      throw Exception('Request timeout. Please check your connection and try again.');
    } catch (e) {
      rethrow;
    }
  }

  /// Submit rating for completed ticket (client only)
  /// Returns: { success: bool, message: string }
  /// Submit rating for completed ticket (client only, requires email token)
  /// emailToken: Token provided via email link for authentication
  /// Returns: { success: bool, message: string } or throws Exception
  Future<Map<String, dynamic>> submitTicketRating({
    required String ticketNumber,
    required int stars,
    String? comment,
    required String clientEmail,
    String? emailToken,
  }) async {
    if (!RegExp(r'^RNG-\d{8}-[A-Z0-9]{4}$').hasMatch(ticketNumber)) {
      throw Exception('Invalid ticket number format');
    }

    if (stars < 1 || stars > 5) {
      throw Exception('Rating must be between 1 and 5 stars');
    }

    if (stars < 3 &&
        (comment == null || comment.trim().isEmpty || comment.trim().length < 5)) {
      throw Exception(
          'Comment is required for ratings below 3 stars (minimum 5 characters)');
    }

    final body = {
      'stars': stars,
      'comment': comment?.trim(),
      'clientEmail': clientEmail.trim(),
    };

    try {
      final response = await HttpUtil()
          .post(
            '$_basePath/$ticketNumber/rating',
            body: body,
            headers: await _getHeaders(emailToken: emailToken),
          )
          .timeout(const Duration(seconds: 30), onTimeout: () {
        throw TimeoutException('Request timed out');
      });

      if (response.statusCode == 200) {
        try {
          final decoded = jsonDecode(response.body);
          return decoded is Map<String, dynamic>
              ? decoded
              : {'success': false, 'error': 'Invalid response format'};
        } catch (_) {
          return {'success': false, 'error': 'Failed to parse response'};
        }
      } else if (response.statusCode == 401) {
        throw Exception('Invalid or expired ticket link');
      } else {
        try {
          final error = jsonDecode(response.body);
          throw Exception(error['error'] ?? 'Failed to submit rating');
        } catch (_) {
          throw Exception('Failed to submit rating (Status: ${response.statusCode})');
        }
      }
    } on TimeoutException {
      throw Exception('Request timeout. Please check your connection and try again.');
    } catch (e) {
      rethrow;
    }
  }

  /// Submit a comment on a ticket (client, admin, or employee)
  /// authorType: 'client', 'admin', or 'employee'
  /// emailToken: Required for client comments
  /// Returns: { success: bool, message: string } or throws Exception
  Future<Map<String, dynamic>> submitTicketComment({
    required String ticketNumber,
    required String text,
    required String authorType,
    String? authorEmail,
    String? emailToken,
  }) async {
    if (!RegExp(r'^RNG-\d{8}-[A-Z0-9]{4}$').hasMatch(ticketNumber)) {
      throw Exception('Invalid ticket number format');
    }

    if (text.trim().isEmpty) {
      throw Exception('Comment text is required');
    }

    if (!['admin', 'employee', 'client'].contains(authorType)) {
      throw Exception('Invalid author type');
    }

    if (authorType == 'client' && authorEmail == null) {
      throw Exception('Author email is required for client comments');
    }

    final body = {
      'text': text.trim(),
      'authorType': authorType,
      if (authorEmail != null) 'authorEmail': authorEmail.toLowerCase(),
    };

    try {
      final response = await HttpUtil()
          .post(
            '$_basePath/$ticketNumber/comment',
            body: body,
            headers: await _getHeaders(emailToken: emailToken),
          )
          .timeout(const Duration(seconds: 30), onTimeout: () {
        throw TimeoutException('Request timed out');
      });

      if (response.statusCode == 200) {
        try {
          final decoded = jsonDecode(response.body);
          return decoded is Map<String, dynamic>
              ? decoded
              : {'success': false, 'error': 'Invalid response format'};
        } catch (_) {
          return {'success': false, 'error': 'Failed to parse response'};
        }
      } else if (response.statusCode == 401) {
        throw Exception('Invalid or expired ticket link');
      } else {
        try {
          final error = jsonDecode(response.body);
          throw Exception(error['error'] ?? 'Failed to submit comment');
        } catch (_) {
          throw Exception('Failed to submit comment (Status: ${response.statusCode})');
        }
      }
    } on TimeoutException {
      throw Exception('Request timeout. Please check your connection and try again.');
    } catch (e) {
      rethrow;
    }
  }

  /// Submit a contact inquiry (redesigned Contact tab)
  /// Returns: { success: bool, message: string }
  Future<Map<String, dynamic>> submitContactInquiry({
    required String name,
    required String email,
    required String subject,
    required String message,
    required String serviceCategory,
  }) async {
    // Input validation
    if (name.trim().isEmpty || name.trim().length < 2) {
      throw Exception('Name must be at least 2 characters');
    }

    final emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    if (!emailRegex.hasMatch(email)) {
      throw Exception('Invalid email address');
    }

    if (subject.trim().isEmpty || subject.trim().length < 5) {
      throw Exception('Subject must be at least 5 characters');
    }

    if (message.trim().isEmpty || message.trim().length < 10) {
      throw Exception('Message must be at least 10 characters');
    }

    final validCategories = ['billing', 'technical', 'account', 'service', 'other'];
    if (!validCategories.contains(serviceCategory)) {
      throw Exception('Invalid service category');
    }

    final body = {
      'name': name.trim(),
      'email': email.trim(),
      'subject': subject.trim(),
      'message': message.trim(),
      'serviceCategory': serviceCategory,
    };

    try {
      final response = await HttpUtil()
          .post(
            _contactPath,
            body: body,
            headers: await _getHeaders(),
          )
          .timeout(const Duration(seconds: 30), onTimeout: () {
        throw TimeoutException('Request timed out');
      });

      if (response.statusCode == 201 || response.statusCode == 200) {
        try {
          final decoded = jsonDecode(response.body);
          return decoded is Map<String, dynamic>
              ? decoded
              : {'success': false, 'error': 'Invalid response format'};
        } catch (_) {
          return {'success': false, 'error': 'Failed to parse response'};
        }
      } else {
        try {
          final error = jsonDecode(response.body);
          throw Exception(error['error'] ?? 'Failed to submit inquiry');
        } catch (_) {
          throw Exception(
              'Failed to submit inquiry (Status: ${response.statusCode})');
        }
      }
    } on TimeoutException {
      throw Exception('Request timeout. Please check your connection and try again.');
    } catch (e) {
      rethrow;
    }
  }
}
