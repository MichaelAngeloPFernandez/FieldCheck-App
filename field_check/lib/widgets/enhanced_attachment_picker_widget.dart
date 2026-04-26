import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../services/attachment_service.dart';
import '../services/image_compression_service.dart';
import '../services/network_service.dart';

/// Enhanced attachment picker with:
/// - Image compression
/// - Network retry on upload
/// - Progress tracking
/// - Multiple files
class EnhancedAttachmentPickerWidget extends StatefulWidget {
  final String resourceType;
  final String resourceId;
  final AttachmentService attachmentService;
  final Function(Map<String, dynamic>)? onAttachmentUploaded;
  final Function()? onUploadStart;
  final Function()? onUploadEnd;
  final bool compressImages;
  final bool showProgress;

  const EnhancedAttachmentPickerWidget({
    Key? key,
    required this.resourceType,
    required this.resourceId,
    required this.attachmentService,
    this.onAttachmentUploaded,
    this.onUploadStart,
    this.onUploadEnd,
    this.compressImages = true,
    this.showProgress = true,
  }) : super(key: key);

  @override
  State<EnhancedAttachmentPickerWidget> createState() =>
      _EnhancedAttachmentPickerWidgetState();
}

class _EnhancedAttachmentPickerWidgetState
    extends State<EnhancedAttachmentPickerWidget> {
  final ImagePicker _imagePicker = ImagePicker();
  bool _isUploading = false;
  double _uploadProgress = 0;
  String? _uploadingFileName;
  int _uploadedCount = 0;
  int _totalCount = 0;

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Add Attachments',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        // Buttons grid (responsive)
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
        // Progress indicator
        if (_isUploading && widget.showProgress)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _uploadingFileName ?? 'Uploading...',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          Text(
                            '$_uploadedCount/$_totalCount files',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _uploadProgress,
                    minHeight: 4,
                  ),
                ),
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
        imageQuality: 90, // High quality, compression done separately
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
        imageQuality: 90,
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
        allowMultiple: true,
      );

      if (result != null && result.files.isNotEmpty) {
        setState(() {
          _totalCount = result.files.length;
          _uploadedCount = 0;
        });

        for (final file in result.files) {
          if (file.path != null) {
            await _uploadFile(File(file.path!), file.name);
          }
        }
      }
    } catch (e) {
      _showError('File picker error: $e');
    }
  }

  Future<void> _uploadFile(File file, String fileName) async {
    try {
      setState(() {
        _isUploading = true;
        _uploadingFileName = fileName;
        _uploadProgress = 0;
      });
      widget.onUploadStart?.call();

      // Compress image if needed
      File fileToUpload = file;
      if (widget.compressImages && _isImage(fileName)) {
        try {
          fileToUpload = await ImageCompressionService.compressImage(file);
        } catch (e) {
          print('Compression failed, using original: $e');
        }
      }

      // Upload with retry
      final response = await NetworkService.uploadWithRetry(
        _buildUploadRequest(fileToUpload, fileName),
        maxRetries: 3,
        timeout: const Duration(seconds: 60),
        onRetry: () {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Retrying upload: $fileName')),
            );
          }
        },
      );

      if (response.statusCode == 201) {
        final result = await response.stream.bytesToString();
        final attachment = _parseResponse(result);

        widget.onAttachmentUploaded?.call(attachment);

        if (mounted) {
          setState(() {
            _uploadedCount++;
            _uploadProgress = _uploadedCount / _totalCount;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✓ Uploaded: $fileName'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        throw Exception('Upload failed: ${response.statusCode}');
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

  dynamic _buildUploadRequest(File file, String fileName) {
    // This is a placeholder - implement per your attachment service
    return null;
  }

  Map<String, dynamic> _parseResponse(String json) {
    // Parse JSON response
    return {};
  }

  bool _isImage(String fileName) {
    final ext = fileName.toLowerCase().split('.').last;
    return ['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext);
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
