import 'dart:async';
import 'package:flutter/material.dart';
import 'package:field_check/config/api_config.dart';
import 'package:field_check/models/report_model.dart';
import 'package:field_check/models/task_model.dart';
import 'package:field_check/services/report_service.dart';
import 'package:field_check/services/user_service.dart';
import 'package:field_check/utils/app_theme.dart';
import 'package:field_check/utils/file_download/file_download.dart';
import 'package:field_check/utils/manila_time.dart';
import 'package:field_check/widgets/app_page.dart';
import 'package:field_check/widgets/app_widgets.dart';
import 'package:http/http.dart' as http;

class _ResubmitCountdown extends StatefulWidget {
  final DateTime until;

  const _ResubmitCountdown({required this.until});

  @override
  State<_ResubmitCountdown> createState() => _ResubmitCountdownState();
}

class _ResubmitCountdownState extends State<_ResubmitCountdown> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _format(Duration d) {
    var secs = d.inSeconds;
    if (secs <= 0) return '0s';

    final days = secs ~/ 86400;
    secs -= days * 86400;
    final hours = secs ~/ 3600;
    secs -= hours * 3600;
    final mins = secs ~/ 60;
    secs -= mins * 60;

    final parts = <String>[];
    if (days > 0) parts.add('${days}d');
    if (hours > 0 || days > 0) parts.add('${hours}h');
    if (mins > 0 || hours > 0 || days > 0) parts.add('${mins}m');
    parts.add('${secs}s');
    return parts.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.until.difference(DateTime.now());
    final isActive = remaining.inSeconds > 0;
    final text = isActive ? _format(remaining) : 'Expired';

    return Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800),
    );
  }
}

class TaskSubmissionViewerScreen extends StatefulWidget {
  final Task task;
  final String employeeId;

  const TaskSubmissionViewerScreen({
    super.key,
    required this.task,
    required this.employeeId,
  });

  @override
  State<TaskSubmissionViewerScreen> createState() =>
      _TaskSubmissionViewerScreenState();
}

class _TaskSubmissionViewerScreenState
    extends State<TaskSubmissionViewerScreen> {
  bool _loading = true;
  String? _error;
  ReportModel? _report;

  String? _submittedByName;
  final Map<String, int> _contentLengthBytesByUrl = <String, int>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (_submittedByName == null) {
        try {
          final profile = await UserService().getProfile();
          if (mounted) {
            setState(() {
              _submittedByName = profile.name;
            });
          }
        } catch (_) {
          // Best-effort only.
        }
      }

      final reports = await ReportService().getCurrentReports(type: 'task');
      final mine = reports
          .where(
            (r) =>
                r.type == 'task' &&
                r.taskId == widget.task.id &&
                r.employeeId == widget.employeeId,
          )
          .toList();
      mine.sort((a, b) => b.submittedAt.compareTo(a.submittedAt));

      if (!mounted) return;
      setState(() {
        _report = mine.isNotEmpty ? mine.first : null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppWidgets.friendlyErrorMessage(
          e,
          fallback: 'Failed to load submission',
        );
        _loading = false;
      });
    }
  }

  String _normalizeUrl(String rawPath) {
    final p = rawPath.trim();
    if (p.isEmpty) return p;
    if (p.startsWith('http://') || p.startsWith('https://')) return p;
    if (p.startsWith('/api/')) return '${ApiConfig.baseUrl}$p';
    if (p.startsWith('/')) return '${ApiConfig.uploadsBaseUrl}$p';
    return '${ApiConfig.uploadsBaseUrl}/$p';
  }

  Widget _imageNetwork(String url, {BoxFit? fit}) {
    final isProtected = _isProtectedAttachmentUrl(url);
    if (!isProtected) {
      return Image.network(
        url,
        fit: fit,
        errorBuilder: (context, error, stack) {
          return Container(
            color: Colors.black12,
            alignment: Alignment.center,
            child: const Icon(Icons.broken_image_outlined),
          );
        },
      );
    }

    return FutureBuilder<String?>(
      future: UserService().getToken(),
      builder: (context, snapshot) {
        final token = snapshot.data;
        return Image.network(
          url,
          fit: fit,
          headers: {if (token != null) 'Authorization': 'Bearer $token'},
          errorBuilder: (context, error, stack) {
            return Container(
              color: Colors.black12,
              alignment: Alignment.center,
              child: const Icon(Icons.broken_image_outlined),
            );
          },
        );
      },
    );
  }

  bool _isImage(String url) {
    final lower = url.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.gif');
  }

  bool _isBefore(String url) => url.toLowerCase().contains('before_');
  bool _isAfter(String url) => url.toLowerCase().contains('after_');
  bool _isDoc(String url) => url.toLowerCase().contains('doc_');

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

  String _displayFilename(String raw) {
    final name = raw.trim();
    if (name.isEmpty) return name;
    final lower = name.toLowerCase();
    if (lower.startsWith('before_')) return name.substring(7);
    if (lower.startsWith('after_')) return name.substring(6);
    if (lower.startsWith('doc_')) return name.substring(4);
    return name;
  }

  IconData _fileIcon(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.pdf')) return Icons.picture_as_pdf;
    if (lower.endsWith('.xls') || lower.endsWith('.xlsx')) return Icons.grid_on;
    if (lower.endsWith('.doc') || lower.endsWith('.docx')) return Icons.article;
    if (lower.endsWith('.ppt') || lower.endsWith('.pptx')) {
      return Icons.slideshow;
    }
    if (lower.endsWith('.zip') || lower.endsWith('.rar')) {
      return Icons.folder_zip;
    }
    return Icons.insert_drive_file;
  }

  Color _fileIconColor(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.pdf')) return Colors.red;
    if (lower.endsWith('.xls') || lower.endsWith('.xlsx')) return Colors.green;
    if (lower.endsWith('.doc') || lower.endsWith('.docx')) return Colors.blue;
    if (lower.endsWith('.ppt') || lower.endsWith('.pptx')) return Colors.orange;
    return Colors.blueGrey;
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

  String _humanBytes(int bytes) {
    if (bytes <= 0) return '-';
    const units = ['B', 'KB', 'MB', 'GB'];
    var size = bytes.toDouble();
    var i = 0;
    while (size >= 1024 && i < units.length - 1) {
      size /= 1024;
      i++;
    }
    final decimals = i == 0 ? 0 : 1;
    return '${size.toStringAsFixed(decimals)} ${units[i]}';
  }

  Future<int?> _tryFetchContentLengthBytes(String url) async {
    final cached = _contentLengthBytesByUrl[url];
    if (cached != null) return cached;

    Uri uri;
    try {
      uri = Uri.parse(url);
      if (uri.host.isEmpty) return null;
    } catch (_) {
      return null;
    }

    try {
      final token = await UserService().getToken();
      final res = await http.head(
        uri,
        headers: {if (token != null) 'Authorization': 'Bearer $token'},
      );
      if (res.statusCode < 200 || res.statusCode >= 400) return null;

      final raw = (res.headers['content-length'] ?? '').trim();
      final bytes = int.tryParse(raw);
      if (bytes == null || bytes <= 0) return null;
      _contentLengthBytesByUrl[url] = bytes;
      return bytes;
    } catch (_) {
      return null;
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
                      style: const TextStyle(fontWeight: FontWeight.w800),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.7,
              ),
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 4,
                child: _imageNetwork(url, fit: BoxFit.contain),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(String title, Widget child) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTheme.md),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: AppTheme.sm),
          child,
        ],
      ),
    );
  }

  Widget _photoRow(String title, List<String> urls) {
    if (urls.isEmpty) return _empty('No photos uploaded');
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: urls.length,
        separatorBuilder: (context, index) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final u = urls[i];
          return InkWell(
            onTap: () => _showImagePreview(title, u),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 1,
                child: _imageNetwork(u, fit: BoxFit.cover),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _docsList(List<String> urls) {
    if (urls.isEmpty) return _empty('No documents attached');
    return Column(
      children: urls.map((u) {
        final rawFilename = _filenameFromUrl(u);
        final displayName = _displayFilename(rawFilename);
        final isProtected = _isProtectedAttachmentUrl(u);
        final downloadUrl = isProtected
            ? _withDownloadQuery(u, displayName)
            : u;
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            _fileIcon(displayName),
            color: _fileIconColor(displayName),
          ),
          title: Text(
            displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: FutureBuilder<int?>(
            future: _tryFetchContentLengthBytes(downloadUrl),
            builder: (context, snapshot) {
              final bytes = snapshot.data;
              final label = bytes == null
                  ? 'Tap to download'
                  : '${_humanBytes(bytes)} \u2022 Tap to download';
              return Text(label, maxLines: 1, overflow: TextOverflow.ellipsis);
            },
          ),
          onTap: () async {
            await _downloadAttachment(downloadUrl, displayName);
          },
        );
      }).toList(),
    );
  }

  Widget _empty(String text) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final report = _report;
    final now = DateTime.now();
    final allowResubmit =
        report?.resubmitUntil != null && report!.resubmitUntil!.isAfter(now);

    final attachments = (report?.attachments ?? const <String>[])
        .map(_normalizeUrl)
        .where((e) => e.trim().isNotEmpty)
        .toList();

    final beforePhotos = attachments
        .where((u) => _isImage(u) && _isBefore(u))
        .toList();
    final afterPhotos = attachments
        .where((u) => _isImage(u) && _isAfter(u))
        .toList();
    final docs = attachments
        .where(
          (u) => !_isImage(u) && (_isDoc(u) || (!_isBefore(u) && !_isAfter(u))),
        )
        .toList();

    return AppPage(
      appBarTitle: 'Task Submission',
      showBack: true,
      scroll: false,
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
      padding: const EdgeInsets.fromLTRB(
        AppTheme.lg,
        AppTheme.lg,
        AppTheme.lg,
        AppTheme.xl,
      ),
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_error != null)
          ? Center(
              child: AppWidgets.errorMessage(message: _error!, onRetry: _load),
            )
          : ListView(
              children: [
                _card(
                  'Task Header',
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Chip(
                            label: Text(
                              'Due: ${formatManila(task.dueDate, 'yyyy-MM-dd')}',
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                          Chip(
                            label: Text(
                              (task.userTaskStatus ?? task.status).toString(),
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                          if (task.type != null && task.type!.isNotEmpty)
                            Chip(
                              label: Text(task.type!),
                              visualDensity: VisualDensity.compact,
                            ),
                          if (task.difficulty != null &&
                              task.difficulty!.isNotEmpty)
                            Chip(
                              label: Text(task.difficulty!),
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Progress: ${task.progressPercent.clamp(0, 100)}%',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: task.progressPercent.clamp(0, 100) / 100.0,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppTheme.md),
                if (allowResubmit) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.orange.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'Reopened',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Colors.deepOrange,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Resubmission window closes in',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              _ResubmitCountdown(until: report.resubmitUntil!),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppTheme.md),
                ],
                _card(
                  'Written Report',
                  (report == null || report.content.trim().isEmpty)
                      ? _empty('No submission notes found')
                      : SelectableText(
                          report.content.trim(),
                          style: const TextStyle(
                            fontSize: AppTheme.fontSizeMd,
                            height: 1.4,
                          ),
                        ),
                ),
                const SizedBox(height: AppTheme.md),
                _card('Before Photos', _photoRow('Before Photo', beforePhotos)),
                const SizedBox(height: AppTheme.md),
                _card('After Photos', _photoRow('After Photo', afterPhotos)),
                const SizedBox(height: AppTheme.md),
                _card('Attached Documents', _docsList(docs)),
                const SizedBox(height: AppTheme.md),
                _card(
                  'Submission Metadata',
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Submitted by: ${(_submittedByName ?? '').trim().isNotEmpty ? _submittedByName!.trim() : widget.employeeId}',
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Submitted at: ${report != null ? formatManila(report.submittedAt, 'yyyy-MM-dd HH:mm') : '-'}',
                      ),
                      const SizedBox(height: 6),
                      const Text('Location at submission: -'),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
