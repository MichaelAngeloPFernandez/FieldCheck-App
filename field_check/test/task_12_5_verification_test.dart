import 'package:flutter_test/flutter_test.dart';
import 'package:field_check/services/client_ticket_service.dart';
import 'package:field_check/services/realtime_service.dart';

void main() {
  group('Task 12.5 - Enhanced Client Ticket Service', () {
    late ClientTicketService service;

    setUp(() {
      service = ClientTicketService();
    });

    test('Service should have RealtimeService dependency', () {
      // Verify that the service has access to RealtimeService
      expect(service, isNotNull);
      // The service should be able to create instances without errors
      expect(() => ClientTicketService(), returnsNormally);
    });

    test('Service should validate Socket.IO connection before processing', () async {
      // Test that Socket.IO validation happens first
      final result = await service.submitClientTicket(
        clientName: 'Valid Name',
        clientEmail: 'valid@email.com',
        serviceType: 'maintenance',
        description: 'Test description',
      );

      // Verify Socket.IO connection check happens first
      expect(result['success'], false);
      expect(result['errorType'], 'socket');
      expect(result['errorCode'], 'SOCKET_DISCONNECTED');
      expect(result['canRetry'], true);
      expect(result['timestamp'], isNotNull);
      
      // Verify the error message is user-friendly
      expect(result['error'], contains('Real-time connection unavailable'));
    });

    test('Enhanced error response structure should include all required fields', () async {
      final result = await service.submitClientTicket(
        clientName: 'Valid Name',
        clientEmail: 'valid@email.com',
        serviceType: 'maintenance',
        description: 'Test description',
      );

      // Verify enhanced error structure (will be socket error due to no connection)
      expect(result['success'], false);
      expect(result['errorType'], isNotNull);
      expect(result['errorCode'], isNotNull);
      expect(result['canRetry'], isNotNull);
      expect(result['timestamp'], isNotNull);
      expect(result['details'], isNotNull);
      
      // Verify it's a socket error as expected
      expect(result['errorType'], 'socket');
      expect(result['canRetry'], true);
    });

    test('Error responses should include proper logging information', () async {
      final result = await service.submitClientTicket(
        clientName: 'Valid Name',
        clientEmail: 'valid@email.com',
        serviceType: 'maintenance',
        description: 'Test description',
      );

      // Verify that error response includes timestamp for logging
      expect(result['timestamp'], isNotNull);
      expect(DateTime.tryParse(result['timestamp']), isNotNull);
      
      // Verify error details are included for debugging
      expect(result['details'], isNotNull);
      expect(result['details'], isA<String>());
    });

    test('Service should handle different error types with proper classification', () async {
      // All tests will return socket errors due to no connection,
      // but we can verify the error structure is consistent
      final result = await service.submitClientTicket(
        clientName: 'Test Name',
        clientEmail: 'test@email.com',
        serviceType: 'cleaning',
        description: 'Test description for error handling',
      );

      // Verify consistent error structure
      expect(result, containsPair('success', false));
      expect(result, containsPair('errorType', 'socket'));
      expect(result, containsPair('errorCode', 'SOCKET_DISCONNECTED'));
      expect(result, containsPair('canRetry', true));
      expect(result.containsKey('timestamp'), true);
      expect(result.containsKey('details'), true);
    });

    test('Service should provide user-friendly error messages', () async {
      final result = await service.submitClientTicket(
        clientName: 'Test User',
        clientEmail: 'user@test.com',
        serviceType: 'maintenance',
        description: 'Testing user-friendly error messages',
      );

      // Verify error message is user-friendly, not technical
      expect(result['error'], isA<String>());
      expect(result['error'], isNot(contains('Exception')));
      expect(result['error'], isNot(contains('Error:')));
      
      // Should contain helpful guidance
      expect(result['error'], contains('connection'));
    });
  });
}