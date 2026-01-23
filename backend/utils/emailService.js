const nodemailer = require('nodemailer');
const accountActivationEmail = require('./templates/accountActivationEmail');
const passwordResetEmail = require('./templates/passwordResetEmail');

const sendEmail = async (options) => {
  // Dev bypass: allow disabling emails entirely
  const disableEmail = process.env.DISABLE_EMAIL === 'true';

  let transporter;
  if (disableEmail) {
    // Use JSON transport so sendMail succeeds without SMTP
    transporter = nodemailer.createTransport({ jsonTransport: true });
  } else if (process.env.EMAIL_HOST) {
    transporter = nodemailer.createTransport({
      host: process.env.EMAIL_HOST,
      port: Number(process.env.EMAIL_PORT || 587),
      secure: process.env.EMAIL_SECURE === 'true',
      auth: {
        user: process.env.EMAIL_USERNAME,
        pass: process.env.EMAIL_PASSWORD,
      },
    });
  } else {
    // Fallback when no SMTP configured: still succeed in dev
    transporter = nodemailer.createTransport({ jsonTransport: true });
  }

  let html = options.message || '';
  if (options.templateName === 'accountActivation') {
    const { name, activationLink } = options.templateData || {};
    html = accountActivationEmail(name || 'User', activationLink || '#');
  } else if (options.templateName === 'passwordReset') {
    const { name, resetLink } = options.templateData || {};
    html = passwordResetEmail(name || 'User', resetLink || '#');
  }

  const mailOptions = {
    from: process.env.EMAIL_FROM || 'FieldCheck <noreply@fieldcheck.com>',
    to: options.email,
    subject: options.subject,
    html,
    attachments: options.attachments || [],
  };

  await transporter.sendMail(mailOptions);
};

module.exports = sendEmail;