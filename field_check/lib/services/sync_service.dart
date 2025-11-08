import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/offline_data_model.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:field_check/utils/http_util.dart';
import 'package:field_check/services/user_service.dart';

class SyncService {
  static const String _offlineDataKey = 'offlineData';

  // Save offline data to shared preferences
  Future<void> saveOfflineData(OfflineData data) async {
    final prefs = await SharedPreferences.getInstance();
    List<OfflineData> offlineRecords = await getOfflineData();
    offlineRecords.add(data);
    final String offlineDataString = json.encode(offlineRecords.map((d) => d.toJson()).toList());
    await prefs.setString(_offlineDataKey, offlineDataString);
  }

  // Get all offline data from shared preferences
  Future<List<OfflineData>> getOfflineData() async {
    final prefs = await SharedPreferences.getInstance();
    final String? offlineDataString = prefs.getString(_offlineDataKey);
    if (offlineDataString != null) {
      final List<dynamic> offlineDataList = json.decode(offlineDataString);
      return offlineDataList.map((json) => OfflineData.fromJson(json)).toList();
    }
    return [];
  }

  // Mark offline data as synced and remove from local storage
  Future<void> markAsSynced(String id) async {
    final prefs = await SharedPreferences.getInstance();
    List<OfflineData> offlineRecords = await getOfflineData();
    offlineRecords.removeWhere((data) => data.id == id);
    final String offlineDataString = json.encode(offlineRecords.map((d) => d.toJson()).toList());
    await prefs.setString(_offlineDataKey, offlineDataString);
  }

  // Synchronize offline data with the backend
  Future<void> syncOfflineData() async {
    final results = await Connectivity().checkConnectivity();
    final bool isDisconnected = results.contains(ConnectivityResult.none);
    if (isDisconnected) {
      print('No internet connection. Cannot sync offline data.');
      return;
    }

    List<OfflineData> offlineRecords = await getOfflineData();

    if (offlineRecords.isEmpty) {
      print('No offline data to sync.');
      return;
    }

    print('Attempting to sync ${offlineRecords.length} offline records...');

    final token = await UserService().getToken();
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };

    for (var data in offlineRecords) {
      try {
        final response = await HttpUtil().post(
          '/api/sync',
          headers: headers,
          body: data.toJson(),
        );

        if (response.statusCode == 200) {
          print('Successfully synced data: ${data.id}');
          await markAsSynced(data.id);
        } else {
          print('Failed to sync data ${data.id}: ${response.statusCode} - ${response.body}');
        }
      } catch (e) {
        print('Error syncing data ${data.id}: $e');
      }
    }
    print('Offline data synchronization attempt completed.');
  }
}