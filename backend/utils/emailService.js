const nodemailer = require('nodemailer');
const accountActivationEmail = require('./templates/accountActivationEmail');
const passwordResetEmail = require('./templates/passwordResetEmail');

let didLogEmailMode = false;

function buildTransportConfig() {
  const disableEmail = process.env.DISABLE_EMAIL === 'true';

  const host = process.env.EMAIL_HOST;
  const portRaw = process.env.EMAIL_PORT;
  const secure = process.env.EMAIL_SECURE === 'true';

  const username = process.env.EMAIL_USERNAME || process.env.EMAIL_USER;
  const password = process.env.EMAIL_PASSWORD || process.env.EMAIL_PASS;

  const hasSmtp = Boolean(host && username && password);
  return {
    disableEmail,
    hasSmtp,
    smtp: {
      host,
      port: Number(portRaw || 587),
      secure,
      auth: {
        user: username,
        pass: password,
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

  const transporter = config.disableEmail || !config.hasSmtp
    ? nodemailer.createTransport({ jsonTransport: true })
    : nodemailer.createTransport(config.smtp);

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

  await withTimeout(transporter.sendMail(mailOptions), 15000, 'sendMail');
};

module.exports = sendEmail;