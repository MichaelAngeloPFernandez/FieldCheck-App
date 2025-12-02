import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:field_check/services/task_service.dart';
import 'package:field_check/services/report_service.dart';
import 'package:field_check/services/autosave_service.dart';
import 'package:field_check/services/realtime_service.dart';
import 'package:field_check/models/task_model.dart';

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
  final TextEditingController _textController = TextEditingController();
  final List<PlatformFile> _selectedFiles = [];
  final AutosaveService _autosaveService = AutosaveService();
  final RealtimeService _realtimeService = RealtimeService();
  bool _isSubmitting = false;
  bool _hasUnsavedChanges = false;
  bool _statusMarkedInProgress = false;
  Timer? _autosaveTimer;

  @override
  void initState() {
    super.initState();
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
      if (!_statusMarkedInProgress && widget.task.status == 'pending' && widget.task.userTaskId != null) {
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
      await TaskService().updateUserTaskStatus(widget.task.userTaskId!, 'in_progress');
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

        final files = autosavedData['files'] as List<dynamic>?;
        if (files != null) {
          setState(() {
            _selectedFiles.clear();
            for (final fileData in files) {
              final file = PlatformFile(
                name: fileData['name'],
                size: fileData['size'],
                path: fileData['path'],
              );
              _selectedFiles.add(file);
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading autosaved data: $e');
    }
  }

  Future<void> _saveToAutosave() async {
    if (!_hasUnsavedChanges) return;

    try {
      final content = _textController.text;
      final files = _selectedFiles
          .map(
            (file) => {'name': file.name, 'size': file.size, 'path': file.path},
          )
          .toList();

      await _autosaveService.saveData('task_report_${widget.task.id}', {
        'content': content,
        'files': files,
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

  Future<void> _pickFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
        withData: false,
      );

      if (result != null) {
        setState(() {
          _selectedFiles.addAll(result.files);
        });
        _hasUnsavedChanges = true;
        _saveToAutosave();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error picking files: $e')));
      }
    }
  }

  void _removeFile(int index) {
    setState(() {
      _selectedFiles.removeAt(index);
    });
    _hasUnsavedChanges = true;
    _saveToAutosave();
  }

  Future<void> _submitReport() async {
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
    });

    try {
      // Get the text content
      final content = _textController.text.trim();

      // Create the report
      await ReportService().createTaskReport(
        taskId: widget.task.id,
        employeeId: widget.employeeId,
        content: content,
      );

      // Update task status
      await TaskService().updateUserTaskStatus(
        widget.task.userTaskId!,
        'completed',
      );

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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error submitting report: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
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
            onPressed: _pickFiles,
            tooltip: 'Attach Files',
          ),
        ],
      ),
      body: Column(
        children: [
          // Task info header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Colors.grey.shade100,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.task.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.task.description,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.schedule, size: 16, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Text(
                      'Due: ${widget.task.dueDate.toLocal().toString().split(' ')[0]}',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Rich text editor
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Text(
                    'Write your report:',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: TextField(
                        controller: _textController,
                        maxLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
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
          if (_selectedFiles.isNotEmpty)
            Container(
              height: 120,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Attached Files:',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _selectedFiles.length,
                      itemBuilder: (context, index) {
                        final file = _selectedFiles[index];
                        return Container(
                          margin: const EdgeInsets.only(right: 8),
                          child: Chip(
                            label: Text(
                              file.name,
                              style: const TextStyle(fontSize: 12),
                            ),
                            deleteIcon: const Icon(Icons.close, size: 16),
                            onDeleted: () => _removeFile(index),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

          // Submit button
          Container(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
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
          ),
        ],
      ),
    );
  }
}
