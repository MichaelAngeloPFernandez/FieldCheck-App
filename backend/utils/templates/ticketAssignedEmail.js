module.exports = (employeeName, ticketNumber, clientName, clientEmail, serviceType, description) => {
  return `
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Client Support Ticket Assigned</title>
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
                background-color: #ff9800;
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
                background-color: #fff3e0;
                border-left: 4px solid #ff9800;
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
                color: #ff9800;
            }
            .content {
                padding: 0 20px;
            }
            .client-details {
                background-color: #f5f5f5;
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
                <h1>🎫 Client Support Ticket Assigned</h1>
            </div>
            
            <div class="content">
                <p>Hello <strong>${employeeName}</strong>,</p>
                
                <p>A new client support ticket has been assigned to you. Please review the details below and begin work.</p>
                
                <div class="ticket-info">
                    <p class="ticket-number">Ticket #: ${ticketNumber}</p>
                    <p><strong>Service Type:</strong> ${serviceType}</p>
                    <p><strong>Status:</strong> In Progress</p>
                </div>
                
                <div class="client-details">
                    <h3>Client Information</h3>
                    <p><strong>Client Name:</strong> ${clientName}</p>
                    <p><strong>Client Email:</strong> ${clientEmail}</p>
                </div>
                
                <h3>Client's Request:</h3>
                <p style="background-color: #f5f5f5; padding: 10px; border-radius: 4px;">
                    ${description}
                </p>
                
                <p><strong>Next Steps:</strong></p>
                <ul>
                    <li>Review the ticket details in your task list</li>
                    <li>Begin work on the client's request</li>
                    <li>Keep the client updated via email if needed</li>
                    <li>Submit completed work for admin review</li>
                </ul>
                
                <p>You can contact the client at: <strong>${clientEmail}</strong></p>
                
                <p style="margin-top: 30px;">Thank you for your dedication to excellent customer service!</p>
            </div>
            
            <div class="footer">
                <p>This is an automated email from FieldCheck Support System.</p>
                <p>Ticket #: ${ticketNumber}</p>
            </div>
        </div>
    </body>
    </html>
  `;
};
