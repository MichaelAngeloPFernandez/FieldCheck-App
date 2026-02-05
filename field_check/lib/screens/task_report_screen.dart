import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:field_check/services/task_service.dart';
import 'package:field_check/services/report_service.dart';
import 'package:field_check/services/autosave_service.dart';
import 'package:field_check/services/realtime_service.dart';
import 'package:field_check/models/task_model.dart';
import 'package:field_check/utils/app_theme.dart';
import 'package:field_check/utils/manila_time.dart';
import 'package:field_check/widgets/app_page.dart';
import 'package:field_check/widgets/app_widgets.dart';

class TaskReportScreen extends StatefulWidget {
  final Task task;
  final String employeeId;
  final String? existingReportId;
  final String? existingReportContent;

  const TaskReportScreen({
    super.key,
    required this.task,
    required this.employeeId,
    this.existingReportId,
    this.existingReportContent,
  });

  @override
  State<TaskReportScreen> createState() => _TaskReportScreenState();
}

class _TaskReportScreenState extends State<TaskReportScreen> {
  static const int _maxUploadBytes = ReportService.maxUploadBytes;
  final TextEditingController _textController = TextEditingController();
  final List<PlatformFile> _beforeFiles = [];
  final List<PlatformFile> _afterFiles = [];
  final List<PlatformFile> _documentFiles = [];
  final AutosaveService _autosaveService = AutosaveService();
  final RealtimeService _realtimeService = RealtimeService();
  late Task _task;
  bool _isSubmitting = false;
  bool _isBlocking = false;
  bool _hasUnsavedChanges = false;
  bool _statusMarkedInProgress = false;
  int _reportProgressPercent = 0;
  int? _lastSyncedProgressPercent;
  Timer? _autosaveTimer;
  String? _submitPhase;
  int _submitTotal = 0;
  int _submitDone = 0;
  String? _submitCurrentFile;

  @override
  void initState() {
    super.initState();
    _task = widget.task;
    if (widget.existingReportId != null &&
        widget.existingReportId!.trim().isNotEmpty) {
      final initial = widget.existingReportContent;
      if (initial != null && initial.trim().isNotEmpty) {
        _textController.text = initial;
      }
    }
    _reportProgressPercent = _calculateReportProgressPercent();
    _loadAutosavedData();
    _startAutosave();
  }

  bool get _isResubmission {
    final id = widget.existingReportId;
    return id != null && id.trim().isNotEmpty;
  }

  bool get _needsAcceptance {
    final s = _task.userTaskStatus;
    return s == null || s == 'pending' || s == 'pending_acceptance';
  }

  int _countWords(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return 0;
    return RegExp(r'\b\w+\b').allMatches(trimmed).length;
  }

  int _calculateReportProgressPercent() {
    final wordCount = _countWords(_textController.text);
    int progress = 0;

    if (wordCount >= 500) {
      progress += 50;
    } else if (wordCount >= 250) {
      progress += 25;
    }

    if (_beforeFiles.isNotEmpty && _afterFiles.isNotEmpty) {
      progress += 25;
    }

    if (_documentFiles.isNotEmpty) {
      progress += 25;
    }

    return progress.clamp(0, 100).toInt();
  }

  void _refreshReportProgress() {
    if (_task.checklist.isNotEmpty) return;
    final next = _calculateReportProgressPercent();
    if (next == _reportProgressPercent || !mounted) return;
    setState(() {
      _reportProgressPercent = next;
    });
  }

  int _currentProgressPercent() {
    if (_task.checklist.isNotEmpty) {
      return _task.progressPercent.clamp(0, 100);
    }
    return _reportProgressPercent;
  }

  Future<void> _acceptTask() async {
    final userTaskId = _task.userTaskId;
    if (userTaskId == null || userTaskId.trim().isEmpty) return;
    try {
      await TaskService().acceptUserTask(userTaskId);
      if (!mounted) return;
      setState(() {
        _task = _task.copyWith(userTaskStatus: 'accepted');
      });
      AppWidgets.showSuccessSnackbar(context, 'Task accepted');
    } catch (e) {
      if (!mounted) return;
      AppWidgets.showErrorSnackbar(
        context,
        AppWidgets.friendlyErrorMessage(e, fallback: 'Failed to accept task'),
      );
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _autosaveTimer?.cancel();
    super.dispose();
  }

  void _startAutosave() {
    _textController.addListener(() {
      _hasUnsavedChanges = true;
      _refreshReportProgress();

      // Mark task as in_progress on first keystroke (if not already marked)
      if (!_statusMarkedInProgress &&
          (_task.userTaskStatus == 'accepted' ||
              _task.userTaskStatus == 'in_progress') &&
          _task.userTaskId != null &&
          _textController.text.trim().isNotEmpty) {
        _statusMarkedInProgress = true;
        _markTaskInProgress();
      }

      _autosaveTimer?.cancel();
      _autosaveTimer = Timer(const Duration(seconds: 2), () {
        _saveToAutosave();
      });
    });
  }

  Future<void> _markTaskInProgress() async {
    try {
      await TaskService().updateUserTaskStatus(
        _task.userTaskId!,
        'in_progress',
      );
      if (mounted) {
        setState(() {
          _task = _task.copyWith(userTaskStatus: 'in_progress');
        });
      }
      if (mounted) {
        AppWidgets.showWarningSnackbar(context, 'Task marked as in progress');
      }
    } catch (e) {
      debugPrint('Error marking task as in_progress: $e');
    }
  }

  Future<void> _loadAutosavedData() async {
    try {
      final autosavedData = await _autosaveService.getData(
        'task_report_${widget.task.id}',
      );
      if (autosavedData != null && mounted) {
        final content = autosavedData['content'] as String?;
        if (content != null && content.isNotEmpty) {
          _textController.text = content;
        }

        final beforeFiles = autosavedData['beforeFiles'] as List<dynamic>?;
        final afterFiles = autosavedData['afterFiles'] as List<dynamic>?;
        List<dynamic>? documentFiles =
            autosavedData['documentFiles'] as List<dynamic>?;

        // Backwards compatibility with legacy single files list
        final legacyFiles = autosavedData['files'] as List<dynamic>?;
        if ((beforeFiles == null || beforeFiles.isEmpty) &&
            (afterFiles == null || afterFiles.isEmpty) &&
            (documentFiles == null || documentFiles.isEmpty) &&
            legacyFiles != null) {
          documentFiles = legacyFiles;
        }

        void loadFiles(List<dynamic>? src, List<PlatformFile> target) {
          if (src == null) return;
          for (final fileData in src) {
            if (fileData is Map<String, dynamic>) {
              final file = PlatformFile(
                name: fileData['name'] ?? '',
                size: fileData['size'] is int ? fileData['size'] as int : 0,
                path: fileData['path'] as String?,
              );
              target.add(file);
            }
          }
        }

        setState(() {
          _beforeFiles.clear();
          _afterFiles.clear();
          _documentFiles.clear();

          loadFiles(beforeFiles, _beforeFiles);
          loadFiles(afterFiles, _afterFiles);
          loadFiles(documentFiles, _documentFiles);

          if (_task.checklist.isEmpty) {
            _reportProgressPercent = _calculateReportProgressPercent();
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading autosaved data: $e');
    }
  }

  Future<void> _saveToAutosave({
    bool force = false,
    String? successMessage,
  }) async {
    if (!_hasUnsavedChanges && !force) return;

    try {
      final content = _textController.text;
      final beforeFiles = _beforeFiles
          .map(
            (file) => {'name': file.name, 'size': file.size, 'path': file.path},
          )
          .toList();
      final afterFiles = _afterFiles
          .map(
            (file) => {'name': file.name, 'size': file.size, 'path': file.path},
          )
          .toList();
      final documentFiles = _documentFiles
          .map(
            (file) => {'name': file.name, 'size': file.size, 'path': file.path},
          )
          .toList();

      await _autosaveService.saveData('task_report_${widget.task.id}', {
        'content': content,
        'beforeFiles': beforeFiles,
        'afterFiles': afterFiles,
        'documentFiles': documentFiles,
        'taskId': widget.task.id,
        'employeeId': widget.employeeId,
      });

      if (mounted) {
        setState(() {
          _hasUnsavedChanges = false;
        });
        AppWidgets.showSuccessSnackbar(
          context,
          successMessage ?? 'Progress saved automatically',
        );
      } else {
        _hasUnsavedChanges = false;
      }

      await _syncReportProgressToBackend(
        progressPercent: _reportProgressPercent,
      );
    } catch (e) {
      debugPrint('Error saving to autosave: $e');
    }
  }

  Future<void> _saveProgressManually() async {
    _refreshReportProgress();
    await _saveToAutosave(force: true, successMessage: 'Progress saved');
  }

  Future<void> _syncReportProgressToBackend({int? progressPercent}) async {
    if (_task.checklist.isNotEmpty) return;
    if (_needsAcceptance) return;

    final userTaskId = _task.userTaskId;
    final status = _task.userTaskStatus;
    if (userTaskId == null || userTaskId.trim().isEmpty) return;
    if (status == null || status.trim().isEmpty) return;

    final next = (progressPercent ?? _calculateReportProgressPercent())
        .clamp(0, 100)
        .toInt();
    if (_lastSyncedProgressPercent == next) return;

    try {
      await TaskService().updateUserTaskStatus(
        userTaskId,
        status,
        progressPercent: next,
      );
      _lastSyncedProgressPercent = next;
    } catch (e) {
      debugPrint('Error syncing report progress: $e');
    }
  }

  Future<void> _pickBeforePhotos() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.image,
        withData: true,
      );

      if (result != null) {
        final accepted = <PlatformFile>[];
        int rejected = 0;

        for (final f in result.files) {
          final size = f.size;
          if (size > _maxUploadBytes) {
            rejected++;
            continue;
          }
          accepted.add(f);
        }

        if (!mounted) return;
        if (rejected > 0) {
          AppWidgets.showWarningSnackbar(
            context,
            '$rejected file(s) were skipped because they exceed 10MB.',
          );
        }

        setState(() {
          _beforeFiles.addAll(accepted);
          _hasUnsavedChanges = true;
          if (_task.checklist.isEmpty) {
            _reportProgressPercent = _calculateReportProgressPercent();
          }
        });
        _saveToAutosave();
      }
    } catch (e) {
      if (!mounted) return;
      AppWidgets.showErrorSnackbar(
        context,
        AppWidgets.friendlyErrorMessage(
          e,
          fallback: 'Error picking before photos',
        ),
      );
    }
  }

  Future<void> _pickAfterPhotos() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.image,
        withData: true,
      );

      if (result != null) {
        final accepted = <PlatformFile>[];
        int rejected = 0;

        for (final f in result.files) {
          final size = f.size;
          if (size > _maxUploadBytes) {
            rejected++;
            continue;
          }
          accepted.add(f);
        }

        if (!mounted) return;
        if (rejected > 0) {
          AppWidgets.showWarningSnackbar(
            context,
            '$rejected file(s) were skipped because they exceed 10MB.',
          );
        }

        setState(() {
          _afterFiles.addAll(accepted);
          _hasUnsavedChanges = true;
          if (_task.checklist.isEmpty) {
            _reportProgressPercent = _calculateReportProgressPercent();
          }
        });
        _saveToAutosave();
      }
    } catch (e) {
      if (!mounted) return;
      AppWidgets.showErrorSnackbar(
        context,
        AppWidgets.friendlyErrorMessage(
          e,
          fallback: 'Error picking after photos',
        ),
      );
    }
  }

  Future<void> _pickDocuments() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
        withData: true,
      );

      if (result != null) {
        final accepted = <PlatformFile>[];
        int rejected = 0;

        for (final f in result.files) {
          final size = f.size;
          if (size > _maxUploadBytes) {
            rejected++;
            continue;
          }
          accepted.add(f);
        }

        if (!mounted) return;
        if (rejected > 0) {
          AppWidgets.showWarningSnackbar(
            context,
            '$rejected file(s) were skipped because they exceed 10MB.',
          );
        }

        setState(() {
          _documentFiles.addAll(accepted);
          _hasUnsavedChanges = true;
          if (_task.checklist.isEmpty) {
            _reportProgressPercent = _calculateReportProgressPercent();
          }
        });
        _saveToAutosave();
      }
    } catch (e) {
      if (!mounted) return;
      AppWidgets.showErrorSnackbar(
        context,
        AppWidgets.friendlyErrorMessage(e, fallback: 'Error picking documents'),
      );
    }
  }

  Future<void> _showAttachmentTypePicker() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Add Before Photos'),
                onTap: () {
                  Navigator.pop(context);
                  _pickBeforePhotos();
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera),
                title: const Text('Add After Photos'),
                onTap: () {
                  Navigator.pop(context);
                  _pickAfterPhotos();
                },
              ),
              ListTile(
                leading: const Icon(Icons.description),
                title: const Text('Add Documents'),
                onTap: () {
                  Navigator.pop(context);
                  _pickDocuments();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _removeBeforeFile(int index) {
    setState(() {
      _beforeFiles.removeAt(index);
      _hasUnsavedChanges = true;
      if (_task.checklist.isEmpty) {
        _reportProgressPercent = _calculateReportProgressPercent();
      }
    });
    _saveToAutosave();
  }

  void _removeAfterFile(int index) {
    setState(() {
      _afterFiles.removeAt(index);
      _hasUnsavedChanges = true;
      if (_task.checklist.isEmpty) {
        _reportProgressPercent = _calculateReportProgressPercent();
      }
    });
    _saveToAutosave();
  }

  void _removeDocumentFile(int index) {
    setState(() {
      _documentFiles.removeAt(index);
      _hasUnsavedChanges = true;
      if (_task.checklist.isEmpty) {
        _reportProgressPercent = _calculateReportProgressPercent();
      }
    });
    _saveToAutosave();
  }

  Future<void> _toggleChecklistItem(int index, bool isCompleted) async {
    try {
      final updated = await TaskService().updateTaskChecklistItem(
        taskId: _task.id,
        index: index,
        isCompleted: isCompleted,
      );
      if (!mounted) return;
      setState(() {
        _task = updated;
      });
      AppWidgets.showSuccessSnackbar(
        context,
        isCompleted
            ? 'Checklist item marked as completed'
            : 'Checklist item marked as incomplete',
      );
    } catch (e) {
      if (!mounted) return;
      AppWidgets.showErrorSnackbar(
        context,
        AppWidgets.friendlyErrorMessage(
          e,
          fallback: 'Failed to update checklist',
        ),
      );
    }
  }

  Future<void> _blockTask() async {
    if (_isBlocking) return;

    const presetReasons = <String>[
      'Customer unavailable',
      'Location inaccessible',
      'Missing materials or tools',
      'Safety concerns',
      'Other',
    ];

    String selectedReason = presetReasons.first;
    String customReason = '';

    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Block Task'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Select a reason for blocking this task:'),
                    const SizedBox(height: 8),
                    ...presetReasons.map(
                      (reason) => RadioListTile<String>(
                        title: Text(reason),
                        value: reason,
                        // ignore: deprecated_member_use
                        groupValue: selectedReason,
                        // ignore: deprecated_member_use
                        onChanged: (value) {
                          if (value == null) return;
                          setStateDialog(() {
                            selectedReason = value;
                          });
                        },
                      ),
                    ),
                    if (selectedReason == 'Other') ...[
                      const SizedBox(height: 8),
                      TextField(
                        decoration: const InputDecoration(
                          labelText: 'Custom reason',
                        ),
                        onChanged: (value) {
                          customReason = value;
                        },
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    String finalReason = selectedReason;
                    if (selectedReason == 'Other') {
                      finalReason = customReason.trim();
                    }

                    if (finalReason.isEmpty) {
                      return;
                    }

                    Navigator.of(context).pop(finalReason);
                  },
                  child: const Text('Confirm'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null || result.trim().isEmpty) {
      return;
    }

    setState(() {
      _isBlocking = true;
    });

    try {
      final updated = await TaskService().blockTask(_task.id, result.trim());
      if (!mounted) return;
      setState(() {
        _task = updated;
      });

      AppWidgets.showErrorSnackbar(context, 'Task has been marked as blocked');

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      AppWidgets.showErrorSnackbar(
        context,
        AppWidgets.friendlyErrorMessage(e, fallback: 'Failed to block task'),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isBlocking = false;
        });
      }
    }
  }

  Future<bool> _submitReport() async {
    if (_isSubmitting) return false;
    if (_textController.text.trim().isEmpty) {
      AppWidgets.showWarningSnackbar(
        context,
        'Please write a report before submitting',
      );
      return false;
    }

    setState(() {
      _isSubmitting = true;
      _submitPhase = 'Preparing submission...';
      _submitTotal =
          _beforeFiles.length + _afterFiles.length + _documentFiles.length;
      _submitDone = 0;
      _submitCurrentFile = null;
    });

    try {
      // Get the text content
      final content = _textController.text.trim();

      // Upload attachments (if any) and collect their URLs
      final List<String> attachmentPaths = [];
      Future<void> uploadGroup(List<PlatformFile> files, String prefix) async {
        if (files.isEmpty) return;
        if (mounted) {
          setState(() {
            _submitPhase = 'Uploading $prefix attachments...';
          });
        }
        for (final file in files) {
          if (file.size > _maxUploadBytes) {
            if (!mounted) return;
            AppWidgets.showWarningSnackbar(
              context,
              'Skipped ${file.name}: exceeds 10MB limit.',
            );
            if (mounted) {
              setState(() {
                _submitDone = min(_submitDone + 1, _submitTotal);
              });
            }
            continue;
          }

          final fileName = '${prefix}_${file.name}';

          if (mounted) {
            setState(() {
              _submitCurrentFile = file.name;
            });
          }

          // Web-safe path: prefer bytes if available.
          if (file.bytes != null) {
            final uploadedPath = await ReportService().uploadAttachmentBytes(
              bytes: file.bytes!,
              fileName: fileName,
              taskId: _task.id,
              employeeId: widget.employeeId,
            );
            attachmentPaths.add(uploadedPath);

            if (mounted) {
              setState(() {
                _submitDone = min(_submitDone + 1, _submitTotal);
              });
            }
            continue;
          }

          // Mobile/desktop path: use file path.
          final filePath = file.path;
          if (filePath == null || filePath.isEmpty) {
            if (!mounted) return;
            AppWidgets.showWarningSnackbar(
              context,
              'Skipped ${file.name}: could not read file data.',
            );
            if (mounted) {
              setState(() {
                _submitDone = min(_submitDone + 1, _submitTotal);
              });
            }
            continue;
          }

          final uploadedPath = await ReportService().uploadAttachment(
            filePath: filePath,
            fileName: fileName,
            taskId: _task.id,
            employeeId: widget.employeeId,
          );
          attachmentPaths.add(uploadedPath);

          if (mounted) {
            setState(() {
              _submitDone = min(_submitDone + 1, _submitTotal);
            });
          }
        }
      }

      await uploadGroup(_beforeFiles, 'before');
      await uploadGroup(_afterFiles, 'after');
      await uploadGroup(_documentFiles, 'doc');

      if (mounted) {
        setState(() {
          _submitPhase = 'Submitting report...';
          _submitCurrentFile = null;
        });
      }

      // Create the report
      if (_isResubmission) {
        await ReportService().resubmitReport(
          reportId: widget.existingReportId!,
          content: content,
          attachments: attachmentPaths,
        );
        await _autosaveService.clearData('task_report_${widget.task.id}');
      } else {
        await ReportService().createTaskReport(
          taskId: _task.id,
          employeeId: widget.employeeId,
          content: content,
          attachments: attachmentPaths,
        );

        if (_needsAcceptance) {
          throw Exception('Accept this task first to begin');
        }

        final progressPercent = _task.checklist.isNotEmpty
            ? null
            : _calculateReportProgressPercent();
        await TaskService().updateUserTaskStatus(
          _task.userTaskId!,
          'completed',
          progressPercent: progressPercent,
        );

        await _autosaveService.clearData('task_report_${widget.task.id}');

        _realtimeService.emit('taskCompleted', {
          'taskId': widget.task.id,
          'employeeId': widget.employeeId,
          'timestamp': DateTime.now().toIso8601String(),
        });
      }

      if (mounted) {
        AppWidgets.showSuccessSnackbar(
          context,
          _isResubmission
              ? 'Report resubmitted successfully!'
              : 'Report submitted successfully!',
        );
        Navigator.pop(context, true);
      }
      return true;
    } catch (e) {
      if (mounted) {
        final phase = _submitPhase;
        final f = _submitCurrentFile;
        final contextLabel = [
          if (phase != null && phase.isNotEmpty) phase,
          if (f != null && f.isNotEmpty) 'File: $f',
        ].join(' • ');
        AppWidgets.showErrorSnackbar(
          context,
          AppWidgets.friendlyErrorMessage(
            e,
            fallback: 'Error submitting report',
          ),
        );

        if (contextLabel.isNotEmpty) {
          AppWidgets.showWarningSnackbar(context, contextLabel);
        }
      }
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _submitPhase = null;
          _submitCurrentFile = null;
        });
      }
    }
  }

  bool _isLikelyImage(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp');
  }

  Future<void> _previewSelectedFile(PlatformFile file) async {
    if (file.bytes == null) {
      if (!mounted) return;
      AppWidgets.showWarningSnackbar(
        context,
        'Preview not available for ${file.name}',
      );
      return;
    }

    if (!_isLikelyImage(file.name)) {
      if (!mounted) return;
      AppWidgets.showWarningSnackbar(context, 'No preview for ${file.name}.');
      return;
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return Dialog(
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 4,
            child: Image.memory(file.bytes!, fit: BoxFit.contain),
          ),
        );
      },
    );
  }

  String _humanBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    var size = bytes.toDouble();
    var i = 0;
    while (size >= 1024 && i < units.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(i == 0 ? 0 : 1)} ${units[i]}';
  }

  @override
  Widget build(BuildContext context) {
    final hasChecklist = _task.checklist.isNotEmpty;
    final progressPercent = _currentProgressPercent().clamp(0, 100).toInt();
    final progressLabel = hasChecklist
        ? 'Progress: $progressPercent%'
        : 'Report Progress: $progressPercent%';
    return AppPage(
      appBarTitle: 'Task Report',
      showBack: true,
      scroll: false,
      actions: [
        if (_needsAcceptance)
          TextButton.icon(
            onPressed: _acceptTask,
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Accept'),
          ),
        if (_hasUnsavedChanges)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.5),
                  ),
                ),
                child: const Text(
                  'Unsaved changes',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        IconButton(
          icon: const Icon(Icons.attach_file),
          onPressed: _isSubmitting ? null : _showAttachmentTypePicker,
          tooltip: 'Attach Files',
        ),
      ],
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          if (_isSubmitting)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(
                AppTheme.lg,
                AppTheme.md,
                AppTheme.lg,
                AppTheme.md,
              ),
              color: AppTheme.backgroundColor,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _submitPhase ?? 'Submitting...',
                    style: AppTheme.bodyMd.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (_submitTotal > 0)
                    LinearProgressIndicator(
                      value: (_submitDone / _submitTotal).clamp(0.0, 1.0),
                      backgroundColor: AppTheme.dividerColor,
                    ),
                  const SizedBox(height: 6),
                  if (_submitTotal > 0)
                    Text(
                      '$_submitDone / $_submitTotal uploaded'
                      '${_submitCurrentFile != null ? ' • ${_submitCurrentFile!}' : ''}',
                      style: AppTheme.bodySm.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
          // Task info header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppTheme.lg),
            color: AppTheme.backgroundColor,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.task.title, style: AppTheme.headingSm),
                const SizedBox(height: 8),
                Text(
                  widget.task.description,
                  style: AppTheme.bodyMd.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.schedule,
                      size: 16,
                      color: AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Due: ${formatManila(_task.dueDate, 'yyyy-MM-dd')}',
                      style: AppTheme.bodySm.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
                if (_task.isOverdue && !_task.isArchived) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: Colors.red.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.warning_amber_rounded,
                              size: 14,
                              color: Colors.red,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Overdue',
                              style: AppTheme.bodySm.copyWith(
                                color: Colors.red,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.check_circle,
                      size: 16,
                      color: AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      progressLabel,
                      style: AppTheme.bodySm.copyWith(
                        color: AppTheme.textPrimary.withValues(alpha: 0.75),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: progressPercent / 100.0,
                  backgroundColor: AppTheme.dividerColor,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppTheme.primaryColor,
                  ),
                ),
              ],
            ),
          ),

          // Rich text editor
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(AppTheme.lg),
              child: Column(
                children: [
                  if (_task.checklist.isNotEmpty) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Checklist:',
                        style: TextStyle(
                          fontSize: AppTheme.headingSm.fontSize,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: AppTheme.dividerColor),
                        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _task.checklist.length,
                        separatorBuilder: (context, _) => const Divider(
                          height: 1,
                          color: AppTheme.dividerColor,
                        ),
                        itemBuilder: (context, index) {
                          final item = _task.checklist[index];
                          final isDisabled =
                              _task.rawStatus == 'blocked' || _isSubmitting;
                          return CheckboxListTile(
                            value: item.isCompleted,
                            onChanged: isDisabled
                                ? null
                                : (value) {
                                    if (value == null) return;
                                    _toggleChecklistItem(index, value);
                                  },
                            title: Text(item.label),
                            subtitle: item.completedAt != null
                                ? Text(
                                    'Completed at: ${formatManila(item.completedAt, 'yyyy-MM-dd HH:mm:ss')}',
                                    style: AppTheme.bodySm,
                                  )
                                : null,
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Write your report:',
                          style: AppTheme.labelLg,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _isSubmitting ? null : _saveProgressManually,
                        icon: const Icon(Icons.save_outlined, size: 18),
                        label: const Text('Save Progress'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppTheme.primaryColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: AppTheme.dividerColor),
                        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      ),
                      child: TextField(
                        controller: _textController,
                        maxLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                        style: AppTheme.bodyMd,
                        decoration: const InputDecoration(
                          hintText:
                              'Describe what you did, any issues encountered, or additional notes...',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.all(16),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Selected files
          if (_beforeFiles.isNotEmpty ||
              _afterFiles.isNotEmpty ||
              _documentFiles.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppTheme.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_beforeFiles.isNotEmpty) ...[
                    const Text(
                      'Before Photos:',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 4),
                    ...List.generate(_beforeFiles.length, (index) {
                      final file = _beforeFiles[index];
                      final tooBig = file.size > _maxUploadBytes;
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          _isLikelyImage(file.name)
                              ? Icons.image_outlined
                              : Icons.insert_drive_file_outlined,
                          color: tooBig ? Colors.red : null,
                        ),
                        title: Text(
                          file.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${_humanBytes(file.size)}'
                          '${tooBig ? ' • exceeds 10MB' : ''}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.visibility),
                              onPressed: _isSubmitting
                                  ? null
                                  : () => _previewSelectedFile(file),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: _isSubmitting
                                  ? null
                                  : () => _removeBeforeFile(index),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 8),
                  ],
                  if (_afterFiles.isNotEmpty) ...[
                    const Text(
                      'After Photos:',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 4),
                    ...List.generate(_afterFiles.length, (index) {
                      final file = _afterFiles[index];
                      final tooBig = file.size > _maxUploadBytes;
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          _isLikelyImage(file.name)
                              ? Icons.image_outlined
                              : Icons.insert_drive_file_outlined,
                          color: tooBig ? Colors.red : null,
                        ),
                        title: Text(
                          file.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${_humanBytes(file.size)}'
                          '${tooBig ? ' • exceeds 10MB' : ''}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.visibility),
                              onPressed: _isSubmitting
                                  ? null
                                  : () => _previewSelectedFile(file),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: _isSubmitting
                                  ? null
                                  : () => _removeAfterFile(index),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 8),
                  ],
                  if (_documentFiles.isNotEmpty) ...[
                    const Text(
                      'Documents:',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 4),
                    ...List.generate(_documentFiles.length, (index) {
                      final file = _documentFiles[index];
                      final tooBig = file.size > _maxUploadBytes;
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          _isLikelyImage(file.name)
                              ? Icons.image_outlined
                              : Icons.insert_drive_file_outlined,
                          color: tooBig ? Colors.red : null,
                        ),
                        title: Text(
                          file.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${_humanBytes(file.size)}'
                          '${tooBig ? ' • exceeds 10MB' : ''}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.visibility),
                              onPressed: _isSubmitting
                                  ? null
                                  : () => _previewSelectedFile(file),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: _isSubmitting
                                  ? null
                                  : () => _removeDocumentFile(index),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),

          // Submit button
          Container(
            padding: const EdgeInsets.all(AppTheme.lg),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        _isSubmitting ||
                            _isBlocking ||
                            _task.rawStatus == 'blocked'
                        ? null
                        : _blockTask,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(
                        vertical: AppTheme.lg,
                      ),
                    ),
                    child: _isBlocking
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.red,
                              ),
                            ),
                          )
                        : const Text(
                            'Block Task',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: AppTheme.md),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _submitReport,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(
                        vertical: AppTheme.lg,
                      ),
                    ),
                    child: _isSubmitting
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              ),
                              SizedBox(width: 8),
                              Text('Submitting...'),
                            ],
                          )
                        : const Text(
                            'Submit Report',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
