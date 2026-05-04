const mongoose = require('mongoose');
const Ticket = require('../../../models/Ticket');
const Company = require('../../../models/Company');
const Service = require('../../../models/Service');

describe('Ticket Model', () => {
  describe('Schema Definition', () => {
    it('should have correct schema fields', () => {
      const schema = Ticket.schema;
      
      expect(schema.paths.companyId).toBeDefined();
      expect(schema.paths.serviceId).toBeDefined();
      expect(schema.paths.title).toBeDefined();
      expect(schema.paths.description).toBeDefined();
      expect(schema.paths.status).toBeDefined();
    });

    it('should have companyId as required ObjectId', () => {
      const companyIdPath = Ticket.schema.paths.companyId;
      expect(companyIdPath.instance).toBe('ObjectId');
      expect(companyIdPath.isRequired).toBe(true);
    });

    it('should have serviceId as optional ObjectId', () => {
      const serviceIdPath = Ticket.schema.paths.serviceId;
      expect(serviceIdPath.instance).toBe('ObjectId');
      // serviceId is optional, so it won't have a default value set to null explicitly
    });

    it('should have title as required String', () => {
      const titlePath = Ticket.schema.paths.title;
      expect(titlePath.instance).toBe('String');
      expect(titlePath.isRequired).toBe(true);
    });

    it('should have status enum with correct values', () => {
      const statusPath = Ticket.schema.paths.status;
      expect(statusPath.enumValues).toContain('open');
      expect(statusPath.enumValues).toContain('in_progress');
      expect(statusPath.enumValues).toContain('completed');
      expect(statusPath.enumValues).toContain('closed');
      expect(statusPath.defaultValue).toBe('open');
    });

    it('should have timestamps enabled', () => {
      const schema = Ticket.schema;
      expect(schema.paths.createdAt).toBeDefined();
      expect(schema.paths.updatedAt).toBeDefined();
    });
  });

  describe('Indexes', () => {
    it('should have companyId and status index', () => {
      const indexes = Ticket.schema._indexes;
      const hasIndex = indexes.some(
        (index) => index[0].companyId === 1 && index[0].status === 1
      );
      expect(hasIndex).toBe(true);
    });

    it('should have serviceId index', () => {
      const indexes = Ticket.schema._indexes;
      const hasIndex = indexes.some((index) => index[0].serviceId === 1);
      expect(hasIndex).toBe(true);
    });
  });

  describe('Model Export', () => {
    it('should export Ticket model', () => {
      expect(Ticket).toBeDefined();
      expect(Ticket.modelName).toBe('Ticket');
    });
  });

  describe('Default Values', () => {
    it('should have correct default values', () => {
      const schema = Ticket.schema;
      
      expect(Ticket.schema.paths.description.defaultValue).toBe('');
      expect(Ticket.schema.paths.status.defaultValue).toBe('open');
      expect(Ticket.schema.paths.serviceId.defaultValue).toBeNull();
    });
  });
});
