import 'package:flutter/material.dart';
import '../services/ticket_service.dart';
import '../services/attachment_service.dart';
import '../services/template_service.dart';
import '../models/ticket_model.dart';
import '../widgets/dynamic_form_renderer.dart';
import '../widgets/attachment_picker_widget.dart';

/// Full ticket creation flow
///
/// Features:
/// - Load template from API
/// - Render dynamic form from JSON Schema
/// - Capture GPS location
/// - Upload attachments
/// - Submit ticket with validation
class TicketCreationScreen extends StatefulWidget {
  final String templateId;
  final AttachmentService attachmentService;
  final ValueChanged<TicketModel>? onTicketCreated;

  const TicketCreationScreen({
    super.key,
    required this.templateId,
    required this.attachmentService,
    this.onTicketCreated,
  });

  @override
  State<TicketCreationScreen> createState() => _TicketCreationScreenState();
}

class _TicketCreationScreenState extends State<TicketCreationScreen> {
  late final GlobalKey<DynamicFormRendererState> _formKey;

  Map<String, dynamic>? _template;
  bool _isLoadingTemplate = true;
  String? _loadError;

  final List<Map<String, dynamic>> _attachments = [];
  bool _isSubmitting = false;
  bool _isFormValid = false;

  @override
  void initState() {
    super.initState();
    _formKey = GlobalKey<DynamicFormRendererState>();
    _loadTemplate();
  }

  Future<void> _loadTemplate() async {
    try {
      setState(() {
        _isLoadingTemplate = true;
        _loadError = null;
      });

      final templateModel = await TemplateService.getTemplate(
        widget.templateId,
      );

      setState(() {
        _template = {
          'name': templateModel.name,
          'description': templateModel.description,
          'jsonSchema': templateModel.jsonSchema,
          'slaSeconds': templateModel.slaSeconds,
        };
        _isLoadingTemplate = false;
      });
    } catch (e) {
      setState(() {
        _loadError = e.toString();
        _isLoadingTemplate = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load template: $e')));
      }
    }
  }

  Future<void> _submitTicket() async {
    if (!_isFormValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fix validation errors')),
      );
      return;
    }

    try {
      setState(() => _isSubmitting = true);

      // Get form data from renderer
      final formData = _formKey.currentState?.getFormData() ?? {};

      // Extract attachment IDs
      // Create ticket
      final result = await TicketService.createTicket(
        templateId: widget.templateId,
        data: formData,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ Ticket ${result.ticketNo} created'),
            backgroundColor: Colors.green,
          ),
        );

        widget.onTicketCreated?.call(result);

        // Navigate back or to ticket details
        Navigator.of(context).pop(result);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_template?['name'] ?? 'Create Ticket')),
      body: _isLoadingTemplate
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('Error: $_loadError'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loadTemplate,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : _buildContent(),
      floatingActionButton: _template != null
          ? FloatingActionButton.extended(
              onPressed: _isSubmitting ? null : _submitTicket,
              label: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Submit'),
              icon: _isSubmitting ? null : const Icon(Icons.check),
            )
          : null,
    );
  }

  Widget _buildContent() {
    final schema = _template?['jsonSchema'] as Map<String, dynamic>? ?? {};

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Template description
        if (_template?['description'] != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Service Description',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Text(_template!['description']),
              ],
            ),
          ),

        // SLA info
        Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Card(
            color: Colors.blue.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.schedule, color: Colors.blue.shade700),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Service Level Agreement',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        Text(
                          'Estimated completion: ${_formatSLA((_template!['slaSeconds'] as int?) ?? 0)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Dynamic form
        Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: DynamicFormRenderer(
                key: _formKey,
                jsonSchema: schema,
                onValidationChanged: (isValid) {
                  setState(() => _isFormValid = isValid);
                },
              ),
            ),
          ),
        ),

        // Attachments section
        Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AttachmentPickerWidget(
                resourceType: 'ticket',
                resourceId: widget
                    .templateId, // Use template as resource until ticket created
                attachmentService: widget.attachmentService,
                onAttachmentUploaded: (attachment) {
                  setState(() {
                    _attachments.add(attachment);
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('✓ Attached: ${attachment['fileName']}'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
              ),

              // Show attached files
              if (_attachments.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Attached Files (${_attachments.length})',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                ..._attachments.map(
                  (att) => ListTile(
                    title: Text(att['fileName']),
                    subtitle: Text(_formatFileSize(att['fileSize'])),
                    trailing: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        final messenger = ScaffoldMessenger.of(context);
                        setState(() {
                          _attachments.removeWhere(
                            (a) => a['_id'] == att['_id'],
                          );
                        });

                        // Delete from server
                        widget.attachmentService
                            .deleteAttachment(att['_id'])
                            .catchError((e) {
                              messenger.showSnackBar(
                                SnackBar(content: Text('Failed to delete: $e')),
                              );
                            });
                      },
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 80), // Space for FAB
      ],
    );
  }

  String _formatSLA(int slaSeconds) {
    final hours = slaSeconds ~/ 3600;
    final minutes = (slaSeconds % 3600) ~/ 60;

    if (hours > 0) {
      return '$hours hours${minutes > 0 ? ' $minutes min' : ''}';
    }
    return '$minutes minutes';
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
