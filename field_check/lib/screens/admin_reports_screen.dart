// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:field_check/services/geofence_service.dart';
import 'package:field_check/services/report_service.dart';
import 'package:field_check/services/task_service.dart';
import 'package:field_check/models/report_model.dart';
import 'package:field_check/models/task_model.dart';
import 'package:field_check/models/geofence_model.dart';
import 'package:field_check/services/attendance_service.dart';
import 'package:intl/intl.dart';
import 'package:field_check/config/api_config.dart';
import 'package:field_check/services/user_service.dart';
import 'package:field_check/screens/report_export_preview_screen.dart';
import 'package:field_check/screens/admin_employee_history_screen.dart';
import 'package:field_check/widgets/app_widgets.dart';
import 'package:field_check/utils/manila_time.dart';
import 'package:field_check/utils/file_download/file_download.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';

class AdminReportsScreen extends StatefulWidget {
  final String? employeeId;
  final bool embedded;

  const AdminReportsScreen({super.key, this.employeeId, this.embedded = false});

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> {
  List<AttendanceRecord> _attendanceRecords = [];
  List<AttendanceRecord> _archivedAttendanceRecords = [];
  late io.Socket _socket;
  List<ReportModel> _taskReports = [];
  List<ReportModel> _archivedTaskReports = [];
  List<Task> _overdueTasks = [];
  String _viewMode = 'attendance'; // 'attendance' | 'task'
  bool _hasNewTaskReports = false;
  bool _isLoadingTaskReports = false;
  String? _taskReportsError;
  bool _isLoadingOverdueTasks = false;
  String? _overdueTasksError;
  bool _showArchivedReports = false;
  bool _showArchivedAttendance = false;

  String _filterDate = 'All Dates';
  String _filterLocationLabel = 'All Locations';
  String? _filterLocationId;
  final String _filterStatus = 'All Status';
  String _reportStatusFilter = 'All';
  String _attendanceStatusFilter = 'All';
  String _taskDifficultyFilter = 'All';
  bool _taskOverdueOnly = false;
  String _attendanceDateFilter = 'all'; // all, today, week, month, custom
  DateTime? _attendanceStartDate;
  DateTime? _attendanceEndDate;
  String? _filterEmployeeId;
  String? _filterEmployeeName;
  List<Geofence> _geofences = [];
  Timer? _debounce;
  Timer? _realtimeRefreshDebounce;

  final AttendanceService _attendanceService = AttendanceService();
  final TaskService _taskService = TaskService();

  void _openEmployeeHistory(String employeeId, String employeeName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AdminEmployeeHistoryScreen(
          employeeId: employeeId,
          employeeName: employeeName,
        ),
      ),
    );
  }

  ChoiceChip _buildFilterChip({
    required String label,
    required bool selected,
    ValueChanged<bool>? onSelected,
    Color? accentColor,
  }) {
    final theme = Theme.of(context);
    final accent = accentColor ?? theme.colorScheme.primary;
    final isDisabled = onSelected == null;
    final baseLabelColor = selected
        ? accent
        : theme.colorScheme.onSurface.withValues(alpha: 0.75);

    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: onSelected,
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      backgroundColor: theme.colorScheme.surface,
      selectedColor: accent.withValues(alpha: 0.12),
      labelStyle: theme.textTheme.bodySmall?.copyWith(
        fontWeight: FontWeight.w600,
        color: isDisabled
            ? baseLabelColor.withValues(alpha: 0.45)
            : baseLabelColor,
      ),
      shape: StadiumBorder(
        side: BorderSide(
          color: isDisabled
              ? theme.colorScheme.outlineVariant.withValues(alpha: 0.5)
              : selected
              ? accent.withValues(alpha: 0.3)
              : theme.colorScheme.outlineVariant,
        ),
      ),
    );
  }

  Widget _buildMetaChip(String label, {Color? color}) {
    final theme = Theme.of(context);
    final accent = color ?? theme.colorScheme.onSurface;
    return Chip(
      label: Text(label),
      backgroundColor: accent.withValues(alpha: color == null ? 0.06 : 0.12),
      labelStyle: theme.textTheme.bodySmall?.copyWith(
        color: accent.withValues(alpha: color == null ? 0.75 : 0.9),
        fontWeight: FontWeight.w600,
      ),
      shape: StadiumBorder(
        side: BorderSide(color: accent.withValues(alpha: 0.2)),
      ),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildCardAction({required Widget child}) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: child,
    );
  }

  Widget _buildSectionHeader({
    required String title,
    String? subtitle,
    Widget? action,
    Widget? badge,
  }) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  if (badge != null) ...[const SizedBox(width: 8), badge],
                ],
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (action != null) action,
      ],
    );
  }

  Widget _buildCountBadge(String label, {Color? color}) {
    final theme = Theme.of(context);
    final accent = color ?? theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: theme.textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: accent,
        ),
      ),
    );
  }

  Widget _buildOverdueTasksSection() {
    final theme = Theme.of(context);
    if (_isLoadingOverdueTasks) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_overdueTasksError != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Overdue Tasks',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              _overdueTasksError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ),
      );
    }

    if (_overdueTasks.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 8.0),
        child: Text('No overdue tasks'),
      );
    }

    final reportsBase = _showArchivedReports
        ? _archivedTaskReports
        : _taskReports;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(
              title: 'Overdue Tasks',
              subtitle: 'Needs attention before the due date',
              badge: _buildCountBadge(
                '${_overdueTasks.length}',
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 12),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _overdueTasks.length,
              itemBuilder: (context, index) {
                final t = _overdueTasks[index];
                final due = DateFormat(
                  'yyyy-MM-dd',
                ).format(toManilaTime(t.dueDate));
                String assignees;
                if (t.assignedToMultiple.isNotEmpty) {
                  final names = t.assignedToMultiple
                      .map((u) => u.name)
                      .where((n) => n.isNotEmpty)
                      .toList();
                  assignees = names.isNotEmpty
                      ? names.join(', ')
                      : 'Unassigned';
                } else if (t.assignedTo != null &&
                    t.assignedTo!.name.isNotEmpty) {
                  assignees = t.assignedTo!.name;
                } else {
                  assignees = 'Unassigned';
                }

                final hasReports = reportsBase.any((r) => r.taskId == t.id);
                final chipColor = hasReports
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface;

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    title: Text(
                      t.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      'Due $due • $assignees',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.7,
                        ),
                      ),
                    ),
                    onTap: hasReports ? () => _showReportsForTask(t) : null,
                    trailing: Wrap(
                      spacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Chip(
                          label: Text(
                            hasReports ? 'Has reports' : 'No reports yet',
                          ),
                          backgroundColor: chipColor.withValues(alpha: 0.12),
                          labelStyle: theme.textTheme.bodySmall?.copyWith(
                            color: chipColor.withValues(alpha: 0.9),
                            fontWeight: FontWeight.w600,
                          ),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                        _buildCardAction(
                          child: SizedBox(
                            width: 40,
                            height: 40,
                            child: PopupMenuButton<String>(
                              tooltip: 'Actions',
                              padding: EdgeInsets.zero,
                              child: Center(
                                child: Icon(
                                  Icons.more_horiz,
                                  color: theme.colorScheme.onSurface.withValues(
                                    alpha: 0.8,
                                  ),
                                ),
                              ),
                              onSelected: (value) {
                                switch (value) {
                                  case 'viewReports':
                                    if (hasReports) {
                                      _showReportsForTask(t);
                                    } else {
                                      AppWidgets.showWarningSnackbar(
                                        context,
                                        'No reports yet for this task',
                                      );
                                    }
                                    return;
                                  case 'deleteTask':
                                    _confirmAndDeleteTask(t);
                                    return;
                                }
                              },
                              itemBuilder: (ctx) => [
                                const PopupMenuItem(
                                  value: 'viewReports',
                                  child: Text('View reports'),
                                ),
                                const PopupMenuDivider(),
                                const PopupMenuItem(
                                  value: 'deleteTask',
                                  child: Text('Delete task'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String _normalizeAttachmentUrl(String rawPath) {
    final p = rawPath.trim();
    if (p.isEmpty) return p;
    if (p.startsWith('http://') || p.startsWith('https://')) {
      return p;
    }

    if (p.startsWith('/')) return '${ApiConfig.uploadsBaseUrl}$p';
    return '${ApiConfig.uploadsBaseUrl}/$p';
  }

  int _defaultPortForScheme(String scheme) {
    final s = scheme.toLowerCase();
    if (s == 'https') return 443;
    if (s == 'http') return 80;
    return 0;
  }

  String _proxyAttachmentUrl(
    String remoteUrl, {
    bool download = false,
    String? filename,
  }) {
    final base = Uri.parse(ApiConfig.baseUrl);
    final qp = <String, String>{'url': remoteUrl};
    if (download) qp['download'] = '1';
    if (filename != null && filename.trim().isNotEmpty) {
      qp['filename'] = filename.trim();
    }
    return base
        .replace(path: '/api/uploads/proxy', queryParameters: qp)
        .toString();
  }

  String _resolveAttachmentAccessUrl(
    String url, {
    required String filename,
    bool forDownload = false,
  }) {
    try {
      final uri = Uri.parse(url);
      if (uri.host.isEmpty) return url;

      final uploadsBase = Uri.parse(ApiConfig.uploadsBaseUrl);
      final baseHost = uploadsBase.host;
      final basePort = uploadsBase.hasPort
          ? uploadsBase.port
          : _defaultPortForScheme(uploadsBase.scheme);
      final uriPort = uri.hasPort
          ? uri.port
          : _defaultPortForScheme(uri.scheme);

      final isUploads = uri.path.startsWith('/uploads');
      final isReportAttachment = uri.path.startsWith(
        '/api/reports/attachments/',
      );
      final isAppAttachment = isUploads || isReportAttachment;
      final isSameHost =
          uri.scheme == uploadsBase.scheme &&
          uri.host == baseHost &&
          uriPort == basePort;

      if (isUploads &&
          !isSameHost &&
          (baseHost == 'localhost' || baseHost == '127.0.0.1')) {
        return _proxyAttachmentUrl(
          uri.toString(),
          download: forDownload,
          filename: filename,
        );
      }

      Uri finalUri = uri;

      if (isAppAttachment && !isSameHost) {
        finalUri = uri.replace(
          scheme: uploadsBase.scheme,
          host: uploadsBase.host,
          port: uploadsBase.hasPort ? uploadsBase.port : null,
        );
      }

      if (forDownload && isAppAttachment) {
        final qp = Map<String, String>.from(finalUri.queryParameters);
        qp['download'] = '1';
        if (filename.trim().isNotEmpty) {
          qp['filename'] = filename.trim();
        }
        finalUri = finalUri.replace(queryParameters: qp);
      }

      return finalUri.toString();
    } catch (_) {
      return url;
    }
  }

  String _ensureUrlEncoded(String url) {
    try {
      var uri = Uri.parse(url);
      if (uri.host.isEmpty) return url;
      // Encode each path segment (handles spaces and special chars in filenames)
      uri = uri.replace(
        pathSegments: uri.pathSegments.map(Uri.encodeComponent).toList(),
      );
      return uri.toString();
    } catch (_) {
      return url;
    }
  }

  bool _isImagePath(String url) {
    final lower = url.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.gif');
  }

  bool _isLegacyAttachmentUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.path.startsWith('/uploads/');
    } catch (_) {
      return url.contains('/uploads/');
    }
  }

  Future<void> _replaceLegacyAttachment({
    required ReportModel report,
    required String rawOldUrl,
    required int index,
  }) async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        withData: true,
        allowMultiple: false,
      );
      if (picked == null || picked.files.isEmpty) return;

      final file = picked.files.first;
      final bytes = file.bytes;
      if (bytes == null) {
        if (mounted) {
          AppWidgets.showErrorSnackbar(context, 'Unable to read selected file');
        }
        return;
      }

      final newPath = await ReportService().uploadAttachmentBytes(
        bytes: bytes,
        fileName: file.name,
        taskId: report.taskId ?? '',
        employeeId: report.employeeId,
      );

      await ReportService().replaceReportAttachment(
        reportId: report.id,
        oldUrl: rawOldUrl,
        newUrl: newPath,
        index: index,
      );

      await _fetchTaskReports();
      if (mounted) {
        AppWidgets.showSuccessSnackbar(context, 'Attachment replaced');
      }
    } catch (e) {
      if (!mounted) return;
      AppWidgets.showErrorSnackbar(
        context,
        AppWidgets.friendlyErrorMessage(
          e,
          fallback: 'Failed to replace attachment',
        ),
      );
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
          if (res.statusCode == 404 && _isLegacyAttachmentUrl(url)) {
            AppWidgets.showErrorSnackbar(
              context,
              'Legacy attachment missing (Render uploads are not persistent). Use Replace attachment in report details.',
            );
            return;
          }
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
    final safeUrl = _ensureUrlEncoded(url);
    Uri uri;
    try {
      uri = Uri.parse(safeUrl);
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
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
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
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _buildCardAction(
                    child: IconButton(
                      tooltip: 'Open',
                      onPressed: () async {
                        try {
                          final uri = Uri.parse(url);
                          final isProtected = uri.path.startsWith(
                            '/api/reports/attachments/',
                          );
                          if (isProtected) {
                            final dl = _resolveAttachmentAccessUrl(
                              url,
                              filename: title,
                              forDownload: true,
                            );
                            await _downloadAttachment(dl, title);
                          } else {
                            await _openUrlExternal(url);
                          }
                        } catch (_) {
                          await _openUrlExternal(url);
                        }
                      },
                      icon: const Icon(Icons.open_in_new),
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints.tightFor(
                        width: 36,
                        height: 36,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _buildCardAction(
                    child: IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close),
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints.tightFor(
                        width: 36,
                        height: 36,
                      ),
                    ),
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
                        final isLegacy = _isLegacyAttachmentUrl(url);
                        final msg = isLegacy
                            ? 'Legacy attachment missing (Render uploads are not persistent). Use Replace attachment in report details.'
                            : 'Failed to load image: $error';
                        return Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(msg),
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

  Future<void> _toggleArchiveAttendanceRecord(AttendanceRecord record) async {
    try {
      if (_showArchivedAttendance) {
        await _attendanceService.restoreAttendanceRecord(record.id);
        if (mounted) {
          AppWidgets.showSuccessSnackbar(context, 'Attendance record restored');
        }
      } else {
        await _attendanceService.archiveAttendanceRecord(record.id);
        if (mounted) {
          AppWidgets.showSuccessSnackbar(context, 'Attendance record archived');
        }
      }
      await _fetchAttendanceRecords();
    } catch (e) {
      if (!mounted) return;
      AppWidgets.showErrorSnackbar(
        context,
        AppWidgets.friendlyErrorMessage(e, fallback: 'Failed to update record'),
      );
    }
  }

  Future<void> _confirmAndDeleteAttendanceRecord(
    AttendanceRecord record,
  ) async {
    final theme = Theme.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final dialogTheme = Theme.of(ctx);
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Delete Attendance Record',
            style: dialogTheme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          content: const Text(
            'Are you sure you want to delete this attendance record? This cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (ok != true) return;

    try {
      await _attendanceService.deleteAttendanceRecord(record.id);
      await _fetchAttendanceRecords();
      if (mounted) {
        AppWidgets.showSuccessSnackbar(context, 'Attendance record deleted');
      }
    } catch (e) {
      if (!mounted) return;
      AppWidgets.showErrorSnackbar(
        context,
        AppWidgets.friendlyErrorMessage(
          e,
          fallback: 'Failed to delete attendance record',
        ),
      );
    }
  }

  void _showAttendanceDetails(AttendanceRecord record) {
    final theme = Theme.of(context);
    final dtIn = toManilaTime(record.checkInTime);
    final dateStr = DateFormat('yyyy-MM-dd').format(dtIn);
    final timeInStr = DateFormat('HH:mm').format(dtIn);
    final dtOut = record.checkOutTime == null
        ? null
        : toManilaTime(record.checkOutTime!);
    final timeOutStr = dtOut == null ? '-' : DateFormat('HH:mm').format(dtOut);
    final durationStr = record.elapsedHours == null
        ? '-'
        : '${record.elapsedHours!.toStringAsFixed(2)} hours';

    final String status;
    if (record.isVoid && record.autoCheckout) {
      status = 'Auto Checkout (Void)';
    } else if (record.isVoid) {
      status = 'Void';
    } else if (record.checkOutTime == null) {
      status = 'Incomplete';
    } else {
      status = 'Completed';
    }

    final statusColor = status.contains('Auto')
        ? theme.colorScheme.error
        : status == 'Void'
        ? theme.colorScheme.onSurface
        : status == 'Incomplete'
        ? theme.colorScheme.primary
        : theme.colorScheme.secondary;

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Attendance Details',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildMetaChip(status, color: statusColor),
                  if (record.isArchived)
                    _buildMetaChip(
                      'Archived',
                      color: theme.colorScheme.tertiary,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDetailRow(
                      'Employee:',
                      record.employeeName ?? record.userId,
                    ),
                    _buildDetailRow('Location:', record.geofenceName ?? '-'),
                    _buildDetailRow('Date:', dateStr),
                    _buildDetailRow('Check-in:', timeInStr),
                    _buildDetailRow('Check-out:', timeOutStr),
                    _buildDetailRow('Duration:', durationStr),
                    _buildDetailRow('Status:', status),
                    if (record.isVoid && record.voidReason != null)
                      _buildDetailRow('Void reason:', record.voidReason!),
                  ],
                ),
              ),
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

  List<ReportModel> _attendanceSessionToReportModels(AttendanceRecord r) {
    final List<ReportModel> out = [];

    // Always include check-in event for visibility.
    out.add(
      ReportModel(
        id: '${r.id}:in',
        type: 'attendance',
        attendanceId: r.id,
        employeeId: r.userId,
        geofenceId: r.geofenceId,
        content: 'Check In',
        status: 'submitted',
        submittedAt: r.checkInTime,
        employeeName: r.employeeName,
        employeeEmail: r.employeeEmail,
        geofenceName: r.geofenceName,
        isArchived: r.isArchived,
      ),
    );

    // If there's a checkout/void event, include it too.
    final DateTime? dtOut = r.checkOutTime;
    if (dtOut != null) {
      final String outContent;
      if (r.isVoid && r.autoCheckout) {
        outContent = 'Auto Checkout (Void)';
      } else if (r.isVoid) {
        outContent = 'Void';
      } else {
        outContent = 'Check Out';
      }

      out.add(
        ReportModel(
          id: '${r.id}:out',
          type: 'attendance',
          attendanceId: r.id,
          employeeId: r.userId,
          geofenceId: r.geofenceId,
          content: outContent,
          status: 'submitted',
          submittedAt: dtOut,
          employeeName: r.employeeName,
          employeeEmail: r.employeeEmail,
          geofenceName: r.geofenceName,
          isArchived: r.isArchived,
        ),
      );
    }

    return out;
  }

  Future<void> _openFiltersSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateSheet) {
            final theme = Theme.of(context);
            Widget buildSheetSection({
              required String title,
              String? subtitle,
              required Widget child,
            }) {
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.7,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    child,
                  ],
                ),
              );
            }

            Widget buildAttendanceFilters() {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  buildSheetSection(
                    title: 'Date range',
                    subtitle: 'Jump to common attendance windows',
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildFilterChip(
                          label: 'All time',
                          selected: _attendanceDateFilter == 'all',
                          onSelected: (sel) {
                            if (!sel) return;
                            _setAttendanceQuickDateFilter('all');
                          },
                        ),
                        _buildFilterChip(
                          label: 'Today',
                          selected: _attendanceDateFilter == 'today',
                          onSelected: (sel) {
                            if (!sel) return;
                            _setAttendanceQuickDateFilter('today');
                          },
                        ),
                        _buildFilterChip(
                          label: 'This week',
                          selected: _attendanceDateFilter == 'week',
                          onSelected: (sel) {
                            if (!sel) return;
                            _setAttendanceQuickDateFilter('week');
                          },
                        ),
                        _buildFilterChip(
                          label: 'This month',
                          selected: _attendanceDateFilter == 'month',
                          onSelected: (sel) {
                            if (!sel) return;
                            _setAttendanceQuickDateFilter('month');
                          },
                        ),
                        _buildFilterChip(
                          label: 'Custom',
                          selected: _attendanceDateFilter == 'custom',
                          onSelected: (sel) async {
                            if (!sel) return;
                            await _pickAttendanceCustomDateRange();
                            setStateSheet(() {});
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  buildSheetSection(
                    title: 'Location',
                    subtitle: 'Filter by a specific site or geofence',
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(_filterLocationId ?? 'all'),
                      initialValue: _filterLocationId ?? 'all',
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: theme.colorScheme.outlineVariant,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        isDense: true,
                        filled: true,
                        fillColor: theme.colorScheme.surface,
                      ),
                      dropdownColor: theme.colorScheme.surface,
                      items: [
                        const DropdownMenuItem(
                          value: 'all',
                          child: Text('All Locations'),
                        ),
                        ..._geofences
                            .where((g) => (g.id ?? '').isNotEmpty)
                            .map(
                              (g) => DropdownMenuItem(
                                value: g.id ?? '',
                                child: Text(g.name),
                              ),
                            ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          if (value == null ||
                              value == 'all' ||
                              value.isEmpty) {
                            _filterLocationId = null;
                            _filterLocationLabel = 'All Locations';
                          } else {
                            _filterLocationId = value;
                            final match = _geofences.firstWhere(
                              (g) => g.id == value,
                              orElse: () => Geofence(
                                id: value,
                                name: 'Selected Location',
                                address: '',
                                latitude: 0,
                                longitude: 0,
                                radius: 0,
                              ),
                            );
                            _filterLocationLabel = match.name;
                          }
                        });
                        setStateSheet(() {});
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  buildSheetSection(
                    title: 'Status',
                    subtitle: 'Filter by incomplete or void sessions',
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildFilterChip(
                          label: 'All',
                          selected: _attendanceStatusFilter == 'All',
                          onSelected: (sel) {
                            if (!sel) return;
                            setState(() {
                              _attendanceStatusFilter = 'All';
                            });
                            setStateSheet(() {});
                          },
                        ),
                        _buildFilterChip(
                          label: 'Normal',
                          selected: _attendanceStatusFilter == 'Normal',
                          onSelected: (sel) {
                            if (!sel) return;
                            setState(() {
                              _attendanceStatusFilter = 'Normal';
                            });
                            setStateSheet(() {});
                          },
                        ),
                        _buildFilterChip(
                          label: 'Void',
                          selected: _attendanceStatusFilter == 'Void',
                          onSelected: (sel) {
                            if (!sel) return;
                            setState(() {
                              _attendanceStatusFilter = 'Void';
                            });
                            setStateSheet(() {});
                          },
                          accentColor: theme.colorScheme.error,
                        ),
                        _buildFilterChip(
                          label: 'Auto Checkout',
                          selected: _attendanceStatusFilter == 'Auto',
                          onSelected: (sel) {
                            if (!sel) return;
                            setState(() {
                              _attendanceStatusFilter = 'Auto';
                            });
                            setStateSheet(() {});
                          },
                          accentColor: theme.colorScheme.tertiary,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }

            Widget buildTaskFilters() {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  buildSheetSection(
                    title: 'Difficulty',
                    subtitle: 'Filter by task difficulty level',
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildFilterChip(
                          label: 'All difficulties',
                          selected: _taskDifficultyFilter == 'All',
                          onSelected: (sel) {
                            if (!sel) return;
                            setState(() {
                              _taskDifficultyFilter = 'All';
                            });
                            setStateSheet(() {});
                          },
                        ),
                        _buildFilterChip(
                          label: 'Easy',
                          selected: _taskDifficultyFilter == 'easy',
                          onSelected: (sel) {
                            if (!sel) return;
                            setState(() {
                              _taskDifficultyFilter = 'easy';
                            });
                            setStateSheet(() {});
                          },
                        ),
                        _buildFilterChip(
                          label: 'Medium',
                          selected: _taskDifficultyFilter == 'medium',
                          onSelected: (sel) {
                            if (!sel) return;
                            setState(() {
                              _taskDifficultyFilter = 'medium';
                            });
                            setStateSheet(() {});
                          },
                        ),
                        _buildFilterChip(
                          label: 'Hard',
                          selected: _taskDifficultyFilter == 'hard',
                          onSelected: (sel) {
                            if (!sel) return;
                            setState(() {
                              _taskDifficultyFilter = 'hard';
                            });
                            setStateSheet(() {});
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  buildSheetSection(
                    title: 'Report status',
                    subtitle: 'Review state for submitted reports',
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildFilterChip(
                          label: 'All',
                          selected:
                              _reportStatusFilter == 'All' && !_taskOverdueOnly,
                          onSelected: (sel) {
                            if (!sel) return;
                            setState(() {
                              _reportStatusFilter = 'All';
                              _taskOverdueOnly = false;
                            });
                            setStateSheet(() {});
                          },
                        ),
                        _buildFilterChip(
                          label: 'Submitted',
                          selected:
                              _reportStatusFilter == 'submitted' &&
                              !_taskOverdueOnly,
                          onSelected: (sel) {
                            if (!sel) return;
                            setState(() {
                              _reportStatusFilter = 'submitted';
                              _taskOverdueOnly = false;
                            });
                            setStateSheet(() {});
                          },
                        ),
                        _buildFilterChip(
                          label: 'Reviewed',
                          selected:
                              _reportStatusFilter == 'reviewed' &&
                              !_taskOverdueOnly,
                          onSelected: (sel) {
                            if (!sel) return;
                            setState(() {
                              _reportStatusFilter = 'reviewed';
                              _taskOverdueOnly = false;
                            });
                            setStateSheet(() {});
                          },
                        ),
                        _buildFilterChip(
                          label: 'Overdue only',
                          selected: _taskOverdueOnly,
                          onSelected: _showArchivedReports
                              ? null
                              : (sel) {
                                  setState(() {
                                    _taskOverdueOnly = sel;
                                    if (sel) {
                                      _reportStatusFilter = 'All';
                                    }
                                  });
                                  setStateSheet(() {});
                                },
                          accentColor: theme.colorScheme.error,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 8,
                  bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Filters',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            setState(() {
                              _attendanceDateFilter = 'all';
                              _attendanceStartDate = null;
                              _attendanceEndDate = null;
                              _filterDate = 'All Dates';
                              _attendanceStatusFilter = 'All';
                              _reportStatusFilter = 'All';
                              _taskDifficultyFilter = 'All';
                              _taskOverdueOnly = false;
                            });
                            setStateSheet(() {});
                            _fetchAttendanceRecords();
                            _fetchTaskReports();
                          },
                          icon: const Icon(Icons.restart_alt),
                          label: const Text('Reset'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _viewMode == 'attendance'
                          ? 'Refine attendance records instantly'
                          : 'Filter task reports with quick selectors',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.7,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_viewMode == 'attendance')
                      buildAttendanceFilters()
                    else
                      buildTaskFilters(),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.check_circle_outline),
                            label: const Text('Done'),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    // Set employee filter if provided
    if (widget.employeeId != null) {
      _filterEmployeeId = widget.employeeId;
    }
    _fetchGeofences();
    _fetchAttendanceRecords();
    _fetchTaskReports();
    _fetchOverdueTasks();
    _initSocket();
  }

  @override
  void dispose() {
    _socket.disconnect();
    _debounce?.cancel();
    _realtimeRefreshDebounce?.cancel();
    super.dispose();
  }

  void _scheduleRealtimeRefresh({bool includeOverdue = true}) {
    _realtimeRefreshDebounce?.cancel();
    _realtimeRefreshDebounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      _fetchTaskReports();
      if (includeOverdue) {
        _fetchOverdueTasks();
      }
    });
  }

  Future<void> _initSocket() async {
    final base = ApiConfig.baseUrl;
    final token = await UserService().getToken();
    final options = io.OptionBuilder()
        .setTransports(['websocket'])
        .enableAutoConnect()
        .setTimeout(20000)
        .build();
    if (token != null) {
      options['extraHeaders'] = {'Authorization': 'Bearer $token'};
    }
    options['reconnection'] = true;
    options['reconnectionAttempts'] = 999999;
    options['reconnectionDelay'] = 500;
    options['reconnectionDelayMax'] = 10000;
    _socket = io.io(base, options);

    _socket.onConnect((_) => debugPrint('Connected to Socket.IO'));
    _socket.onDisconnect((_) => debugPrint('Disconnected from Socket.IO'));
    _socket.onConnectError(
      (err) => debugPrint('Socket.IO Connect Error: $err'),
    );
    _socket.onError((err) => debugPrint('Socket.IO Error: $err'));
    _socket.on(
      'reconnect_attempt',
      (_) => debugPrint('Reports socket reconnect attempt'),
    );
    _socket.on('reconnect', (_) => debugPrint('Reports socket reconnected'));
    _socket.on(
      'reconnect_error',
      (err) => debugPrint('Reports socket reconnect error: $err'),
    );
    _socket.on(
      'reconnect_failed',
      (_) => debugPrint('Reports socket reconnect failed'),
    );

    _socket.on('newAttendanceRecord', (data) {
      debugPrint('New attendance record: $data');
      _fetchAttendanceRecords();
    });

    _socket.on('updatedAttendanceRecord', (data) {
      debugPrint('Attendance record updated: $data');
      _fetchAttendanceRecords();
    });

    _socket.on('newReport', (_) {
      setState(() {
        _hasNewTaskReports = true;
      });
      // Always fetch reports in real-time for all admins
      _fetchTaskReports();
    });

    _socket.on('updatedReport', (_) {
      // Always fetch reports in real-time for all admins
      _fetchTaskReports();
    });

    _socket.on('deletedReport', (_) {
      // Always fetch reports in real-time for all admins
      _fetchTaskReports();
    });

    _socket.on('reportArchived', (_) {
      _fetchTaskReports();
    });

    _socket.on('reportRestored', (_) {
      _fetchTaskReports();
    });

    _socket.on('taskAssignedToMultiple', (data) {
      debugPrint('Task assigned to multiple: $data');
      _scheduleRealtimeRefresh();
    });

    _socket.on('taskUnassigned', (data) {
      debugPrint('Task unassigned: $data');
      _scheduleRealtimeRefresh();
    });

    _socket.on('userTaskArchived', (data) {
      debugPrint('User task archived: $data');
      _scheduleRealtimeRefresh();
    });

    _socket.on('userTaskRestored', (data) {
      debugPrint('User task restored: $data');
      _scheduleRealtimeRefresh();
    });

    _socket.on('taskCompleted', (data) {
      debugPrint('Task completed event: $data');
      _fetchAttendanceRecords();
      if (_viewMode == 'task') {
        _fetchTaskReports();
      }
    });
  }

  Future<void> _fetchGeofences() async {
    try {
      final geofences = await GeofenceService().fetchGeofences();
      if (!mounted) return;
      setState(() {
        _geofences = geofences;
      });
    } catch (e) {
      debugPrint('Error fetching geofences: $e');
    }
  }

  Future<void> _fetchAttendanceRecords() async {
    try {
      debugPrint(
        'Fetching attendance records with filters: date=$_filterDate, location=$_filterLocationLabel, status=$_filterStatus',
      );
      final records = await _attendanceService.getAttendanceRecords(
        employeeId: _filterEmployeeId,
      );
      final current = records.where((r) => !r.isArchived).toList()
        ..sort((a, b) => b.checkInTime.compareTo(a.checkInTime));
      final archived = records.where((r) => r.isArchived).toList()
        ..sort((a, b) => b.checkInTime.compareTo(a.checkInTime));

      debugPrint(
        '✓ Fetched ${records.length} attendance records (current=${current.length}, archived=${archived.length})',
      );
      setState(() {
        _attendanceRecords = current;
        _archivedAttendanceRecords = archived;
      });
    } catch (e) {
      debugPrint('✗ Error fetching attendance records: $e');
      setState(() {
        _attendanceRecords = [];
        _archivedAttendanceRecords = [];
      });
    }
  }

  Future<void> _fetchOverdueTasks() async {
    setState(() {
      _isLoadingOverdueTasks = true;
      _overdueTasksError = null;
    });
    try {
      final tasks = await _taskService.getOverdueTasks();
      setState(() {
        _overdueTasks = tasks;
        _isLoadingOverdueTasks = false;
      });
    } catch (e) {
      debugPrint('Error fetching overdue tasks: $e');
      setState(() {
        _isLoadingOverdueTasks = false;
        _overdueTasksError = 'Failed to load overdue tasks: $e';
        _overdueTasks = [];
      });
    }
  }

  Future<void> _fetchTaskReports() async {
    setState(() {
      _isLoadingTaskReports = true;
      _taskReportsError = null;
    });
    try {
      if (_showArchivedReports) {
        final reports = await ReportService().getArchivedReports(type: 'task');
        final overdueCount = reports
            .where((r) => r.taskIsOverdue == true)
            .length;
        debugPrint(
          'Task reports (archived): total=${reports.length}, overdue=$overdueCount',
        );
        setState(() {
          _archivedTaskReports = reports;
          _isLoadingTaskReports = false;
        });
      } else {
        final reports = await ReportService().getCurrentReports(type: 'task');
        final overdueCount = reports
            .where((r) => r.taskIsOverdue == true)
            .length;
        debugPrint(
          'Task reports (current): total=${reports.length}, overdue=$overdueCount',
        );
        setState(() {
          _taskReports = reports;
          _isLoadingTaskReports = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching task reports: $e');
      setState(() {
        _isLoadingTaskReports = false;
        _taskReportsError = 'Failed to load reports: $e';
      });
    }
  }

  List<ReportModel> _filteredTaskReports() {
    final base = _showArchivedReports ? _archivedTaskReports : _taskReports;
    var filtered = base;

    // Filter by employee if specified
    if (_filterEmployeeId != null) {
      filtered = filtered
          .where((r) => r.employeeId == _filterEmployeeId)
          .toList();
      _filterEmployeeName = filtered.isNotEmpty
          ? filtered.first.employeeName
          : null;
    }

    // Filter by report status (only when not in overdue-only mode)
    if (_reportStatusFilter != 'All' && !_taskOverdueOnly) {
      filtered = filtered
          .where(
            (r) => r.status.toLowerCase() == _reportStatusFilter.toLowerCase(),
          )
          .toList();
    }

    // Filter by task difficulty (for task reports)
    if (_taskDifficultyFilter != 'All') {
      final target = _taskDifficultyFilter.toLowerCase();
      filtered = filtered
          .where((r) => (r.taskDifficulty ?? '').toLowerCase() == target)
          .toList();
    }

    // Filter by overdue-only, based on underlying task state
    if (_taskOverdueOnly) {
      filtered = filtered.where((r) => r.taskIsOverdue == true).toList();
    }

    final list = filtered.toList();
    if (_showArchivedReports) {
      // Archived: keep a predictable sort (newest first)
      list.sort((a, b) => b.submittedAt.compareTo(a.submittedAt));
    } else {
      // Current: show overdue items first, then newest first
      list.sort((a, b) {
        final ao = a.taskIsOverdue == true ? 1 : 0;
        final bo = b.taskIsOverdue == true ? 1 : 0;
        if (ao != bo) {
          return bo.compareTo(ao); // overdue first
        }
        return b.submittedAt.compareTo(a.submittedAt); // newest first
      });
    }

    return list;
  }

  int _getOpenCheckInsCount() {
    // Open session = no checkout time and not voided.
    return _attendanceRecords
        .where((r) => r.isVoid || r.checkOutTime == null)
        .length;
  }

  List<AttendanceRecord> get _filteredAttendanceRecords {
    final base = _showArchivedAttendance
        ? _archivedAttendanceRecords
        : _attendanceRecords;

    Iterable<AttendanceRecord> result = base;

    if (_attendanceStartDate != null || _attendanceEndDate != null) {
      result = result.where((record) {
        final dt = toManilaTime(record.checkInTime);

        if (_attendanceStartDate != null &&
            dt.isBefore(_attendanceStartDate!)) {
          return false;
        }
        if (_attendanceEndDate != null && !dt.isBefore(_attendanceEndDate!)) {
          return false;
        }
        return true;
      });
    }

    if (_filterLocationId != null) {
      result = result.where((record) => record.geofenceId == _filterLocationId);
    }

    return result.where((record) {
      switch (_attendanceStatusFilter) {
        case 'Normal':
          return !record.isVoid;
        case 'Void':
          return record.isVoid && !record.autoCheckout;
        case 'Auto':
          return record.isVoid && record.autoCheckout;
        default:
          return true;
      }
    }).toList();
  }

  void _setAttendanceQuickDateFilter(String value) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);

    DateTime? start;
    DateTime? endExclusive;
    String label = 'All Dates';

    switch (value) {
      case 'today':
        start = todayStart;
        endExclusive = todayStart.add(const Duration(days: 1));
        label = DateFormat('yyyy-MM-dd').format(todayStart);
        break;
      case 'week':
        final weekday = todayStart.weekday; // Monday = 1
        start = todayStart.subtract(Duration(days: weekday - 1));
        endExclusive = start.add(const Duration(days: 7));
        final endInclusive = endExclusive.subtract(const Duration(days: 1));
        label =
            'Week of ${DateFormat('yyyy-MM-dd').format(start)} - ${DateFormat('yyyy-MM-dd').format(endInclusive)}';
        break;
      case 'month':
        start = DateTime(todayStart.year, todayStart.month, 1);
        final nextMonth = todayStart.month == 12
            ? DateTime(todayStart.year + 1, 1, 1)
            : DateTime(todayStart.year, todayStart.month + 1, 1);
        endExclusive = nextMonth;
        label = DateFormat('MMMM yyyy').format(start);
        break;
      case 'all':
      default:
        start = null;
        endExclusive = null;
        label = 'All Dates';
        break;
    }

    setState(() {
      _attendanceDateFilter = value;
      _attendanceStartDate = start;
      _attendanceEndDate = endExclusive;
      _filterDate = label;
    });
  }

  Future<void> _pickAttendanceCustomDateRange() async {
    final now = DateTime.now();
    final baseStart = _attendanceStartDate ?? DateTime(now.year, now.month, 1);
    final baseEnd = _attendanceEndDate != null
        ? _attendanceEndDate!.subtract(const Duration(days: 1))
        : DateTime(now.year, now.month, now.day);

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1),
      initialDateRange: DateTimeRange(start: baseStart, end: baseEnd),
    );

    if (picked == null) return;

    final start = DateTime(
      picked.start.year,
      picked.start.month,
      picked.start.day,
    );
    final endExclusive = DateTime(
      picked.end.year,
      picked.end.month,
      picked.end.day,
    ).add(const Duration(days: 1));

    setState(() {
      _attendanceDateFilter = 'custom';
      _attendanceStartDate = start;
      _attendanceEndDate = endExclusive;
      _filterDate =
          '${DateFormat('yyyy-MM-dd').format(picked.start)} - ${DateFormat('yyyy-MM-dd').format(picked.end)}';
    });
  }

  @override
  Widget build(BuildContext context) {
    const brandColor = Color(0xFF2688d4);
    final theme = Theme.of(context);

    String formatTime(DateTime? dt) =>
        dt == null ? '-' : formatManila(dt, 'HH:mm');

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // View toggle
                Row(
                  children: [
                    ChoiceChip(
                      label: const Text('Attendance'),
                      selected: _viewMode == 'attendance',
                      onSelected: (sel) {
                        if (!sel) return;
                        setState(() {
                          _viewMode = 'attendance';
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Task Reports'),
                          if (_hasNewTaskReports)
                            Padding(
                              padding: const EdgeInsets.only(left: 6.0),
                              child: SizedBox(
                                width: 8,
                                height: 8,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.error,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      selected: _viewMode == 'task',
                      onSelected: (sel) async {
                        if (!sel) return;
                        setState(() {
                          _viewMode = 'task';
                          _hasNewTaskReports = false;
                        });
                        await _fetchTaskReports();
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Current'),
                      selected: _viewMode == 'attendance'
                          ? !_showArchivedAttendance
                          : !_showArchivedReports,
                      onSelected: (sel) async {
                        if (!sel) return;
                        if (_viewMode == 'attendance') {
                          setState(() {
                            _showArchivedAttendance = false;
                          });
                          await _fetchAttendanceRecords();
                          return;
                        }
                        setState(() {
                          _showArchivedReports = false;
                        });
                        await _fetchTaskReports();
                      },
                    ),
                    ChoiceChip(
                      label: const Text('Archived'),
                      selected: _viewMode == 'attendance'
                          ? _showArchivedAttendance
                          : _showArchivedReports,
                      onSelected: (sel) async {
                        if (!sel) return;
                        if (_viewMode == 'attendance') {
                          setState(() {
                            _showArchivedAttendance = true;
                          });
                          await _fetchAttendanceRecords();
                          return;
                        }
                        setState(() {
                          _showArchivedReports = true;
                          _taskOverdueOnly = false;
                        });
                        await _fetchTaskReports();
                      },
                    ),
                  ],
                ),

                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: Row(
                    children: [
                      FilledButton.icon(
                        onPressed: _openFiltersSheet,
                        icon: const Icon(Icons.tune),
                        label: const Text('Filters'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _viewMode == 'attendance'
                              ? 'Showing: ${_showArchivedAttendance ? 'Archived' : 'Current'} • $_filterDate • $_filterLocationLabel • $_attendanceStatusFilter'
                              : 'Showing: ${_showArchivedReports ? 'Archived' : 'Current'} • $_taskDifficultyFilter • $_reportStatusFilter',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.7),
                              ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: Theme(
                    data: theme.copyWith(
                      dividerColor: Colors.transparent,
                      splashColor: Colors.transparent,
                      highlightColor: Colors.transparent,
                    ),
                    child: ExpansionTile(
                      tilePadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 2,
                      ),
                      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      leading: Icon(
                        Icons.filter_alt_outlined,
                        color: theme.colorScheme.primary,
                      ),
                      title: Text(
                        'Quick filters',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        _viewMode == 'attendance'
                            ? 'Jump to common date ranges'
                            : 'Common report statuses',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.7,
                          ),
                        ),
                      ),
                      children: [
                        if (_viewMode == 'attendance')
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _buildFilterChip(
                                label: 'All time',
                                selected: _attendanceDateFilter == 'all',
                                onSelected: (sel) {
                                  if (!sel) return;
                                  _setAttendanceQuickDateFilter('all');
                                },
                              ),
                              _buildFilterChip(
                                label: 'Today',
                                selected: _attendanceDateFilter == 'today',
                                onSelected: (sel) {
                                  if (!sel) return;
                                  _setAttendanceQuickDateFilter('today');
                                },
                              ),
                              _buildFilterChip(
                                label: 'This week',
                                selected: _attendanceDateFilter == 'week',
                                onSelected: (sel) {
                                  if (!sel) return;
                                  _setAttendanceQuickDateFilter('week');
                                },
                              ),
                              _buildFilterChip(
                                label: 'This month',
                                selected: _attendanceDateFilter == 'month',
                                onSelected: (sel) {
                                  if (!sel) return;
                                  _setAttendanceQuickDateFilter('month');
                                },
                              ),
                            ],
                          )
                        else
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _buildFilterChip(
                                label: 'Submitted',
                                selected: _reportStatusFilter == 'submitted',
                                onSelected: (sel) {
                                  if (!sel) return;
                                  setState(() {
                                    _reportStatusFilter = 'submitted';
                                  });
                                },
                              ),
                              _buildFilterChip(
                                label: 'Reviewed',
                                selected: _reportStatusFilter == 'reviewed',
                                onSelected: (sel) {
                                  if (!sel) return;
                                  setState(() {
                                    _reportStatusFilter = 'reviewed';
                                  });
                                },
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                if (_viewMode == 'attendance')
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          title: 'Sessions',
                          value: _attendanceRecords.length.toString(),
                          icon: Icons.list_alt,
                          color: brandColor,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildStatCard(
                          title: 'Void/Incomplete check-ins',
                          value: _getOpenCheckInsCount().toString(),
                          icon: Icons.login,
                          color: Colors.teal,
                        ),
                      ),
                    ],
                  ),

                if (_viewMode == 'attendance') const SizedBox(height: 12),

                if (_viewMode == 'attendance')
                  (!_showArchivedAttendance
                          ? _attendanceRecords.isEmpty
                          : _archivedAttendanceRecords.isEmpty)
                      ? Center(
                          child: Text(
                            _showArchivedAttendance
                                ? 'No archived attendance records'
                                : 'No attendance records',
                          ),
                        )
                      : Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(
                              color: Theme.of(
                                context,
                              ).colorScheme.outlineVariant,
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                return SizedBox(
                                  width: constraints.maxWidth,
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(
                                        minWidth: constraints.maxWidth,
                                      ),
                                      child: DataTable(
                                        columns: const [
                                          DataColumn(label: Text('Employee')),
                                          DataColumn(label: Text('Location')),
                                          DataColumn(label: Text('Date')),
                                          DataColumn(label: Text('In')),
                                          DataColumn(label: Text('Out')),
                                          DataColumn(label: Text('Status')),
                                          DataColumn(label: Text('Actions')),
                                        ],
                                        rows: _filteredAttendanceRecords.map((
                                          record,
                                        ) {
                                          String status;
                                          Color? chipBg;
                                          Color? chipFg;

                                          if (record.isVoid &&
                                              record.autoCheckout) {
                                            status = 'Auto Checkout (Void)';
                                            chipBg = Theme.of(context)
                                                .colorScheme
                                                .error
                                                .withValues(alpha: 0.12);
                                            chipFg = Theme.of(
                                              context,
                                            ).colorScheme.error;
                                          } else if (record.isVoid) {
                                            status = 'Void';
                                            chipBg = Theme.of(context)
                                                .colorScheme
                                                .onSurface
                                                .withValues(alpha: 0.12);
                                            chipFg = Theme.of(context)
                                                .colorScheme
                                                .onSurface
                                                .withValues(alpha: 0.85);
                                          } else if (record.checkOutTime ==
                                              null) {
                                            status = 'Incomplete';
                                            chipBg = Theme.of(context)
                                                .colorScheme
                                                .primary
                                                .withValues(alpha: 0.12);
                                            chipFg = Theme.of(
                                              context,
                                            ).colorScheme.primary;
                                          } else {
                                            status = 'Completed';
                                            chipBg = Theme.of(context)
                                                .colorScheme
                                                .secondary
                                                .withValues(alpha: 0.12);
                                            chipFg = Theme.of(
                                              context,
                                            ).colorScheme.secondary;
                                          }

                                          final date = formatManila(
                                            record.checkInTime,
                                            'yyyy-MM-dd',
                                          );

                                          final timeIn = formatTime(
                                            record.checkInTime,
                                          );
                                          final timeOut = formatTime(
                                            record.checkOutTime,
                                          );

                                          return DataRow(
                                            cells: [
                                              DataCell(
                                                Text(
                                                  record.employeeName ??
                                                      'Unknown',
                                                ),
                                              ),
                                              DataCell(
                                                Text(
                                                  record.geofenceName ?? 'N/A',
                                                ),
                                              ),
                                              DataCell(Text(date)),
                                              DataCell(Text(timeIn)),
                                              DataCell(Text(timeOut)),
                                              DataCell(
                                                Chip(
                                                  label: Text(status),
                                                  backgroundColor: chipBg,
                                                  labelStyle: TextStyle(
                                                    color: chipFg,
                                                  ),
                                                ),
                                              ),
                                              DataCell(
                                                _buildCardAction(
                                                  child: SizedBox(
                                                    width: 40,
                                                    height: 40,
                                                    child: PopupMenuButton<String>(
                                                      tooltip: 'Actions',
                                                      padding: EdgeInsets.zero,
                                                      child: Center(
                                                        child: Icon(
                                                          Icons.more_horiz,
                                                          color: theme
                                                              .colorScheme
                                                              .onSurface
                                                              .withValues(
                                                                alpha: 0.8,
                                                              ),
                                                        ),
                                                      ),
                                                      onSelected: (value) async {
                                                        switch (value) {
                                                          case 'view':
                                                            _showAttendanceDetails(
                                                              record,
                                                            );
                                                            return;
                                                          case 'history':
                                                            Navigator.push(
                                                              context,
                                                              MaterialPageRoute(
                                                                builder: (context) => AdminEmployeeHistoryScreen(
                                                                  employeeId:
                                                                      record
                                                                          .userId,
                                                                  employeeName:
                                                                      record
                                                                          .employeeName ??
                                                                      'Unknown',
                                                                ),
                                                              ),
                                                            );
                                                            return;
                                                          case 'archive':
                                                            await _toggleArchiveAttendanceRecord(
                                                              record,
                                                            );
                                                            return;
                                                          case 'delete':
                                                            await _confirmAndDeleteAttendanceRecord(
                                                              record,
                                                            );
                                                            return;
                                                        }
                                                      },
                                                      itemBuilder: (ctx) =>
                                                          <
                                                            PopupMenuEntry<
                                                              String
                                                            >
                                                          >[
                                                            const PopupMenuItem(
                                                              value: 'view',
                                                              child: Text(
                                                                'View details',
                                                              ),
                                                            ),
                                                            const PopupMenuItem(
                                                              value: 'history',
                                                              child: Text(
                                                                'View history',
                                                              ),
                                                            ),
                                                            PopupMenuItem(
                                                              value: 'archive',
                                                              child: Text(
                                                                _showArchivedAttendance
                                                                    ? 'Restore'
                                                                    : 'Archive',
                                                              ),
                                                            ),
                                                            const PopupMenuDivider(),
                                                            const PopupMenuItem(
                                                              value: 'delete',
                                                              child: Text(
                                                                'Delete',
                                                              ),
                                                            ),
                                                          ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          );
                                        }).toList(),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),

                if (_viewMode == 'task') _buildTaskReportsView(),
              ],
            ),
          ),
        ),
      ],
    );

    if (widget.embedded) {
      return LayoutBuilder(
        builder: (context, constraints) {
          const maxDesktopWidth = 1280.0;
          final maxWidth = constraints.hasBoundedWidth
              ? (constraints.maxWidth < maxDesktopWidth
                    ? constraints.maxWidth
                    : maxDesktopWidth)
              : maxDesktopWidth;

          final centered = Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: content,
            ),
          );

          if (constraints.hasBoundedHeight && constraints.hasBoundedWidth) {
            return SizedBox(
              width: constraints.maxWidth,
              height: constraints.maxHeight,
              child: centered,
            );
          }

          return centered;
        },
      );
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Admin Reports',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onPrimary,
              ),
            ),
            if (_filterEmployeeId != null)
              Text(
                'Filtered: ${_filterEmployeeName ?? _filterEmployeeId}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onPrimary.withValues(alpha: 0.85),
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
        backgroundColor: brandColor,
        actions: [
          if (_filterEmployeeId != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _filterEmployeeId = null;
                    _filterEmployeeName = null;
                  });
                },
                icon: const Icon(Icons.clear),
                label: const Text('Clear Filter'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.surface,
                  foregroundColor: theme.colorScheme.error,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  textStyle: const TextStyle(fontWeight: FontWeight.w700),
                  shape: const StadiumBorder(),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: ElevatedButton.icon(
              onPressed: _exportReport,
              icon: const Icon(Icons.download),
              label: const Text('Export'),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.surface,
                foregroundColor: brandColor,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
                shape: const StadiumBorder(),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(child: content),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    final theme = Theme.of(context);
    final surface = theme.colorScheme.surface;
    final tint = color.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.18 : 0.08,
    );
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(color: Color.alphaBlend(tint, surface)),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                    border: Border.all(color: color.withValues(alpha: 0.3)),
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.85,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _dialogWidthFor(BuildContext context) {
    final screen = MediaQuery.sizeOf(context).width;
    final available = screen - 32;
    return available.clamp(320, 860).toDouble();
  }

  void _showReportDetails(ReportModel r) {
    showDialog(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final dialogWidth = _dialogWidthFor(ctx);
        final isWide = MediaQuery.sizeOf(ctx).width >= 900;
        final actionSize = isWide ? 44.0 : 36.0;
        return AlertDialog(
          insetPadding: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            r.taskTitle ?? 'Report Details',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          content: SizedBox(
            width: dialogWidth,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildReportStatusChip(r.status),
                      if (r.taskIsOverdue)
                        _buildMetaChip(
                          'Overdue',
                          color: theme.colorScheme.error,
                        ),
                      _buildMetaChip(
                        formatManila(r.submittedAt, 'yyyy-MM-dd HH:mm'),
                      ),
                      _buildMetaChip('Attachments: ${r.attachments.length}'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildDetailRow(
                          'Employee:',
                          r.employeeName ?? r.employeeId,
                        ),
                        _buildDetailRow(
                          'Task:',
                          r.taskTitle ?? (r.taskId ?? '-'),
                        ),
                        _buildDetailRow('Status:', r.status),
                        _buildDetailRow(
                          'Submitted:',
                          formatManila(r.submittedAt, 'yyyy-MM-dd HH:mm'),
                        ),
                      ],
                    ),
                  ),
                  if (r.content.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Content',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant,
                        ),
                      ),
                      child: SelectableText(
                        r.content,
                        style: theme.textTheme.bodySmall?.copyWith(
                          height: 1.35,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.85,
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (r.attachments.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Attachments',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: r.attachments.asMap().entries.map((entry) {
                        final i = entry.key;
                        final rawPath = entry.value;
                        final normalized = _normalizeAttachmentUrl(rawPath);
                        final url = _ensureUrlEncoded(normalized);
                        final filename = _filenameFromUrl(url);
                        final accessUrl = _resolveAttachmentAccessUrl(
                          url,
                          filename: filename,
                        );
                        final downloadUrl = _resolveAttachmentAccessUrl(
                          url,
                          filename: filename,
                          forDownload: true,
                        );
                        final isImage = _isImagePath(url);
                        final isLegacy = _isLegacyAttachmentUrl(url);

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: InkWell(
                            onTap: () async {
                              if (isImage) {
                                _showImagePreview(filename, accessUrl);
                                return;
                              }
                              try {
                                final uri = Uri.parse(accessUrl);
                                final isProtected = uri.path.startsWith(
                                  '/api/reports/attachments/',
                                );
                                if (isProtected) {
                                  await _downloadAttachment(
                                    downloadUrl,
                                    filename,
                                  );
                                  return;
                                }
                              } catch (_) {}
                              await _openUrlExternal(accessUrl);
                            },
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: theme.colorScheme.outlineVariant,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    isImage
                                        ? Icons.image
                                        : Icons.insert_drive_file,
                                    color: isImage
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.onSurface
                                              .withValues(alpha: 0.8),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          filename,
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                              ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          url,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color: theme
                                                    .colorScheme
                                                    .onSurface
                                                    .withValues(alpha: 0.7),
                                              ),
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  _buildCardAction(
                                    child: SizedBox(
                                      width: actionSize,
                                      height: actionSize,
                                      child: PopupMenuButton<String>(
                                        tooltip: 'Attachment actions',
                                        padding: EdgeInsets.zero,
                                        child: Center(
                                          child: Icon(
                                            Icons.more_vert,
                                            color: theme.colorScheme.onSurface
                                                .withValues(alpha: 0.8),
                                          ),
                                        ),
                                        onSelected: (value) async {
                                          switch (value) {
                                            case 'preview':
                                              _showImagePreview(
                                                filename,
                                                accessUrl,
                                              );
                                              return;
                                            case 'open':
                                              try {
                                                final uri = Uri.parse(
                                                  accessUrl,
                                                );
                                                final isProtected = uri.path
                                                    .startsWith(
                                                      '/api/reports/attachments/',
                                                    );
                                                if (!isImage && isProtected) {
                                                  await _downloadAttachment(
                                                    downloadUrl,
                                                    filename,
                                                  );
                                                  return;
                                                }
                                              } catch (_) {}
                                              await _openUrlExternal(accessUrl);
                                              return;
                                            case 'download':
                                              await _downloadAttachment(
                                                downloadUrl,
                                                filename,
                                              );
                                              return;
                                            case 'replace':
                                              await _replaceLegacyAttachment(
                                                report: r,
                                                rawOldUrl: rawPath,
                                                index: i,
                                              );
                                              return;
                                            case 'copy':
                                              await Clipboard.setData(
                                                ClipboardData(text: accessUrl),
                                              );
                                              if (!mounted) return;
                                              AppWidgets.showSuccessSnackbar(
                                                context,
                                                'Link copied',
                                              );
                                              return;
                                          }
                                        },
                                        itemBuilder: (ctx) =>
                                            <PopupMenuEntry<String>>[
                                              if (isImage)
                                                const PopupMenuItem(
                                                  value: 'preview',
                                                  child: Text('Preview'),
                                                ),
                                              const PopupMenuItem(
                                                value: 'open',
                                                child: Text('Open'),
                                              ),
                                              const PopupMenuItem(
                                                value: 'download',
                                                child: Text('Download'),
                                              ),
                                              if (isLegacy) ...[
                                                const PopupMenuDivider(),
                                                const PopupMenuItem(
                                                  value: 'replace',
                                                  child: Text(
                                                    'Replace attachment',
                                                  ),
                                                ),
                                              ],
                                              const PopupMenuDivider(),
                                              const PopupMenuItem(
                                                value: 'copy',
                                                child: Text('Copy link'),
                                              ),
                                            ],
                                      ),
                                    ),
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
          ),
          actions: [
            if (r.type == 'task' && r.taskIsOverdue)
              FilledButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: const Text('Reopen submission?'),
                      content: const Text(
                        'Allow this employee to resubmit their report for the next 24 hours?',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(c, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(c, true),
                          child: const Text('Reopen 24h'),
                        ),
                      ],
                    ),
                  );
                  if (ok != true) return;
                  try {
                    await ReportService().reopenReportForResubmission(
                      reportId: r.id,
                      hours: 24,
                    );
                    await _fetchTaskReports();
                    if (!mounted) return;
                    AppWidgets.showSuccessSnackbar(
                      context,
                      'Submission reopened for 24 hours',
                    );
                  } catch (e) {
                    if (!mounted) return;
                    AppWidgets.showErrorSnackbar(
                      context,
                      AppWidgets.friendlyErrorMessage(
                        e,
                        fallback: 'Failed to reopen submission',
                      ),
                    );
                  }
                },
                child: const Text('Reopen 24h'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _showReportsForTask(Task task) {
    final reports = _filteredTaskReports()
        .where((r) => r.taskId == task.id)
        .toList();

    if (reports.isEmpty) {
      AppWidgets.showWarningSnackbar(context, 'No reports yet for this task');
      return;
    }

    if (reports.length == 1) {
      _showReportDetails(reports.first);
      return;
    }

    showDialog<void>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final isWide = MediaQuery.sizeOf(ctx).width >= 900;
        final actionSize = isWide ? 48.0 : 40.0;
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Reports for "${task.title}"',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          content: SizedBox(
            width: _dialogWidthFor(ctx),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: reports.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final r = reports[i];
                final submitted = DateFormat(
                  'yyyy-MM-dd HH:mm',
                ).format(toManilaTime(r.submittedAt));
                return Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    title: Text(
                      r.employeeName ?? r.employeeId,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      submitted,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.7,
                        ),
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _showReportDetails(r);
                    },
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildCardAction(
                          child: SizedBox(
                            width: actionSize,
                            height: actionSize,
                            child: PopupMenuButton<String>(
                              tooltip: 'Actions',
                              padding: EdgeInsets.zero,
                              child: Center(
                                child: Icon(
                                  Icons.more_horiz,
                                  color: theme.colorScheme.onSurface.withValues(
                                    alpha: 0.8,
                                  ),
                                ),
                              ),
                              onSelected: (value) {
                                switch (value) {
                                  case 'view':
                                    Navigator.pop(ctx);
                                    _showReportDetails(r);
                                    return;
                                  case 'history':
                                    Navigator.pop(ctx);
                                    _openEmployeeHistory(
                                      r.employeeId,
                                      r.employeeName ?? 'Unknown',
                                    );
                                    return;
                                  case 'review':
                                    Navigator.pop(ctx);
                                    _markReportReviewed(r);
                                    return;
                                  case 'archive':
                                    Navigator.pop(ctx);
                                    _toggleArchiveReport(r);
                                    return;
                                  case 'delete':
                                    Navigator.pop(ctx);
                                    _confirmAndDeleteReport(r);
                                    return;
                                }
                              },
                              itemBuilder: (ctx) => <PopupMenuEntry<String>>[
                                const PopupMenuItem(
                                  value: 'view',
                                  child: Text('View details'),
                                ),
                                const PopupMenuItem(
                                  value: 'history',
                                  child: Text('View history'),
                                ),
                                if (r.status.toLowerCase() != 'reviewed')
                                  const PopupMenuItem(
                                    value: 'review',
                                    child: Text('Mark as reviewed'),
                                  ),
                                PopupMenuItem(
                                  value: 'archive',
                                  child: Text(
                                    _showArchivedReports
                                        ? 'Restore'
                                        : 'Archive',
                                  ),
                                ),
                                const PopupMenuDivider(),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Delete'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _reportStatusBg(String status) {
    final s = status.toLowerCase();
    if (s == 'reviewed') {
      return Theme.of(context).colorScheme.primary.withValues(alpha: 0.12);
    }
    if (s == 'submitted') {
      return Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.14);
    }
    return Theme.of(context).colorScheme.surface;
  }

  Color _reportStatusFg(String status) {
    final s = status.toLowerCase();
    if (s == 'reviewed') return Theme.of(context).colorScheme.primary;
    if (s == 'submitted') return Theme.of(context).colorScheme.tertiary;
    return Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.85);
  }

  Widget _buildReportStatusChip(String status) {
    final theme = Theme.of(context);
    return Chip(
      label: Text(status),
      backgroundColor: _reportStatusBg(status),
      labelStyle: theme.textTheme.bodySmall?.copyWith(
        color: _reportStatusFg(status),
        fontWeight: FontWeight.w600,
      ),
      shape: StadiumBorder(
        side: BorderSide(
          color: _reportStatusFg(status).withValues(alpha: 0.25),
        ),
      ),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }

  String _contentPreview(String content, {int maxChars = 140}) {
    final c = content.trim();
    if (c.isEmpty) return '-';
    if (c.length <= maxChars) return c;
    return '${c.substring(0, maxChars)}…';
  }

  Future<void> _confirmAndDeleteReport(ReportModel r) async {
    final theme = Theme.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final dialogTheme = Theme.of(ctx);
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Delete Report',
            style: dialogTheme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          content: const Text('Are you sure you want to delete this report?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (ok != true) return;

    try {
      await ReportService().deleteReport(r.id);
      await _fetchTaskReports();
      if (mounted) {
        AppWidgets.showSuccessSnackbar(context, 'Report deleted');
      }
    } catch (e) {
      if (mounted) {
        AppWidgets.showErrorSnackbar(
          context,
          AppWidgets.friendlyErrorMessage(
            e,
            fallback: 'Failed to delete report',
          ),
        );
      }
    }
  }

  Future<void> _confirmAndDeleteTask(Task task) async {
    final theme = Theme.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final dialogTheme = Theme.of(ctx);
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Delete Task',
            style: dialogTheme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          content: Text(
            'Are you sure you want to delete the task "${task.title}"? This cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (ok != true) return;

    try {
      await _taskService.deleteTask(task.id);
      await _fetchOverdueTasks();
      await _fetchTaskReports();
      if (mounted) {
        AppWidgets.showSuccessSnackbar(context, 'Task deleted');
      }
    } catch (e) {
      if (mounted) {
        AppWidgets.showErrorSnackbar(
          context,
          AppWidgets.friendlyErrorMessage(e, fallback: 'Failed to delete task'),
        );
      }
    }
  }

  Future<void> _markReportReviewed(ReportModel r) async {
    try {
      await ReportService().updateReportStatus(r.id, 'reviewed');
      await _fetchTaskReports();
      if (mounted) {
        AppWidgets.showSuccessSnackbar(context, 'Marked as reviewed');
      }
    } catch (e) {
      if (mounted) {
        AppWidgets.showErrorSnackbar(
          context,
          AppWidgets.friendlyErrorMessage(
            e,
            fallback: 'Failed to mark report as reviewed',
          ),
        );
      }
    }
  }

  Future<void> _toggleArchiveReport(ReportModel r) async {
    try {
      if (_showArchivedReports) {
        await ReportService().restoreReport(r.id);
        if (mounted) {
          AppWidgets.showSuccessSnackbar(context, 'Report restored');
        }
      } else {
        await ReportService().archiveReport(r.id);
        if (mounted) {
          AppWidgets.showSuccessSnackbar(context, 'Report archived');
        }
      }
      await _fetchTaskReports();
    } catch (e, st) {
      debugPrint('Error toggling archive for report ${r.id}: $e\n$st');
      if (mounted) {
        AppWidgets.showErrorSnackbar(
          context,
          AppWidgets.friendlyErrorMessage(
            e,
            fallback: 'Failed to update report',
          ),
        );
      }
    }
  }

  Widget _buildTaskReportCard(ReportModel r) {
    final theme = Theme.of(context);
    final isWide = MediaQuery.sizeOf(context).width >= 900;
    final actionSize = isWide ? 44.0 : 36.0;
    final submitted = DateFormat(
      'yyyy-MM-dd HH:mm',
    ).format(toManilaTime(r.submittedAt));
    final attachmentCount = r.attachments.length;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showReportDetails(r),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.taskTitle ?? (r.taskId ?? 'Task'),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          r.employeeName ?? r.employeeId,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.7,
                            ),
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildCardAction(
                    child: SizedBox(
                      width: actionSize,
                      height: actionSize,
                      child: PopupMenuButton<String>(
                        tooltip: 'Actions',
                        padding: EdgeInsets.zero,
                        child: Center(
                          child: Icon(
                            Icons.more_horiz,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.8,
                            ),
                          ),
                        ),
                        onSelected: (value) {
                          switch (value) {
                            case 'view':
                              _showReportDetails(r);
                              return;
                            case 'history':
                              _openEmployeeHistory(
                                r.employeeId,
                                r.employeeName ?? 'Unknown',
                              );
                              return;
                            case 'review':
                              _markReportReviewed(r);
                              return;
                            case 'archive':
                              _toggleArchiveReport(r);
                              return;
                            case 'delete':
                              _confirmAndDeleteReport(r);
                              return;
                          }
                        },
                        itemBuilder: (ctx) => <PopupMenuEntry<String>>[
                          const PopupMenuItem(
                            value: 'view',
                            child: Text('View details'),
                          ),
                          const PopupMenuItem(
                            value: 'history',
                            child: Text('View history'),
                          ),
                          if (r.status.toLowerCase() != 'reviewed')
                            const PopupMenuItem(
                              value: 'review',
                              child: Text('Mark as reviewed'),
                            ),
                          PopupMenuItem(
                            value: 'archive',
                            child: Text(
                              _showArchivedReports ? 'Restore' : 'Archive',
                            ),
                          ),
                          const PopupMenuDivider(),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _buildReportStatusChip(r.status),
                  if (r.taskIsOverdue)
                    _buildMetaChip('Overdue', color: theme.colorScheme.error),
                  if ((r.taskDifficulty ?? '').isNotEmpty)
                    _buildMetaChip(r.taskDifficulty!),
                  _buildMetaChip(submitted),
                  _buildMetaChip('Attachments: $attachmentCount'),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                _contentPreview(r.content),
                style: theme.textTheme.bodySmall?.copyWith(
                  height: 1.35,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTaskReportsView() {
    final theme = Theme.of(context);
    if (_isLoadingTaskReports) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_taskReportsError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                _taskReportsError!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _fetchTaskReports,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    final reports = _showArchivedReports ? _archivedTaskReports : _taskReports;
    if (reports.isEmpty && !_taskOverdueOnly) {
      return Center(
        child: Text(
          _showArchivedReports ? 'No archived task reports' : 'No task reports',
        ),
      );
    }
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(
              title: 'Task Reports',
              subtitle: _showArchivedReports
                  ? 'Archived task history'
                  : 'Latest task submissions',
              badge: _buildCountBadge(
                '${reports.length}',
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildFilterChip(
                  label: 'All difficulties',
                  selected: _taskDifficultyFilter == 'All',
                  onSelected: (sel) {
                    if (!sel) return;
                    setState(() {
                      _taskDifficultyFilter = 'All';
                    });
                  },
                ),
                _buildFilterChip(
                  label: 'Easy',
                  selected: _taskDifficultyFilter == 'easy',
                  onSelected: (sel) {
                    if (!sel) return;
                    setState(() {
                      _taskDifficultyFilter = 'easy';
                    });
                  },
                ),
                _buildFilterChip(
                  label: 'Medium',
                  selected: _taskDifficultyFilter == 'medium',
                  onSelected: (sel) {
                    if (!sel) return;
                    setState(() {
                      _taskDifficultyFilter = 'medium';
                    });
                  },
                ),
                _buildFilterChip(
                  label: 'Hard',
                  selected: _taskDifficultyFilter == 'hard',
                  onSelected: (sel) {
                    if (!sel) return;
                    setState(() {
                      _taskDifficultyFilter = 'hard';
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildFilterChip(
                  label: 'All',
                  selected: _reportStatusFilter == 'All' && !_taskOverdueOnly,
                  onSelected: (sel) {
                    if (!sel) return;
                    setState(() {
                      _reportStatusFilter = 'All';
                      _taskOverdueOnly = false;
                    });
                  },
                ),
                _buildFilterChip(
                  label: 'Submitted',
                  selected:
                      _reportStatusFilter == 'submitted' && !_taskOverdueOnly,
                  onSelected: (sel) {
                    if (!sel) return;
                    setState(() {
                      _reportStatusFilter = 'submitted';
                      _taskOverdueOnly = false;
                    });
                  },
                ),
                _buildFilterChip(
                  label: 'Reviewed',
                  selected:
                      _reportStatusFilter == 'reviewed' && !_taskOverdueOnly,
                  onSelected: (sel) {
                    if (!sel) return;
                    setState(() {
                      _reportStatusFilter = 'reviewed';
                      _taskOverdueOnly = false;
                    });
                  },
                ),
                _buildFilterChip(
                  label: 'Overdue only',
                  selected: _taskOverdueOnly,
                  onSelected: _showArchivedReports
                      ? null
                      : (sel) {
                          setState(() {
                            _taskOverdueOnly = sel;
                            if (sel) {
                              _reportStatusFilter = 'All';
                            }
                          });
                          if (sel) {
                            _fetchOverdueTasks();
                          }
                        },
                  accentColor: theme.colorScheme.error,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_taskOverdueOnly && !_showArchivedReports)
              _buildOverdueTasksSection(),
            if (!_taskOverdueOnly && reports.isEmpty)
              Center(
                child: Text(
                  _showArchivedReports
                      ? 'No archived task reports'
                      : 'No task reports',
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _filteredTaskReports().length,
                itemBuilder: (context, index) {
                  final r = _filteredTaskReports()[index];
                  return _buildTaskReportCard(r);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportReport() async {
    // Show export preview with filters applied
    if (_viewMode == 'attendance') {
      final recordsToExport = _filteredAttendanceRecords
          .expand(_attendanceSessionToReportModels)
          .toList();

      if (recordsToExport.isEmpty) {
        AppWidgets.showWarningSnackbar(
          context,
          'No attendance records to export for selected filters',
        );
        return;
      }

      DateTime? inclusiveStart;
      DateTime? inclusiveEnd;

      if (_attendanceStartDate != null || _attendanceEndDate != null) {
        inclusiveStart = _attendanceStartDate;
        if (_attendanceEndDate != null) {
          inclusiveEnd = _attendanceEndDate!.subtract(const Duration(days: 1));
        }
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ReportExportPreviewScreen(
            records: recordsToExport,
            reportType: _viewMode,
            taskReports: _filteredTaskReports(),
            startDate: inclusiveStart,
            endDate: inclusiveEnd,
            locationFilterId: _filterLocationId,
            locationFilterLabel: _filterLocationLabel != 'All Locations'
                ? _filterLocationLabel
                : null,
            statusFilter: _filterStatus != 'All Status' ? _filterStatus : null,
            employeeIdFilter: _filterEmployeeId,
          ),
        ),
      );
    } else {
      if (_taskReports.isEmpty) {
        AppWidgets.showWarningSnackbar(context, 'No task reports to export');
        return;
      }

      final attendanceForContext = _filteredAttendanceRecords
          .expand(_attendanceSessionToReportModels)
          .toList();
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ReportExportPreviewScreen(
            records: attendanceForContext,
            reportType: _viewMode,
            taskReports: _filteredTaskReports(),
            startDate: _filterDate != 'All Dates'
                ? DateTime.parse(_filterDate)
                : null,
            endDate: null,
            locationFilterId: _filterLocationId,
            locationFilterLabel: _filterLocationLabel != 'All Locations'
                ? _filterLocationLabel
                : null,
            statusFilter: _reportStatusFilter != 'All'
                ? _reportStatusFilter
                : null,
          ),
        ),
      );
    }
  }
}
