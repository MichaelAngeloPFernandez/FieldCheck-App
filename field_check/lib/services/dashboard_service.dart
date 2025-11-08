import 'dart:convert';
import 'package:field_check/utils/http_util.dart';
import 'package:field_check/services/user_service.dart';
import '../models/dashboard_model.dart';

class DashboardService {
  static const String _dashboardPath = '/api/dashboard';

  // Get dashboard statistics
  Future<DashboardStats> getDashboardStats() async {
    try {
      final token = await UserService().getToken();
      final headers = <String, String>{
        if (token != null) 'Authorization': 'Bearer $token',
      };
      final response = await HttpUtil().get('$_dashboardPath/stats', headers: headers);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return DashboardStats.fromJson(data);
      } else {
        throw Exception('Failed to load dashboard stats');
      }
    } catch (e) {
      print('Error fetching dashboard stats: $e');
      rethrow;
    }
  }

  // Get real-time updates
  Future<RealtimeUpdates> getRealtimeUpdates() async {
    try {
      final token = await UserService().getToken();
      final headers = <String, String>{
        if (token != null) 'Authorization': 'Bearer $token',
      };
      final response = await HttpUtil().get('$_dashboardPath/realtime', headers: headers);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return RealtimeUpdates.fromJson(data);
      } else {
        // Gracefully handle non-admin or backend unavailability
        return RealtimeUpdates(
          onlineUsers: 0,
          recentCheckIns: const [],
          pendingTasksToday: const [],
          timestamp: DateTime.now(),
        );
      }
    } catch (e) {
      // Avoid spamming logs — return empty updates
      return RealtimeUpdates(
        onlineUsers: 0,
        recentCheckIns: const [],
        pendingTasksToday: const [],
        timestamp: DateTime.now(),
      );
    }
  }
}
