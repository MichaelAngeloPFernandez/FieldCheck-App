const nodemailer = require('nodemailer');
const https = require('https');
const { OAuth2Client } = require('google-auth-library');
const accountActivationEmail = require('./templates/accountActivationEmail');
const passwordResetEmail = require('./templates/passwordResetEmail');

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
      socketTimeout: 30000,
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

const sendEmail = async (options) => {
  // Dev bypass: allow disabling emails entirely
  const config = buildTransportConfig();
  logEmailModeOnce(config);

  if (!config.disableEmail && process.env.NODE_ENV === 'production' && !config.hasSmtp) {
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

  try {
    if (!config.disableEmail && preferGmailApi) {
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

    const info = await withTimeout(
      transporter.sendMail(mailOptions),
      30000,
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

    // If SMTP is blocked (common on some hosts), optionally fall back to Resend.
    if (transportMode === 'smtp' && isTimeout && (process.env.RESEND_API_KEY || '').toString().trim()) {
      try {
        const from = mailOptions.from;
        const to = Array.isArray(mailOptions.to) ? mailOptions.to.join(',') : String(mailOptions.to);
        await withTimeout(
          _sendWithResend({ from, to, subject: mailOptions.subject, html }),
          12000,
          'resend',
        );
        console.warn('Email: SMTP timed out; delivered via Resend fallback', {
          to: mailOptions.to,
          subject: mailOptions.subject,
        });
        return { fallback: 'resend' };
      } catch (fallbackErr) {
        console.error('Email: Resend fallback failed', {
          to: mailOptions.to,
          subject: mailOptions.subject,
          error: fallbackErr && fallbackErr.message ? fallbackErr.message : String(fallbackErr),
        });
      }
    }

    if (
      transportMode === 'smtp' &&
      isTimeout &&
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
        console.warn('Email: SMTP timed out; delivered via Gmail API fallback', {
          to: mailOptions.to,
          subject: mailOptions.subject,
        });
        return { fallback: 'gmail_api' };
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

module.exports = sendEmail;