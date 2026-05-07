#!/usr/bin/env node

/**
 * Test Gmail SMTP connectivity and configuration
 * Run: node test_gmail_smtp.js
 * 
 * This script verifies:
 * 1. Environment variables are set correctly
 * 2. SMTP connection can be established to Gmail
 * 3. Authentication works with the provided credentials
 * 4. Email can be sent through Gmail SMTP
 */

const nodemailer = require('nodemailer');
const dotenv = require('dotenv');
const path = require('path');

console.log('🔍 FieldCheck Gmail SMTP Diagnostic Test\n');

// Load environment variables
const envPath = path.join(__dirname, '.env');
console.log(`📋 Loading environment from: ${envPath}\n`);
dotenv.config({ path: envPath });

// Test 1: Check environment variables
console.log('=== TEST 1: Environment Variables ===');
const requiredEnvVars = [
  'EMAIL_HOST',
  'EMAIL_PORT',
  'EMAIL_USERNAME',
  'EMAIL_PASSWORD',
  'EMAIL_FROM'
];

let allEnvVarsSet = true;
requiredEnvVars.forEach(varName => {
  const value = process.env[varName];
  if (value) {
    const displayValue = varName === 'EMAIL_PASSWORD' 
      ? '*'.repeat(Math.max(3, value.length - 4)) + value.substring(value.length - 4)
      : value;
    console.log(`✅ ${varName}: ${displayValue}`);
  } else {
    console.log(`❌ ${varName}: NOT SET`);
    allEnvVarsSet = false;
  }
});

if (!allEnvVarsSet) {
  console.error('\n❌ Missing required environment variables. Please update .env file.\n');
  process.exit(1);
}

// Test 2: Verify Gmail configuration
console.log('\n=== TEST 2: Gmail Configuration ===');
const emailUsername = process.env.EMAIL_USERNAME;
const isGmail = emailUsername && emailUsername.toLowerCase().includes('@gmail.com');

if (isGmail) {
  console.log(`✅ Gmail account detected: ${emailUsername}`);
} else {
  console.warn(`⚠️  Not a Gmail account. Testing standard SMTP.`);
}

// Test 3: Test SMTP connection
console.log('\n=== TEST 3: SMTP Connection Test ===');

const testSmtpConnection = async () => {
  const transportConfig = {
    host: process.env.EMAIL_HOST,
    port: Number(process.env.EMAIL_PORT) || 587,
    secure: process.env.EMAIL_SECURE === 'true' ? true : false,
    auth: {
      user: process.env.EMAIL_USERNAME,
      pass: process.env.EMAIL_PASSWORD,
    },
    ...(isGmail ? { requireTLS: true } : {}),
    connectionTimeout: 15000,
    greetingTimeout: 15000,
    socketTimeout: 15000,
    tls: {
      minVersion: 'TLSv1.2',
    }
  };

  console.log('\n📝 Transporter Configuration:');
  console.log(`  Host: ${transportConfig.host}`);
  console.log(`  Port: ${transportConfig.port}`);
  console.log(`  Secure: ${transportConfig.secure}`);
  console.log(`  RequireTLS: ${transportConfig.requireTLS || 'not set'}`);
  console.log(`  User: ${transportConfig.auth.user}`);

  try {
    const transporter = nodemailer.createTransport(transportConfig);
    
    console.log('\n🔌 Attempting SMTP connection...');
    const verified = await Promise.race([
      transporter.verify(),
      new Promise((_, reject) => 
        setTimeout(() => reject(new Error('Verification timeout after 12 seconds')), 12000)
      )
    ]);

    console.log('✅ SMTP Connection Successful!');
    console.log('✅ Authentication Successful!');
    
    return transporter;
  } catch (error) {
    console.error('❌ SMTP Connection Failed!');
    console.error(`   Error: ${error.message}`);
    
    if (error.code) {
      console.error(`   Error Code: ${error.code}`);
    }
    
    if (error.responseCode) {
      console.error(`   Response Code: ${error.responseCode}`);
    }
    
    if (error.response) {
      console.error(`   Response: ${error.response}`);
    }

    if (isGmail) {
      console.error('\n💡 Gmail-specific troubleshooting:');
      console.error('   1. Verify you have 2-Factor Authentication enabled');
      console.error('   2. Generate an App Password: https://myaccount.google.com/apppasswords');
      console.error('   3. Use the 16-character password (without spaces) in EMAIL_PASSWORD');
      console.error('   4. Check that "Less secure app access" is enabled (if not using App Password)');
      console.error('   5. Wait 10-15 minutes after enabling App Password before testing');
    }
    
    return null;
  }
};

// Test 4: Test email sending
const testEmailSending = async (transporter) => {
  console.log('\n=== TEST 4: Email Sending Test ===');
  
  const testEmail = {
    from: process.env.EMAIL_FROM || process.env.EMAIL_USERNAME,
    to: process.env.EMAIL_USERNAME, // Send to self
    subject: '[TEST] FieldCheck Gmail SMTP Verification',
    html: `
      <html>
        <head>
          <style>body { font-family: Arial, sans-serif; }</style>
        </head>
        <body>
          <h2>✅ Gmail SMTP Test Successful!</h2>
          <p>This email confirms that your Gmail SMTP configuration is working correctly.</p>
          <p><strong>Sent from:</strong> ${process.env.EMAIL_FROM || process.env.EMAIL_USERNAME}</p>
          <p><strong>Time:</strong> ${new Date().toISOString()}</p>
          <hr>
          <p>If you received this email, your email service is properly configured.</p>
        </body>
      </html>
    `,
    text: 'FieldCheck Gmail SMTP Test - If you received this, your email service is working!'
  };

  try {
    console.log(`\n📧 Sending test email to ${testEmail.to}...`);
    const info = await Promise.race([
      transporter.sendMail(testEmail),
      new Promise((_, reject) =>
        setTimeout(() => reject(new Error('Send email timeout after 15 seconds')), 15000)
      )
    ]);

    console.log('✅ Email Sent Successfully!');
    console.log(`   Message ID: ${info.messageId}`);
    console.log('\n✅ All tests passed! Your Gmail SMTP is properly configured.\n');
    return true;
  } catch (error) {
    console.error('❌ Email Sending Failed!');
    console.error(`   Error: ${error.message}`);
    
    if (error.response) {
      console.error(`   Response: ${error.response}`);
    }
    
    return false;
  }
};

// Run all tests
(async () => {
  try {
    const transporter = await testSmtpConnection();
    
    if (transporter) {
      const success = await testEmailSending(transporter);
      process.exit(success ? 0 : 1);
    } else {
      console.error('\n❌ Cannot proceed with email test - SMTP connection failed.\n');
      process.exit(1);
    }
  } catch (error) {
    console.error('\n❌ Unexpected error during tests:', error.message);
    process.exit(1);
  }
})();
