/**
 * Unit tests for Task Status Service
 * Tests the status transition logic without database
 */

const {
  isValidTransition,
  getValidNextStatuses,
  VALID_TRANSITIONS,
} = require('../../services/taskStatusService');

describe('Task Status Service - Status Transitions', () => {
  describe('isValidTransition', () => {
    it('should allow pending to in_progress', () => {
      expect(isValidTransition('pending', 'in_progress')).toBe(true);
    });

    it('should allow pending to blocked', () => {
      expect(isValidTransition('pending', 'blocked')).toBe(true);
    });

    it('should allow in_progress to completed', () => {
      expect(isValidTransition('in_progress', 'completed')).toBe(true);
    });

    it('should allow in_progress to blocked', () => {
      expect(isValidTransition('in_progress', 'blocked')).toBe(true);
    });

    it('should allow blocked to in_progress', () => {
      expect(isValidTransition('blocked', 'in_progress')).toBe(true);
    });

    it('should allow completed to reviewed', () => {
      expect(isValidTransition('completed', 'reviewed')).toBe(true);
    });

    it('should allow reviewed to closed', () => {
      expect(isValidTransition('reviewed', 'closed')).toBe(true);
    });

    it('should allow any status to blocked', () => {
      expect(isValidTransition('pending', 'blocked')).toBe(true);
      expect(isValidTransition('in_progress', 'blocked')).toBe(true);
      expect(isValidTransition('completed', 'blocked')).toBe(true);
      expect(isValidTransition('reviewed', 'blocked')).toBe(true);
      expect(isValidTransition('closed', 'blocked')).toBe(true);
    });

    it('should reject invalid transitions', () => {
      expect(isValidTransition('pending', 'completed')).toBe(false);
      expect(isValidTransition('completed', 'pending')).toBe(false);
      expect(isValidTransition('reviewed', 'in_progress')).toBe(false);
      expect(isValidTransition('closed', 'pending')).toBe(false);
    });

    it('should handle case-insensitive statuses', () => {
      expect(isValidTransition('PENDING', 'IN_PROGRESS')).toBe(true);
      expect(isValidTransition('Pending', 'In_Progress')).toBe(true);
    });

    it('should handle null/undefined statuses', () => {
      expect(isValidTransition(null, 'in_progress')).toBe(true);
      expect(isValidTransition(undefined, 'in_progress')).toBe(true);
    });
  });

  describe('getValidNextStatuses', () => {
    it('should return valid next statuses for pending', () => {
      const validStatuses = getValidNextStatuses('pending');
      expect(validStatuses).toContain('in_progress');
      expect(validStatuses).toContain('blocked');
    });

    it('should return valid next statuses for in_progress', () => {
      const validStatuses = getValidNextStatuses('in_progress');
      expect(validStatuses).toContain('completed');
      expect(validStatuses).toContain('blocked');
    });

    it('should return valid next statuses for blocked', () => {
      const validStatuses = getValidNextStatuses('blocked');
      expect(validStatuses).toContain('in_progress');
      expect(validStatuses).toContain('blocked');
    });

    it('should return valid next statuses for completed', () => {
      const validStatuses = getValidNextStatuses('completed');
      expect(validStatuses).toContain('reviewed');
      expect(validStatuses).toContain('blocked');
    });

    it('should always include blocked as valid next status', () => {
      const statuses = ['pending', 'in_progress', 'completed', 'reviewed', 'closed'];
      statuses.forEach((status) => {
        const validStatuses = getValidNextStatuses(status);
        expect(validStatuses).toContain('blocked');
      });
    });
  });

  describe('VALID_TRANSITIONS constant', () => {
    it('should define all valid transitions', () => {
      expect(VALID_TRANSITIONS.pending).toContain('in_progress');
      expect(VALID_TRANSITIONS.pending).toContain('blocked');
      expect(VALID_TRANSITIONS.in_progress).toContain('completed');
      expect(VALID_TRANSITIONS.in_progress).toContain('blocked');
      expect(VALID_TRANSITIONS.blocked).toContain('in_progress');
      expect(VALID_TRANSITIONS.completed).toContain('reviewed');
      expect(VALID_TRANSITIONS.reviewed).toContain('closed');
    });

    it('should have correct structure', () => {
      expect(typeof VALID_TRANSITIONS).toBe('object');
      expect(Array.isArray(VALID_TRANSITIONS.pending)).toBe(true);
      expect(Array.isArray(VALID_TRANSITIONS.in_progress)).toBe(true);
      expect(Array.isArray(VALID_TRANSITIONS.blocked)).toBe(true);
      expect(Array.isArray(VALID_TRANSITIONS.completed)).toBe(true);
      expect(Array.isArray(VALID_TRANSITIONS.reviewed)).toBe(true);
    });
  });
});
