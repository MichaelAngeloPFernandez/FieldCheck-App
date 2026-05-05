const ClientTicket = require('../models/ClientTicket');

/**
 * Generate a unique ticket number in format: RNG-YYYYMMDD-XXXX
 * Where XXXX is a random 4-character alphanumeric string
 * 
 * @returns {Promise<string>} Unique ticket number
 */
async function generateTicketNumber() {
  const MAX_RETRIES = 5;

  for (let attempt = 0; attempt < MAX_RETRIES; attempt++) {
    const now = new Date();
    const year = now.getFullYear();
    const month = String(now.getMonth() + 1).padStart(2, '0');
    const day = String(now.getDate()).padStart(2, '0');
    const dateStr = `${year}${month}${day}`;

    // Generate 4 random characters (alphanumeric: A-Z, 0-9)
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    let randomStr = '';
    for (let i = 0; i < 4; i++) {
      randomStr += chars.charAt(Math.floor(Math.random() * chars.length));
    }

    const ticketNumber = `RNG-${dateStr}-${randomStr}`;

    // Check for uniqueness
    const existing = await ClientTicket.findOne({ ticketNumber });
    if (!existing) {
      return ticketNumber;
    }

    console.warn(`Ticket number collision detected: ${ticketNumber}, retrying...`);
  }

  // If collision persists after retries, throw error
  throw new Error(
    `Failed to generate unique ticket number after ${MAX_RETRIES} attempts. Please try again.`
  );
}

module.exports = {
  generateTicketNumber,
};
