// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:field_check/utils/http_util.dart';
import 'package:field_check/utils/app_theme.dart';
import 'dart:convert';

class ClientGradesReportScreen extends StatefulWidget {
  final bool embedded;

  const ClientGradesReportScreen({super.key, this.embedded = false});

  @override
  State<ClientGradesReportScreen> createState() =>
      _ClientGradesReportScreenState();
}

class _ClientGradesReportScreenState extends State<ClientGradesReportScreen> {
  List<Map<String, dynamic>> _ratings = [];
  bool _isLoading = true;
  String? _error;

  // Filters
  String _ratingFilter = 'all'; // 'all', '5', '4', '3', '2', '1'
  String _sortBy = 'recent'; // 'recent', 'oldest', 'highest', 'lowest'
  final TextEditingController _searchController = TextEditingController();

  int _currentPage = 1;
  int _totalPages = 1;
  int _totalRatings = 0;
  static const int _ratingsPerPage = 15;

  @override
  void initState() {
    super.initState();
    _loadRatings();
  }

  Future<void> _loadRatings() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final query = <String, String>{
        'page': _currentPage.toString(),
        'limit': _ratingsPerPage.toString(),
      };

      if (_ratingFilter != 'all') {
        query['stars'] = _ratingFilter;
      }
      if (_searchController.text.isNotEmpty) {
        query['search'] = _searchController.text.trim();
      }

      // Add sort parameter
      query['sort'] = _sortBy;

      final response = await HttpUtil().get(
        '/api/ticket-ratings',
        queryParams: query,
      ).timeout(const Duration(seconds: 30));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        setState(() {
          _ratings = List<Map<String, dynamic>>.from(data['ratings'] ?? []);
          _totalRatings = data['total'] ?? 0;
          _totalPages = data['pages'] ?? 1;
          _isLoading = false;
          _error = null;
        });
      } else {
        throw Exception('Failed to load ratings');
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

  double _getAverageRating() {
    if (_ratings.isEmpty) return 0;
    final sum = _ratings.fold<int>(
      0,
      (prev, rating) => prev + (rating['stars'] as int? ?? 0),
    );
    return sum / _ratings.length;
  }

  int _getRatingCount(int stars) {
    return _ratings.where((r) => r['stars'] == stars).length;
  }

  Color _getStarColor(int stars) {
    if (stars >= 4) return Colors.green;
    if (stars >= 3) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text('Error: $_error'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadRatings,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_ratings.isEmpty && _searchController.text.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.star_outline,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No ratings yet',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Completed tickets with ratings will appear here',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Summary Stats
            if (_totalRatings > 0) ...[
              Card(
                elevation: 1,
                child: Padding(
                  padding: const EdgeInsets.all(AppTheme.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Overall Performance',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: AppTheme.md),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Average Rating',
                                  style: theme.textTheme.bodySmall,
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Text(
                                      _getAverageRating().toStringAsFixed(1),
                                      style: theme.textTheme.headlineMedium
                                          ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: _getStarColor(
                                          _getAverageRating().toInt(),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    ...List.generate(5, (i) {
                                      final filled = (i + 1) <=
                                          _getAverageRating().toInt();
                                      return Icon(
                                        filled
                                            ? Icons.star
                                            : Icons.star_outline,
                                        color: filled
                                            ? Colors.amber
                                            : Colors.grey[400],
                                        size: 16,
                                      );
                                    }),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Total Ratings',
                                  style: theme.textTheme.bodySmall,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _totalRatings.toString(),
                                  style: theme.textTheme.headlineMedium
                                      ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppTheme.md),
                      // Rating distribution
                      ...List.generate(5, (idx) {
                        final stars = 5 - idx;
                        final count = _getRatingCount(stars);
                        final percentage = _totalRatings > 0
                            ? (count / _totalRatings * 100)
                            : 0;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 60,
                                child: Row(
                                  children: [
                                    Text('$stars'),
                                    const SizedBox(width: 4),
                                    const Icon(
                                      Icons.star,
                                      size: 14,
                                      color: Colors.amber,
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: percentage / 100,
                                    minHeight: 8,
                                    backgroundColor:
                                        Colors.grey.withValues(alpha: 0.3),
                                    valueColor: AlwaysStoppedAnimation(
                                      _getStarColor(stars),
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 50,
                                child: Text(
                                  '$count (${percentage.toStringAsFixed(0)}%)',
                                  textAlign: TextAlign.right,
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppTheme.md),
            ],

            // Search and Filters
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search ticket or email...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    onChanged: (_) {
                      _currentPage = 1;
                      _loadRatings();
                    },
                  ),
                ),
                const SizedBox(width: AppTheme.sm),
                PopupMenuButton<String>(
                  tooltip: 'Rating Filter',
                  onSelected: (value) {
                    setState(() => _ratingFilter = value);
                    _currentPage = 1;
                    _loadRatings();
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'all',
                      child: Text('All Ratings'),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: '5',
                      child: Text('⭐⭐⭐⭐⭐ (5 stars)'),
                    ),
                    const PopupMenuItem(
                      value: '4',
                      child: Text('⭐⭐⭐⭐ (4 stars)'),
                    ),
                    const PopupMenuItem(
                      value: '3',
                      child: Text('⭐⭐⭐ (3 stars)'),
                    ),
                    const PopupMenuItem(
                      value: '2',
                      child: Text('⭐⭐ (2 stars)'),
                    ),
                    const PopupMenuItem(
                      value: '1',
                      child: Text('⭐ (1 star)'),
                    ),
                  ],
                  child: OutlinedButton(
                    onPressed: null,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.filter_list, size: 18),
                        const SizedBox(width: 4),
                        Text(
                          _ratingFilter == 'all'
                              ? 'Filter'
                              : '$_ratingFilter ⭐',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: AppTheme.sm),
                PopupMenuButton<String>(
                  tooltip: 'Sort',
                  onSelected: (value) {
                    setState(() => _sortBy = value);
                    _currentPage = 1;
                    _loadRatings();
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'recent',
                      child: Text('Newest First'),
                    ),
                    const PopupMenuItem(
                      value: 'oldest',
                      child: Text('Oldest First'),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'highest',
                      child: Text('Highest Rating'),
                    ),
                    const PopupMenuItem(
                      value: 'lowest',
                      child: Text('Lowest Rating'),
                    ),
                  ],
                  child: OutlinedButton(
                    onPressed: null,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.sort, size: 18),
                        const SizedBox(width: 4),
                        const Text('Sort'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.md),

            // Ratings List
            if (_ratings.isNotEmpty) ...[
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _ratings.length,
                itemBuilder: (context, index) {
                  final rating = _ratings[index];
                  final ticketNumber = rating['ticketNumber'] as String? ?? 'N/A';
                  final clientEmail = rating['clientEmail'] as String? ?? 'N/A';
                  final stars = rating['stars'] as int? ?? 0;
                  final comment = rating['comment'] as String?;
                  final submittedAt = rating['submittedAt'] as String?;

                  return Card(
                    margin: const EdgeInsets.only(bottom: AppTheme.md),
                    elevation: 1,
                    child: Padding(
                      padding: const EdgeInsets.all(AppTheme.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Ticket #: $ticketNumber',
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      clientEmail,
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              // Star rating display
                              Column(
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: List.generate(5, (i) {
                                      final isFilled = (i + 1) <= stars;
                                      return Icon(
                                        isFilled
                                            ? Icons.star
                                            : Icons.star_outline,
                                        color: isFilled
                                            ? _getStarColor(stars)
                                            : Colors.grey[400],
                                        size: 18,
                                      );
                                    }),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '$stars/5',
                                    style: theme.textTheme.labelSmall
                                        ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: _getStarColor(stars),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          if (comment != null && comment.isNotEmpty) ...[
                            const SizedBox(height: AppTheme.md),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(AppTheme.sm),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.grey.shade800
                                    : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                comment,
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          ],
                          if (submittedAt != null) ...[
                            const SizedBox(height: AppTheme.sm),
                            Text(
                              'Submitted: ${_formatDate(submittedAt)}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ] else if (_searchController.text.isNotEmpty) ...[
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.search_off,
                      size: 48,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No ratings found',
                      style: theme.textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
            ],

            // Pagination
            if (_totalPages > 1) ...[
              const SizedBox(height: AppTheme.md),
              Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_currentPage > 1)
                      IconButton(
                        icon: const Icon(Icons.chevron_left),
                        onPressed: () {
                          setState(() => _currentPage--);
                          _loadRatings();
                        },
                      ),
                    Text(
                      'Page $_currentPage of $_totalPages',
                      style: theme.textTheme.bodySmall,
                    ),
                    if (_currentPage < _totalPages)
                      IconButton(
                        icon: const Icon(Icons.chevron_right),
                        onPressed: () {
                          setState(() => _currentPage++);
                          _loadRatings();
                        },
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
