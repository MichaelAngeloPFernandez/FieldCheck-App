const mongoose = require('mongoose');
const { cloneTemplateTasksForTicket } = require('../../services/taskCloningService');
const Task = require('../../models/Task');
const TaskTemplate = require('../../models/TaskTemplate');
const Service = require('../../models/Service');
const Ticket = require('../../models/Ticket');
const Company = require('../../models/Company');
const User = require('../../models/User');

describe('Task Cloning Service', () => {
  let companyId, serviceId, ticketId, userId;
  let company, service, ticket, user;

  beforeAll(async () => {
    // Connect to test database
    if (mongoose.connection.readyState === 0) {
      await mongoose.connect(process.env.MONGODB_TEST_URI || 'mongodb://localhost:27017/fieldcheck-test');
    }
  });

  afterAll(async () => {
    await mongoose.connection.close();
  });

  beforeEach(async () => {
    // Clear collections
    await Task.deleteMany({});
    await TaskTemplate.deleteMany({});
    await Service.deleteMany({});
    await Ticket.deleteMany({});
    await Company.deleteMany({});
    await User.deleteMany({});

    // Create test data
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

  describe('cloneTemplateTasksForTicket', () => {
    it('should clone all active templates for a service', async () => {
      // Create templates
      const template1 = await TaskTemplate.create({
        serviceId,
        companyId,
        title: 'Template 1',
        description: 'First template',
        type: 'inspection',
        difficulty: 'easy',
        checklist: [
          { label: 'Check item 1', isCompleted: false },
          { label: 'Check item 2', isCompleted: false },
        ],
        isActive: true,
      });

      const template2 = await TaskTemplate.create({
        serviceId,
        companyId,
        title: 'Template 2',
        description: 'Second template',
        type: 'maintenance',
        difficulty: 'medium',
        checklist: [{ label: 'Maintenance check', isCompleted: false }],
        isActive: true,
      });

      // Clone templates
      const clonedTasks = await cloneTemplateTasksForTicket(ticketId, serviceId, companyId, userId);

      // Verify cloned tasks
      expect(clonedTasks).toHaveLength(2);
      expect(clonedTasks[0].title).toBe('Template 1');
      expect(clonedTasks[0].description).toBe('First template');
      expect(clonedTasks[0].type).toBe('inspection');
      expect(clonedTasks[0].difficulty).toBe('easy');
      expect(clonedTasks[0].taskOrigin).toBe('template');
      expect(clonedTasks[0].templateId.toString()).toBe(template1._id.toString());
      expect(clonedTasks[0].ticketId.toString()).toBe(ticketId.toString());
      expect(clonedTasks[0].status).toBe('pending');
      expect(clonedTasks[0].checklist).toHaveLength(2);
      expect(clonedTasks[0].checklist[0].isCompleted).toBe(false);

      expect(clonedTasks[1].title).toBe('Template 2');
      expect(clonedTasks[1].type).toBe('maintenance');
      expect(clonedTasks[1].difficulty).toBe('medium');
    });

    it('should return empty array if no active templates exist', async () => {
      const clonedTasks = await cloneTemplateTasksForTicket(ticketId, serviceId, companyId, userId);

      expect(clonedTasks).toHaveLength(0);
    });

    it('should skip inactive templates', async () => {
      // Create active and inactive templates
      await TaskTemplate.create({
        serviceId,
        companyId,
        title: 'Active Template',
        description: 'Active',
        type: 'general',
        difficulty: 'easy',
        checklist: [],
        isActive: true,
      });

      await TaskTemplate.create({
        serviceId,
        companyId,
        title: 'Inactive Template',
        description: 'Inactive',
        type: 'general',
        difficulty: 'easy',
        checklist: [],
        isActive: false,
      });

      const clonedTasks = await cloneTemplateTasksForTicket(ticketId, serviceId, companyId, userId);

      expect(clonedTasks).toHaveLength(1);
      expect(clonedTasks[0].title).toBe('Active Template');
    });

    it('should record status history when cloning', async () => {
      await TaskTemplate.create({
        serviceId,
        companyId,
        title: 'Template',
        description: 'Test',
        type: 'general',
        difficulty: 'easy',
        checklist: [],
        isActive: true,
      });

      const clonedTasks = await cloneTemplateTasksForTicket(ticketId, serviceId, companyId, userId);

      expect(clonedTasks[0].statusHistory).toHaveLength(1);
      expect(clonedTasks[0].statusHistory[0].status).toBe('pending');
      expect(clonedTasks[0].statusHistory[0].changedBy.toString()).toBe(userId.toString());
      expect(clonedTasks[0].statusHistory[0].reason).toBe('Task created from template');
    });

    it('should set assignedBy to the provided userId', async () => {
      await TaskTemplate.create({
        serviceId,
        companyId,
        title: 'Template',
        description: 'Test',
        type: 'general',
        difficulty: 'easy',
        checklist: [],
        isActive: true,
      });

      const clonedTasks = await cloneTemplateTasksForTicket(ticketId, serviceId, companyId, userId);

      expect(clonedTasks[0].assignedBy.toString()).toBe(userId.toString());
    });

    it('should throw error if service not found', async () => {
      const invalidServiceId = new mongoose.Types.ObjectId();

      await expect(
        cloneTemplateTasksForTicket(ticketId, invalidServiceId, companyId, userId)
      ).rejects.toThrow('Service not found');
    });

    it('should throw error if service belongs to different company', async () => {
      const otherCompany = await Company.create({
        name: 'Other Company',
        email: 'other@company.com',
      });

      const otherService = await Service.create({
        companyId: otherCompany._id,
        name: 'Other Service',
        description: 'Other service',
        isActive: true,
      });

      await expect(
        cloneTemplateTasksForTicket(ticketId, otherService._id, companyId, userId)
      ).rejects.toThrow('Service not found');
    });

    it('should continue cloning if one template fails', async () => {
      // Create valid template
      const validTemplate = await TaskTemplate.create({
        serviceId,
        companyId,
        title: 'Valid Template',
        description: 'Valid',
        type: 'general',
        difficulty: 'easy',
        checklist: [],
        isActive: true,
      });

      // Create another valid template
      const validTemplate2 = await TaskTemplate.create({
        serviceId,
        companyId,
        title: 'Valid Template 2',
        description: 'Valid 2',
        type: 'general',
        difficulty: 'easy',
        checklist: [],
        isActive: true,
      });

      // Mock Task.create to fail for first template
      const originalCreate = Task.create;
      let callCount = 0;
      Task.create = jest.fn(async (data) => {
        callCount++;
        if (callCount === 1) {
          throw new Error('Database error');
        }
        return originalCreate.call(Task, data);
      });

      const clonedTasks = await cloneTemplateTasksForTicket(ticketId, serviceId, companyId, userId);

      // Should have cloned the second template despite first failing
      expect(clonedTasks).toHaveLength(1);
      expect(clonedTasks[0].title).toBe('Valid Template 2');

      // Restore original
      Task.create = originalCreate;
    });

    it('should copy checklist items correctly', async () => {
      const template = await TaskTemplate.create({
        serviceId,
        companyId,
        title: 'Template with Checklist',
        description: 'Test',
        type: 'general',
        difficulty: 'easy',
        checklist: [
          { label: 'Item 1', isCompleted: false },
          { label: 'Item 2', isCompleted: false },
          { label: 'Item 3', isCompleted: false },
        ],
        isActive: true,
      });

      const clonedTasks = await cloneTemplateTasksForTicket(ticketId, serviceId, companyId, userId);

      expect(clonedTasks[0].checklist).toHaveLength(3);
      expect(clonedTasks[0].checklist[0].label).toBe('Item 1');
      expect(clonedTasks[0].checklist[0].isCompleted).toBe(false);
      expect(clonedTasks[0].checklist[1].label).toBe('Item 2');
      expect(clonedTasks[0].checklist[2].label).toBe('Item 3');
    });

    it('should set companyId on cloned tasks', async () => {
      await TaskTemplate.create({
        serviceId,
        companyId,
        title: 'Template',
        description: 'Test',
        type: 'general',
        difficulty: 'easy',
        checklist: [],
        isActive: true,
      });

      const clonedTasks = await cloneTemplateTasksForTicket(ticketId, serviceId, companyId, userId);

      expect(clonedTasks[0].companyId.toString()).toBe(companyId.toString());
    });
  });
});
