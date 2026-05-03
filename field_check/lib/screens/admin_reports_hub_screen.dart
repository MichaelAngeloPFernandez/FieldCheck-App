import 'package:flutter/material.dart';
import 'package:field_check/screens/admin_reports_screen.dart';
import 'package:field_check/screens/enhanced_reports_screen.dart';

class AdminReportsHubScreen extends StatefulWidget {
  static final ValueNotifier<int> requestedInitialTab = ValueNotifier<int>(0);

  static void selectInitialTab(int index) {
    requestedInitialTab.value = index.clamp(0, 1);
  }

  final int initialTab;
  final bool embedded;

  const AdminReportsHubScreen({
    super.key,
    this.initialTab = 0,
    this.embedded = false,
  });

  @override
  State<AdminReportsHubScreen> createState() => _AdminReportsHubScreenState();
}

class _AdminReportsHubScreenState extends State<AdminReportsHubScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final VoidCallback _tabRequestListener;

  @override
  void initState() {
    super.initState();
    final fromWidget = widget.initialTab.clamp(0, 1);
    final initial = AdminReportsHubScreen.requestedInitialTab.value.clamp(0, 1);
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: initial != 0 ? initial : fromWidget,
    );

    _tabRequestListener = () {
      final idx = AdminReportsHubScreen.requestedInitialTab.value.clamp(0, 1);
      if (!mounted) return;
      if (_tabController.index == idx) return;
      _tabController.animateTo(idx);
    };
    AdminReportsHubScreen.requestedInitialTab.addListener(_tabRequestListener);
  }

  @override
  void dispose() {
    AdminReportsHubScreen.requestedInitialTab.removeListener(
      _tabRequestListener,
    );
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tabs = TabBar(
      controller: _tabController,
      labelColor: widget.embedded
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).colorScheme.onPrimary,
      unselectedLabelColor: widget.embedded
          ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.75)
          : Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.75),
      indicatorColor: widget.embedded
          ? Theme.of(context).colorScheme.primary
          : Colors.white,
      indicatorWeight: 3,
      tabs: const [
        Tab(icon: Icon(Icons.table_chart), text: 'Manage'),
        Tab(icon: Icon(Icons.insights), text: 'Analytics'),
      ],
    );

    final body = TabBarView(
      controller: _tabController,
      children: const [_AdminReportsEmbedded(), _EnhancedReportsEmbedded()],
    );

    if (!widget.embedded) {
      return Scaffold(
        appBar: AppBar(title: const Text('Reports'), bottom: tabs),
        body: body,
      );
    }

    return Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surface,
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: tabs,
          ),
        ),
        const Divider(height: 1),
        Expanded(child: body),
      ],
    );
  }
}

class _AdminReportsEmbedded extends StatelessWidget {
  const _AdminReportsEmbedded();

  @override
  Widget build(BuildContext context) {
    return const AdminReportsScreen(embedded: true);
  }
}

class _EnhancedReportsEmbedded extends StatelessWidget {
  const _EnhancedReportsEmbedded();

  @override
  Widget build(BuildContext context) {
    return const EnhancedReportsScreen();
  }
}
