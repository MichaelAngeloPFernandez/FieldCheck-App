class ValidationService {
  static final ValidationService _instance = ValidationService._internal();

  factory ValidationService() {
    return _instance;
  }

  ValidationService._internal();

  // Constants for validation limits
  static const int maxTasksPerEmployee = 20;
  static const int maxGeofencesPerEmployee = 10;
  static const int maxFileUploadSizeMB = 50;
  static const int maxBatchSize = 100;
  static const int maxMessageLength = 320;
  static const int maxReportSize = 10 * 1024 * 1024; // 10MB
  static const int maxLogEntries = 10000;
  static const Duration maxTaskDuration = Duration(days: 365);

  /// Validate task creation
  ValidationResult validateTaskCreation({
    required String title,
    required String description,
    required int currentTaskCount,
    required DateTime dueDate,
    String? type,
    String? difficulty,
  }) {
    // Check title
    if (title.isEmpty || title.length > 200) {
      return ValidationResult(
        isValid: false,
        message: 'Task title must be between 1 and 200 characters',
      );
    }

    // Check description
    if (description.isEmpty || description.length > 2000) {
      return ValidationResult(
        isValid: false,
        message: 'Task description must be between 1 and 2000 characters',
      );
    }

    // Check task limit
    if (currentTaskCount >= maxTasksPerEmployee) {
      return ValidationResult(
        isValid: false,
        message:
            'Employee has reached maximum task limit ($maxTasksPerEmployee)',
      );
    }

    // Check due date
    final now = DateTime.now();
    if (dueDate.isBefore(now)) {
      return ValidationResult(
        isValid: false,
        message: 'Due date cannot be in the past',
      );
    }

    if (dueDate.difference(now) > maxTaskDuration) {
      return ValidationResult(
        isValid: false,
        message: 'Due date cannot be more than 1 year in the future',
      );
    }

    // Validate type if provided
    if (type != null && !_isValidTaskType(type)) {
      return ValidationResult(
        isValid: false,
        message: 'Invalid task type: $type',
      );
    }

    // Validate difficulty if provided
    if (difficulty != null && !_isValidDifficulty(difficulty)) {
      return ValidationResult(
        isValid: false,
        message: 'Invalid difficulty level: $difficulty',
      );
    }

    return ValidationResult(isValid: true);
  }

  /// Validate file upload
  ValidationResult validateFileUpload({
    required String fileName,
    required int fileSizeBytes,
    required String fileType,
  }) {
    // Check file name
    if (fileName.isEmpty || fileName.length > 255) {
      return ValidationResult(
        isValid: false,
        message: 'File name must be between 1 and 255 characters',
      );
    }

    // Check file size
    final fileSizeMB = fileSizeBytes / (1024 * 1024);
    if (fileSizeMB > maxFileUploadSizeMB) {
      return ValidationResult(
        isValid: false,
        message: 'File size exceeds maximum limit ($maxFileUploadSizeMB MB)',
      );
    }

    // Check file type
    if (!_isValidFileType(fileType)) {
      return ValidationResult(
        isValid: false,
        message: 'File type not allowed: $fileType',
      );
    }

    return ValidationResult(isValid: true);
  }

  /// Validate SMS message
  ValidationResult validateSmsMessage(String message) {
    if (message.isEmpty) {
      return ValidationResult(
        isValid: false,
        message: 'Message cannot be empty',
      );
    }

    if (message.length > maxMessageLength) {
      return ValidationResult(
        isValid: false,
        message:
            'Message exceeds maximum length ($maxMessageLength characters)',
      );
    }

    return ValidationResult(isValid: true);
  }

  /// Validate batch operation
  ValidationResult validateBatchOperation({
    required List<String> ids,
    required String operationType,
  }) {
    if (ids.isEmpty) {
      return ValidationResult(
        isValid: false,
        message: 'Batch operation requires at least one item',
      );
    }

    if (ids.length > maxBatchSize) {
      return ValidationResult(
        isValid: false,
        message: 'Batch size exceeds maximum limit ($maxBatchSize items)',
      );
    }

    // Check for duplicates
    if (ids.length != ids.toSet().length) {
      return ValidationResult(
        isValid: false,
        message: 'Batch contains duplicate items',
      );
    }

    return ValidationResult(isValid: true);
  }

  /// Validate geofence assignment
  ValidationResult validateGeofenceAssignment({
    required int currentGeofenceCount,
    required double latitude,
    required double longitude,
    required double radius,
  }) {
    // Check geofence limit
    if (currentGeofenceCount >= maxGeofencesPerEmployee) {
      return ValidationResult(
        isValid: false,
        message:
            'Employee has reached maximum geofence limit ($maxGeofencesPerEmployee)',
      );
    }

    // Validate coordinates
    if (latitude < -90 || latitude > 90) {
      return ValidationResult(
        isValid: false,
        message: 'Invalid latitude: $latitude',
      );
    }

    if (longitude < -180 || longitude > 180) {
      return ValidationResult(
        isValid: false,
        message: 'Invalid longitude: $longitude',
      );
    }

    // Validate radius
    if (radius <= 0 || radius > 50000) {
      return ValidationResult(
        isValid: false,
        message: 'Radius must be between 0 and 50000 meters',
      );
    }

    return ValidationResult(isValid: true);
  }

  /// Validate report data
  ValidationResult validateReportData({
    required Map<String, dynamic> reportData,
    required int reportSizeBytes,
  }) {
    if (reportData.isEmpty) {
      return ValidationResult(
        isValid: false,
        message: 'Report data cannot be empty',
      );
    }

    if (reportSizeBytes > maxReportSize) {
      return ValidationResult(
        isValid: false,
        message:
            'Report size exceeds maximum limit (${maxReportSize ~/ (1024 * 1024)} MB)',
      );
    }

    return ValidationResult(isValid: true);
  }

  /// Validate API input
  ValidationResult validateApiInput({
    required Map<String, dynamic> input,
    required List<String> requiredFields,
  }) {
    // Check required fields
    for (final field in requiredFields) {
      if (!input.containsKey(field) || input[field] == null) {
        return ValidationResult(
          isValid: false,
          message: 'Missing required field: $field',
        );
      }
    }

    return ValidationResult(isValid: true);
  }

  bool _isValidTaskType(String type) {
    const validTypes = [
      'delivery',
      'logistics',
      'troubleshooting',
      'inspection',
      'general',
      'maintenance',
      'support',
    ];
    return validTypes.contains(type.toLowerCase());
  }

  bool _isValidDifficulty(String difficulty) {
    const validDifficulties = ['easy', 'medium', 'hard', 'critical'];
    return validDifficulties.contains(difficulty.toLowerCase());
  }

  bool _isValidFileType(String fileType) {
    const validTypes = [
      'pdf',
      'doc',
      'docx',
      'xls',
      'xlsx',
      'txt',
      'jpg',
      'jpeg',
      'png',
      'gif',
      'zip',
    ];
    return validTypes.contains(fileType.toLowerCase());
  }
}

class ValidationResult {
  final bool isValid;
  final String? message;

  ValidationResult({required this.isValid, this.message});

  @override
  String toString() => 'ValidationResult(isValid: $isValid, message: $message)';
}
