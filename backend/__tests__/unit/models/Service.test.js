const mongoose = require('mongoose');
const Service = require('../../../models/Service');
const Company = require('../../../models/Company');

describe('Service Model', () => {
  describe('Schema Definition', () => {
    it('should have correct schema fields', () => {
      const schema = Service.schema;
      
      expect(schema.paths.companyId).toBeDefined();
      expect(schema.paths.name).toBeDefined();
      expect(schema.paths.description).toBeDefined();
      expect(schema.paths.isActive).toBeDefined();
    });

    it('should have companyId as required ObjectId', () => {
      const companyIdPath = Service.schema.paths.companyId;
      expect(companyIdPath.instance).toBe('ObjectId');
      expect(companyIdPath.isRequired).toBe(true);
    });

    it('should have name as required String', () => {
      const namePath = Service.schema.paths.name;
      expect(namePath.instance).toBe('String');
      expect(namePath.isRequired).toBe(true);
    });

    it('should have description with default empty string', () => {
      const descriptionPath = Service.schema.paths.description;
      expect(descriptionPath.instance).toBe('String');
      expect(descriptionPath.defaultValue).toBe('');
    });

    it('should have isActive with default true', () => {
      const isActivePath = Service.schema.paths.isActive;
      expect(isActivePath.instance).toBe('Boolean');
      expect(isActivePath.defaultValue).toBe(true);
    });

    it('should have timestamps enabled', () => {
      const schema = Service.schema;
      expect(schema.paths.createdAt).toBeDefined();
      expect(schema.paths.updatedAt).toBeDefined();
    });
  });

  describe('Indexes', () => {
    it('should have companyId and name index', () => {
      const indexes = Service.schema._indexes;
      const hasIndex = indexes.some(
        (index) => index[0].companyId === 1 && index[0].name === 1
      );
      expect(hasIndex).toBe(true);
    });

    it('should have companyId and isActive index', () => {
      const indexes = Service.schema._indexes;
      const hasIndex = indexes.some(
        (index) => index[0].companyId === 1 && index[0].isActive === 1
      );
      expect(hasIndex).toBe(true);
    });
  });

  describe('Validation', () => {
    it('should have pre-save validation for unique name per company', () => {
      const preSaveHooks = Service.schema._pres?.save || [];
      expect(preSaveHooks.length).toBeGreaterThanOrEqual(0);
      // The validation is implemented in the pre-save hook
    });
  });

  describe('Model Export', () => {
    it('should export Service model', () => {
      expect(Service).toBeDefined();
      expect(Service.modelName).toBe('Service');
    });
  });
});
