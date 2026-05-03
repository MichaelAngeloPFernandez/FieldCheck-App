import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'package:field_check/config/api_config.dart';
import 'package:field_check/services/user_service.dart';

import 'export_service_stub.dart';

class ExportServiceImpl implements ExportService {
  final String _basePath = '/api/export';

  Future<Map<String, String>> _buildHeaders() async {
    final token = await UserService().getToken();
    return {if (token != null) 'Authorization': 'Bearer $token'};
  }

  Future<ExportResult> _getAndSave({
    required Uri url,
    required String filename,
    required String mimeType,
    bool adminOnly = false,
  }) async {
    final headers = await _buildHeaders();
    final response = await http.get(url, headers: headers);

    if (response.statusCode == 200) {
      final bytes = Uint8List.fromList(response.bodyBytes);
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$filename');
      await file.writeAsBytes(bytes, flush: true);

      return ExportResult(bytes: bytes, filename: file.path, mimeType: mimeType);
    }

    if (adminOnly && response.statusCode == 403) {
      throw Exception('Only administrators can export this report');
    }

    throw Exception('Failed to export file: ${response.statusCode}');
  }

  @override
  Future<ExportResult> exportAttendancePDF({
    String? startDate,
    String? endDate,
    String? employeeId,
    String? geofenceId,
  }) async {
    final queryParams = <String, String>{};
    if (startDate != null) queryParams['startDate'] = startDate;
    if (endDate != null) queryParams['endDate'] = endDate;
    if (employeeId != null) queryParams['employeeId'] = employeeId;
    if (geofenceId != null) queryParams['geofenceId'] = geofenceId;

    final url = Uri.parse('${ApiConfig.baseUrl}$_basePath/attendance/pdf')
        .replace(queryParameters: queryParams);

    return _getAndSave(
      url: url,
      filename: 'attendance_${DateTime.now().millisecondsSinceEpoch}.pdf',
      mimeType: 'application/pdf',
      adminOnly: true,
    );
  }

  @override
  Future<ExportResult> exportAttendanceExcel({
    String? startDate,
    String? endDate,
    String? employeeId,
    String? geofenceId,
  }) async {
    final queryParams = <String, String>{};
    if (startDate != null) queryParams['startDate'] = startDate;
    if (endDate != null) queryParams['endDate'] = endDate;
    if (employeeId != null) queryParams['employeeId'] = employeeId;
    if (geofenceId != null) queryParams['geofenceId'] = geofenceId;

    final url = Uri.parse('${ApiConfig.baseUrl}$_basePath/attendance/excel')
        .replace(queryParameters: queryParams);

    return _getAndSave(
      url: url,
      filename: 'attendance_${DateTime.now().millisecondsSinceEpoch}.xlsx',
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
  }

  @override
  Future<ExportResult> exportTasksPDF({
    String? startDate,
    String? endDate,
    String? status,
  }) async {
    final queryParams = <String, String>{};
    if (startDate != null) queryParams['startDate'] = startDate;
    if (endDate != null) queryParams['endDate'] = endDate;
    if (status != null) queryParams['status'] = status;

    final url = Uri.parse('${ApiConfig.baseUrl}$_basePath/tasks/pdf')
        .replace(queryParameters: queryParams);

    return _getAndSave(
      url: url,
      filename: 'tasks_${DateTime.now().millisecondsSinceEpoch}.pdf',
      mimeType: 'application/pdf',
      adminOnly: true,
    );
  }

  @override
  Future<ExportResult> exportTasksExcel({
    String? startDate,
    String? endDate,
    String? status,
  }) async {
    final queryParams = <String, String>{};
    if (startDate != null) queryParams['startDate'] = startDate;
    if (endDate != null) queryParams['endDate'] = endDate;
    if (status != null) queryParams['status'] = status;

    final url = Uri.parse('${ApiConfig.baseUrl}$_basePath/tasks/excel')
        .replace(queryParameters: queryParams);

    return _getAndSave(
      url: url,
      filename: 'tasks_${DateTime.now().millisecondsSinceEpoch}.xlsx',
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
  }

  @override
  Future<ExportResult> exportCombinedExcel({
    String? startDate,
    String? endDate,
  }) async {
    final queryParams = <String, String>{};
    if (startDate != null) queryParams['startDate'] = startDate;
    if (endDate != null) queryParams['endDate'] = endDate;

    final url = Uri.parse('${ApiConfig.baseUrl}$_basePath/combined/excel')
        .replace(queryParameters: queryParams);

    return _getAndSave(
      url: url,
      filename: 'combined_report_${DateTime.now().millisecondsSinceEpoch}.xlsx',
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
  }
}
