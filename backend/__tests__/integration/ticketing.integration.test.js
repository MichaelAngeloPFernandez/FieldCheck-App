/**
 * Integration Tests — Full Ticket Lifecycle
 *
 * Tests the complete ticket workflow end-to-end using an in-memory MongoDB
 * instance (mongodb-memory-server) and Supertest against the real Express
 * routes (with auth middleware mocked via JWT).
 *
 * Lifecycle covered:
 *   create (open) → in_progress → completed → verified → closed
 *
 * Additional assertions:
 *   - completedAt is set on first terminal transition
 *   - sla_status is finalized on close/verify
 *   - audit log entries exist for each transition
 *   - 403 on cross-company access
 *   - 403 when employee tries to access another employee's ticket
 *   - 400 when updating a closed ticket
 *
 * Framework: Jest + Supertest + mongodb-memory-server
 *
 * NOTE: The global setup.js replaces global.Date with a mock subclass.
 * Mongoose 8 uses `instanceof Date` checks during schema compilation, which
 * fails when Date is replaced.  We restore the native Date before any model
 * imports below.
 */

// ─── Restore native Date (must happen before any Mongoose model is required) ─
// setup.js does: global.Date = class extends Date { ... }
// The mock class's prototype chain is: MockDate → NativeDate → Object
// We recover NativeDate via Object.getPrototypeOf.
{
  const MockDate = global.Date;
  const NativeDate = Object.getPrototypeOf(MockDate);
  if (typeof NativeDate === 'function' && NativeDate !== Object) {
    global.Date = NativeDate;
  }
}

const request = require('supertest');
const express = require('express');
const mongoose = require('mongoose');
const { MongoMemoryServer } = require('mongodb-memory-server');
const jwt = require('jsonwebtoken');

// Models
const Company = require('../../models/Company');
const User = require('../../models/User');
const TicketTemplate = require('../../models/TicketTemplate');
const Ticket = require('../../models/Ticket');
const AuditLog = require('../../models/AuditLog');

// Routes
const ticketRoutes = require('../../routes/ticketRoutes');

// ─── Test constants ───────────────────────────────────────────────────────────

const JWT_SECRET = 'test-secret-key';
process.env.JWT_SECRET = JWT_SECRET;

// ─── App factory ─────────────────────────────────────────────────────────────

const buildApp = () => {
  const app = express();
  app.use(express.json());
  app.use('/api/tickets', ticketRoutes);
  // Generic error handler
  app.use((err, req, res, _next) => {
    const status = res.statusCode && res.statusCode !== 200 ? res.statusCode : 500;
    res.status(status).json({ message: err.message });
  });
  return app;
};

// ─── Token helpers ────────────────────────────────────────────────────────────

const makeToken = (userId) =>
  jwt.sign({ id: userId }, JWT_SECRET, { expiresIn: '1h' });

// ─── Setup / Teardown ─────────────────────────────────────────────────────────

let mongod;
let app;

// Shared test fixtures
let companyA;
let companyB;
let adminA;
let employeeA;
let employeeB; // belongs to company B
let template;

beforeAll(async () => {
  mongod = await MongoMemoryServer.create();
  await mongoose.connect(mongod.getUri());
  app = buildApp();
});

afterAll(async () => {
  await mongoose.disconnect();
  await mongod.stop();
});

beforeEach(async () => {
  // Clear all collections
  await Promise.all([
    Company.deleteMany({}),
    User.deleteMany({}),
    TicketTemplate.deleteMany({}),
    Ticket.deleteMany({}),
    AuditLog.deleteMany({}),
    mongoose.connection.collection('counters').deleteMany({}),
  ]);

  // Create companies
  companyA = await Company.create({ name: 'Company A', code: 'CMPA' });
  companyB = await Company.create({ name: 'Company B', code: 'CMPB' });

  // Create users
  adminA = await User.create({
    name: 'Admin A',
    email: 'admin@cmpa.com',
    username: 'admin_a',
    password: 'hashed',
    role: 'admin',
    company: companyA._id,
    isActive: true,
  });

  employeeA = await User.create({
    name: 'Employee A',
    email: 'emp@cmpa.com',
    username: 'emp_a',
    password: 'hashed',
    role: 'employee',
    company: companyA._id,
    isActive: true,
    employeeId: 'EMP001',
  });

  employeeB = await User.create({
    name: 'Employee B',
    email: 'emp@cmpb.com',
    username: 'emp_b',
    password: 'hashed',
    role: 'employee',
    company: companyB._id,
    isActive: true,
    employeeId: 'EMP002',
  });

  // Create a ticket template for company A
  template = await TicketTemplate.create({
    company: companyA._id,
    name: 'Field Inspection',
    description: 'Standard field inspection form',
    json_schema: {
      type: 'object',
      properties: {
        location: { type: 'string' },
        notes: { type: 'string' },
      },
      required: ['location'],
      additionalProperties: true,
    },
    workflow: {
      statuses: ['open', 'in_progress', 'completed', 'verified', 'closed'],
      transitions: {
        open: ['in_progress', 'closed'],
        in_progress: ['completed', 'closed'],
        completed: ['verified', 'closed'],
        verified: ['closed'],
        closed: [],
      },
    },
    sla_seconds: 3600, // 1 hour SLA
    isActive: true,
    created_by: adminA._id,
  });
});

// ─── Helpers ──────────────────────────────────────────────────────────────────

const adminHeaders = () => ({
  Authorization: `Bearer ${makeToken(adminA._id)}`,
  'Content-Type': 'application/json',
});

const employeeAHeaders = () => ({
  Authorization: `Bearer ${makeToken(employeeA._id)}`,
  'Content-Type': 'application/json',
});

const employeeBHeaders = () => ({
  Authorization: `Bearer ${makeToken(employeeB._id)}`,
  'Content-Type': 'application/json',
});

// ─── Tests ────────────────────────────────────────────────────────────────────

describe('Ticket Lifecycle — Integration', () => {
  let ticketId;
  let ticketNo;

  describe('Step 1: Create ticket (open)', () => {
    it('creates a ticket with status=open and correct ticket_no format', async () => {
      const res = await request(app)
        .post('/api/tickets')
        .set(adminHeaders())
        .send({
          template_id: String(template._id),
          data: { location: 'Site A', notes: 'Initial inspection' },
          assignee_id: String(employeeA._id),
        });

      expect(res.status).toBe(201);
      expect(res.body.status).toBe('open');
      expect(res.body.ticket_no).toMatch(/^CMPA-\d{4}$/);
      expect(res.body.sla_deadline).not.toBeNull();
      expect(res.body.sla_status).toBe('on_time');
      expect(res.body.completedAt).toBeNull();

      ticketId = res.body._id;
      ticketNo = res.body.ticket_no;
    });

    it('creates an audit log entry with action=created', async () => {
      const res = await request(app)
        .post('/api/tickets')
        .set(adminHeaders())
        .send({
          template_id: String(template._id),
          data: { location: 'Site B' },
        });

      expect(res.status).toBe(201);
      const id = res.body._id;

      const logs = await AuditLog.find({
        resource_type: 'ticket',
        resource_id: String(id),
        action: 'created',
      }).lean();

      expect(logs.length).toBeGreaterThanOrEqual(1);
    });

    it('rejects creation when assignee_id is not an employee', async () => {
      const res = await request(app)
        .post('/api/tickets')
        .set(adminHeaders())
        .send({
          template_id: String(template._id),
          data: { location: 'Site C' },
          assignee_id: String(adminA._id), // admin, not employee
        });

      expect(res.status).toBe(400);
      expect(res.body.message).toMatch(/employee/i);
    });

    it('rejects creation with invalid template data (missing required field)', async () => {
      const res = await request(app)
        .post('/api/tickets')
        .set(adminHeaders())
        .send({
          template_id: String(template._id),
          data: { notes: 'no location provided' }, // missing required 'location'
        });

      expect(res.status).toBe(400);
      expect(res.body.message).toMatch(/validation/i);
    });
  });

  describe('Step 2: Transition open → in_progress', () => {
    beforeEach(async () => {
      const res = await request(app)
        .post('/api/tickets')
        .set(adminHeaders())
        .send({
          template_id: String(template._id),
          data: { location: 'Site A' },
          assignee_id: String(employeeA._id),
        });
      ticketId = res.body._id;
    });

    it('transitions to in_progress successfully', async () => {
      const res = await request(app)
        .patch(`/api/tickets/${ticketId}/status`)
        .set(adminHeaders())
        .send({ status: 'in_progress' });

      expect(res.status).toBe(200);
      expect(res.body.status).toBe('in_progress');
      expect(res.body.completedAt).toBeNull();
    });

    it('logs status_changed audit entry', async () => {
      await request(app)
        .patch(`/api/tickets/${ticketId}/status`)
        .set(adminHeaders())
        .send({ status: 'in_progress' });

      const logs = await AuditLog.find({
        resource_type: 'ticket',
        resource_id: String(ticketId),
        action: 'status_changed',
      }).lean();

      expect(logs.length).toBeGreaterThanOrEqual(1);
      expect(logs[0].details.from).toBe('open');
      expect(logs[0].details.to).toBe('in_progress');
    });
  });

  describe('Step 3: Transition in_progress → completed', () => {
    beforeEach(async () => {
      const create = await request(app)
        .post('/api/tickets')
        .set(adminHeaders())
        .send({
          template_id: String(template._id),
          data: { location: 'Site A' },
          assignee_id: String(employeeA._id),
        });
      ticketId = create.body._id;

      await request(app)
        .patch(`/api/tickets/${ticketId}/status`)
        .set(adminHeaders())
        .send({ status: 'in_progress' });
    });

    it('sets completedAt on transition to completed', async () => {
      const res = await request(app)
        .patch(`/api/tickets/${ticketId}/status`)
        .set(adminHeaders())
        .send({ status: 'completed' });

      expect(res.status).toBe(200);
      expect(res.body.status).toBe('completed');
      expect(res.body.completedAt).not.toBeNull();
    });
  });

  describe('Step 4: Transition completed → verified (SLA finalization)', () => {
    beforeEach(async () => {
      const create = await request(app)
        .post('/api/tickets')
        .set(adminHeaders())
        .send({
          template_id: String(template._id),
          data: { location: 'Site A' },
          assignee_id: String(employeeA._id),
        });
      ticketId = create.body._id;

      await request(app)
        .patch(`/api/tickets/${ticketId}/status`)
        .set(adminHeaders())
        .send({ status: 'in_progress' });

      await request(app)
        .patch(`/api/tickets/${ticketId}/status`)
        .set(adminHeaders())
        .send({ status: 'completed' });
    });

    it('finalizes sla_status on transition to verified', async () => {
      const res = await request(app)
        .patch(`/api/tickets/${ticketId}/status`)
        .set(adminHeaders())
        .send({ status: 'verified' });

      expect(res.status).toBe(200);
      expect(res.body.status).toBe('verified');
      // Completed well within the 1-hour SLA → on_time
      expect(res.body.sla_status).toBe('on_time');
    });
  });

  describe('Step 5: Transition verified → closed', () => {
    beforeEach(async () => {
      const create = await request(app)
        .post('/api/tickets')
        .set(adminHeaders())
        .send({
          template_id: String(template._id),
          data: { location: 'Site A' },
          assignee_id: String(employeeA._id),
        });
      ticketId = create.body._id;

      for (const status of ['in_progress', 'completed', 'verified']) {
        await request(app)
          .patch(`/api/tickets/${ticketId}/status`)
          .set(adminHeaders())
          .send({ status });
      }
    });

    it('closes the ticket successfully', async () => {
      const res = await request(app)
        .patch(`/api/tickets/${ticketId}/status`)
        .set(adminHeaders())
        .send({ status: 'closed' });

      expect(res.status).toBe(200);
      expect(res.body.status).toBe('closed');
    });

    it('rejects further status transitions on a closed ticket', async () => {
      await request(app)
        .patch(`/api/tickets/${ticketId}/status`)
        .set(adminHeaders())
        .send({ status: 'closed' });

      const res = await request(app)
        .patch(`/api/tickets/${ticketId}/status`)
        .set(adminHeaders())
        .send({ status: 'open' });

      expect(res.status).toBe(400);
    });

    it('rejects data updates on a closed ticket', async () => {
      await request(app)
        .patch(`/api/tickets/${ticketId}/status`)
        .set(adminHeaders())
        .send({ status: 'closed' });

      const res = await request(app)
        .patch(`/api/tickets/${ticketId}`)
        .set(adminHeaders())
        .send({ notes: 'trying to update a closed ticket' });

      expect(res.status).toBe(400);
      expect(res.body.message).toMatch(/closed/i);
    });
  });

  describe('Access control', () => {
    beforeEach(async () => {
      const create = await request(app)
        .post('/api/tickets')
        .set(adminHeaders())
        .send({
          template_id: String(template._id),
          data: { location: 'Site A' },
          assignee_id: String(employeeA._id),
        });
      ticketId = create.body._id;
    });

    it('returns 403 when employee accesses a ticket not assigned to them', async () => {
      // employeeB is from a different company and not the assignee
      const res = await request(app)
        .get(`/api/tickets/${ticketId}`)
        .set(employeeBHeaders());

      // Could be 403 (wrong company) or 403 (wrong assignee) — both are correct
      expect(res.status).toBe(403);
    });

    it('allows the assigned employee to view their own ticket', async () => {
      const res = await request(app)
        .get(`/api/tickets/${ticketId}`)
        .set(employeeAHeaders());

      expect(res.status).toBe(200);
      expect(res.body._id).toBe(ticketId);
    });

    it('returns 403 when admin from company B tries to access company A ticket', async () => {
      const adminB = await User.create({
        name: 'Admin B',
        email: 'admin@cmpb.com',
        username: 'admin_b',
        password: 'hashed',
        role: 'admin',
        company: companyB._id,
        isActive: true,
      });

      const res = await request(app)
        .get(`/api/tickets/${ticketId}`)
        .set({
          Authorization: `Bearer ${makeToken(adminB._id)}`,
          'Content-Type': 'application/json',
        });

      expect(res.status).toBe(403);
    });
  });

  describe('Audit trail completeness', () => {
    it('has audit entries for every status transition in the full lifecycle', async () => {
      const create = await request(app)
        .post('/api/tickets')
        .set(adminHeaders())
        .send({
          template_id: String(template._id),
          data: { location: 'Site A' },
          assignee_id: String(employeeA._id),
        });
      const id = create.body._id;

      const transitions = ['in_progress', 'completed', 'verified', 'closed'];
      for (const status of transitions) {
        await request(app)
          .patch(`/api/tickets/${id}/status`)
          .set(adminHeaders())
          .send({ status });
      }

      const logs = await AuditLog.find({
        resource_type: 'ticket',
        resource_id: String(id),
      })
        .sort({ created_at: 1 })
        .lean();

      const actions = logs.map((l) => l.action);
      expect(actions).toContain('created');
      expect(actions.filter((a) => a === 'status_changed').length).toBe(
        transitions.length,
      );
    });
  });

  describe('GET /api/tickets/employees', () => {
    it('returns active employees for the admin company', async () => {
      const res = await request(app)
        .get('/api/tickets/employees')
        .set(adminHeaders());

      expect(res.status).toBe(200);
      expect(Array.isArray(res.body)).toBe(true);
      expect(res.body.length).toBeGreaterThanOrEqual(1);

      const emp = res.body.find((e) => e._id === String(employeeA._id));
      expect(emp).toBeDefined();
      expect(emp.name).toBe('Employee A');
    });

    it('returns 403 when called by an employee', async () => {
      const res = await request(app)
        .get('/api/tickets/employees')
        .set(employeeAHeaders());

      expect(res.status).toBe(403);
    });
  });
});
