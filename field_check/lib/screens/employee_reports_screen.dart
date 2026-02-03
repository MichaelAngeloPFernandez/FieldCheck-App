import 'dart:async';
import 'package:flutter/material.dart';
import 'package:field_check/config/api_config.dart';
import 'package:field_check/models/report_model.dart';
import 'package:field_check/services/report_service.dart';
import 'package:field_check/services/task_service.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:field_check/utils/app_theme.dart';
import 'package:field_check/widgets/app_page.dart';
import 'package:field_check/widgets/app_widgets.dart';
import 'package:field_check/utils/manila_time.dart';
import 'package:field_check/services/user_service.dart';
import 'package:field_check/utils/file_download/file_download.dart';
import 'package:field_check/screens/task_report_screen.dart';

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

  String _tab = 'current'; // current | archived

  DateTimeRange? _dateRange;
  bool _attachmentsOnly = false;
  String _statusFilter = 'all'; // all | submitted | reviewed

  List<ReportModel> _reports = [];

  String _formatDateRangeLabel(DateTimeRange? range) {
    if (range == null) return 'Any date';
    final start = DateTime.utc(
      range.start.year,
      range.start.month,
      range.start.day,
    );
    final end = DateTime.utc(range.end.year, range.end.month, range.end.day);
    final s = formatManila(start, 'MMM d, yyyy');
    final e = formatManila(end, 'MMM d, yyyy');
    if (s == e) return s;
    return '$s - $e';
  }

  bool _matchesDateRange(DateTime dt, DateTimeRange range) {
    final manila = toManilaTime(dt);
    final start = DateTime.utc(
      range.start.year,
      range.start.month,
      range.start.day,
      0,
      0,
      0,
      0,
    );
    final end = DateTime.utc(
      range.end.year,
      range.end.month,
      range.end.day,
      23,
      59,
      59,
      999,
    );
    return !manila.isBefore(start) && !manila.isAfter(end);
  }

  List<ReportModel> get _filteredReports {
    var out = _reports;

    if (_statusFilter != 'all') {
      out = out.where((r) => r.status.toLowerCase() == _statusFilter).toList();
    }

    if (_attachmentsOnly) {
      out = out.where((r) => r.attachments.isNotEmpty).toList();
    }

    final range = _dateRange;
    if (range != null) {
      out = out.where((r) => _matchesDateRange(r.submittedAt, range)).toList();
    }

    return out;
  }

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
    if (p.startsWith('/')) return '${ApiConfig.uploadsBaseUrl}$p';
    return '${ApiConfig.uploadsBaseUrl}/$p';
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
      final qName = uri.queryParameters['filename'];
      if (qName != null && qName.trim().isNotEmpty) {
        return qName;
      }
      final segs = uri.pathSegments;
      if (segs.isEmpty) return url;
      return Uri.decodeComponent(segs.last);
    } catch (_) {
      return url;
    }
  }

  bool _isProtectedAttachmentUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.path.startsWith('/api/reports/attachments/');
    } catch (_) {
      return false;
    }
  }

  String _withDownloadQuery(String url, String filename) {
    try {
      final uri = Uri.parse(url);
      final qp = Map<String, String>.from(uri.queryParameters);
      qp['download'] = '1';
      if (filename.trim().isNotEmpty) {
        qp['filename'] = filename.trim();
      }
      return uri.replace(queryParameters: qp).toString();
    } catch (_) {
      return url;
    }
  }

  Future<void> _downloadAttachment(String url, String filename) async {
    Uri uri;
    try {
      uri = Uri.parse(url);
      if (uri.host.isEmpty) {
        throw const FormatException('Invalid URL');
      }
    } catch (_) {
      if (mounted) {
        AppWidgets.showErrorSnackbar(context, 'Invalid attachment URL');
      }
      return;
    }

    try {
      final token = await UserService().getToken();
      final res = await http.get(
        uri,
        headers: {if (token != null) 'Authorization': 'Bearer $token'},
      );
      if (res.statusCode != 200) {
        if (mounted) {
          AppWidgets.showErrorSnackbar(
            context,
            'Failed to download file (${res.statusCode})',
          );
        }
        return;
      }

      final mimeType = (res.headers['content-type'] ?? '').trim();
      await FileDownload.downloadBytes(
        bytes: res.bodyBytes,
        filename: filename,
        mimeType: mimeType.isNotEmpty ? mimeType : 'application/octet-stream',
      );
      if (mounted) {
        AppWidgets.showSuccessSnackbar(context, 'Download started');
      }
    } catch (e) {
      if (mounted) {
        AppWidgets.showErrorSnackbar(
          context,
          AppWidgets.friendlyErrorMessage(
            e,
            fallback: 'Unable to download attachment',
          ),
        );
      }
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
        AppWidgets.showErrorSnackbar(context, 'Invalid attachment URL');
      }
      return;
    }

    // Keep URL encoded; decoding path segments can break URLs with spaces.

    final can = await canLaunchUrl(uri);
    if (!can) {
      if (mounted) {
        AppWidgets.showErrorSnackbar(
          context,
          'No app found to open attachment',
        );
      }
      return;
    }

    final ok = await launchUrl(
      uri,
      mode: LaunchMode.platformDefault,
      webOnlyWindowName: '_blank',
    );
    if (!ok && mounted) {
      AppWidgets.showErrorSnackbar(context, 'Unable to open attachment');
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
                color: Theme.of(context).colorScheme.surface,
                border: Border(
                  bottom: BorderSide(
                    color: Theme.of(
                      context,
                    ).dividerColor.withValues(alpha: 0.35),
                  ),
                ),
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
                    onPressed: () async {
                      if (_isProtectedAttachmentUrl(url)) {
                        final dl = _withDownloadQuery(url, title);
                        await _downloadAttachment(dl, title);
                        return;
                      }
                      await _openUrlExternal(url);
                    },
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
                child: FutureBuilder<String?>(
                  future: UserService().getToken(),
                  builder: (context, snap) {
                    final token = snap.data;
                    return Image.network(
                      url,
                      headers: token != null
                          ? {'Authorization': 'Bearer $token'}
                          : null,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stack) {
                        return Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text('Failed to load image: $error'),
                        );
                      },
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
      final service = ReportService();
      final all = _tab == 'archived'
          ? await service.getArchivedReports(type: type)
          : await service.getCurrentReports(type: type);
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

  Future<void> _toggleArchive(ReportModel r) async {
    if (_isLoading) return;

    final doArchive = _tab != 'archived';
    final actionText = doArchive ? 'Archive' : 'Restore';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$actionText Report'),
        content: Text(
          doArchive
              ? 'Move this report to Archived?'
              : 'Restore this report to Current?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(actionText),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      setState(() {
        _isLoading = true;
      });

      if (doArchive) {
        await ReportService().archiveReport(r.id);
      } else {
        await ReportService().restoreReport(r.id);
      }

      if (!mounted) return;
      AppWidgets.showSuccessSnackbar(
        context,
        doArchive ? 'Report archived' : 'Report restored',
      );
      await _loadReports();
    } catch (e) {
      if (!mounted) return;
      AppWidgets.showErrorSnackbar(
        context,
        AppWidgets.friendlyErrorMessage(e, fallback: 'Failed to update report'),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showReportDetails(ReportModel r) {
    final now = DateTime.now();
    final allowResubmit =
        r.resubmitUntil != null && r.resubmitUntil!.isAfter(now);
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
                formatManila(r.submittedAt, 'yyyy-MM-dd HH:mm'),
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
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).dividerColor.withValues(alpha: 0.35),
                    ),
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
                    final isProtected = _isProtectedAttachmentUrl(url);
                    final downloadUrl = isProtected
                        ? _withDownloadQuery(url, filename)
                        : url;

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: InkWell(
                        onTap: () async {
                          if (isImage) {
                            _showImagePreview(filename, url);
                          } else {
                            if (isProtected) {
                              await _downloadAttachment(downloadUrl, filename);
                            } else {
                              await _openUrlExternal(url);
                            }
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Theme.of(context).colorScheme.outline,
                            ),
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
                                onPressed: () async {
                                  if (!isImage && isProtected) {
                                    await _downloadAttachment(
                                      downloadUrl,
                                      filename,
                                    );
                                    return;
                                  }
                                  await _openUrlExternal(url);
                                },
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
          if (r.type == 'task' && r.taskId != null && allowResubmit)
            FilledButton(
              onPressed: () async {
                final taskId = r.taskId;
                if (taskId == null || taskId.trim().isEmpty) return;
                Navigator.pop(ctx);
                try {
                  final task = await TaskService().getTaskById(taskId);
                  if (!mounted) return;
                  final ok = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (context) => TaskReportScreen(
                        task: task,
                        employeeId: widget.employeeId,
                        existingReportId: r.id,
                        existingReportContent: r.content,
                      ),
                    ),
                  );
                  if (ok == true && mounted) {
                    await _loadReports();
                  }
                } catch (e) {
                  if (!mounted) return;
                  AppWidgets.showErrorSnackbar(
                    context,
                    AppWidgets.friendlyErrorMessage(
                      e,
                      fallback: 'Unable to open resubmission',
                    ),
                  );
                }
              },
              child: const Text('Resubmit'),
            ),
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
    final submitted = formatManila(r.submittedAt, 'yyyy-MM-dd HH:mm');
    final attachments = r.attachments.length;
    final canArchive = r.type == 'task';
    final isArchivedTab = _tab == 'archived';

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.35),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showReportDetails(r),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      r.taskTitle ?? (r.taskId ?? 'Task'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: AppTheme.fontSizeMd,
                        color: AppTheme.textPrimaryColor,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (canArchive)
                    IconButton(
                      tooltip: isArchivedTab ? 'Restore' : 'Archive',
                      onPressed: () => _toggleArchive(r),
                      icon: Icon(
                        isArchivedTab
                            ? Icons.unarchive_outlined
                            : Icons.archive_outlined,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                    label: Text(submitted),
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.08),
                    labelStyle: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.85),
                          fontWeight: FontWeight.w700,
                        ),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  Chip(
                    label: Text('Status: ${r.status}'),
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.08),
                    labelStyle: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.85),
                          fontWeight: FontWeight.w700,
                        ),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  Chip(
                    label: Text('Attachments: $attachments'),
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.08),
                    labelStyle: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.85),
                          fontWeight: FontWeight.w700,
                        ),
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
    final filtered = _filteredReports;

    return AppPage(
      appBarTitle: 'My Reports',
      scroll: false,
      actions: [
        IconButton(
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh),
          onPressed: _loadReports,
        ),
      ],
      padding: const EdgeInsets.fromLTRB(
        AppTheme.lg,
        AppTheme.lg,
        AppTheme.lg,
        AppTheme.xl,
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(AppTheme.md),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              border: Border.all(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.35),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ChoiceChip(
                      label: const Text('Current'),
                      selected: _tab == 'current',
                      onSelected: (sel) {
                        if (!sel) return;
                        setState(() {
                          _tab = 'current';
                        });
                        _loadReports();
                      },
                    ),
                    const SizedBox(width: AppTheme.sm),
                    ChoiceChip(
                      label: const Text('Archived'),
                      selected: _tab == 'archived',
                      onSelected: (sel) {
                        if (!sel) return;
                        setState(() {
                          _tab = 'archived';
                        });
                        _loadReports();
                      },
                    ),
                    const Spacer(),
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
                    const SizedBox(width: AppTheme.sm),
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
                const SizedBox(height: AppTheme.sm),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ChoiceChip(
                        label: Text(_formatDateRangeLabel(_dateRange)),
                        selected: _dateRange != null,
                        onSelected: (_) async {
                          final picked = await showDateRangePicker(
                            context: context,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                            initialDateRange: _dateRange,
                          );
                          if (picked == null) return;
                          if (!mounted) return;
                          setState(() {
                            _dateRange = picked;
                          });
                        },
                      ),
                      const SizedBox(width: AppTheme.sm),
                      ChoiceChip(
                        label: const Text('Attachments'),
                        selected: _attachmentsOnly,
                        onSelected: (sel) {
                          setState(() {
                            _attachmentsOnly = sel;
                          });
                        },
                      ),
                      const SizedBox(width: AppTheme.sm),
                      ChoiceChip(
                        label: const Text('Submitted'),
                        selected: _statusFilter == 'submitted',
                        onSelected: (sel) {
                          setState(() {
                            _statusFilter = sel ? 'submitted' : 'all';
                          });
                        },
                      ),
                      const SizedBox(width: AppTheme.sm),
                      ChoiceChip(
                        label: const Text('Reviewed'),
                        selected: _statusFilter == 'reviewed',
                        onSelected: (sel) {
                          setState(() {
                            _statusFilter = sel ? 'reviewed' : 'all';
                          });
                        },
                      ),
                      const SizedBox(width: AppTheme.sm),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _dateRange = null;
                            _attachmentsOnly = false;
                            _statusFilter = 'all';
                          });
                        },
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppTheme.md),
          Expanded(
            child: _isLoading
                ? AppWidgets.loadingIndicator(message: 'Loading reports...')
                : (_error != null
                      ? AppWidgets.errorMessage(
                          message: _error!,
                          onRetry: _loadReports,
                        )
                      : (filtered.isEmpty
                            ? AppWidgets.emptyState(
                                title: 'No reports',
                                message: _tab == 'archived'
                                    ? 'No archived reports.'
                                    : 'No current reports yet.',
                              )
                            : RefreshIndicator(
                                onRefresh: _loadReports,
                                child: ListView.builder(
                                  padding: EdgeInsets.zero,
                                  itemCount: filtered.length,
                                  itemBuilder: (context, index) {
                                    final r = filtered[index];
                                    return _buildReportCard(r);
                                  },
                                ),
                              ))),
          ),
        ],
      ),
    );
  }
}
