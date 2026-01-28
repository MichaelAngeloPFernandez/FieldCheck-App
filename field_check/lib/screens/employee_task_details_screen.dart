import 'package:flutter/material.dart';
import 'package:field_check/models/task_model.dart';
import 'package:field_check/screens/task_report_screen.dart';
import 'package:field_check/utils/app_theme.dart';
import 'package:field_check/widgets/app_page.dart';
import 'package:field_check/utils/manila_time.dart';

class EmployeeTaskDetailsScreen extends StatelessWidget {
  final Task task;
  final String employeeId;

  const EmployeeTaskDetailsScreen({
    super.key,
    required this.task,
    required this.employeeId,
  });

  Color _statusColor(BuildContext context, String status) {
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

  @override
  Widget build(BuildContext context) {
    final isCompleted = task.status == 'completed';

    return AppPage(
      appBarTitle: 'Task Details',
      showBack: true,
      padding: const EdgeInsets.fromLTRB(
        AppTheme.lg,
        AppTheme.lg,
        AppTheme.lg,
        AppTheme.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            task.title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: AppTheme.sm),
          Text(task.description, style: AppTheme.bodyMd),
          const SizedBox(height: AppTheme.md),
          Wrap(
            spacing: AppTheme.sm,
            runSpacing: AppTheme.sm,
            children: [
              Chip(
                label: Text(task.status),
                backgroundColor: _statusColor(
                  context,
                  task.status,
                ).withValues(alpha: 0.15),
                labelStyle: TextStyle(
                  color: _statusColor(context, task.status),
                  fontWeight: FontWeight.w700,
                ),
                visualDensity: VisualDensity.compact,
              ),
              Chip(
                label: Text('Due: ${formatManila(task.dueDate, 'yyyy-MM-dd')}'),
                visualDensity: VisualDensity.compact,
              ),
              if (task.rawStatus == 'blocked')
                Chip(
                  label: const Text('Blocked'),
                  backgroundColor: Colors.red.withValues(alpha: 0.15),
                  labelStyle: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w700,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          if (task.checklist.isNotEmpty) ...[
            const SizedBox(height: AppTheme.lg),
            Text(
              'Checklist (${task.progressPercent.clamp(0, 100)}%)',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppTheme.sm),
            LinearProgressIndicator(
              value: task.progressPercent.clamp(0, 100) / 100.0,
            ),
            const SizedBox(height: AppTheme.sm),
            ...task.checklist.map(
              (c) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  c.isCompleted ? Icons.check_circle : Icons.circle_outlined,
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
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.75),
                        ),
                      )
                    : null,
              ),
            ),
          ],
          const SizedBox(height: AppTheme.xl),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: isCompleted
                  ? null
                  : () async {
                      final result = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                          builder: (context) => TaskReportScreen(
                            task: task,
                            employeeId: employeeId,
                          ),
                        ),
                      );

                      if (result == true && context.mounted) {
                        Navigator.pop(context, true);
                      }
                    },
              child: Text(isCompleted ? 'Completed' : 'Complete Task'),
            ),
          ),
        ],
      ),
    );
  }
}
