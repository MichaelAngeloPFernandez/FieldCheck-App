const mongoose = require('mongoose');
const Task = require('../../../models/Task');
const User = require('../../../models/User');
const Company = require('../../../models/Company');
const TaskTemplate = require('../../../models/TaskTemplate');
const Service = require('../../../models/Service');
const Ticket = require('../../../models/Ticket');

describe('Task Model - Enhanced with Template System', () => {
  describe('Schema Definition', () => {
    it('should have existing fields', () => {
      const schema = Task.schema;
      
      expect(schema.paths.title).toBeDefined();
      expect(schema.paths.description).toBeDefined();
      expect(schema.paths.dueDate).toBeDefined();
      expect(schema.paths.assignedBy).toBeDefined();
      expect(schema.paths.status).toBeDefined();
      expect(schema.paths.type).toBeDefined();
      expect(schema.paths.difficulty).toBeDefined();
      expect(schema.paths.checklist).toBeDefined();
      expect(schema.paths.blockReason).toBeDefined();
    });

    it('should have new template system fields', () => {
      const schema = Task.schema;
      
      expect(schema.paths.taskOrigin).toBeDefined();
      expect(schema.paths.templateId).toBeDefined();
      expect(schema.paths.ticketId).toBeDefined();
      expect(schema.paths.assignedTo).toBeDefined();
      expect(schema.paths.completedBy).toBeDefined();
      expect(schema.paths.completedAt).toBeDefined();
      expect(schema.paths.taskDuration).toBeDefined();
      expect(schema.paths.notes).toBeDefined();
      expect(schema.paths.statusHistory).toBeDefined();
      expect(schema.paths.companyId).toBeDefined();
    });

    it('should have taskOrigin enum with correct values', () => {
      const taskOriginPath = Task.schema.paths.taskOrigin;
      expect(taskOriginPath.enumValues).toContain('template');
      expect(taskOriginPath.enumValues).toContain('ad_hoc');
      expect(taskOriginPath.defaultValue).toBe('ad_hoc');
    });

    it('should have status enum with correct values', () => {
      const statusPath = Task.schema.paths.status;
      expect(statusPath.enumValues).toContain('pending');
      expect(statusPath.enumValues).toContain('in_progress');
      expect(statusPath.enumValues).toContain('completed');
      expect(statusPath.enumValues).toContain('blocked');
      expect(statusPath.enumValues).toContain('reviewed');
      expect(statusPath.enumValues).toContain('closed');
    });

    it('should have timestamps enabled', () => {
      const schema = Task.schema;
      expect(schema.paths.createdAt).toBeDefined();
      expect(schema.paths.updatedAt).toBeDefined();
    });
  });

  describe('Indexes', () => {
    it('should have ticketId and taskOrigin index', () => {
      const indexes = Task.schema._indexes;
      const hasIndex = indexes.some(
        (index) => index[0].ticketId === 1 && index[0].taskOrigin === 1
      );
      expect(hasIndex).toBe(true);
    });

    it('should have assignedTo and status index', () => {
      const indexes = Task.schema._indexes;
      const hasIndex = indexes.some(
        (index) => index[0].assignedTo === 1 && index[0].status === 1
      );
      expect(hasIndex).toBe(true);
    });

    it('should have companyId and createdAt index', () => {
      const indexes = Task.schema._indexes;
      const hasIndex = indexes.some(
        (index) => index[0].companyId === 1 && index[0].createdAt === 1
      );
      expect(hasIndex).toBe(true);
    });
  });

  describe('Model Export', () => {
    it('should export Task model', () => {
      expect(Task).toBeDefined();
      expect(Task.modelName).toBe('Task');
    });
  });

  describe('Backward Compatibility', () => {
    it('should have default values for new fields', () => {
      const schema = Task.schema;
      
      expect(Task.schema.paths.taskOrigin.defaultValue).toBe('ad_hoc');
      expect(Task.schema.paths.templateId.defaultValue).toBeNull();
      expect(Task.schema.paths.ticketId.defaultValue).toBeNull();
      expect(Task.schema.paths.assignedTo.defaultValue).toBeNull();
      expect(Task.schema.paths.completedBy.defaultValue).toBeNull();
      expect(Task.schema.paths.completedAt.defaultValue).toBeNull();
      expect(Task.schema.paths.taskDuration.defaultValue).toBeNull();
      expect(Task.schema.paths.notes.defaultValue).toBe('');
    });
  });
});
