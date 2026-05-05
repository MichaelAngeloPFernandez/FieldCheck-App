module.exports = (ticketNumber, clientName, serviceType, description, trackingLink) => {
  return `
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Ticket Confirmation</title>
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
                padding: 20px;
                text-align: center;
                border-radius: 8px 8px 0 0;
                margin: -20px -20px 20px -20px;
            }
            .header h1 {
                margin: 0;
                font-size: 24px;
            }
            .ticket-info {
                background-color: #f9f9f9;
                border-left: 4px solid #2688d4;
                padding: 15px;
                margin: 20px 0;
                border-radius: 4px;
            }
            .ticket-info p {
                margin: 8px 0;
            }
            .ticket-number {
                font-size: 18px;
                font-weight: bold;
                color: #2688d4;
            }
            .content {
                padding: 0 20px;
            }
            .button {
                display: inline-block;
                background-color: #2688d4;
                color: #ffffff;
                padding: 12px 24px;
                text-decoration: none;
                border-radius: 5px;
                margin-top: 20px;
                font-weight: bold;
            }
            .button:hover {
                background-color: #1a5a9f;
            }
            .footer {
                text-align: center;
                padding: 20px;
                font-size: 12px;
                color: #888888;
                border-top: 1px solid #e0e0e0;
                margin-top: 20px;
            }
        </style>
    </head>
    <body>
        <div class="container">
            <div class="header">
                <h1>🎫 Support Ticket Received</h1>
            </div>
            
            <div class="content">
                <p>Hello <strong>${clientName}</strong>,</p>
                
                <p>Thank you for submitting a support ticket! We have received your request and will get started on it right away.</p>
                
                <div class="ticket-info">
                    <p class="ticket-number">Ticket #: ${ticketNumber}</p>
                    <p><strong>Service Type:</strong> ${serviceType}</p>
                    <p><strong>Submitted:</strong> ${new Date().toLocaleDateString()}</p>
                </div>
                
                <p>Your request details:</p>
                <p style="background-color: #f5f5f5; padding: 10px; border-radius: 4px;">
                    ${description}
                </p>
                
                <p>You can track the status of your ticket at any time using the link below:</p>
                
                <a href="${trackingLink}" class="button">View Ticket Status</a>
                
                <p style="margin-top: 30px;">We will keep you updated via email as we work on your request. If you have any questions, please reply to this email with your ticket number.</p>
                
                <p>Best regards,<br>FieldCheck Support Team</p>
            </div>
            
            <div class="footer">
                <p>This is an automated email. Please do not reply directly to this message.</p>
                <p>Ticket #: ${ticketNumber}</p>
            </div>
        </div>
    </body>
    </html>
  `;
};
