const mongoose = require('mongoose');
const TaskTemplate = require('../../../models/TaskTemplate');
const Service = require('../../../models/Service');
const Company = require('../../../models/Company');

describe('TaskTemplate Model', () => {
  describe('Schema Definition', () => {
    it('should have correct schema fields', () => {
      const schema = TaskTemplate.schema;
      
      expect(schema.paths.serviceId).toBeDefined();
      expect(schema.paths.companyId).toBeDefined();
      expect(schema.paths.title).toBeDefined();
      expect(schema.paths.description).toBeDefined();
      expect(schema.paths.type).toBeDefined();
      expect(schema.paths.difficulty).toBeDefined();
      expect(schema.paths.checklist).toBeDefined();
      expect(schema.paths.isActive).toBeDefined();
    });

    it('should have serviceId as required ObjectId', () => {
      const serviceIdPath = TaskTemplate.schema.paths.serviceId;
      expect(serviceIdPath.instance).toBe('ObjectId');
      expect(serviceIdPath.isRequired).toBe(true);
    });

    it('should have companyId as required ObjectId', () => {
      const companyIdPath = TaskTemplate.schema.paths.companyId;
      expect(companyIdPath.instance).toBe('ObjectId');
      expect(companyIdPath.isRequired).toBe(true);
    });

    it('should have title as required String', () => {
      const titlePath = TaskTemplate.schema.paths.title;
      expect(titlePath.instance).toBe('String');
      expect(titlePath.isRequired).toBe(true);
    });

    it('should have type enum with correct values', () => {
      const typePath = TaskTemplate.schema.paths.type;
      expect(typePath.enumValues).toContain('general');
      expect(typePath.enumValues).toContain('inspection');
      expect(typePath.enumValues).toContain('maintenance');
      expect(typePath.enumValues).toContain('delivery');
      expect(typePath.enumValues).toContain('other');
      expect(typePath.defaultValue).toBe('general');
    });

    it('should have difficulty enum with correct values', () => {
      const difficultyPath = TaskTemplate.schema.paths.difficulty;
      expect(difficultyPath.enumValues).toContain('easy');
      expect(difficultyPath.enumValues).toContain('medium');
      expect(difficultyPath.enumValues).toContain('hard');
      expect(difficultyPath.defaultValue).toBe('medium');
    });

    it('should have timestamps enabled', () => {
      const schema = TaskTemplate.schema;
      expect(schema.paths.createdAt).toBeDefined();
      expect(schema.paths.updatedAt).toBeDefined();
    });
  });

  describe('Indexes', () => {
    it('should have serviceId index', () => {
      const indexes = TaskTemplate.schema._indexes;
      const hasIndex = indexes.some((index) => index[0].serviceId === 1);
      expect(hasIndex).toBe(true);
    });

    it('should have companyId and isActive index', () => {
      const indexes = TaskTemplate.schema._indexes;
      const hasIndex = indexes.some(
        (index) => index[0].companyId === 1 && index[0].isActive === 1
      );
      expect(hasIndex).toBe(true);
    });
  });

  describe('Model Export', () => {
    it('should export TaskTemplate model', () => {
      expect(TaskTemplate).toBeDefined();
      expect(TaskTemplate.modelName).toBe('TaskTemplate');
    });
  });
});
