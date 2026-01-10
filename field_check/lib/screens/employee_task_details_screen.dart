import 'package:flutter/material.dart';
import 'package:field_check/models/task_model.dart';
import 'package:field_check/screens/task_report_screen.dart';

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

    return Scaffold(
      appBar: AppBar(title: const Text('Task Details')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              task.title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(task.description),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  label: Text(task.status),
                  backgroundColor: _statusColor(
                    context,
                    task.status,
                  ).withValues(alpha: 0.15),
                  labelStyle: TextStyle(
                    color: _statusColor(context, task.status),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Chip(
                  label: Text(
                    'Due: ${task.dueDate.toLocal().toString().split(' ')[0]}',
                  ),
                ),
                if (task.rawStatus == 'blocked')
                  Chip(
                    label: const Text('Blocked'),
                    backgroundColor: Colors.red.withValues(alpha: 0.15),
                    labelStyle: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
            if (task.checklist.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Checklist (${task.progressPercent.clamp(0, 100)}%)',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: task.progressPercent.clamp(0, 100) / 100.0,
              ),
              const SizedBox(height: 8),
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
                          'Completed at: ${c.completedAt!.toLocal().toString().split('.')[0]}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.75),
                              ),
                        )
                      : null,
                ),
              ),
            ],
            const SizedBox(height: 20),
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
      ),
    );
  }
}
