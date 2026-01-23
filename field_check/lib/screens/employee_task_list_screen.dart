// ignore_for_file: avoid_print
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:field_check/models/task_model.dart';
import 'package:field_check/services/task_service.dart';
import 'package:field_check/services/realtime_service.dart';
import 'package:field_check/services/autosave_service.dart';
import 'package:field_check/screens/task_report_screen.dart';
import 'package:field_check/screens/map_screen.dart';
import 'package:field_check/screens/employee_reports_screen.dart';
import 'package:field_check/widgets/app_widgets.dart';
import 'package:field_check/utils/manila_time.dart';

class EmployeeTaskListScreen extends StatefulWidget {
  final String userModelId;

  const EmployeeTaskListScreen({super.key, required this.userModelId});

  @override
  State<EmployeeTaskListScreen> createState() => _EmployeeTaskListScreenState();
}

class _EmployeeTaskListScreenState extends State<EmployeeTaskListScreen>
    with SingleTickerProviderStateMixin {
  late Future<List<Task>> _assignedTasksFuture;
  final RealtimeService _realtimeService = RealtimeService();
  final AutosaveService _autosaveService = AutosaveService();

  late final TabController _tabController;

  StreamSubscription<Map<String, dynamic>>? _taskSub;
  Timer? _taskRefreshDebounce;

  String _statusFilter = 'all'; // all, pending, in_progress, completed

  @override
  void initState() {
    super.initState();
    // ignore: unnecessary_statements
    _completeTaskWithReport;
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!mounted) return;
      if (_tabController.indexIsChanging) return;
      _refreshTasks();
    });
    _assignedTasksFuture = TaskService().fetchAssignedTasks(
      widget.userModelId,
      archived: _fetchArchived,
    );
    _markTasksScopeRead();
    _initRealtimeService();
    _autosaveService.initialize();
  }

  Future<void> _markTasksScopeRead() async {
    try {
      await TaskService().markTasksScopeRead();
    } catch (_) {}
  }

  bool _isTaskNew(Task task) {
    final lastViewedAt = task.lastViewedAt;
    if (lastViewedAt == null) return true;
    return task.updatedAt.isAfter(lastViewedAt);
  }

  bool get _isCurrentTab => _tabController.index == 0;
  bool get _isOverdueTab => _tabController.index == 1;
  bool get _isArchivedTab => _tabController.index == 2;

  bool get _fetchArchived => _isArchivedTab;

  Future<void> _deleteOverdue(Task task) async {
    final userTaskId = task.userTaskId;
    if (userTaskId == null || userTaskId.trim().isEmpty) {
      if (!mounted) return;
      AppWidgets.showErrorSnackbar(context, 'Unable to delete task');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Delete overdue task?'),
          content: const Text('This will remove it from your task list.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await TaskService().archiveUserTask(userTaskId);
      if (!mounted) return;
      AppWidgets.showSuccessSnackbar(context, 'Task deleted');
      await _refreshTasks();
    } catch (e) {
      if (!mounted) return;
      AppWidgets.showErrorSnackbar(
        context,
        AppWidgets.friendlyErrorMessage(e, fallback: 'Failed to delete task'),
      );
    }
  }

  Future<void> _toggleArchive(Task task) async {
    final userTaskId = task.userTaskId;
    if (userTaskId == null || userTaskId.trim().isEmpty) {
      if (!mounted) return;
      AppWidgets.showErrorSnackbar(
        context,
        'Unable to update task archive state',
      );
      return;
    }

    try {
      if (_isArchivedTab) {
        await TaskService().restoreUserTask(userTaskId);
        if (mounted) {
          AppWidgets.showSuccessSnackbar(context, 'Task restored');
        }
      } else {
        await TaskService().archiveUserTask(userTaskId);
        if (mounted) {
          AppWidgets.showSuccessSnackbar(context, 'Task archived');
        }
      }
      await _refreshTasks();
    } catch (e) {
      if (!mounted) return;
      AppWidgets.showErrorSnackbar(
        context,
        AppWidgets.friendlyErrorMessage(e, fallback: 'Failed to update task'),
      );
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'completed':
        return Colors.green;
      case 'in_progress':
        return Colors.orange;
      case 'pending':
        return Colors.blue;
      default:
        return Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);
    }
  }

  Widget _buildSectionHeader(
    String title, {
    String? subtitle,
    Widget? trailing,
  }) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  Widget _buildSurfaceCard({
    required Widget child,
    EdgeInsetsGeometry? padding,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildStatusPill({
    required String label,
    required Color color,
    IconData? icon,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool selected,
    required VoidCallback onSelected,
  }) {
    final theme = Theme.of(context);
    final activeColor = theme.colorScheme.primary;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (value) {
        if (!value) return;
        onSelected();
      },
      labelStyle: theme.textTheme.labelMedium?.copyWith(
        fontWeight: FontWeight.w700,
        color: selected
            ? activeColor
            : theme.colorScheme.onSurface.withValues(alpha: 0.7),
      ),
      selectedColor: activeColor.withValues(alpha: 0.16),
      backgroundColor: theme.colorScheme.surface,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected
              ? activeColor.withValues(alpha: 0.45)
              : theme.dividerColor.withValues(alpha: 0.35),
        ),
      ),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _buildMetaChip(String label, {IconData? icon}) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurface.withValues(alpha: 0.7);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStateCard({
    required IconData icon,
    required String title,
    required String message,
    Widget? action,
  }) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: _buildSurfaceCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: theme.colorScheme.primary),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                ),
                textAlign: TextAlign.center,
              ),
              if (action != null) ...[const SizedBox(height: 12), action],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openTaskDetails(Task task) async {
    final isCompleted = task.status == 'completed';

    final userTaskId = task.userTaskId;
    if (userTaskId != null && userTaskId.trim().isNotEmpty) {
      TaskService().markUserTaskViewed(userTaskId).then((_) {
        if (!mounted) return;
        setState(() {
          _assignedTasksFuture = TaskService().fetchAssignedTasks(
            widget.userModelId,
            archived: _fetchArchived,
          );
        });
      });
    }

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.72,
          minChildSize: 0.45,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        task.title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_isTaskNew(task))
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: Colors.red.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Text(
                          'NEW',
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: Colors.red,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ),
                    if (_isTaskNew(task)) const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _statusColor(
                          task.status,
                        ).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: _statusColor(
                            task.status,
                          ).withValues(alpha: 0.35),
                        ),
                      ),
                      child: Text(
                        task.status,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: _statusColor(task.status),
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(task.description),
                const SizedBox(height: 12),
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
                    if (task.type != null && task.type!.isNotEmpty)
                      Chip(
                        label: Text(task.type!),
                        visualDensity: VisualDensity.compact,
                      ),
                    if (task.difficulty != null && task.difficulty!.isNotEmpty)
                      Chip(
                        label: Text(task.difficulty!),
                        visualDensity: VisualDensity.compact,
                      ),
                    if (task.rawStatus == 'blocked')
                      Chip(
                        label: const Text('Blocked'),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: Colors.red.withValues(alpha: 0.12),
                        labelStyle: const TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'Progress: ${_taskProgressLabel(task)}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: _taskProgressValue(task),
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.12),
                ),
                if (task.checklist.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    'Checklist (${task.progressPercent.clamp(0, 100)}%)',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  ...task.checklist.map(
                    (c) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        c.isCompleted
                            ? Icons.check_circle
                            : Icons.circle_outlined,
                        color: c.isCompleted
                            ? Colors.green
                            : Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.55),
                      ),
                      title: Text(c.label),
                      subtitle: c.completedAt != null
                          ? Text(
                              'Completed at: ${formatManila(c.completedAt, 'yyyy-MM-dd HH:mm:ss')}',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.75),
                                  ),
                            )
                          : null,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isCompleted
                        ? null
                        : () async {
                            final ok = await Navigator.push<bool>(
                              context,
                              MaterialPageRoute(
                                builder: (context) => TaskReportScreen(
                                  task: task,
                                  employeeId: widget.userModelId,
                                ),
                              ),
                            );
                            if (ok == true && ctx.mounted) {
                              Navigator.pop(ctx, true);
                            }
                          },
                    child: Text(isCompleted ? 'Completed' : 'Complete Task'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Close'),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == true && mounted) {
      setState(() {
        _assignedTasksFuture = TaskService().fetchAssignedTasks(
          widget.userModelId,
          archived: _fetchArchived,
        );
      });
    }
  }

  @override
  void dispose() {
    _taskRefreshDebounce?.cancel();
    _taskSub?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _initRealtimeService() async {
    await _realtimeService.initialize();

    _taskSub?.cancel();
    _taskSub = _realtimeService.taskStream.listen((event) {
      // Conservative strategy: refresh on any task-related event.
      // Server payload shapes vary, so avoid brittle filtering.
      _taskRefreshDebounce?.cancel();
      _taskRefreshDebounce = Timer(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        setState(() {
          _assignedTasksFuture = TaskService().fetchAssignedTasks(
            widget.userModelId,
            archived: _fetchArchived,
          );
        });
      });
    });
  }

  Future<void> _completeTaskWithReport(Task task) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) =>
            TaskReportScreen(task: task, employeeId: widget.userModelId),
      ),
    );

    if (result == true && mounted) {
      setState(() {
        _assignedTasksFuture = TaskService().fetchAssignedTasks(
          widget.userModelId,
          archived: _fetchArchived,
        );
      });
    }
  }

  Future<void> _refreshTasks() async {
    setState(() {
      _assignedTasksFuture = TaskService().fetchAssignedTasks(
        widget.userModelId,
        archived: _fetchArchived,
      );
    });
  }

  double _taskProgressValue(Task task) {
    if (task.checklist.isNotEmpty) {
      final clamped = task.progressPercent.clamp(0, 100);
      return clamped / 100.0;
    }

    switch (task.status) {
      case 'completed':
        return 1.0;
      case 'in_progress':
        return 0.5;
      case 'pending':
      default:
        return 0.0;
    }
  }

  String _taskProgressLabel(Task task) {
    if (task.checklist.isNotEmpty) {
      final clamped = task.progressPercent.clamp(0, 100);
      return '$clamped%';
    }

    switch (task.status) {
      case 'completed':
        return '100%';
      case 'in_progress':
        return '50%';
      case 'pending':
      default:
        return '0%';
    }
  }

  Widget _buildTaskCard(Task task) {
    final theme = Theme.of(context);
    final statusColor = _statusColor(task.status);
    final isCompleted = task.status == 'completed';
    final isNew = _isTaskNew(task);
    final hasMeta =
        (task.type != null && task.type!.isNotEmpty) ||
        (task.difficulty != null && task.difficulty!.isNotEmpty);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: GestureDetector(
        onTap: () => _openTaskDetails(task),
        child: _buildSurfaceCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      task.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        decoration: isCompleted
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (isNew) ...[
                    _buildStatusPill(
                      label: 'NEW',
                      color: Colors.red,
                      icon: Icons.fiber_new,
                    ),
                    const SizedBox(width: 6),
                  ],
                  IconButton(
                    tooltip: _isOverdueTab
                        ? 'Delete'
                        : (_isArchivedTab ? 'Restore' : 'Archive'),
                    icon: Icon(
                      _isOverdueTab
                          ? Icons.delete_outline
                          : (_isArchivedTab
                                ? Icons.unarchive_outlined
                                : Icons.archive_outlined),
                    ),
                    onPressed: () {
                      if (_isOverdueTab) {
                        _deleteOverdue(task);
                        return;
                      }
                      _toggleArchive(task);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                task.description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildMetaChip(
                    'Due ${formatManila(task.dueDate, 'yyyy-MM-dd')}',
                    icon: Icons.event,
                  ),
                  if (task.type != null && task.type!.isNotEmpty)
                    _buildMetaChip(task.type!, icon: Icons.category),
                  if (task.difficulty != null && task.difficulty!.isNotEmpty)
                    _buildMetaChip(task.difficulty!, icon: Icons.speed),
                  if (hasMeta == false)
                    _buildMetaChip('Task details', icon: Icons.info_outline),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildStatusPill(
                    label: task.status.replaceAll('_', ' '),
                    color: statusColor,
                  ),
                  if (task.isOverdue)
                    _buildStatusPill(
                      label: 'Overdue',
                      color: theme.colorScheme.error,
                      icon: Icons.warning_amber_rounded,
                    ),
                  if (task.rawStatus == 'blocked')
                    _buildStatusPill(
                      label: 'Blocked',
                      color: Colors.red.shade700,
                      icon: Icons.block,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value: _taskProgressValue(task),
                      backgroundColor: theme.colorScheme.onSurface.withValues(
                        alpha: 0.12,
                      ),
                      valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _taskProgressLabel(task),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
              if (task.assignedToMultiple.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Assigned to:',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: task.assignedToMultiple
                      .map((user) => _buildMetaChip(user.name))
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'My Tasks',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelStyle: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          unselectedLabelStyle: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          tabs: const [
            Tab(text: 'Current'),
            Tab(text: 'Overdue'),
            Tab(text: 'Archived'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'My Reports',
            icon: const Icon(Icons.description_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      EmployeeReportsScreen(employeeId: widget.userModelId),
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'Refresh Tasks',
            icon: const Icon(Icons.refresh),
            onPressed: _refreshTasks,
          ),
          IconButton(
            tooltip: 'Open Map',
            icon: const Icon(Icons.map),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MapScreen()),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshTasks,
        child: FutureBuilder<List<Task>>(
          future: _assignedTasksFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            } else if (snapshot.hasError) {
              return _buildStateCard(
                icon: Icons.error_outline,
                title: 'Unable to load tasks',
                message: snapshot.error.toString(),
                action: FilledButton.icon(
                  onPressed: _refreshTasks,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              );
            } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
              final message = _isArchivedTab
                  ? 'No archived tasks yet.'
                  : (_isOverdueTab
                        ? 'No overdue tasks. Great job staying on track!'
                        : 'No tasks assigned yet.');
              return _buildStateCard(
                icon: Icons.task_alt,
                title: 'All clear',
                message: message,
              );
            }

            final tasks = snapshot.data!
                .where((t) => _isArchivedTab ? t.isArchived : !t.isArchived)
                .where((t) {
                  if (_isOverdueTab) return t.isOverdue;
                  if (_isCurrentTab) return !t.isOverdue;
                  return true;
                })
                .where(
                  (t) =>
                      _statusFilter == 'all' ? true : t.status == _statusFilter,
                )
                .toList();

            tasks.sort((a, b) {
              // In-progress first
              final aInProgress = a.status == 'in_progress';
              final bInProgress = b.status == 'in_progress';
              if (aInProgress != bInProgress) {
                return aInProgress ? -1 : 1;
              }

              // Then due date (soonest first)
              final byDue = a.dueDate.compareTo(b.dueDate);
              if (byDue != 0) return byDue;

              // Then title
              return a.title.compareTo(b.title);
            });

            final activeLabel = _statusFilter == 'all'
                ? 'All'
                : _statusFilter.replaceAll('_', ' ');

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: _buildSurfaceCard(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSectionHeader(
                          'Filter tasks',
                          subtitle: 'Showing $activeLabel tasks',
                          trailing: _buildStatusPill(
                            label: '${tasks.length} tasks',
                            color: theme.colorScheme.primary,
                            icon: Icons.list_alt,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _buildFilterChip(
                              label: 'All',
                              selected: _statusFilter == 'all',
                              onSelected: () =>
                                  setState(() => _statusFilter = 'all'),
                            ),
                            _buildFilterChip(
                              label: 'Pending',
                              selected: _statusFilter == 'pending',
                              onSelected: () =>
                                  setState(() => _statusFilter = 'pending'),
                            ),
                            _buildFilterChip(
                              label: 'In Progress',
                              selected: _statusFilter == 'in_progress',
                              onSelected: () =>
                                  setState(() => _statusFilter = 'in_progress'),
                            ),
                            _buildFilterChip(
                              label: 'Completed',
                              selected: _statusFilter == 'completed',
                              onSelected: () =>
                                  setState(() => _statusFilter = 'completed'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (tasks.isEmpty)
                  _buildStateCard(
                    icon: Icons.filter_alt_off,
                    title: 'No matching tasks',
                    message: 'Try adjusting your filter or pull to refresh.',
                  )
                else
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: tasks.length,
                      itemBuilder: (context, index) {
                        final task = tasks[index];
                        return _buildTaskCard(task);
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
