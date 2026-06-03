const nodemailer = require('nodemailer');
const https = require('https');
const { OAuth2Client } = require('google-auth-library');
const accountActivationEmail = require('./templates/accountActivationEmail');
const passwordResetEmail = require('./templates/passwordResetEmail');
const ticketStatusUpdateEmail = require('./templates/ticketStatusUpdateEmail');
const { generateEmailToken } = require('./emailTokenGenerator');

let didLogEmailMode = false;

function buildTransportConfig() {
  const disableEmail = process.env.DISABLE_EMAIL === 'true';

  const username = process.env.EMAIL_USERNAME || process.env.EMAIL_USER;
  const password = process.env.EMAIL_PASSWORD || process.env.EMAIL_PASS;

  const useGmailDefaults =
    (process.env.EMAIL_PROVIDER || '').toString().trim().toLowerCase() === 'gmail' ||
    (typeof username === 'string' && username.toLowerCase().includes('@gmail.com'));

  const host = process.env.EMAIL_HOST || (useGmailDefaults ? 'smtp.gmail.com' : undefined);
  const portRaw = process.env.EMAIL_PORT || (useGmailDefaults ? '587' : undefined);
  const secureExplicit = process.env.EMAIL_SECURE;
  const port = Number(portRaw || 587);
  const secure =
    typeof secureExplicit === 'string'
      ? secureExplicit === 'true'
      : port === 465;

  const hasSmtp = Boolean(host && username && password);
  
  return {
    disableEmail,
    hasSmtp,
    isGmail: useGmailDefaults,
    smtp: {
      host,
      port,
      secure,
      auth: {
        user: username,
        pass: password,
      },
      // Gmail commonly requires STARTTLS on 587.
      ...(useGmailDefaults ? { requireTLS: true } : {}),
      // Avoid hanging connections on providers that are slow or blocked.
      connectionTimeout: 15000,
      greetingTimeout: 15000,
      socketTimeout: 15000, // Reduced from 30000 to 15000 for faster fallback
      tls: {
        minVersion: 'TLSv1.2',
      },
    },
  };
}

function logEmailModeOnce(config) {
  if (didLogEmailMode) return;
  didLogEmailMode = true;

  if (config.disableEmail) {
    console.warn('Email: DISABLE_EMAIL=true (emails will not be delivered)');
    return;
  }

  if (config.hasSmtp) {
    console.log(
      `Email: SMTP enabled host=${config.smtp.host} user=${config.smtp.auth.user}`,
    );
    return;
  }

  console.warn('Email: SMTP not configured; using dev JSON transport (no delivery)');
}

function withTimeout(promise, ms, label) {
  let t;
  const timeoutPromise = new Promise((_, reject) => {
    t = setTimeout(() => reject(new Error(`${label} timed out`)), ms);
  });
  return Promise.race([promise, timeoutPromise]).finally(() => clearTimeout(t));
}

function _sendWithResend({ from, to, subject, html }) {
  return new Promise((resolve, reject) => {
    const apiKey = (process.env.RESEND_API_KEY || '').toString().trim();
    if (!apiKey) {
      return reject(new Error('RESEND_API_KEY not set'));
    }

    const payload = JSON.stringify({
      from,
      to,
      subject,
      html,
    });

    const req = https.request(
      {
        method: 'POST',
        hostname: 'api.resend.com',
        path: '/emails',
        headers: {
          Authorization: `Bearer ${apiKey}`,
          'Content-Type': 'application/json',
          'Content-Length': Buffer.byteLength(payload),
        },
      },
      (res) => {
        let body = '';
        res.on('data', (chunk) => {
          body += chunk;
        });
        res.on('end', () => {
          if (res.statusCode && res.statusCode >= 200 && res.statusCode < 300) {
            return resolve({ statusCode: res.statusCode, body });
          }
          return reject(new Error(`Resend failed (${res.statusCode}): ${body}`));
        });
      },
    );

    req.on('error', reject);
    req.write(payload);
    req.end();
  });
}

function _sendWithGmailApi({ from, to, subject, html }) {
  return new Promise(async (resolve, reject) => {
    try {
      const clientId = (process.env.CLIENT_ID || '').toString().trim();
      const clientSecret = (process.env.CLIENT_SECRET || '').toString().trim();
      const refreshToken = (process.env.REFRESH_TOKEN || '').toString().trim();
      const emailUser = (process.env.EMAIL_USER || process.env.EMAIL_USERNAME || '').toString().trim();

      if (!clientId || !clientSecret || !refreshToken || !emailUser) {
        return reject(new Error('Gmail API OAuth env not fully set (CLIENT_ID/CLIENT_SECRET/REFRESH_TOKEN/EMAIL_USER)'));
      }

      const oauth2Client = new OAuth2Client(clientId, clientSecret);
      oauth2Client.setCredentials({ refresh_token: refreshToken });

      const accessTokenResponse = await oauth2Client.getAccessToken();
      const accessToken =
        accessTokenResponse && typeof accessTokenResponse === 'object'
          ? accessTokenResponse.token
          : accessTokenResponse;

      if (!accessToken) {
        return reject(new Error('Failed to obtain Gmail API access token'));
      }

      const rawLines = [
        `From: ${from}`,
        `To: ${to}`,
        `Subject: ${subject}`,
        'MIME-Version: 1.0',
        'Content-Type: text/html; charset="UTF-8"',
        'Content-Transfer-Encoding: 7bit',
        '',
        html || '',
      ];
      const raw = rawLines.join('\r\n');
      const encodedMessage = Buffer.from(raw)
        .toString('base64')
        .replace(/\+/g, '-')
        .replace(/\//g, '_')
        .replace(/=+$/g, '');

      const payload = JSON.stringify({ raw: encodedMessage });
      const req = https.request(
        {
          method: 'POST',
          hostname: 'gmail.googleapis.com',
          path: '/gmail/v1/users/me/messages/send',
          headers: {
            Authorization: `Bearer ${accessToken}`,
            'Content-Type': 'application/json',
            'Content-Length': Buffer.byteLength(payload),
          },
        },
        (res) => {
          let body = '';
          res.on('data', (chunk) => {
            body += chunk;
          });
          res.on('end', () => {
            if (res.statusCode && res.statusCode >= 200 && res.statusCode < 300) {
              return resolve({ statusCode: res.statusCode, body });
            }
            return reject(new Error(`Gmail API failed (${res.statusCode}): ${body}`));
          });
        },
      );
      req.on('error', reject);
      req.write(payload);
      req.end();
    } catch (e) {
      return reject(e);
    }
  });
}

/**
 * Initialize and verify email service configuration at server startup.
 * Checks available providers (SMTP, Resend API, Gmail API) and logs their status.
 * @returns {Promise<Object>} Initialization result with provider status
 */
const initializeEmailService = async () => {
  const config = buildTransportConfig();
  const result = {
    initialized: true,
    providers: {
      smtp: { available: false, verified: false },
      resend: { available: false, verified: false },
      gmailApi: { available: false, verified: false },
    },
    mode: 'none',
  };

  // Check if email is disabled
  if (config.disableEmail) {
    result.mode = 'disabled';
    console.warn('Email: DISABLE_EMAIL=true (emails will not be delivered)');
    return result;
  }

  // Check SMTP configuration
  if (config.hasSmtp) {
    result.providers.smtp.available = true;
    result.mode = 'smtp';
    console.log(
      `Email: SMTP configured host=${config.smtp.host} user=${config.smtp.auth.user}`,
    );

    // Optionally verify SMTP connectivity
    if (process.env.EMAIL_VERIFY === 'true') {
      try {
        const transporter = nodemailer.createTransport({
          ...config.smtp,
          logger: false,
          debug: false,
        });
        await withTimeout(transporter.verify(), 12000, 'smtpVerify');
        result.providers.smtp.verified = true;
        console.log('Email: SMTP verification successful');
      } catch (e) {
        console.error('Email: SMTP verification failed', {
          host: config.smtp.host,
          port: config.smtp.port,
          user: config.smtp.auth.user,
          isGmail: config.isGmail,
          error: e && e.message ? e.message : String(e),
          code: e && e.code ? e.code : undefined,
          responseCode: e && e.responseCode ? e.responseCode : undefined,
          response: e && e.response ? String(e.response).substring(0, 100) : undefined,
          // Additional diagnostic info for Gmail
          ...(config.isGmail ? {
            diagnosis: 'Gmail SMTP failure - likely causes:',
            possibleReasons: [
              '1. Gmail App Password is incorrect or revoked',
              '2. Less secure app access is not enabled for this account',
              '3. 2FA needs to be enabled and app password must be generated',
              '4. Server cannot reach smtp.gmail.com on port 587',
              '5. ISP blocks SMTP port 587'
            ]
          } : {})
        });
      }
    }
  }

  // Check Resend API configuration
  const resendApiKey = (process.env.RESEND_API_KEY || '').toString().trim();
  if (resendApiKey) {
    result.providers.resend.available = true;
    if (!config.hasSmtp) {
      result.mode = 'resend';
    }
    console.log('Email: Resend API configured (available as fallback)');
  }

  // Check Gmail API configuration
  const hasGmailApiEnv =
    (process.env.CLIENT_ID || '').toString().trim() &&
    (process.env.CLIENT_SECRET || '').toString().trim() &&
    (process.env.REFRESH_TOKEN || '').toString().trim() &&
    (process.env.EMAIL_USER || process.env.EMAIL_USERNAME || '').toString().trim();

  if (hasGmailApiEnv) {
    result.providers.gmailApi.available = true;
    const provider = (process.env.EMAIL_PROVIDER || '').toString().trim().toLowerCase();
    const preferGmailApi = provider === 'gmail_api' || provider === 'gmailapi' || provider === 'gmail-api';
    if (preferGmailApi) {
      result.mode = 'gmail_api';
    }
    console.log('Email: Gmail API configured (available as fallback)');
  }

  // Warn if no providers configured in production
  if (process.env.NODE_ENV === 'production' && result.mode === 'none') {
    console.error('Email: No email providers configured in production environment');
    result.initialized = false;
  }

  return result;
};

const sendEmail = async (options) => {
  // Dev bypass: allow disabling emails entirely
  const config = buildTransportConfig();
  logEmailModeOnce(config);

  const resendApiKey = (process.env.RESEND_API_KEY || '').toString().trim();
  const hasResend = Boolean(resendApiKey);

  if (!config.disableEmail && process.env.NODE_ENV === 'production' && !config.hasSmtp && !hasResend) {
    throw new Error('Email service not configured');
  }

  const transportMode = config.disableEmail
    ? 'disabled-json'
    : config.hasSmtp
      ? 'smtp'
      : 'dev-json';

  let transporter;
  try {
    transporter = config.disableEmail || !config.hasSmtp
      ? nodemailer.createTransport({ jsonTransport: true })
      : nodemailer.createTransport({
          ...config.smtp,
          logger: process.env.EMAIL_DEBUG === 'true',
          debug: process.env.EMAIL_DEBUG === 'true',
        });
  } catch (e) {
    console.error('Email: failed to create transporter', {
      mode: transportMode,
      host: config.smtp && config.smtp.host,
      port: config.smtp && config.smtp.port,
      secure: config.smtp && config.smtp.secure,
      user: config.smtp && config.smtp.auth && config.smtp.auth.user,
      error: e && e.message ? e.message : String(e),
    });
    throw e;
  }

  // Optional: verify SMTP connectivity/credentials (useful on Render).
  if (transportMode === 'smtp' && process.env.EMAIL_VERIFY === 'true') {
    try {
      await withTimeout(transporter.verify(), 12000, 'smtpVerify');
    } catch (e) {
      console.error('Email: transporter.verify failed', {
        host: config.smtp && config.smtp.host,
        port: config.smtp && config.smtp.port,
        secure: config.smtp && config.smtp.secure,
        user: config.smtp && config.smtp.auth && config.smtp.auth.user,
        error: e && e.message ? e.message : String(e),
        code: e && e.code ? e.code : undefined,
        response: e && e.response ? e.response : undefined,
        responseCode: e && e.responseCode ? e.responseCode : undefined,
      });
      throw e;
    }
  }

  let html = options.message || '';
  if (options.templateName === 'accountActivation') {
    const { name, activationLink } = options.templateData || {};
    html = accountActivationEmail(name || 'User', activationLink || '#');
  } else if (options.templateName === 'passwordReset') {
    const { name, resetLink, resetToken } = options.templateData || {};
    html = passwordResetEmail(name || 'User', resetLink || '', resetToken || '');
  }

  const mailOptions = {
    from: process.env.EMAIL_FROM || 'FieldCheck <noreply@fieldcheck.com>',
    to: options.email,
    subject: options.subject,
    html,
    attachments: options.attachments || [],
  };

  const provider = (process.env.EMAIL_PROVIDER || '').toString().trim().toLowerCase();
  const preferGmailApi = provider === 'gmail_api' || provider === 'gmailapi' || provider === 'gmail-api';
  const preferResend = provider === 'resend';
  const hasGmailApiEnv =
    (process.env.CLIENT_ID || '').toString().trim() &&
    (process.env.CLIENT_SECRET || '').toString().trim() &&
    (process.env.REFRESH_TOKEN || '').toString().trim() &&
    (process.env.EMAIL_USER || process.env.EMAIL_USERNAME || '').toString().trim();

  try {
    // If Resend is explicitly preferred OR SMTP not configured but Resend is available, try Resend first
    if (!config.disableEmail && hasResend && (preferResend || !config.hasSmtp)) {
      const from = mailOptions.from;
      const to = Array.isArray(mailOptions.to) ? mailOptions.to.join(',') : String(mailOptions.to);

      try {
        await withTimeout(
          _sendWithResend({ from, to, subject: mailOptions.subject, html }),
          12000,
          'resend',
        );
        console.log('Email: delivered via Resend', {
          to: mailOptions.to,
          subject: mailOptions.subject,
        });
        return { provider: 'resend' };
      } catch (resendErr) {
        const hasFallback = config.hasSmtp || preferGmailApi || !!hasGmailApiEnv;
        if (!hasFallback) throw resendErr;

        console.warn('Email: Resend failed; falling back to alternate provider', {
          to: mailOptions.to,
          subject: mailOptions.subject,
          error: resendErr && resendErr.message ? resendErr.message : String(resendErr),
        });
      }
    }

    // If Gmail API is explicitly preferred OR SMTP not configured but Gmail API is available, try Gmail API first
    if (!config.disableEmail && hasGmailApiEnv && (preferGmailApi || (!config.hasSmtp && !hasResend))) {
      const from = mailOptions.from;
      const to = Array.isArray(mailOptions.to) ? mailOptions.to.join(',') : String(mailOptions.to);
      await withTimeout(
        _sendWithGmailApi({ from, to, subject: mailOptions.subject, html }),
        12000,
        'gmailApi',
      );
      console.log('Email: delivered via Gmail API', {
        to: mailOptions.to,
        subject: mailOptions.subject,
      });
      return { provider: 'gmail_api' };
    }

    // Default: try SMTP (if configured), with Resend/Gmail API as fallbacks
    const info = await withTimeout(
      transporter.sendMail(mailOptions),
      15000, // Reduced from 30000 to 15000 for faster fallback
      'sendMail',
    );

    if (transportMode !== 'smtp') {
      console.warn('Email: sent using non-SMTP transport (no delivery)', {
        mode: transportMode,
        to: mailOptions.to,
        subject: mailOptions.subject,
        preview: info && info.message ? info.message : undefined,
      });
    }
    return info;
  } catch (e) {
    const code = e && e.code ? String(e.code) : '';
    const msg = e && e.message ? String(e.message) : '';

    const isTimeout =
      code === 'ETIMEDOUT' ||
      msg.toLowerCase().includes('timed out') ||
      msg.toLowerCase().includes('timeout');

    const isAuthError =
      code === 'EAUTH' ||
      msg.toLowerCase().includes('authentication') ||
      msg.toLowerCase().includes('invalid credentials') ||
      msg.toLowerCase().includes('username and password not accepted');

    const isConnectionError =
      code === 'ECONNREFUSED' ||
      code === 'ENOTFOUND' ||
      code === 'ECONNRESET' ||
      msg.toLowerCase().includes('connection refused') ||
      msg.toLowerCase().includes('getaddrinfo');

    // Enhanced fallback logic: trigger for all SMTP failures (timeout, auth, connection)
    const shouldFallback = transportMode === 'smtp' && (isTimeout || isAuthError || isConnectionError);

    // If SMTP fails, optionally fall back to Resend.
    if (shouldFallback && (process.env.RESEND_API_KEY || '').toString().trim()) {
      try {
        const from = mailOptions.from;
        const to = Array.isArray(mailOptions.to) ? mailOptions.to.join(',') : String(mailOptions.to);
        await withTimeout(
          _sendWithResend({ from, to, subject: mailOptions.subject, html }),
          12000,
          'resend',
        );
        const reason = isTimeout ? 'timed out' : isAuthError ? 'authentication failed' : 'connection failed';
        console.warn(`Email: SMTP ${reason}; delivered via Resend fallback`, {
          to: mailOptions.to,
          subject: mailOptions.subject,
          smtpError: code || msg,
        });
        return { fallback: 'resend', reason };
      } catch (fallbackErr) {
        console.error('Email: Resend fallback failed', {
          to: mailOptions.to,
          subject: mailOptions.subject,
          error: fallbackErr && fallbackErr.message ? fallbackErr.message : String(fallbackErr),
        });
      }
    }

    // If Resend fallback failed or not available, try Gmail API
    if (
      shouldFallback &&
      (process.env.CLIENT_ID || '').toString().trim() &&
      (process.env.CLIENT_SECRET || '').toString().trim() &&
      (process.env.REFRESH_TOKEN || '').toString().trim()
    ) {
      try {
        const from = mailOptions.from;
        const to = Array.isArray(mailOptions.to) ? mailOptions.to.join(',') : String(mailOptions.to);
        await withTimeout(
          _sendWithGmailApi({ from, to, subject: mailOptions.subject, html }),
          12000,
          'gmailApiFallback',
        );
        const reason = isTimeout ? 'timed out' : isAuthError ? 'authentication failed' : 'connection failed';
        console.warn(`Email: SMTP ${reason}; delivered via Gmail API fallback`, {
          to: mailOptions.to,
          subject: mailOptions.subject,
          smtpError: code || msg,
        });
        return { fallback: 'gmail_api', reason };
      } catch (fallbackErr) {
        console.error('Email: Gmail API fallback failed', {
          to: mailOptions.to,
          subject: mailOptions.subject,
          error: fallbackErr && fallbackErr.message ? fallbackErr.message : String(fallbackErr),
        });
      }
    }

    console.error('Email: sendMail failed', {
      mode: transportMode,
      host: config.smtp && config.smtp.host,
      port: config.smtp && config.smtp.port,
      secure: config.smtp && config.smtp.secure,
      user: config.smtp && config.smtp.auth && config.smtp.auth.user,
      to: mailOptions.to,
      subject: mailOptions.subject,
      error: e && e.message ? e.message : String(e),
      code: e && e.code ? e.code : undefined,
      response: e && e.response ? e.response : undefined,
      responseCode: e && e.responseCode ? e.responseCode : undefined,
    });
    throw e;
  }
};

/**
 * Send status update email to client when their ticket status changes.
 * Uses the existing email service infrastructure with fallback providers.
 * 
 * @param {Object} ticket - ClientTicket object with client information
 * @param {string} newStatus - New status value (in_progress, pending_review, completed, closed)
 * @returns {Promise<Object>} Email send result
 */
const sendStatusUpdateEmail = async (ticket, newStatus) => {
  const { token } = generateEmailToken();
  const frontendUrl = process.env.FRONTEND_URL || 'http://localhost:3000';
  const trackingLink = `${frontendUrl}/client-ticket/${ticket.ticketNumber}?token=${token}`;
  
  const emailHtml = ticketStatusUpdateEmail(
    ticket.clientName,
    ticket.ticketNumber,
    newStatus,
    trackingLink
  );
  
  await sendEmail({
    email: ticket.clientEmail,
    subject: `Ticket Update: ${ticket.ticketNumber} - Status Changed`,
    html: emailHtml
  });
};

module.exports = sendEmail;
module.exports.initializeEmailService = initializeEmailService;
module.exports.sendStatusUpdateEmail = sendStatusUpdateEmail;