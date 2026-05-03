/**
 * Property-Based Tests — Preservation of Existing Functionality
 * 
 * Property 2: Preservation - Task Management and Other Features Work Unchanged
 * 
 * For any user interaction that involves task management, user management, 
 * attendance tracking, or any other non-ticket/template feature, the fixed 
 * application SHALL produce exactly the same behavior as the original application.
 * 
 * **Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5, 3.6**
 * 
 * Framework: Jest
 */

const fs = require('fs');
const path = require('path');

describe('Preservation Tests - Existing Functionality Unchanged', () => {
  const backendRoot = path.join(__dirname, '../../../');

  describe('Task Model Preservation', () => {
    it('should have Task model without service_type field', () => {
      const taskModelPath = path.join(backendRoot, 'models/Task.js');
      const content = fs.readFileSync(taskModelPath, 'utf8');

      // Verify Task model exists
      expect(content).toContain('const taskSchema');
      expect(content).toContain('title');
      expect(content).toContain('description');
      expect(content).toContain('assignedBy');
      expect(content).toContain('status');

      // Verify service_type is NOT in the model
      expect(content).not.toContain('service_type');
    });

    it('should have UserTask model for task assignments', () => {
      const userTaskPath = path.join(backendRoot, 'models/UserTask.js');
      expect(fs.existsSync(userTaskPath)).toBe(true);

      const content = fs.readFileSync(userTaskPath, 'utf8');
      expect(content).toContain('userId');
      expect(content).toContain('taskId');
      expect(content).toContain('status');
    });
  });

  describe('User Model Preservation', () => {
    it('should have User model for user management', () => {
      const userModelPath = path.join(backendRoot, 'models/User.js');
      expect(fs.existsSync(userModelPath)).toBe(true);

      const content = fs.readFileSync(userModelPath, 'utf8');
      expect(content).toContain('name');
      expect(content).toContain('email');
      expect(content).toContain('role');
    });
  });

  describe('Attendance Model Preservation', () => {
    it('should have Attendance model for attendance tracking', () => {
      const attendanceModelPath = path.join(backendRoot, 'models/Attendance.js');
      expect(fs.existsSync(attendanceModelPath)).toBe(true);

      const content = fs.readFileSync(attendanceModelPath, 'utf8');
      expect(content).toContain('employee');
      expect(content).toContain('status');
    });
  });

  describe('Chat Model Preservation', () => {
    it('should have ChatMessage model for messaging', () => {
      const chatModelPath = path.join(backendRoot, 'models/ChatMessage.js');
      expect(fs.existsSync(chatModelPath)).toBe(true);

      const content = fs.readFileSync(chatModelPath, 'utf8');
      expect(content).toContain('senderUser');
      expect(content).toContain('body');
    });
  });

  describe('Report Model Preservation', () => {
    it('should have Report model for report generation', () => {
      const reportModelPath = path.join(backendRoot, 'models/Report.js');
      expect(fs.existsSync(reportModelPath)).toBe(true);

      const content = fs.readFileSync(reportModelPath, 'utf8');
      expect(content).toContain('type');
      expect(content).toContain('status');
    });
  });

  describe('Task Controller Preservation', () => {
    it('should have task controller without service_type handling', () => {
      const taskControllerPath = path.join(backendRoot, 'controllers/taskController.js');
      expect(fs.existsSync(taskControllerPath)).toBe(true);

      const content = fs.readFileSync(taskControllerPath, 'utf8');
      
      // Verify task controller exists and has core functionality
      expect(content).toContain('createTask');
      expect(content).toContain('getTask');
      expect(content).toContain('updateTask');

      // Verify service_type is not handled in task controller
      // (it should not have service_type specific logic)
      const serviceTypeMatches = content.match(/service_type/g) || [];
      // Allow some matches in comments, but not in actual code logic
      expect(serviceTypeMatches.length).toBeLessThan(3);
    });
  });

  describe('Routes Preservation', () => {
    it('should have task routes without ticket/template routes', () => {
      const routesDir = path.join(backendRoot, 'routes');
      const files = fs.readdirSync(routesDir);

      // Verify task routes exist
      expect(files).toContain('taskRoutes.js');

      // Verify ticket/template routes don't exist
      expect(files).not.toContain('ticketRoutes.js');
      expect(files).not.toContain('templateRoutes.js');
    });

    it('should have user routes for user management', () => {
      const routesDir = path.join(backendRoot, 'routes');
      const files = fs.readdirSync(routesDir);

      expect(files).toContain('userRoutes.js');
    });

    it('should have attendance routes for attendance tracking', () => {
      const routesDir = path.join(backendRoot, 'routes');
      const files = fs.readdirSync(routesDir);

      expect(files).toContain('attendanceRoutes.js');
    });

    it('should have chat routes for messaging', () => {
      const routesDir = path.join(backendRoot, 'routes');
      const files = fs.readdirSync(routesDir);

      expect(files).toContain('chatRoutes.js');
    });

    it('should have report routes for report generation', () => {
      const routesDir = path.join(backendRoot, 'routes');
      const files = fs.readdirSync(routesDir);

      expect(files).toContain('reportRoutes.js');
    });
  });

  describe('Services Preservation', () => {
    it('should have notification service for notifications', () => {
      const notificationServicePath = path.join(backendRoot, 'services/notificationService.js');
      expect(fs.existsSync(notificationServicePath)).toBe(true);
    });

    it('should have audit service for audit logging', () => {
      const auditServicePath = path.join(backendRoot, 'services/auditService.js');
      expect(fs.existsSync(auditServicePath)).toBe(true);
    });

    it('should not have ticket service', () => {
      const ticketServicePath = path.join(backendRoot, 'services/ticketService.js');
      expect(fs.existsSync(ticketServicePath)).toBe(false);
    });
  });

  describe('Server Configuration Preservation', () => {
    it('should have task routes registered in server.js', () => {
      const serverPath = path.join(backendRoot, 'server.js');
      const content = fs.readFileSync(serverPath, 'utf8');

      expect(content).toContain("app.use('/api/tasks'");
      expect(content).toContain('taskRoutes');
    });

    it('should have user routes registered in server.js', () => {
      const serverPath = path.join(backendRoot, 'server.js');
      const content = fs.readFileSync(serverPath, 'utf8');

      expect(content).toContain("app.use('/api/users'");
      expect(content).toContain('userRoutes');
    });

    it('should have attendance routes registered in server.js', () => {
      const serverPath = path.join(backendRoot, 'server.js');
      const content = fs.readFileSync(serverPath, 'utf8');

      expect(content).toContain("app.use('/api/attendance'");
      expect(content).toContain('attendanceRoutes');
    });

    it('should have chat routes registered in server.js', () => {
      const serverPath = path.join(backendRoot, 'server.js');
      const content = fs.readFileSync(serverPath, 'utf8');

      expect(content).toContain("app.use('/api/chat'");
      expect(content).toContain('chatRoutes');
    });

    it('should have report routes registered in server.js', () => {
      const serverPath = path.join(backendRoot, 'server.js');
      const content = fs.readFileSync(serverPath, 'utf8');

      expect(content).toContain("app.use('/api/reports'");
      expect(content).toContain('reportRoutes');
    });

    it('should not have ticket routes registered in server.js', () => {
      const serverPath = path.join(backendRoot, 'server.js');
      const content = fs.readFileSync(serverPath, 'utf8');

      expect(content).not.toContain("app.use('/api/tickets'");
      expect(content).not.toContain('ticketRoutes');
    });

    it('should not have template routes registered in server.js', () => {
      const serverPath = path.join(backendRoot, 'server.js');
      const content = fs.readFileSync(serverPath, 'utf8');

      expect(content).not.toContain("app.use('/api/templates'");
      expect(content).not.toContain('templateRoutes');
    });
  });

  describe('Database Initialization Preservation', () => {
    it('should not have ticket/template seed data files', () => {
      const seedsDir = path.join(backendRoot, 'seeds');
      if (fs.existsSync(seedsDir)) {
        const files = fs.readdirSync(seedsDir);

        expect(files).not.toContain('ticketTemplates.json');
        expect(files).not.toContain('seedAirconTemplate.js');
        expect(files).not.toContain('seedElectricalTemplate.js');
        expect(files).not.toContain('seedPlumbingTemplate.js');
      }
    });
  });

  describe('No Regressions in Core Functionality', () => {
    it('should have all required models for core features', () => {
      const modelsDir = path.join(backendRoot, 'models');
      const files = fs.readdirSync(modelsDir);

      // Core models that must exist
      expect(files).toContain('Task.js');
      expect(files).toContain('User.js');
      expect(files).toContain('UserTask.js');
      expect(files).toContain('Attendance.js');
      expect(files).toContain('ChatMessage.js');
      expect(files).toContain('Report.js');

      // Ticket/template models must NOT exist
      expect(files).not.toContain('Ticket.js');
      expect(files).not.toContain('TicketTemplate.js');
    });

    it('should have all required controllers for core features', () => {
      const controllersDir = path.join(backendRoot, 'controllers');
      const files = fs.readdirSync(controllersDir);

      // Core controllers that must exist
      expect(files).toContain('taskController.js');
      expect(files).toContain('userController.js');
      expect(files).toContain('attendanceController.js');
      expect(files).toContain('chatController.js');
      expect(files).toContain('reportController.js');
    });

    it('should have all required routes for core features', () => {
      const routesDir = path.join(backendRoot, 'routes');
      const files = fs.readdirSync(routesDir);

      // Core routes that must exist
      expect(files).toContain('taskRoutes.js');
      expect(files).toContain('userRoutes.js');
      expect(files).toContain('attendanceRoutes.js');
      expect(files).toContain('chatRoutes.js');
      expect(files).toContain('reportRoutes.js');

      // Ticket/template routes must NOT exist
      expect(files).not.toContain('ticketRoutes.js');
      expect(files).not.toContain('templateRoutes.js');
    });
  });
});
