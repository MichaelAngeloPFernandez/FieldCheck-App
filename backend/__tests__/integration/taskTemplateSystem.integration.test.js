/**
 * Integration Tests for Task Template System Endpoints
 * 
 * Tests for:
 * - Service Management Endpoints
 * - Task Template Endpoints
 * - Task Management Endpoints (new)
 * - Ticket Management Endpoints
 * 
 * Framework: Jest + Supertest
 */

const request = require('supertest');
const mongoose = require('mongoose');
const dotenv = require('dotenv');
const express = require('express');

dotenv.config();

// Import models
const Service = require('../../models/Service');
const TaskTemplate = require('../../models/TaskTemplate');
const Task = require('../../models/Task');
const Ticket = require('../../models/Ticket');
const User = require('../../models/User');
const Company = require('../../models/Company');

// Test data
let testCompany;
let testAdmin;
let testEmployee;
let testService;
let testTemplate;
let testTicket;
let testTask;

// Helper to generate auth token
const generateToken = (userId) => {
  const jwt = require('jsonwebtoken');
  return jwt.sign({ id: userId }, process.env.JWT_SECRET, { expiresIn: '1h' });
};

// Create a minimal test app that uses the routes
const createTestApp = () => {
  const app = express();
  app.use(express.json());

  // Mock auth middleware
  app.use((req, res, next) => {
    const token = req.headers.authorization?.split(' ')[1];
    if (token) {
      try {
        const jwt = require('jsonwebtoken');
        const decoded = jwt.verify(token, process.env.JWT_SECRET);
        req.user = { _id: decoded.id };
        req.companyId = testCompany._id.toString();
      } catch (e) {
        return res.status(401).json({ message: 'Invalid token' });
      }
    }
    next();
  });

  // Import and use routes
  const serviceRoutes = require('../../routes/serviceRoutes');
  const templateRoutes = require('../../routes/templateRoutes');
  const ticketRoutes = require('../../routes/ticketRoutes');
  const taskRoutes = require('../../routes/taskRoutes');

  app.use('/api/services', serviceRoutes);
  app.use('/api/templates', templateRoutes);
  app.use('/api/tickets', ticketRoutes);
  app.use('/api/tasks', taskRoutes);

  // Error handling middleware
  app.use((err, req, res, next) => {
    console.error(err);
    res.status(err.status || 500).json({
      message: err.message || 'Internal server error',
    });
  });

  return app;
};

describe('Task Template System - Integration Tests', () => {
  let app;

  beforeAll(async () => {
    // Connect to test database
    if (mongoose.connection.readyState === 0) {
      await mongoose.connect(process.env.MONGO_URI || process.env.MONGODB_URI);
    }

    app = createTestApp();
  });

  afterAll(async () => {
    // Cleanup
    await Service.deleteMany({});
    await TaskTemplate.deleteMany({});
    await Task.deleteMany({});
    await Ticket.deleteMany({});
    await User.deleteMany({});
    await Company.deleteMany({});

    if (mongoose.connection.readyState === 1) {
      await mongoose.disconnect();
    }
  });

  beforeEach(async () => {
    // Create test company
    testCompany = await Company.create({
      name: 'Test Company',
      email: 'test@company.com',
      code: 'TEST_COMPANY_' + Date.now(),
    });

    // Create test admin user
    testAdmin = await User.create({
      name: 'Test Admin',
      email: 'admin@test.com',
      password: 'hashedpassword',
      role: 'admin',
      company: testCompany._id,
    });

    // Create test employee
    testEmployee = await User.create({
      name: 'Test Employee',
      email: 'employee@test.com',
      password: 'hashedpassword',
      role: 'employee',
      company: testCompany._id,
    });
  });

  afterEach(async () => {
    // Cleanup test data
    await Service.deleteMany({ companyId: testCompany._id });
    await TaskTemplate.deleteMany({ companyId: testCompany._id });
    await Task.deleteMany({ companyId: testCompany._id });
    await Ticket.deleteMany({ companyId: testCompany._id });
  });

  // ============ SERVICE MANAGEMENT ENDPOINTS ============

  describe('Service Management Endpoints', () => {
    describe('POST /api/services', () => {
      it('should create a new service', async () => {
        const token = generateToken(testAdmin._id);

        const response = await request(app)
          .post('/api/services')
          .set('Authorization', `Bearer ${token}`)
          .send({
            name: 'Aircon Cleaning',
            description: 'Professional aircon cleaning service',
          });

        expect(response.status).toBe(201);
        expect(response.body.name).toBe('Aircon Cleaning');
        expect(response.body.companyId.toString()).toBe(testCompany._id.toString());
        expect(response.body.isActive).toBe(true);
      });

      it('should reject service without name', async () => {
        const token = generateToken(testAdmin._id);

        const response = await request(app)
          .post('/api/services')
          .set('Authorization', `Bearer ${token}`)
          .send({
            description: 'No name provided',
          });

        expect(response.status).toBe(400);
        expect(response.body.message).toContain('name is required');
      });

      it('should reject duplicate service names', async () => {
        const token = generateToken(testAdmin._id);

        // Create first service
        await request(app)
          .post('/api/services')
          .set('Authorization', `Bearer ${token}`)
          .send({
            name: 'Aircon Cleaning',
          });

        // Try to create duplicate
        const response = await request(app)
          .post('/api/services')
          .set('Authorization', `Bearer ${token}`)
          .send({
            name: 'Aircon Cleaning',
          });

        expect(response.status).toBe(400);
        expect(response.body.message).toContain('already exists');
      });

      it('should reject non-admin users', async () => {
        const token = generateToken(testEmployee._id);

        const response = await request(app)
          .post('/api/services')
          .set('Authorization', `Bearer ${token}`)
          .send({
            name: 'Aircon Cleaning',
          });

        expect(response.status).toBe(401);
      });
    });

    describe('GET /api/services', () => {
      beforeEach(async () => {
        // Create test services
        testService = await Service.create({
          companyId: testCompany._id,
          name: 'Aircon Cleaning',
          description: 'Cleaning service',
          isActive: true,
        });

        await Service.create({
          companyId: testCompany._id,
          name: 'Plumbing Repair',
          description: 'Repair service',
          isActive: false,
        });
      });

      it('should list all services for company', async () => {
        const token = generateToken(testAdmin._id);

        const response = await request(app)
          .get('/api/services')
          .set('Authorization', `Bearer ${token}`);

        expect(response.status).toBe(200);
        expect(Array.isArray(response.body)).toBe(true);
        expect(response.body.length).toBe(2);
      });

      it('should filter by isActive', async () => {
        const token = generateToken(testAdmin._id);

        const response = await request(app)
          .get('/api/services?isActive=true')
          .set('Authorization', `Bearer ${token}`);

        expect(response.status).toBe(200);
        expect(response.body.length).toBe(1);
        expect(response.body[0].isActive).toBe(true);
      });

      it('should sort by name', async () => {
        const token = generateToken(testAdmin._id);

        const response = await request(app)
          .get('/api/services?sort=name')
          .set('Authorization', `Bearer ${token}`);

        expect(response.status).toBe(200);
        expect(response.body[0].name).toBe('Aircon Cleaning');
        expect(response.body[1].name).toBe('Plumbing Repair');
      });
    });

    describe('GET /api/services/:id', () => {
      beforeEach(async () => {
        testService = await Service.create({
          companyId: testCompany._id,
          name: 'Aircon Cleaning',
          description: 'Cleaning service',
        });

        // Create templates for service
        testTemplate = await TaskTemplate.create({
          serviceId: testService._id,
          companyId: testCompany._id,
          title: 'Inspect filters',
          type: 'inspection',
        });
      });

      it('should get service with templates', async () => {
        const token = generateToken(testAdmin._id);

        const response = await request(app)
          .get(`/api/services/${testService._id}`)
          .set('Authorization', `Bearer ${token}`);

        expect(response.status).toBe(200);
        expect(response.body.name).toBe('Aircon Cleaning');
        expect(Array.isArray(response.body.templates)).toBe(true);
        expect(response.body.templates.length).toBe(1);
      });

      it('should return 404 for non-existent service', async () => {
        const token = generateToken(testAdmin._id);
        const fakeId = new mongoose.Types.ObjectId();

        const response = await request(app)
          .get(`/api/services/${fakeId}`)
          .set('Authorization', `Bearer ${token}`);

        expect(response.status).toBe(404);
      });
    });

    describe('PUT /api/services/:id', () => {
      beforeEach(async () => {
        testService = await Service.create({
          companyId: testCompany._id,
          name: 'Aircon Cleaning',
          description: 'Original description',
        });
      });

      it('should update service', async () => {
        const token = generateToken(testAdmin._id);

        const response = await request(app)
          .put(`/api/services/${testService._id}`)
          .set('Authorization', `Bearer ${token}`)
          .send({
            name: 'Premium Aircon Cleaning',
            description: 'Updated description',
            isActive: false,
          });

        expect(response.status).toBe(200);
        expect(response.body.name).toBe('Premium Aircon Cleaning');
        expect(response.body.description).toBe('Updated description');
        expect(response.body.isActive).toBe(false);
      });

      it('should reject duplicate name on update', async () => {
        const token = generateToken(testAdmin._id);

        // Create another service
        await Service.create({
          companyId: testCompany._id,
          name: 'Plumbing Repair',
        });

        // Try to rename first service to duplicate name
        const response = await request(app)
          .put(`/api/services/${testService._id}`)
          .set('Authorization', `Bearer ${token}`)
          .send({
            name: 'Plumbing Repair',
          });

        expect(response.status).toBe(400);
        expect(response.body.message).toContain('already exists');
      });
    });

    describe('DELETE /api/services/:id', () => {
      beforeEach(async () => {
        testService = await Service.create({
          companyId: testCompany._id,
          name: 'Aircon Cleaning',
        });

        // Create templates for service
        await TaskTemplate.create({
          serviceId: testService._id,
          companyId: testCompany._id,
          title: 'Inspect filters',
        });
      });

      it('should delete service and templates', async () => {
        const token = generateToken(testAdmin._id);

        const response = await request(app)
          .delete(`/api/services/${testService._id}`)
          .set('Authorization', `Bearer ${token}`);

        expect(response.status).toBe(200);
        expect(response.body.success).toBe(true);

        // Verify service is deleted
        const service = await Service.findById(testService._id);
        expect(service).toBeNull();

        // Verify templates are deleted
        const templates = await TaskTemplate.find({ serviceId: testService._id });
        expect(templates.length).toBe(0);
      });
    });
  });

  // ============ TASK TEMPLATE ENDPOINTS ============

  describe('Task Template Endpoints', () => {
    beforeEach(async () => {
      testService = await Service.create({
        companyId: testCompany._id,
        name: 'Aircon Cleaning',
      });
    });

    describe('POST /api/templates/service/:serviceId', () => {
      it('should create a template', async () => {
        const token = generateToken(testAdmin._id);

        const response = await request(app)
          .post(`/api/templates/service/${testService._id}`)
          .set('Authorization', `Bearer ${token}`)
          .send({
            title: 'Inspect filters',
            description: 'Check and replace filters',
            type: 'inspection',
            difficulty: 'easy',
            checklist: [
              { label: 'Check filter condition' },
              { label: 'Replace if needed' },
            ],
          });

        expect(response.status).toBe(201);
        expect(response.body.title).toBe('Inspect filters');
        expect(response.body.type).toBe('inspection');
        expect(response.body.checklist.length).toBe(2);
      });

      it('should reject template without title', async () => {
        const token = generateToken(testAdmin._id);

        const response = await request(app)
          .post(`/api/templates/service/${testService._id}`)
          .set('Authorization', `Bearer ${token}`)
          .send({
            description: 'No title',
          });

        expect(response.status).toBe(400);
        expect(response.body.message).toContain('title is required');
      });

      it('should reject invalid type', async () => {
        const token = generateToken(testAdmin._id);

        const response = await request(app)
          .post(`/api/templates/service/${testService._id}`)
          .set('Authorization', `Bearer ${token}`)
          .send({
            title: 'Test',
            type: 'invalid_type',
          });

        expect(response.status).toBe(400);
        expect(response.body.message).toContain('Invalid type');
      });
    });

    describe('GET /api/templates/service/:serviceId', () => {
      beforeEach(async () => {
        await TaskTemplate.create({
          serviceId: testService._id,
          companyId: testCompany._id,
          title: 'Inspect filters',
          isActive: true,
        });

        await TaskTemplate.create({
          serviceId: testService._id,
          companyId: testCompany._id,
          title: 'Clean coils',
          isActive: false,
        });
      });

      it('should list templates for service', async () => {
        const token = generateToken(testAdmin._id);

        const response = await request(app)
          .get(`/api/templates/service/${testService._id}`)
          .set('Authorization', `Bearer ${token}`);

        expect(response.status).toBe(200);
        expect(Array.isArray(response.body)).toBe(true);
        expect(response.body.length).toBe(2);
      });

      it('should filter by isActive', async () => {
        const token = generateToken(testAdmin._id);

        const response = await request(app)
          .get(`/api/templates/service/${testService._id}?isActive=true`)
          .set('Authorization', `Bearer ${token}`);

        expect(response.status).toBe(200);
        expect(response.body.length).toBe(1);
        expect(response.body[0].isActive).toBe(true);
      });
    });

    describe('GET /api/templates/:id', () => {
      beforeEach(async () => {
        testTemplate = await TaskTemplate.create({
          serviceId: testService._id,
          companyId: testCompany._id,
          title: 'Inspect filters',
        });
      });

      it('should get template details', async () => {
        const token = generateToken(testAdmin._id);

        const response = await request(app)
          .get(`/api/templates/${testTemplate._id}`)
          .set('Authorization', `Bearer ${token}`);

        expect(response.status).toBe(200);
        expect(response.body.title).toBe('Inspect filters');
      });
    });

    describe('PUT /api/templates/:id', () => {
      beforeEach(async () => {
        testTemplate = await TaskTemplate.create({
          serviceId: testService._id,
          companyId: testCompany._id,
          title: 'Inspect filters',
          difficulty: 'easy',
        });
      });

      it('should update template', async () => {
        const token = generateToken(testAdmin._id);

        const response = await request(app)
          .put(`/api/templates/${testTemplate._id}`)
          .set('Authorization', `Bearer ${token}`)
          .send({
            title: 'Advanced Filter Inspection',
            difficulty: 'hard',
          });

        expect(response.status).toBe(200);
        expect(response.body.title).toBe('Advanced Filter Inspection');
        expect(response.body.difficulty).toBe('hard');
      });
    });

    describe('DELETE /api/templates/:id', () => {
      beforeEach(async () => {
        testTemplate = await TaskTemplate.create({
          serviceId: testService._id,
          companyId: testCompany._id,
          title: 'Inspect filters',
        });
      });

      it('should delete template', async () => {
        const token = generateToken(testAdmin._id);

        const response = await request(app)
          .delete(`/api/templates/${testTemplate._id}`)
          .set('Authorization', `Bearer ${token}`);

        expect(response.status).toBe(200);
        expect(response.body.success).toBe(true);

        const template = await TaskTemplate.findById(testTemplate._id);
        expect(template).toBeNull();
      });
    });
  });

  // ============ TICKET MANAGEMENT ENDPOINTS ============

  describe('Ticket Management Endpoints', () => {
    describe('POST /api/tickets', () => {
      it('should create ticket without service', async () => {
        const token = generateToken(testAdmin._id);

        const response = await request(app)
          .post('/api/tickets')
          .set('Authorization', `Bearer ${token}`)
          .send({
            title: 'General Maintenance',
            description: 'Routine maintenance',
          });

        expect(response.status).toBe(201);
        expect(response.body.title).toBe('General Maintenance');
        expect(response.body.status).toBe('open');
        expect(response.body.serviceId).toBeNull();
      });

      it('should create ticket with service and clone templates', async () => {
        const token = generateToken(testAdmin._id);

        // Create service with templates
        const service = await Service.create({
          companyId: testCompany._id,
          name: 'Aircon Cleaning',
        });

        await TaskTemplate.create({
          serviceId: service._id,
          companyId: testCompany._id,
          title: 'Inspect filters',
          isActive: true,
        });

        await TaskTemplate.create({
          serviceId: service._id,
          companyId: testCompany._id,
          title: 'Clean coils',
          isActive: true,
        });

        const response = await request(app)
          .post('/api/tickets')
          .set('Authorization', `Bearer ${token}`)
          .send({
            title: 'Aircon Service',
            serviceId: service._id.toString(),
          });

        expect(response.status).toBe(201);
        expect(response.body.serviceId.toString()).toBe(service._id.toString());
        expect(Array.isArray(response.body.tasks)).toBe(true);
        expect(response.body.tasks.length).toBe(2);
        expect(response.body.tasks[0].taskOrigin).toBe('template');
      });

      it('should reject ticket without title', async () => {
        const token = generateToken(testAdmin._id);

        const response = await request(app)
          .post('/api/tickets')
          .set('Authorization', `Bearer ${token}`)
          .send({
            description: 'No title',
          });

        expect(response.status).toBe(400);
        expect(response.body.message).toContain('title is required');
      });
    });

    describe('GET /api/tickets', () => {
      beforeEach(async () => {
        await Ticket.create({
          companyId: testCompany._id,
          title: 'Ticket 1',
          status: 'open',
        });

        await Ticket.create({
          companyId: testCompany._id,
          title: 'Ticket 2',
          status: 'closed',
        });
      });

      it('should list all tickets', async () => {
        const token = generateToken(testAdmin._id);

        const response = await request(app)
          .get('/api/tickets')
          .set('Authorization', `Bearer ${token}`);

        expect(response.status).toBe(200);
        expect(Array.isArray(response.body)).toBe(true);
        expect(response.body.length).toBe(2);
      });

      it('should filter by status', async () => {
        const token = generateToken(testAdmin._id);

        const response = await request(app)
          .get('/api/tickets?status=open')
          .set('Authorization', `Bearer ${token}`);

        expect(response.status).toBe(200);
        expect(response.body.length).toBe(1);
        expect(response.body[0].status).toBe('open');
      });
    });

    describe('GET /api/tickets/:id', () => {
      beforeEach(async () => {
        testTicket = await Ticket.create({
          companyId: testCompany._id,
          title: 'Test Ticket',
        });

        testTask = await Task.create({
          ticketId: testTicket._id,
          companyId: testCompany._id,
          title: 'Test Task',
          assignedBy: testAdmin._id,
          assignedTo: testEmployee._id,
        });
      });

      it('should get ticket with tasks', async () => {
        const token = generateToken(testAdmin._id);

        const response = await request(app)
          .get(`/api/tickets/${testTicket._id}`)
          .set('Authorization', `Bearer ${token}`);

        expect(response.status).toBe(200);
        expect(response.body.title).toBe('Test Ticket');
        expect(Array.isArray(response.body.tasks)).toBe(true);
        expect(response.body.tasks.length).toBe(1);
      });

      it('should allow employee to access assigned tasks', async () => {
        const token = generateToken(testEmployee._id);

        const response = await request(app)
          .get(`/api/tickets/${testTicket._id}`)
          .set('Authorization', `Bearer ${token}`);

        expect(response.status).toBe(200);
      });

      it('should deny employee access to unassigned tasks', async () => {
        const token = generateToken(testEmployee._id);

        // Create another employee
        const otherEmployee = await User.create({
          name: 'Other Employee',
          email: 'other@test.com',
          password: 'hashedpassword',
          role: 'employee',
          company: testCompany._id,
        });

        // Create ticket with task assigned to other employee
        const ticket = await Ticket.create({
          companyId: testCompany._id,
          title: 'Other Ticket',
        });

        await Task.create({
          ticketId: ticket._id,
          companyId: testCompany._id,
          title: 'Other Task',
          assignedBy: testAdmin._id,
          assignedTo: otherEmployee._id,
        });

        const response = await request(app)
          .get(`/api/tickets/${ticket._id}`)
          .set('Authorization', `Bearer ${token}`);

        expect(response.status).toBe(403);
      });
    });
  });

  // ============ TASK MANAGEMENT ENDPOINTS ============

  describe('Task Management Endpoints', () => {
    beforeEach(async () => {
      testTicket = await Ticket.create({
        companyId: testCompany._id,
        title: 'Test Ticket',
      });
    });

    describe('POST /api/tasks/ticket/:ticketId/create', () => {
      it('should create ad-hoc task', async () => {
        const token = generateToken(testAdmin._id);

        const response = await request(app)
          .post(`/api/tasks/ticket/${testTicket._id}/create`)
          .set('Authorization', `Bearer ${token}`)
          .send({
            title: 'Ad-hoc Task',
            description: 'Unexpected work',
            type: 'maintenance',
            difficulty: 'medium',
            checklist: [{ label: 'Step 1' }],
          });

        expect(response.status).toBe(201);
        expect(response.body.title).toBe('Ad-hoc Task');
        expect(response.body.taskOrigin).toBe('ad_hoc');
        expect(response.body.ticketId.toString()).toBe(testTicket._id.toString());
      });
    });

    describe('GET /api/tasks/ticket/:ticketId/list', () => {
      beforeEach(async () => {
        await Task.create({
          ticketId: testTicket._id,
          companyId: testCompany._id,
          title: 'Template Task',
          taskOrigin: 'template',
          assignedBy: testAdmin._id,
          assignedTo: testEmployee._id,
        });

        await Task.create({
          ticketId: testTicket._id,
          companyId: testCompany._id,
          title: 'Ad-hoc Task',
          taskOrigin: 'ad_hoc',
          assignedBy: testAdmin._id,
        });
      });

      it('should list all tasks for ticket', async () => {
        const token = generateToken(testAdmin._id);

        const response = await request(app)
          .get(`/api/tasks/ticket/${testTicket._id}/list`)
          .set('Authorization', `Bearer ${token}`);

        expect(response.status).toBe(200);
        expect(Array.isArray(response.body)).toBe(true);
        expect(response.body.length).toBe(2);
      });

      it('should filter by taskOrigin', async () => {
        const token = generateToken(testAdmin._id);

        const response = await request(app)
          .get(`/api/tasks/ticket/${testTicket._id}/list?taskOrigin=template`)
          .set('Authorization', `Bearer ${token}`);

        expect(response.status).toBe(200);
        expect(response.body.length).toBe(1);
        expect(response.body[0].taskOrigin).toBe('template');
      });

      it('should show only assigned tasks for employee', async () => {
        const token = generateToken(testEmployee._id);

        const response = await request(app)
          .get(`/api/tasks/ticket/${testTicket._id}/list`)
          .set('Authorization', `Bearer ${token}`);

        expect(response.status).toBe(200);
        expect(response.body.length).toBe(1);
        expect(response.body[0].title).toBe('Template Task');
      });
    });

    describe('PUT /api/tasks/:id/assign', () => {
      beforeEach(async () => {
        testTask = await Task.create({
          ticketId: testTicket._id,
          companyId: testCompany._id,
          title: 'Unassigned Task',
          assignedBy: testAdmin._id,
          status: 'pending',
        });
      });

      it('should assign task to employee', async () => {
        const token = generateToken(testAdmin._id);

        const response = await request(app)
          .put(`/api/tasks/${testTask._id}/assign`)
          .set('Authorization', `Bearer ${token}`)
          .send({
            assignedTo: testEmployee._id.toString(),
          });

        expect(response.status).toBe(200);
        expect(response.body.assignedTo.toString()).toBe(testEmployee._id.toString());
        expect(response.body.status).toBe('assigned');
      });
    });

    describe('PUT /api/tasks/:id/status', () => {
      beforeEach(async () => {
        testTask = await Task.create({
          ticketId: testTicket._id,
          companyId: testCompany._id,
          title: 'Test Task',
          assignedBy: testAdmin._id,
          assignedTo: testEmployee._id,
          status: 'pending',
        });
      });

      it('should update task status', async () => {
        const token = generateToken(testEmployee._id);

        const response = await request(app)
          .put(`/api/tasks/${testTask._id}/status`)
          .set('Authorization', `Bearer ${token}`)
          .send({
            status: 'in_progress',
            reason: 'Started work',
          });

        expect(response.status).toBe(200);
        expect(response.body.status).toBe('in_progress');
        expect(response.body.statusHistory.length).toBeGreaterThan(0);
      });

      it('should record completion details', async () => {
        const token = generateToken(testEmployee._id);

        const response = await request(app)
          .put(`/api/tasks/${testTask._id}/status`)
          .set('Authorization', `Bearer ${token}`)
          .send({
            status: 'completed',
          });

        expect(response.status).toBe(200);
        expect(response.body.status).toBe('completed');
        expect(response.body.completedBy).toBeDefined();
        expect(response.body.completedAt).toBeDefined();
      });
    });

    describe('POST /api/tasks/:id/checklist/:itemIndex/complete', () => {
      beforeEach(async () => {
        testTask = await Task.create({
          ticketId: testTicket._id,
          companyId: testCompany._id,
          title: 'Task with Checklist',
          assignedBy: testAdmin._id,
          assignedTo: testEmployee._id,
          checklist: [
            { label: 'Step 1', isCompleted: false },
            { label: 'Step 2', isCompleted: false },
          ],
        });
      });

      it('should complete checklist item', async () => {
        const token = generateToken(testEmployee._id);

        const response = await request(app)
          .post(`/api/tasks/${testTask._id}/checklist/0/complete`)
          .set('Authorization', `Bearer ${token}`);

        expect(response.status).toBe(200);
        expect(response.body.checklist[0].isCompleted).toBe(true);
        expect(response.body.checklist[0].completedAt).toBeDefined();
      });

      it('should reject invalid item index', async () => {
        const token = generateToken(testEmployee._id);

        const response = await request(app)
          .post(`/api/tasks/${testTask._id}/checklist/99/complete`)
          .set('Authorization', `Bearer ${token}`);

        expect(response.status).toBe(400);
        expect(response.body.message).toContain('Invalid checklist item index');
      });
    });
  });
});
