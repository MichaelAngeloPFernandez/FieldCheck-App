/**
 * Email template for when a client ticket is assigned to an employee
 * Sent to the client to let them know their ticket is being worked on
 */

module.exports = (clientName, ticketNumber, employeeName, serviceType) => {
  return `
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Your Ticket is Being Worked On</title>
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
                background-color: #2196f3;
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
                background-color: #e3f2fd;
                border-left: 4px solid #2196f3;
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
                color: #2196f3;
            }
            .content {
                padding: 0 20px;
            }
            .employee-info {
                background-color: #f0f7ff;
                border: 1px solid #90caf9;
                padding: 15px;
                border-radius: 4px;
                margin: 20px 0;
            }
            .employee-info h3 {
                margin-top: 0;
                color: #2196f3;
            }
            .status-box {
                background-color: #fff9e6;
                border-left: 4px solid #ffc107;
                padding: 15px;
                border-radius: 4px;
                margin: 20px 0;
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
                <h1>👷 Your Ticket is Being Worked On</h1>
            </div>
            
            <div class="content">
                <p>Hello <strong>${clientName}</strong>,</p>
                
                <p>Great news! Your support request has been assigned to our team and work has begun. We're committed to resolving your issue as quickly as possible.</p>
                
                <div class="ticket-info">
                    <p class="ticket-number">Ticket #: ${ticketNumber}</p>
                    <p><strong>Service Type:</strong> ${serviceType.replace(/_/g, ' ').charAt(0).toUpperCase() + serviceType.replace(/_/g, ' ').slice(1)}</p>
                    <p><strong>Status:</strong> In Progress</p>
                </div>
                
                <div class="employee-info">
                    <h3>👤 Your Assigned Technician</h3>
                    <p><strong>${employeeName}</strong> has been assigned to your ticket and is currently working on your request. You will receive email updates with progress notes as the work continues.</p>
                </div>
                
                <div class="status-box">
                    <p><strong>⏱️ Expected Timeline:</strong> We aim to complete this within 7 business days. You will be notified as soon as your ticket is completed.</p>
                    <p>If you have any urgent updates or additional information to share, please reply to this email or submit a new ticket.</p>
                </div>
                
                <p>Thank you for choosing FieldCheck! We appreciate your patience and will keep you informed every step of the way.</p>
                
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
