module.exports = (name, activationLink) => {
  return `
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Account Activation</title>
        <style>
            body {
                font-family: Arial, sans-serif;
                background-color: #f4f4f4;
                margin: 0;
                padding: 0;
            }
            .container {
                width: 100%;
                max-width: 600px;
                margin: 0 auto;
                background-color: #ffffff;
                padding: 20px;
                border-radius: 8px;
                box-shadow: 0 0 10px rgba(0, 0, 0, 0.1);
            }
            .header {
                background-color: #2688d4;
                color: #ffffff;
                padding: 10px 20px;
                text-align: center;
                border-radius: 8px 8px 0 0;
            }
            .content {
                padding: 20px;
                text-align: center;
            }
            .button {
                display: inline-block;
                background-color: #2688d4;
                color: #ffffff;
                padding: 10px 20px;
                text-decoration: none;
                border-radius: 5px;
                margin-top: 20px;
            }
            .footer {
                text-align: center;
                padding: 20px;
                font-size: 12px;
                color: #888888;
            }
        </style>
    </head>
    <body>
        <div class="container">
            <div class="header">
                <h2>Account Activation</h2>
            </div>
            <div class="content">
                <p>Hello ${name},</p>
                <p>Thank you for registering with FieldCheck! Please activate your account by clicking the button below:</p>
                <a href="${activationLink}" class="button">Activate Account</a>
                <p>If the button above does not work, please copy and paste the following link into your web browser:</p>
                <p>${activationLink}</p>
                <p>Best regards,</p>
                <p>The FieldCheck Team</p>
            </div>
            <div class="footer">
                <p>&copy; ${new Date().getFullYear()} FieldCheck. All rights reserved.</p>
            </div>
        </div>
    </body>
    </html>
  `;
};