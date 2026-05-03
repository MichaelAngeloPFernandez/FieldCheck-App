/**
 * Jest Configuration for FieldCheck Backend Tests
 * 
 * Configures:
 * - Test environment (Node)
 * - Coverage thresholds (80%+ minimum)
 * - Module paths
 * - Test timeouts
 * - Mock configurations
 */

module.exports = {
  displayName: 'backend',
  testEnvironment: 'node',
  roots: ['<rootDir>'],
  testMatch: ['**/__tests__/**/*.test.js'],
  collectCoverageFrom: [
    '**/*.js',
    '!**/*.test.js',
    '!node_modules/**',
    '!__tests__/**',
    '!public/**',
    '!coverage/**',
    '!test-results/**',
  ],
  coverageThreshold: {
    global: {
      branches: 80,
      functions: 80,
      lines: 80,
      statements: 80,
    },
  },
  moduleNameMapper: {
    '^@/(.*)$': '<rootDir>/$1',
  },
  setupFilesAfterEnv: ['<rootDir>/__tests__/setup.js'],
  testTimeout: 10000,
  verbose: true,
  bail: false,
  maxWorkers: '50%',
  errorOnDeprecated: true,

  // Coverage reporter configuration
  coverageReporters: [
    'text',
    'text-summary',
    'html',
    'lcov',
    'json',
  ],

  // Test reporters
  reporters: [
    'default',
    [
      'jest-junit',
      {
        outputDirectory: './test-results',
        outputName: 'junit.xml',
        classNameTemplate: '{classname}',
        titleTemplate: '{title}',
        ancestorSeparator: ' › ',
        uniqueOutputName: false,
        suiteNameTemplate: '{suite}',
        usePathAsClassName: true,
      },
    ],
  ],
};
