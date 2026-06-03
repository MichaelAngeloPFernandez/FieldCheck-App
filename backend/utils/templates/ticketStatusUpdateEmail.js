/**
 * Email template for ticket status updates
 * Sends notification to clients when their ticket status changes
 * 
 * @param {string} clientName - Name of the client
 * @param {string} ticketNumber - Ticket number (format: RNG-YYYYMMDD-XXXX)
 * @param {string} newStatus - New status value (in_progress, pending_review, completed, closed)
 * @param {string} trackingLink - Direct link to ticket tracking page with authentication token
 * @returns {string} HTML email template
 */
function ticketStatusUpdateEmail(clientName, ticketNumber, newStatus, trackingLink) {
  // Status-specific messages and icons
  const statusMessages = {
    'in_progress': {
      title: 'Work Has Started',
      message: 'Our team has begun working on your support request.',
      icon: '🔧'
    },
    'pending_review': {
      title: 'Under Review',
      message: 'Work has been completed and is now under review by our team.',
      icon: '👀'
    },
    'completed': {
      title: 'Work Completed',
      message: 'Your support request has been completed successfully!',
      icon: '✅',
      showRating: true
    },
    'closed': {
      title: 'Ticket Closed',
      message: 'Your support ticket has been closed.',
      icon: '🔒'
    }
  };
  
  // Get status info or use default
  const statusInfo = statusMessages[newStatus] || {
    title: 'Status Update',
    message: `Your ticket status has been updated to: ${newStatus}`,
    icon: '📋'
  };
  
  return `
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Ticket Status Update - ${ticketNumber}</title>
        <style>
            body {
                font-family: Arial, sans-serif;
                background-color: #f4f4f4;
                margin: 0;
                padding: 0;
                line-height: 1.6;
            }
            .container {
                width: 100%;
                max-width: 600px;
                margin: 0 auto;
                background-color: #ffffff;
                border-radius: 10px;
                box-shadow: 0 0 10px rgba(0, 0, 0, 0.1);
                overflow: hidden;
            }
            .header {
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                color: #ffffff;
                padding: 30px;
                text-align: center;
            }
            .header h1 {
                margin: 0;
                font-size: 28px;
                font-weight: bold;
            }
            .content {
                background-color: #f9f9f9;
                padding: 30px;
            }
            .content p {
                font-size: 16px;
                margin-bottom: 20px;
                color: #333333;
            }
            .ticket-box {
                background-color: #ffffff;
                padding: 20px;
                border-radius: 8px;
                margin: 20px 0;
                border-left: 4px solid #667eea;
            }
            .ticket-box p {
                margin: 0;
            }
            .ticket-label {
                font-size: 14px;
                color: #666666;
                margin-bottom: 5px;
            }
            .ticket-number {
                font-size: 20px;
                font-weight: bold;
                color: #667eea;
                margin-top: 5px;
            }
            .rating-box {
                background-color: #fff3cd;
                padding: 20px;
                border-radius: 8px;
                margin: 20px 0;
                border-left: 4px solid #ffc107;
            }
            .rating-box p {
                margin: 0;
                color: #856404;
            }
            .rating-title {
                font-weight: bold;
                margin-bottom: 10px;
                font-size: 16px;
            }
            .rating-text {
                font-size: 14px;
            }
            .button-container {
                text-align: center;
                margin: 30px 0;
            }
            .button {
                display: inline-block;
                background-color: #667eea;
                color: #ffffff;
                padding: 15px 40px;
                text-decoration: none;
                border-radius: 5px;
                font-weight: bold;
                font-size: 16px;
            }
            .button:hover {
                background-color: #5568d3;
            }
            .footer-text {
                font-size: 14px;
                color: #666666;
                margin-top: 30px;
            }
            .signature {
                font-size: 14px;
                color: #666666;
                margin-top: 20px;
            }
            .footer {
                text-align: center;
                padding: 20px;
                font-size: 12px;
                color: #999999;
            }
            .footer p {
                margin: 5px 0;
                font-size: 12px;
            }
        </style>
    </head>
    <body>
        <div class="container">
            <div class="header">
                <h1>${statusInfo.icon} ${statusInfo.title}</h1>
            </div>
            
            <div class="content">
                <p>Hello <strong>${clientName}</strong>,</p>
                
                <p>${statusInfo.message}</p>
                
                <div class="ticket-box">
                    <p class="ticket-label">Ticket Number</p>
                    <p class="ticket-number">${ticketNumber}</p>
                </div>
                
                ${statusInfo.showRating ? `
                <div class="rating-box">
                    <p class="rating-title">Rate Your Experience</p>
                    <p class="rating-text">
                        We'd love to hear your feedback! Please rate the service you received by visiting your ticket tracking page.
                    </p>
                </div>
                ` : ''}
                
                <div class="button-container">
                    <a href="${trackingLink}" class="button">View Ticket Details</a>
                </div>
                
                <p class="footer-text">
                    If you have any questions, please reply to this email or visit your ticket tracking page.
                </p>
                
                <p class="signature">
                    Best regards,<br>
                    <strong>FieldCheck Support Team</strong>
                </p>
            </div>
            
            <div class="footer">
                <p>This is an automated notification from FieldCheck.</p>
                <p>Ticket: ${ticketNumber}</p>
            </div>
        </div>
    </body>
    </html>
  `;
}

module.exports = ticketStatusUpdateEmail;
