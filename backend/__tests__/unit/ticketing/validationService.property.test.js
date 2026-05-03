/**
 * Property-Based Tests — ValidationService
 *
 * Property 2: For any JSON Schema + data pair, ValidationService.validate()
 * must agree with a fresh AJV instance compiled directly from the same schema.
 *
 * This ensures our wrapper never diverges from the underlying AJV behaviour.
 *
 * Framework: Jest + fast-check (100 runs per property)
 */

const fc = require('fast-check');
const Ajv = require('ajv');
const addFormats = require('ajv-formats');
const validationService = require('../../../services/validationService');

// Reference AJV instance — same config as ValidationService
const refAjv = new Ajv({ allErrors: true, verbose: true });
addFormats(refAjv);

// ─── Arbitraries ─────────────────────────────────────────────────────────────

/** Generates a simple flat JSON Schema with a subset of string/number properties */
const simpleSchemaArb = fc.record({
  type: fc.constant('object'),
  properties: fc.dictionary(
    fc.stringMatching(/^[a-z][a-z0-9_]{0,9}$/),
    fc.oneof(
      fc.record({ type: fc.constant('string') }),
      fc.record({ type: fc.constant('number') }),
      fc.record({ type: fc.constant('boolean') }),
    ),
  ),
  required: fc.array(fc.stringMatching(/^[a-z][a-z0-9_]{0,9}$/), { maxLength: 3 }),
  additionalProperties: fc.boolean(),
});

/** Generates a flat object with mixed value types */
const flatObjectArb = fc.dictionary(
  fc.stringMatching(/^[a-z][a-z0-9_]{0,9}$/),
  fc.oneof(
    fc.string({ maxLength: 20 }),
    fc.integer({ min: -1000, max: 1000 }),
    fc.boolean(),
    fc.constant(null),
  ),
);

// ─── Tests ───────────────────────────────────────────────────────────────────

describe('ValidationService — Property 2: agrees with raw AJV', () => {
  it('valid result matches raw AJV for 100 random schema+data pairs', () => {
    fc.assert(
      fc.property(simpleSchemaArb, flatObjectArb, (schema, data) => {
        const serviceResult = validationService.validate(schema, data);
        const refValidate = refAjv.compile(schema);
        const refValid = refValidate(data);

        // The `valid` flag must agree
        expect(serviceResult.valid).toBe(refValid);

        // When valid, errors array must be empty
        if (serviceResult.valid) {
          expect(serviceResult.errors).toHaveLength(0);
        }

        // When invalid, errors array must be non-empty
        if (!serviceResult.valid) {
          expect(serviceResult.errors.length).toBeGreaterThan(0);
        }
      }),
      { numRuns: 100, seed: 42 },
    );
  });

  it('always returns an object with { valid: boolean, errors: Array }', () => {
    fc.assert(
      fc.property(simpleSchemaArb, flatObjectArb, (schema, data) => {
        const result = validationService.validate(schema, data);
        expect(typeof result.valid).toBe('boolean');
        expect(Array.isArray(result.errors)).toBe(true);
      }),
      { numRuns: 100, seed: 99 },
    );
  });

  it('never throws — even with malformed schemas', () => {
    fc.assert(
      fc.property(fc.anything(), fc.anything(), (schema, data) => {
        expect(() => validationService.validate(schema, data)).not.toThrow();
        const result = validationService.validate(schema, data);
        expect(typeof result.valid).toBe('boolean');
        expect(Array.isArray(result.errors)).toBe(true);
      }),
      { numRuns: 50, seed: 7 },
    );
  });
});
