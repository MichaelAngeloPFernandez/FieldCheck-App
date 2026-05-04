const mongoose = require('mongoose');
const {
  notifyTaskAssignment,
  notifyTaskCompletion,
  notifyTaskStatusChange,
} = require('../../services/notificationService');
const Task = require('../../models/Task');
const Ticket = require('../../models/Ticket');
const TaskTemplate = require('../../models/TaskTemplate');
const Service = require('../../models/Service');
const Company = require('../../models/Company');
const User = require('../../models/User');

describe('Notification Service - Task Notifications', () => {
  let companyId, serviceId, ticketId, userId, employeeId;
  let company, service, ticket, user, employee;

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
    await Ticket.deleteMany({});
    await Service.deleteMany({});
    await Company.deleteMany({});
    await User.deleteMany({});

    company = await Company.create({
      name: 'Test Company',
      email: 'test@company.com',
    });
    companyId = company._id;

    user = await User.create({
      name: 'Admin User',
      email: 'admin@test.com',
      password: 'password123',
      role: 'admin',
      companyId,
    });
    userId = user._id;

    employee = await User.create({
      name: 'Employee User',
      email: 'employee@test.com',
      password: 'password123',
      role: 'employee',
      companyId,
    });
    employeeId = employee._id;

    service = await Service.create({
      companyId,
      name: 'Test Service',
      description: 'A test service',
      isActive: true,
    });
    serviceId = service._id;

    ticket = await Ticket.create({
      companyId,
      serviceId,
      title: 'Test Ticket',
      description: 'A test ticket',
      status: 'open',
    });
    ticketId = ticket._id;
  });

  describe('notifyTaskAssignment', () => {
    it('should send task assignment notification', async () => {
      const task = await Task.create({
        title: 'Assignment Test Task',
        description: 'Test task for assignment',
        companyId,
        assignedBy: userId,
        ticketId,
        taskOrigin: 'template',
        status: 'pending',
      });

      // Mock socket.io
      global.io = {
        to: jest.fn().mockReturnThis(),
        emit: jest.fn(),
      };

      await notifyTaskAssignment(task._id, employeeId, userId);

      expect(global.io.to).toHaveBeenCalledWith(`user_${employeeId}`);
      expect(global.io.emit).toHaveBeenCalledWith(
        'taskAssigned',
        expect.objectContaining({
          type: 'task_assigned',
          taskId: task._id,
          taskOrigin: 'template',
        })
      );

      delete global.io;
    });

    it('should include task details in notification', async () => {
      const task = await Task.create({
        title: 'Detailed Task',
        description: 'Task with details',
        type: 'inspection',
        difficulty: 'hard',
        companyId,
        assignedBy: userId,
        ticketId,
        taskOrigin: 'ad_hoc',
        status: 'pending',
      });

      global.io = {
        to: jest.fn().mockReturnThis(),
        emit: jest.fn(),
      };

      await notifyTaskAssignment(task._id, employeeId, userId);

      const emitCall = global.io.emit.mock.calls[0];
      const notificationData = emitCall[1];

      expect(notificationData.title).toContain('Ad-hoc Task');
      expect(notificationData.message).toContain('Detailed Task');
      expect(notificationData.type).toBe('inspection');
      expect(notificationData.difficulty).toBe('hard');

      delete global.io;
    });

    it('should handle missing task gracefully', async () => {
      const invalidTaskId = new mongoose.Types.ObjectId();

      global.io = {
        to: jest.fn().mockReturnThis(),
        emit: jest.fn(),
      };

      // Should not throw
      await notifyTaskAssignment(invalidTaskId, employeeId, userId);

      expect(global.io.emit).not.toHaveBeenCalled();

      delete global.io;
    });

    it('should handle missing socket.io gracefully', async () => {
      const task = await Task.create({
        title: 'Task',
        description: 'Test',
        companyId,
        assignedBy: userId,
        ticketId,
        status: 'pending',
      });

      global.io = undefined;

      // Should not throw
      await notifyTaskAssignment(task._id, employeeId, userId);
    });
  });

  describe('notifyTaskCompletion', () => {
    it('should send task completion notification', async () => {
      const task = await Task.create({
        title: 'Completion Test Task',
        description: 'Test task for completion',
        companyId,
        assignedBy: userId,
        ticketId,
        status: 'completed',
        completedAt: new Date(),
        completedBy: employeeId,
      });

      global.io = {
        to: jest.fn().mockReturnThis(),
        emit: jest.fn(),
      };

      await notifyTaskCompletion(task._id, employeeId);

      expect(global.io.to).toHaveBeenCalledWith(`user_${userId}`);
      expect(global.io.emit).toHaveBeenCalledWith(
        'taskCompleted',
        expect.objectContaining({
          type: 'task_completed',
          taskId: task._id,
        })
      );

      delete global.io;
    });

    it('should include completion details in notification', async () => {
      const completedTime = new Date();
      const task = await Task.create({
        title: 'Completed Task',
        description: 'Test',
        companyId,
        assignedBy: userId,
        ticketId,
        status: 'completed',
        completedAt: completedTime,
        completedBy: employeeId,
        taskDuration: 3600000, // 1 hour
      });

      global.io = {
        to: jest.fn().mockReturnThis(),
        emit: jest.fn(),
      };

      await notifyTaskCompletion(task._id, employeeId);

      const emitCall = global.io.emit.mock.calls[0];
      const notificationData = emitCall[1];

      expect(notificationData.completedAt).toBeDefined();
      expect(notificationData.taskDuration).toBe(3600000);

      delete global.io;
    });

    it('should handle missing task gracefully', async () => {
      const invalidTaskId = new mongoose.Types.ObjectId();

      global.io = {
        to: jest.fn().mockReturnThis(),
        emit: jest.fn(),
      };

      await notifyTaskCompletion(invalidTaskId, employeeId);

      expect(global.io.emit).not.toHaveBeenCalled();

      delete global.io;
    });
  });

  describe('notifyTaskStatusChange', () => {
    it('should send task status change notification', async () => {
      const task = await Task.create({
        title: 'Status Change Task',
        description: 'Test',
        companyId,
        assignedBy: userId,
        assignedTo: employeeId,
        ticketId,
        status: 'in_progress',
      });

      global.io = {
        to: jest.fn().mockReturnThis(),
        emit: jest.fn(),
      };

      await notifyTaskStatusChange(task._id, 'pending', 'in_progress', userId, 'Started work');

      expect(global.io.to).toHaveBeenCalledWith(`user_${employeeId}`);
      expect(global.io.emit).toHaveBeenCalledWith(
        'taskStatusChanged',
        expect.objectContaining({
          type: 'task_status_changed',
          oldStatus: 'pending',
          newStatus: 'in_progress',
          reason: 'Started work',
        })
      );

      delete global.io;
    });

    it('should notify both assigned employee and assigner', async () => {
      const task = await Task.create({
        title: 'Status Change Task',
        description: 'Test',
        companyId,
        assignedBy: userId,
        assignedTo: employeeId,
        ticketId,
        status: 'completed',
      });

      global.io = {
        to: jest.fn().mockReturnThis(),
        emit: jest.fn(),
      };

      await notifyTaskStatusChange(task._id, 'in_progress', 'completed', employeeId);

      // Should be called twice - once for assigned employee, once for assigner
      expect(global.io.to).toHaveBeenCalledWith(`user_${employeeId}`);
      expect(global.io.to).toHaveBeenCalledWith(`user_${userId}`);

      delete global.io;
    });

    it('should not notify assigner twice if they changed status', async () => {
      const task = await Task.create({
        title: 'Status Change Task',
        description: 'Test',
        companyId,
        assignedBy: userId,
        assignedTo: employeeId,
        ticketId,
        status: 'completed',
      });

      global.io = {
        to: jest.fn().mockReturnThis(),
        emit: jest.fn(),
      };

      // User who assigned the task is changing the status
      await notifyTaskStatusChange(task._id, 'in_progress', 'completed', userId);

      // Should only notify the assigned employee
      expect(global.io.to).toHaveBeenCalledTimes(1);
      expect(global.io.to).toHaveBeenCalledWith(`user_${employeeId}`);

      delete global.io;
    });

    it('should include status change details', async () => {
      const task = await Task.create({
        title: 'Status Change Task',
        description: 'Test',
        companyId,
        assignedBy: userId,
        assignedTo: employeeId,
        ticketId,
        status: 'blocked',
      });

      global.io = {
        to: jest.fn().mockReturnThis(),
        emit: jest.fn(),
      };

      const blockReason = 'Waiting for approval';
      await notifyTaskStatusChange(task._id, 'in_progress', 'blocked', userId, blockReason);

      const emitCall = global.io.emit.mock.calls[0];
      const notificationData = emitCall[1];

      expect(notificationData.oldStatus).toBe('in_progress');
      expect(notificationData.newStatus).toBe('blocked');
      expect(notificationData.reason).toBe(blockReason);
      expect(notificationData.changedBy).toBe('Admin User');

      delete global.io;
    });

    it('should handle missing task gracefully', async () => {
      const invalidTaskId = new mongoose.Types.ObjectId();

      global.io = {
        to: jest.fn().mockReturnThis(),
        emit: jest.fn(),
      };

      await notifyTaskStatusChange(invalidTaskId, 'pending', 'in_progress', userId);

      expect(global.io.emit).not.toHaveBeenCalled();

      delete global.io;
    });

    it('should handle missing socket.io gracefully', async () => {
      const task = await Task.create({
        title: 'Status Change Task',
        description: 'Test',
        companyId,
        assignedBy: userId,
        assignedTo: employeeId,
        ticketId,
        status: 'in_progress',
      });

      global.io = undefined;

      // Should not throw
      await notifyTaskStatusChange(task._id, 'pending', 'in_progress', userId);
    });
  });
});
