import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:field_check/services/client_ticket_service.dart';
import 'package:field_check/services/realtime_service.dart';
import 'package:field_check/config/api_config.dart';
import 'dart:async';
import 'dart:developer' as developer;

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
  final List<PlatformFile> _selectedFiles = [];
  
  // Retry mechanism state variables
  int _retryAttemptCount = 0;
  bool _isRetrying = false;
  Timer? _retryTimer;
  
  // Submission tracking for debugging
  String? _currentSubmissionId;
  DateTime? _submissionStartTime;

  final List<(String label, String value)> _serviceTypeOptions = const [
    ('Facility Inspection', 'facility_inspection'),
    ('Maintenance', 'maintenance'),
    ('Equipment Check', 'equipment_check'),
    ('Cleaning', 'cleaning'),
    ('Security Audit', 'security_audit'),
    ('Aircon Cleaning', 'aircon_cleaning'),
    ('Other', 'other'),
  ];

  // Structured logging helper methods
  void _logInfo(String message, {Map<String, dynamic>? context}) {
    final timestamp = DateTime.now().toIso8601String();
    developer.log('CLIENT_TICKET_FORM: $message', name: 'ClientTicketForm');
    // Use developer.log instead of print for production
    developer.log('[$timestamp] [INFO] [ClientTicketForm] ${_currentSubmissionId != null ? '[${_currentSubmissionId!}] ' : ''}$message${context != null ? ' | Context: $context' : ''}');
  }

  void _logError(String message, {dynamic error, Map<String, dynamic>? context}) {
    final timestamp = DateTime.now().toIso8601String();
    developer.log('CLIENT_TICKET_FORM ERROR: $message', name: 'ClientTicketForm', error: error);
    // Use developer.log instead of print for production
    developer.log('[$timestamp] [ERROR] [ClientTicketForm] ${_currentSubmissionId != null ? '[${_currentSubmissionId!}] ' : ''}$message${error != null ? ' | Error: $error' : ''}${context != null ? ' | Context: $context' : ''}');
  }

  void _logWarning(String message, {Map<String, dynamic>? context}) {
    final timestamp = DateTime.now().toIso8601String();
    developer.log('CLIENT_TICKET_FORM WARNING: $message', name: 'ClientTicketForm');
    // Use developer.log instead of print for production
    developer.log('[$timestamp] [WARNING] [ClientTicketForm] ${_currentSubmissionId != null ? '[${_currentSubmissionId!}] ' : ''}$message${context != null ? ' | Context: $context' : ''}');
  }

  String _generateSubmissionId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = (timestamp % 10000).toString().padLeft(4, '0');
    return 'SUB_${timestamp}_$random';
  }

  @override
  void dispose() {
    _logInfo('ClientTicketForm disposing', context: {
      'submissionId': _currentSubmissionId,
      'isSubmitting': _isSubmitting,
      'retryAttemptCount': _retryAttemptCount,
      'hasSelectedFiles': _selectedFiles.isNotEmpty,
    });
    
    _nameController.dispose();
    _emailController.dispose();
    _descriptionController.dispose();
    _otherServiceDetailsController.dispose();
    _retryTimer?.cancel();
    super.dispose();
  }

  Future<void> _pickFiles() async {
    _logInfo('File picker initiated', context: {
      'currentFileCount': _selectedFiles.length,
      'maxFilesAllowed': 5,
    });
    
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf', 'doc', 'docx'],
        allowMultiple: true,
      );

      if (result != null) {
        _logInfo('Files selected from picker', context: {
          'selectedFileCount': result.files.length,
          'fileNames': result.files.map((f) => f.name).toList(),
          'fileSizes': result.files.map((f) => f.size).toList(),
        });

        final totalSize = result.files.fold<int>(
          0,
          (sum, file) => sum + (file.size),
        );

        // Check total size (50MB limit)
        if (totalSize > 50 * 1024 * 1024) {
          _logWarning('Total file size exceeds limit', context: {
            'totalSizeBytes': totalSize,
            'limitBytes': 50 * 1024 * 1024,
            'totalSizeMB': (totalSize / (1024 * 1024)).toStringAsFixed(2),
          });
          _showError('Total file size exceeds 50MB limit');
          return;
        }

        // Check individual file size (10MB each)
        for (final file in result.files) {
          if (file.size > 10 * 1024 * 1024) {
            _logWarning('Individual file size exceeds limit', context: {
              'fileName': file.name,
              'fileSizeBytes': file.size,
              'limitBytes': 10 * 1024 * 1024,
              'fileSizeMB': (file.size / (1024 * 1024)).toStringAsFixed(2),
            });
            _showError('${file.name} exceeds 10MB limit');
            return;
          }
        }

        // Max 5 files
        if (_selectedFiles.length + result.files.length > 5) {
          _logWarning('Maximum file count would be exceeded', context: {
            'currentFileCount': _selectedFiles.length,
            'newFileCount': result.files.length,
            'totalWouldBe': _selectedFiles.length + result.files.length,
            'maxAllowed': 5,
          });
          _showError('Maximum 5 files allowed');
          return;
        }

        setState(() {
          _selectedFiles.addAll(result.files);
          _errorMessage = null;
        });

        _logInfo('Files successfully added', context: {
          'totalFileCount': _selectedFiles.length,
          'newlyAddedCount': result.files.length,
          'totalSizeBytes': _selectedFiles.fold<int>(0, (sum, file) => sum + file.size),
        });
      } else {
        _logInfo('File picker cancelled by user');
      }
    } catch (e) {
      _logError('Error during file picking', error: e, context: {
        'currentFileCount': _selectedFiles.length,
      });
      _showError('Error picking files: $e');
    }
  }

  void _removeFile(int index) {
    if (index >= 0 && index < _selectedFiles.length) {
      final removedFile = _selectedFiles[index];
      _logInfo('File removed from selection', context: {
        'fileName': removedFile.name,
        'fileSize': removedFile.size,
        'removedIndex': index,
        'remainingFileCount': _selectedFiles.length - 1,
      });
      
      setState(() {
        _selectedFiles.removeAt(index);
      });
    } else {
      _logWarning('Attempted to remove file at invalid index', context: {
        'requestedIndex': index,
        'currentFileCount': _selectedFiles.length,
      });
    }
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

  void _handleSubmissionError(dynamic error) {
    _logError('Handling submission error', error: error, context: {
      'errorType': error.runtimeType.toString(),
      'retryAttemptCount': _retryAttemptCount,
      'submissionDuration': _submissionStartTime != null 
          ? DateTime.now().difference(_submissionStartTime!).inMilliseconds 
          : null,
    });

    // Classify error type and provide appropriate handling
    if (error is TimeoutException) {
      _logWarning('Timeout exception detected', context: {
        'errorMessage': error.message ?? 'No message',
        'duration': error.duration?.inMilliseconds,
      });
      _showTimeoutError();
    } else if (error.toString().contains('Request timeout') || 
               error.toString().contains('connection') ||
               error.toString().contains('network')) {
      _logWarning('Network error detected', context: {
        'errorString': error.toString(),
        'errorType': 'network',
      });
      _showNetworkError();
    } else if (error.toString().contains('Invalid') || 
               error.toString().contains('must be') ||
               error.toString().contains('required')) {
      _logWarning('Validation error detected', context: {
        'errorString': error.toString(),
        'errorType': 'validation',
      });
      _showValidationError(error.toString());
    } else if (error.toString().contains('Status:') ||
               error.toString().contains('Failed to submit') ||
               error.toString().contains('server')) {
      _logWarning('Server error detected', context: {
        'errorString': error.toString(),
        'errorType': 'server',
      });
      _showServerError(error.toString());
    } else {
      // Generic error fallback
      _logWarning('Generic error detected', context: {
        'errorString': error.toString(),
        'errorType': 'generic',
      });
      _showGenericError(error.toString());
    }
  }

  void _showTimeoutError() {
    _logWarning('Showing timeout error dialog', context: {
      'retryAttemptCount': _retryAttemptCount,
      'submissionId': _currentSubmissionId,
    });
    _showRetryDialog(
      'Request timed out. Please check your internet connection and try again.',
    );
  }

  void _showNetworkError() {
    _logWarning('Showing network error dialog', context: {
      'retryAttemptCount': _retryAttemptCount,
      'submissionId': _currentSubmissionId,
    });
    _showRetryDialog(
      'Network connection issue. Please check your internet and try again.',
    );
  }

  void _showValidationError(String message) {
    _logWarning('Showing validation error', context: {
      'errorMessage': message,
      'retryAttemptCount': _retryAttemptCount,
      'submissionId': _currentSubmissionId,
    });
    
    // Validation errors should use red color as they indicate user input issues
    setState(() {
      _errorMessage = message;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(message),
              ),
            ],
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  void _showServerError(String message) {
    _logWarning('Showing server error dialog', context: {
      'errorMessage': message,
      'retryAttemptCount': _retryAttemptCount,
      'submissionId': _currentSubmissionId,
    });
    _showRetryDialog(
      'Server error occurred. Please try again or contact support if the issue persists.',
    );
  }

  void _showGenericError(String message) {
    _logWarning('Showing generic error dialog', context: {
      'errorMessage': message,
      'retryAttemptCount': _retryAttemptCount,
      'submissionId': _currentSubmissionId,
    });
    // Generic errors use retry dialog
    _showRetryDialog(
      'An error occurred: ${message.length > 100 ? '${message.substring(0, 100)}...' : message}',
    );
  }

  // Retry mechanism methods
  void _retrySubmission() {
    if (_retryAttemptCount >= 3) {
      _logWarning('Maximum retry attempts reached', context: {
        'maxRetries': 3,
        'currentAttempt': _retryAttemptCount,
      });
      _showMaxRetriesReached();
      return;
    }

    _retryAttemptCount++;
    
    // Calculate exponential backoff delay: 1s, 2s, 4s
    final delaySeconds = [1, 2, 4][_retryAttemptCount - 1];
    
    _logInfo('Initiating retry attempt', context: {
      'retryAttempt': _retryAttemptCount,
      'maxRetries': 3,
      'delaySeconds': delaySeconds,
      'backoffStrategy': 'exponential',
    });
    
    setState(() {
      _isRetrying = true;
      _errorMessage = null;
    });

    _retryTimer = Timer(Duration(seconds: delaySeconds), () {
      if (mounted) {
        _logInfo('Retry delay completed, starting submission', context: {
          'retryAttempt': _retryAttemptCount,
          'delaySeconds': delaySeconds,
        });
        setState(() {
          _isRetrying = false;
        });
        _submitForm();
      } else {
        _logWarning('Widget unmounted during retry delay', context: {
          'retryAttempt': _retryAttemptCount,
        });
      }
    });
  }

  void _showMaxRetriesReached() {
    _logError('Maximum retry attempts reached', context: {
      'maxRetries': 3,
      'retryAttemptCount': _retryAttemptCount,
      'submissionId': _currentSubmissionId,
      'totalSubmissionTime': _submissionStartTime != null 
          ? DateTime.now().difference(_submissionStartTime!).inMilliseconds 
          : null,
    });
    
    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.error_outline, color: Colors.red),
              SizedBox(width: 8),
              Text('Maximum Retries Reached'),
            ],
          ),
          content: const Text(
            'We\'ve tried submitting your ticket 3 times but encountered errors. '
            'Please check your internet connection and try again later, or contact support if the issue persists.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                _logInfo('Max retries dialog - try again later selected', context: {
                  'submissionId': _currentSubmissionId,
                });
                Navigator.pop(context);
                _resetRetryState();
              },
              child: const Text('Try Again Later'),
            ),
            TextButton(
              onPressed: () {
                _logInfo('Max retries dialog - retry now selected', context: {
                  'submissionId': _currentSubmissionId,
                });
                Navigator.pop(context);
                _resetRetryState();
                _submitForm();
              },
              child: const Text('Retry Now'),
            ),
          ],
        ),
      );
    }
  }

  void _resetRetryState() {
    _logInfo('Resetting retry state', context: {
      'previousRetryCount': _retryAttemptCount,
      'wasRetrying': _isRetrying,
      'hadError': _errorMessage != null,
    });
    
    setState(() {
      _retryAttemptCount = 0;
      _isRetrying = false;
      _errorMessage = null;
    });
    _retryTimer?.cancel();
  }

  void _showRetryDialog(String errorMessage, {bool isSocketIOError = false}) {
    _logWarning('Displaying retry dialog', context: {
      'errorMessage': errorMessage,
      'isSocketIOError': isSocketIOError,
      'retryAttemptCount': _retryAttemptCount,
      'maxRetries': 3,
      'submissionId': _currentSubmissionId,
    });
    
    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(
                isSocketIOError ? Icons.wifi_off : Icons.error_outline,
                color: isSocketIOError ? Colors.orange : Colors.red,
              ),
              const SizedBox(width: 8),
              const Text('Submission Failed'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(errorMessage),
              const SizedBox(height: 16),
              if (_retryAttemptCount > 0)
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Retry attempt: $_retryAttemptCount/3',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                _logInfo('Retry dialog cancelled by user', context: {
                  'retryAttemptCount': _retryAttemptCount,
                  'submissionId': _currentSubmissionId,
                });
                Navigator.pop(context);
                _resetRetryState();
              },
              child: const Text('Cancel'),
            ),
            if (_retryAttemptCount < 3)
              ElevatedButton(
                onPressed: () {
                  _logInfo('Retry initiated by user', context: {
                    'retryAttemptCount': _retryAttemptCount,
                    'submissionId': _currentSubmissionId,
                  });
                  Navigator.pop(context);
                  _retrySubmission();
                },
                child: Text(
                  _retryAttemptCount == 0 ? 'Retry' : 'Retry ($_retryAttemptCount/3)',
                ),
              ),
          ],
        ),
      );
    }
  }

  void _handleResponseError(String errorMessage, Map<String, dynamic> response) {
    _logError('Handling response error', context: {
      'errorMessage': errorMessage,
      'response': response,
      'retryAttemptCount': _retryAttemptCount,
      'submissionId': _currentSubmissionId,
    });

    // Classify response errors based on content and provide appropriate handling
    if (errorMessage.contains('Invalid') || 
        errorMessage.contains('must be') ||
        errorMessage.contains('required') ||
        errorMessage.contains('format')) {
      _logWarning('Response validation error detected', context: {
        'errorMessage': errorMessage,
        'errorType': 'validation',
        'response': response,
      });
      _showValidationError(errorMessage);
    } else if (errorMessage.contains('timeout') || 
               errorMessage.contains('connection') ||
               errorMessage.contains('network')) {
      _logWarning('Response network error detected', context: {
        'errorMessage': errorMessage,
        'errorType': 'network',
        'response': response,
      });
      _showNetworkError();
    } else if (errorMessage.contains('server') ||
               errorMessage.contains('internal') ||
               response.containsKey('statusCode')) {
      _logWarning('Response server error detected', context: {
        'errorMessage': errorMessage,
        'errorType': 'server',
        'statusCode': response['statusCode'],
        'response': response,
      });
      _showServerError(errorMessage);
    } else {
      // For other response errors, show retry dialog
      _logWarning('Response generic error detected', context: {
        'errorMessage': errorMessage,
        'errorType': 'generic',
        'response': response,
      });
      _showRetryDialog(
        'Unable to submit ticket: $errorMessage. Please try again.',
      );
    }
  }

  Future<void> _submitForm() async {
    // Generate unique submission ID for tracking
    _currentSubmissionId = _generateSubmissionId();
    _submissionStartTime = DateTime.now();
    
    _logInfo('Form submission initiated', context: {
      'submissionId': _currentSubmissionId,
      'retryAttempt': _retryAttemptCount,
      'isRetry': _retryAttemptCount > 0,
      'formData': {
        'serviceType': _selectedServiceType,
        'hasOtherDetails': _selectedServiceType == 'other' && _otherServiceDetailsController.text.trim().isNotEmpty,
        'signupForTracking': _signupForTracking,
        'attachmentCount': _selectedFiles.length,
        'nameLength': _nameController.text.trim().length,
        'emailLength': _emailController.text.trim().length,
        'descriptionLength': _descriptionController.text.trim().length,
      },
    });

    // Form validation logging
    _logInfo('Starting form validation');
    if (!_formKey.currentState!.validate()) {
      _logWarning('Form validation failed', context: {
        'submissionId': _currentSubmissionId,
      });
      return;
    }
    _logInfo('Form validation passed');

    // Validate "Other" service details
    if (_selectedServiceType == 'other') {
      _logInfo('Validating "Other" service details');
      if (_otherServiceDetailsController.text.trim().isEmpty) {
        _logWarning('Other service details validation failed', context: {
          'serviceType': _selectedServiceType,
          'detailsLength': _otherServiceDetailsController.text.trim().length,
        });
        _showError('Please provide service details for "Other" type');
        return;
      }
      _logInfo('Other service details validation passed');
    }

    // Optional warning logging for Socket.IO status (non-blocking)
    final realtimeService = RealtimeService();
    if (!realtimeService.isConnected) {
      _logWarning('Socket.IO disconnected during submission attempt', context: {
        'submissionId': _currentSubmissionId,
        'note': 'HTTP submission will proceed independently',
      });
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    _logInfo('Form submission state updated', context: {
      'isSubmitting': true,
      'errorMessage': null,
    });

    try {
      _logInfo('Initializing ClientTicketService');
      final service = ClientTicketService();

      // TODO: In production, upload files to Cloudinary/GridFS and get URLs
      // For now, pass empty attachments
      final attachments = <Map<String, String>>[];
      
      _logInfo('Preparing submission data', context: {
        'attachmentCount': attachments.length,
        'clientName': _nameController.text.trim().isNotEmpty ? 'provided' : 'empty',
        'clientEmail': _emailController.text.trim().isNotEmpty ? 'provided' : 'empty',
        'serviceType': _selectedServiceType,
        'hasDescription': _descriptionController.text.trim().isNotEmpty,
        'hasOtherDetails': _selectedServiceType == 'other' ? _otherServiceDetailsController.text.trim().isNotEmpty : null,
        'signupForTracking': _signupForTracking,
        'apiBaseUrl': ApiConfig.baseUrl,
        'ticketEndpoint': '${ApiConfig.baseUrl}/api/client-tickets',
      });

      _logInfo('Calling ClientTicketService.submitClientTicket');
      final httpRequestStartTime = DateTime.now();
      
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

      final httpRequestDuration = DateTime.now().difference(httpRequestStartTime);
      final totalSubmissionDuration = DateTime.now().difference(_submissionStartTime!);

      _logInfo('HTTP request completed', context: {
        'httpDurationMs': httpRequestDuration.inMilliseconds,
        'totalDurationMs': totalSubmissionDuration.inMilliseconds,
        'responseReceived': true,
        'responseKeys': response.keys.toList(),
        'responseStatusCode': response['statusCode'],
        'responseErrorType': response['errorType'],
      });

      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });

        _logInfo('Form submission state reset', context: {
          'isSubmitting': false,
        });

        if (response['success'] == true || response['ticketNumber'] != null) {
          final ticketNumber = response['ticketNumber'] ?? '';

          _logInfo('Ticket submission successful', context: {
            'ticketNumber': ticketNumber,
            'success': response['success'],
            'totalDurationMs': totalSubmissionDuration.inMilliseconds,
            'retryAttempt': _retryAttemptCount,
          });

          // Reset retry state on successful submission
          _resetRetryState();

          // Show success dialog
          if (mounted) {
            _logInfo('Displaying success dialog', context: {
              'ticketNumber': ticketNumber,
            });
            
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
                        _logInfo('Success dialog closed by user', context: {
                          'ticketNumber': ticketNumber,
                        });
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
          // Handle response errors with proper classification
          final errorMessage = response['error'] ?? response['message'] ?? 'Failed to submit ticket';
          
          _logError('Ticket submission failed with response error', context: {
            'errorMessage': errorMessage,
            'response': response,
            'responseStatusCode': response['statusCode'],
            'responseErrorType': response['errorType'],
            'responseDetails': response['details'],
            'totalDurationMs': totalSubmissionDuration.inMilliseconds,
            'retryAttempt': _retryAttemptCount,
          });
          
          _handleResponseError(errorMessage, response);
        }
      }
    } catch (e) {
      final totalSubmissionDuration = _submissionStartTime != null 
          ? DateTime.now().difference(_submissionStartTime!) 
          : null;
          
      _logError('Exception during ticket submission', error: e, context: {
        'submissionId': _currentSubmissionId,
        'totalDurationMs': totalSubmissionDuration?.inMilliseconds,
        'retryAttempt': _retryAttemptCount,
        'exceptionType': e.runtimeType.toString(),
      });
      
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
        _handleSubmissionError(e);
      }
    } finally {
      // Clear submission tracking
      final finalDuration = _submissionStartTime != null 
          ? DateTime.now().difference(_submissionStartTime!) 
          : null;
          
      _logInfo('Submission process completed', context: {
        'submissionId': _currentSubmissionId,
        'totalDurationMs': finalDuration?.inMilliseconds,
        'retryAttempt': _retryAttemptCount,
        'finalState': _isSubmitting ? 'submitting' : 'idle',
      });
      
      // Keep submission ID for potential retry tracking
      if (_retryAttemptCount == 0) {
        _currentSubmissionId = null;
        _submissionStartTime = null;
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
                initialValue: _selectedServiceType,
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
                                          '${file.size / 1024 ~/ 1024} MB',
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
                          }),
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
                  onPressed: (_isSubmitting || _isRetrying) ? null : _submitForm,
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
                      : _isRetrying
                          ? Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor:
                                        AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Retrying... ($_retryAttemptCount/3)',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
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
