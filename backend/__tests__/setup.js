/**
 * Jest Setup File
 * 
 * Runs before all tests to:
 * - Configure environment variables
 * - Mock global objects
 * - Setup test timeouts
 * - Configure logging
 */

// Set test environment
process.env.NODE_ENV = 'test';
process.env.MONGODB_URI = 'mongodb://localhost:27017/fieldcheck-test';

// Mock console methods to reduce noise during tests
global.console = {
  ...console,
  log: jest.fn(),
  debug: jest.fn(),
  info: jest.fn(),
  warn: jest.fn(),
  error: jest.fn(),
};

// Re-enable console.error for actual errors
global.console.error = console.error;

// Set default timeout
jest.setTimeout(10000);

// Mock Date for consistent testing
const mockDate = new Date('2024-11-28T10:00:00Z');
global.Date = class extends Date {
  constructor(...args) {
    if (args.length === 0) {
      super(mockDate);
    } else {
      super(...args);
    }
  }

  static now() {
    return mockDate.getTime();
  }
};

// Mock fetch if not available
if (typeof global.fetch === 'undefined') {
  global.fetch = jest.fn();
}

// Setup test fixtures
global.testFixtures = {
  mockGeofence: {
    _id: 'geofence123',
    name: 'Test Office',
    latitude: 40.7128,
    longitude: -74.006,
    radius: 100,
    isActive: true,
  },

  mockUser: {
    _id: 'user123',
    email: 'test@example.com',
    role: 'employee',
    isActive: true,
  },

  mockAttendance: {
    _id: 'attendance123',
    employee: 'user123',
    geofence: 'geofence123',
    checkIn: new Date(),
    status: 'in',
    location: {
      lat: 40.7128,
      lng: -74.006,
    },
  },
};

// Suppress deprecation warnings
process.on('warning', (warning) => {
  if (warning.name === 'DeprecationWarning') {
    // Suppress specific deprecation warnings if needed
  }
});
