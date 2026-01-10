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

class TaskReportScreen extends StatefulWidget {
  final Task task;
  final String employeeId;

  const TaskReportScreen({
    super.key,
    required this.task,
    required this.employeeId,
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
  Timer? _autosaveTimer;
  String? _submitPhase;
  int _submitTotal = 0;
  int _submitDone = 0;
  String? _submitCurrentFile;

  @override
  void initState() {
    super.initState();
    _task = widget.task;
    _loadAutosavedData();
    _startAutosave();
  }

  @override
  void dispose() {
    _textController.dispose();
    _autosaveTimer?.cancel();
    super.dispose();
  }

  void _startAutosave() {
    _textController.addListener(() {
      if (_textController.text.isEmpty) return;

      _hasUnsavedChanges = true;

      // Mark task as in_progress on first keystroke (if not already marked)
      if (!_statusMarkedInProgress &&
          _task.status == 'pending' &&
          _task.userTaskId != null) {
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Task marked as in progress'),
            duration: Duration(seconds: 1),
            backgroundColor: Colors.orange,
          ),
        );
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
        });
      }
    } catch (e) {
      debugPrint('Error loading autosaved data: $e');
    }
  }

  Future<void> _saveToAutosave() async {
    if (!_hasUnsavedChanges) return;

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

      _hasUnsavedChanges = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Progress saved automatically'),
            duration: Duration(seconds: 1),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error saving to autosave: $e');
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '$rejected file(s) were skipped because they exceed 10MB.',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }

        setState(() {
          _beforeFiles.addAll(accepted);
        });
        _saveToAutosave();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking before photos: $e')),
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '$rejected file(s) were skipped because they exceed 10MB.',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }

        setState(() {
          _afterFiles.addAll(accepted);
        });
        _saveToAutosave();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error picking after photos: $e')));
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '$rejected file(s) were skipped because they exceed 10MB.',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }

        setState(() {
          _documentFiles.addAll(accepted);
        });
        _saveToAutosave();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error picking documents: $e')));
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
    });
    _hasUnsavedChanges = true;
    _saveToAutosave();
  }

  void _removeAfterFile(int index) {
    setState(() {
      _afterFiles.removeAt(index);
    });
    _hasUnsavedChanges = true;
    _saveToAutosave();
  }

  void _removeDocumentFile(int index) {
    setState(() {
      _documentFiles.removeAt(index);
    });
    _hasUnsavedChanges = true;
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isCompleted
                ? 'Checklist item marked as completed'
                : 'Checklist item marked as incomplete',
          ),
          duration: const Duration(seconds: 1),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to update checklist: $e')));
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

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Task has been marked as blocked'),
          backgroundColor: Colors.red,
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to block task: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isBlocking = false;
        });
      }
    }
  }

  Future<void> _submitReport() async {
    if (_isSubmitting) return;
    if (_textController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please write a report before submitting'),
        ),
      );
      return;
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
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Skipped ${file.name}: exceeds 10MB limit.'),
                backgroundColor: Colors.orange,
              ),
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
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Skipped ${file.name}: could not read file data.',
                ),
                backgroundColor: Colors.orange,
              ),
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
      await ReportService().createTaskReport(
        taskId: _task.id,
        employeeId: widget.employeeId,
        content: content,
        attachments: attachmentPaths,
      );

      // Update task status
      await TaskService().updateUserTaskStatus(_task.userTaskId!, 'completed');

      // Clear autosaved data
      await _autosaveService.clearData('task_report_${widget.task.id}');

      // Emit real-time update
      _realtimeService.emit('taskCompleted', {
        'taskId': widget.task.id,
        'employeeId': widget.employeeId,
        'timestamp': DateTime.now().toIso8601String(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Report submitted successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        final phase = _submitPhase;
        final f = _submitCurrentFile;
        final contextLabel = [
          if (phase != null && phase.isNotEmpty) phase,
          if (f != null && f.isNotEmpty) 'File: $f',
        ].join(' • ');
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error submitting report: $e')));

        if (contextLabel.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(contextLabel),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Preview not available for ${file.name}')),
      );
      return;
    }

    if (!_isLikelyImage(file.name)) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No preview for ${file.name}.')));
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Task Report'),
        actions: [
          if (_hasUnsavedChanges)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Icon(Icons.save, color: Colors.orange),
            ),
          IconButton(
            icon: const Icon(Icons.attach_file),
            onPressed: _isSubmitting ? null : _showAttachmentTypePicker,
            tooltip: 'Attach Files',
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isSubmitting)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
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
            padding: const EdgeInsets.all(16),
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
                      'Due: ${_task.dueDate.toLocal().toString().split(' ')[0]}',
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
                if (_task.checklist.isNotEmpty) ...[
                  Row(
                    children: [
                      Icon(
                        Icons.check_circle,
                        size: 16,
                        color: AppTheme.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Progress: ${_task.progressPercent.clamp(0, 100)}%',
                        style: AppTheme.bodySm.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: _task.progressPercent.clamp(0, 100) / 100.0,
                    backgroundColor: AppTheme.dividerColor,
                  ),
                ],
              ],
            ),
          ),

          // Rich text editor
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
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
                        borderRadius: BorderRadius.circular(8),
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
                                    'Completed at: ${item.completedAt!.toLocal().toString().split('.')[0]}',
                                    style: AppTheme.bodySm,
                                  )
                                : null,
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  const Text('Write your report:', style: AppTheme.labelLg),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: AppTheme.dividerColor),
                        borderRadius: BorderRadius.circular(8),
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
              padding: const EdgeInsets.all(16),
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
            padding: const EdgeInsets.all(16),
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
                      padding: const EdgeInsets.symmetric(vertical: 16),
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
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _submitReport,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(vertical: 16),
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
