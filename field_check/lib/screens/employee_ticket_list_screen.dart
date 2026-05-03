import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:field_check/models/ticket_model.dart';
import 'package:field_check/services/ticket_service.dart';
import 'package:field_check/screens/admin_ticket_detail_screen.dart';
import 'package:field_check/screens/employee_ticket_create_screen.dart';
import 'package:field_check/services/offline_queue_service.dart';

class EmployeeTicketListScreen extends StatefulWidget {
  const EmployeeTicketListScreen({super.key});

  @override
  State<EmployeeTicketListScreen> createState() =>
      _EmployeeTicketListScreenState();
}

class _EmployeeTicketListScreenState extends State<EmployeeTicketListScreen> {
  List<TicketModel> _tickets = [];
  bool _loading = true;
  String? _error;
  int _pendingOffline = 0;

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
      final tickets = await TicketService.getTickets();
      final pending = await OfflineQueueService().pendingCount;
      if (!mounted) return;
      setState(() {
        _tickets = tickets;
        _pendingOffline = pending;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Tickets'),
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 48,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(height: 8),
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  ElevatedButton(onPressed: _load, child: const Text('Retry')),
                ],
              ),
            )
          : Column(
              children: [
                // Offline queue banner
                if (_pendingOffline > 0)
                  MaterialBanner(
                    content: Text('$_pendingOffline ticket(s) queued offline'),
                    leading: const Icon(Icons.cloud_off, color: Colors.orange),
                    actions: [
                      TextButton(
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          final count = await OfflineQueueService()
                              .processQueue();
                          if (!mounted) return;
                          messenger.showSnackBar(
                            SnackBar(content: Text('Synced $count ticket(s)')),
                          );
                          _load();
                        },
                        child: const Text('Sync Now'),
                      ),
                    ],
                  ),
                Expanded(
                  child: _tickets.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.confirmation_number_outlined,
                                size: 64,
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.3,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No tickets assigned',
                                style: theme.textTheme.titleMedium,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Create a new ticket to get started.',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: _tickets.length,
                            itemBuilder: (ctx, i) =>
                                _buildTicketCard(_tickets[i], theme),
                          ),
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const EmployeeTicketCreateScreen(),
            ),
          );
          if (result == true) _load();
        },
        icon: const Icon(Icons.add),
        label: const Text('New Ticket'),
      ),
    );
  }

  Widget _buildTicketCard(TicketModel ticket, ThemeData theme) {
    final statusColor = _getStatusColor(ticket.status);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AdminTicketDetailScreen(ticketId: ticket.id),
            ),
          );
          _load();
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_getStatusIcon(ticket.status), color: statusColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          ticket.ticketNo,
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            ticket.templateName ?? 'Ticket',
                            style: theme.textTheme.titleSmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _humanize(ticket.status),
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (ticket.slaDeadline != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Icon(
                      Icons.timer,
                      size: 16,
                      color: ticket.isOverdue
                          ? Colors.red
                          : ticket.isAtRisk
                          ? Colors.orange
                          : Colors.green,
                    ),
                    Text(
                      DateFormat('MMM d').format(ticket.slaDeadline!.toLocal()),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'open':
        return Colors.blue;
      case 'in_progress':
        return Colors.orange;
      case 'completed':
        return Colors.green;
      case 'verified':
        return Colors.teal;
      case 'closed':
        return Colors.grey;
      default:
        return Colors.blue;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'open':
        return Icons.fiber_new;
      case 'in_progress':
        return Icons.play_arrow;
      case 'completed':
        return Icons.check_circle;
      case 'verified':
        return Icons.verified;
      case 'closed':
        return Icons.archive;
      default:
        return Icons.confirmation_number;
    }
  }

  String _humanize(String s) => s
      .replaceAll('_', ' ')
      .split(' ')
      .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
      .join(' ');
}
