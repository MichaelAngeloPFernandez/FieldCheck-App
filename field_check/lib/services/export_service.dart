import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:field_check/services/user_service.dart';
import 'package:field_check/config/api_config.dart';

class ExportService {
  final String _basePath = '/api/export';

  Future<Map<String, String>> _buildHeaders() async {
    final token = await UserService().getToken();
    return {if (token != null) 'Authorization': 'Bearer $token'};
  }

  /// Export attendance records as PDF (Admin Only)
  /// @param startDate - Optional start date (ISO format)
  /// @param endDate - Optional end date (ISO format)
  /// @param employeeId - Optional employee ID filter
  /// @param geofenceId - Optional geofence ID filter
  /// @returns File path of downloaded PDF
  /// @throws Exception if user is not an admin
  Future<String> exportAttendancePDF({
    String? startDate,
    String? endDate,
    String? employeeId,
    String? geofenceId,
  }) async {
    try {
      final headers = await _buildHeaders();
      final queryParams = <String, String>{};

      if (startDate != null) queryParams['startDate'] = startDate;
      if (endDate != null) queryParams['endDate'] = endDate;
      if (employeeId != null) queryParams['employeeId'] = employeeId;
      if (geofenceId != null) queryParams['geofenceId'] = geofenceId;

      final url = Uri.parse(
        '${ApiConfig.baseUrl}$_basePath/attendance/pdf',
      ).replace(queryParameters: queryParams);

      final response = await http.get(url, headers: headers);

      if (response.statusCode == 200) {
        return await _saveFile(
          'attendance_${DateTime.now().millisecondsSinceEpoch}.pdf',
          response.bodyBytes,
        );
      } else if (response.statusCode == 403) {
        throw Exception('Only administrators can export PDF reports');
      } else {
        throw Exception('Failed to export PDF: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error exporting attendance PDF: $e');
    }
  }

  /// Export attendance records as Excel
  /// @param startDate - Optional start date (ISO format)
  /// @param endDate - Optional end date (ISO format)
  /// @param employeeId - Optional employee ID filter
  /// @param geofenceId - Optional geofence ID filter
  /// @returns File path of downloaded Excel file
  Future<String> exportAttendanceExcel({
    String? startDate,
    String? endDate,
    String? employeeId,
    String? geofenceId,
  }) async {
    try {
      final headers = await _buildHeaders();
      final queryParams = <String, String>{};

      if (startDate != null) queryParams['startDate'] = startDate;
      if (endDate != null) queryParams['endDate'] = endDate;
      if (employeeId != null) queryParams['employeeId'] = employeeId;
      if (geofenceId != null) queryParams['geofenceId'] = geofenceId;

      final url = Uri.parse(
        '${ApiConfig.baseUrl}$_basePath/attendance/excel',
      ).replace(queryParameters: queryParams);

      final response = await http.get(url, headers: headers);

      if (response.statusCode == 200) {
        return await _saveFile(
          'attendance_${DateTime.now().millisecondsSinceEpoch}.xlsx',
          response.bodyBytes,
        );
      } else {
        throw Exception('Failed to export Excel: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error exporting attendance Excel: $e');
    }
  }

  /// Export tasks as PDF (Admin Only)
  /// @param startDate - Optional start date (ISO format)
  /// @param endDate - Optional end date (ISO format)
  /// @param status - Optional status filter (pending, in_progress, completed)
  /// @returns File path of downloaded PDF
  /// @throws Exception if user is not an admin
  Future<String> exportTasksPDF({
    String? startDate,
    String? endDate,
    String? status,
  }) async {
    try {
      final headers = await _buildHeaders();
      final queryParams = <String, String>{};

      if (startDate != null) queryParams['startDate'] = startDate;
      if (endDate != null) queryParams['endDate'] = endDate;
      if (status != null) queryParams['status'] = status;

      final url = Uri.parse(
        '${ApiConfig.baseUrl}$_basePath/tasks/pdf',
      ).replace(queryParameters: queryParams);

      final response = await http.get(url, headers: headers);

      if (response.statusCode == 200) {
        return await _saveFile(
          'tasks_${DateTime.now().millisecondsSinceEpoch}.pdf',
          response.bodyBytes,
        );
      } else if (response.statusCode == 403) {
        throw Exception('Only administrators can export PDF reports');
      } else {
        throw Exception('Failed to export PDF: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error exporting tasks PDF: $e');
    }
  }

  /// Export tasks as Excel
  /// @param startDate - Optional start date (ISO format)
  /// @param endDate - Optional end date (ISO format)
  /// @param status - Optional status filter
  /// @returns File path of downloaded Excel file
  Future<String> exportTasksExcel({
    String? startDate,
    String? endDate,
    String? status,
  }) async {
    try {
      final headers = await _buildHeaders();
      final queryParams = <String, String>{};

      if (startDate != null) queryParams['startDate'] = startDate;
      if (endDate != null) queryParams['endDate'] = endDate;
      if (status != null) queryParams['status'] = status;

      final url = Uri.parse(
        '${ApiConfig.baseUrl}$_basePath/tasks/excel',
      ).replace(queryParameters: queryParams);

      final response = await http.get(url, headers: headers);

      if (response.statusCode == 200) {
        return await _saveFile(
          'tasks_${DateTime.now().millisecondsSinceEpoch}.xlsx',
          response.bodyBytes,
        );
      } else {
        throw Exception('Failed to export Excel: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error exporting tasks Excel: $e');
    }
  }

  /// Export combined report (attendance + tasks) as Excel
  /// @param startDate - Optional start date (ISO format)
  /// @param endDate - Optional end date (ISO format)
  /// @returns File path of downloaded Excel file
  Future<String> exportCombinedExcel({
    String? startDate,
    String? endDate,
  }) async {
    try {
      final headers = await _buildHeaders();
      final queryParams = <String, String>{};

      if (startDate != null) queryParams['startDate'] = startDate;
      if (endDate != null) queryParams['endDate'] = endDate;

      final url = Uri.parse(
        '${ApiConfig.baseUrl}$_basePath/combined/excel',
      ).replace(queryParameters: queryParams);

      final response = await http.get(url, headers: headers);

      if (response.statusCode == 200) {
        return await _saveFile(
          'combined_report_${DateTime.now().millisecondsSinceEpoch}.xlsx',
          response.bodyBytes,
        );
      } else {
        throw Exception('Failed to export Excel: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error exporting combined Excel: $e');
    }
  }

  /// Save file to device storage
  /// @param filename - Name of the file
  /// @param bytes - File content as bytes
  /// @returns File path
  Future<String> _saveFile(String filename, List<int> bytes) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$filename');
      await file.writeAsBytes(bytes);
      return file.path;
    } catch (e) {
      throw Exception('Error saving file: $e');
    }
  }

  /// Get list of exported files
  /// @returns List of file paths
  Future<List<String>> getExportedFiles() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final files = directory.listSync();
      return files
          .where((f) => f.path.endsWith('.pdf') || f.path.endsWith('.xlsx'))
          .map((f) => f.path)
          .toList();
    } catch (e) {
      throw Exception('Error getting exported files: $e');
    }
  }

  /// Delete an exported file
  /// @param filePath - Path of the file to delete
  Future<void> deleteExportedFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      throw Exception('Error deleting file: $e');
    }
  }

  /// Share exported file (opens share dialog)
  /// @param filePath - Path of the file to share
  Future<void> shareFile(String filePath) async {
    try {
      // This would typically use a package like 'share_plus' to share files
      // For now, we just return the file path
      // Implementation depends on the share_plus package
      throw UnimplementedError(
        'Share functionality requires share_plus package',
      );
    } catch (e) {
      throw Exception('Error sharing file: $e');
    }
  }
}
