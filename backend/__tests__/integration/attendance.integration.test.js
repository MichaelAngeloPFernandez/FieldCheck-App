/**
 * Integration Tests for Attendance Endpoints
 * 
 * Tests for:
 * - Check-in endpoint with rate limiting & validation
 * - Check-out endpoint with rate limiting & validation
 * - Sync endpoint with offline data
 * - Cache invalidation on write
 * 
 * Framework: Jest + Supertest
 * Coverage Target: 100%
 */

const request = require('supertest');
const express = require('express');
const {
  performanceTracking,
  checkInRateLimiter,
  checkOutRateLimiter,
  cacheAttendanceData,
  invalidateAttendanceCache,
  getMetrics,
  cacheManager,
  checkInLimiter,
  checkOutLimiter,
  performanceTracker,
} = require('../../middleware/performanceOptimizer');

const resetPerformanceGlobals = () => {
  cacheManager.clear();
  checkInLimiter.requests.clear();
  checkOutLimiter.requests.clear();
  performanceTracker.endpoints.clear();
};

// Mock Express app
const createTestApp = () => {
  const app = express();
  app.use(express.json());
  app.use(performanceTracking);

  // Mock auth middleware
  app.use((req, res, next) => {
    req.user = { _id: 'testuser123', email: 'test@example.com' };
    next();
  });

  // Mock routes
  app.post('/api/attendance/checkin', checkInRateLimiter, (req, res) => {
    res.json({ status: 'checked-in', timestamp: new Date() });
  });

  app.post('/api/attendance/checkout', checkOutRateLimiter, (req, res) => {
    res.json({ status: 'checked-out', timestamp: new Date() });
  });

  app.get('/api/attendance', cacheAttendanceData, (req, res) => {
    res.json({ records: [] });
  });

  app.post('/api/attendance/sync', invalidateAttendanceCache, (req, res) => {
    res.json({ synced: true });
  });

  app.get('/api/metrics', (req, res) => {
    getMetrics(req, res);
  });

  return app;
};

describe('Attendance Endpoints - Integration Tests', () => {
  let app;

  beforeEach(() => {
    resetPerformanceGlobals();
    app = createTestApp();
  });

  describe('Check-in Endpoint', () => {
    it('should allow valid check-in', async () => {
      const response = await request(app)
        .post('/api/attendance/checkin')
        .send({
          latitude: 40.7128,
          longitude: -74.006,
          geofenceId: 'geo123',
        });

      expect(response.status).toBe(200);
      expect(response.body.status).toBe('checked-in');
    });

    it('should include rate limit headers', async () => {
      const response = await request(app)
        .post('/api/attendance/checkin')
        .send({
          latitude: 40.7128,
          longitude: -74.006,
        });

      expect(response.headers['x-ratelimit-limit']).toBe('10');
      expect(response.headers['x-ratelimit-remaining']).toBeDefined();
    });

    it('should enforce rate limit (10 per 60 seconds)', async () => {
      // Make 10 successful requests
      for (let i = 0; i < 10; i++) {
        const response = await request(app).post('/api/attendance/checkin').send({
          latitude: 40.7128,
          longitude: -74.006,
        });
        expect(response.status).toBe(200);
      }

      // 11th request should be rate limited
      const response = await request(app).post('/api/attendance/checkin').send({
        latitude: 40.7128,
        longitude: -74.006,
      });

      expect(response.status).toBe(429);
    });

    it('should include response time header', async () => {
      const response = await request(app).post('/api/attendance/checkin').send({
        latitude: 40.7128,
        longitude: -74.006,
      });

      expect(response.headers['x-response-time']).toBeDefined();
      expect(response.headers['x-response-time']).toMatch(/ms/);
    });
  });

  describe('Check-out Endpoint', () => {
    it('should allow valid check-out', async () => {
      const response = await request(app)
        .post('/api/attendance/checkout')
        .send({
          latitude: 40.7128,
          longitude: -74.006,
          geofenceId: 'geo123',
        });

      expect(response.status).toBe(200);
      expect(response.body.status).toBe('checked-out');
    });

    it('should enforce rate limit separately from check-in', async () => {
      // Make 10 check-in requests
      for (let i = 0; i < 10; i++) {
        await request(app).post('/api/attendance/checkin').send({
          latitude: 40.7128,
          longitude: -74.006,
        });
      }

      // Check-in should be rate limited
      let response = await request(app).post('/api/attendance/checkin').send({
        latitude: 40.7128,
        longitude: -74.006,
      });
      expect(response.status).toBe(429);

      // Check-out should still work (separate limit)
      response = await request(app).post('/api/attendance/checkout').send({
        latitude: 40.7128,
        longitude: -74.006,
      });
      expect(response.status).toBe(200);
    });

    it('should allow 10 check-outs per 60 seconds', async () => {
      for (let i = 0; i < 10; i++) {
        const response = await request(app).post('/api/attendance/checkout').send({
          latitude: 40.7128,
          longitude: -74.006,
        });
        expect(response.status).toBe(200);
      }

      const response = await request(app).post('/api/attendance/checkout').send({
        latitude: 40.7128,
        longitude: -74.006,
      });
      expect(response.status).toBe(429);
    });
  });

  describe('Caching - GET Attendance', () => {
    it('should cache GET responses', async () => {
      const response1 = await request(app).get('/api/attendance');
      expect(response1.status).toBe(200);
      expect(response1.headers['x-cache']).toBe('MISS');

      const response2 = await request(app).get('/api/attendance');
      expect(response2.status).toBe(200);
      expect(response2.headers['x-cache']).toBe('HIT');
    });

    it('should serve cached data faster', async () => {
      await request(app).get('/api/attendance'); // MISS

      const response = await request(app).get('/api/attendance'); // HIT
      const cacheTime = parseInt(response.headers['x-response-time']);
      expect(cacheTime).toBeLessThan(50); // Should be very fast from cache
    });
  });

  describe('Cache Invalidation - Write Operations', () => {
    it('should invalidate cache on sync', async () => {
      // Prime cache
      let response = await request(app).get('/api/attendance');
      expect(response.headers['x-cache']).toBe('MISS');

      response = await request(app).get('/api/attendance');
      expect(response.headers['x-cache']).toBe('HIT');

      // Sync (write) - should invalidate
      await request(app).post('/api/attendance/sync').send({
        attendance: [],
      });

      // Next GET should be MISS (cache invalidated)
      response = await request(app).get('/api/attendance');
      expect(response.headers['x-cache']).toBe('MISS');
    });
  });

  describe('Performance Metrics', () => {
    it('should track response times', async () => {
      await request(app).post('/api/attendance/checkin').send({
        latitude: 40.7128,
        longitude: -74.006,
      });

      await request(app).post('/api/attendance/checkin').send({
        latitude: 40.7128,
        longitude: -74.006,
      });

      const response = await request(app).get('/api/metrics');
      expect(response.status).toBe(200);
      expect(response.body.performance).toBeDefined();
    });

    it('should calculate percentiles', async () => {
      for (let i = 0; i < 5; i++) {
        await request(app).get('/api/attendance');
      }

      const response = await request(app).get('/api/metrics');
      const stats = response.body.performance.find(
        s => s.endpoint.includes('/api/attendance')
      );

      expect(stats).toBeDefined();
      expect(stats.p50).toBeDefined();
      expect(stats.p95).toBeDefined();
      expect(stats.p99).toBeDefined();
    });
  });
});

describe('Concurrency & Race Conditions', () => {
  let app;

  beforeEach(() => {
    resetPerformanceGlobals();
    app = createTestApp();
  });

  it('should handle concurrent check-ins', async () => {
    const promises = Array.from({ length: 5 }, () =>
      request(app).post('/api/attendance/checkin').send({
        latitude: 40.7128,
        longitude: -74.006,
      })
    );

    const responses = await Promise.all(promises);
    expect(responses.every(r => r.status === 200)).toBe(true);
  });

  it('should handle concurrent reads with cache', async () => {
    const promises = Array.from({ length: 10 }, () =>
      request(app).get('/api/attendance')
    );

    const responses = await Promise.all(promises);
    expect(responses.every(r => r.status === 200)).toBe(true);

    // First should be MISS, rest should be HIT
    const hits = responses.filter(r => r.headers['x-cache'] === 'HIT');
    expect(hits.length).toBeGreaterThan(0);
  });

  it('should handle concurrent check-in and check-out', async () => {
    const promises = [
      ...Array.from({ length: 5 }, () =>
        request(app).post('/api/attendance/checkin').send({
          latitude: 40.7128,
          longitude: -74.006,
        })
      ),
      ...Array.from({ length: 5 }, () =>
        request(app).post('/api/attendance/checkout').send({
          latitude: 40.7128,
          longitude: -74.006,
        })
      ),
    ];

    const responses = await Promise.all(promises);
    expect(responses.every(r => r.status === 200)).toBe(true);
  });
});

describe('Error Handling', () => {
  let app;

  beforeEach(() => {
    resetPerformanceGlobals();
    app = createTestApp();
  });

  it('should handle missing user', async () => {
    const testApp = express();
    testApp.use(express.json());
    testApp.post('/api/attendance/checkin', checkInRateLimiter, (req, res) => {
      res.json({ status: 'checked-in' });
    });

    const response = await request(testApp)
      .post('/api/attendance/checkin')
      .send({
        latitude: 40.7128,
        longitude: -74.006,
      });

    // Should still work (rate limiting uses IP as fallback)
    expect([200, 429]).toContain(response.status);
  });

  it('should handle invalid JSON', async () => {
    const response = await request(app)
      .post('/api/attendance/checkin')
      .set('Content-Type', 'application/json')
      .send('invalid json');

    expect([400, 500]).toContain(response.status);
  });

  it('should handle missing request body', async () => {
    const response = await request(app).post('/api/attendance/checkin');

    expect(response.status).toBe(200); // Still succeeds (req.body is {})
  });
});

describe('Edge Cases', () => {
  let app;

  beforeEach(() => {
    resetPerformanceGlobals();
    app = createTestApp();
  });

  it('should handle very fast consecutive requests', async () => {
    const responses = [];
    for (let i = 0; i < 15; i++) {
      responses.push(
        await request(app).post('/api/attendance/checkin').send({
          latitude: 40.7128,
          longitude: -74.006,
        })
      );
    }

    const successful = responses.filter(r => r.status === 200);
    const rateLimited = responses.filter(r => r.status === 429);

    expect(successful.length).toBe(10);
    expect(rateLimited.length).toBe(5);
  });

  it('should handle requests with large payloads', async () => {
    const largeData = {
      latitude: 40.7128,
      longitude: -74.006,
      metadata: 'x'.repeat(10000),
    };

    const response = await request(app)
      .post('/api/attendance/checkin')
      .send(largeData);

    expect([200, 413]).toContain(response.status); // 413 = Payload Too Large
  });

  it('should handle cache with different query parameters', async () => {
    const response1 = await request(app).get('/api/attendance?employee=emp1');
    expect(response1.headers['x-cache']).toBe('MISS');

    const response2 = await request(app).get('/api/attendance?employee=emp1');
    expect(response2.headers['x-cache']).toBe('HIT');

    const response3 = await request(app).get('/api/attendance?employee=emp2');
    expect(response3.headers['x-cache']).toBe('MISS'); // Different query
  });
});
