import 'package:flutter/material.dart';
import '../services/admin_actions_service.dart';

class AdminActionsModal extends StatefulWidget {
  final String employeeId;
  final String employeeName;
  final VoidCallback? onActionComplete;

  const AdminActionsModal({
    super.key,
    required this.employeeId,
    required this.employeeName,
    this.onActionComplete,
  });

  @override
  State<AdminActionsModal> createState() => _AdminActionsModalState();
}

class _AdminActionsModalState extends State<AdminActionsModal> {
  final AdminActionsService _adminService = AdminActionsService();
  bool _isLoading = false;
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _reasonController = TextEditingController();

  @override
  void dispose() {
    _messageController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _handleAction(String action) async {
    if (!mounted) return;

    setState(() => _isLoading = true);

    try {
      bool success = false;
      String message = '';

      switch (action) {
        case 'mark_busy':
          success = await _adminService.updateEmployeeStatus(
            employeeId: widget.employeeId,
            status: 'busy',
            reason: 'Marked busy by admin',
          );
          message = success ? 'Employee marked as busy' : 'Failed to mark busy';
          break;

        case 'mark_available':
          success = await _adminService.updateEmployeeStatus(
            employeeId: widget.employeeId,
            status: 'available',
            reason: 'Marked available by admin',
          );
          message = success
              ? 'Employee marked as available'
              : 'Failed to mark available';
          break;

        case 'send_message':
          if (_messageController.text.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Please enter a message')),
            );
            return;
          }
          success = await _adminService.sendMessage(
            employeeId: widget.employeeId,
            message: _messageController.text,
            messageType: 'general',
          );
          message = success
              ? 'Message sent successfully'
              : 'Failed to send message';
          break;

        case 'send_urgent':
          if (_messageController.text.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Please enter a message')),
            );
            return;
          }
          success = await _adminService.sendMessage(
            employeeId: widget.employeeId,
            message: _messageController.text,
            messageType: 'urgent',
          );
          message = success ? 'Urgent message sent' : 'Failed to send message';
          break;

        case 'view_analytics':
          final analytics = await _adminService.getEmployeeAnalytics(
            employeeId: widget.employeeId,
            period: '30days',
          );
          if (analytics != null) {
            _showAnalyticsDialog(analytics);
            success = true;
          }
          message = success ? 'Analytics loaded' : 'Failed to load analytics';
          break;

        case 'view_performance':
          final metrics = await _adminService.getPerformanceMetrics(
            employeeId: widget.employeeId,
            period: '30days',
          );
          if (metrics != null) {
            _showPerformanceDialog(metrics);
            success = true;
          }
          message = success
              ? 'Performance metrics loaded'
              : 'Failed to load metrics';
          break;

        case 'export_data':
          final url = await _adminService.exportEmployeeData(
            employeeId: widget.employeeId,
            format: 'pdf',
          );
          if (url != null) {
            _showExportDialog(url);
            success = true;
          }
          message = success ? 'Export initiated' : 'Failed to export data';
          break;
      }

      if (!mounted) return;

      setState(() => _isLoading = false);

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.green),
        );
        widget.onActionComplete?.call();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void _showAnalyticsDialog(Map<String, dynamic> analytics) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Employee Analytics'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildAnalyticsItem(
                'Tasks Completed',
                analytics['tasksCompleted']?.toString() ?? 'N/A',
              ),
              _buildAnalyticsItem(
                'Tasks Pending',
                analytics['tasksPending']?.toString() ?? 'N/A',
              ),
              _buildAnalyticsItem(
                'Avg Completion Time',
                analytics['avgCompletionTime']?.toString() ?? 'N/A',
              ),
              _buildAnalyticsItem(
                'On-Time Rate',
                analytics['onTimeRate']?.toString() ?? 'N/A',
              ),
              _buildAnalyticsItem(
                'Attendance Rate',
                analytics['attendanceRate']?.toString() ?? 'N/A',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showPerformanceDialog(Map<String, dynamic> metrics) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Performance Metrics'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildAnalyticsItem(
                'Efficiency Score',
                metrics['efficiencyScore']?.toString() ?? 'N/A',
              ),
              _buildAnalyticsItem(
                'Quality Score',
                metrics['qualityScore']?.toString() ?? 'N/A',
              ),
              _buildAnalyticsItem(
                'Reliability Score',
                metrics['reliabilityScore']?.toString() ?? 'N/A',
              ),
              _buildAnalyticsItem(
                'Overall Rating',
                metrics['overallRating']?.toString() ?? 'N/A',
              ),
              _buildAnalyticsItem(
                'Trend',
                metrics['trend']?.toString() ?? 'N/A',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showExportDialog(String url) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export Successful'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 48),
            const SizedBox(height: 16),
            const Text('Employee data has been exported successfully.'),
            const SizedBox(height: 8),
            Text(
              'Download URL: $url',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.75),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyticsItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(value, style: const TextStyle(color: Colors.blue)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Admin Actions',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.employeeName,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: onSurface.withValues(alpha: 0.75),
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Status Actions
              _buildSectionTitle('Status Management'),
              _buildActionButton(
                'Mark as Busy',
                Icons.schedule,
                Colors.red,
                () => _handleAction('mark_busy'),
              ),
              _buildActionButton(
                'Mark as Available',
                Icons.check_circle,
                Colors.green,
                () => _handleAction('mark_available'),
              ),
              const SizedBox(height: 16),

              // Messaging
              _buildSectionTitle('Messaging'),
              TextField(
                controller: _messageController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Enter message...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildActionButton(
                      'Send Message',
                      Icons.mail,
                      Colors.blue,
                      () => _handleAction('send_message'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildActionButton(
                      'Send Urgent',
                      Icons.priority_high,
                      Colors.orange,
                      () => _handleAction('send_urgent'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Analytics & Reports
              _buildSectionTitle('Analytics & Reports'),
              Row(
                children: [
                  Expanded(
                    child: _buildActionButton(
                      'View Analytics',
                      Icons.analytics,
                      Colors.purple,
                      () => _handleAction('view_analytics'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildActionButton(
                      'Performance',
                      Icons.trending_up,
                      Colors.teal,
                      () => _handleAction('view_performance'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildActionButton(
                'Export Data',
                Icons.download,
                Colors.indigo,
                () => _handleAction('export_data'),
              ),
              const SizedBox(height: 24),

              // Loading indicator
              if (_isLoading) const Center(child: CircularProgressIndicator()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: Theme.of(
            context,
          ).colorScheme.onSurface.withValues(alpha: 0.75),
        ),
      ),
    );
  }

  Widget _buildActionButton(
    String label,
    IconData icon,
    Color color,
    VoidCallback onPressed,
  ) {
    return SizedBox(
      height: 44,
      child: ElevatedButton.icon(
        onPressed: _isLoading ? null : onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.grey[300],
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}
