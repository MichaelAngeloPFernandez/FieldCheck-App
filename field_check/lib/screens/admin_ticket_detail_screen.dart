import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:field_check/models/ticket_model.dart';
import 'package:field_check/services/ticket_service.dart';

class AdminTicketDetailScreen extends StatefulWidget {
  final String ticketId;
  const AdminTicketDetailScreen({super.key, required this.ticketId});

  @override
  State<AdminTicketDetailScreen> createState() => _AdminTicketDetailScreenState();
}

class _AdminTicketDetailScreenState extends State<AdminTicketDetailScreen> {
  TicketModel? _ticket;
  List<Map<String, dynamic>> _auditTrail = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final ticket = await TicketService.getTicket(widget.ticketId);
      final audit = await TicketService.getAuditTrail(widget.ticketId);
      if (!mounted) return;
      setState(() {
        _ticket = ticket;
        _auditTrail = audit;
        _loading = false;
      });

    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _changeStatus(String newStatus) async {
    try {
      final updated = await TicketService.changeStatus(widget.ticketId, newStatus);
      setState(() => _ticket = updated);
      _load(); // Refresh audit trail
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Status changed to ${_humanize(newStatus)}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ticket Details')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_ticket == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ticket Details')),
        body: const Center(child: Text('Ticket not found')),
      );
    }

    final ticket = _ticket!;
    final statusColor = _getStatusColor(ticket.status);

    return Scaffold(
      appBar: AppBar(
        title: Text(ticket.ticketNo),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header card
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _humanize(ticket.status),
                            style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const Spacer(),
                        if (ticket.slaDeadline != null)
                          _buildSlaChip(ticket, theme),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(ticket.templateName ?? 'Ticket',
                        style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    _infoRow(Icons.person_outline, 'Assignee',
                        ticket.assigneeName ?? 'Unassigned'),
                    _infoRow(Icons.person, 'Created by',
                        ticket.createdByName ?? 'Unknown'),
                    if (ticket.createdAt != null)
                      _infoRow(Icons.calendar_today, 'Created',
                          DateFormat('MMM d, y h:mm a').format(ticket.createdAt!.toLocal())),
                    if (ticket.geofenceName != null)
                      _infoRow(Icons.location_on, 'Geofence', ticket.geofenceName!),
                    if (ticket.notes.isNotEmpty)
                      _infoRow(Icons.note, 'Notes', ticket.notes),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Status actions
            Text('Change Status', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ['open', 'in_progress', 'completed', 'verified', 'closed']
                  .where((s) => s != ticket.status)
                  .map((s) => ActionChip(
                        label: Text(_humanize(s)),
                        avatar: Icon(_getStatusIcon(s), size: 18),
                        onPressed: () => _changeStatus(s),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 24),

            // Form data
            Text('Ticket Data', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (ticket.data.isNotEmpty)
              ...ticket.data.entries.map((e) {
                final value = e.value;
                if (value is Map) {
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_humanize(e.key), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                          ...value.entries.map((ve) => Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Row(
                                  children: [
                                    Text('${_humanize(ve.key.toString())}: ', style: const TextStyle(fontWeight: FontWeight.w500)),
                                    Expanded(child: Text(ve.value.toString())),
                                  ],
                                ),
                              )),
                        ],
                      ),
                    ),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 140,
                        child: Text(_humanize(e.key),
                            style: const TextStyle(fontWeight: FontWeight.w500)),
                      ),
                      Expanded(child: Text(value.toString())),
                    ],
                  ),
                );
              }),
            const SizedBox(height: 24),

            // Audit trail
            Text('Audit Trail',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (_auditTrail.isEmpty)
              const Text('No audit entries yet.')
            else
              ..._auditTrail.map((entry) => _buildAuditEntry(entry, theme)),
          ],
        ),
      ),
    );
  }

  Widget _buildSlaChip(TicketModel ticket, ThemeData theme) {
    final color = ticket.isOverdue ? Colors.red : ticket.isAtRisk ? Colors.orange : Colors.green;
    final label = ticket.isOverdue ? 'OVERDUE' : ticket.isAtRisk ? 'AT RISK' : 'ON TIME';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  Widget _buildAuditEntry(Map<String, dynamic> entry, ThemeData theme) {
    final action = entry['action']?.toString() ?? '';
    final actor = entry['actor_id'];
    final actorName = actor is Map ? actor['name']?.toString() ?? 'System' : 'System';
    final details = entry['details'] is Map ? entry['details'] as Map : {};
    final createdAt = entry['created_at'] != null
        ? DateTime.tryParse(entry['created_at'].toString())
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: theme.colorScheme.primary, width: 3)),
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(_humanize(action),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const Spacer(),
              if (createdAt != null)
                Text(DateFormat('MMM d, h:mm a').format(createdAt.toLocal()),
                    style: TextStyle(fontSize: 11, color: theme.hintColor)),
            ],
          ),
          Text('by $actorName', style: TextStyle(fontSize: 12, color: theme.hintColor)),
          if (details.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                details.entries.map((e) => '${_humanize(e.key.toString())}: ${e.value}').join(' · '),
                style: TextStyle(fontSize: 11, color: theme.hintColor),
              ),
            ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'open': return Colors.blue;
      case 'in_progress': return Colors.orange;
      case 'completed': return Colors.green;
      case 'verified': return Colors.teal;
      case 'closed': return Colors.grey;
      case 'blocked': return Colors.red;
      default: return Colors.blue;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'open': return Icons.fiber_new;
      case 'in_progress': return Icons.play_arrow;
      case 'completed': return Icons.check_circle;
      case 'verified': return Icons.verified;
      case 'closed': return Icons.archive;
      default: return Icons.circle;
    }
  }

  String _humanize(String s) => s
      .replaceAll('_', ' ')
      .split(' ')
      .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
      .join(' ');
}
