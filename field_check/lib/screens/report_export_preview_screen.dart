import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:field_check/services/attendance_service.dart';
import 'package:field_check/services/user_service.dart';
import 'package:field_check/config/api_config.dart';
import 'package:field_check/models/report_model.dart';
import 'package:http/http.dart' as http;

class ReportExportPreviewScreen extends StatefulWidget {
  final List<AttendanceRecord> records;
  final String reportType; // 'attendance' or 'task'
  final DateTime? startDate;
  final DateTime? endDate;
  final String? locationFilter;
  final String? statusFilter;
  final List<ReportModel>? taskReports;

  const ReportExportPreviewScreen({
    super.key,
    required this.records,
    required this.reportType,
    this.startDate,
    this.endDate,
    this.locationFilter,
    this.statusFilter,
    this.taskReports,
  });

  @override
  State<ReportExportPreviewScreen> createState() =>
      _ReportExportPreviewScreenState();
}

class _ReportExportPreviewScreenState extends State<ReportExportPreviewScreen> {
  static const platform = MethodChannel('com.fieldcheck.field_check/files');
  bool _isExporting = false;
  String? _exportError = null;

  Future<String?> _saveFileToDownloads(
    String fileName,
    List<int> fileBytes,
  ) async {
    try {
      debugPrint('Saving file via native channel: $fileName');
      final result = await platform.invokeMethod<Map>('saveFile', {
        'fileName': fileName,
        'fileBytes': fileBytes,
      });

      if (result != null) {
        final path = result['path'] as String?;
        final size = result['size'] as int?;
        debugPrint('✓ File saved successfully via native channel');
        debugPrint('  Path: $path');
        debugPrint('  Size: $size bytes');
        return path;
      }
    } catch (e) {
      debugPrint('Native channel error: $e');
    }
    return null;
  }

  Future<void> _exportToPDF() async {
    setState(() {
      _isExporting = true;
      _exportError = null;
    });

    try {
      debugPrint('Starting PDF export...');
      final token = await _getToken();
      final queryParams = <String, String>{'type': widget.reportType};

      if (widget.startDate != null) {
        queryParams['startDate'] = widget.startDate!.toIso8601String();
      }
      if (widget.endDate != null) {
        queryParams['endDate'] = widget.endDate!.toIso8601String();
      }
      if (widget.locationFilter != null) {
        queryParams['geofenceId'] = widget.locationFilter!;
      }
      if (widget.statusFilter != null) {
        queryParams['status'] = widget.statusFilter!;
      }

      final uri = Uri.parse(
        '${ApiConfig.baseUrl}/api/export/${widget.reportType}/pdf',
      ).replace(queryParameters: queryParams);

      debugPrint('Requesting PDF from: $uri');
      final response = await http
          .get(uri, headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 30));

      debugPrint(
        'Response status: ${response.statusCode}, body length: ${response.bodyBytes.length}',
      );

      if (response.statusCode == 200) {
        // Save file using native Android method
        try {
          final fileName =
              'FieldCheck_Report_${DateTime.now().millisecondsSinceEpoch}.pdf';
          final filePath = await _saveFileToDownloads(
            fileName,
            response.bodyBytes,
          );

          if (filePath == null) {
            throw Exception('Failed to save file via native channel');
          }

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('✓ PDF saved to: $filePath'),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 4),
              ),
            );
            // Show download completion dialog
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('✓ Export Complete'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Your PDF report has been saved!'),
                    const SizedBox(height: 12),
                    const Text(
                      'File path:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      filePath,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '📁 Check your Downloads folder',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('OK'),
                  ),
                ],
              ),
            );
          }
        } catch (e) {
          throw Exception('Failed to save PDF file: $e');
        }
      } else {
        throw Exception('Failed to export PDF: ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        _exportError = 'Export failed: $e';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isExporting = false;
      });
    }
  }

  Future<void> _exportToCSV() async {
    setState(() {
      _isExporting = true;
      _exportError = null;
    });

    try {
      debugPrint('Starting CSV export...');
      final token = await _getToken();
      final queryParams = <String, String>{'type': widget.reportType};

      if (widget.startDate != null) {
        queryParams['startDate'] = widget.startDate!.toIso8601String();
      }
      if (widget.endDate != null) {
        queryParams['endDate'] = widget.endDate!.toIso8601String();
      }
      if (widget.locationFilter != null) {
        queryParams['geofenceId'] = widget.locationFilter!;
      }
      if (widget.statusFilter != null) {
        queryParams['status'] = widget.statusFilter!;
      }

      final uri = Uri.parse(
        '${ApiConfig.baseUrl}/api/export/${widget.reportType}/excel',
      ).replace(queryParameters: queryParams);

      debugPrint('Requesting CSV from: $uri');
      final response = await http
          .get(uri, headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 30));

      debugPrint(
        'Response status: ${response.statusCode}, body length: ${response.bodyBytes.length}',
      );

      if (response.statusCode == 200) {
        // Save file using native Android method
        try {
          final fileName =
              'FieldCheck_Report_${DateTime.now().millisecondsSinceEpoch}.csv';
          final filePath = await _saveFileToDownloads(
            fileName,
            response.bodyBytes,
          );

          if (filePath == null) {
            throw Exception('Failed to save file via native channel');
          }

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('✓ CSV saved to: $filePath'),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 4),
              ),
            );
            // Show download completion dialog
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('✓ Export Complete'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Your CSV report has been saved!'),
                    const SizedBox(height: 12),
                    const Text(
                      'File path:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      filePath,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '📁 Check your Downloads folder',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('OK'),
                  ),
                ],
              ),
            );
          }
        } catch (e) {
          throw Exception('Failed to save CSV file: $e');
        }
      } else {
        throw Exception('Failed to export CSV: ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        _exportError = 'Export failed: $e';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isExporting = false;
      });
    }
  }

  Future<String?> _getToken() async {
    try {
      return await UserService().getToken();
    } catch (e) {
      debugPrint('Error getting token: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM dd, yyyy');
    final timeFormat = DateFormat('hh:mm a');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Export Preview'),
        backgroundColor: const Color(0xFF2688d4),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Export format selection
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: _isExporting ? null : _exportToPDF,
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('Export PDF'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _isExporting ? null : _exportToCSV,
                  icon: const Icon(Icons.table_chart),
                  label: const Text('Export CSV'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey,
                  ),
                ),
              ],
            ),
          ),

          if (_isExporting)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(),
            ),

          if (_exportError != null)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red),
                ),
                child: Text(
                  _exportError!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ),

          // Print preview
          Expanded(
            child: SingleChildScrollView(
              child: Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withAlpha(25), blurRadius: 8),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Center(
                      child: Column(
                        children: [
                          const Text(
                            'FIELD CHECK REPORT',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.reportType == 'attendance'
                                ? 'Attendance Report'
                                : 'Task Report',
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Generated on ${dateFormat.format(DateTime.now())} at ${timeFormat.format(DateTime.now())}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const Divider(thickness: 2),
                    const SizedBox(height: 16),

                    // Filter info
                    if (widget.startDate != null || widget.endDate != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Date Range:',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '${widget.startDate != null ? dateFormat.format(widget.startDate!) : 'N/A'} to ${widget.endDate != null ? dateFormat.format(widget.endDate!) : 'N/A'}',
                          ),
                          const SizedBox(height: 12),
                        ],
                      ),

                    if (widget.locationFilter != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Location Filter:',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(widget.locationFilter!),
                          const SizedBox(height: 12),
                        ],
                      ),

                    // Records count
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.withAlpha(30),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Total Records: ${widget.records.length}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Attendance Table header
                    if (widget.records.isNotEmpty)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'ATTENDANCE RECORDS',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: const Text(
                                    'Employee',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 1,
                                  child: const Text(
                                    'Date',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 1,
                                  child: const Text(
                                    'Time',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 1,
                                  child: const Text(
                                    'Location',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 1,
                                  child: const Text(
                                    'Status',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),

                          // Table rows (preview first 10)
                          ...widget.records.take(10).map((record) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      record.employeeName ?? 'Unknown',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 1,
                                    child: Text(
                                      dateFormat.format(record.timestamp),
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 1,
                                    child: Text(
                                      timeFormat.format(record.timestamp),
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 1,
                                    child: Text(
                                      record.geofenceName ?? 'N/A',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 1,
                                    child: Text(
                                      record.isCheckIn ? 'In' : 'Out',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: record.isCheckIn
                                            ? Colors.green
                                            : Colors.red,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),

                          if (widget.records.length > 10)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                '... and ${widget.records.length - 10} more records',
                                style: const TextStyle(
                                  fontStyle: FontStyle.italic,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                        ],
                      )
                    else
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Text(
                            'No attendance records to display',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      ),

                    const SizedBox(height: 24),

                    // Tasks section
                    if (widget.taskReports != null &&
                        widget.taskReports!.isNotEmpty)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'TASKS COMPLETED',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: const Text(
                                    'Employee',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: const Text(
                                    'Task',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 1,
                                  child: const Text(
                                    'Status',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 1,
                                  child: const Text(
                                    'Date',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...widget.taskReports!.take(10).map((task) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      task.employeeName ?? 'Unknown',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      task.taskTitle ?? 'N/A',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 1,
                                    child: Text(
                                      task.status,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: task.status == 'completed'
                                            ? Colors.green
                                            : Colors.orange,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 1,
                                    child: Text(
                                      dateFormat.format(task.submittedAt),
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                          if (widget.taskReports!.length > 10)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                '... and ${widget.taskReports!.length - 10} more tasks',
                                style: const TextStyle(
                                  fontStyle: FontStyle.italic,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                        ],
                      ),

                    const SizedBox(height: 24),
                    const Divider(thickness: 2),
                    const SizedBox(height: 12),

                    // Footer
                    Center(
                      child: Text(
                        'This is a preview of your export. Click "Export PDF" or "Export CSV" to download the complete file.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
