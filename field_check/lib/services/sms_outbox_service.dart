import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'notification_service.dart';

enum SmsJobType { urgent, taskAssignment, overdueTask, attendance }

class SmsSendResult {
  final bool success;
  final bool queued;
  final Map<String, dynamic>? backendResponse;
  final String? error;

  SmsSendResult({
    required this.success,
    required this.queued,
    this.backendResponse,
    this.error,
  });
}

class SmsOutboxService {
  static const String _prefsKey = 'sms.outbox.jobs.v1';

  static final SmsOutboxService _instance = SmsOutboxService._internal();
  factory SmsOutboxService() => _instance;
  SmsOutboxService._internal();

  final NotificationService _notificationService = NotificationService();
  StreamSubscription<dynamic>? _connectivitySub;
  bool _retryInProgress = false;

  bool _isOffline(dynamic connectivity) {
    if (connectivity is ConnectivityResult) {
      return connectivity == ConnectivityResult.none;
    }
    if (connectivity is List<ConnectivityResult>) {
      return connectivity.contains(ConnectivityResult.none);
    }
    return false;
  }

  Future<void> init() async {
    _connectivitySub?.cancel();
    _connectivitySub = Connectivity().onConnectivityChanged.listen((_) {
      unawaited(retryPending());
    });
  }

  Future<void> dispose() async {
    await _connectivitySub?.cancel();
    _connectivitySub = null;
  }

  Future<List<Map<String, dynamic>>> _loadJobs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.trim().isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<void> _saveJobs(List<Map<String, dynamic>> jobs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(jobs));
  }

  Future<int> pendingCount() async => (await _loadJobs()).length;

  Future<void> clearAll() async {
    await _saveJobs([]);
  }

  Future<void> enqueue({
    required SmsJobType type,
    required Map<String, dynamic> payload,
    required String message,
    String? lastError,
  }) async {
    final jobs = await _loadJobs();
    jobs.add({
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'type': type.name,
      'createdAt': DateTime.now().toIso8601String(),
      'message': message,
      'payload': payload,
      'attemptCount': 0,
      'lastAttemptAt': null,
      'lastError': lastError,
    });
    await _saveJobs(jobs);
  }

  Future<void> openDeviceComposer({
    required String message,
    String? phoneNumber,
  }) async {
    if (kIsWeb) return;

    final encoded = Uri.encodeComponent(message);
    final uri = Uri.parse(
      phoneNumber == null || phoneNumber.trim().isEmpty
          ? 'sms:?body=$encoded'
          : 'sms:${phoneNumber.trim()}?body=$encoded',
    );

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<SmsSendResult> sendUrgentWithFallback(String message) async {
    try {
      final resp = await _notificationService
          .sendUrgentSmsToEmployeesWithResult(message);
      return SmsSendResult(success: true, queued: false, backendResponse: resp);
    } catch (e) {
      await enqueue(
        type: SmsJobType.urgent,
        payload: {'message': message},
        message: message,
        lastError: e.toString(),
      );
      await openDeviceComposer(message: message);
      return SmsSendResult(success: false, queued: true, error: e.toString());
    }
  }

  Future<void> retryPending() async {
    if (_retryInProgress) return;
    _retryInProgress = true;

    try {
      final connectivity = await Connectivity().checkConnectivity();
      if (_isOffline(connectivity)) return;

      var jobs = await _loadJobs();
      if (jobs.isEmpty) return;

      const maxAttempts = 5;

      final remaining = <Map<String, dynamic>>[];
      for (final job in jobs) {
        final attemptCount = (job['attemptCount'] as int?) ?? 0;
        if (attemptCount >= maxAttempts) {
          remaining.add(job);
          continue;
        }

        final type = (job['type'] ?? '').toString();
        final payload = (job['payload'] is Map)
            ? (job['payload'] as Map).cast<String, dynamic>()
            : <String, dynamic>{};

        try {
          if (type == SmsJobType.urgent.name) {
            await _notificationService.sendUrgentSmsToEmployees(
              (payload['message'] ?? job['message'] ?? '').toString(),
            );
          } else if (type == SmsJobType.taskAssignment.name) {
            await _notificationService.sendTaskAssignmentSms(
              employeeId: (payload['employeeId'] ?? '').toString(),
              taskTitle: (payload['taskTitle'] ?? '').toString(),
              taskDescription: (payload['taskDescription'] ?? '').toString(),
            );
          } else if (type == SmsJobType.overdueTask.name) {
            await _notificationService.sendOverdueTaskSms(
              employeeId: (payload['employeeId'] ?? '').toString(),
              taskTitle: (payload['taskTitle'] ?? '').toString(),
              hoursOverdue: (payload['hoursOverdue'] as int?) ?? 0,
            );
          } else if (type == SmsJobType.attendance.name) {
            await _notificationService.sendAttendanceSms(
              employeeId: (payload['employeeId'] ?? '').toString(),
              isCheckIn: (payload['isCheckIn'] as bool?) ?? true,
              geofenceName: (payload['geofenceName'] ?? '').toString(),
              timestamp: (payload['timestamp'] ?? '').toString(),
            );
          } else {
            throw Exception('Unknown job type: $type');
          }
        } catch (e) {
          final next = Map<String, dynamic>.from(job);
          next['attemptCount'] = attemptCount + 1;
          next['lastAttemptAt'] = DateTime.now().toIso8601String();
          next['lastError'] = e.toString();
          remaining.add(next);
        }
      }

      await _saveJobs(remaining);
    } finally {
      _retryInProgress = false;
    }
  }
}
