import 'package:flutter/material.dart';
import 'package:field_check/services/reports_aggregator_service.dart';
import 'package:intl/intl.dart';

class EnhancedReportsScreen extends StatefulWidget {
  const EnhancedReportsScreen({super.key});

  @override
  State<EnhancedReportsScreen> createState() => _EnhancedReportsScreenState();
}

class _EnhancedReportsScreenState extends State<EnhancedReportsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ReportsAggregatorService _reportsService = ReportsAggregatorService();
  bool _isLoading = false;

  ReportSummary? _todayReport;
  WeeklySummary? _weeklyReport;
  MonthlySummary? _monthlyReport;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadReports();
  }

  Future<void> _loadReports() async {
    setState(() => _isLoading = true);

    try {
      final today = await _reportsService.getTodayReport();
      final weekly = await _reportsService.getWeeklyReport();
      final monthly = await _reportsService.getMonthlyReport();

      if (mounted) {
        setState(() {
          _todayReport = today;
          _weeklyReport = weekly;
          _monthlyReport = monthly;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading reports: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surface,
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    tabs: const [
                      Tab(text: "Today's Report", icon: Icon(Icons.calendar_today)),
                      Tab(text: 'Weekly Report', icon: Icon(Icons.calendar_view_week)),
                      Tab(text: 'Monthly Report', icon: Icon(Icons.calendar_view_month)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _loadReports,
                  tooltip: 'Refresh',
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildTodayReportTab(),
                    _buildWeeklyReportTab(),
                    _buildMonthlyReportTab(),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildTodayReportTab() {
    if (_todayReport == null) {
      return const Center(child: Text('No data available'));
    }

    return RefreshIndicator(
      onRefresh: _loadReports,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Report Icons Section
            _buildTodayReportIcons(),
            const SizedBox(height: 24),
            // Report Calendar
            _buildReportCalendar(),
          ],
        ),
      ),
    );
  }

  Widget _buildTodayReportIcons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildReportIcon(
          icon: Icons.task_alt,
          label: 'Task Report',
          count: _todayReport!.totalTasks,
          color: Colors.blue,
          onTap: () => _showTaskReportDialog(),
        ),
        _buildReportIcon(
          icon: Icons.login,
          label: 'Attendance Report',
          count: _todayReport!.checkIns,
          color: Colors.green,
          onTap: () => _showAttendanceReportDialog(),
        ),
      ],
    );
  }

  Widget _buildReportIcon({
    required IconData icon,
    required String label,
    required int count,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color, width: 2),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 32),
                const SizedBox(height: 4),
                Text(
                  count.toString(),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildReportCalendar() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Report Calendar',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildCalendarGrid(),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendarGrid() {
    final now = DateTime.now();
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final firstDay = DateTime(now.year, now.month, 1);
    final startingDayOfWeek = firstDay.weekday;

    return Column(
      children: [
        // Weekday headers
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: const [
            Text('Mon', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('Tue', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('Wed', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('Thu', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('Fri', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('Sat', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('Sun', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 8),
        // Calendar days
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            childAspectRatio: 1.2,
          ),
          itemCount: daysInMonth + (startingDayOfWeek - 1),
          itemBuilder: (context, index) {
            if (index < startingDayOfWeek - 1) {
              return const SizedBox();
            }

            final day = index - (startingDayOfWeek - 1) + 1;
            final date = DateTime(now.year, now.month, day);
            final isToday = day == now.day;

            return GestureDetector(
              onTap: () => _showDateReportDialog(date),
              child: Container(
                decoration: BoxDecoration(
                  color: isToday ? Colors.blue.withValues(alpha: 0.2) : null,
                  border: Border.all(
                    color: isToday ? Colors.blue : Colors.grey.shade300,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        day.toString(),
                        style: TextStyle(
                          fontWeight: isToday
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: isToday ? Colors.blue : Colors.black,
                        ),
                      ),
                      if (isToday)
                        Container(
                          width: 4,
                          height: 4,
                          decoration: const BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildWeeklyReportTab() {
    if (_weeklyReport == null) {
      return const Center(child: Text('No data available'));
    }

    return RefreshIndicator(
      onRefresh: _loadReports,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildWeeklyCarousel(),
            const SizedBox(height: 24),
            _buildWeeklyStats(),
            const SizedBox(height: 24),
            _buildReportCalendar(),
          ],
        ),
      ),
    );
  }

  Widget _buildWeeklyCarousel() {
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final weekStart = _weeklyReport!.weekStart;

    return SizedBox(
      height: 120,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: 7,
        itemBuilder: (context, index) {
          final date = weekStart.add(Duration(days: index));
          final dateStr = _weeklyReport!
              .dailyReports['${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}'];

          return GestureDetector(
            onTap: () => _showDateReportDialog(date),
            child: Container(
              width: 100,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue, width: 1.5),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    days[index],
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    date.day.toString(),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tasks: ${dateStr?.totalTasks ?? 0}',
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildWeeklyStats() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Weekly Summary',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildStatRow('Total Tasks', _weeklyReport!.totalTasks.toString()),
            _buildStatRow(
              'Completed Tasks',
              _weeklyReport!.completedTasks.toString(),
            ),
            _buildStatRow(
              'Total Check-Ins',
              _weeklyReport!.totalCheckIns.toString(),
            ),
            _buildStatRow(
              'Completion Rate',
              _weeklyReport!.totalTasks > 0
                  ? '${((_weeklyReport!.completedTasks / _weeklyReport!.totalTasks) * 100).toStringAsFixed(1)}%'
                  : '0%',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthlyReportTab() {
    if (_monthlyReport == null) {
      return const Center(child: Text('No data available'));
    }

    return RefreshIndicator(
      onRefresh: _loadReports,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildMonthlySummaryCards(),
            const SizedBox(height: 24),
            _buildMonthlyHeatmap(),
            const SizedBox(height: 24),
            _buildReportCalendar(),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthlySummaryCards() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.2,
      children: [
        _buildSummaryCard(
          'Completed Tasks',
          _monthlyReport!.completedTasks.toString(),
          Colors.green,
          Icons.check_circle,
        ),
        _buildSummaryCard(
          'Incomplete Tasks',
          _monthlyReport!.incompleteTasks.toString(),
          Colors.orange,
          Icons.pending_actions,
        ),
        _buildSummaryCard(
          'On-Time Check-Ins',
          _monthlyReport!.onTimeCheckIns.toString(),
          Colors.blue,
          Icons.login,
        ),
        _buildSummaryCard(
          'Late Check-Ins',
          _monthlyReport!.lateCheckIns.toString(),
          Colors.red,
          Icons.schedule,
        ),
      ],
    );
  }

  Widget _buildSummaryCard(
    String label,
    String value,
    Color color,
    IconData icon,
  ) {
    return Card(
      elevation: 2,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color, width: 1.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthlyHeatmap() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Activity Heatmap',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildCalendarGrid(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 14)),
          Text(
            value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  void _showTaskReportDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Task Report'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDialogStat(
              'Total Tasks',
              _todayReport!.totalTasks.toString(),
            ),
            _buildDialogStat(
              'Completed',
              _todayReport!.completedTasks.toString(),
            ),
            _buildDialogStat('Pending', _todayReport!.pendingTasks.toString()),
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

  void _showAttendanceReportDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Attendance Report'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDialogStat('Check-Ins', _todayReport!.checkIns.toString()),
            _buildDialogStat('Check-Outs', _todayReport!.checkOuts.toString()),
            _buildDialogStat(
              'Incomplete',
              _todayReport!.incompleteAttendance.toString(),
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

  void _showDateReportDialog(DateTime date) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Report for ${DateFormat('MMM dd, yyyy').format(date)}'),
        content: const Text('Detailed report for this date'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDialogStat(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
