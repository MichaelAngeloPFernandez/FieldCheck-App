import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:field_check/services/ticket_service.dart';

/// Offline queue for ticket operations.
/// Queues ticket creation and status changes when offline, retries on reconnect.
class OfflineQueueService {
  static final OfflineQueueService _instance = OfflineQueueService._internal();
  factory OfflineQueueService() => _instance;
  OfflineQueueService._internal();

  static const String _queueKey = 'offline_queue';
  StreamSubscription? _connectivitySub;
  bool _processing = false;

  /// Initialize connectivity listener for automatic retry.
  void initialize() {
    _connectivitySub?.cancel();
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final result = results.isNotEmpty ? results.first : ConnectivityResult.none;
      if (result != ConnectivityResult.none) {
        processQueue();
      }
    });
  }

  /// Add a ticket creation to the offline queue.
  Future<void> enqueueTicketCreation({
    required String templateId,
    required Map<String, dynamic> data,
    String? assigneeId,
    Map<String, double>? gps,
    String? geofenceId,
    String? notes,
  }) async {
    final item = {
      'type': 'create_ticket',
      'payload': {
        'template_id': templateId,
        'data': data,
        if (assigneeId != null) 'assignee_id': assigneeId,
        if (gps != null) 'gps': gps,
        if (geofenceId != null) 'geofence_id': geofenceId,
        if (notes != null) 'notes': notes,
      },
      'queued_at': DateTime.now().toIso8601String(),
    };
    await _addToQueue(item);
  }

  /// Add a status change to the offline queue.
  Future<void> enqueueStatusChange({
    required String ticketId,
    required String status,
  }) async {
    final item = {
      'type': 'change_status',
      'payload': {
        'ticket_id': ticketId,
        'status': status,
      },
      'queued_at': DateTime.now().toIso8601String(),
    };
    await _addToQueue(item);
  }

  /// Process all queued items.
  Future<int> processQueue() async {
    if (_processing) return 0;
    _processing = true;

    try {
      final queue = await _getQueue();
      if (queue.isEmpty) return 0;

      int processed = 0;
      final failed = <Map<String, dynamic>>[];

      for (final item in queue) {
        try {
          final type = item['type'] as String?;
          final payload = item['payload'] as Map<String, dynamic>?;
          if (type == null || payload == null) continue;

          if (type == 'create_ticket') {
            await TicketService.createTicket(
              templateId: payload['template_id'] as String,
              data: payload['data'] as Map<String, dynamic>,
              assigneeId: payload['assignee_id'] as String?,
              gps: payload['gps'] != null
                  ? Map<String, double>.from(payload['gps'] as Map)
                  : null,
              geofenceId: payload['geofence_id'] as String?,
              notes: payload['notes'] as String?,
            );
            processed++;
          } else if (type == 'change_status') {
            await TicketService.changeStatus(
              payload['ticket_id'] as String,
              payload['status'] as String,
            );
            processed++;
          }
        } catch (e) {
          // Keep failed items for retry
          failed.add(item);
        }
      }

      // Save only failed items back to queue
      await _saveQueue(failed);
      return processed;
    } finally {
      _processing = false;
    }
  }

  /// Get number of pending items.
  Future<int> get pendingCount async {
    final queue = await _getQueue();
    return queue.length;
  }

  /// Get all queued items (for UI display).
  Future<List<Map<String, dynamic>>> getQueuedItems() async {
    return _getQueue();
  }

  /// Clear the queue.
  Future<void> clearQueue() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_queueKey);
  }

  Future<List<Map<String, dynamic>>> _getQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_queueKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final List decoded = jsonDecode(raw);
      return decoded.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<void> _addToQueue(Map<String, dynamic> item) async {
    final queue = await _getQueue();
    queue.add(item);
    await _saveQueue(queue);
  }

  Future<void> _saveQueue(List<Map<String, dynamic>> queue) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_queueKey, jsonEncode(queue));
  }

  void dispose() {
    _connectivitySub?.cancel();
  }
}
