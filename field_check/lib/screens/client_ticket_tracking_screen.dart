import 'package:flutter/material.dart';
import 'package:field_check/widgets/app_widgets.dart';
import 'package:field_check/utils/app_theme.dart';
import 'package:field_check/services/client_ticket_service.dart';

class ClientTicketTrackingScreen extends StatefulWidget {
  final String ticketNumber;
  final String? emailToken;

  const ClientTicketTrackingScreen({
    super.key,
    required this.ticketNumber,
    this.emailToken,
  });

  @override
  State<ClientTicketTrackingScreen> createState() =>
      _ClientTicketTrackingScreenState();
}

class _ClientTicketTrackingScreenState extends State<ClientTicketTrackingScreen> {
  final TextEditingController _commentController = TextEditingController();
  final TextEditingController _ratingCommentController = TextEditingController();

  Map<String, dynamic>? _ticket;
  bool _isLoading = true;
  String? _error;
  int _selectedRating = 0;
  bool _isSubmittingComment = false;
  bool _isSubmittingRating = false;

  @override
  void initState() {
    super.initState();
    _loadTicket();
  }

  Future<void> _loadTicket() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final result = await ClientTicketService().getClientTicket(
        widget.ticketNumber,
        emailToken: widget.emailToken,
      );

      if (!mounted) return;

      if (result.containsKey('data')) {
        setState(() {
          _ticket = result['data'] as Map<String, dynamic>;
          _isLoading = false;
          _error = null;
        });
      } else {
        throw Exception(result['error'] ?? 'Failed to load ticket');
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

  Future<void> _submitComment() async {
    final comment = _commentController.text.trim();
    if (comment.isEmpty) return;

    setState(() => _isSubmittingComment = true);

    try {
      if (_ticket == null) {
        throw Exception('Ticket data not loaded');
      }

      final clientEmail = (_ticket!['clientEmail'] ?? '') as String;
      await ClientTicketService().submitTicketComment(
        ticketNumber: widget.ticketNumber,
        text: comment,
        authorType: 'client',
        authorEmail: clientEmail,
        emailToken: widget.emailToken,
      );

      if (!mounted) return;

      _commentController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Comment added successfully'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
      _loadTicket();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmittingComment = false);
      }
    }
  }

  Future<void> _submitRating() async {
    if (_selectedRating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a rating'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final comment = _ratingCommentController.text.trim();
    if (_selectedRating < 3 && comment.length < 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please provide detailed feedback for ratings below 3 stars'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSubmittingRating = true);

    try {
      if (_ticket == null) {
        throw Exception('Ticket data not loaded');
      }

      final clientEmail = (_ticket!['clientEmail'] ?? '') as String;
      await ClientTicketService().submitTicketRating(
        ticketNumber: widget.ticketNumber,
        stars: _selectedRating,
        comment: comment.isNotEmpty ? comment : null,
        clientEmail: clientEmail,
        emailToken: widget.emailToken,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Thank you for your feedback!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
      _ratingCommentController.clear();
      setState(() => _selectedRating = 0);
      _loadTicket();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmittingRating = false);
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
        return Colors.purple;
      case 'completed':
        return Colors.green;
      case 'closed':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  String _formatDate(dynamic dateStr) {
    try {
      final date = DateTime.parse(dateStr as String);
      return '${date.month}/${date.day}/${date.year}';
    } catch (_) {
      return 'Unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ticket Tracking'),
        elevation: 0,
      ),
      body: _isLoading
          ? AppWidgets.loadingIndicator(message: 'Loading ticket...')
          : _error != null
              ? AppWidgets.emptyState(
                  title: 'Error',
                  message: _error!,
                  icon: Icons.error_outline,
                )
              : _ticket == null
                  ? AppWidgets.emptyState(
                      title: 'No Ticket',
                      message: 'Ticket not found',
                      icon: Icons.inbox_outlined,
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(AppTheme.md),
                      child: Column(
                        spacing: AppTheme.md,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildTicketHeader(theme, isDark),
                          _buildStatusTimeline(theme, isDark),
                          _buildTicketDetails(theme, isDark),
                          if (_ticket?['comments'] != null)
                            _buildCommentsSection(theme, isDark),
                          _buildCommentForm(theme, isDark),
                          if (_ticket?['status'] == 'completed')
                            _buildRatingSection(theme, isDark),
                          const SizedBox(height: AppTheme.md),
                        ],
                      ),
                    ),
    );
  }

  Widget _buildTicketHeader(ThemeData theme, bool isDark) {
    final ticketNumber = (_ticket?['ticketNumber'] ?? 'Unknown') as String;
    final createdAt = _ticket?['createdAt'];
    final status = (_ticket?['status'] ?? 'open') as String;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  '🎫',
                  style: TextStyle(fontSize: 24),
                ),
                const SizedBox(width: AppTheme.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ticket #$ticketNumber',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Created: ${_formatDate(createdAt)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.md),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.md,
                vertical: AppTheme.sm,
              ),
              decoration: BoxDecoration(
                color: _statusColor(status).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Status: ${_formatStatus(status)}',
                style: TextStyle(
                  color: _statusColor(status),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusTimeline(ThemeData theme, bool isDark) {
    final status = (_ticket?['status'] ?? 'open') as String;
    const statuses = ['open', 'in_progress', 'pending_review', 'completed'];
    final currentIndex = statuses.indexOf(status);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Status Progress',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: AppTheme.md),
        SizedBox(
          height: 60,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(statuses.length, (idx) {
              final isPast = idx < currentIndex;
              final isCurrent = idx == currentIndex;

              return Expanded(
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: isPast || isCurrent
                          ? Colors.green
                          : Colors.grey[300],
                      child: Icon(
                        isPast ? Icons.check : Icons.circle,
                        color: isDark ? Colors.black : Colors.white,
                        size: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatStatus(statuses[idx]),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isPast || isCurrent
                            ? theme.primaryColor
                            : theme.textTheme.bodySmall?.color?.withValues(alpha: 0.5),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildTicketDetails(ThemeData theme, bool isDark) {
    final clientName = (_ticket?['clientName'] ?? 'N/A') as String;
    final clientEmail = (_ticket?['clientEmail'] ?? 'N/A') as String;
    final serviceType = (_ticket?['serviceType'] ?? 'N/A') as String;
    final description = (_ticket?['description'] ?? 'N/A') as String;
    final otherDetails = _ticket?['otherServiceDetails'] as String?;
    final assignedEmployee = _ticket?['assignedEmployeeId'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Client Information',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: AppTheme.md),
                Text('Name: $clientName'),
                Text('Email: $clientEmail'),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppTheme.md),
        Card(
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Service Details',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: AppTheme.md),
                Chip(label: Text(_formatStatus(serviceType))),
                const SizedBox(height: AppTheme.md),
                Text(
                  'Description:',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppTheme.sm),
                Text(description),
                if (otherDetails != null) ...[
                  const SizedBox(height: AppTheme.md),
                  Text(
                    'Additional Details:',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppTheme.sm),
                  Text(otherDetails),
                ],
              ],
            ),
          ),
        ),
        if (assignedEmployee != null) ...[
          const SizedBox(height: AppTheme.md),
          Card(
            elevation: 1,
            color: theme.primaryColor.withValues(alpha: 0.1),
            child: Padding(
              padding: const EdgeInsets.all(AppTheme.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Assigned Employee',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: AppTheme.md),
                  Text(assignedEmployee is Map
                      ? '${assignedEmployee['name'] ?? 'Unknown'} (${assignedEmployee['email'] ?? ''})'
                      : 'N/A'),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCommentsSection(ThemeData theme, bool isDark) {
    final comments = (_ticket?['comments'] ?? []) as List;
    if (comments.isEmpty) return const SizedBox.shrink();

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Comments (${comments.length})',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: AppTheme.md),
            ...comments.map((comment) {
              final authorType = comment['authorType'] as String? ?? 'unknown';
              final text = comment['text'] as String? ?? '';
              final createdAt = comment['createdAt'];

              String authorLabel = 'Unknown';
              Color authorColor = Colors.grey;

              if (authorType == 'client') {
                authorLabel = 'You';
                authorColor = Colors.blue;
              } else if (authorType == 'admin') {
                authorLabel = 'Admin';
                authorColor = Colors.orange;
              } else if (authorType == 'employee') {
                authorLabel = 'Support Team';
                authorColor = Colors.green;
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Chip(
                        label: Text(authorLabel),
                        backgroundColor: authorColor.withValues(alpha: 0.2),
                        labelStyle: TextStyle(color: authorColor),
                      ),
                      const SizedBox(width: AppTheme.sm),
                      Text(
                        _formatDate(createdAt),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTheme.sm),
                  Container(
                    padding: const EdgeInsets.all(AppTheme.md),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[800] : Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(text),
                  ),
                  const SizedBox(height: AppTheme.md),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildCommentForm(ThemeData theme, bool isDark) {
    if (_ticket?['status'] == 'closed') {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Add a Comment',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: AppTheme.md),
            TextFormField(
              controller: _commentController,
              decoration: InputDecoration(
                hintText: 'Share your thoughts...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: AppTheme.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _isSubmittingComment ? null : _submitComment,
                child: _isSubmittingComment
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Post Comment'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRatingSection(ThemeData theme, bool isDark) {
    final rating = _ticket?['rating'];
    final hasRating = rating != null && rating is Map && rating['stars'] != null;

    if (hasRating) {
      return Card(
        elevation: 2,
        color: Colors.green.withValues(alpha: 0.1),
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green),
                  const SizedBox(width: AppTheme.md),
                  Text(
                    'Your Rating Submitted',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.md),
              Row(
                children: List.generate(
                  5,
                  (idx) => Icon(
                    Icons.star,
                    color: idx < (rating['stars'] as int)
                        ? Colors.amber
                        : Colors.grey[300],
                  ),
                ),
              ),
              if (rating['comment'] != null && (rating['comment'] as String).isNotEmpty) ...[
                const SizedBox(height: AppTheme.md),
                Text(
                  'Your Feedback:',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppTheme.sm),
                Text(rating['comment'] as String),
              ],
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Rate Your Experience',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: AppTheme.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(
                5,
                (idx) => GestureDetector(
                  onTap: () => setState(() => _selectedRating = idx + 1),
                  child: Icon(
                    Icons.star,
                    size: 32,
                    color: idx < _selectedRating ? Colors.amber : Colors.grey[300],
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppTheme.md),
            if (_selectedRating > 0) ...[
              Text(
                _selectedRating < 3
                    ? 'Please tell us what went wrong (required for ratings below 3 stars)'
                    : 'Optional: Share more details',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _selectedRating < 3 ? Colors.orange : Colors.grey,
                ),
              ),
              const SizedBox(height: AppTheme.md),
              TextFormField(
                controller: _ratingCommentController,
                decoration: InputDecoration(
                  hintText: 'Your feedback...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: AppTheme.md),
            ],
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _isSubmittingRating || _selectedRating == 0
                    ? null
                    : _submitRating,
                child: _isSubmittingRating
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Submit Rating'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _commentController.dispose();
    _ratingCommentController.dispose();
    super.dispose();
  }
}
