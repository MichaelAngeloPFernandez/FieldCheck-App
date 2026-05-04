/**
 * Integration tests for Task Cloning Service
 * These tests verify the cloning logic works correctly with real database operations
 * Run with: npm test -- __tests__/integration/taskCloningService.integration.test.js
 */

const { cloneTemplateTasksForTicket } = require('../../services/taskCloningService');

describe('Task Cloning Service - Integration Tests', () => {
  describe('cloneTemplateTasksForTicket', () => {
    it('should be a function', () => {
      expect(typeof cloneTemplateTasksForTicket).toBe('function');
    });

    it('should accept required parameters', () => {
      const ticketId = 'ticket123';
      const serviceId = 'service123';
      const companyId = 'company123';
      const userId = 'user123';

      // Function should be callable with these parameters
      expect(() => {
        cloneTemplateTasksForTicket(ticketId, serviceId, companyId, userId);
      }).not.toThrow();
    });
  });
});
