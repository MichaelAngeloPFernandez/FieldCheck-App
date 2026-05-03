/**
 * Comprehensive debug logger for tracking data flow issues
 */

const colors = {
  reset: '\x1b[0m',
  bright: '\x1b[1m',
  red: '\x1b[31m',
  green: '\x1b[32m',
  yellow: '\x1b[33m',
  blue: '\x1b[34m',
  magenta: '\x1b[35m',
  cyan: '\x1b[36m',
};

const logger = {
  // Attendance operations
  logCheckIn: (userId, geofenceId, distance, radius) => {
    console.log(
      `${colors.green}✓ CHECK-IN${colors.reset} | User: ${userId} | Geofence: ${geofenceId} | Distance: ${distance.toFixed(1)}m/${radius}m`
    );
  },

  logCheckOut: (userId, geofenceId, duration) => {
    console.log(
      `${colors.cyan}✓ CHECK-OUT${colors.reset} | User: ${userId} | Geofence: ${geofenceId} | Duration: ${duration}min`
    );
  },

  logGeofenceUpdate: (geofenceId, fields) => {
    console.log(
      `${colors.magenta}⚙ GEOFENCE UPDATE${colors.reset} | ID: ${geofenceId} | Fields: ${Object.keys(fields).join(', ')}`
    );
  },

  logTaskUpdate: (taskId, status) => {
    console.log(
      `${colors.blue}⚙ TASK UPDATE${colors.reset} | ID: ${taskId} | Status: ${status}`
    );
  },

  logError: (operation, error) => {
    console.log(
      `${colors.red}✗ ERROR${colors.reset} | Operation: ${operation} | ${error.message}`
    );
  },

  logSocketEvent: (event, data) => {
    console.log(
      `${colors.yellow}📡 SOCKET EVENT${colors.reset} | ${event} | Data keys: ${Object.keys(data).join(', ')}`
    );
  },

  logDataFlow: (source, destination, dataSize) => {
    console.log(
      `${colors.bright}→ DATA FLOW${colors.reset} | ${source} → ${destination} | Size: ${dataSize} bytes`
    );
  },
};

module.exports = logger;
