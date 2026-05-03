import 'dart:convert';

import 'package:field_check/utils/http_util.dart';

class AvailabilityService {
  static const String _availabilityPath = '/api/availability';

  Future<List<Map<String, dynamic>>> getNearbyForTask(
    String taskId, {
    int maxDistanceMeters = 2000,
  }) async {
    final response = await HttpUtil().get(
      '$_availabilityPath/task/$taskId',
      queryParams: {'maxDistanceMeters': maxDistanceMeters.toString()},
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to load nearby employees: ${response.body}');
    }

    final Map<String, dynamic> data = json.decode(response.body);
    final List<dynamic> employees = data['employees'] as List<dynamic>? ?? [];
    return employees.cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> getOnlineAvailability() async {
    final response = await HttpUtil().get('$_availabilityPath/online');

    if (response.statusCode != 200) {
      throw Exception('Failed to load online availability: ${response.body}');
    }

    final Map<String, dynamic> data = json.decode(response.body);
    final List<dynamic> employees = data['employees'] as List<dynamic>? ?? [];
    return employees.cast<Map<String, dynamic>>();
  }
}
