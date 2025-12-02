import 'dart:convert';
import '../models/report_model.dart';
import 'package:field_check/utils/http_util.dart';
import 'user_service.dart';

class ReportService {
  final String _basePath = '/api/reports';

  Future<Map<String, String>> _headers({bool jsonContent = true}) async {
    final headers = <String, String>{};
    if (jsonContent) headers['Content-Type'] = 'application/json';
    final token = await UserService().getToken();
    if (token != null) headers['Authorization'] = 'Bearer $token';
    return headers;
  }

  Future<List<ReportModel>> fetchReports({String? type}) async {
    final queryParams = type != null ? {'type': type} : null;
    final response = await HttpUtil().get(_basePath, queryParams: queryParams, headers: await _headers(jsonContent: false));
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
  }) async {
    final response = await HttpUtil().post(
      _basePath,
      headers: await _headers(),
      body: {
        'type': 'task',
        'taskId': taskId,
        'employeeId': employeeId,
        'content': content,
      },
    );
    if (response.statusCode == 201 || response.statusCode == 200) {
      return ReportModel.fromJson(json.decode(response.body));
    } else {
      throw Exception('Failed to create task report');
    }
  }
}