import 'package:field_check/utils/http_util.dart';
import 'package:field_check/services/user_service.dart';
import 'dart:convert';

class NotificationService {
  static const String _basePath = '/api/notifications';

  Future<Map<String, String>> _headers() async {
    final token = await UserService().getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<Map<String, dynamic>> sendUrgentInAppOnly({
    required String message,
    required String recipientMode,
    String? employeeId,
  }) async {
    final body = <String, dynamic>{
      'message': message,
      'sendEmail': false,
      'sendInApp': true,
      'recipientMode': recipientMode,
    };
    if (employeeId != null && employeeId.trim().isNotEmpty) {
      body['employeeId'] = employeeId.trim();
    }

    final response = await HttpUtil()
        .post(
          '$_basePath/urgent-multichannel',
          body: body,
          headers: await _headers(),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception('Failed to send urgent notification: ${response.body}');
    }

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } catch (_) {}
    return <String, dynamic>{};
  }

  Future<Map<String, dynamic>> sendUrgentMultichannel({
    required String message,
    required bool sendEmail,
    required bool sendInApp,
    required String recipientMode,
  }) async {
    final response = await HttpUtil()
        .post(
          '$_basePath/urgent-multichannel',
          body: <String, dynamic>{
            'message': message,
            'sendEmail': sendEmail,
            'sendInApp': sendInApp,
            'recipientMode': recipientMode,
          },
          headers: await _headers(),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception('Failed to send urgent notification: ${response.body}');
    }

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } catch (_) {}
    return <String, dynamic>{};
  }
}
