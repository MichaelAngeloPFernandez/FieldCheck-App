import 'package:flutter/material.dart';
import '../services/ticket_service.dart';
import '../services/attachment_service.dart';
import '../services/draft_service.dart';
import '../services/template_service.dart';
import '../models/ticket_model.dart';
import '../widgets/dynamic_form_renderer.dart';
import '../widgets/enhanced_attachment_picker_widget.dart';

/// Enhanced ticket creation screen with:
/// - Offline draft support
/// - Auto-save every 30 seconds
/// - Slow network handling
/// - Responsive design (tablet + mobile)
/// - Dark mode support
class EnhancedTicketCreationScreen extends StatefulWidget {
  final String templateId;
  final AttachmentService attachmentService;
  final DraftService draftService;
  final String? requesterEmail;
  final ValueChanged<TicketModel>? onTicketCreated;

  const EnhancedTicketCreationScreen({
    super.key,
    required this.templateId,
    required this.attachmentService,
    required this.draftService,
    this.onTicketCreated,
    this.requesterEmail,
  });

  @override
  State<EnhancedTicketCreationScreen> createState() =>
      _EnhancedTicketCreationScreenState();
}

class _EnhancedTicketCreationScreenState
    extends State<EnhancedTicketCreationScreen> {
  late final GlobalKey<DynamicFormRendererState> _formKey;

  Map<String, dynamic>? _template;
  bool _isLoadingTemplate = true;
  String? _loadError;

  final List<Map<String, dynamic>> _attachments = [];
  bool _isSubmitting = false;
  bool _isFormValid = false;
  bool _autoSavingDraft = false;

  late Future<void> _initializeFuture;

  @override
  void initState() {
    super.initState();
    _formKey = GlobalKey<DynamicFormRendererState>();
    _initializeFuture = _initialize();
  }

  Future<void> _initialize() async {
    await _loadTemplate();
    await _checkDraft();
    _startAutoSave();
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

  Future<void> _checkDraft() async {
    try {
      final draft = await widget.draftService.loadDraft(
        templateId: widget.templateId,
        requesterEmail: widget.requesterEmail ?? '',
      );

      if (draft != null && mounted) {
        _showDraftDialog(draft);
      }
    } catch (e) {
      debugPrint('Draft check error: $e');
    }
  }

  void _showDraftDialog(Map<String, dynamic> draft) {
    final metadata = widget.draftService.getDraftMetadata(draft);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Recover Draft?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Found unsaved work from ${metadata['formattedTime']}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Text('${metadata['fieldCount']} fields filled'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteDraft();
            },
            child: const Text('Discard'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _loadDraft(draft);
            },
            child: const Text('Recover'),
          ),
        ],
      ),
    );
  }

  void _loadDraft(Map<String, dynamic> draft) {
    // Load draft data into form (if form is ready)
    if (_template != null) {
      // Form will need to be updated with draft data
      // This would be passed to DynamicFormRenderer
    }
  }

  void _startAutoSave() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 30));

      if (mounted && _template != null && !_isSubmitting) {
        await _saveDraft();
      }

      return mounted; // Continue until widget disposed
    });
  }

  Future<void> _saveDraft() async {
    try {
      setState(() => _autoSavingDraft = true);

      final formData = _formKey.currentState?.getFormData() ?? {};

      await widget.draftService.saveDraft(
        templateId: widget.templateId,
        formData: formData,
        requesterEmail: widget.requesterEmail ?? 'unknown',
      );

      if (mounted) {
        // Silent save - no notification
      }
    } catch (e) {
      debugPrint('Auto-save error: $e');
    } finally {
      if (mounted) {
        setState(() => _autoSavingDraft = false);
      }
    }
  }

  Future<void> _deleteDraft() async {
    try {
      await widget.draftService.deleteDraft(
        templateId: widget.templateId,
        requesterEmail: widget.requesterEmail ?? '',
      );
    } catch (e) {
      debugPrint('Draft delete error: $e');
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

      final formData = _formKey.currentState?.getFormData() ?? {};

      final result = await TicketService.createTicket(
        templateId: widget.templateId,
        data: formData,
      );

      // Clear draft
      await _deleteDraft();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ Ticket ${result.ticketNo} created'),
            backgroundColor: Colors.green,
          ),
        );

        widget.onTicketCreated?.call(result);
        Navigator.of(context).pop(result);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return FutureBuilder<void>(
      future: _initializeFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(title: const Text('Create Ticket')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(_template?['name'] ?? 'Create Ticket'),
            actions: [
              if (_autoSavingDraft)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Theme.of(context).appBarTheme.foregroundColor ??
                            Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          body: _buildContent(isMobile),
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
      },
    );
  }

  Widget _buildContent(bool isMobile) {
    if (_isLoadingTemplate) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_loadError != null) {
      return Center(
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
      );
    }

    final schema = _template?['jsonSchema'] as Map<String, dynamic>? ?? {};

    return ListView(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      children: [
        // Template description
        if (_template?['description'] != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
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
          ),

        const SizedBox(height: 16),

        // Dynamic form
        Card(
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

        const SizedBox(height: 16),

        // Attachments
        EnhancedAttachmentPickerWidget(
          resourceType: 'ticket',
          resourceId: widget.templateId,
          attachmentService: widget.attachmentService,
          onAttachmentUploaded: (attachment) {
            setState(() => _attachments.add(attachment));
          },
        ),

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
              trailing: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () async {
                  setState(() {
                    _attachments.removeWhere((a) => a['_id'] == att['_id']);
                  });

                  final messenger = ScaffoldMessenger.of(context);

                  try {
                    await widget.attachmentService.deleteAttachment(att['_id']);
                  } catch (e) {
                    messenger.showSnackBar(
                      SnackBar(content: Text('Failed to delete: $e')),
                    );
                  }
                },
              ),
            ),
          ),
        ],

        const SizedBox(height: 80),
      ],
    );
  }
}
