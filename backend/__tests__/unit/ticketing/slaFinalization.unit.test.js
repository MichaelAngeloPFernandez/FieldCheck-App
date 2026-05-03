/**
 * Unit Tests — TicketService.finalizeSlaStatus()
 *
 * Covers:
 *   - on_time when completedAt ≤ sla_deadline
 *   - overdue kept when completedAt > sla_deadline
 *   - sla_status stays null when sla_deadline is null
 *   - uses current time when completedAt is absent
 */

// Restore native Date before any Mongoose model is loaded.
// setup.js replaces global.Date with a mock subclass; Mongoose 8 uses
// `instanceof Date` checks during schema compilation which fail with the mock.
{
  const MockDate = global.Date;
  const NativeDate = Object.getPrototypeOf(MockDate);
  if (typeof NativeDate === 'function' && NativeDate !== Object) {
    global.Date = NativeDate;
  }
}

const TicketService = require('../../../services/ticketService');

// ─── Helpers ─────────────────────────────────────────────────────────────────

const makeTicket = (overrides = {}) => ({
  sla_deadline: null,
  sla_status: null,
  completedAt: null,
  ...overrides,
});

// ─── Tests ───────────────────────────────────────────────────────────────────

describe('TicketService.finalizeSlaStatus()', () => {
  describe('when sla_deadline is null', () => {
    it('leaves sla_status as null', () => {
      const ticket = makeTicket({ sla_deadline: null, sla_status: null });
      TicketService.finalizeSlaStatus(ticket);
      expect(ticket.sla_status).toBeNull();
    });

    it('leaves sla_status unchanged even if it was previously set', () => {
      const ticket = makeTicket({ sla_deadline: null, sla_status: 'on_time' });
      TicketService.finalizeSlaStatus(ticket);
      expect(ticket.sla_status).toBe('on_time');
    });

    it('returns the ticket object', () => {
      const ticket = makeTicket();
      const result = TicketService.finalizeSlaStatus(ticket);
      expect(result).toBe(ticket);
    });
  });

  describe('when completedAt ≤ sla_deadline (on time)', () => {
    it('sets sla_status to "on_time" when completed exactly at deadline', () => {
      const deadline = new Date('2024-06-01T12:00:00Z');
      const ticket = makeTicket({
        sla_deadline: deadline,
        completedAt: new Date('2024-06-01T12:00:00Z'), // exactly at deadline
        sla_status: 'on_time',
      });
      TicketService.finalizeSlaStatus(ticket);
      expect(ticket.sla_status).toBe('on_time');
    });

    it('sets sla_status to "on_time" when completed before deadline', () => {
      const deadline = new Date('2024-06-01T12:00:00Z');
      const ticket = makeTicket({
        sla_deadline: deadline,
        completedAt: new Date('2024-06-01T10:00:00Z'), // 2 hours early
        sla_status: 'at_risk',
      });
      TicketService.finalizeSlaStatus(ticket);
      expect(ticket.sla_status).toBe('on_time');
    });

    it('sets sla_status to "on_time" when completed 1ms before deadline', () => {
      const deadline = new Date('2024-06-01T12:00:00.000Z');
      const ticket = makeTicket({
        sla_deadline: deadline,
        completedAt: new Date('2024-06-01T11:59:59.999Z'),
        sla_status: 'at_risk',
      });
      TicketService.finalizeSlaStatus(ticket);
      expect(ticket.sla_status).toBe('on_time');
    });
  });

  describe('when completedAt > sla_deadline (overdue)', () => {
    it('keeps sla_status as "overdue" when completed after deadline', () => {
      const deadline = new Date('2024-06-01T12:00:00Z');
      const ticket = makeTicket({
        sla_deadline: deadline,
        completedAt: new Date('2024-06-01T14:00:00Z'), // 2 hours late
        sla_status: 'overdue',
      });
      TicketService.finalizeSlaStatus(ticket);
      expect(ticket.sla_status).toBe('overdue');
    });

    it('does NOT change sla_status to "on_time" when overdue', () => {
      const deadline = new Date('2024-06-01T12:00:00Z');
      const ticket = makeTicket({
        sla_deadline: deadline,
        completedAt: new Date('2024-06-02T00:00:00Z'), // 12 hours late
        sla_status: 'overdue',
      });
      TicketService.finalizeSlaStatus(ticket);
      expect(ticket.sla_status).not.toBe('on_time');
    });

    it('keeps sla_status as "overdue" when completed 1ms after deadline', () => {
      const deadline = new Date('2024-06-01T12:00:00.000Z');
      const ticket = makeTicket({
        sla_deadline: deadline,
        completedAt: new Date('2024-06-01T12:00:00.001Z'),
        sla_status: 'overdue',
      });
      TicketService.finalizeSlaStatus(ticket);
      expect(ticket.sla_status).toBe('overdue');
    });
  });

  describe('when completedAt is null (uses current time)', () => {
    it('uses current time as completedAt when not set', () => {
      // Set deadline far in the future — current time should be before it
      const futureDeadline = new Date(Date.now() + 10 * 60 * 1000); // +10 min
      const ticket = makeTicket({
        sla_deadline: futureDeadline,
        completedAt: null,
        sla_status: 'on_time',
      });
      TicketService.finalizeSlaStatus(ticket);
      // Current time < future deadline → on_time
      expect(ticket.sla_status).toBe('on_time');
    });

    it('marks overdue when deadline is in the past and completedAt is null', () => {
      const pastDeadline = new Date(Date.now() - 10 * 60 * 1000); // -10 min
      const ticket = makeTicket({
        sla_deadline: pastDeadline,
        completedAt: null,
        sla_status: 'overdue',
      });
      TicketService.finalizeSlaStatus(ticket);
      // Current time > past deadline → overdue stays
      expect(ticket.sla_status).toBe('overdue');
    });
  });

  describe('return value', () => {
    it('always returns the same ticket object (mutates in place)', () => {
      const ticket = makeTicket({
        sla_deadline: new Date('2099-01-01'),
        completedAt: new Date('2024-01-01'),
        sla_status: 'on_time',
      });
      const result = TicketService.finalizeSlaStatus(ticket);
      expect(result).toBe(ticket);
    });
  });
});
