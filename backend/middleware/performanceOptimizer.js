/**
 * Performance Optimizer Middleware
 * 
 * Provides:
 * - Rate limiting for check-in/out endpoints
 * - Query caching with TTL
 * - Response time tracking
 * - Memory-efficient caching strategy
 * 
 * Targets:
 * - API response time: <200ms
 * - Check-in throughput: 100+ requests/second
 * - Cache hit rate: >80%
 */

/**
 * Simple in-memory cache with TTL support
 * (Can be replaced with Redis in production)
 */
class CacheManager {
  constructor(maxSize = 1000, defaultTTL = 300000) {
    this.cache = new Map();
    this.ttls = new Map();
    this.stats = {
      hits: 0,
      misses: 0,
      evictions: 0,
    };
    this.maxSize = maxSize;
    this.defaultTTL = defaultTTL;
  }

  /**
   * Generate cache key from request parameters
   */
  static generateKey(prefix, params) {
    const key = Object.keys(params)
      .sort()
      .map(k => `${k}=${params[k]}`)
      .join(':');
    return `${prefix}:${key}`;
  }

  /**
   * Get value from cache
   */
  get(key) {
    if (!this.cache.has(key)) {
      this.stats.misses++;
      return null;
    }

    // Check if expired
    const ttl = this.ttls.get(key);
    if (ttl && ttl < Date.now()) {
      this.cache.delete(key);
      this.ttls.delete(key);
      this.stats.misses++;
      return null;
    }

    this.stats.hits++;
    return this.cache.get(key);
  }

  /**
   * Set value in cache with TTL
   */
  set(key, value, ttl = this.defaultTTL) {
    // Enforce size limit
    if (this.cache.size >= this.maxSize) {
      // Remove oldest entry (simple FIFO eviction)
      const firstKey = this.cache.keys().next().value;
      this.cache.delete(firstKey);
      this.ttls.delete(firstKey);
      this.stats.evictions++;
    }

    this.cache.set(key, value);
    if (ttl) {
      this.ttls.set(key, Date.now() + ttl);
    }
  }

  /**
   * Check if key exists in cache (without counting as hit)
   */
  has(key) {
    return this.cache.has(key);
  }

  /**
   * Delete from cache
   */
  delete(key) {
    this.cache.delete(key);
    this.ttls.delete(key);
  }

  /**
   * Clear all cache
   */
  clear() {
    this.cache.clear();
    this.ttls.clear();
  }

  /**
   * Get cache statistics
   */
  getStats() {
    const total = this.stats.hits + this.stats.misses;
    return {
      ...this.stats,
      hitRate: total > 0 ? ((this.stats.hits / total) * 100).toFixed(2) + '%' : 'N/A',
      size: this.cache.size,
      maxSize: this.maxSize,
    };
  }

  /**
   * Clear expired entries
   */
  cleanup() {
    let cleaned = 0;
    for (const [key, ttl] of this.ttls.entries()) {
      if (ttl < Date.now()) {
        this.cache.delete(key);
        this.ttls.delete(key);
        cleaned++;
      }
    }
    return cleaned;
  }
}

/**
 * Rate limiter for check-in/out endpoints
 * Uses sliding window counter algorithm
 */
class RateLimiter {
  constructor(maxRequests = 10, windowMs = 60000) {
    this.maxRequests = maxRequests;
    this.windowMs = windowMs;
    this.requests = new Map(); // userId -> [timestamps]
  }

  /**
   * Check if request is allowed
   */
  isAllowed(userId) {
    const now = Date.now();
    const windowStart = now - this.windowMs;

    if (!this.requests.has(userId)) {
      this.requests.set(userId, []);
    }

    const timestamps = this.requests.get(userId);

    // Remove old timestamps outside window
    const validTimestamps = timestamps.filter(ts => ts > windowStart);
    this.requests.set(userId, validTimestamps);

    // Check if limit exceeded
    if (validTimestamps.length >= this.maxRequests) {
      return {
        allowed: false,
        remaining: 0,
        retryAfter: Math.ceil((validTimestamps[0] + this.windowMs - now) / 1000),
      };
    }

    // Record this request
    validTimestamps.push(now);

    return {
      allowed: true,
      remaining: this.maxRequests - validTimestamps.length,
      retryAfter: null,
    };
  }

  /**
   * Reset limit for user
   */
  reset(userId) {
    this.requests.delete(userId);
  }

  /**
   * Get statistics
   */
  getStats() {
    return {
      trackedUsers: this.requests.size,
      maxRequests: this.maxRequests,
      windowMs: this.windowMs,
    };
  }
}

/**
 * Performance tracking middleware
 */
class PerformanceTracker {
  constructor() {
    this.endpoints = new Map(); // endpoint -> [response times]
    this.maxSamples = 100;
  }

  /**
   * Track request timing
   */
  trackRequest(endpoint, responseTime) {
    if (!this.endpoints.has(endpoint)) {
      this.endpoints.set(endpoint, []);
    }

    const times = this.endpoints.get(endpoint);
    times.push(responseTime);

    // Keep only last N samples
    if (times.length > this.maxSamples) {
      times.shift();
    }
  }

  /**
   * Get performance stats for endpoint
   */
  getStats(endpoint) {
    if (!this.endpoints.has(endpoint)) {
      return null;
    }

    const times = this.endpoints.get(endpoint);
    if (times.length === 0) return null;

    const sorted = [...times].sort((a, b) => a - b);
    const avg = times.reduce((a, b) => a + b) / times.length;
    const p50 = sorted[Math.floor(sorted.length * 0.5)];
    const p95 = sorted[Math.floor(sorted.length * 0.95)];
    const p99 = sorted[Math.floor(sorted.length * 0.99)];

    return {
      endpoint,
      samples: times.length,
      average: avg.toFixed(2),
      min: Math.min(...times),
      max: Math.max(...times),
      p50,
      p95,
      p99,
    };
  }

  /**
   * Get all stats
   */
  getAllStats() {
    const results = [];
    for (const endpoint of this.endpoints.keys()) {
      results.push(this.getStats(endpoint));
    }
    return results;
  }
}

// Global instances
const cacheManager = new CacheManager(1000, 300000); // 5-minute default TTL
const checkInLimiter = new RateLimiter(10, 60000); // 10 check-ins per 60 seconds per user
const checkOutLimiter = new RateLimiter(10, 60000); // 10 check-outs per 60 seconds per user
const performanceTracker = new PerformanceTracker();

/**
 * Rate limiting middleware for check-in
 */
function checkInRateLimiter(req, res, next) {
  const userId = req.user?._id?.toString() || req.ip;
  const result = checkInLimiter.isAllowed(userId);

  res.set('X-RateLimit-Limit', '10');
  res.set('X-RateLimit-Remaining', result.remaining.toString());

  if (!result.allowed) {
    res.status(429);
    throw new Error(
      `Too many check-ins. Maximum 10 per minute. Retry after ${result.retryAfter}s`
    );
  }

  next();
}

/**
 * Rate limiting middleware for check-out
 */
function checkOutRateLimiter(req, res, next) {
  const userId = req.user?._id?.toString() || req.ip;
  const result = checkOutLimiter.isAllowed(userId);

  res.set('X-RateLimit-Limit', '10');
  res.set('X-RateLimit-Remaining', result.remaining.toString());

  if (!result.allowed) {
    res.status(429);
    throw new Error(
      `Too many check-outs. Maximum 10 per minute. Retry after ${result.retryAfter}s`
    );
  }

  next();
}

/**
 * Performance tracking middleware
 */
function performanceTracking(req, res, next) {
  const startTime = Date.now();
  const endpoint = `${req.method} ${req.path}`;

  // Wrap res.json to track response time
  const originalJson = res.json;
  res.json = function(data) {
    const responseTime = Date.now() - startTime;
    performanceTracker.trackRequest(endpoint, responseTime);

    // Add performance headers
    res.set('X-Response-Time', `${responseTime}ms`);

    // Log if slow (>500ms)
    if (responseTime > 500) {
      console.warn(`🐢 Slow response: ${endpoint} took ${responseTime}ms`);
    }

    return originalJson.call(this, data);
  };

  next();
}

/**
 * Geofence data caching middleware
 * Caches frequently accessed geofence data
 */
function cacheGeofenceData(req, res, next) {
  // Only cache GET requests
  if (req.method !== 'GET') {
    return next();
  }

  const cacheKey = CacheManager.generateKey('geofence', {
    path: req.path,
    query: JSON.stringify(req.query),
  });

  // Check cache first
  const cached = cacheManager.get(cacheKey);
  if (cached) {
    res.set('X-Cache', 'HIT');
    return res.json(cached);
  }

  // Wrap res.json to cache successful responses
  const originalJson = res.json;
  res.json = function(data) {
    // Only cache successful responses
    if (res.statusCode === 200 && data) {
      cacheManager.set(cacheKey, data, 300000); // 5-minute cache
      res.set('X-Cache', 'MISS');
    }

    return originalJson.call(this, data);
  };

  next();
}

/**
 * Invalidate cache on write operations
 */
function invalidateGeofenceCache(req, res, next) {
  // Wrap res.json to invalidate cache after successful write
  const originalJson = res.json;
  res.json = function(data) {
    if (res.statusCode >= 200 && res.statusCode < 300) {
      // Invalidate related cache entries
      const keys = Array.from(cacheManager.cache.keys()).filter(
        k => k.startsWith('geofence:')
      );
      keys.forEach(key => cacheManager.delete(key));
    }

    return originalJson.call(this, data);
  };

  next();
}

/**
 * Attendance data caching middleware
 */
function cacheAttendanceData(req, res, next) {
  // Only cache GET requests
  if (req.method !== 'GET') {
    return next();
  }

  const cacheKey = CacheManager.generateKey('attendance', {
    path: req.path,
    query: JSON.stringify(req.query),
    userId: req.user?._id?.toString() || 'anonymous',
  });

  // Check cache first
  const cached = cacheManager.get(cacheKey);
  if (cached) {
    res.set('X-Cache', 'HIT');
    return res.json(cached);
  }

  // Wrap res.json to cache successful responses
  const originalJson = res.json;
  res.json = function(data) {
    // Only cache successful responses
    if (res.statusCode === 200 && data) {
      cacheManager.set(cacheKey, data, 120000); // 2-minute cache for attendance
      res.set('X-Cache', 'MISS');
    }

    return originalJson.call(this, data);
  };

  next();
}

/**
 * Invalidate attendance cache on write
 */
function invalidateAttendanceCache(req, res, next) {
  const originalJson = res.json;
  res.json = function(data) {
    if (res.statusCode >= 200 && res.statusCode < 300) {
      // Invalidate related cache entries
      const keys = Array.from(cacheManager.cache.keys()).filter(
        k => k.startsWith('attendance:')
      );
      keys.forEach(key => cacheManager.delete(key));
    }

    return originalJson.call(this, data);
  };

  next();
}

/**
 * Dashboard caching with longer TTL
 */
function cacheDashboardData(req, res, next) {
  // Only cache GET requests
  if (req.method !== 'GET') {
    return next();
  }

  const cacheKey = CacheManager.generateKey('dashboard', {
    path: req.path,
    query: JSON.stringify(req.query),
  });

  // Check cache first
  const cached = cacheManager.get(cacheKey);
  if (cached) {
    res.set('X-Cache', 'HIT');
    return res.json(cached);
  }

  // Wrap res.json to cache successful responses
  const originalJson = res.json;
  res.json = function(data) {
    // Only cache successful responses
    if (res.statusCode === 200 && data) {
      cacheManager.set(cacheKey, data, 600000); // 10-minute cache for dashboard
      res.set('X-Cache', 'MISS');
    }

    return originalJson.call(this, data);
  };

  next();
}

/**
 * Get performance metrics endpoint
 */
function getMetrics(req, res) {
  const metrics = {
    cache: cacheManager.getStats(),
    checkInLimiter: checkInLimiter.getStats(),
    checkOutLimiter: checkOutLimiter.getStats(),
    performance: performanceTracker.getAllStats(),
    timestamp: new Date().toISOString(),
  };

  res.json(metrics);
}

/**
 * Reset metrics (development only)
 */
function resetMetrics(req, res) {
  if (process.env.NODE_ENV === 'production') {
    res.status(403);
    throw new Error('Metrics reset not allowed in production');
  }

  cacheManager.clear();
  checkInLimiter.requests.clear();
  checkOutLimiter.requests.clear();
  performanceTracker.endpoints.clear();

  res.json({ message: 'Metrics reset' });
}

module.exports = {
  // Cache manager
  cacheManager,
  CacheManager,

  // Rate limiters
  checkInLimiter,
  checkOutLimiter,
  RateLimiter,

  // Performance tracker
  performanceTracker,
  PerformanceTracker,

  // Middleware functions
  performanceTracking,
  checkInRateLimiter,
  checkOutRateLimiter,
  cacheGeofenceData,
  invalidateGeofenceCache,
  cacheAttendanceData,
  invalidateAttendanceCache,
  cacheDashboardData,

  // Metrics endpoints
  getMetrics,
  resetMetrics,
};
