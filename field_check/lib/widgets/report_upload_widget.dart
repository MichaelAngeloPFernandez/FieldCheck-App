import 'package:flutter/material.dart';
import 'package:field_check/utils/app_theme.dart';
import 'package:field_check/widgets/app_widgets.dart';

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
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final primary = theme.colorScheme.primary;
    return Card(
      elevation: 2,
      margin: const EdgeInsets.all(AppTheme.md),
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Upload Report',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(AppTheme.lg),
              decoration: BoxDecoration(
                border: Border.all(
                  color: theme.dividerColor.withValues(alpha: 0.5),
                ),
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                color: theme.colorScheme.surface,
              ),
              child: Column(
                children: [
                  Icon(Icons.cloud_upload, size: 48, color: primary),
                  const SizedBox(height: 12),
                  Text(
                    _selectedFileName ?? 'Select a file to upload',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: _selectedFileName != null
                          ? primary
                          : onSurface.withValues(alpha: 0.75),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  AppWidgets.primaryButton(
                    label: 'Choose File',
                    onPressed: _selectFile,
                    icon: Icons.attach_file,
                    width: double.infinity,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(AppTheme.md),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(
                  alpha: 0.35,
                ),
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'File Requirements:',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: onSurface.withValues(alpha: 0.9),
                    ),
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
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final primary = theme.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.xs),
      child: Row(
        children: [
          Icon(Icons.check_circle, size: 16, color: primary),
          const SizedBox(width: AppTheme.sm),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: onSurface.withValues(alpha: 0.82),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
