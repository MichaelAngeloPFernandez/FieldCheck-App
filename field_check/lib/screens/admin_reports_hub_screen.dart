import 'package:flutter/material.dart';
import 'package:field_check/screens/admin_reports_screen.dart';
import 'package:field_check/screens/enhanced_reports_screen.dart';

class AdminReportsHubScreen extends StatefulWidget {
  const AdminReportsHubScreen({super.key});

  @override
  State<AdminReportsHubScreen> createState() => _AdminReportsHubScreenState();
}

class _AdminReportsHubScreenState extends State<AdminReportsHubScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          tabs: const [
            Tab(icon: Icon(Icons.table_chart), text: 'Manage'),
            Tab(icon: Icon(Icons.insights), text: 'Analytics'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _AdminReportsEmbedded(),
          _EnhancedReportsEmbedded(),
        ],
      ),
    );
  }
}

class _AdminReportsEmbedded extends StatelessWidget {
  const _AdminReportsEmbedded();

  @override
  Widget build(BuildContext context) {
    return const AdminReportsScreen();
  }
}

class _EnhancedReportsEmbedded extends StatelessWidget {
  const _EnhancedReportsEmbedded();

  @override
  Widget build(BuildContext context) {
    return const EnhancedReportsScreen();
  }
}
