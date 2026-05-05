import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:field_check/services/client_ticket_service.dart';

class ClientTicketForm extends StatefulWidget {
  final Function(String ticketNumber)? onSuccess;
  final Function()? onClose;

  const ClientTicketForm({
    super.key,
    this.onSuccess,
    this.onClose,
  });

  @override
  State<ClientTicketForm> createState() => _ClientTicketFormState();
}

class _ClientTicketFormState extends State<ClientTicketForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _otherServiceDetailsController = TextEditingController();

  String _selectedServiceType = 'facility_inspection';
  bool _signupForTracking = false;
  bool _isSubmitting = false;
  String? _errorMessage;
  List<PlatformFile> _selectedFiles = [];

  final List<(String label, String value)> _serviceTypeOptions = const [
    ('Facility Inspection', 'facility_inspection'),
    ('Maintenance', 'maintenance'),
    ('Equipment Check', 'equipment_check'),
    ('Cleaning', 'cleaning'),
    ('Security Audit', 'security_audit'),
    ('Aircon Cleaning', 'aircon_cleaning'),
    ('Other', 'other'),
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _descriptionController.dispose();
    _otherServiceDetailsController.dispose();
    super.dispose();
  }

  Future<void> _pickFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf', 'doc', 'docx'],
        allowMultiple: true,
      );

      if (result != null) {
        final totalSize = result.files.fold<int>(
          0,
          (sum, file) => sum + (file.size ?? 0),
        );

        // Check total size (50MB limit)
        if (totalSize > 50 * 1024 * 1024) {
          _showError('Total file size exceeds 50MB limit');
          return;
        }

        // Check individual file size (10MB each)
        for (final file in result.files) {
          if ((file.size ?? 0) > 10 * 1024 * 1024) {
            _showError('${file.name} exceeds 10MB limit');
            return;
          }
        }

        // Max 5 files
        if (_selectedFiles.length + result.files.length > 5) {
          _showError('Maximum 5 files allowed');
          return;
        }

        setState(() {
          _selectedFiles.addAll(result.files);
          _errorMessage = null;
        });
      }
    } catch (e) {
      _showError('Error picking files: $e');
    }
  }

  void _removeFile(int index) {
    setState(() {
      _selectedFiles.removeAt(index);
    });
  }

  void _showError(String message) {
    setState(() {
      _errorMessage = message;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Validate "Other" service details
    if (_selectedServiceType == 'other') {
      if (_otherServiceDetailsController.text.trim().isEmpty) {
        _showError('Please provide service details for "Other" type');
        return;
      }
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final service = ClientTicketService();

      // TODO: In production, upload files to Cloudinary/GridFS and get URLs
      // For now, pass empty attachments
      final attachments = <Map<String, String>>[];

      final response = await service.submitClientTicket(
        clientName: _nameController.text.trim(),
        clientEmail: _emailController.text.trim(),
        serviceType: _selectedServiceType,
        description: _descriptionController.text.trim(),
        otherServiceDetails: _selectedServiceType == 'other'
            ? _otherServiceDetailsController.text.trim()
            : null,
        attachments: attachments,
        signupForTracking: _signupForTracking,
      );

      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });

        if (response['success'] == true || response['ticketNumber'] != null) {
          final ticketNumber = response['ticketNumber'] ?? '';

          // Show success dialog
          if (mounted) {
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (context) {
                return AlertDialog(
                  title: const Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green),
                      SizedBox(width: 8),
                      Text('Ticket Submitted!'),
                    ],
                  ),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Your support ticket has been successfully submitted.',
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            border: Border.all(color: Colors.blue.shade200),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Ticket Number:',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                ticketNumber,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF2688d4),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Please check your email for confirmation and tracking details.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onSuccess?.call(ticketNumber);
                        widget.onClose?.call();
                      },
                      child: const Text('Close'),
                    ),
                  ],
                );
              },
            );
          }
        } else {
          _showError(response['error'] ?? response['message'] ?? 'Failed to submit ticket');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
        _showError(e.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SingleChildScrollView(
      child: Form(
        key: _formKey,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Text(
                '🎫 Submit a Support Ticket',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Let us know how we can help you',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 24),

              // Name Field
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Your Name *',
                  hintText: 'e.g., John Doe',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  prefixIcon: const Icon(Icons.person),
                ),
                validator: (value) {
                  if (value?.isEmpty ?? true) {
                    return 'Name is required';
                  }
                  if (value!.trim().length < 2) {
                    return 'Name must be at least 2 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Email Field
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'Email Address *',
                  hintText: 'e.g., john@example.com',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  prefixIcon: const Icon(Icons.email),
                ),
                validator: (value) {
                  if (value?.isEmpty ?? true) {
                    return 'Email is required';
                  }
                  final emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
                  if (!emailRegex.hasMatch(value!)) {
                    return 'Please enter a valid email address';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Service Type Dropdown
              DropdownButtonFormField<String>(
                value: _selectedServiceType,
                decoration: InputDecoration(
                  labelText: 'Service Type *',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  prefixIcon: const Icon(Icons.build),
                ),
                items: _serviceTypeOptions
                    .map((option) => DropdownMenuItem(
                          value: option.$2,
                          child: Text(option.$1),
                        ))
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedServiceType = value ?? 'facility_inspection';
                  });
                },
              ),
              const SizedBox(height: 16),

              // Other Service Details (conditional)
              if (_selectedServiceType == 'other')
                Column(
                  children: [
                    TextFormField(
                      controller: _otherServiceDetailsController,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: 'Service Details *',
                        hintText: 'Please describe the service you need',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        prefixIcon: const Icon(Icons.description),
                      ),
                      validator: (value) {
                        if (_selectedServiceType == 'other') {
                          if (value?.isEmpty ?? true) {
                            return 'Service details are required';
                          }
                          if (value!.trim().length < 5) {
                            return 'Please provide more details (min 5 characters)';
                          }
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                  ],
                ),

              // Description Field
              TextFormField(
                controller: _descriptionController,
                maxLines: 5,
                decoration: InputDecoration(
                  labelText: 'Description of Your Issue *',
                  hintText: 'Describe your problem in detail...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  prefixIcon: const Icon(Icons.notes),
                  alignLabelWithHint: true,
                ),
                validator: (value) {
                  if (value?.isEmpty ?? true) {
                    return 'Description is required';
                  }
                  if (value!.trim().length < 10) {
                    return 'Description must be at least 10 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // File Attachment Section
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Attachments (Optional)',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: _selectedFiles.length >= 5 ? null : _pickFiles,
                    icon: const Icon(Icons.attach_file),
                    label: Text(
                      _selectedFiles.isEmpty
                          ? 'Choose Files (Max 5)'
                          : 'Add More Files',
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_selectedFiles.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Selected Files (${_selectedFiles.length}/5)',
                            style: theme.textTheme.labelSmall,
                          ),
                          const SizedBox(height: 8),
                          ..._selectedFiles.asMap().entries.map((entry) {
                            final index = entry.key;
                            final file = entry.value;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                children: [
                                  const Icon(Icons.attach_file, size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          file.name,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.labelSmall,
                                        ),
                                        Text(
                                          '${(file.size ?? 0) / 1024 ~/ 1024} MB',
                                          style: theme.textTheme.labelSmall?.copyWith(
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close, size: 18),
                                    onPressed: () => _removeFile(index),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    'Supported: JPG, PNG, PDF, DOC, DOCX (Max 10MB each)',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Tracking Checkbox
              CheckboxListTile(
                value: _signupForTracking,
                onChanged: (value) {
                  setState(() {
                    _signupForTracking = value ?? false;
                  });
                },
                contentPadding: EdgeInsets.zero,
                title: const Text('Get ticket tracking updates via email'),
                subtitle: const Text(
                  'Optional: Sign up to view your ticket status online',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(height: 24),

              // Error Message
              if (_errorMessage != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade100,
                    border: Border.all(color: Colors.red),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error, color: Colors.red),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),

              // Submit Button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submitForm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2688d4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          'Submit Support Ticket',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 12),

              // Close Button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton(
                  onPressed: widget.onClose,
                  child: const Text('Cancel'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
