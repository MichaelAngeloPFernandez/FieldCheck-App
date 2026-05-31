import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AttachmentService {
  final String apiBaseUrl;
  late Dio _dio;
  String? _authToken;

  AttachmentService({required this.apiBaseUrl}) {
    _dio = Dio(
      BaseOptions(
        baseUrl: apiBaseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
      ),
    );
  }

  /// Initialize with auth token
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _authToken = prefs.getString('jwt_token');
    _updateAuthHeaders();
  }

  void _updateAuthHeaders() {
    if (_authToken != null) {
      _dio.options.headers['Authorization'] = 'Bearer $_authToken';
    }
  }

  /// Upload a file as an attachment
  /// Accepts file data as `List<int>` (bytes) for web compatibility
  /// or can be extended to accept file path on native platforms
  /// 
  /// Returns: Map with _id, fileName, fileSize, url, uploadedAt
  Future<Map<String, dynamic>> uploadAttachment({
    required List<int> fileBytes,
    required String fileName,
    required String resourceType, // 'report', 'task'
    required String resourceId,
  }) async {
    if (_authToken == null) {
      throw Exception('Not authenticated');
    }

    try {
      final formData = FormData.fromMap({
        'resourceType': resourceType,
        'resourceId': resourceId,
        'file': MultipartFile.fromBytes(
          fileBytes,
          filename: fileName,
        ),
      });

      final response = await _dio.post(
        '/api/attachments/upload',
        data: formData,
        options: Options(
          headers: {'Authorization': 'Bearer $_authToken'},
        ),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        return Map<String, dynamic>.from(response.data);
      } else {
        throw Exception(
          'Upload failed: ${response.statusCode} - ${response.data}',
        );
      }
    } on DioException catch (e) {
      throw Exception('Upload error: ${e.message}');
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
      final response = await _dio.get(
        '/api/attachments/$attachmentId',
        options: Options(
          headers: {'Authorization': 'Bearer $_authToken'},
        ),
      );

      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(response.data);
      } else {
        throw Exception('Failed to get attachment: ${response.statusCode}');
      }
    } on DioException catch (e) {
      throw Exception('Get attachment error: ${e.message}');
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
      final response = await _dio.get(
        '/api/resources/$resourceType/$resourceId/attachments',
        options: Options(
          headers: {'Authorization': 'Bearer $_authToken'},
        ),
      );

      if (response.statusCode == 200) {
        final data = response.data;
        return List<Map<String, dynamic>>.from(data['attachments'] ?? []);
      } else {
        throw Exception(
          'Failed to get attachments: ${response.statusCode}',
        );
      }
    } on DioException catch (e) {
      throw Exception('Get attachments error: ${e.message}');
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
      final response = await _dio.delete(
        '/api/attachments/$attachmentId',
        options: Options(
          headers: {'Authorization': 'Bearer $_authToken'},
        ),
      );

      if (response.statusCode != 200) {
        throw Exception('Delete failed: ${response.statusCode}');
      }
    } on DioException catch (e) {
      throw Exception('Delete attachment error: ${e.message}');
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
