/**
 * Preservation Property Tests for Email Service
 * 
 * **CRITICAL**: These tests MUST PASS on unfixed code - they verify existing functionality
 * **GOAL**: Ensure fixes don't break existing email system behavior
 * **METHODOLOGY**: Observation-first - observe behavior on UNFIXED code, then write tests
 * 
 * **Validates: Requirements 3.1, 3.2, 3.3, 3.4**
 * 
 * Property 3: Preservation - Email System Existing Functionality
 * 
 * For any email request where the bug condition does NOT hold (SMTP working correctly,
 * service initialized, credentials valid), the fixed sendEmail function SHALL produce
 * exactly the same behavior as the original function, preserving all existing functionality
 * for email templates, attachments, provider selection, and disabled mode.
 */

const sendEmail = require('../../utils/emailService');

describe('Email Service - Preservation Property Tests', () => {
  let originalEnv;

  beforeEach(() => {
    // Save original environment
    originalEnv = { ...process.env };
    
    // Reset console mocks
    jest.clearAllMocks();
  });

  afterEach(() => {
    // Restore original environment
    process.env = originalEnv;
  });

  describe('Property 3.1: Email Disabled Mode (DISABLE_EMAIL=true)', () => {
    /**
     * Preservation Test 1: Email with DISABLE_EMAIL=true uses JSON transport
     * 
     * Observed Behavior on UNFIXED code:
     * - When DISABLE_EMAIL=true, email uses JSON transport (no actual delivery)
     * - Console logs warning: "DISABLE_EMAIL=true (emails will not be delivered)"
     * - sendEmail returns info object with message property (JSON representation)
     * 
     * This behavior MUST be preserved after implementing fixes.
     */
    it('should use JSON transport when DISABLE_EMAIL=true (no actual delivery)', async () => {
      // Configure email disabled mode
      process.env.DISABLE_EMAIL = 'true';
      process.env.EMAIL_FROM = 'test@example.com';
      
      const emailRequest = {
        email: 'user@example.com',
        subject: 'Test Email',
        templateName: 'passwordReset',
        templateData: {
          name: 'Test User',
          resetLink: 'https://example.com/reset',
          resetToken: 'test123'
        }
      };

      const result = await sendEmail(emailRequest);

      // Preservation Assertions:
      // 1. Email returns result (not thrown error)
      expect(result).toBeDefined();
      
      // 2. Result contains message property (JSON transport)
      expect(result.message).toBeDefined();
      
      // 3. Console warns about disabled email
      expect(console.warn).toHaveBeenCalledWith(
        expect.stringContaining('DISABLE_EMAIL=true')
      );
      
      // 4. No actual SMTP connection attempted (no SMTP errors)
      // This is implicit - if SMTP was attempted, test would timeout or fail
    });

    /**
     * Preservation Test 2: Multiple emails in disabled mode
     * 
     * Observed Behavior: Multiple emails can be sent in disabled mode without errors
     */
    it('should handle multiple emails in disabled mode without errors', async () => {
      process.env.DISABLE_EMAIL = 'true';
      process.env.EMAIL_FROM = 'test@example.com';
      
      const emailRequests = [
        {
          email: 'user1@example.com',
          subject: 'Email 1',
          templateName: 'passwordReset',
          templateData: { name: 'User 1', resetLink: 'https://example.com/reset1', resetToken: 'token1' }
        },
        {
          email: 'user2@example.com',
          subject: 'Email 2',
          templateName: 'accountActivation',
          templateData: { name: 'User 2', activationLink: 'https://example.com/activate2' }
        }
      ];

      // Send multiple emails
      const results = await Promise.all(emailRequests.map(req => sendEmail(req)));

      // Preservation Assertions:
      // 1. All emails return results
      expect(results).toHaveLength(2);
      results.forEach(result => {
        expect(result).toBeDefined();
        expect(result.message).toBeDefined();
      });
    });
  });

  describe('Property 3.2: Template Rendering (accountActivation, passwordReset)', () => {
    /**
     * Preservation Test 3: accountActivation template renders correctly
     * 
     * Observed Behavior on UNFIXED code:
     * - accountActivation template uses accountActivationEmail function
     * - Template receives name and activationLink parameters
     * - Returns HTML string with activation link
     * 
     * This behavior MUST be preserved after implementing fixes.
     */
    it('should render accountActivation template with correct parameters', async () => {
      process.env.DISABLE_EMAIL = 'true'; // Use JSON transport to avoid SMTP
      process.env.EMAIL_FROM = 'test@example.com';
      
      const emailRequest = {
        email: 'newemployee@company.com',
        subject: 'Activate your FieldCheck account',
        templateName: 'accountActivation',
        templateData: {
          name: 'Jane Smith',
          activationLink: 'https://fieldcheck-app.onrender.com/activate?token=xyz789'
        }
      };

      const result = await sendEmail(emailRequest);

      // Preservation Assertions:
      // 1. Email sent successfully
      expect(result).toBeDefined();
      
      // 2. Result contains message (JSON transport)
      expect(result.message).toBeDefined();
      
      // 3. Message contains HTML (template rendered)
      const messageStr = JSON.stringify(result.message);
      expect(messageStr).toContain('Jane Smith');
      expect(messageStr).toContain('activate?token=xyz789');
    });

    /**
     * Preservation Test 4: passwordReset template renders correctly
     * 
     * Observed Behavior on UNFIXED code:
     * - passwordReset template uses passwordResetEmail function
     * - Template receives name, resetLink, and resetToken parameters
     * - Returns HTML string with reset link
     * 
     * This behavior MUST be preserved after implementing fixes.
     */
    it('should render passwordReset template with correct parameters', async () => {
      process.env.DISABLE_EMAIL = 'true';
      process.env.EMAIL_FROM = 'test@example.com';
      
      const emailRequest = {
        email: 'user@example.com',
        subject: 'Reset your FieldCheck password',
        templateName: 'passwordReset',
        templateData: {
          name: 'John Doe',
          resetLink: 'https://fieldcheck-app.onrender.com/reset?token=abc123',
          resetToken: 'abc123'
        }
      };

      const result = await sendEmail(emailRequest);

      // Preservation Assertions:
      // 1. Email sent successfully
      expect(result).toBeDefined();
      
      // 2. Message contains template data
      const messageStr = JSON.stringify(result.message);
      expect(messageStr).toContain('John Doe');
      expect(messageStr).toContain('reset?token=abc123');
    });

    /**
     * Preservation Test 5: Custom message (no template)
     * 
     * Observed Behavior: Email can be sent with custom message instead of template
     */
    it('should send email with custom message (no template)', async () => {
      process.env.DISABLE_EMAIL = 'true';
      process.env.EMAIL_FROM = 'test@example.com';
      
      const emailRequest = {
        email: 'user@example.com',
        subject: 'Custom Email',
        message: '<h1>Custom HTML Message</h1><p>This is a custom email.</p>'
      };

      const result = await sendEmail(emailRequest);

      // Preservation Assertions:
      expect(result).toBeDefined();
      expect(result.message).toBeDefined();
      
      const messageStr = JSON.stringify(result.message);
      expect(messageStr).toContain('Custom HTML Message');
    });
  });

  describe('Property 3.3: Email Attachments Support', () => {
    /**
     * Preservation Test 6: Email with attachments array
     * 
     * Observed Behavior on UNFIXED code:
     * - Email supports attachments array parameter
     * - Attachments are included in mailOptions
     * - Each attachment has filename, content, contentType
     * 
     * This behavior MUST be preserved after implementing fixes.
     */
    it('should include attachments in mailOptions when attachments array provided', async () => {
      process.env.DISABLE_EMAIL = 'true';
      process.env.EMAIL_FROM = 'test@example.com';
      
      const emailRequest = {
        email: 'user@example.com',
        subject: 'Email with Attachments',
        message: '<p>Please see attached files.</p>',
        attachments: [
          {
            filename: 'report.pdf',
            content: Buffer.from('PDF content'),
            contentType: 'application/pdf'
          },
          {
            filename: 'image.jpg',
            content: Buffer.from('JPEG content'),
            contentType: 'image/jpeg'
          }
        ]
      };

      const result = await sendEmail(emailRequest);

      // Preservation Assertions:
      // 1. Email sent successfully with attachments
      expect(result).toBeDefined();
      
      // 2. Result contains message
      expect(result.message).toBeDefined();
      
      // Note: In JSON transport mode, attachments are included in the message object
      // We can't directly verify attachment content, but we verify no error is thrown
    });

    /**
     * Preservation Test 7: Email without attachments
     * 
     * Observed Behavior: Email works correctly when attachments array is empty or undefined
     */
    it('should send email successfully when attachments array is empty', async () => {
      process.env.DISABLE_EMAIL = 'true';
      process.env.EMAIL_FROM = 'test@example.com';
      
      const emailRequest = {
        email: 'user@example.com',
        subject: 'Email without Attachments',
        message: '<p>No attachments.</p>',
        attachments: []
      };

      const result = await sendEmail(emailRequest);

      // Preservation Assertions:
      expect(result).toBeDefined();
      expect(result.message).toBeDefined();
    });
  });

  describe('Property 3.4: Provider Selection (EMAIL_PROVIDER env var)', () => {
    /**
     * Preservation Test 8: EMAIL_PROVIDER=gmail_api uses Gmail API directly
     * 
     * Observed Behavior on UNFIXED code:
     * - When EMAIL_PROVIDER=gmail_api, system uses Gmail API as primary provider
     * - Gmail API is NOT used as fallback, but as primary delivery method
     * - Requires CLIENT_ID, CLIENT_SECRET, REFRESH_TOKEN, EMAIL_USER env vars
     * 
     * This behavior MUST be preserved after implementing fixes.
     */
    it('should use Gmail API directly when EMAIL_PROVIDER=gmail_api', async () => {
      // Configure Gmail API as primary provider
      process.env.DISABLE_EMAIL = 'false';
      process.env.EMAIL_PROVIDER = 'gmail_api';
      process.env.CLIENT_ID = 'test_client_id';
      process.env.CLIENT_SECRET = 'test_client_secret';
      process.env.REFRESH_TOKEN = 'test_refresh_token';
      process.env.EMAIL_USER = 'test@gmail.com';
      process.env.EMAIL_FROM = 'test@gmail.com';
      
      // Remove SMTP config to ensure Gmail API is used
      delete process.env.EMAIL_HOST;
      delete process.env.EMAIL_USERNAME;
      delete process.env.EMAIL_PASSWORD;
      
      const emailRequest = {
        email: 'user@example.com',
        subject: 'Test Gmail API',
        message: '<p>Test email via Gmail API</p>'
      };

      // Mock Gmail API OAuth2 and request
      const { OAuth2Client } = require('google-auth-library');
      const originalGetAccessToken = OAuth2Client.prototype.getAccessToken;
      OAuth2Client.prototype.getAccessToken = jest.fn().mockResolvedValue({
        token: 'mock_access_token'
      });

      const https = require('https');
      const originalRequest = https.request;
      https.request = jest.fn((options, callback) => {
        if (options.hostname === 'gmail.googleapis.com') {
          const mockRes = {
            statusCode: 200,
            on: jest.fn((event, handler) => {
              if (event === 'data') {
                handler(JSON.stringify({ id: 'gmail-message-id' }));
              }
              if (event === 'end') {
                handler();
              }
            })
          };
          setTimeout(() => callback(mockRes), 100);
          return {
            on: jest.fn(),
            write: jest.fn(),
            end: jest.fn()
          };
        }
        return originalRequest.apply(https, arguments);
      });

      try {
        const result = await sendEmail(emailRequest);

        // Preservation Assertions:
        // 1. Email delivered via Gmail API
        expect(result).toBeDefined();
        expect(result.provider).toBe('gmail_api');
        
        // 2. Console logs Gmail API delivery
        expect(console.log).toHaveBeenCalledWith(
          expect.stringContaining('delivered via Gmail API'),
          expect.any(Object)
        );
      } finally {
        OAuth2Client.prototype.getAccessToken = originalGetAccessToken;
        https.request = originalRequest;
      }
    });

    /**
     * Preservation Test 9: Working SMTP delivers via SMTP without fallback
     * 
     * Observed Behavior on UNFIXED code:
     * - When SMTP is configured and working, email delivers via SMTP
     * - No fallback to Resend or Gmail API when SMTP succeeds
     * - Console does NOT log fallback messages
     * 
     * This behavior MUST be preserved after implementing fixes.
     */
    it('should deliver via SMTP without fallback when SMTP is working', async () => {
      // Configure working SMTP (using JSON transport to simulate success)
      process.env.DISABLE_EMAIL = 'false';
      process.env.EMAIL_HOST = 'smtp.example.com';
      process.env.EMAIL_PORT = '587';
      process.env.EMAIL_USERNAME = 'test@example.com';
      process.env.EMAIL_PASSWORD = 'testpass';
      process.env.EMAIL_FROM = 'test@example.com';
      
      // Remove fallback providers
      delete process.env.RESEND_API_KEY;
      delete process.env.CLIENT_ID;
      delete process.env.CLIENT_SECRET;
      delete process.env.REFRESH_TOKEN;
      
      const emailRequest = {
        email: 'user@example.com',
        subject: 'Test SMTP',
        message: '<p>Test email via SMTP</p>'
      };

      // Mock nodemailer to simulate successful SMTP delivery
      const nodemailer = require('nodemailer');
      const mockSendMail = jest.fn().mockResolvedValue({
        messageId: 'smtp-message-id',
        accepted: ['user@example.com'],
        response: '250 OK'
      });
      
      const originalCreateTransport = nodemailer.createTransport;
      nodemailer.createTransport = jest.fn().mockReturnValue({
        sendMail: mockSendMail,
        verify: jest.fn().mockResolvedValue(true)
      });

      try {
        const result = await sendEmail(emailRequest);

        // Preservation Assertions:
        // 1. Email delivered successfully
        expect(result).toBeDefined();
        expect(result.messageId).toBe('smtp-message-id');
        
        // 2. No fallback messages logged
        expect(console.warn).not.toHaveBeenCalledWith(
          expect.stringContaining('fallback')
        );
        
        // 3. sendMail was called (SMTP used)
        expect(mockSendMail).toHaveBeenCalled();
      } finally {
        nodemailer.createTransport = originalCreateTransport;
      }
    });

    /**
     * Preservation Test 10: Resend API as primary provider
     * 
     * Observed Behavior: When SMTP not configured but Resend API is, Resend is used as primary
     */
    it('should use Resend API as primary provider when SMTP not configured', async () => {
      // Configure Resend API only (no SMTP)
      process.env.DISABLE_EMAIL = 'false';
      process.env.RESEND_API_KEY = 'test_resend_key';
      process.env.EMAIL_FROM = 'test@example.com';
      
      // Remove SMTP config
      delete process.env.EMAIL_HOST;
      delete process.env.EMAIL_USERNAME;
      delete process.env.EMAIL_PASSWORD;
      delete process.env.EMAIL_PROVIDER;
      
      const emailRequest = {
        email: 'user@example.com',
        subject: 'Test Resend',
        message: '<p>Test email via Resend</p>'
      };

      // Mock Resend API
      const https = require('https');
      const originalRequest = https.request;
      https.request = jest.fn((options, callback) => {
        if (options.hostname === 'api.resend.com') {
          const mockRes = {
            statusCode: 200,
            on: jest.fn((event, handler) => {
              if (event === 'data') {
                handler(JSON.stringify({ id: 'resend-message-id' }));
              }
              if (event === 'end') {
                handler();
              }
            })
          };
          setTimeout(() => callback(mockRes), 100);
          return {
            on: jest.fn(),
            write: jest.fn(),
            end: jest.fn()
          };
        }
        return originalRequest.apply(https, arguments);
      });

      try {
        const result = await sendEmail(emailRequest);

        // Preservation Assertions:
        // 1. Email delivered via Resend
        expect(result).toBeDefined();
        expect(result.provider).toBe('resend');
        
        // 2. Console logs Resend delivery
        expect(console.log).toHaveBeenCalledWith(
          expect.stringContaining('delivered via Resend'),
          expect.any(Object)
        );
      } finally {
        https.request = originalRequest;
      }
    });
  });

  describe('Property 3: Preservation - Overall Behavior', () => {
    /**
     * Preservation Test 11: Email FROM address respects EMAIL_FROM env var
     * 
     * Observed Behavior: Email FROM address uses EMAIL_FROM env var or default
     */
    it('should use EMAIL_FROM env var for from address', async () => {
      process.env.DISABLE_EMAIL = 'true';
      process.env.EMAIL_FROM = 'custom@fieldcheck.com';
      
      const emailRequest = {
        email: 'user@example.com',
        subject: 'Test FROM',
        message: '<p>Test email</p>'
      };

      const result = await sendEmail(emailRequest);

      // Preservation Assertions:
      expect(result).toBeDefined();
      expect(result.message).toBeDefined();
      
      // FROM address is included in the message
      const messageStr = JSON.stringify(result.message);
      expect(messageStr).toContain('custom@fieldcheck.com');
    });

    /**
     * Preservation Test 12: Email logging format consistency
     * 
     * Observed Behavior: Email operations log to console with consistent format
     */
    it('should maintain consistent logging format for email operations', async () => {
      process.env.DISABLE_EMAIL = 'true';
      process.env.EMAIL_FROM = 'test@example.com';
      
      // Clear previous logs
      jest.clearAllMocks();
      
      const emailRequest = {
        email: 'user@example.com',
        subject: 'Test Logging',
        message: '<p>Test email</p>'
      };

      await sendEmail(emailRequest);

      // Preservation Assertions:
      // 1. Console.warn called for email operations
      expect(console.warn).toHaveBeenCalled();
      
      // 2. At least one log message contains "Email:" prefix
      const warnCalls = console.warn.mock.calls;
      const hasEmailPrefix = warnCalls.some(call => 
        call.some(arg => typeof arg === 'string' && arg.includes('Email:'))
      );
      expect(hasEmailPrefix).toBe(true);
    });

    /**
     * Preservation Test 13: Error handling for missing configuration
     * 
     * Observed Behavior: Clear error when email not configured in production
     */
    it('should throw clear error when email not configured in production', async () => {
      // Configure production environment with no email providers
      process.env.NODE_ENV = 'production';
      process.env.DISABLE_EMAIL = 'false';
      delete process.env.EMAIL_HOST;
      delete process.env.EMAIL_USERNAME;
      delete process.env.EMAIL_PASSWORD;
      delete process.env.RESEND_API_KEY;
      delete process.env.CLIENT_ID;
      delete process.env.CLIENT_SECRET;
      delete process.env.REFRESH_TOKEN;
      
      const emailRequest = {
        email: 'user@example.com',
        subject: 'Test Error',
        message: '<p>Test email</p>'
      };

      // Preservation Assertions:
      // Should throw error with clear message
      await expect(sendEmail(emailRequest)).rejects.toThrow('Email service not configured');
    });
  });
});
