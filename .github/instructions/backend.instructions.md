---
name: backend-validation
description: "Backend API development guidelines. Use when: working on Node.js/Express backend, fixing controller bugs, or adding/modifying API endpoints. Enforces validation, error handling, and security best practices."
applyTo: "backend/**/*.js"
---

# Backend Development Guidelines

## Critical Requirements for All Controllers

### 1. Input Validation (REQUIRED)
Every endpoint must validate inputs **before** using them:

```javascript
// ✅ CORRECT
router.post('/reports', authenticate, async (req, res) => {
  const { type, ...data } = req.body;
  
  // Validate type field
  if (!type || !['attendance', 'task', 'performance'].includes(type)) {
    return res.status(400).json({ error: 'Invalid type field' });
  }
  
  // Continue with safe data...
});

// ❌ WRONG - No validation
router.post('/reports', authenticate, async (req, res) => {
  const report = new Report(req.body); // Could have invalid data
  await report.save();
});
```

### 2. Error Handling (REQUIRED)
Never use empty catch blocks. Always log and return meaningful errors:

```javascript
// ✅ CORRECT
try {
  const result = await someOperation();
  res.json(result);
} catch (error) {
  console.error('Operation failed:', error);
  res.status(500).json({ 
    error: 'Operation failed',
    message: process.env.NODE_ENV === 'development' ? error.message : 'Internal error'
  });
}

// ❌ WRONG
try {
  const result = await someOperation();
  res.json(result);
} catch (error) {
  // Silent failure!
}
```

### 3. URL Path Consistency (REQUIRED)
Check for path duplication in routes. Example bad pattern:
```javascript
// ❌ BAD - Creates /api/tasks/api/tasks/:id
router.get('/api/tasks/:id', handler);
// If base is already /api/tasks

// ✅ CORRECT - Let router handle the base path
router.get('/:id', handler);
```

### 4. Query Parameter Handling (REQUIRED)
When endpoints accept optional filters, document and validate them:

```javascript
// Reports endpoint must support ?type parameter
// Example: GET /api/reports?type=attendance
router.get('/', authenticate, async (req, res) => {
  const { type } = req.query;
  
  let query = {};
  if (type && ['attendance', 'task', 'performance'].includes(type)) {
    query.type = type;
  }
  
  const reports = await Report.find(query);
  res.json(reports);
});
```

### 5. Security Checklist for All Endpoints
- [ ] Input validation present
- [ ] Error handling doesn't expose sensitive data
- [ ] CORS properly configured (not `origin: "*"` in production)
- [ ] Rate limiting enabled
- [ ] Authentication required (unless public endpoint)
- [ ] Authorization checked (user can only access their own data)

## Known Issues to Fix

| Controller | Issue | Fix |
|-----------|-------|-----|
| exportController.js | Wrong field names in mapping | Use exact model field names |
| server.js sync endpoint | Missing validation | Add request validation middleware |
| userController.js | No password strength check | Add regex: `/.{8,}[A-Z][0-9]/` |
| taskController.js | No geofence validation | Check geofence exists before creating task |

## Files That Need Attention

Priority files to review:
- `backend/controllers/exportController.js` - Critical field name fixes
- `backend/routes/sync.js` - Add validation
- `backend/server.js` - Fix CORS, enable rate limiting
- All controllers - Audit for empty catch blocks
