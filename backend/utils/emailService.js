const nodemailer = require('nodemailer');
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

  try {
    const info = await withTimeout(
      transporter.sendMail(mailOptions),
      15000,
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