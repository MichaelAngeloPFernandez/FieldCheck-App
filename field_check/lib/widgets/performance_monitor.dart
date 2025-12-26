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
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedMonitor(Map<String, PerformanceMetric> metrics) {
    return Container(
      width: 350,
      constraints: const BoxConstraints(maxHeight: 500),
      decoration: BoxDecoration(
        color: Colors.white,
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
                const Text(
                  'Performance Monitor',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
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
              border: Border(top: BorderSide(color: Colors.grey[300]!)),
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
              color: isSelected ? Colors.blue : Colors.grey,
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
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStatRow('Total Items', '${stats['totalItems']}'),
        _buildStatRow('Total Size', '${stats['totalSize']} bytes'),
        const SizedBox(height: 12),
        if (items.isNotEmpty) ...[
          const Text(
            'Cached Items:',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
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
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  _buildStatRow('Size', '${item['size']} bytes', fontSize: 10),
                  _buildStatRow('Age', '${item['age']}s', fontSize: 10),
                  _buildStatRow('TTL', '${item['ttl']}s', fontSize: 10),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Memory monitoring requires platform-specific implementation.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text(
            'To enable memory monitoring, implement platform channels for iOS and Android.',
            style: TextStyle(fontSize: 11),
          ),
        ),
      ],
    );
  }

  Widget _buildMetricRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          Text(
            value,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value, {double fontSize = 11}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: fontSize, color: Colors.grey),
          ),
          Text(
            value,
            style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
