import 'package:flutter/material.dart';
import '../services/ticket_service.dart';
import '../services/attachment_service.dart';
import '../screens/ticket_creation_screen.dart';
import '../services/template_service.dart';
import '../models/ticket_template_model.dart';
import '../models/ticket_model.dart';

/// Template selection and ticket creation demo screen
///
/// Shows how to integrate the complete ticket system
class TicketDashboardScreen extends StatefulWidget {
  final String apiBaseUrl;
  final String authToken;
  final String? userName;
  final String? userEmail;

  const TicketDashboardScreen({
    super.key,
    required this.apiBaseUrl,
    required this.authToken,
    this.userName,
    this.userEmail,
  });

  @override
  State<TicketDashboardScreen> createState() => _TicketDashboardScreenState();
}

class _TicketDashboardScreenState extends State<TicketDashboardScreen> {
  late final AttachmentService _attachmentService;

  List<TicketTemplateModel> _templates = [];
  List<TicketModel> _userTickets = [];
  bool _isLoadingTemplates = true;
  bool _isLoadingTickets = true;
  String? _templatesError;
  String? _ticketsError;

  @override
  void initState() {
    super.initState();
    _initializeServices();
    _loadTemplates();
    _loadTickets();
  }

  void _initializeServices() {
    _attachmentService = AttachmentService(apiBaseUrl: widget.apiBaseUrl);
    _attachmentService.updateAuthToken(widget.authToken);
  }

  Future<void> _loadTemplates() async {
    try {
      setState(() {
        _templatesError = null;
        _isLoadingTemplates = true;
      });

      final templates = await TemplateService.getTemplates();

      setState(() {
        _templates = templates;
        _isLoadingTemplates = false;
      });
    } catch (e) {
      setState(() {
        _templatesError = e.toString();
        _isLoadingTemplates = false;
      });
    }
  }

  Future<void> _loadTickets() async {
    try {
      setState(() {
        _ticketsError = null;
        _isLoadingTickets = true;
      });

      final tickets = await TicketService.getTickets();

      setState(() {
        _userTickets = tickets;
        _isLoadingTickets = false;
      });
    } catch (e) {
      setState(() {
        _ticketsError = e.toString();
        _isLoadingTickets = false;
      });
    }
  }

  void _openTicketCreation(String templateId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TicketCreationScreen(
          templateId: templateId,
          attachmentService: _attachmentService,
          onTicketCreated: (ticket) {
            // Refresh tickets list
            _loadTickets();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Service Requests'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.add_circle), text: 'New Service'),
              Tab(icon: Icon(Icons.history), text: 'My Requests'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // Tab 1: Templates / Create new
            _buildTemplatesTab(),
            // Tab 2: User tickets
            _buildTicketsTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildTemplatesTab() {
    if (_isLoadingTemplates) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_templatesError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text('Error: $_templatesError'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadTemplates,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_templates.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('No service templates available'),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _templates.length,
      itemBuilder: (context, index) {
        final template = _templates[index];
        final name = template.name;
        final description = template.description;
        final serviceType = '';

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: _getServiceIcon(serviceType),
            title: Text(name),
            subtitle: Text(
              description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.arrow_forward),
            onTap: () => _openTicketCreation(template.id),
          ),
        );
      },
    );
  }

  Widget _buildTicketsTab() {
    if (_isLoadingTickets) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_ticketsError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text('Error: $_ticketsError'),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loadTickets, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_userTickets.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('No service requests yet'),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _userTickets.length,
      itemBuilder: (context, index) {
        final ticket = _userTickets[index];
        final ticketNumber = ticket.ticketNo;
        final status = ticket.status;
        final createdAt = ticket.createdAt;
        final isEscalated = ticket.isOverdue;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: _getStatusIcon(status),
            title: Text(ticketNumber),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_capitalizeStatus(status)),
                if (createdAt != null)
                  Text(
                    _formatDate(createdAt.toIso8601String()),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
              ],
            ),
            trailing: isEscalated
                ? Tooltip(
                    message: 'SLA Breached',
                    child: Icon(Icons.warning, color: Colors.orange),
                  )
                : null,
          ),
        );
      },
    );
  }

  Widget _getServiceIcon(String serviceType) {
    final iconData =
        {
          'aircon_cleaning': Icons.air,
          'plumbing': Icons.water_drop,
          'electrical': Icons.flash_on,
          'hvac_maintenance': Icons.hvac,
          'general_repair': Icons.construction,
        }[serviceType] ??
        Icons.handyman;

    return Container(
      decoration: BoxDecoration(
        color: Colors.blue.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(iconData, color: Colors.blue.shade700),
    );
  }

  Widget _getStatusIcon(String status) {
    final (icon, color) =
        {
          'draft': (Icons.edit_outlined, Colors.grey),
          'assigned': (Icons.person, Colors.blue),
          'in_progress': (Icons.hourglass_bottom, Colors.orange),
          'completed': (Icons.check_circle, Colors.green),
          'closed': (Icons.done_all, Colors.grey),
          'cancelled': (Icons.cancel, Colors.red),
        }[status] ??
        (Icons.help, Colors.grey);

    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: color),
    );
  }

  String _capitalizeStatus(String status) {
    return status
        .replaceAll('_', ' ')
        .split(' ')
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      final now = DateTime.now();
      final diff = now.difference(date);

      if (diff.inDays == 0) {
        return '${diff.inHours}h ago';
      } else if (diff.inDays < 7) {
        return '${diff.inDays}d ago';
      } else {
        return '${date.day}/${date.month}/${date.year}';
      }
    } catch (e) {
      return dateString;
    }
  }
}
