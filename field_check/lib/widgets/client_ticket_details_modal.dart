import 'package:flutter/material.dart';
import 'package:field_check/services/client_ticket_service.dart';
import 'package:field_check/screens/client_tickets_screen.dart';
import 'package:field_check/utils/manila_time.dart';

/// Client Ticket Details Modal Widget
/// Displays comprehensive ticket information with management actions
class ClientTicketDetailsModal extends StatefulWidget {
  final String ticketNumber;
  final VoidCallback? onTicketUpdated;

  const ClientTicketDetailsModal({
    super.key,
    required this.ticketNumber,
    this.onTicketUpdated,
  });

  @override
  State<ClientTicketDetailsModal> createState() => _ClientTicketDetailsModalState();
}

class _ClientTicketDetailsModalState extends State<ClientTicketDetailsModal> {
  final ClientTicketService _ticketService = ClientTicketService();
  Map<String, dynamic>? _ticketData;
  bool _isLoading = true;
  String? _error;
  bool _isPerformingAction = false;

  @override
  void initState() {
    super.initState();
    _loadTicketDetails();
  }

  Future<void> _loadTicketDetails() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final result = await _ticketService.getClientTicket(widget.ticketNumber);
      
      if (mounted) {
        setState(() {
          _ticketData = result;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _archiveTicket() async {
    final confirmed = await _showConfirmationDialog(
      title: 'Archive Ticket',
      message: 'Are you sure you want to archive this ticket? This action can be undone.',
      confirmText: 'Archive',
      isDestructive: false,
    );

    if (!confirmed) return;

    try {
      setState(() => _isPerformingAction = true);

      final result = await _ticketService.archiveClientTicket(widget.ticketNumber);
      
      if (mounted) {
        if (result['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message'] ?? 'Ticket archived successfully'),
              backgroundColor: Colors.green,
            ),
          );
          widget.onTicketUpdated?.call();
          Navigator.of(context).pop();
        } else {
          _showErrorSnackBar(result['error'] ?? 'Failed to archive ticket');
        }
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('Error archiving ticket: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isPerformingAction = false);
      }
    }
  }

  Future<void> _deleteTicket() async {
    final confirmed = await _showConfirmationDialog(
      title: 'Delete Ticket',
      message: 'Are you sure you want to permanently delete this ticket? This action cannot be undone.',
      confirmText: 'Delete',
      isDestructive: true,
    );

    if (!confirmed) return;

    try {
      setState(() => _isPerformingAction = true);

      final result = await _ticketService.deleteClientTicket(widget.ticketNumber);
      
      if (mounted) {
        if (result['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message'] ?? 'Ticket deleted successfully'),
              backgroundColor: Colors.green,
            ),
          );
          widget.onTicketUpdated?.call();
          Navigator.of(context).pop();
        } else {
          _showErrorSnackBar(result['error'] ?? 'Failed to delete ticket');
        }
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('Error deleting ticket: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isPerformingAction = false);
      }
    }
  }

  Future<bool> _showConfirmationDialog({
    required String title,
    required String message,
    required String confirmText,
    required bool isDestructive,
  }) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: isDestructive ? Colors.red : null,
              foregroundColor: isDestructive ? Colors.white : null,
            ),
            child: Text(confirmText),
          ),
        ],
      ),
    ) ?? false;
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _navigateToFullTicketView() {
    Navigator.of(context).pop(); // Close modal first
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const ClientTicketsScreen(),
      ),
    );
  }

  void _navigateToTaskManagement() {
    Navigator.of(context).pop(); // Close modal first
    // Navigate to admin tasks page - this will be handled by the parent
    // by setting the selected index to the tasks page
  }

  Widget _buildTicketDetailRow(String label, String? value, {IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: Colors.grey[600]),
            const SizedBox(width: 8),
          ],
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value ?? '-',
              style: const TextStyle(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String? status) {
    if (status == null) return const SizedBox.shrink();
    
    Color backgroundColor;
    Color textColor;
    
    switch (status.toLowerCase()) {
      case 'open':
      case 'pending':
        backgroundColor = Colors.orange.shade100;
        textColor = Colors.orange.shade800;
        break;
      case 'in_progress':
        backgroundColor = Colors.blue.shade100;
        textColor = Colors.blue.shade800;
        break;
      case 'completed':
        backgroundColor = Colors.green.shade100;
        textColor = Colors.green.shade800;
        break;
      case 'archived':
        backgroundColor = Colors.grey.shade100;
        textColor = Colors.grey.shade800;
        break;
      default:
        backgroundColor = Colors.grey.shade100;
        textColor = Colors.grey.shade800;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.confirmation_number,
                  color: Theme.of(context).primaryColor,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Client Ticket Details',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        widget.ticketNumber,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),

          // Content
          Flexible(
            child: _isLoading
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator(),
                    ),
                  )
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.error_outline,
                                size: 48,
                                color: Colors.red[300],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Error loading ticket details',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _error!,
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Colors.grey[600],
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: _loadTicketDetails,
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Status and basic info
                            Row(
                              children: [
                                _buildStatusChip(_ticketData?['status']),
                                const Spacer(),
                                Text(
                                  formatManila(
                                    DateTime.tryParse(_ticketData?['createdAt'] ?? '') ?? DateTime.now(),
                                    'MMM dd, yyyy HH:mm',
                                  ),
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),

                            // Client Information
                            Text(
                              'Client Information',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _buildTicketDetailRow(
                              'Name',
                              _ticketData?['clientName'],
                              icon: Icons.person,
                            ),
                            _buildTicketDetailRow(
                              'Email',
                              _ticketData?['clientEmail'],
                              icon: Icons.email,
                            ),
                            const SizedBox(height: 24),

                            // Service Information
                            Text(
                              'Service Information',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _buildTicketDetailRow(
                              'Service Type',
                              _ticketData?['serviceType'],
                              icon: Icons.build,
                            ),
                            if (_ticketData?['otherServiceDetails'] != null)
                              _buildTicketDetailRow(
                                'Details',
                                _ticketData?['otherServiceDetails'],
                              ),
                            const SizedBox(height: 24),

                            // Description
                            Text(
                              'Description',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.grey[50],
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey[200]!),
                              ),
                              child: Text(
                                _ticketData?['description'] ?? 'No description provided',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Additional Information
                            if (_ticketData?['assignedTo'] != null ||
                                _ticketData?['priority'] != null ||
                                _ticketData?['category'] != null) ...[
                              Text(
                                'Additional Information',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 12),
                              if (_ticketData?['assignedTo'] != null)
                                _buildTicketDetailRow(
                                  'Assigned To',
                                  _ticketData?['assignedTo'],
                                  icon: Icons.person_pin,
                                ),
                              if (_ticketData?['priority'] != null)
                                _buildTicketDetailRow(
                                  'Priority',
                                  _ticketData?['priority'],
                                  icon: Icons.priority_high,
                                ),
                              if (_ticketData?['category'] != null)
                                _buildTicketDetailRow(
                                  'Category',
                                  _ticketData?['category'],
                                  icon: Icons.category,
                                ),
                              const SizedBox(height: 24),
                            ],
                          ],
                        ),
                      ),
          ),

          // Action Buttons
          if (!_isLoading && _error == null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Column(
                children: [
                  // Primary Actions
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isPerformingAction ? null : _navigateToFullTicketView,
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('View Full Details'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isPerformingAction ? null : _navigateToTaskManagement,
                          icon: const Icon(Icons.task_alt),
                          label: const Text('Manage Tasks'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Management Actions
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isPerformingAction ? null : _archiveTicket,
                          icon: _isPerformingAction
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.archive),
                          label: const Text('Archive'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isPerformingAction ? null : _deleteTicket,
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Delete'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}