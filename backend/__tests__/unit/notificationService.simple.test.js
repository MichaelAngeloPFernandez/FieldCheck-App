/**
 * Unit tests for Notification Service - Task Notifications
 * Tests the notification functions structure and exports
 */

const notificationService = require('../../services/notificationService');

describe('Notification Service - Task Notifications', () => {
  describe('Module exports', () => {
    it('should export notifyTaskAssignment function', () => {
      expect(typeof notificationService.notifyTaskAssignment).toBe('function');
    });

    it('should export notifyTaskCompletion function', () => {
      expect(typeof notificationService.notifyTaskCompletion).toBe('function');
    });

    it('should export notifyTaskStatusChange function', () => {
      expect(typeof notificationService.notifyTaskStatusChange).toBe('function');
    });

    it('should export legacy notification functions', () => {
      expect(typeof notificationService.sendSms).toBe('function');
      expect(typeof notificationService.notifyTaskAssigned).toBe('function');
      expect(typeof notificationService.notifyTaskOverdue).toBe('function');
      expect(typeof notificationService.notifyTaskEscalated).toBe('function');
      expect(typeof notificationService.notifyAttendanceCheckIn).toBe('function');
      expect(typeof notificationService.notifyAttendanceCheckOut).toBe('function');
      expect(typeof notificationService.notifyAutoCheckoutWarning).toBe('function');
      expect(typeof notificationService.notifyLocationWarning).toBe('function');
      expect(typeof notificationService.notifyWorkloadWarning).toBe('function');
    });
  });

  describe('notifyTaskAssignment', () => {
    it('should be an async function', async () => {
      const result = notificationService.notifyTaskAssignment('task1', 'emp1', 'user1');
      expect(result instanceof Promise).toBe(true);
    });

    it('should handle missing socket.io gracefully', async () => {
      global.io = undefined;

      // Should not throw
      await expect(
        notificationService.notifyTaskAssignment('task1', 'emp1', 'user1')
      ).resolves.not.toThrow();
    });
  });

  describe('notifyTaskCompletion', () => {
    it('should be an async function', async () => {
      const result = notificationService.notifyTaskCompletion('task1', 'emp1');
      expect(result instanceof Promise).toBe(true);
    });

    it('should handle missing socket.io gracefully', async () => {
      global.io = undefined;

      // Should not throw
      await expect(
        notificationService.notifyTaskCompletion('task1', 'emp1')
      ).resolves.not.toThrow();
    });
  });

  describe('notifyTaskStatusChange', () => {
    it('should be an async function', async () => {
      const result = notificationService.notifyTaskStatusChange('task1', 'pending', 'in_progress', 'user1');
      expect(result instanceof Promise).toBe(true);
    });

    it('should accept optional reason parameter', async () => {
      global.io = undefined;

      // Should not throw with or without reason
      await expect(
        notificationService.notifyTaskStatusChange('task1', 'pending', 'in_progress', 'user1')
      ).resolves.not.toThrow();

      await expect(
        notificationService.notifyTaskStatusChange('task1', 'pending', 'in_progress', 'user1', 'Test reason')
      ).resolves.not.toThrow();
    });

    it('should handle missing socket.io gracefully', async () => {
      global.io = undefined;

      // Should not throw
      await expect(
        notificationService.notifyTaskStatusChange('task1', 'pending', 'in_progress', 'user1')
      ).resolves.not.toThrow();
    });
  });

  describe('Legacy notification functions', () => {
    it('should return undefined for legacy functions', async () => {
      const result1 = await notificationService.sendSms();
      const result2 = await notificationService.notifyTaskAssigned();
      const result3 = await notificationService.notifyTaskOverdue();

      expect(result1).toBeUndefined();
      expect(result2).toBeUndefined();
      expect(result3).toBeUndefined();
    });
  });
});
