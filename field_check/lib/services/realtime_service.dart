// ignore_for_file: avoid_print, library_prefixes
import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:field_check/config/api_config.dart';
import 'package:field_check/services/user_service.dart';

class RealtimeService {
  static final RealtimeService _instance = RealtimeService._internal();
  factory RealtimeService() => _instance;
  RealtimeService._internal();

  io.Socket? _socket;
  String? _lastAuthToken;
  final StreamController<Map<String, dynamic>> _eventController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<int> _onlineCountController =
      StreamController<int>.broadcast();
  final StreamController<Map<String, dynamic>> _attendanceController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _taskController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _userController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _locationController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _notificationController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _chatController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _unreadCountsController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _adminNearbyController =
      StreamController<Map<String, dynamic>>.broadcast();

  bool _isConnected = false;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int maxReconnectAttempts = 5;
  final Set<String> _rooms = <String>{};

  Stream<Map<String, dynamic>> get eventStream => _eventController.stream;
  Stream<int> get onlineCountStream => _onlineCountController.stream;
  Stream<Map<String, dynamic>> get attendanceStream =>
      _attendanceController.stream;
  Stream<Map<String, dynamic>> get taskStream => _taskController.stream;
  Stream<Map<String, dynamic>> get userStream => _userController.stream;
  Stream<Map<String, dynamic>> get locationStream => _locationController.stream;
  Stream<Map<String, dynamic>> get notificationStream =>
      _notificationController.stream;
  Stream<Map<String, dynamic>> get chatStream => _chatController.stream;
  Stream<Map<String, dynamic>> get unreadCountsStream =>
      _unreadCountsController.stream;
  Stream<Map<String, dynamic>> get adminNearbyStream =>
      _adminNearbyController.stream;

  bool get isConnected => _isConnected;

  Future<void> initialize() async {
    final token = await UserService().getToken();

    // Important: RealtimeService is a singleton. If the user logs out and logs in
    // as a different account without a full restart, we must rebuild the socket
    // with the new token so the backend joins the correct `user:<id>` room.
    final tokenChanged = (token ?? '') != (_lastAuthToken ?? '');

    if (_socket != null && _isConnected && !tokenChanged) return;

    try {
      try {
        if (_socket != null) {
          _socket!.disconnect();
          _socket!.dispose();
        }
      } catch (_) {}
      _socket = null;
      _isConnected = false;

      _lastAuthToken = token;
      final options = io.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          .setExtraHeaders({
            if (token != null) 'Authorization': 'Bearer $token',
          })
          .setTimeout(60000)
          .build();

      if (token != null) {
        options['auth'] = {'token': token};
      }

      options['reconnection'] = true;
      options['reconnectionAttempts'] = 999999;
      options['reconnectionDelay'] = 500;
      options['reconnectionDelayMax'] = 5000;
      options['randomizationFactor'] = 0.5;

      // Critical for Flutter Web: ensure we do not reuse a cached Socket.IO
      // manager that may still carry the previous user's auth token.
      options['forceNew'] = true;
      options['force new connection'] = true;

      _socket = io.io(ApiConfig.baseUrl, options);

      _socket!.onConnect((_) {
        print('RealtimeService: Connected to Socket.IO');
        _isConnected = true;
        _reconnectAttempts = 0;
        _reconnectTimer?.cancel();

        // Re-join any rooms after reconnect.
        for (final room in _rooms) {
          try {
            _socket!.emit('joinRoom', {'room': room});
          } catch (_) {}
        }
      });

      _socket!.onDisconnect((_) {
        print('RealtimeService: Disconnected from Socket.IO');
        _isConnected = false;
        // Socket.IO client will auto-reconnect; keep a lightweight fallback.
        _scheduleReconnect();
      });

      _socket!.onConnectError((err) {
        print('RealtimeService: Connect Error: $err');
        _isConnected = false;
      });

      _socket!.onError((err) {
        print('RealtimeService: Error: $err');
      });

      // Listen for real-time events
      _setupEventListeners();
    } catch (e) {
      print('RealtimeService: Failed to initialize: $e');
    }
  }

  void _setupEventListeners() {
    if (_socket == null) return;

    // Online presence
    _socket!.on('onlineCount', (data) {
      try {
        final count = data is int ? data : int.tryParse('$data') ?? 0;
        _onlineCountController.add(count);
      } catch (e) {
        print('Error processing onlineCount: $e');
      }
    });

    _socket!.on('seedOnlineSnapshot', (data) {
      print('RealtimeService: Seed online snapshot: $data');
      try {
        if (data is Map<String, dynamic>) {
          _eventController.add({
            'type': 'presence',
            'action': 'seedOnlineSnapshot',
            'data': data,
          });
        } else if (data is Map) {
          _eventController.add({
            'type': 'presence',
            'action': 'seedOnlineSnapshot',
            'data': Map<String, dynamic>.from(data),
          });
        }
      } catch (e) {
        print('RealtimeService: Error processing seedOnlineSnapshot: $e');
      }
    });

    // Attendance events
    _socket!.on('newAttendanceRecord', (data) {
      print('RealtimeService: New attendance record: $data');
      _attendanceController.add({'type': 'new', 'data': data});
      _eventController.add({
        'type': 'attendance',
        'action': 'new',
        'data': data,
      });
    });

    _socket!.on('updatedAttendanceRecord', (data) {
      print('RealtimeService: Updated attendance record: $data');
      _attendanceController.add({'type': 'updated', 'data': data});
      _eventController.add({
        'type': 'attendance',
        'action': 'updated',
        'data': data,
      });
    });

    // Task events
    _socket!.on('newTask', (data) {
      print('RealtimeService: New task: $data');
      _taskController.add({'type': 'new', 'data': data});
      _eventController.add({'type': 'task', 'action': 'new', 'data': data});
    });

    _socket!.on('updatedTask', (data) {
      print('RealtimeService: Updated task: $data');
      _taskController.add({'type': 'updated', 'data': data});
      _eventController.add({'type': 'task', 'action': 'updated', 'data': data});
    });

    _socket!.on('deletedTask', (data) {
      print('RealtimeService: Deleted task: $data');
      _taskController.add({'type': 'deleted', 'data': data});
      _eventController.add({'type': 'task', 'action': 'deleted', 'data': data});
    });

    _socket!.on('updatedUserTaskStatus', (data) {
      print('RealtimeService: Updated user task status: $data');
      _taskController.add({'type': 'status_updated', 'data': data});
      _eventController.add({
        'type': 'task',
        'action': 'status_updated',
        'data': data,
      });
    });

    _socket!.on('taskAssignedToMultiple', (data) {
      print('RealtimeService: Task assigned to multiple: $data');
      _taskController.add({'type': 'assigned_multiple', 'data': data});
      _eventController.add({
        'type': 'task',
        'action': 'assigned_multiple',
        'data': data,
      });
    });

    _socket!.on('taskUnassigned', (data) {
      print('RealtimeService: Task unassigned: $data');
      _taskController.add({'type': 'unassigned', 'data': data});
      _eventController.add({
        'type': 'task',
        'action': 'unassigned',
        'data': data,
      });
    });

    _socket!.on('userTaskArchived', (data) {
      print('RealtimeService: User task archived: $data');
      _taskController.add({'type': 'user_task_archived', 'data': data});
      _eventController.add({
        'type': 'task',
        'action': 'user_task_archived',
        'data': data,
      });
    });

    _socket!.on('userTaskRestored', (data) {
      print('RealtimeService: User task restored: $data');
      _taskController.add({'type': 'user_task_restored', 'data': data});
      _eventController.add({
        'type': 'task',
        'action': 'user_task_restored',
        'data': data,
      });
    });

    // Live employee locations (for admin world map / tracking)
    _socket!.on('liveEmployeeLocation', (data) {
      print('RealtimeService: Live employee location: $data');
      try {
        if (data is Map<String, dynamic>) {
          _locationController.add(data);
          _eventController.add({
            'type': 'location',
            'action': 'live',
            'data': data,
          });
        }
      } catch (e) {
        print('Error processing liveEmployeeLocation: $e');
      }
    });

    // Report events
    _socket!.on('newReport', (data) {
      print('RealtimeService: New report: $data');
      _eventController.add({'type': 'report', 'action': 'new', 'data': data});
    });

    _socket!.on('updatedReport', (data) {
      print('RealtimeService: Updated report: $data');
      _eventController.add({
        'type': 'report',
        'action': 'updated',
        'data': data,
      });
    });

    _socket!.on('deletedReport', (data) {
      print('RealtimeService: Deleted report: $data');
      _eventController.add({
        'type': 'report',
        'action': 'deleted',
        'data': data,
      });
    });

    _socket!.on('reportArchived', (data) {
      print('RealtimeService: Report archived: $data');
      _eventController.add({
        'type': 'report',
        'action': 'archived',
        'data': data,
      });
    });

    _socket!.on('reportRestored', (data) {
      print('RealtimeService: Report restored: $data');
      _eventController.add({
        'type': 'report',
        'action': 'restored',
        'data': data,
      });
    });

    // User account events for real-time sync
    _socket!.on('userCreated', (data) {
      print('RealtimeService: User created: $data');
      _userController.add({'type': 'created', 'data': data});
      _eventController.add({'type': 'user', 'action': 'created', 'data': data});
    });

    _socket!.on('userDeleted', (data) {
      print('RealtimeService: User deleted: $data');
      _userController.add({'type': 'deleted', 'data': data});
      _eventController.add({'type': 'user', 'action': 'deleted', 'data': data});
    });

    _socket!.on('userDeactivated', (data) {
      print('RealtimeService: User deactivated: $data');
      _userController.add({'type': 'deactivated', 'data': data});
      _eventController.add({
        'type': 'user',
        'action': 'deactivated',
        'data': data,
      });
    });

    _socket!.on('userReactivated', (data) {
      print('RealtimeService: User reactivated: $data');
      _userController.add({'type': 'reactivated', 'data': data});
      _eventController.add({
        'type': 'user',
        'action': 'reactivated',
        'data': data,
      });
    });

    // Persisted (DB-backed) notifications pushed via AppNotificationService.
    _socket!.on('notificationCreated', (data) {
      try {
        if (data is Map<String, dynamic>) {
          _notificationController.add(data);
          _eventController.add({
            'type': 'notification',
            'action': (data['action'] ?? data['scope'] ?? 'created').toString(),
            'data': data,
          });
        } else if (data is Map) {
          final mapped = Map<String, dynamic>.from(data);
          _notificationController.add(mapped);
          _eventController.add({
            'type': 'notification',
            'action': (mapped['action'] ?? mapped['scope'] ?? 'created')
                .toString(),
            'data': mapped,
          });
        }
      } catch (e) {
        print('RealtimeService: Error processing notificationCreated: $e');
      }
    });

    // Admin notifications for check-in/check-out events
    _socket!.on('adminNotification', (data) {
      print('RealtimeService: Admin notification: $data');
      if (data is Map<String, dynamic>) {
        _notificationController.add(data);
        _eventController.add({
          'type': 'notification',
          'action': data['action'] ?? 'info',
          'data': data,
        });
      }
    });

    // Employee online/offline presence events
    _socket!.on('employeeOnline', (data) {
      print('RealtimeService: Employee online: $data');
      try {
        if (data is Map<String, dynamic>) {
          _eventController.add({
            'type': 'presence',
            'action': 'employeeOnline',
            'data': data,
          });
        } else if (data is Map) {
          _eventController.add({
            'type': 'presence',
            'action': 'employeeOnline',
            'data': Map<String, dynamic>.from(data),
          });
        }
      } catch (e) {
        print('RealtimeService: Error processing employeeOnline: $e');
      }
    });

    _socket!.on('employeeOffline', (data) {
      print('RealtimeService: Employee offline: $data');
      try {
        if (data is Map<String, dynamic>) {
          _eventController.add({
            'type': 'presence',
            'action': 'employeeOffline',
            'data': data,
          });
        } else if (data is Map) {
          _eventController.add({
            'type': 'presence',
            'action': 'employeeOffline',
            'data': Map<String, dynamic>.from(data),
          });
        }
      } catch (e) {
        print('RealtimeService: Error processing employeeOffline: $e');
      }
    });

    _socket!.on('adminNearbyMode', (data) {
      print('RealtimeService: adminNearbyMode: $data');
      try {
        if (data is Map<String, dynamic>) {
          _adminNearbyController.add(data);
        } else if (data is Map) {
          _adminNearbyController.add(Map<String, dynamic>.from(data));
        }
      } catch (e) {
        print('RealtimeService: Error processing adminNearbyMode: $e');
      }
    });

    _socket!.on('unreadCounts', (data) {
      try {
        if (data is Map<String, dynamic>) {
          _unreadCountsController.add(data);
        } else if (data is Map) {
          _unreadCountsController.add(Map<String, dynamic>.from(data));
        }
      } catch (e) {
        print('Error processing unreadCounts: $e');
      }
    });

    _socket!.on('chatMessage', (data) {
      try {
        if (data is Map<String, dynamic>) {
          _chatController.add(data);
          _eventController.add({
            'type': 'chat',
            'action': 'message',
            'data': data,
          });
        } else if (data is Map) {
          final mapped = Map<String, dynamic>.from(data);
          _chatController.add(mapped);
          _eventController.add({
            'type': 'chat',
            'action': 'message',
            'data': mapped,
          });
        }
      } catch (e) {
        print('Error processing chatMessage: $e');
      }
    });
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    // Avoid aggressive loops; keep a slow fallback reconnect in case the
    // underlying client reconnection is blocked by a transient error.
    _reconnectTimer = Timer(
      Duration(seconds: 5 + (2 * _reconnectAttempts)),
      () {
        _reconnectAttempts = (_reconnectAttempts + 1).clamp(0, 999999);
        try {
          if (_socket != null && !_isConnected) {
            _socket!.connect();
            return;
          }
        } catch (_) {}

        initialize();
      },
    );
  }

  void emit(String event, Map<String, dynamic> data) {
    if (_socket != null && _isConnected) {
      _socket!.emit(event, data);
    } else {
      print('RealtimeService: Cannot emit $event - not connected');
    }
  }

  void joinRoom(String room) {
    final r = room.trim();
    if (r.isEmpty) return;
    _rooms.add(r);
    if (_socket != null && _isConnected) {
      _socket!.emit('joinRoom', {'room': r});
    }
  }

  void leaveRoom(String room) {
    final r = room.trim();
    if (r.isEmpty) return;
    _rooms.remove(r);
    if (_socket != null && _isConnected) {
      _socket!.emit('leaveRoom', {'room': r});
    }
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    try {
      _socket?.disconnect();
      _socket?.dispose();
    } catch (_) {}
    _socket = null;
    _isConnected = false;
  }

  /// Hard reset for logout flows.
  ///
  /// RealtimeService is a singleton, so without an explicit reset a user can log
  /// out and log back in as another account and still carry stale rooms/token.
  void reset() {
    disconnect();
    _lastAuthToken = null;
    _rooms.clear();
    _reconnectAttempts = 0;
  }

  void dispose() {
    disconnect();
    _eventController.close();
    _onlineCountController.close();
    _attendanceController.close();
    _taskController.close();
    _userController.close();
    _locationController.close();
    _notificationController.close();
    _chatController.close();
    _adminNearbyController.close();
  }
}
