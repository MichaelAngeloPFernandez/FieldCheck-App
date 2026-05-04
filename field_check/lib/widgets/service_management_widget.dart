import 'package:flutter/material.dart';
import 'package:field_check/models/service_model.dart';
import 'package:field_check/models/task_template_model.dart';
import 'package:field_check/models/task_model.dart';
import 'package:field_check/services/service_service.dart';
import 'package:field_check/services/task_template_service.dart';
import 'package:field_check/widgets/app_widgets.dart';

class ServiceManagementWidget extends StatefulWidget {
  const ServiceManagementWidget({super.key});

  @override
  State<ServiceManagementWidget> createState() =>
      _ServiceManagementWidgetState();
}

class _ServiceManagementWidgetState extends State<ServiceManagementWidget> {
  final ServiceService _serviceService = ServiceService();
  final TaskTemplateService _templateService = TaskTemplateService();

  List<Service> _services = [];
  Map<String, List<TaskTemplate>> _templatesByService = {};
  bool _isLoading = true;
  String _searchQuery = '';
  String _sortBy = 'name'; // 'name' or 'createdAt'
  final Set<String> _expandedServices = {};

  @override
  void initState() {
    super.initState();
    _loadServices();
  }

  Future<void> _loadServices() async {
    try {
      setState(() => _isLoading = true);
      final services = await _serviceService.getServices();

      // Load templates for each service
      final templatesByService = <String, List<TaskTemplate>>{};
      for (final service in services) {
        try {
          final templates = await _templateService.getTemplatesForService(
            service.id,
          );
          templatesByService[service.id] = templates;
        } catch (e) {
          debugPrint('Error loading templates for service ${service.id}: $e');
          templatesByService[service.id] = [];
        }
      }

      if (mounted) {
        setState(() {
          _services = services;
          _templatesByService = templatesByService;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading services: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        AppWidgets.showErrorSnackbar(
          context,
          AppWidgets.friendlyErrorMessage(
            e,
            fallback: 'Failed to load services',
          ),
        );
      }
    }
  }

  List<Service> _getFilteredAndSortedServices() {
    var filtered = _services.where((s) {
      if (_searchQuery.isEmpty) return true;
      return s.name.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    filtered.sort((a, b) {
      switch (_sortBy) {
        case 'createdAt':
          return b.createdAt.compareTo(a.createdAt);
        case 'name':
        default:
          return a.name.compareTo(b.name);
      }
    });

    return filtered;
  }

  Future<void> _createService() async {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    String? error;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Create Service'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (error != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Text(
                      error!,
                      style: TextStyle(color: Colors.red.shade800),
                    ),
                  ),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Service Name *',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) {
                    if (error != null) {
                      setDialogState(() => error = null);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) {
                  setDialogState(() => error = 'Service name is required');
                  return;
                }

                try {
                  await _serviceService.createService(
                    name: name,
                    description: descriptionController.text.trim(),
                  );
                  if (ctx.mounted) {
                    Navigator.of(ctx).pop(true);
                  }
                } catch (e) {
                  setDialogState(() => error = 'Failed to create service: $e');
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      _loadServices();
      if (mounted) {
        AppWidgets.showSuccessSnackbar(context, 'Service created successfully');
      }
    }
  }

  Future<void> _editService(Service service) async {
    final nameController = TextEditingController(text: service.name);
    final descriptionController = TextEditingController(
      text: service.description ?? '',
    );
    String? error;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Edit Service'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (error != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Text(
                      error!,
                      style: TextStyle(color: Colors.red.shade800),
                    ),
                  ),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Service Name *',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) {
                    if (error != null) {
                      setDialogState(() => error = null);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) {
                  setDialogState(() => error = 'Service name is required');
                  return;
                }

                try {
                  await _serviceService.updateService(
                    serviceId: service.id,
                    name: name,
                    description: descriptionController.text.trim(),
                  );
                  if (ctx.mounted) {
                    Navigator.of(ctx).pop(true);
                  }
                } catch (e) {
                  setDialogState(() => error = 'Failed to update service: $e');
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      _loadServices();
      if (mounted) {
        AppWidgets.showSuccessSnackbar(context, 'Service updated successfully');
      }
    }
  }

  Future<void> _deleteService(Service service) async {
    final templates = _templatesByService[service.id] ?? [];
    final hasTemplates = templates.isNotEmpty;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Service'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to delete "${service.name}"?'),
            if (hasTemplates) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Warning: This service has ${templates.length} template(s)',
                      style: TextStyle(
                        color: Colors.orange.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'All associated templates will also be deleted.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (result == true) {
      try {
        await _serviceService.deleteService(service.id);
        _loadServices();
        if (mounted) {
          AppWidgets.showSuccessSnackbar(
            context,
            'Service deleted successfully',
          );
        }
      } catch (e) {
        if (mounted) {
          AppWidgets.showErrorSnackbar(
            context,
            AppWidgets.friendlyErrorMessage(
              e,
              fallback: 'Failed to delete service',
            ),
          );
        }
      }
    }
  }

  Widget _buildChecklistBuilder(
    List<TaskChecklistItem> checklist,
    StateSetter setDialogState,
  ) {
    final itemController = TextEditingController();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Row(
          children: [
            const Icon(Icons.checklist, size: 18),
            const SizedBox(width: 6),
            Text(
              'Checklist (${checklist.length} items)',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: itemController,
                decoration: const InputDecoration(
                  hintText: 'Add checklist item...',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  isDense: true,
                ),
                onSubmitted: (value) {
                  if (value.trim().isNotEmpty) {
                    setDialogState(() {
                      checklist.add(TaskChecklistItem(label: value.trim()));
                    });
                    itemController.clear();
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: () {
                if (itemController.text.trim().isNotEmpty) {
                  setDialogState(() {
                    checklist.add(
                      TaskChecklistItem(label: itemController.text.trim()),
                    );
                  });
                  itemController.clear();
                }
              },
              icon: const Icon(Icons.add_circle, color: Color(0xFF2688d4)),
              tooltip: 'Add item',
            ),
          ],
        ),
        if (checklist.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...checklist.asMap().entries.map((entry) {
            final idx = entry.key;
            final item = entry.value;
            return Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.drag_indicator,
                    size: 16,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      item.label,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  InkWell(
                    onTap: () {
                      setDialogState(() => checklist.removeAt(idx));
                    },
                    child: Icon(
                      Icons.close,
                      size: 16,
                      color: Colors.red.shade400,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ],
    );
  }

  Future<void> _createTemplate(Service service) async {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    String taskType = 'general';
    String difficulty = 'medium';
    List<TaskChecklistItem> checklist = [];
    String? error;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Create Template'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (error != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Text(
                        error!,
                        style: TextStyle(color: Colors.red.shade800),
                      ),
                    ),
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: 'Template Title *',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) {
                      if (error != null) {
                        setDialogState(() => error = null);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: taskType,
                    decoration: const InputDecoration(
                      labelText: 'Task Type',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'general',
                        child: Text('General'),
                      ),
                      DropdownMenuItem(
                        value: 'inspection',
                        child: Text('Inspection'),
                      ),
                      DropdownMenuItem(
                        value: 'maintenance',
                        child: Text('Maintenance'),
                      ),
                      DropdownMenuItem(
                        value: 'delivery',
                        child: Text('Delivery'),
                      ),
                      DropdownMenuItem(value: 'other', child: Text('Other')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => taskType = value);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: difficulty,
                    decoration: const InputDecoration(
                      labelText: 'Difficulty',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'easy', child: Text('Easy')),
                      DropdownMenuItem(value: 'medium', child: Text('Medium')),
                      DropdownMenuItem(value: 'hard', child: Text('Hard')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => difficulty = value);
                      }
                    },
                  ),
                  _buildChecklistBuilder(checklist, setDialogState),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final title = titleController.text.trim();
                if (title.isEmpty) {
                  setDialogState(() => error = 'Template title is required');
                  return;
                }

                try {
                  await _templateService.createTemplate(
                    serviceId: service.id,
                    title: title,
                    description: descriptionController.text.trim(),
                    type: taskType,
                    difficulty: difficulty,
                    checklist: checklist,
                  );
                  if (ctx.mounted) {
                    Navigator.of(ctx).pop(true);
                  }
                } catch (e) {
                  setDialogState(() => error = 'Failed to create template: $e');
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      _loadServices();
      if (mounted) {
        AppWidgets.showSuccessSnackbar(
          context,
          'Template created successfully',
        );
      }
    }
  }

  Future<void> _deleteTemplate(TaskTemplate template) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Template'),
        content: Text('Are you sure you want to delete "${template.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (result == true) {
      try {
        await _templateService.deleteTemplate(template.id);
        _loadServices();
        if (mounted) {
          AppWidgets.showSuccessSnackbar(
            context,
            'Template deleted successfully',
          );
        }
      } catch (e) {
        if (mounted) {
          AppWidgets.showErrorSnackbar(
            context,
            AppWidgets.friendlyErrorMessage(
              e,
              fallback: 'Failed to delete template',
            ),
          );
        }
      }
    }
  }

  Future<void> _editTemplate(TaskTemplate template) async {
    final titleController = TextEditingController(text: template.title);
    final descriptionController = TextEditingController(
      text: template.description ?? '',
    );
    String taskType = template.type;
    String difficulty = template.difficulty;
    List<TaskChecklistItem> checklist = List.from(template.checklist);
    String? error;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Edit Template'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (error != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Text(
                        error!,
                        style: TextStyle(color: Colors.red.shade800),
                      ),
                    ),
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: 'Template Title *',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) {
                      if (error != null) setDialogState(() => error = null);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: taskType,
                    decoration: const InputDecoration(
                      labelText: 'Task Type',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'general',
                        child: Text('General'),
                      ),
                      DropdownMenuItem(
                        value: 'inspection',
                        child: Text('Inspection'),
                      ),
                      DropdownMenuItem(
                        value: 'maintenance',
                        child: Text('Maintenance'),
                      ),
                      DropdownMenuItem(
                        value: 'delivery',
                        child: Text('Delivery'),
                      ),
                      DropdownMenuItem(value: 'other', child: Text('Other')),
                    ],
                    onChanged: (value) {
                      if (value != null) setDialogState(() => taskType = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: difficulty,
                    decoration: const InputDecoration(
                      labelText: 'Difficulty',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'easy', child: Text('Easy')),
                      DropdownMenuItem(value: 'medium', child: Text('Medium')),
                      DropdownMenuItem(value: 'hard', child: Text('Hard')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => difficulty = value);
                      }
                    },
                  ),
                  _buildChecklistBuilder(checklist, setDialogState),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final title = titleController.text.trim();
                if (title.isEmpty) {
                  setDialogState(() => error = 'Template title is required');
                  return;
                }
                try {
                  await _templateService.updateTemplate(
                    templateId: template.id,
                    title: title,
                    description: descriptionController.text.trim(),
                    type: taskType,
                    difficulty: difficulty,
                    checklist: checklist,
                  );
                  if (ctx.mounted) Navigator.of(ctx).pop(true);
                } catch (e) {
                  setDialogState(() => error = 'Failed to update template: $e');
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      _loadServices();
      if (mounted) {
        AppWidgets.showSuccessSnackbar(
          context,
          'Template updated successfully',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final filteredServices = _getFilteredAndSortedServices();

    return Column(
      children: [
        // Header with search and actions
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'Search services...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onChanged: (value) {
                        setState(() => _searchQuery = value);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      setState(() => _sortBy = value);
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'name',
                        child: Text('Sort by Name'),
                      ),
                      const PopupMenuItem(
                        value: 'createdAt',
                        child: Text('Sort by Date'),
                      ),
                    ],
                    child: OutlinedButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.sort),
                      label: const Text('Sort'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _createService,
                    icon: const Icon(Icons.add),
                    label: const Text('New Service'),
                  ),
                ],
              ),
            ],
          ),
        ),
        // Services list
        Expanded(
          child: filteredServices.isEmpty
              ? Center(
                  child: Text(
                    _searchQuery.isEmpty
                        ? 'No services yet. Create one to get started.'
                        : 'No services match your search.',
                  ),
                )
              : ListView.builder(
                  itemCount: filteredServices.length,
                  itemBuilder: (context, index) {
                    final service = filteredServices[index];
                    final templates = _templatesByService[service.id] ?? [];
                    final isExpanded = _expandedServices.contains(service.id);

                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Column(
                        children: [
                          ListTile(
                            title: Text(service.name),
                            subtitle: service.description != null
                                ? Text(service.description!)
                                : null,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Chip(
                                  label: Text('${templates.length} templates'),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: Icon(
                                    isExpanded
                                        ? Icons.expand_less
                                        : Icons.expand_more,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      if (isExpanded) {
                                        _expandedServices.remove(service.id);
                                      } else {
                                        _expandedServices.add(service.id);
                                      }
                                    });
                                  },
                                ),
                                PopupMenuButton<String>(
                                  onSelected: (value) {
                                    switch (value) {
                                      case 'edit':
                                        _editService(service);
                                        break;
                                      case 'delete':
                                        _deleteService(service);
                                        break;
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    const PopupMenuItem(
                                      value: 'edit',
                                      child: Text('Edit'),
                                    ),
                                    const PopupMenuItem(
                                      value: 'delete',
                                      child: Text('Delete'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          if (isExpanded) ...[
                            const Divider(height: 1),
                            Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text(
                                        'Templates',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                      ),
                                      FilledButton.icon(
                                        onPressed: () =>
                                            _createTemplate(service),
                                        icon: const Icon(Icons.add, size: 18),
                                        label: const Text('Add Template'),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  if (templates.isEmpty)
                                    const Text(
                                      'No templates yet. Create one to define tasks for this service.',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    )
                                  else
                                    Column(
                                      children: templates.map((template) {
                                        return Container(
                                          margin: const EdgeInsets.only(
                                            bottom: 8,
                                          ),
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade50,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            border: Border.all(
                                              color: Colors.grey.shade200,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      template.title,
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                    if (template.description !=
                                                        null) ...[
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        template.description!,
                                                        style: const TextStyle(
                                                          fontSize: 12,
                                                          color: Colors.grey,
                                                        ),
                                                      ),
                                                    ],
                                                    const SizedBox(height: 8),
                                                    Row(
                                                      children: [
                                                        Chip(
                                                          label: Text(
                                                            template.type,
                                                          ),
                                                          visualDensity:
                                                              VisualDensity
                                                                  .compact,
                                                        ),
                                                        const SizedBox(
                                                          width: 8,
                                                        ),
                                                        Chip(
                                                          label: Text(
                                                            template.difficulty,
                                                          ),
                                                          visualDensity:
                                                              VisualDensity
                                                                  .compact,
                                                        ),
                                                        if (template
                                                            .checklist
                                                            .isNotEmpty) ...[
                                                          const SizedBox(
                                                            width: 8,
                                                          ),
                                                          Chip(
                                                            label: Text(
                                                              '${template.checklist.length} items',
                                                            ),
                                                            visualDensity:
                                                                VisualDensity
                                                                    .compact,
                                                          ),
                                                        ],
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              PopupMenuButton<String>(
                                                onSelected: (value) {
                                                  if (value == 'edit') {
                                                    _editTemplate(template);
                                                  } else if (value ==
                                                      'delete') {
                                                    _deleteTemplate(template);
                                                  }
                                                },
                                                itemBuilder: (context) => [
                                                  const PopupMenuItem(
                                                    value: 'edit',
                                                    child: Text('Edit'),
                                                  ),
                                                  const PopupMenuItem(
                                                    value: 'delete',
                                                    child: Text('Delete'),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
