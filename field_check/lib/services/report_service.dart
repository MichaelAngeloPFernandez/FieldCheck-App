import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/report_model.dart';
import 'package:field_check/utils/http_util.dart';
import 'user_service.dart';

class ReportService {
  final String _basePath = '/api/reports';

  static const int maxUploadBytes = 10 * 1024 * 1024;

  String _extractErrorMessage(http.Response response) {
    try {
      final decoded = json.decode(response.body);
      if (decoded is Map<String, dynamic> && decoded['message'] != null) {
        return decoded['message'].toString();
      }
      return decoded.toString();
    } catch (_) {
      return response.body;
    }
  }

  Future<http.Response> _sendMultipartWithAuthRetry(
    http.MultipartRequest request,
  ) async {
    var streamed = await request.send();
    var response = await http.Response.fromStream(streamed);

    if (response.statusCode != 401) {
      return response;
    }

    final refreshed = await UserService().refreshAccessToken();
    if (!refreshed) {
      return response;
    }

    final token = await UserService().getToken();
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    } else {
      request.headers.remove('Authorization');
    }

    streamed = await request.send();
    response = await http.Response.fromStream(streamed);
    return response;
  }

  Future<Map<String, String>> _headers({bool jsonContent = true}) async {
    final headers = <String, String>{};
    if (jsonContent) headers['Content-Type'] = 'application/json';
    final token = await UserService().getToken();
    if (token != null) headers['Authorization'] = 'Bearer $token';
    return headers;
  }

  Future<List<ReportModel>> fetchReports({String? type}) async {
    final queryParams = type != null ? {'type': type} : null;
    final response = await HttpUtil().get(
      _basePath,
      queryParams: queryParams,
      headers: await _headers(jsonContent: false),
    );
    if (response.statusCode == 200) {
      final list = json.decode(response.body) as List<dynamic>;
      return list.map((e) => ReportModel.fromJson(e)).toList();
    } else {
      throw Exception('Failed to fetch reports');
    }
  }

  Future<List<ReportModel>> getCurrentReports({String? type}) async {
    final queryParams = <String, String>{'archived': 'false'};
    if (type != null) queryParams['type'] = type;
    final response = await HttpUtil().get(
      _basePath,
      queryParams: queryParams,
      headers: await _headers(jsonContent: false),
    );
    if (response.statusCode == 200) {
      final list = json.decode(response.body) as List<dynamic>;
      return list.map((e) => ReportModel.fromJson(e)).toList();
    } else {
      throw Exception('Failed to fetch current reports');
    }
  }

  Future<List<ReportModel>> getArchivedReports({String? type}) async {
    final queryParams = <String, String>{'archived': 'true'};
    if (type != null) queryParams['type'] = type;
    final response = await HttpUtil().get(
      _basePath,
      queryParams: queryParams,
      headers: await _headers(jsonContent: false),
    );
    if (response.statusCode == 200) {
      final list = json.decode(response.body) as List<dynamic>;
      return list.map((e) => ReportModel.fromJson(e)).toList();
    } else {
      throw Exception('Failed to fetch archived reports');
    }
  }

  Future<void> archiveReport(String id) async {
    final response = await HttpUtil().put(
      '$_basePath/$id/archive',
      headers: await _headers(),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to archive report');
    }
  }

  Future<void> restoreReport(String id) async {
    final response = await HttpUtil().put(
      '$_basePath/$id/restore',
      headers: await _headers(),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to restore report');
    }
  }

  Future<ReportModel> updateReportStatus(String id, String status) async {
    final response = await HttpUtil().patch(
      '$_basePath/$id/status',
      headers: await _headers(),
      body: {'status': status},
    );
    if (response.statusCode == 200) {
      return ReportModel.fromJson(json.decode(response.body));
    } else {
      throw Exception('Failed to update report status');
    }
  }

  Future<void> deleteReport(String id) async {
    final response = await HttpUtil().delete(
      '$_basePath/$id',
      headers: await _headers(jsonContent: false),
    );
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception('Failed to delete report');
    }
  }

  Future<ReportModel> createTaskReport({
    required String taskId,
    required String employeeId,
    required String content,
    List<String>? attachments,
  }) async {
    final response = await HttpUtil().post(
      _basePath,
      headers: await _headers(),
      body: {
        'type': 'task',
        'taskId': taskId,
        'employeeId': employeeId,
        'content': content,
        if (attachments != null && attachments.isNotEmpty)
          'attachments': attachments,
      },
    );
    if (response.statusCode == 201 || response.statusCode == 200) {
      return ReportModel.fromJson(json.decode(response.body));
    } else {
      throw Exception('Failed to create task report');
    }
  }

  Future<String> uploadAttachment({
    required String filePath,
    required String fileName,
    required String taskId,
    required String employeeId,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}$_basePath/upload');

    final headers = await _headers(jsonContent: false);
    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(headers);

    request.fields['taskId'] = taskId;
    request.fields['employeeId'] = employeeId;

    request.files.add(
      await http.MultipartFile.fromPath('file', filePath, filename: fileName),
    );

    final response = await _sendMultipartWithAuthRetry(request);

    if (response.statusCode == 200 || response.statusCode == 201) {
      final decoded = json.decode(response.body);
      if (decoded is Map<String, dynamic> && decoded['path'] is String) {
        return decoded['path'] as String;
      }
      throw Exception('Upload succeeded but response invalid');
    } else {
      final msg = _extractErrorMessage(response);
      throw Exception('Failed to upload attachment (${response.statusCode}): $msg');
    }
  }

  Future<String> uploadAttachmentBytes({
    required Uint8List bytes,
    required String fileName,
    required String taskId,
    required String employeeId,
  }) async {
    if (bytes.lengthInBytes > maxUploadBytes) {
      throw Exception('File too large (max 10MB)');
    }

    final uri = Uri.parse('${ApiConfig.baseUrl}$_basePath/upload');

    final headers = await _headers(jsonContent: false);
    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(headers);

    request.fields['taskId'] = taskId;
    request.fields['employeeId'] = employeeId;

    request.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: fileName),
    );

    final response = await _sendMultipartWithAuthRetry(request);

    if (response.statusCode == 200 || response.statusCode == 201) {
      final decoded = json.decode(response.body);
      if (decoded is Map<String, dynamic> && decoded['path'] is String) {
        return decoded['path'] as String;
      }
      throw Exception('Upload succeeded but response invalid');
    } else {
      final msg = _extractErrorMessage(response);
      throw Exception('Failed to upload attachment (${response.statusCode}): $msg');
    }
  }
}
