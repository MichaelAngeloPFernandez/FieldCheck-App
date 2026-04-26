/**
 * ValidationService
 * 
 * Validates ticket data against template JSON Schema using AJV.
 * Provides detailed error messages for form field validation.
 */

const Ajv = require('ajv');
const addFormats = require('ajv-formats');

class ValidationService {
  constructor() {
    this.ajv = new Ajv({ allErrors: true, verbose: true });
    // Add format validators: email, date, time, etc.
    addFormats(this.ajv);
  }

  /**
   * Validate data against schema
   * 
   * @param {Object} schema - JSON Schema v7
   * @param {Object} data - Data to validate
   * @returns {Object} - { valid: boolean, errors: Array }
   */
  validate(schema, data) {
    try {
      const validate = this.ajv.compile(schema);
      const isValid = validate(data);

      if (isValid) {
        return {
          valid: true,
          errors: [],
        };
      }

      // Format errors for client
      const errors = this._formatErrors(validate.errors);
      return {
        valid: false,
        errors,
      };
    } catch (error) {
      return {
        valid: false,
        errors: [
          {
            field: '$schema',
            message: `Schema compilation error: ${error.message}`,
          },
        ],
      };
    }
  }

  /**
   * Format AJV errors to user-friendly messages
   * @private
   */
  _formatErrors(ajvErrors) {
    return (ajvErrors || []).map((err) => {
      const field = err.instancePath || '$root';
      let message = '';

      switch (err.keyword) {
        case 'required':
          message = `Missing required field: ${err.params.missingProperty}`;
          break;
        case 'type':
          message = `${field} must be of type ${err.params.type}`;
          break;
        case 'minLength':
          message = `${field} must be at least ${err.params.minLength} characters`;
          break;
        case 'maxLength':
          message = `${field} must be at most ${err.params.maxLength} characters`;
          break;
        case 'minimum':
          message = `${field} must be at least ${err.params.limit}`;
          break;
        case 'maximum':
          message = `${field} must be at most ${err.params.limit}`;
          break;
        case 'pattern':
          message = `${field} format is invalid`;
          break;
        case 'enum':
          message = `${field} must be one of: ${err.params.allowedValues.join(', ')}`;
          break;
        default:
          message = err.message || 'Validation failed';
      }

      return {
        field,
        message,
        keyword: err.keyword,
      };
    });
  }

  /**
   * Validate multiple objects (batch validation)
   */
  validateBatch(schema, dataArray) {
    return dataArray.map((data) => ({
      data,
      result: this.validate(schema, data),
    }));
  }
}

module.exports = new ValidationService();
