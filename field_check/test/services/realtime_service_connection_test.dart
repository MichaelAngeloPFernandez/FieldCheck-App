import 'package:flutter_test/flutter_test.dart';
import 'package:field_check/services/realtime_service.dart';

void main() {
  group('RealtimeService Connection Management', () {
    late RealtimeService realtimeService;

    setUp(() {
      realtimeService = RealtimeService();
    });

    test('should provide connection status getter', () {
      // Test the public connection status getter
      final status = realtimeService.connectionStatus;
      
      expect(status, isA<Map<String, dynamic>>());
      expect(status.containsKey('isConnected'), isTrue);
      expect(status.containsKey('reconnectAttempts'), isTrue);
      expect(status.containsKey('hasSocket'), isTrue);
      expect(status.containsKey('roomsJoined'), isTrue);
    });

    test('should provide connection status validation', () {
      // Test the isConnected getter
      expect(realtimeService.isConnected, isA<bool>());
    });

    test('should provide connection status stream', () {
      // Test the connection status stream
      expect(realtimeService.connectionStatusStream, isA<Stream<Map<String, dynamic>>>());
    });

    test('should provide connection recovery stream', () {
      // Test the connection recovery stream
      expect(realtimeService.connectionRecoveryStream, isA<Stream<Map<String, dynamic>>>());
    });

    test('should provide health check method', () async {
      // Test the health check method exists and returns a boolean
      final healthResult = await realtimeService.performHealthCheck();
      expect(healthResult, isA<bool>());
    });

    test('connection status should include all required fields', () {
      final status = realtimeService.connectionStatus;
      
      // Verify all required fields are present
      expect(status['isConnected'], isA<bool>());
      expect(status['reconnectAttempts'], isA<int>());
      expect(status['hasSocket'], isA<bool>());
      expect(status['roomsJoined'], isA<List>());
      
      // Optional fields (may be null initially)
      expect(status.containsKey('lastConnectionTime'), isTrue);
      expect(status.containsKey('lastDisconnectionTime'), isTrue);
      expect(status.containsKey('lastError'), isTrue);
    });

    test('should handle connection validation gracefully when not connected', () async {
      // When not connected, health check should return false
      final healthResult = await realtimeService.performHealthCheck();
      expect(healthResult, isFalse);
    });
  });
}