import 'package:flutter/material.dart';

class ReportUploadWidget extends StatefulWidget {
  final Function(String fileName, List<int> fileBytes)? onFileSelected;
  final Function(String message)? onError;

  const ReportUploadWidget({super.key, this.onFileSelected, this.onError});

  @override
  State<ReportUploadWidget> createState() => _ReportUploadWidgetState();
}

class _ReportUploadWidgetState extends State<ReportUploadWidget> {
  String? _selectedFileName;

  Future<void> _selectFile() async {
    // In a real app, you would use file_picker package
    // For now, this is a placeholder for the file selection logic
    debugPrint('File selection would be implemented with file_picker package');
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Upload Report',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
                color: Colors.grey.shade50,
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.cloud_upload,
                    size: 48,
                    color: Colors.blue.shade300,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _selectedFileName ?? 'Select a file to upload',
                    style: TextStyle(
                      fontSize: 14,
                      color: _selectedFileName != null
                          ? Colors.green
                          : Colors.grey,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _selectFile,
                    icon: const Icon(Icons.attach_file),
                    label: const Text('Choose File'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'File Requirements:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  _buildRequirement('Maximum size: 50 MB'),
                  _buildRequirement(
                    'Supported formats: PDF, DOC, DOCX, XLS, XLSX, TXT, JPG, PNG, GIF, ZIP',
                  ),
                  _buildRequirement('File name must be 1-255 characters'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRequirement(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.check_circle, size: 16, color: Colors.green),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }
}
