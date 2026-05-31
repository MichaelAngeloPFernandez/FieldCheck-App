import 'package:flutter/material.dart';
import 'package:field_check/widgets/app_widgets.dart';
import 'package:field_check/utils/app_theme.dart';
import 'package:field_check/services/client_ticket_service.dart';

class ClientGradesScreen extends StatefulWidget {
  final String? clientEmail;

  const ClientGradesScreen({super.key, this.clientEmail});

  @override
  State<ClientGradesScreen> createState() => _ClientGradesScreenState();
}

class _ClientGradesScreenState extends State<ClientGradesScreen> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<Map<String, dynamic>> _grades = [];
  bool _isLoading = true;
  String? _error;
  String? _clientEmail;

  // Summary stats
  int _totalGrades = 0;
  double _averageRating = 0.0;
  int _fiveStarCount = 0;
  int _fourStarCount = 0;
  int _threeStarCount = 0;
  int _twoStarCount = 0;
  int _oneStarCount = 0;

  // Filters
  int? _starFilter; // null = all, 1-5 for specific rating
  String _sortBy = 'recent'; // 'recent', 'rating_high', 'rating_low'

  int _currentPage = 1;
  int _totalPages = 1;
  static const int _gradesPerPage = 10;

  @override
  void initState() {
    super.initState();
    _clientEmail = widget.clientEmail;
    if (_clientEmail != null && _clientEmail!.isNotEmpty) {
      _loadGrades();
    }
  }

  Future<void> _loadGrades() async {
    if (_clientEmail == null || _clientEmail!.isEmpty) {
      setState(() {
        _error = 'Please provide a client email';
        _isLoading = false;
      });
      return;
    }

    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final response = await ClientTicketService().getClientRatings(
        clientEmail: _clientEmail!,
        page: _currentPage,
        limit: _gradesPerPage,
        stars: _starFilter,
        sortBy: _sortBy,
      );

      if (!mounted) return;

      if (response['success'] == true) {
        final ratings = response['ratings'] as List? ?? [];
        setState(() {
          _grades = List<Map<String, dynamic>>.from(ratings);
          _totalGrades = response['total'] ?? 0;
          _totalPages = response['pages'] ?? 1;
          _averageRating = (response['averageRating'] as num?)?.toDouble() ?? 0.0;
          _fiveStarCount = response['fiveStarCount'] ?? 0;
          _fourStarCount = response['fourStarCount'] ?? 0;
          _threeStarCount = response['threeStarCount'] ?? 0;
          _twoStarCount = response['twoStarCount'] ?? 0;
          _oneStarCount = response['oneStarCount'] ?? 0;
          _isLoading = false;
          _error = null;
        });
      } else {
        throw Exception(response['error'] ?? 'Failed to load grades');
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

  void _updateEmail() {
    setState(() {
      _clientEmail = _emailController.text.trim();
      _currentPage = 1;
    });
    _loadGrades();
  }

  String _formatStars(int stars) {
    return '$stars ${stars == 1 ? 'star' : 'stars'}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Grades'),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Email input & filters
          Padding(
            padding: const EdgeInsets.all(AppTheme.md),
            child: Column(
              spacing: AppTheme.sm,
              children: [
                // Email field (only if not provided)
                if (widget.clientEmail == null)
                  TextField(
                    controller: _emailController,
                    decoration: InputDecoration(
                      labelText: 'Your Email',
                      hintText: 'Enter your email to view grades',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.search),
                        onPressed: _updateEmail,
                      ),
                    ),
                    onSubmitted: (_) => _updateEmail(),
                  ),

                // Summary stats (only show if grades exist)
                if (_totalGrades > 0)
                  Container(
                    padding: const EdgeInsets.all(AppTheme.md),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.grey.shade900
                          : Colors.blue.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark
                            ? Colors.grey.shade700
                            : Colors.blue.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Column(
                      spacing: AppTheme.sm,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                spacing: AppTheme.xs,
                                children: [
                                  Text(
                                    'Average Rating',
                                    style: theme.textTheme.labelSmall,
                                  ),
                                  Row(
                                    spacing: AppTheme.xs,
                                    children: [
                                      Text(
                                        _averageRating.toStringAsFixed(1),
                                        style: theme.textTheme.headlineSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                              color: Colors.amber,
                                            ),
                                      ),
                                      const Icon(Icons.star,
                                          color: Colors.amber, size: 20),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                spacing: AppTheme.xs,
                                children: [
                                  Text(
                                    'Total Grades',
                                    style: theme.textTheme.labelSmall,
                                  ),
                                  Text(
                                    _totalGrades.toString(),
                                    style:
                                        theme.textTheme.headlineSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        // Star distribution
                        Column(
                          spacing: AppTheme.xs,
                          children: [
                            _buildStarRow(5, _fiveStarCount),
                            _buildStarRow(4, _fourStarCount),
                            _buildStarRow(3, _threeStarCount),
                            _buildStarRow(2, _twoStarCount),
                            _buildStarRow(1, _oneStarCount),
                          ],
                        ),
                      ],
                    ),
                  ),

                // Filters
                Row(
                  spacing: AppTheme.sm,
                  children: [
                    // Star filter
                    Expanded(
                      child: DropdownButton<int?>(
                        isExpanded: true,
                        value: _starFilter,
                        hint: const Text('All Ratings'),
                        underline: Container(
                          height: 1,
                          color: Colors.grey.withValues(alpha: 0.3),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: null,
                            child: Text('All Ratings'),
                          ),
                          DropdownMenuItem(value: 5, child: Text('⭐⭐⭐⭐⭐')),
                          DropdownMenuItem(value: 4, child: Text('⭐⭐⭐⭐')),
                          DropdownMenuItem(value: 3, child: Text('⭐⭐⭐')),
                          DropdownMenuItem(value: 2, child: Text('⭐⭐')),
                          DropdownMenuItem(value: 1, child: Text('⭐')),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _starFilter = value;
                            _currentPage = 1;
                          });
                          _loadGrades();
                        },
                      ),
                    ),
                    const SizedBox(width: AppTheme.sm),
                    // Sort dropdown
                    Expanded(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: _sortBy,
                        hint: const Text('Sort'),
                        underline: Container(
                          height: 1,
                          color: Colors.grey.withValues(alpha: 0.3),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'recent',
                            child: Text('Most Recent'),
                          ),
                          DropdownMenuItem(
                            value: 'rating_high',
                            child: Text('Highest Rating'),
                          ),
                          DropdownMenuItem(
                            value: 'rating_low',
                            child: Text('Lowest Rating'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() {
                            _sortBy = value;
                            _currentPage = 1;
                          });
                          _loadGrades();
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Grades list
          Expanded(
            child: _isLoading
                ? AppWidgets.loadingIndicator(message: 'Loading grades...')
                : _error != null
                    ? AppWidgets.emptyState(
                        title: 'Error',
                        message: _error!,
                        icon: Icons.error_outline,
                      )
                    : _grades.isEmpty
                        ? AppWidgets.emptyState(
                            title: 'No Grades Yet',
                            message: 'You haven\'t submitted any grades for your tickets',
                            icon: Icons.assignment_turned_in_outlined,
                          )
                        : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppTheme.md,
                            ),
                            itemCount: _grades.length,
                            itemBuilder: (context, index) {
                              final grade = _grades[index];
                              return _buildGradeCard(theme, grade);
                            },
                          ),
          ),

          // Pagination
          if (_totalPages > 1 && _grades.isNotEmpty)
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
                        _loadGrades();
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
                        _loadGrades();
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

  Widget _buildStarRow(int stars, int count) {
    final percentage =
        _totalGrades > 0 ? (count / _totalGrades * 100).toStringAsFixed(0) : '0';
    return Row(
      children: [
        SizedBox(
          width: 50,
          child: Text(
            _formatStars(stars),
            style: const TextStyle(fontSize: 12),
          ),
        ),
        Expanded(
          child: LinearProgressIndicator(
            value: _totalGrades > 0 ? count / _totalGrades : 0,
            minHeight: 6,
          ),
        ),
        const SizedBox(width: AppTheme.xs),
        SizedBox(
          width: 30,
          child: Text(
            '$percentage%',
            style: const TextStyle(fontSize: 12),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildGradeCard(ThemeData theme, Map<String, dynamic> grade) {
    final ticketNumber = grade['ticketNumber'] as String? ?? 'N/A';
    final ticketDescription = grade['ticketDescription'] as String? ?? '';
    final stars = grade['stars'] as int? ?? 0;
    final comment = grade['comment'] as String? ?? '';
    final submittedAt = grade['submittedAt'] as String?;
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = isDark ? Colors.grey.shade900 : Colors.grey.shade100;

    return Card(
      margin: const EdgeInsets.only(bottom: AppTheme.md),
      color: cardBg,
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: AppTheme.sm,
          children: [
            // Header with ticket number and rating
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                      if (ticketDescription.isNotEmpty)
                        Text(
                          ticketDescription,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                // Star rating
                Column(
                  spacing: AppTheme.xs,
                  children: [
                    Row(
                      spacing: 2,
                      children: List.generate(
                        5,
                        (i) => Icon(
                          i < stars ? Icons.star : Icons.star_border,
                          color: Colors.amber,
                          size: 20,
                        ),
                      ),
                    ),
                    Text(
                      _formatStars(stars),
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
              ],
            ),

            // Comment
            if (comment.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppTheme.sm),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.grey.shade800
                      : Colors.white.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.grey.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: AppTheme.xs,
                  children: [
                    Text(
                      'Your Review',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      comment,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),

            // Date
            if (submittedAt != null)
              Align(
                alignment: Alignment.bottomRight,
                child: Text(
                  _formatDate(submittedAt),
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: Colors.grey),
                ),
              ),
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
    _emailController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}
