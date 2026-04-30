import 'package:flutter/material.dart';
import 'package:field_check/models/ticket_template_model.dart';
import 'package:field_check/services/template_service.dart';
import 'package:field_check/services/ticket_service.dart';
import 'package:field_check/services/offline_queue_service.dart';
import 'package:field_check/widgets/dynamic_form_renderer.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class EmployeeTicketCreateScreen extends StatefulWidget {
  const EmployeeTicketCreateScreen({super.key});

  @override
  State<EmployeeTicketCreateScreen> createState() =>
      _EmployeeTicketCreateScreenState();
}

class _EmployeeTicketCreateScreenState
    extends State<EmployeeTicketCreateScreen> {
  List<TicketTemplateModel> _templates = [];
  TicketTemplateModel? _selectedTemplate;
  Map<String, dynamic> _formData = {};
  final _notesController = TextEditingController();
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final templates = await TemplateService.getTemplates();
      if (!mounted) return;
      setState(() {
        _templates = templates;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _onTemplateSelected(TicketTemplateModel? template) {
    setState(() {
      _selectedTemplate = template;
      _formData = {};
    });
  }

  Future<void> _submit() async {
    if (_selectedTemplate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a task template')),
      );
      return;
    }

    // Client-side required field check
    final required = _selectedTemplate!.requiredFields;
    for (final field in required) {
      final val = _formData[field];
      if (val == null ||
          (val is String && val.trim().isEmpty) ||
          (val is Map && val.isEmpty)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Please fill in the required field: ${_humanize(field)}'),
          ),
        );
        return;
      }
    }

    setState(() => _submitting = true);

    try {
      // Check connectivity
      final connectivity = await Connectivity().checkConnectivity();
      final isOffline = connectivity.isEmpty ||
          connectivity.every((r) => r == ConnectivityResult.none);

      if (isOffline) {
        // Queue for later
        await OfflineQueueService().enqueueTicketCreation(
          templateId: _selectedTemplate!.id,
          data: _formData,
          notes: _notesController.text.trim().isNotEmpty
              ? _notesController.text.trim()
              : null,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('📡 Offline — ticket queued for submission'),
            backgroundColor: Colors.orange,
          ),
        );
        Navigator.pop(context, true);
        return;
      }

      await TicketService.createTicket(
        templateId: _selectedTemplate!.id,
        data: _formData,
        notes: _notesController.text.trim().isNotEmpty
            ? _notesController.text.trim()
            : null,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Ticket created successfully!'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Ticket'),
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline,
                          size: 48, color: theme.colorScheme.error),
                      const SizedBox(height: 8),
                      Text(_error!),
                      const SizedBox(height: 16),
                      ElevatedButton(
                          onPressed: _loadTemplates,
                          child: const Text('Retry')),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Step 1: Template dropdown
                      Text(
                        'Step 1: Select Task Type',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Choose the type of task to create a ticket for.',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedTemplate?.id,
                        decoration: InputDecoration(
                          labelText: 'Task Template',
                          prefixIcon: const Icon(Icons.assignment),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.15),
                        ),
                        items: _templates.map((t) {
                          return DropdownMenuItem(
                            value: t.id,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(t.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                if (t.description.isNotEmpty)
                                  Text(
                                    t.description,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme.hintColor),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: (id) {
                          final template =
                              _templates.where((t) => t.id == id).firstOrNull;
                          _onTemplateSelected(template);
                        },
                        hint: const Text('Select a task template...'),
                        isExpanded: true,
                      ),

                      // Template info
                      if (_selectedTemplate != null) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            if (_selectedTemplate!.slaFormatted != null)
                              Chip(
                                avatar: const Icon(Icons.timer, size: 16),
                                label:
                                    Text('SLA: ${_selectedTemplate!.slaFormatted}'),
                                visualDensity: VisualDensity.compact,
                              ),
                            const SizedBox(width: 8),
                            Chip(
                              avatar: const Icon(Icons.schema, size: 16),
                              label: Text(
                                  'v${_selectedTemplate!.version}'),
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                        const Divider(height: 32),

                        // Step 2: Dynamic form
                        Text(
                          'Step 2: Fill in Details',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        DynamicFormRenderer(
                          jsonSchema: _selectedTemplate!.jsonSchema,
                          initialData: _formData,
                          onChanged: (data) {
                            _formData = data;
                          },
                        ),

                        const SizedBox(height: 16),

                        // Notes field
                        TextFormField(
                          controller: _notesController,
                          maxLines: 3,
                          decoration: InputDecoration(
                            labelText: 'Additional Notes (optional)',
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)),
                            filled: true,
                            fillColor: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.15),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Submit button
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: FilledButton.icon(
                            onPressed: _submitting ? null : _submit,
                            icon: _submitting
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.send),
                            label: Text(
                                _submitting ? 'Submitting...' : 'Submit Ticket'),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ],
                  ),
                ),
    );
  }

  String _humanize(String s) => s
      .replaceAll('_', ' ')
      .split(' ')
      .map((w) =>
          w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
      .join(' ');
}
