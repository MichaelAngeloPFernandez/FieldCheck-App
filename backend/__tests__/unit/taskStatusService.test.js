const mongoose = require('mongoose');
const {
  isValidTransition,
  updateTaskStatus,
  getTaskStatusHistory,
  getValidNextStatuses,
  VALID_TRANSITIONS,
} = require('../../services/taskStatusService');
const Task = require('../../models/Task');
const Company = require('../../models/Company');
const User = require('../../models/User');

describe('Task Status Service', () => {
  let companyId, userId, taskId;
  let company, user, task;

  beforeAll(async () => {
    if (mongoose.connection.readyState === 0) {
      await mongoose.connect(process.env.MONGODB_TEST_URI || 'mongodb://localhost:27017/fieldcheck-test');
    }
  });

  afterAll(async () => {
    await mongoose.connection.close();
  });

  beforeEach(async () => {
    await Task.deleteMany({});
    await Company.deleteMany({});
    await User.deleteMany({});

    company = await Company.create({
      name: 'Test Company',
      email: 'test@company.com',
    });
    companyId = company._id;

    user = await User.create({
      name: 'Test User',
      email: 'user@test.com',
      password: 'password123',
      role: 'admin',
      companyId,
    });
    userId = user._id;

    task = await Task.create({
      title: 'Test Task',
      description: 'A test task',
      companyId,
      assignedBy: userId,
      status: 'pending',
    });
    taskId = task._id;
  });

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
  });

  describe('updateTaskStatus', () => {
    it('should update task status successfully', async () => {
      const updatedTask = await updateTaskStatus(taskId, 'in_progress', userId);

      expect(updatedTask.status).toBe('in_progress');
      expect(updatedTask.statusHistory).toHaveLength(2); // pending + in_progress
    });

    it('should record status change in history', async () => {
      await updateTaskStatus(taskId, 'in_progress', userId, 'Started working');

      const updatedTask = await Task.findById(taskId);
      const lastHistory = updatedTask.statusHistory[updatedTask.statusHistory.length - 1];

      expect(lastHistory.status).toBe('in_progress');
      expect(lastHistory.changedBy.toString()).toBe(userId.toString());
      expect(lastHistory.reason).toBe('Started working');
      expect(lastHistory.changedAt).toBeDefined();
    });

    it('should record completedAt and completedBy when marked completed', async () => {
      // First move to in_progress
      await updateTaskStatus(taskId, 'in_progress', userId);

      // Then mark as completed
      const completedTask = await updateTaskStatus(taskId, 'completed', userId);

      expect(completedTask.completedAt).toBeDefined();
      expect(completedTask.completedBy.toString()).toBe(userId.toString());
      expect(completedTask.status).toBe('completed');
    });

    it('should calculate task duration when completed', async () => {
      // Create task with known createdAt
      const createdTime = new Date('2024-01-01T10:00:00Z');
      const testTask = await Task.create({
        title: 'Duration Test',
        description: 'Test',
        companyId,
        assignedBy: userId,
        status: 'pending',
        createdAt: createdTime,
      });

      // Move to in_progress
      await updateTaskStatus(testTask._id, 'in_progress', userId);

      // Mock current time for completion
      const completedTime = new Date('2024-01-01T12:00:00Z');
      jest.useFakeTimers();
      jest.setSystemTime(completedTime);

      const completedTask = await updateTaskStatus(testTask._id, 'completed', userId);

      jest.useRealTimers();

      // Duration should be 2 hours = 7200000 ms
      expect(completedTask.taskDuration).toBeDefined();
      expect(completedTask.taskDuration).toBeGreaterThan(0);
    });

    it('should require reason when blocking task', async () => {
      await expect(updateTaskStatus(taskId, 'blocked', userId)).rejects.toThrow(
        'Block reason is required when blocking a task'
      );
    });

    it('should record block reason', async () => {
      const blockReason = 'Waiting for customer feedback';
      const blockedTask = await updateTaskStatus(taskId, 'blocked', userId, blockReason);

      expect(blockedTask.blockReason).toBe(blockReason);
      expect(blockedTask.status).toBe('blocked');
    });

    it('should throw error for invalid transition', async () => {
      await updateTaskStatus(taskId, 'in_progress', userId);

      await expect(updateTaskStatus(taskId, 'pending', userId)).rejects.toThrow(
        'Invalid status transition'
      );
    });

    it('should throw error if task not found', async () => {
      const invalidTaskId = new mongoose.Types.ObjectId();

      await expect(updateTaskStatus(invalidTaskId, 'in_progress', userId)).rejects.toThrow(
        'Task not found'
      );
    });

    it('should allow transition from any status to blocked', async () => {
      // pending -> blocked
      const blockedTask1 = await updateTaskStatus(taskId, 'blocked', userId, 'Blocked from pending');
      expect(blockedTask1.status).toBe('blocked');

      // blocked -> in_progress
      const inProgressTask = await updateTaskStatus(taskId, 'in_progress', userId);
      expect(inProgressTask.status).toBe('in_progress');

      // in_progress -> blocked
      const blockedTask2 = await updateTaskStatus(taskId, 'blocked', userId, 'Blocked from in_progress');
      expect(blockedTask2.status).toBe('blocked');
    });

    it('should handle multiple status transitions', async () => {
      // pending -> in_progress
      await updateTaskStatus(taskId, 'in_progress', userId);

      // in_progress -> completed
      await updateTaskStatus(taskId, 'completed', userId);

      // completed -> reviewed
      await updateTaskStatus(taskId, 'reviewed', userId);

      // reviewed -> closed
      const closedTask = await updateTaskStatus(taskId, 'closed', userId);

      expect(closedTask.status).toBe('closed');
      expect(closedTask.statusHistory).toHaveLength(5); // pending + in_progress + completed + reviewed + closed
    });
  });

  describe('getTaskStatusHistory', () => {
    it('should return status history for task', async () => {
      await updateTaskStatus(taskId, 'in_progress', userId, 'Started');
      await updateTaskStatus(taskId, 'completed', userId);

      const history = await getTaskStatusHistory(taskId);

      expect(history).toHaveLength(3); // pending + in_progress + completed
      expect(history[0].status).toBe('pending');
      expect(history[1].status).toBe('in_progress');
      expect(history[2].status).toBe('completed');
    });

    it('should populate changedBy user information', async () => {
      await updateTaskStatus(taskId, 'in_progress', userId);

      const history = await getTaskStatusHistory(taskId);
      const lastEntry = history[history.length - 1];

      expect(lastEntry.changedBy).toBeDefined();
      expect(lastEntry.changedBy.name).toBe('Test User');
      expect(lastEntry.changedBy.email).toBe('user@test.com');
    });

    it('should throw error if task not found', async () => {
      const invalidTaskId = new mongoose.Types.ObjectId();

      await expect(getTaskStatusHistory(invalidTaskId)).rejects.toThrow('Task not found');
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
  });
});
