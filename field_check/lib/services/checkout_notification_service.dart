import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../config/api_config.dart';
import '../services/user_service.dart';

/// Service for handling auto-checkout notifications and warnings
class CheckoutNotificationService {
  static final CheckoutNotificationService _instance =
      CheckoutNotificationService._internal();

  factory CheckoutNotificationService() => _instance;
  CheckoutNotificationService._internal();

  late io.Socket _socket;
  bool _isConnected = false;

  final StreamController<CheckoutWarning> _warningStream =
      StreamController<CheckoutWarning>.broadcast();
  final StreamController<AutoCheckoutEvent> _checkoutStream =
      StreamController<AutoCheckoutEvent>.broadcast();

  Stream<CheckoutWarning> get warningStream => _warningStream.stream;
  Stream<AutoCheckoutEvent> get checkoutStream => _checkoutStream.stream;

  /// Initialize socket connection for notifications
  Future<void> initialize() async {
    if (_isConnected) return;

    try {
      final token = await UserService().getToken();
      final options = io.OptionBuilder()
          .setTransports(['websocket'])
          .enableAutoConnect()
          .setTimeout(20000)
          .build();

      if (token != null) {
        options['extraHeaders'] = {'Authorization': 'Bearer $token'};
      }

      options['reconnection'] = true;
      options['reconnectionAttempts'] = 999999;
      options['reconnectionDelay'] = 500;

      _socket = io.io(ApiConfig.baseUrl, options);

      _socket.onConnect((_) {
        _isConnected = true;
        debugPrint('✅ Checkout notification service connected');
      });

      _socket.onDisconnect((_) {
        _isConnected = false;
        debugPrint('❌ Checkout notification service disconnected');
      });

      // Listen for checkout warnings
      _socket.on('checkoutWarning', (data) {
        debugPrint('⚠️ Checkout warning received: $data');
        final warning = CheckoutWarning.fromMap(data);
        _warningStream.add(warning);
      });

      // Listen for auto-checkout events
      _socket.on('employeeAutoCheckout', (data) {
        debugPrint('🔴 Auto-checkout event received: $data');
        final event = AutoCheckoutEvent.fromMap(data);
        _checkoutStream.add(event);
      });

      debugPrint('✅ Checkout notification service initialized');
    } catch (e) {
      debugPrint('❌ Error initializing checkout notification service: $e');
    }
  }

  /// Check if service is connected
  bool get isConnected => _isConnected;

  /// Dispose service
  void dispose() {
    _socket.disconnect();
    _warningStream.close();
    _checkoutStream.close();
  }
}

/// Checkout warning model
class CheckoutWarning {
  final String employeeId;
  final String employeeName;
  final int minutesRemaining;
  final String message;
  final DateTime timestamp;

  CheckoutWarning({
    required this.employeeId,
    required this.employeeName,
    required this.minutesRemaining,
    required this.message,
    required this.timestamp,
  });

  factory CheckoutWarning.fromMap(Map<String, dynamic> map) {
    return CheckoutWarning(
      employeeId: map['employeeId'] ?? '',
      employeeName: map['employeeName'] ?? 'Unknown',
      minutesRemaining: map['minutesRemaining'] ?? 5,
      message: map['message'] ?? 'You will be auto-checked out soon',
      timestamp: DateTime.parse(
        map['timestamp'] ?? DateTime.now().toIso8601String(),
      ),
    );
  }
}

/// Auto-checkout event model
class AutoCheckoutEvent {
  final String employeeId;
  final String employeeName;
  final String reason;
  final DateTime timestamp;
  final bool isVoid;

  AutoCheckoutEvent({
    required this.employeeId,
    required this.employeeName,
    required this.reason,
    required this.timestamp,
    required this.isVoid,
  });

  factory AutoCheckoutEvent.fromMap(Map<String, dynamic> map) {
    return AutoCheckoutEvent(
      employeeId: map['employeeId'] ?? '',
      employeeName: map['employeeName'] ?? 'Unknown',
      reason: map['reason'] ?? 'Offline for extended period',
      timestamp: DateTime.parse(
        map['timestamp'] ?? DateTime.now().toIso8601String(),
      ),
      isVoid: map['isVoid'] ?? true,
    );
  }
}
