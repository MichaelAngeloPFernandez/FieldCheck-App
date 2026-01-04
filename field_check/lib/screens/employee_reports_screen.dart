import 'dart:async';
import 'package:flutter/material.dart';
import 'package:field_check/config/api_config.dart';
import 'package:field_check/models/report_model.dart';
import 'package:field_check/services/report_service.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:field_check/theme/app_theme.dart';

class EmployeeReportsScreen extends StatefulWidget {
  final String employeeId;

  const EmployeeReportsScreen({super.key, required this.employeeId});

  @override
  State<EmployeeReportsScreen> createState() => _EmployeeReportsScreenState();
}

class _EmployeeReportsScreenState extends State<EmployeeReportsScreen> {
  late final AppLifecycleListener _lifecycleListener;
  Timer? _autoRefreshTimer;
  bool _isLoading = false;
  String? _error;

  String _typeFilter = 'task'; // task | all

  List<ReportModel> _reports = [];

  @override
  void initState() {
    super.initState();
    _loadReports();

    _lifecycleListener = AppLifecycleListener(
      onResume: () {
        if (mounted) {
          _loadReports();
        }
      },
    );

    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted) return;
      if (_isLoading) return;
      _loadReports();
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _lifecycleListener.dispose();
    super.dispose();
  }

  String _normalizeAttachmentUrl(String rawPath) {
    final p = rawPath.trim();
    if (p.isEmpty) return p;
    if (p.startsWith('http://') || p.startsWith('https://')) return p;
    if (p.startsWith('/')) return '${ApiConfig.baseUrl}$p';
    return '${ApiConfig.baseUrl}/$p';
  }

  bool _isImagePath(String url) {
    final lower = url.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.gif');
  }

  String _filenameFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final segs = uri.pathSegments;
      if (segs.isEmpty) return url;
      return segs.last;
    } catch (_) {
      return url;
    }
  }

  Future<void> _openUrlExternal(String url) async {
    Uri uri;
    try {
      uri = Uri.parse(url);
      if (uri.host.isEmpty) {
        throw const FormatException('Invalid URL');
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid attachment URL'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    uri = uri.replace(
      pathSegments: uri.pathSegments.map(Uri.decodeComponent).toList(),
    );

    final can = await canLaunchUrl(uri);
    if (!can) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No app found to open attachment'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to open attachment'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showImagePreview(String title, String url) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Open',
                    onPressed: () => _openUrlExternal(url),
                    icon: const Icon(Icons.open_in_new),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Flexible(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 5,
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stack) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('Failed to load image: $error'),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadReports() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final type = _typeFilter == 'all' ? null : _typeFilter;
      final all = await ReportService().fetchReports(type: type);
      final mine = all.where((r) => r.employeeId == widget.employeeId).toList();
      mine.sort((a, b) => b.submittedAt.compareTo(a.submittedAt));

      if (!mounted) return;
      setState(() {
        _reports = mine;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load reports: $e';
        _isLoading = false;
      });
    }
  }

  void _showReportDetails(ReportModel r) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(r.taskTitle ?? 'Report Details'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow('Task:', r.taskTitle ?? (r.taskId ?? '-')),
              _buildDetailRow('Status:', r.status),
              _buildDetailRow(
                'Submitted:',
                DateFormat('yyyy-MM-dd HH:mm').format(r.submittedAt.toLocal()),
              ),
              if (r.content.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text(
                  'Content',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: SelectableText(
                    r.content,
                    style: const TextStyle(
                      fontSize: AppTheme.fontSizeMd,
                      height: 1.35,
                      color: AppTheme.textPrimaryColor,
                    ),
                  ),
                ),
              ],
              if (r.attachments.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text(
                  'Attachments:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: r.attachments.map((rawPath) {
                    final url = _normalizeAttachmentUrl(rawPath);
                    final filename = _filenameFromUrl(url);
                    final isImage = _isImagePath(url);

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: InkWell(
                        onTap: () {
                          if (isImage) {
                            _showImagePreview(filename, url);
                          } else {
                            _openUrlExternal(url);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Theme.of(context).colorScheme.outline),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isImage ? Icons.image : Icons.insert_drive_file,
                                color: isImage ? Colors.blue : Colors.blueGrey,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      filename,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: AppTheme.fontSizeMd,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      rawPath,
                                      style: const TextStyle(
                                        fontSize: AppTheme.fontSizeSm,
                                        color: AppTheme.textSecondaryColor,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                tooltip: 'Open',
                                onPressed: () => _openUrlExternal(url),
                                icon: const Icon(Icons.open_in_new),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _buildReportCard(ReportModel r) {
    final submitted = DateFormat('yyyy-MM-dd HH:mm').format(r.submittedAt.toLocal());
    final attachments = r.attachments.length;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showReportDetails(r),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                r.taskTitle ?? (r.taskId ?? 'Task'),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: AppTheme.fontSizeMd,
                  color: AppTheme.textPrimaryColor,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                    label: Text(submitted),
                    backgroundColor: Colors.grey.shade100,
                    labelStyle: TextStyle(color: Colors.grey.shade800),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  Chip(
                    label: Text('Status: ${r.status}'),
                    backgroundColor: Colors.blueGrey.shade50,
                    labelStyle: TextStyle(color: Colors.blueGrey.shade800),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  Chip(
                    label: Text('Attachments: $attachments'),
                    backgroundColor: Colors.grey.shade100,
                    labelStyle: TextStyle(color: Colors.grey.shade800),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                r.content.trim().isEmpty ? '-' : r.content.trim(),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: AppTheme.fontSizeMd,
                  height: 1.35,
                  color: AppTheme.textPrimaryColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Reports'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _loadReports,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('Task'),
                    selected: _typeFilter == 'task',
                    onSelected: (sel) {
                      if (!sel) return;
                      setState(() {
                        _typeFilter = 'task';
                      });
                      _loadReports();
                    },
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('All'),
                    selected: _typeFilter == 'all',
                    onSelected: (sel) {
                      if (!sel) return;
                      setState(() {
                        _typeFilter = 'all';
                      });
                      _loadReports();
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : (_error != null)
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.error_outline,
                                  size: 48,
                                  color: Colors.red,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _error!,
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 12),
                                FilledButton(
                                  onPressed: _loadReports,
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : (_reports.isEmpty)
                          ? const Center(child: Text('No reports yet.'))
                          : RefreshIndicator(
                              onRefresh: _loadReports,
                              child: ListView.builder(
                                padding: const EdgeInsets.all(12),
                                itemCount: _reports.length,
                                itemBuilder: (context, index) {
                                  final r = _reports[index];
                                  return _buildReportCard(r);
                                },
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }
}
