import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:field_check/models/ticket_model.dart';
import 'package:field_check/services/ticket_service.dart';
import 'package:field_check/screens/admin_ticket_detail_screen.dart';
import 'package:field_check/screens/employee_ticket_create_screen.dart';

class AdminTicketListScreen extends StatefulWidget {
  const AdminTicketListScreen({super.key});

  @override
  State<AdminTicketListScreen> createState() => _AdminTicketListScreenState();
}

class _AdminTicketListScreenState extends State<AdminTicketListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<TicketModel> _tickets = [];
  bool _loading = true;
  String? _error;
  String _statusFilter = 'all';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) _loadTickets();
    });
    _loadTickets();
  }

  Future<void> _loadTickets() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final archived = _tabController.index == 2;
      final tickets = await TicketService.getTickets(archived: archived);
      if (!mounted) return;
      setState(() {
        _tickets = tickets;
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

  List<TicketModel> get _filteredTickets {
    if (_tabController.index == 1) {
      return _tickets.where((t) => t.isOverdue || t.isAtRisk).toList();
    }
    if (_statusFilter == 'all') return _tickets;
    return _tickets.where((t) => t.status == _statusFilter).toList();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tickets'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadTickets,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Active'),
            Tab(text: 'SLA Alerts'),
            Tab(text: 'Archived'),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_tabController.index == 0)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  for (final s in ['all', 'open', 'in_progress', 'completed', 'verified', 'closed'])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: Text(s == 'all' ? 'All' : _humanize(s)),
                        selected: _statusFilter == s,
                        onSelected: (v) {
                          setState(() => _statusFilter = v ? s : 'all');
                        },
                        selectedColor: theme.colorScheme.primaryContainer,
                      ),
                    ),
                ],
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.error_outline,
                                size: 48, color: theme.colorScheme.error),
                            const SizedBox(height: 8),
                            Text(_error!, textAlign: TextAlign.center),
                            const SizedBox(height: 16),
                            ElevatedButton(
                                onPressed: _loadTickets,
                                child: const Text('Retry')),
                          ],
                        ),
                      )
                    : _filteredTickets.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.confirmation_number_outlined,
                                    size: 64,
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.3)),
                                const SizedBox(height: 12),
                                Text('No tickets found',
                                    style: theme.textTheme.titleMedium),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _loadTickets,
                            child: ListView.builder(
                              padding: const EdgeInsets.all(12),
                              itemCount: _filteredTickets.length,
                              itemBuilder: (ctx, i) =>
                                  _buildTicketCard(_filteredTickets[i], theme),
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
                builder: (_) => const EmployeeTicketCreateScreen()),
          );
          if (result == true) _loadTickets();
        },
        icon: const Icon(Icons.add),
        label: const Text('New Ticket'),
      ),
    );
  }

  Widget _buildTicketCard(TicketModel ticket, ThemeData theme) {
    final statusColor = _getStatusColor(ticket.status, theme);
    final slaColor = ticket.isOverdue
        ? Colors.red
        : ticket.isAtRisk
            ? Colors.orange
            : Colors.green;

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
          _loadTickets();
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      ticket.ticketNo,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      ticket.templateName ?? 'Ticket',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _humanize(ticket.status),
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: statusColor, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.person_outline, size: 14, color: theme.hintColor),
                  const SizedBox(width: 4),
                  Text(
                    ticket.assigneeName ?? 'Unassigned',
                    style: theme.textTheme.bodySmall,
                  ),
                  const Spacer(),
                  if (ticket.slaDeadline != null) ...[
                    Icon(Icons.timer_outlined, size: 14, color: slaColor),
                    const SizedBox(width: 4),
                    Text(
                      DateFormat('MMM d, h:mm a')
                          .format(ticket.slaDeadline!.toLocal()),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: slaColor),
                    ),
                  ],
                ],
              ),
              if (ticket.createdAt != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Created ${DateFormat('MMM d, y').format(ticket.createdAt!.toLocal())}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.hintColor),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(String status, ThemeData theme) {
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
      case 'blocked':
        return Colors.red;
      default:
        return theme.colorScheme.primary;
    }
  }

  String _humanize(String s) => s
      .replaceAll('_', ' ')
      .split(' ')
      .map((w) =>
          w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
      .join(' ');
}
