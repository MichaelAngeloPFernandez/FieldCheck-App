// ignore_for_file: avoid_print, library_prefixes
import 'dart:async';
import 'package:flutter/scheduler.dart';
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
  final StreamController<Map<String, dynamic>> _geofenceController =
      StreamController<Map<String, dynamic>>.broadcast();

  bool _isConnected = false;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int maxReconnectAttempts = 5;
  final Set<String> _rooms = <String>{};
  
  // Connection management enhancements
  Timer? _healthCheckTimer;
  DateTime? _lastConnectionTime;
  DateTime? _lastDisconnectionTime;
  String? _lastConnectionError;
  final StreamController<Map<String, dynamic>> _connectionStatusController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _connectionRecoveryController =
      StreamController<Map<String, dynamic>>.broadcast();

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
  Stream<Map<String, dynamic>> get geofenceStream =>
      _geofenceController.stream;
  Stream<Map<String, dynamic>> get connectionStatusStream =>
      _connectionStatusController.stream;
  Stream<Map<String, dynamic>> get connectionRecoveryStream =>
      _connectionRecoveryController.stream;

  bool get isConnected => _isConnected;
  
  /// Public getter for connection status validation
  /// Returns detailed connection information for external validation
  Map<String, dynamic> get connectionStatus => {
    'isConnected': _isConnected,
    'reconnectAttempts': _reconnectAttempts,
    'lastConnectionTime': _lastConnectionTime?.toIso8601String(),
    'lastDisconnectionTime': _lastDisconnectionTime?.toIso8601String(),
    'lastError': _lastConnectionError,
    'hasSocket': _socket != null,
    'roomsJoined': _rooms.toList(),
  };
  
  /// Connection health check method that can be called externally
  /// Returns true if connection is healthy, false otherwise
  Future<bool> performHealthCheck() async {
    try {
      if (_socket == null || !_isConnected) {
        print('RealtimeService: Health check failed - not connected');
        return false;
      }
      
      // Test connection by emitting a ping event
      final completer = Completer<bool>();
      Timer? timeoutTimer;
      
      // Set up timeout for health check
      timeoutTimer = Timer(const Duration(seconds: 5), () {
        if (!completer.isCompleted) {
          completer.complete(false);
        }
      });
      
      // Listen for pong response
      _socket!.once('pong', (_) {
        timeoutTimer?.cancel();
        if (!completer.isCompleted) {
          completer.complete(true);
        }
      });
      
      // Send ping
      _socket!.emit('ping');
      
      final result = await completer.future;
      print('RealtimeService: Health check result: $result');
      
      // Emit health check result
      _connectionStatusController.add({
        'type': 'health_check',
        'healthy': result,
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      return result;
    } catch (e) {
      print('RealtimeService: Health check error: $e');
      _connectionStatusController.add({
        'type': 'health_check',
        'healthy': false,
        'error': e.toString(),
        'timestamp': DateTime.now().toIso8601String(),
      });
      return false;
    }
  }

  bool _isWidgetTestEnvironment() {
    try {
      return SchedulerBinding.instance.runtimeType
          .toString()
          .contains('TestWidgets');
    } catch (_) {
      return false;
    }
  }

  Future<void> initialize() async {
    if (_isWidgetTestEnvironment()) return;

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
        _lastConnectionTime = DateTime.now();
        _lastConnectionError = null;
        _reconnectTimer?.cancel();
        
        // Emit connection recovery notification
        _connectionRecoveryController.add({
          'type': 'connected',
          'timestamp': _lastConnectionTime!.toIso8601String(),
          'reconnectAttempts': _reconnectAttempts,
        });
        
        // Emit connection status update
        _connectionStatusController.add({
          'type': 'connection_status',
          'connected': true,
          'timestamp': _lastConnectionTime!.toIso8601String(),
        });

        // Re-join any rooms after reconnect.
        for (final room in _rooms) {
          try {
            _socket!.emit('joinRoom', {'room': room});
          } catch (_) {}
        }
        
        // Start periodic health checks
        _startHealthCheckTimer();
      });

      _socket!.onDisconnect((_) {
        print('RealtimeService: Disconnected from Socket.IO');
        _isConnected = false;
        _lastDisconnectionTime = DateTime.now();
        _healthCheckTimer?.cancel();
        
        // Emit connection status update
        _connectionStatusController.add({
          'type': 'connection_status',
          'connected': false,
          'timestamp': _lastDisconnectionTime!.toIso8601String(),
        });
        
        // Socket.IO client will auto-reconnect; keep a lightweight fallback.
        _scheduleReconnectWithBackoff();
      });

      _socket!.onConnectError((err) {
        print('RealtimeService: Connect Error: $err');
        _isConnected = false;
        _lastConnectionError = err.toString();
        _lastDisconnectionTime = DateTime.now();
        
        // Classify connection error type
        final errorType = _classifyConnectionError(err);
        
        // Emit connection error notification
        _connectionStatusController.add({
          'type': 'connection_error',
          'error': err.toString(),
          'errorType': errorType,
          'timestamp': _lastDisconnectionTime!.toIso8601String(),
          'reconnectAttempts': _reconnectAttempts,
        });
      });

      _socket!.onError((err) {
        print('RealtimeService: Error: $err');
        _lastConnectionError = err.toString();
        
        // Classify error type for better handling
        final errorType = _classifyConnectionError(err);
        
        // Emit error notification
        _connectionStatusController.add({
          'type': 'socket_error',
          'error': err.toString(),
          'errorType': errorType,
          'timestamp': DateTime.now().toIso8601String(),
        });
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

    // Handle notifications marked as read from another device/tab
    _socket!.on('notificationsRead', (data) {
      try {
        if (data is Map<String, dynamic>) {
          final notificationIds = data['notificationIds'];
          if (notificationIds is List) {
            _eventController.add({
              'type': 'notification',
              'action': 'read',
              'notificationIds': notificationIds,
              'data': data,
            });
          }
        } else if (data is Map) {
          final mapped = Map<String, dynamic>.from(data);
          final notificationIds = mapped['notificationIds'];
          if (notificationIds is List) {
            _eventController.add({
              'type': 'notification',
              'action': 'read',
              'notificationIds': notificationIds,
              'data': mapped,
            });
          }
        }
      } catch (e) {
        print('RealtimeService: Error processing notificationsRead: $e');
      }
    });

    // Handle notifications deleted from another device/tab or auto-deleted (employee offline)
    _socket!.on('notificationsDeleted', (data) {
      try {
        if (data is Map<String, dynamic>) {
          final notificationIds = data['notificationIds'];
          if (notificationIds is List) {
            _eventController.add({
              'type': 'notification',
              'action': 'deleted',
              'notificationIds': notificationIds,
              'data': data,
            });
          }
        } else if (data is Map) {
          final mapped = Map<String, dynamic>.from(data);
          final notificationIds = mapped['notificationIds'];
          if (notificationIds is List) {
            _eventController.add({
              'type': 'notification',
              'action': 'deleted',
              'notificationIds': notificationIds,
              'data': mapped,
            });
          }
        }
      } catch (e) {
        print('RealtimeService: Error processing notificationsDeleted: $e');
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

    // Geofence events - real-time updates for newly created/updated geofences
    _socket!.on('geofenceCreated', (data) {
      print('RealtimeService: Geofence created: $data');
      try {
        if (data is Map<String, dynamic>) {
          _geofenceController.add({'type': 'created', 'data': data});
          _eventController.add({
            'type': 'geofence',
            'action': 'created',
            'data': data,
          });
        } else if (data is Map) {
          final mapped = Map<String, dynamic>.from(data);
          _geofenceController.add({'type': 'created', 'data': mapped});
          _eventController.add({
            'type': 'geofence',
            'action': 'created',
            'data': mapped,
          });
        }
      } catch (e) {
        print('RealtimeService: Error processing geofenceCreated: $e');
      }
    });

    _socket!.on('geofenceUpdated', (data) {
      print('RealtimeService: Geofence updated: $data');
      try {
        if (data is Map<String, dynamic>) {
          _geofenceController.add({'type': 'updated', 'data': data});
          _eventController.add({
            'type': 'geofence',
            'action': 'updated',
            'data': data,
          });
        } else if (data is Map) {
          final mapped = Map<String, dynamic>.from(data);
          _geofenceController.add({'type': 'updated', 'data': mapped});
          _eventController.add({
            'type': 'geofence',
            'action': 'updated',
            'data': mapped,
          });
        }
      } catch (e) {
        print('RealtimeService: Error processing geofenceUpdated: $e');
      }
    });

    _socket!.on('geofenceDeleted', (data) {
      print('RealtimeService: Geofence deleted: $data');
      try {
        if (data is Map<String, dynamic>) {
          _geofenceController.add({'type': 'deleted', 'data': data});
          _eventController.add({
            'type': 'geofence',
            'action': 'deleted',
            'data': data,
          });
        } else if (data is Map) {
          final mapped = Map<String, dynamic>.from(data);
          _geofenceController.add({'type': 'deleted', 'data': mapped});
          _eventController.add({
            'type': 'geofence',
            'action': 'deleted',
            'data': mapped,
          });
        }
      } catch (e) {
        print('RealtimeService: Error processing geofenceDeleted: $e');
      }
    });
  }

  void _scheduleReconnectWithBackoff() {
    _reconnectTimer?.cancel();
    
    // Aggressive reconnection strategy for presence-critical features
    // Use fixed 2-second interval for first 10 attempts, then exponential backoff
    final isPresenceCritical = _reconnectAttempts < 10;
    
    int finalDelay;
    if (isPresenceCritical) {
      // Fixed 2-second interval for presence-critical reconnection
      finalDelay = 2000;
    } else {
      // Exponential backoff with jitter for persistent failures
      final baseDelay = 2000; // 2 seconds base
      final maxDelay = 30000; // 30 seconds max
      final backoffMultiplier = 1.5;
      
      final delay = (baseDelay * 
          (backoffMultiplier * (_reconnectAttempts - 10)).clamp(1, maxDelay ~/ baseDelay))
          .clamp(baseDelay, maxDelay);
      
      // Add jitter (±10% of delay)
      final jitter = (delay * 0.1 * (2 * (DateTime.now().millisecond / 1000) - 1)).round();
      finalDelay = ((delay + jitter).clamp(baseDelay, maxDelay) as int);
    }
    
    print('RealtimeService: Scheduling reconnect in ${finalDelay}ms (attempt ${_reconnectAttempts + 1}, presence-critical: $isPresenceCritical)');
    
    _reconnectTimer = Timer(
      Duration(milliseconds: finalDelay),
      () {
        _reconnectAttempts = (_reconnectAttempts + 1).clamp(0, 999999);
        
        // Emit reconnection attempt notification
        _connectionRecoveryController.add({
          'type': 'reconnect_attempt',
          'attempt': _reconnectAttempts,
          'presenceCritical': isPresenceCritical,
          'timestamp': DateTime.now().toIso8601String(),
        });
        
        try {
          if (_socket != null && !_isConnected) {
            print('RealtimeService: Attempting to reconnect (attempt $_reconnectAttempts)');
            _socket!.connect();
            return;
          }
        } catch (e) {
          print('RealtimeService: Reconnect attempt failed: $e');
        }

        // Fallback to full reinitialization
        initialize();
      },
    );
  }
  
  /// Classify connection errors for better error handling
  String _classifyConnectionError(dynamic error) {
    final errorStr = error.toString().toLowerCase();
    
    if (errorStr.contains('timeout') || errorStr.contains('timed out')) {
      return 'timeout';
    } else if (errorStr.contains('network') || errorStr.contains('connection refused') || 
               errorStr.contains('unreachable') || errorStr.contains('dns')) {
      return 'network';
    } else if (errorStr.contains('auth') || errorStr.contains('unauthorized') || 
               errorStr.contains('forbidden') || errorStr.contains('token')) {
      return 'authentication';
    } else if (errorStr.contains('websocket') || errorStr.contains('transport')) {
      return 'transport';
    } else {
      return 'unknown';
    }
  }
  
  /// Start periodic health check timer
  void _startHealthCheckTimer() {
    _healthCheckTimer?.cancel();
    
    // Perform health check every 30 seconds
    _healthCheckTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_isConnected) {
        performHealthCheck();
      }
    });
  }

  void emit(String event, Map<String, dynamic> data) {
    if (_socket != null && _isConnected) {
      try {
        _socket!.emit(event, data);
        print('RealtimeService: Emitted event "$event" with data: $data');
      } catch (e) {
        print('RealtimeService: Failed to emit event "$event": $e');
        _connectionStatusController.add({
          'type': 'emit_error',
          'event': event,
          'error': e.toString(),
          'timestamp': DateTime.now().toIso8601String(),
        });
      }
    } else {
      print('RealtimeService: Cannot emit $event - not connected (socket: ${_socket != null}, connected: $_isConnected)');
      _connectionStatusController.add({
        'type': 'emit_failed',
        'event': event,
        'reason': 'not_connected',
        'timestamp': DateTime.now().toIso8601String(),
      });
    }
  }

  void joinRoom(String room) {
    final r = room.trim();
    if (r.isEmpty) return;
    _rooms.add(r);
    if (_socket != null && _isConnected) {
      try {
        _socket!.emit('joinRoom', {'room': r});
        print('RealtimeService: Joined room "$r"');
      } catch (e) {
        print('RealtimeService: Failed to join room "$r": $e');
      }
    } else {
      print('RealtimeService: Queued room "$r" for joining when connected');
    }
  }

  void leaveRoom(String room) {
    final r = room.trim();
    if (r.isEmpty) return;
    _rooms.remove(r);
    if (_socket != null && _isConnected) {
      try {
        _socket!.emit('leaveRoom', {'room': r});
        print('RealtimeService: Left room "$r"');
      } catch (e) {
        print('RealtimeService: Failed to leave room "$r": $e');
      }
    } else {
      print('RealtimeService: Removed room "$r" from queue');
    }
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _healthCheckTimer?.cancel();
    
    try {
      _socket?.disconnect();
      _socket?.dispose();
    } catch (_) {}
    _socket = null;
    _isConnected = false;
    _lastDisconnectionTime = DateTime.now();
    
    // Emit disconnection notification
    _connectionStatusController.add({
      'type': 'manual_disconnect',
      'timestamp': _lastDisconnectionTime!.toIso8601String(),
    });
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
    _lastConnectionTime = null;
    _lastDisconnectionTime = null;
    _lastConnectionError = null;
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
    _connectionStatusController.close();
    _connectionRecoveryController.close();
  }
}
