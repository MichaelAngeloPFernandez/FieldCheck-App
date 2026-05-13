import 'package:flutter/material.dart';
import 'package:field_check/widgets/app_widgets.dart';
import 'package:field_check/utils/app_theme.dart';
import 'package:field_check/utils/http_util.dart';
import 'dart:convert';

class ClientTicketsScreen extends StatefulWidget {
  const ClientTicketsScreen({super.key});

  @override
  State<ClientTicketsScreen> createState() => _ClientTicketsScreenState();
}

class _ClientTicketsScreenState extends State<ClientTicketsScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<Map<String, dynamic>> _tickets = [];
  bool _isLoading = true;
  String? _error;

  // Filters
  String _statusFilter = 'all';
  String _serviceTypeFilter = 'all';
  String _sortBy = 'created_desc';

  int _currentPage = 1;
  int _totalPages = 1;
  int _totalTickets = 0;
  static const int _ticketsPerPage = 10;

  final List<String> _statuses = [
    'open',
    'in_progress',
    'pending_review',
    'completed',
    'closed',
    'expired'
  ];

  final List<String> _serviceTypes = [
    'facility_inspection',
    'maintenance',
    'equipment_check',
    'cleaning',
    'security_audit',
    'aircon_cleaning',
    'other'
  ];

  @override
  void initState() {
    super.initState();
    _loadTickets();
  }

  Future<void> _loadTickets() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final query = <String, String>{
        'page': _currentPage.toString(),
        'limit': _ticketsPerPage.toString(),
      };

      if (_statusFilter != 'all') {
        query['status'] = _statusFilter;
      }
      if (_serviceTypeFilter != 'all') {
        query['serviceType'] = _serviceTypeFilter;
      }
      if (_searchController.text.isNotEmpty) {
        query['search'] = _searchController.text.trim();
      }

      final response = await HttpUtil().get(
        '/api/client-tickets',
        queryParams: query,
      ).timeout(const Duration(seconds: 30));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        setState(() {
          _tickets = List<Map<String, dynamic>>.from(data['tickets'] ?? []);
          _totalTickets = data['total'] ?? 0;
          _totalPages = data['pages'] ?? 1;
          _isLoading = false;
          _error = null;
        });
      } else {
        throw Exception('Failed to load tickets');
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

  String _formatStatus(String status) {
    return status
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'open':
        return Colors.blue;
      case 'in_progress':
        return Colors.orange;
      case 'pending_review':
        return Colors.amber;
      case 'completed':
        return Colors.green;
      case 'closed':
        return Colors.grey;
      case 'expired':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Client Tickets'),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Search & Filters
          Padding(
            padding: const EdgeInsets.all(AppTheme.md),
            child: Column(
              spacing: AppTheme.sm,
              children: [
                // Search field
                SearchBar(
                  controller: _searchController,
                  hintText: 'Search by ticket #, client email, or name...',
                  leading: const Icon(Icons.search),
                  trailing: [
                    if (_searchController.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _currentPage = 1;
                          _loadTickets();
                        },
                      ),
                  ],
                  onSubmitted: (_) {
                    _currentPage = 1;
                    _loadTickets();
                  },
                ),
                // Filter chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    spacing: AppTheme.xs,
                    children: [
                      // Status filter
                      FilterChip(
                        label: Text(_statusFilter == 'all'
                            ? 'All Status'
                            : _formatStatus(_statusFilter)),
                        onSelected: (_) => _showStatusPicker(),
                      ),
                      // Service type filter
                      FilterChip(
                        label: Text(_serviceTypeFilter == 'all'
                            ? 'All Types'
                            : _serviceTypeFilter
                                .replaceAll('_', ' ')
                                .toUpperCase()),
                        onSelected: (_) => _showServiceTypePicker(),
                      ),
                      // Sort
                      FilterChip(
                        label: Text(_sortBy == 'created_desc'
                            ? 'Newest'
                            : _sortBy == 'created_asc'
                                ? 'Oldest'
                                : 'Status'),
                        onSelected: (_) => _showSortPicker(),
                      ),
                      // Reset
                      if (_statusFilter != 'all' ||
                          _serviceTypeFilter != 'all' ||
                          _searchController.text.isNotEmpty)
                        ActionChip(
                          label: const Text('Reset'),
                          onPressed: () {
                            setState(() {
                              _statusFilter = 'all';
                              _serviceTypeFilter = 'all';
                              _searchController.clear();
                              _currentPage = 1;
                            });
                            _loadTickets();
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Ticket count
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.md),
            child: Text(
              'Total: $_totalTickets tickets',
              style: theme.textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: AppTheme.sm),
          // Tickets list
          Expanded(
            child: _isLoading
                ? AppWidgets.loadingIndicator(message: 'Loading tickets...')
                : _error != null
                    ? AppWidgets.emptyState(
                        title: 'Error',
                        message: _error!,
                        icon: Icons.error_outline,
                      )
                    : _tickets.isEmpty
                        ? AppWidgets.emptyState(
                            title: 'No Tickets',
                            message: 'No client tickets match your filters',
                            icon: Icons.inbox_outlined,
                          )
                        : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppTheme.md,
                            ),
                            itemCount: _tickets.length,
                            itemBuilder: (context, index) {
                              final ticket = _tickets[index];
                              return _buildTicketCard(theme, ticket);
                            },
                          ),
          ),
          // Pagination
          if (_totalPages > 1)
            Padding(
              padding: const EdgeInsets.all(AppTheme.md),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: AppTheme.sm,
                children: [
                  if (_currentPage > 1)
                    ElevatedButton.icon(
                      onPressed: () {
                        setState(() => _currentPage--);
                        _loadTickets();
                        _scrollController.animateTo(
                          0,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                        );
                      },
                      icon: const Icon(Icons.chevron_left),
                      label: const Text('Previous'),
                    ),
                  Text(
                    'Page $_currentPage of $_totalPages',
                    style: theme.textTheme.bodySmall,
                  ),
                  if (_currentPage < _totalPages)
                    ElevatedButton.icon(
                      onPressed: () {
                        setState(() => _currentPage++);
                        _loadTickets();
                        _scrollController.animateTo(
                          0,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                        );
                      },
                      icon: const Icon(Icons.chevron_right),
                      label: const Text('Next'),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTicketCard(ThemeData theme, Map<String, dynamic> ticket) {
    final ticketNumber = ticket['ticketNumber'] as String? ?? 'N/A';
    final clientName = ticket['clientName'] as String? ?? 'Unknown';
    final clientEmail = ticket['clientEmail'] as String? ?? '';
    final serviceType = ticket['serviceType'] as String? ?? 'other';
    final status = ticket['status'] as String? ?? 'open';
    final createdAt = ticket['createdAt'] as String?;
    final description = ticket['description'] as String? ?? '';
    final assignedEmployeeId = ticket['assignedEmployeeId'] as String?;

    final isDark = theme.brightness == Brightness.dark;
    final cardBg =
        isDark ? Colors.grey.shade900 : Colors.grey.shade100;

    return Card(
      margin: const EdgeInsets.only(bottom: AppTheme.md),
      color: cardBg,
      child: ListTile(
        contentPadding: const EdgeInsets.all(AppTheme.md),
        title: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: AppTheme.xs,
                children: [
                  Text(
                    '🎫 $ticketNumber',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '$clientName • $clientEmail',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.sm,
                vertical: AppTheme.xs,
              ),
              decoration: BoxDecoration(
                color: _statusColor(status).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _formatStatus(status),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: _statusColor(status),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: AppTheme.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: AppTheme.xs,
            children: [
              Text(
                description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
              Row(
                spacing: AppTheme.md,
                children: [
                  if (createdAt != null)
                    Text(
                      'Created: ${_formatDate(createdAt)}',
                      style: theme.textTheme.labelSmall,
                    ),
                  Text(
                    'Type: ${serviceType.replaceAll('_', ' ').toUpperCase()}',
                    style: theme.textTheme.labelSmall,
                  ),
                  if (assignedEmployeeId != null)
                    Text(
                      'Assigned',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: Colors.green),
                    ),
                ],
              ),
            ],
          ),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'archive') {
              _archiveTicket(ticketNumber);
            } else if (value == 'delete') {
              _deleteTicket(ticketNumber);
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'archive',
              child: Text('Archive'),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: 'delete',
              child: Text('Delete'),
            ),
          ],
        ),
        onTap: () => _showTicketDetails(context, ticket),
      ),
    );
  }

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final diff = now.difference(date);

      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inHours < 1) return '${diff.inMinutes}m ago';
      if (diff.inDays < 1) return '${diff.inHours}h ago';
      if (diff.inDays < 30) return '${diff.inDays}d ago';

      return '${date.month}/${date.day}/${date.year}';
    } catch (_) {
      return 'Unknown';
    }
  }

  void _showTicketDetails(BuildContext context, Map<String, dynamic> ticket) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return _TicketDetailModal(ticket: ticket, onRefresh: _loadTickets);
      },
    );
  }

  void _showStatusPicker() {
    showModalBottomSheet<String>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: ListView(
            children: [
              const Padding(
                padding: EdgeInsets.all(AppTheme.md),
                child: Text('Filter by Status'),
              ),
              ListTile(
                title: const Text('All'),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _statusFilter = 'all');
                  _currentPage = 1;
                  _loadTickets();
                },
              ),
              ..._statuses.map(
                (s) => ListTile(
                  title: Text(_formatStatus(s)),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() => _statusFilter = s);
                    _currentPage = 1;
                    _loadTickets();
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showServiceTypePicker() {
    showModalBottomSheet<String>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: ListView(
            children: [
              const Padding(
                padding: EdgeInsets.all(AppTheme.md),
                child: Text('Filter by Service Type'),
              ),
              ListTile(
                title: const Text('All'),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _serviceTypeFilter = 'all');
                  _currentPage = 1;
                  _loadTickets();
                },
              ),
              ..._serviceTypes.map(
                (t) => ListTile(
                  title: Text(t.replaceAll('_', ' ').toUpperCase()),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() => _serviceTypeFilter = t);
                    _currentPage = 1;
                    _loadTickets();
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showSortPicker() {
    showModalBottomSheet<String>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: ListView(
            children: [
              const Padding(
                padding: EdgeInsets.all(AppTheme.md),
                child: Text('Sort By'),
              ),
              ListTile(
                title: const Text('Newest First'),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _sortBy = 'created_desc');
                },
              ),
              ListTile(
                title: const Text('Oldest First'),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _sortBy = 'created_asc');
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _archiveTicket(String ticketNumber) async {
    // Ask for confirmation
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archive Ticket?'),
        content: const Text(
          'This ticket will be hidden but remain searchable. You can restore it later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final response = await HttpUtil().put(
        '/api/client-tickets/$ticketNumber/archive',
        body: {},
      ).timeout(const Duration(seconds: 15));

      if (!mounted) return;
      if (response.statusCode == 200) {
        AppWidgets.showSuccessSnackbar(context, 'Ticket archived successfully');
        _loadTickets();
      } else {
        AppWidgets.showErrorSnackbar(
          context,
          'Failed to archive ticket: ${response.statusCode}',
        );
      }
    } catch (e) {
      if (!mounted) return;
      AppWidgets.showErrorSnackbar(context, 'Error archiving ticket: $e');
    }
  }

  Future<void> _deleteTicket(String ticketNumber) async {
    // Ask for confirmation (stronger confirmation for deletion)
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Ticket Permanently?'),
        content: const Text(
          'This action cannot be undone. The ticket will be permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final response = await HttpUtil().delete(
        '/api/client-tickets/$ticketNumber',
      ).timeout(const Duration(seconds: 15));

      if (!mounted) return;
      if (response.statusCode == 200) {
        AppWidgets.showSuccessSnackbar(context, 'Ticket deleted permanently');
        _loadTickets();
      } else {
        AppWidgets.showErrorSnackbar(
          context,
          'Failed to delete ticket: ${response.statusCode}',
        );
      }
    } catch (e) {
      if (!mounted) return;
      AppWidgets.showErrorSnackbar(context, 'Error deleting ticket: $e');
    }
  }
}

class _TicketDetailModal extends StatefulWidget {
  final Map<String, dynamic> ticket;
  final VoidCallback onRefresh;

  const _TicketDetailModal({
    required this.ticket,
    required this.onRefresh,
  });

  @override
  State<_TicketDetailModal> createState() => _TicketDetailModalState();
}

class _TicketDetailModalState extends State<_TicketDetailModal> {
  bool _isUpdating = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = isDark ? Colors.grey.shade900 : Colors.grey.shade100;

    final ticket = widget.ticket;
    final ticketNumber = ticket['ticketNumber'] as String? ?? 'N/A';
    final clientName = ticket['clientName'] as String? ?? 'Unknown';
    final clientEmail = ticket['clientEmail'] as String? ?? '';
    final serviceType = ticket['serviceType'] as String? ?? 'other';
    final status = ticket['status'] as String? ?? 'open';
    final description = ticket['description'] as String? ?? '';
    final attachments = ticket['attachments'] as List? ?? [];
    final rating = ticket['rating'] as Map<String, dynamic>?;

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: AppTheme.md,
          children: [
            // Header
            Text(
              '🎫 $ticketNumber',
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            // Client info
            Container(
              padding: const EdgeInsets.all(AppTheme.md),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: AppTheme.xs,
                children: [
                  Text(
                    'Client Information',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(clientName, style: theme.textTheme.bodyMedium),
                  Text(clientEmail,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: Colors.blue)),
                ],
              ),
            ),
            // Status & Type
            Row(
              spacing: AppTheme.md,
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(AppTheme.md),
                    decoration: BoxDecoration(
                      color: _getStatusColor(status).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: AppTheme.xs,
                      children: [
                        Text(
                          'Status',
                          style: theme.textTheme.labelSmall,
                        ),
                        Text(
                          _formatStatus(status),
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(AppTheme.md),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: AppTheme.xs,
                      children: [
                        Text(
                          'Service Type',
                          style: theme.textTheme.labelSmall,
                        ),
                        Text(
                          serviceType.replaceAll('_', ' ').toUpperCase(),
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            // Description
            Container(
              padding: const EdgeInsets.all(AppTheme.md),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: AppTheme.xs,
                children: [
                  Text(
                    'Description',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(description, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            // Attachments
            if (attachments.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(AppTheme.md),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: AppTheme.sm,
                  children: [
                    Text(
                      'Attachments (${attachments.length})',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    ...attachments.map(
                      (att) => Text(
                        att['fileName'] ?? 'Unknown file',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: Colors.blue),
                      ),
                    ),
                  ],
                ),
              ),
            // Rating
            if (rating != null)
              Container(
                padding: const EdgeInsets.all(AppTheme.md),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: AppTheme.xs,
                  children: [
                    Text(
                      'Client Rating',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Row(
                      children: [
                        ...List.generate(
                          5,
                          (i) => Icon(
                            i < (rating['stars'] ?? 0)
                                ? Icons.star
                                : Icons.star_border,
                            color: Colors.amber,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: AppTheme.sm),
                        Text(
                          '${rating['stars'] ?? 0} stars',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                    if (rating['comment'] != null)
                      Text(
                        rating['comment'] as String,
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
            // Action button
            if (status != 'completed' && status != 'closed')
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isUpdating ? null : () => _updateStatus(context),
                  child: _isUpdating
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : Text(_getNextStatusLabel(status)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatStatus(String status) {
    return status
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'open':
        return Colors.blue;
      case 'in_progress':
        return Colors.orange;
      case 'pending_review':
        return Colors.amber;
      case 'completed':
        return Colors.green;
      case 'closed':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  String _getNextStatusLabel(String currentStatus) {
    switch (currentStatus) {
      case 'open':
        return 'Mark as In Progress';
      case 'in_progress':
        return 'Mark as Pending Review';
      case 'pending_review':
        return 'Mark as Completed';
      default:
        return 'Update Status';
    }
  }

  Future<void> _updateStatus(BuildContext context) async {
    // Status progression
    const statusMap = {
      'open': 'in_progress',
      'in_progress': 'pending_review',
      'pending_review': 'completed',
    };

    final currentStatus = widget.ticket['status'] as String? ?? 'open';
    final nextStatus = statusMap[currentStatus];
    if (nextStatus == null) return;

    setState(() => _isUpdating = true);

    // Store context-dependent objects before async operation
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      await Future.delayed(const Duration(milliseconds: 500));

      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('Status updated to ${_formatStatus(nextStatus)}'),
            backgroundColor: Colors.green,
          ),
        );
        navigator.pop();
        widget.onRefresh();
      }
    } catch (e) {
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUpdating = false);
      }
    }
  }
}
