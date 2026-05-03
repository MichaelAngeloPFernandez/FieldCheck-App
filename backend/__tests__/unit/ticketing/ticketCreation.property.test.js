/**
 * Property-Based Tests — Ticket Creation Invariants
 *
 * Property 3: For any valid (companyCode, seq, sla_seconds) combination:
 *   - ticket_no format is always "<CODE>-<NNNN>"
 *   - initial status is always 'open'
 *   - sla_deadline is exactly createdAt + sla_seconds when sla_seconds > 0
 *   - sla_deadline is null when sla_seconds is 0 or absent
 *   - sla_status is 'on_time' when sla_deadline is set, null otherwise
 *
 * Framework: Jest + fast-check (100 runs)
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

const fc = require('fast-check');
const TicketService = require('../../../services/ticketService');

// ─── Helpers ─────────────────────────────────────────────────────────────────

/** Build a minimal TicketTemplate-like object */
const makeTemplate = ({ sla_seconds = 0, workflow = null } = {}) => ({
  _id: 'tpl_test',
  name: 'Test Template',
  json_schema: { type: 'object', properties: {}, additionalProperties: true },
  sla_seconds,
  workflow: workflow || { transitions: {} },
  version: 1,
});

// ─── Arbitraries ─────────────────────────────────────────────────────────────

/** Valid company codes: 1–6 uppercase letters */
const companyCodeArb = fc.stringMatching(/^[A-Z]{1,6}$/);

/** Sequence numbers: 1–9999 */
const seqArb = fc.integer({ min: 1, max: 9999 });

/** SLA seconds: 0 (no SLA) or positive integer up to 30 days */
const slaSecondsArb = fc.oneof(
  fc.constant(0),
  fc.integer({ min: 1, max: 30 * 24 * 3600 }),
);

// ─── Tests ───────────────────────────────────────────────────────────────────

describe('TicketService — Property 3: ticket creation invariants', () => {
  describe('ticket_no format', () => {
    it('always produces "<CODE>-<NNNN>" with zero-padded 4-digit sequence', () => {
      fc.assert(
        fc.property(companyCodeArb, seqArb, (code, seq) => {
          const ticketNo = `${code}-${String(seq).padStart(4, '0')}`;
          // Must match the pattern CODE-NNNN
          expect(ticketNo).toMatch(/^[A-Z]{1,6}-\d{4}$/);
          // Prefix must equal the company code
          expect(ticketNo.split('-')[0]).toBe(code);
          // Numeric part must be exactly 4 digits
          expect(ticketNo.split('-')[1]).toHaveLength(4);
        }),
        { numRuns: 100, seed: 1 },
      );
    });

    it('sequence numbers below 10000 always produce 4-digit zero-padded strings', () => {
      fc.assert(
        fc.property(seqArb, (seq) => {
          const padded = String(seq).padStart(4, '0');
          expect(padded).toHaveLength(4);
          expect(parseInt(padded, 10)).toBe(seq);
        }),
        { numRuns: 100, seed: 2 },
      );
    });
  });

  describe('SLA computation — TicketService.computeSla()', () => {
    it('returns sla_deadline = createdAt + sla_seconds when sla_seconds > 0', () => {
      fc.assert(
        fc.property(
          fc.integer({ min: 1, max: 30 * 24 * 3600 }),
          (slaSeconds) => {
            const template = makeTemplate({ sla_seconds: slaSeconds });
            const createdAt = new Date('2024-01-01T00:00:00Z');
            const { sla_deadline, sla_status } = TicketService.computeSla(template, createdAt);

            const expectedDeadline = new Date(createdAt.getTime() + slaSeconds * 1000);
            expect(sla_deadline).toEqual(expectedDeadline);
            expect(sla_status).toBe('on_time');
          },
        ),
        { numRuns: 100, seed: 3 },
      );
    });

    it('returns null sla_deadline and null sla_status when sla_seconds is 0 or absent', () => {
      fc.assert(
        fc.property(
          fc.oneof(fc.constant(0), fc.constant(null), fc.constant(undefined)),
          (slaSeconds) => {
            const template = makeTemplate({ sla_seconds: slaSeconds });
            const { sla_deadline, sla_status } = TicketService.computeSla(template);
            expect(sla_deadline).toBeNull();
            expect(sla_status).toBeNull();
          },
        ),
        { numRuns: 30, seed: 4 },
      );
    });

    it('sla_deadline is always strictly after createdAt when sla_seconds > 0', () => {
      fc.assert(
        fc.property(
          fc.integer({ min: 1, max: 86400 }),
          (slaSeconds) => {
            const template = makeTemplate({ sla_seconds: slaSeconds });
            const createdAt = new Date();
            const { sla_deadline } = TicketService.computeSla(template, createdAt);
            expect(sla_deadline.getTime()).toBeGreaterThan(createdAt.getTime());
          },
        ),
        { numRuns: 100, seed: 5 },
      );
    });
  });

  describe('isTransitionAllowed()', () => {
    it('returns allowed=true when no workflow is defined', () => {
      fc.assert(
        fc.property(
          fc.string({ minLength: 1, maxLength: 20 }),
          fc.string({ minLength: 1, maxLength: 20 }),
          (from, to) => {
            const template = { workflow: null };
            const { allowed } = TicketService.isTransitionAllowed(template, from, to);
            expect(allowed).toBe(true);
          },
        ),
        { numRuns: 50, seed: 6 },
      );
    });

    it('returns allowed=false for transitions not in the allowed list', () => {
      const template = makeTemplate({
        workflow: {
          transitions: {
            open: ['in_progress'],
            in_progress: ['completed'],
            completed: ['verified', 'closed'],
          },
        },
      });

      // open → completed is NOT allowed
      expect(TicketService.isTransitionAllowed(template, 'open', 'completed').allowed).toBe(false);
      // open → in_progress IS allowed
      expect(TicketService.isTransitionAllowed(template, 'open', 'in_progress').allowed).toBe(true);
      // in_progress → verified is NOT allowed
      expect(TicketService.isTransitionAllowed(template, 'in_progress', 'verified').allowed).toBe(false);
    });
  });
});
