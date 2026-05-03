/**
 * Property-Based Tests — Workflow Transition Enforcement
 *
 * Property 10: For any (fromStatus, toStatus) pair:
 *   - If toStatus is in template.workflow.transitions[fromStatus] → allowed = true
 *   - If toStatus is NOT in that list → allowed = false
 *   - If no workflow is defined → always allowed = true
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

const STATUSES = ['open', 'in_progress', 'completed', 'verified', 'closed', 'rejected'];

const STANDARD_WORKFLOW = {
  transitions: {
    open: ['in_progress'],
    in_progress: ['completed', 'open'],
    completed: ['verified', 'closed'],
    verified: ['closed'],
    closed: [],
    rejected: [],
  },
};

const makeTemplateWithWorkflow = (workflow) => ({
  _id: 'tpl_wf',
  name: 'Workflow Template',
  json_schema: { type: 'object', additionalProperties: true },
  sla_seconds: 0,
  workflow,
});

// ─── Arbitraries ─────────────────────────────────────────────────────────────

const statusArb = fc.constantFrom(...STATUSES);

// ─── Tests ───────────────────────────────────────────────────────────────────

describe('TicketService — Property 10: workflow transition enforcement', () => {
  it('allowed transitions always return allowed=true', () => {
    // Enumerate all explicitly allowed transitions and verify each
    const template = makeTemplateWithWorkflow(STANDARD_WORKFLOW);

    for (const [from, tos] of Object.entries(STANDARD_WORKFLOW.transitions)) {
      for (const to of tos) {
        const { allowed } = TicketService.isTransitionAllowed(template, from, to);
        expect(allowed).toBe(true);
      }
    }
  });

  it('disallowed transitions always return allowed=false', () => {
    fc.assert(
      fc.property(statusArb, statusArb, (from, to) => {
        const template = makeTemplateWithWorkflow(STANDARD_WORKFLOW);
        const allowedList = STANDARD_WORKFLOW.transitions[from] || [];
        const { allowed } = TicketService.isTransitionAllowed(template, from, to);

        if (allowedList.includes(to)) {
          expect(allowed).toBe(true);
        } else {
          expect(allowed).toBe(false);
        }
      }),
      { numRuns: 100, seed: 10 },
    );
  });

  it('returns allowed=true for any transition when workflow is null', () => {
    fc.assert(
      fc.property(statusArb, statusArb, (from, to) => {
        const template = makeTemplateWithWorkflow(null);
        const { allowed } = TicketService.isTransitionAllowed(template, from, to);
        expect(allowed).toBe(true);
      }),
      { numRuns: 100, seed: 11 },
    );
  });

  it('returns allowed=true for any transition when transitions map is missing', () => {
    fc.assert(
      fc.property(statusArb, statusArb, (from, to) => {
        const template = makeTemplateWithWorkflow({ transitions: undefined });
        const { allowed } = TicketService.isTransitionAllowed(template, from, to);
        expect(allowed).toBe(true);
      }),
      { numRuns: 100, seed: 12 },
    );
  });

  it('allowedTransitions array always matches the template definition', () => {
    fc.assert(
      fc.property(statusArb, statusArb, (from, to) => {
        const template = makeTemplateWithWorkflow(STANDARD_WORKFLOW);
        const { allowedTransitions } = TicketService.isTransitionAllowed(template, from, to);
        const expected = STANDARD_WORKFLOW.transitions[from] || [];
        expect(allowedTransitions).toEqual(expected);
      }),
      { numRuns: 100, seed: 13 },
    );
  });

  it('closed status has no allowed outgoing transitions', () => {
    const template = makeTemplateWithWorkflow(STANDARD_WORKFLOW);
    for (const to of STATUSES) {
      const { allowed } = TicketService.isTransitionAllowed(template, 'closed', to);
      expect(allowed).toBe(false);
    }
  });
});
