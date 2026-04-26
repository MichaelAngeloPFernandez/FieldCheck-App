import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../services/attachment_service.dart';

/// Widget for picking and uploading attachments
/// Supports: Camera, Gallery, File picker
class AttachmentPickerWidget extends StatefulWidget {
  final String resourceType; // 'report', 'task', 'ticket'
  final String resourceId;
  final AttachmentService attachmentService;
  final Function(Map<String, dynamic>) onAttachmentUploaded;
  final Function()? onUploadStart;
  final Function()? onUploadEnd;

  const AttachmentPickerWidget({
    Key? key,
    required this.resourceType,
    required this.resourceId,
    required this.attachmentService,
    required this.onAttachmentUploaded,
    this.onUploadStart,
    this.onUploadEnd,
  }) : super(key: key);

  @override
  State<AttachmentPickerWidget> createState() => _AttachmentPickerWidgetState();
}

class _AttachmentPickerWidgetState extends State<AttachmentPickerWidget> {
  final ImagePicker _imagePicker = ImagePicker();
  bool _isUploading = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Add Attachments',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildPickerButton(
                icon: Icons.camera_alt,
                label: 'Camera',
                onPressed: _pickFromCamera,
                enabled: !_isUploading,
              ),
              const SizedBox(width: 8),
              _buildPickerButton(
                icon: Icons.image,
                label: 'Gallery',
                onPressed: _pickFromGallery,
                enabled: !_isUploading,
              ),
              const SizedBox(width: 8),
              _buildPickerButton(
                icon: Icons.folder,
                label: 'Files',
                onPressed: _pickFile,
                enabled: !_isUploading,
              ),
            ],
          ),
        ),
        if (_isUploading)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                CircularProgressIndicator(),
                SizedBox(height: 8),
                Text('Uploading file...'),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildPickerButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required bool enabled,
  }) {
    return ElevatedButton.icon(
      onPressed: enabled ? onPressed : null,
      icon: Icon(icon),
      label: Text(label),
    );
  }

  Future<void> _pickFromCamera() async {
    try {
      final XFile? photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85, // Compress to 85% quality
      );

      if (photo != null) {
        await _uploadFile(File(photo.path), photo.name);
      }
    } catch (e) {
      _showError('Camera error: $e');
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final XFile? photo = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );

      if (photo != null) {
        await _uploadFile(File(photo.path), photo.name);
      }
    } catch (e) {
      _showError('Gallery error: $e');
    }
  }

  Future<void> _pickFile() async {
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'pdf',
          'doc',
          'docx',
          'xls',
          'xlsx',
          'jpg',
          'jpeg',
          'png',
          'gif'
        ],
      );

      if (result != null && result.files.single.path != null) {
        await _uploadFile(
          File(result.files.single.path!),
          result.files.single.name,
        );
      }
    } catch (e) {
      _showError('File picker error: $e');
    }
  }

  Future<void> _uploadFile(File file, String fileName) async {
    try {
      setState(() => _isUploading = true);
      widget.onUploadStart?.call();

      final response = await widget.attachmentService.uploadAttachment(
        file: file,
        resourceType: widget.resourceType,
        resourceId: widget.resourceId,
      );

      widget.onAttachmentUploaded(response);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Uploaded: $fileName')),
        );
      }
    } catch (e) {
      _showError('Upload failed: $e');
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
        widget.onUploadEnd?.call();
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }
}
