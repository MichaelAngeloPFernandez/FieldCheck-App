import 'package:flutter/material.dart';
import 'package:field_check/services/realtime_service.dart';
import 'package:field_check/widgets/app_page.dart';
import 'package:intl/intl.dart';

/// Notification Center Screen
/// Displays notifications categorized by type with filtering and actions
class NotificationCenterScreen extends StatefulWidget {
  final Function(int)? onTabRequested;

  const NotificationCenterScreen({
    super.key,
    this.onTabRequested,
  });

  @override
  State<NotificationCenterScreen> createState() =>
      _NotificationCenterScreenState();
}

class DashboardNotification {
  final String id;
  final String title;
  final String message;
  final String category; // tasks, alerts, messages, announcements, geofences
  final DateTime timestamp;
  final Map<String, dynamic>? payload;
  bool isRead;

  DashboardNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.category,
    required this.timestamp,
    this.payload,
    this.isRead = false,
  });
}

class _NotificationCenterScreenState extends State<NotificationCenterScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final RealtimeService _realtimeService = RealtimeService();
  
  // Notification lists by category
  final Map<String, List<DashboardNotification>> _notificationsByCategory = {
    'all': [],
    'tasks': [],
    'alerts': [],
    'messages': [],
    'announcements': [],
    'geofences': [],
  };

  static const List<String> _categories = [
    'all',
    'tasks',
    'alerts',
    'messages',
    'announcements',
    'geofences',
  ];

  static const Map<String, IconData> _categoryIcons = {
    'all': Icons.notifications,
    'tasks': Icons.task_alt,
    'alerts': Icons.warning_rounded,
    'messages': Icons.mail,
    'announcements': Icons.campaign,
    'geofences': Icons.location_on,
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _categories.length, vsync: this);
    _setupNotificationListener();
  }

  void _setupNotificationListener() {
    try {
      _realtimeService.notificationStream.listen(
        (notification) {
          if (!mounted) return;
          _handleNewNotification(notification);
        },
        onError: (error) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Notification error: $error')),
            );
          }
        },
      );
    } catch (e) {
      debugPrint('Error setting up notification listener: $e');
    }
  }

  void _handleNewNotification(dynamic notification) {
    if (notification is! Map<String, dynamic>) return;

    try {
      final notif = DashboardNotification(
        id: notification['id'] ?? 'unknown',
        title: notification['title'] ?? 'Notification',
        message: notification['message'] ?? '',
        category: _normalizeCategory(notification['scope'] ?? 'alerts'),
        timestamp: notification['createdAt'] != null
            ? DateTime.parse(notification['createdAt'])
            : DateTime.now(),
        payload: notification['payload'],
        isRead: notification['readAt'] != null,
      );

      setState(() {
        // Add to category
        _notificationsByCategory[notif.category]?.insert(0, notif);
        // Add to all
        _notificationsByCategory['all']?.insert(0, notif);
      });
    } catch (e) {
      debugPrint('Error handling notification: $e');
    }
  }

  String _normalizeCategory(String scope) {
    switch (scope.toLowerCase()) {
      case 'tasks':
        return 'tasks';
      case 'adminFeed':
        return 'alerts';
      case 'messages':
        return 'messages';
      case 'announcements':
        return 'announcements';
      case 'geofences':
        return 'geofences';
      default:
        return 'alerts';
    }
  }

  Future<void> _markAsRead(DashboardNotification notification) async {
    if (notification.isRead) return;

    setState(() {
      notification.isRead = true;
    });

    // Notification state is local-only; no backend call needed.
    try {
      debugPrint('Marked notification ${notification.id} as read');
    } catch (e) {
      debugPrint('Error marking notification as read: $e');
      // Revert on error
      setState(() {
        notification.isRead = false;
      });
    }
  }

  Future<void> _deleteNotification(DashboardNotification notification) async {
    setState(() {
      _notificationsByCategory[notification.category]?.remove(notification);
      _notificationsByCategory['all']?.remove(notification);
    });

    try {
      debugPrint('Deleted notification ${notification.id}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notification deleted')),
        );
      }
    } catch (e) {
      debugPrint('Error deleting notification: $e');
      // Revert on error
      if (mounted) {
        setState(() {
          _notificationsByCategory[notification.category]?.add(notification);
          _notificationsByCategory['all']?.add(notification);
        });
      }
    }
  }

  Future<void> _markAllAsRead(String category) async {
    final notifications = _notificationsByCategory[category] ?? [];
    final unreadCount =
        notifications.where((n) => !n.isRead).length;

    if (unreadCount == 0) return;

    setState(() {
      for (final notif in notifications) {
        notif.isRead = true;
      }
    });

    try {
      if (category == 'all') {
        // Mark all as read — local state only
        debugPrint('Marked all notifications as read');
      } else {
        // Mark category as read
        for (final notif in notifications.where((n) => !n.isRead)) {
          notif.isRead = true;
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Marked $unreadCount notification${unreadCount > 1 ? 's' : ''} as read'),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error marking all as read: $e');
      // Revert on error
      if (mounted) {
        setState(() {
          for (final notif in notifications) {
            notif.isRead = false;
          }
        });
      }
    }
  }

  Widget _buildNotificationItem(
    DashboardNotification notification,
    ThemeData theme,
  ) {
    final isUnread = !notification.isRead;
    final category = notification.category;

    return Card(
      elevation: isUnread ? 2 : 0,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isUnread
              ? theme.colorScheme.primary.withValues(alpha: 0.3)
              : Colors.transparent,
        ),
      ),
      child: Container(
        color: isUnread
            ? theme.colorScheme.primary.withValues(alpha: 0.05)
            : Colors.transparent,
        child: Dismissible(
          key: Key(notification.id),
          onDismissed: (_) => _deleteNotification(notification),
          background: Container(
            color: Colors.red.withValues(alpha: 0.7),
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 16),
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _getCategoryColor(category).withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _categoryIcons[category] ?? Icons.notifications,
                color: _getCategoryColor(category),
                size: 20,
              ),
            ),
            title: Text(
              notification.title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: isUnread ? FontWeight.bold : FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 4),
                Text(
                  notification.message,
                  style: theme.textTheme.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  _formatTime(notification.timestamp),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
            trailing: isUnread
                ? Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ),
                  )
                : null,
            onTap: () => _markAsRead(notification),
          ),
        ),
      ),
    );
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'tasks':
        return Colors.orange;
      case 'alerts':
        return Colors.red;
      case 'messages':
        return Colors.blue;
      case 'announcements':
        return Colors.purple;
      case 'geofences':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inSeconds < 60) {
      return 'Just now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      return DateFormat('MMM d').format(time);
    }
  }

  Widget _buildTabContent(String category) {
    final notifications = _notificationsByCategory[category] ?? [];
    final unreadCount = notifications.where((n) => !n.isRead).length;

    if (notifications.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _categoryIcons[category] ?? Icons.notifications,
              size: 48,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No ${category == 'all' ? '' : '$category '}notifications',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.5),
                  ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        if (unreadCount > 0)
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _markAllAsRead(category),
                icon: const Icon(Icons.done_all),
                label: Text('Mark all as read ($unreadCount)'),
              ),
            ),
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: notifications.length,
            itemBuilder: (context, index) {
              return _buildNotificationItem(
                notifications[index],
                Theme.of(context),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppPage(
      useScaffold: false,
      useSafeArea: true,
      scroll: false,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                bottom: BorderSide(
                  color: theme.colorScheme.outlineVariant,
                ),
              ),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Notifications',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  tabs: _categories.map((category) {
                    final count = _notificationsByCategory[category]?.length ?? 0;
                    return Tab(
                      child: Row(
                        children: [
                          Icon(_categoryIcons[category]),
                          const SizedBox(width: 8),
                          Text(
                            category[0].toUpperCase() + category.substring(1),
                          ),
                          if (count > 0)
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      _getCategoryColor(category),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  count.toString(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: _categories
                  .map((category) => _buildTabContent(category))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}
