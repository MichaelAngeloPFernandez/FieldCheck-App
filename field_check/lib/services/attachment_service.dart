import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';

class AttachmentService {
  final String apiBaseUrl;
  String? _authToken;

  AttachmentService({required this.apiBaseUrl});

  /// Initialize with auth token
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _authToken = prefs.getString('jwt_token');
  }

  /// Upload a file as an attachment
  /// 
  /// Returns: Map with _id, fileName, fileSize, url, uploadedAt
  Future<Map<String, dynamic>> uploadAttachment({
    required File file,
    required String resourceType, // 'report', 'task', 'ticket'
    required String resourceId,
  }) async {
    if (_authToken == null) {
      throw Exception('Not authenticated');
    }

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$apiBaseUrl/api/attachments/upload'),
      );

      request.headers['Authorization'] = 'Bearer $_authToken';
      request.fields['resourceType'] = resourceType;
      request.fields['resourceId'] = resourceId;
      request.files.add(
        await http.MultipartFile.fromPath('file', file.path),
      );

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      if (response.statusCode == 201) {
        return jsonDecode(responseBody);
      } else {
        throw Exception(
          'Upload failed: ${response.statusCode} - $responseBody',
        );
      }
    } catch (e) {
      throw Exception('Upload error: ${e.toString()}');
    }
  }

  /// Get attachment metadata
  Future<Map<String, dynamic>> getAttachment(String attachmentId) async {
    if (_authToken == null) {
      throw Exception('Not authenticated');
    }

    try {
      final response = await http.get(
        Uri.parse('$apiBaseUrl/api/attachments/$attachmentId'),
        headers: {'Authorization': 'Bearer $_authToken'},
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to get attachment: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Get attachment error: ${e.toString()}');
    }
  }

  /// Get all attachments for a resource
  Future<List<Map<String, dynamic>>> getAttachmentsForResource({
    required String resourceType,
    required String resourceId,
  }) async {
    if (_authToken == null) {
      throw Exception('Not authenticated');
    }

    try {
      final response = await http.get(
        Uri.parse(
          '$apiBaseUrl/api/resources/$resourceType/$resourceId/attachments',
        ),
        headers: {'Authorization': 'Bearer $_authToken'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['attachments'] ?? []);
      } else {
        throw Exception(
          'Failed to get attachments: ${response.statusCode}',
        );
      }
    } catch (e) {
      throw Exception('Get attachments error: ${e.toString()}');
    }
  }

  /// Delete an attachment
  Future<void> deleteAttachment(String attachmentId) async {
    if (_authToken == null) {
      throw Exception('Not authenticated');
    }

    try {
      final response = await http.delete(
        Uri.parse('$apiBaseUrl/api/attachments/$attachmentId'),
        headers: {'Authorization': 'Bearer $_authToken'},
      );

      if (response.statusCode != 200) {
        throw Exception('Delete failed: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Delete attachment error: ${e.toString()}');
    }
  }

  /// Get full file URL (for downloading/displaying)
  String getFileUrl(String storageName) {
    return '$apiBaseUrl/api/attachments/$storageName/file';
  }

  /// Update auth token (call after login)
  void updateAuthToken(String token) {
    _authToken = token;
  }
}
