/**
 * Property-Based Test — Bug Condition Exploration
 * 
 * Property 1: Bug Condition - Complete Removal of Ticket/Template Functionality
 * 
 * For any file path in the codebase, the fixed application SHALL NOT contain
 * any ticket or template management files, routes, models, or services.
 * 
 * This test verifies that all ticket/template code has been removed from the codebase.
 * 
 * **Validates: Requirements 2.1, 2.2, 2.3, 2.4, 2.5, 2.6**
 * 
 * Framework: Jest + fast-check
 */

const fs = require('fs');
const path = require('path');

describe('Bug Condition Exploration - Ticket/Template Removal', () => {
  const projectRoot = path.join(__dirname, '../../../..');
  const backendRoot = path.join(projectRoot, 'backend');
  const fieldCheckRoot = path.join(projectRoot, 'field_check');

  /**
   * Helper function to check if a file exists
   */
  const fileExists = (filePath) => {
    try {
      return fs.existsSync(filePath);
    } catch (err) {
      return false;
    }
  };

  /**
   * Helper function to search for files matching a pattern
   */
  const findFilesMatching = (dir, pattern) => {
    const results = [];
    if (!fs.existsSync(dir)) return results;

    const files = fs.readdirSync(dir, { withFileTypes: true });
    for (const file of files) {
      const fullPath = path.join(dir, file.name);
      if (file.isDirectory()) {
        results.push(...findFilesMatching(fullPath, pattern));
      } else if (pattern.test(file.name)) {
        results.push(fullPath);
      }
    }
    return results;
  };

  /**
   * Helper function to search for text in files
   */
  const searchInFiles = (dir, searchText, filePattern = /\.js$|\.dart$/) => {
    const results = [];
    if (!fs.existsSync(dir)) return results;

    const files = fs.readdirSync(dir, { withFileTypes: true });
    for (const file of files) {
      // Skip node_modules and other directories
      if (file.isDirectory() && ['node_modules', '.git', 'build', 'dist', '.firebase'].includes(file.name)) {
        continue;
      }

      const fullPath = path.join(dir, file.name);
      if (file.isDirectory()) {
        results.push(...searchInFiles(fullPath, searchText, filePattern));
      } else if (filePattern.test(file.name)) {
        try {
          const content = fs.readFileSync(fullPath, 'utf8');
          if (content.includes(searchText)) {
            results.push({ file: fullPath, match: searchText });
          }
        } catch (err) {
          // Skip files that can't be read
        }
      }
    }
    return results;
  };

  describe('Frontend Screen Files Removal', () => {
    it('should not have admin_template_management_screen.dart', () => {
      const filePath = path.join(fieldCheckRoot, 'lib/screens/admin_template_management_screen.dart');
      expect(fileExists(filePath)).toBe(false);
    });

    it('should not have admin_ticket_list_screen.dart', () => {
      const filePath = path.join(fieldCheckRoot, 'lib/screens/admin_ticket_list_screen.dart');
      expect(fileExists(filePath)).toBe(false);
    });

    it('should not have admin_ticket_detail_screen.dart', () => {
      const filePath = path.join(fieldCheckRoot, 'lib/screens/admin_ticket_detail_screen.dart');
      expect(fileExists(filePath)).toBe(false);
    });

    it('should not have enhanced_ticket_creation_screen.dart', () => {
      const filePath = path.join(fieldCheckRoot, 'lib/screens/enhanced_ticket_creation_screen.dart');
      expect(fileExists(filePath)).toBe(false);
    });

    it('should not have ticket_creation_screen.dart', () => {
      const filePath = path.join(fieldCheckRoot, 'lib/screens/ticket_creation_screen.dart');
      expect(fileExists(filePath)).toBe(false);
    });

    it('should not have ticket_dashboard_screen.dart', () => {
      const filePath = path.join(fieldCheckRoot, 'lib/screens/ticket_dashboard_screen.dart');
      expect(fileExists(filePath)).toBe(false);
    });

    it('should not have employee_ticket_create_screen.dart', () => {
      const filePath = path.join(fieldCheckRoot, 'lib/screens/employee_ticket_create_screen.dart');
      expect(fileExists(filePath)).toBe(false);
    });

    it('should not have employee_ticket_list_screen.dart', () => {
      const filePath = path.join(fieldCheckRoot, 'lib/screens/employee_ticket_list_screen.dart');
      expect(fileExists(filePath)).toBe(false);
    });
  });

  describe('Backend Route Files Removal', () => {
    it('should not have ticketRoutes.js', () => {
      const filePath = path.join(backendRoot, 'routes/ticketRoutes.js');
      expect(fileExists(filePath)).toBe(false);
    });

    it('should not have templateRoutes.js', () => {
      const filePath = path.join(backendRoot, 'routes/templateRoutes.js');
      expect(fileExists(filePath)).toBe(false);
    });
  });

  describe('Backend Model Files Removal', () => {
    it('should not have Ticket.js model', () => {
      const filePath = path.join(backendRoot, 'models/Ticket.js');
      expect(fileExists(filePath)).toBe(false);
    });

    it('should not have TicketTemplate.js model', () => {
      const filePath = path.join(backendRoot, 'models/TicketTemplate.js');
      expect(fileExists(filePath)).toBe(false);
    });
  });

  describe('Backend Service Files Removal', () => {
    it('should not have ticketService.js', () => {
      const filePath = path.join(backendRoot, 'services/ticketService.js');
      expect(fileExists(filePath)).toBe(false);
    });
  });

  describe('Backend Seed Data Files Removal', () => {
    it('should not have ticketTemplates.json', () => {
      const filePath = path.join(backendRoot, 'seeds/ticketTemplates.json');
      expect(fileExists(filePath)).toBe(false);
    });

    it('should not have seedAirconTemplate.js', () => {
      const filePath = path.join(backendRoot, 'seeds/seedAirconTemplate.js');
      expect(fileExists(filePath)).toBe(false);
    });

    it('should not have seedElectricalTemplate.js', () => {
      const filePath = path.join(backendRoot, 'seeds/seedElectricalTemplate.js');
      expect(fileExists(filePath)).toBe(false);
    });

    it('should not have seedPlumbingTemplate.js', () => {
      const filePath = path.join(backendRoot, 'seeds/seedPlumbingTemplate.js');
      expect(fileExists(filePath)).toBe(false);
    });
  });

  describe('Backend Route Registrations Removal', () => {
    it('should not have /api/tickets route registration in server.js', () => {
      const serverPath = path.join(backendRoot, 'server.js');
      const content = fs.readFileSync(serverPath, 'utf8');
      expect(content).not.toMatch(/app\.use\(['"]\/api\/tickets/);
      expect(content).not.toMatch(/ticketRoutes/);
    });

    it('should not have /api/templates route registration in server.js', () => {
      const serverPath = path.join(backendRoot, 'server.js');
      const content = fs.readFileSync(serverPath, 'utf8');
      expect(content).not.toMatch(/app\.use\(['"]\/api\/templates/);
      expect(content).not.toMatch(/templateRoutes/);
    });
  });

  describe('Frontend Import Cleanup', () => {
    it('should not have imports of removed ticket/template screens in dart files', () => {
      const dartFiles = findFilesMatching(fieldCheckRoot, /\.dart$/);
      const ticketImports = [];

      for (const file of dartFiles) {
        try {
          const content = fs.readFileSync(file, 'utf8');
          if (content.includes('admin_template_management_screen') ||
              content.includes('admin_ticket_list_screen') ||
              content.includes('admin_ticket_detail_screen') ||
              content.includes('enhanced_ticket_creation_screen') ||
              content.includes('ticket_creation_screen') ||
              content.includes('ticket_dashboard_screen') ||
              content.includes('employee_ticket_create_screen') ||
              content.includes('employee_ticket_list_screen')) {
            ticketImports.push(file);
          }
        } catch (err) {
          // Skip files that can't be read
        }
      }

      expect(ticketImports).toEqual([]);
    });
  });

  describe('Backend Import Cleanup', () => {
    it('should not have imports of removed ticket/template models or services', () => {
      const jsFiles = findFilesMatching(backendRoot, /\.js$/);
      const ticketImports = [];

      for (const file of jsFiles) {
        // Skip node_modules and test files
        if (file.includes('node_modules') || file.includes('__tests__')) continue;

        try {
          const content = fs.readFileSync(file, 'utf8');
          if (content.includes("require('./Ticket'") ||
              content.includes("require('./TicketTemplate'") ||
              content.includes("require('../models/Ticket'") ||
              content.includes("require('../models/TicketTemplate'") ||
              content.includes("require('../services/ticketService'") ||
              content.includes("require('./ticketService'")) {
            ticketImports.push(file);
          }
        } catch (err) {
          // Skip files that can't be read
        }
      }

      expect(ticketImports).toEqual([]);
    });
  });

  describe('Database References Cleanup', () => {
    it('should not have references to Ticket model in other models', () => {
      const modelsDir = path.join(backendRoot, 'models');
      const modelFiles = findFilesMatching(modelsDir, /\.js$/);
      const ticketReferences = [];

      for (const file of modelFiles) {
        try {
          const content = fs.readFileSync(file, 'utf8');
          // Look for references to Ticket model (excluding comments)
          if (content.match(/(?<!\/\/).*require.*Ticket|(?<!\/\/).*mongoose\.model.*Ticket/)) {
            ticketReferences.push(file);
          }
        } catch (err) {
          // Skip files that can't be read
        }
      }

      expect(ticketReferences).toEqual([]);
    });
  });
});
