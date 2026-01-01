import 'dart:typed_data';

class ExportResult {
  final Uint8List bytes;
  final String filename;
  final String mimeType;

  const ExportResult({
    required this.bytes,
    required this.filename,
    required this.mimeType,
  });
}

abstract class ExportService {
  Future<ExportResult> exportAttendancePDF({
    String? startDate,
    String? endDate,
    String? employeeId,
    String? geofenceId,
  });

  Future<ExportResult> exportAttendanceExcel({
    String? startDate,
    String? endDate,
    String? employeeId,
    String? geofenceId,
  });

  Future<ExportResult> exportTasksPDF({
    String? startDate,
    String? endDate,
    String? status,
  });

  Future<ExportResult> exportTasksExcel({
    String? startDate,
    String? endDate,
    String? status,
  });

  Future<ExportResult> exportCombinedExcel({
    String? startDate,
    String? endDate,
  });
}
