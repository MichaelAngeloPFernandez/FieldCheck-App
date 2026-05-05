module.exports = (clientName, ticketNumber, employeeName, ratingLink) => {
  return `
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Support Ticket Completed</title>
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
                background-color: #4caf50;
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
                background-color: #f1f8f4;
                border-left: 4px solid #4caf50;
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
                color: #4caf50;
            }
            .content {
                padding: 0 20px;
            }
            .rating-section {
                background-color: #fff9e6;
                border: 1px solid #ffc107;
                padding: 15px;
                border-radius: 4px;
                margin: 20px 0;
            }
            .rating-section h3 {
                margin-top: 0;
                color: #ff9800;
            }
            .button {
                display: inline-block;
                background-color: #4caf50;
                color: #ffffff;
                padding: 12px 24px;
                text-decoration: none;
                border-radius: 5px;
                margin-top: 10px;
                font-weight: bold;
            }
            .button:hover {
                background-color: #388e3c;
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
                <h1>✅ Support Ticket Completed</h1>
            </div>
            
            <div class="content">
                <p>Hello <strong>${clientName}</strong>,</p>
                
                <p>We're pleased to inform you that your support ticket has been completed!</p>
                
                <div class="ticket-info">
                    <p class="ticket-number">Ticket #: ${ticketNumber}</p>
                    <p><strong>Completed By:</strong> ${employeeName}</p>
                    <p><strong>Completed On:</strong> ${new Date().toLocaleDateString()}</p>
                </div>
                
                <p>We appreciate your patience and look forward to serving you again. Your feedback is valuable to us!</p>
                
                <div class="rating-section">
                    <h3>⭐ Please Rate Your Experience</h3>
                    <p>We would love to hear about your experience with our service. Please take a moment to rate the quality of work and provide any feedback.</p>
                    <a href="${ratingLink}" class="button">Rate Your Service</a>
                    <p style="font-size: 12px; color: #666; margin-top: 10px;">
                        Your feedback helps us improve and serve you better.
                    </p>
                </div>
                
                <p>If you have any additional concerns or need further assistance, please don't hesitate to submit another ticket.</p>
                
                <p>Thank you for choosing FieldCheck!<br>Best regards,<br>FieldCheck Support Team</p>
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
