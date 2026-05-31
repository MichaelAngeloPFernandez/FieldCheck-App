import 'package:field_check/utils/http_util.dart';
import 'package:field_check/config/api_config.dart';
import 'package:field_check/services/user_service.dart';
import 'package:field_check/services/realtime_service.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:developer' as developer;

class ClientTicketService {
  static const String _basePath = '/api/client-tickets';
  static const String _contactPath = '/api/contact';
  static const String _debugEndpoint = 'http://127.0.0.1:7594/ingest/1c924b68-154a-46b7-8559-78da3d47b03c';
  static const String _debugSessionId = '1d6461';
  
  final RealtimeService _realtimeService = RealtimeService();

  void _debugLog({
    required String runId,
    required String hypothesisId,
    required String location,
    required String message,
    required Map<String, dynamic> data,
  }) {
    // #region agent log
    final payload = {
      'sessionId': _debugSessionId,
      'runId': runId,
      'hypothesisId': hypothesisId,
      'location': location,
      'message': message,
      'data': data,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    unawaited(
      http
          .post(
            Uri.parse(_debugEndpoint),
            headers: const {
              'Content-Type': 'application/json',
              'X-Debug-Session-Id': _debugSessionId,
            },
            body: jsonEncode(payload),
          )
          .then((_) {}, onError: (_) {}),
    );
    // #endregion
  }

  Future<Map<String, String>> _getHeaders({String? emailToken}) async {
    final token = await UserService().getToken();
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
      if (emailToken != null) 'X-Ticket-Token': emailToken,
    };
    return headers;
  }

  /// Enhanced error response structure with type classification and retry-ability
  Map<String, dynamic> _createErrorResponse({
    required String errorType,
    required String errorCode,
    required String message,
    required bool canRetry,
    String? details,
    int? statusCode,
  }) {
    developer.log(
      'ClientTicketService Error: $errorType - $errorCode - $message',
      name: 'ClientTicketService',
      error: details,
    );
    
    return {
      'success': false,
      'error': message,
      'errorType': errorType,
      'errorCode': errorCode,
      'canRetry': canRetry,
      'statusCode': statusCode,
      'details': details,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  // NOTE: Socket.IO validation removed - HTTP submission proceeds independently
  // Socket.IO is only needed for real-time updates AFTER submission succeeds
  // Keeping method for reference but not used anymore
  /*
  /// Check Socket.IO connection before making requests
  Future<Map<String, dynamic>?> _validateConnection() async {
    try {
      if (!_realtimeService.isConnected) {
        developer.log(
          'Socket.IO connection not available for ticket submission',
          name: 'ClientTicketService',
        );
        
        return _createErrorResponse(
          errorType: 'socket',
          errorCode: 'SOCKET_DISCONNECTED',
          message: 'Real-time connection unavailable. Please check your internet connection.',
          canRetry: true,
          details: 'Socket.IO connection is not established',
        );
      }
      
      developer.log(
        'Socket.IO connection validated successfully',
        name: 'ClientTicketService',
      );
      
      return null; // No error
    } catch (e) {
      developer.log(
        'Error validating Socket.IO connection: $e',
        name: 'ClientTicketService',
        error: e,
      );
      
      return _createErrorResponse(
        errorType: 'socket',
        errorCode: 'SOCKET_VALIDATION_ERROR',
        message: 'Connection validation failed. Please try again.',
        canRetry: true,
        details: e.toString(),
      );
    }
  }
  */

  /// Submit a new client support ticket (public - no auth required)
  /// Returns: success: bool, ticketNumber: string, message: string, trackingLink: string?
  /// Enhanced with detailed error handling
  Future<Map<String, dynamic>> submitClientTicket({
    required String clientName,
    required String clientEmail,
    required String serviceType,
    required String description,
    String? otherServiceDetails,
    List<Map<String, String>>? attachments, // [fileName, fileUrl, fileType]
    bool signupForTracking = false,
  }) async {
    final runId = 'submit-${DateTime.now().millisecondsSinceEpoch}';
    developer.log(
      'Starting client ticket submission for: $clientEmail',
      name: 'ClientTicketService',
    );
    _debugLog(
      runId: runId,
      hypothesisId: 'H1',
      location: 'client_ticket_service.dart:submitClientTicket:start',
      message: 'Submit called',
      data: {
        'baseUrl': ApiConfig.baseUrl,
        'path': _basePath,
        'descriptionLength': description.trim().length,
        'serviceType': serviceType,
      },
    );

    // Optional: Log Socket.IO status for debugging (non-blocking)
    if (!_realtimeService.isConnected) {
      developer.log(
        'Socket.IO disconnected during ticket submission (HTTP will proceed independently)',
        name: 'ClientTicketService',
      );
    }

    // Input validation
    if (clientName.trim().isEmpty || clientName.trim().length < 2) {
      return _createErrorResponse(
        errorType: 'validation',
        errorCode: 'INVALID_CLIENT_NAME',
        message: 'Client name must be at least 2 characters',
        canRetry: false,
        details: 'Client name validation failed',
      );
    }

    final emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    if (!emailRegex.hasMatch(clientEmail)) {
      return _createErrorResponse(
        errorType: 'validation',
        errorCode: 'INVALID_EMAIL',
        message: 'Invalid email address',
        canRetry: false,
        details: 'Email format validation failed',
      );
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
      return _createErrorResponse(
        errorType: 'validation',
        errorCode: 'INVALID_SERVICE_TYPE',
        message: 'Invalid service type',
        canRetry: false,
        details: 'Service type not in allowed list',
      );
    }

    if (description.trim().isEmpty || description.trim().length < 10) {
      return _createErrorResponse(
        errorType: 'validation',
        errorCode: 'INVALID_DESCRIPTION',
        message: 'Description must be at least 10 characters',
        canRetry: false,
        details: 'Description length validation failed',
      );
    }

    if (serviceType == 'other' &&
        (otherServiceDetails == null ||
            otherServiceDetails.trim().isEmpty ||
            otherServiceDetails.trim().length < 5)) {
      return _createErrorResponse(
        errorType: 'validation',
        errorCode: 'MISSING_OTHER_DETAILS',
        message: 'Please provide service details for "Other" service type (min 5 characters)',
        canRetry: false,
        details: 'Other service details validation failed',
      );
    }

    if (attachments != null && attachments.length > 5) {
      return _createErrorResponse(
        errorType: 'validation',
        errorCode: 'TOO_MANY_ATTACHMENTS',
        message: 'Maximum 5 file attachments allowed',
        canRetry: false,
        details: 'Attachment count exceeds limit',
      );
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

    developer.log(
      'Sending HTTP request for ticket submission',
      name: 'ClientTicketService',
    );
    _debugLog(
      runId: runId,
      hypothesisId: 'H2',
      location: 'client_ticket_service.dart:submitClientTicket:beforePost',
      message: 'About to call HttpUtil.post',
      data: {
        'requestUrl': '${ApiConfig.baseUrl}$_basePath',
        'hasOtherServiceDetails': otherServiceDetails != null && otherServiceDetails.trim().isNotEmpty,
        'attachmentCount': attachments?.length ?? 0,
      },
    );

    try {
      final requestStart = DateTime.now();
      http.Response response;
      try {
        response = await HttpUtil()
            .post(
              _basePath,
              body: body,
              headers: await _getHeaders(),
            )
            .timeout(const Duration(seconds: 90), onTimeout: () {
          throw TimeoutException('Request timed out');
        });
      } on TimeoutException {
        _debugLog(
          runId: runId,
          hypothesisId: 'H4',
          location: 'client_ticket_service.dart:submitClientTicket:retry',
          message: 'Initial submit timed out, retrying',
          data: {'requestUrl': '${ApiConfig.baseUrl}$_basePath'},
        );
        response = await HttpUtil()
            .post(
              _basePath,
              body: body,
              headers: await _getHeaders(),
            )
            .timeout(const Duration(seconds: 90), onTimeout: () {
          throw TimeoutException('Request timed out after retry');
        });
      }
      _debugLog(
        runId: runId,
        hypothesisId: 'H3',
        location: 'client_ticket_service.dart:submitClientTicket:afterPost',
        message: 'HttpUtil.post completed',
        data: {
          'elapsedMs': DateTime.now().difference(requestStart).inMilliseconds,
          'statusCode': response.statusCode,
          'bodyLength': response.body.length,
        },
      );

      developer.log(
        'HTTP response received: ${response.statusCode}',
        name: 'ClientTicketService',
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic>) {
            developer.log(
              'Ticket submission successful: ${decoded['ticketNumber'] ?? 'Unknown'}',
              name: 'ClientTicketService',
            );
            return decoded;
          } else {
            return _createErrorResponse(
              errorType: 'server',
              errorCode: 'INVALID_RESPONSE_FORMAT',
              message: 'Server returned invalid response format',
              canRetry: true,
              statusCode: response.statusCode,
            );
          }
        } catch (e) {
          return _createErrorResponse(
            errorType: 'server',
            errorCode: 'RESPONSE_PARSE_ERROR',
            message: 'Failed to parse server response',
            canRetry: true,
            details: e.toString(),
            statusCode: response.statusCode,
          );
        }
      } else {
        // Enhanced error handling for different HTTP status codes
        return _handleHttpError(response);
      }
    } on TimeoutException catch (e) {
      _debugLog(
        runId: runId,
        hypothesisId: 'H4',
        location: 'client_ticket_service.dart:submitClientTicket:timeout',
        message: 'TimeoutException caught in submitClientTicket',
        data: {
          'error': e.toString(),
          'requestUrl': '${ApiConfig.baseUrl}$_basePath',
        },
      );
      return _createErrorResponse(
        errorType: 'timeout',
        errorCode: 'REQUEST_TIMEOUT',
        message: 'Request timeout. Please check your connection and try again.',
        canRetry: true,
        details: e.toString(),
      );
    } on SocketException catch (e) {
      _debugLog(
        runId: runId,
        hypothesisId: 'H5',
        location: 'client_ticket_service.dart:submitClientTicket:socket',
        message: 'SocketException caught in submitClientTicket',
        data: {
          'error': e.toString(),
          'requestUrl': '${ApiConfig.baseUrl}$_basePath',
        },
      );
      return _createErrorResponse(
        errorType: 'network',
        errorCode: 'NETWORK_ERROR',
        message: 'Network connection failed. Please check your internet connection.',
        canRetry: true,
        details: e.toString(),
      );
    } catch (e) {
      _debugLog(
        runId: runId,
        hypothesisId: 'H5',
        location: 'client_ticket_service.dart:submitClientTicket:catch',
        message: 'Unexpected exception caught in submitClientTicket',
        data: {
          'errorType': e.runtimeType.toString(),
          'error': e.toString(),
          'requestUrl': '${ApiConfig.baseUrl}$_basePath',
        },
      );
      return _createErrorResponse(
        errorType: 'unknown',
        errorCode: 'UNEXPECTED_ERROR',
        message: 'An unexpected error occurred. Please try again.',
        canRetry: true,
        details: e.toString(),
      );
    }
  }

  /// Handle HTTP error responses with specific error codes
  Map<String, dynamic> _handleHttpError(dynamic response) {
    final statusCode = response.statusCode;
    
    try {
      final errorBody = jsonDecode(response.body);
      final serverMessage = errorBody['error'] ?? 'Server error occurred';
      
      switch (statusCode) {
        case 400:
          return _createErrorResponse(
            errorType: 'validation',
            errorCode: 'BAD_REQUEST',
            message: serverMessage,
            canRetry: false,
            statusCode: statusCode,
          );
        case 401:
          return _createErrorResponse(
            errorType: 'authentication',
            errorCode: 'UNAUTHORIZED',
            message: 'Authentication required or invalid',
            canRetry: false,
            statusCode: statusCode,
          );
        case 403:
          return _createErrorResponse(
            errorType: 'authorization',
            errorCode: 'FORBIDDEN',
            message: 'Access denied',
            canRetry: false,
            statusCode: statusCode,
          );
        case 404:
          return _createErrorResponse(
            errorType: 'server',
            errorCode: 'NOT_FOUND',
            message: 'Service endpoint not found',
            canRetry: false,
            statusCode: statusCode,
          );
        case 409:
          return _createErrorResponse(
            errorType: 'validation',
            errorCode: 'CONFLICT',
            message: serverMessage,
            canRetry: false,
            statusCode: statusCode,
          );
        case 422:
          return _createErrorResponse(
            errorType: 'validation',
            errorCode: 'UNPROCESSABLE_ENTITY',
            message: serverMessage,
            canRetry: false,
            statusCode: statusCode,
          );
        case 429:
          return _createErrorResponse(
            errorType: 'rate_limit',
            errorCode: 'TOO_MANY_REQUESTS',
            message: 'Too many requests. Please wait and try again.',
            canRetry: true,
            statusCode: statusCode,
          );
        case 500:
          return _createErrorResponse(
            errorType: 'server',
            errorCode: 'INTERNAL_SERVER_ERROR',
            message: 'Server error occurred. Please try again later.',
            canRetry: true,
            statusCode: statusCode,
          );
        case 502:
          return _createErrorResponse(
            errorType: 'server',
            errorCode: 'BAD_GATEWAY',
            message: 'Service temporarily unavailable. Please try again.',
            canRetry: true,
            statusCode: statusCode,
          );
        case 503:
          return _createErrorResponse(
            errorType: 'server',
            errorCode: 'SERVICE_UNAVAILABLE',
            message: 'Service temporarily unavailable. Please try again later.',
            canRetry: true,
            statusCode: statusCode,
          );
        case 504:
          return _createErrorResponse(
            errorType: 'timeout',
            errorCode: 'GATEWAY_TIMEOUT',
            message: 'Server timeout. Please try again.',
            canRetry: true,
            statusCode: statusCode,
          );
        default:
          return _createErrorResponse(
            errorType: 'server',
            errorCode: 'HTTP_ERROR',
            message: serverMessage,
            canRetry: statusCode >= 500,
            statusCode: statusCode,
          );
      }
    } catch (_) {
      return _createErrorResponse(
        errorType: 'server',
        errorCode: 'HTTP_ERROR',
        message: 'Server error occurred (Status: $statusCode)',
        canRetry: statusCode >= 500,
        statusCode: statusCode,
      );
    }
  }

  /// Get ticket details by ticket number (public tracking)
  /// Returns: ticket data or error
  /// Fetch a client ticket by ticket number (public - optional email token)
  /// emailToken: Token provided via email link for authentication
  /// Returns: data: ticket details or throws Exception
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
  /// Returns: success: bool, message: string
  /// Submit rating for completed ticket (client only, requires email token)
  /// emailToken: Token provided via email link for authentication
  /// Returns: success: bool, message: string or throws Exception
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
  /// Returns: success: bool, message: string or throws Exception
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
  /// Returns: success: bool, message: string
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

  /// Fetch pending client tickets (admin only)
  /// Returns: success: bool, data: List of Map with String dynamic, pagination: Map
  Future<Map<String, dynamic>> fetchPendingTickets({
    int page = 1,
    int limit = 50,
  }) async {
    try {
      final response = await HttpUtil()
          .get(
            '$_basePath?status=open&page=$page&limit=$limit',
            headers: await _getHeaders(),
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
        throw Exception('Unauthorized. Admin access required.');
      } else {
        try {
          final error = jsonDecode(response.body);
          throw Exception(error['error'] ?? 'Failed to fetch pending tickets');
        } catch (_) {
          throw Exception('Failed to fetch pending tickets (Status: ${response.statusCode})');
        }
      }
    } on TimeoutException {
      throw Exception('Request timeout. Please check your connection and try again.');
    } catch (e) {
      rethrow;
    }
  }

  /// Organize client tickets (admin only)
  /// Allows admins to organize tickets by priority, category, or assignment
  /// Returns: success: bool, message: string
  Future<Map<String, dynamic>> organizeClientTickets({
    required List<String> ticketIds,
    String? organizationType, // 'priority', 'category', 'assignment'
    String? organizationValue,
    Map<String, dynamic>? organizationData,
  }) async {
    if (ticketIds.isEmpty) {
      throw Exception('At least one ticket ID is required');
    }

    final validOrganizationTypes = ['priority', 'category', 'assignment', 'status'];
    if (organizationType != null && !validOrganizationTypes.contains(organizationType)) {
      throw Exception('Invalid organization type. Must be one of: ${validOrganizationTypes.join(', ')}');
    }

    final body = {
      'ticketIds': ticketIds,
      if (organizationType != null) 'organizationType': organizationType,
      if (organizationValue != null) 'organizationValue': organizationValue,
      if (organizationData != null) 'organizationData': organizationData,
    };

    try {
      final response = await HttpUtil()
          .post(
            '$_basePath/organize',
            body: body,
            headers: await _getHeaders(),
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
        throw Exception('Unauthorized. Admin access required.');
      } else if (response.statusCode == 404) {
        throw Exception('One or more tickets not found');
      } else {
        try {
          final error = jsonDecode(response.body);
          throw Exception(error['error'] ?? 'Failed to organize tickets');
        } catch (_) {
          throw Exception('Failed to organize tickets (Status: ${response.statusCode})');
        }
      }
    } on TimeoutException {
      throw Exception('Request timeout. Please check your connection and try again.');
    } catch (e) {
      rethrow;
    }
  }

  /// Delete a client ticket (admin only)
  /// Permanently removes a ticket from the system
  /// Returns: success: bool, message: string
  Future<Map<String, dynamic>> deleteClientTicket(String ticketNumber) async {
    if (!RegExp(r'^RNG-\d{8}-[A-Z0-9]{4}$').hasMatch(ticketNumber)) {
      throw Exception('Invalid ticket number format');
    }

    try {
      final response = await HttpUtil()
          .delete(
            '$_basePath/$ticketNumber',
            headers: await _getHeaders(),
          )
          .timeout(const Duration(seconds: 30), onTimeout: () {
        throw TimeoutException('Request timed out');
      });

      if (response.statusCode == 200) {
        try {
          final decoded = jsonDecode(response.body);
          return decoded is Map<String, dynamic>
              ? decoded
              : {'success': true, 'message': 'Ticket deleted successfully'};
        } catch (_) {
          return {'success': true, 'message': 'Ticket deleted successfully'};
        }
      } else if (response.statusCode == 401) {
        throw Exception('Unauthorized. Admin access required.');
      } else if (response.statusCode == 404) {
        throw Exception('Ticket not found');
      } else if (response.statusCode == 403) {
        throw Exception('Cannot delete ticket. Ticket may be in progress or completed.');
      } else {
        try {
          final error = jsonDecode(response.body);
          throw Exception(error['error'] ?? 'Failed to delete ticket');
        } catch (_) {
          throw Exception('Failed to delete ticket (Status: ${response.statusCode})');
        }
      }
    } on TimeoutException {
      throw Exception('Request timeout. Please check your connection and try again.');
    } catch (e) {
      rethrow;
    }
  }

  /// Archive a client ticket (admin only)
  /// Moves a ticket to archived status without deleting it
  /// Returns: success: bool, message: string
  Future<Map<String, dynamic>> archiveClientTicket(String ticketNumber, {
    String? archiveReason,
  }) async {
    if (!RegExp(r'^RNG-\d{8}-[A-Z0-9]{4}$').hasMatch(ticketNumber)) {
      throw Exception('Invalid ticket number format');
    }

    final body = {
      'action': 'archive',
      if (archiveReason != null && archiveReason.trim().isNotEmpty)
        'archiveReason': archiveReason.trim(),
    };

    try {
      final response = await HttpUtil()
          .patch(
            '$_basePath/$ticketNumber/status',
            body: body,
            headers: await _getHeaders(),
          )
          .timeout(const Duration(seconds: 30), onTimeout: () {
        throw TimeoutException('Request timed out');
      });

      if (response.statusCode == 200) {
        try {
          final decoded = jsonDecode(response.body);
          return decoded is Map<String, dynamic>
              ? decoded
              : {'success': true, 'message': 'Ticket archived successfully'};
        } catch (_) {
          return {'success': true, 'message': 'Ticket archived successfully'};
        }
      } else if (response.statusCode == 401) {
        throw Exception('Unauthorized. Admin access required.');
      } else if (response.statusCode == 404) {
        throw Exception('Ticket not found');
      } else if (response.statusCode == 409) {
        throw Exception('Cannot archive ticket. Ticket may already be archived or in an invalid state.');
      } else {
        try {
          final error = jsonDecode(response.body);
          throw Exception(error['error'] ?? 'Failed to archive ticket');
        } catch (_) {
          throw Exception('Failed to archive ticket (Status: ${response.statusCode})');
        }
      }
    } on TimeoutException {
      throw Exception('Request timeout. Please check your connection and try again.');
    } catch (e) {
      rethrow;
    }
  }
  /// Get all ticket ratings for a client (public - email-based auth)
  /// Returns: success: bool, ratings: List, total: int, pages: int, averageRating: double
  Future<Map<String, dynamic>> getClientRatings({
    required String clientEmail,
    int page = 1,
    int limit = 10,
    int? stars,
    String sortBy = 'recent',
  }) async {
    try {
      final query = <String, String>{
        'clientEmail': clientEmail,
        'page': page.toString(),
        'limit': limit.toString(),
        'sort': sortBy,
        if (stars != null) 'stars': stars.toString(),
      };

      final response = await HttpUtil()
          .get(
            '/api/ticket-ratings',
            queryParams: query,
          )
          .timeout(const Duration(seconds: 30), onTimeout: () {
        throw TimeoutException('Request timed out');
      });

      if (response.statusCode == 200) {
        try {
          final decoded = jsonDecode(response.body);
          return decoded is Map<String, dynamic>
              ? {
                  'success': true,
                  'ratings': decoded['ratings'] ?? [],
                  'total': decoded['total'] ?? 0,
                  'pages': decoded['pages'] ?? 1,
                  'averageRating': decoded['averageRating'] ?? 0.0,
                  'fiveStarCount': decoded['fiveStarCount'] ?? 0,
                  'fourStarCount': decoded['fourStarCount'] ?? 0,
                  'threeStarCount': decoded['threeStarCount'] ?? 0,
                  'twoStarCount': decoded['twoStarCount'] ?? 0,
                  'oneStarCount': decoded['oneStarCount'] ?? 0,
                }
              : {
                  'success': true,
                  'ratings': [],
                  'total': 0,
                  'pages': 1,
                  'averageRating': 0.0,
                };
        } catch (_) {
          return {
            'success': true,
            'ratings': [],
            'total': 0,
            'pages': 1,
            'averageRating': 0.0,
          };
        }
      } else if (response.statusCode == 404) {
        return {
          'success': true,
          'ratings': [],
          'total': 0,
          'pages': 1,
          'averageRating': 0.0,
          'message': 'No ratings found for this email',
        };
      } else {
        try {
          final error = jsonDecode(response.body);
          throw Exception(error['error'] ?? 'Failed to load ratings');
        } catch (_) {
          throw Exception('Failed to load ratings (Status: ${response.statusCode})');
        }
      }
    } on TimeoutException {
      throw Exception('Request timeout. Please check your connection and try again.');
    } catch (e) {
      rethrow;
    }
  }}
