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

  bool _isConnected = false;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int maxReconnectAttempts = 5;

  Stream<Map<String, dynamic>> get eventStream => _eventController.stream;
  Stream<int> get onlineCountStream => _onlineCountController.stream;
  Stream<Map<String, dynamic>> get attendanceStream =>
      _attendanceController.stream;
  Stream<Map<String, dynamic>> get taskStream => _taskController.stream;
  Stream<Map<String, dynamic>> get userStream => _userController.stream;
  Stream<Map<String, dynamic>> get locationStream => _locationController.stream;
  Stream<Map<String, dynamic>> get notificationStream =>
      _notificationController.stream;

  bool get isConnected => _isConnected;

  Future<void> initialize() async {
    if (_socket != null && _isConnected) return;

    try {
      final token = await UserService().getToken();
      final options = io.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          .setExtraHeaders({
            if (token != null) 'Authorization': 'Bearer $token',
          })
          .setTimeout(20000)
          .build();

      _socket = io.io(ApiConfig.baseUrl, options);

      _socket!.onConnect((_) {
        print('RealtimeService: Connected to Socket.IO');
        _isConnected = true;
        _reconnectAttempts = 0;
        _reconnectTimer?.cancel();
      });

      _socket!.onDisconnect((_) {
        print('RealtimeService: Disconnected from Socket.IO');
        _isConnected = false;
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
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= maxReconnectAttempts) {
      print('RealtimeService: Max reconnection attempts reached');
      return;
    }

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: 2 * (_reconnectAttempts + 1)), () {
      _reconnectAttempts++;
      print(
        'RealtimeService: Attempting reconnection $_reconnectAttempts/$maxReconnectAttempts',
      );
      initialize();
    });
  }

  void emit(String event, Map<String, dynamic> data) {
    if (_socket != null && _isConnected) {
      _socket!.emit(event, data);
    } else {
      print('RealtimeService: Cannot emit $event - not connected');
    }
  }

  void joinRoom(String room) {
    if (_socket != null && _isConnected) {
      _socket!.emit('joinRoom', {'room': room});
    }
  }

  void leaveRoom(String room) {
    if (_socket != null && _isConnected) {
      _socket!.emit('leaveRoom', {'room': room});
    }
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _socket?.disconnect();
    _socket = null;
    _isConnected = false;
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
  }
}
