import 'package:flutter/material.dart';
import '../services/performance_service.dart';

class PerformanceMonitor extends StatefulWidget {
  final PerformanceService performanceService;

  const PerformanceMonitor({super.key, required this.performanceService});

  @override
  State<PerformanceMonitor> createState() => _PerformanceMonitorState();
}

class _PerformanceMonitorState extends State<PerformanceMonitor> {
  bool _isExpanded = false;
  String _selectedTab = 'metrics'; // metrics, cache, memory

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, PerformanceMetric>>(
      stream: widget.performanceService.metricsStream,
      builder: (context, snapshot) {
        final metrics = snapshot.data ?? {};

        return Positioned(
          bottom: 16,
          right: 16,
          child: _isExpanded
              ? _buildExpandedMonitor(metrics)
              : _buildCollapsedMonitor(metrics),
        );
      },
    );
  }

  Widget _buildCollapsedMonitor(Map<String, PerformanceMetric> metrics) {
    final avgDuration = metrics.isEmpty
        ? 0
        : metrics.values.fold<int>(
                0,
                (sum, m) => sum + m.averageDuration.inMilliseconds,
              ) ~/
              metrics.length;
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: () => setState(() => _isExpanded = true),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.blue,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.blue.withValues(alpha: 0.5),
              blurRadius: 8,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.speed, color: Colors.white, size: 20),
            const SizedBox(height: 4),
            Text(
              '${avgDuration}ms',
              style: theme.textTheme.labelMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedMonitor(Map<String, PerformanceMetric> metrics) {
    final theme = Theme.of(context);
    return Container(
      width: 350,
      constraints: const BoxConstraints(maxHeight: 500),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 12,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Performance Monitor',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _isExpanded = false),
                  child: const Icon(Icons.close, color: Colors.white, size: 20),
                ),
              ],
            ),
          ),
          // Tabs
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                _buildTab('Metrics', 'metrics'),
                _buildTab('Cache', 'cache'),
                _buildTab('Memory', 'memory'),
              ],
            ),
          ),
          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: _buildTabContent(metrics),
            ),
          ),
          // Footer
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: theme.dividerColor.withValues(alpha: 0.6),
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton.icon(
                  onPressed: () {
                    widget.performanceService.clearMetrics();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Metrics cleared')),
                    );
                  },
                  icon: const Icon(Icons.delete, size: 16),
                  label: const Text('Clear Metrics'),
                ),
                TextButton.icon(
                  onPressed: () {
                    widget.performanceService.clearCache();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Cache cleared')),
                    );
                  },
                  icon: const Icon(Icons.delete, size: 16),
                  label: const Text('Clear Cache'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTab(String label, String value) {
    final isSelected = _selectedTab == value;
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTab = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isSelected ? Colors.blue : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected
                  ? Colors.blue
                  : onSurface.withValues(alpha: 0.68),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabContent(Map<String, PerformanceMetric> metrics) {
    switch (_selectedTab) {
      case 'metrics':
        return _buildMetricsTab(metrics);
      case 'cache':
        return _buildCacheTab();
      case 'memory':
        return _buildMemoryTab();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildMetricsTab(Map<String, PerformanceMetric> metrics) {
    if (metrics.isEmpty) {
      return const Center(child: Text('No metrics recorded yet'));
    }

    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: metrics.entries.map((entry) {
        final metric = entry.value;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                metric.name,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              _buildMetricRow('Calls', '${metric.callCount}'),
              _buildMetricRow(
                'Avg Duration',
                '${metric.averageDuration.inMilliseconds}ms',
              ),
              _buildMetricRow(
                'Max Duration',
                '${metric.maxDuration.inMilliseconds}ms',
              ),
              _buildMetricRow(
                'Success Rate',
                '${metric.successRate.toStringAsFixed(1)}%',
              ),
              const Divider(),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCacheTab() {
    final stats = widget.performanceService.getCacheStats();
    final items = stats['items'] as List? ?? [];
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStatRow('Total Items', '${stats['totalItems']}'),
        _buildStatRow('Total Size', '${stats['totalSize']} bytes'),
        const SizedBox(height: 12),
        if (items.isNotEmpty) ...[
          Text(
            'Cached Items:',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item['key'],
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  _buildStatRow('Size', '${item['size']} bytes'),
                  _buildStatRow('Age', '${item['age']}s'),
                  _buildStatRow('TTL', '${item['ttl']}s'),
                ],
              ),
            ),
          ),
        ] else
          const Center(child: Text('Cache is empty')),
      ],
    );
  }

  Widget _buildMemoryTab() {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Memory monitoring requires platform-specific implementation.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: onSurface.withValues(alpha: 0.75),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            'To enable memory monitoring, implement platform channels for iOS and Android.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: onSurface.withValues(alpha: 0.82),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMetricRow(String label, String value) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: onSurface.withValues(alpha: 0.7),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: onSurface.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value, {double fontSize = 11}) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final effectiveSize = fontSize < 12 ? 12.0 : fontSize;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: effectiveSize,
              color: onSurface.withValues(alpha: 0.7),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: effectiveSize,
              fontWeight: FontWeight.w700,
              color: onSurface.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}
