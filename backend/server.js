const express = require('express');
const http = require('http'); // Import http module
const { Server } = require('socket.io'); // Import Server from socket.io
const dotenv = require('dotenv');
const connectDB = require('./config/db');
const cors = require('cors');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const compression = require('compression');
const morgan = require('morgan');

console.log('🚀 Starting server initialization...');

dotenv.config();

console.log('📦 Modules loaded, environment configured');

const app = express();
const server = http.createServer(app); // Create http server
const io = new Server(server, { // Initialize socket.io
  cors: {
    origin: "*", // Allow all origins for now, refine later
    methods: ["GET", "POST"]
  }
});

// Export io for use in other modules
module.exports.io = io;

console.log('🔌 Socket.io initialized');

// --- Presence tracking: broadcast online socket count ---
let lastBroadcastCount = 0;
io.on('connection', (socket) => {
  try {
    const count = io.of('/').sockets.size;
    if (count !== lastBroadcastCount) {
      lastBroadcastCount = count;
      io.emit('onlineCount', count);
    }
  } catch (_) {}

  socket.on('disconnect', () => {
    try {
      const count = io.of('/').sockets.size;
      if (count !== lastBroadcastCount) {
        lastBroadcastCount = count;
        io.emit('onlineCount', count);
      }
    } catch (_) {}
  });
});

// Security & performance middleware
app.use(helmet());
app.use(compression());
if (process.env.NODE_ENV !== 'production') {
  app.use(morgan('dev'));
}
// Rate limiting: keep strict in production, relax/disable in development
const isProd = process.env.NODE_ENV === 'production';
const limiter = rateLimit({
  windowMs: parseInt(process.env.RATE_LIMIT_WINDOW_MS || '900000'), // 15 minutes
  max: parseInt(process.env.RATE_LIMIT_MAX || (isProd ? '1000' : '0')), // 0 disables in dev
  standardHeaders: true,
  legacyHeaders: false,
  // Skip preflight and health checks to avoid blocking normal API usage
  skip: (req) => req.method === 'OPTIONS' || req.path === '/api/health',
});
if (isProd) {
  app.use(limiter);
}

// Route modules (loaded after io initialization to avoid circular deps)
const userRoutes = require('./routes/userRoutes');
const geofenceRoutes = require('./routes/geofenceRoutes');
const attendanceRoutes = require('./routes/attendanceRoutes');
const settingsRoutes = require('./routes/settingsRoutes');
const dashboardRoutes = require('./routes/dashboardRoutes');
const reportRoutes = require('./routes/reportRoutes');

app.use(express.json({ limit: '200kb' })); // To parse JSON bodies (limited)
app.use(cors({
  origin: '*',
  methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization']
}));

app.get('/api/health', (req, res) => {
  res.json({ status: 'ok' });
});

app.get('/', (req, res) => {
  res.send('Hello from the backend!');
});

app.use('/api/users', userRoutes);
app.use('/api/geofences', geofenceRoutes);
app.use('/api/attendance', attendanceRoutes);
app.use('/api/settings', settingsRoutes);
app.use('/api/dashboard', dashboardRoutes);
const taskRoutes = require('./routes/taskRoutes');
app.use('/api/tasks', taskRoutes);
app.use('/api/reports', reportRoutes);

// Offline sync endpoint
const { protect } = require('./middleware/authMiddleware');
const Attendance = require('./models/Attendance');
const Geofence = require('./models/Geofence');
app.post('/api/sync', protect, async (req, res) => {
  const payload = req.body || {};
  const results = { attendanceProcessed: 0 };
  try {
    const items = Array.isArray(payload.attendance) ? payload.attendance : [];
    for (const item of items) {
      try {
        const geofence = await Geofence.findById(item.geofenceId);
        if (!geofence) continue;
        const toRad = (deg) => (deg * Math.PI) / 180;
        const haversineMeters = (lat1, lon1, lat2, lon2) => {
          const R = 6371000;
          const dLat = toRad(lat2 - lat1);
          const dLon = toRad(lon2 - lon1);
          const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
            Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) *
            Math.sin(dLon / 2) * Math.sin(dLon / 2);
          const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
          return R * c;
        };
        const distanceMeters = haversineMeters(geofence.latitude, geofence.longitude, item.latitude, item.longitude);
        if (distanceMeters > geofence.radius) continue;

        if (item.type === 'checkin') {
          await Attendance.create({
            employee: req.user._id,
            geofence: geofence._id,
            checkIn: item.timestamp ? new Date(item.timestamp) : new Date(),
            status: 'in',
            location: { lat: item.latitude, lng: item.longitude },
          });
        } else if (item.type === 'checkout') {
          const openRecord = await Attendance.findOne({ employee: req.user._id, geofence: geofence._id, checkOut: { $exists: false } }).sort({ createdAt: -1 });
          if (openRecord) {
            openRecord.checkOut = item.timestamp ? new Date(item.timestamp) : new Date();
            openRecord.status = 'out';
            openRecord.location = { lat: item.latitude, lng: item.longitude };
            await openRecord.save();
          }
        }
        results.attendanceProcessed++;
      } catch (_) {}
    }
    res.status(200).json({ message: 'Sync processed', results });
  } catch (e) {
    res.status(500).json({ message: 'Sync failed' });
  }
});

// Error handling middleware (JSON responses)
const { notFound, errorHandler } = require('./middleware/errorMiddleware');
app.use(notFound);
app.use(errorHandler);

const port = process.env.PORT || 3000;

// Gracefully handle server listen errors (e.g., port already in use)
server.on('error', (err) => {
  if (err && err.code === 'EADDRINUSE') {
    console.log(`Port ${port} in use; backend already running. Skipping start.`);
    process.exit(0);
  } else {
    console.error('Server error:', err);
    process.exit(1);
  }
});

process.on('unhandledRejection', (reason, promise) => {
  console.error('Unhandled Rejection at:', promise, 'reason:', reason);
});

process.on('uncaughtException', (error) => {
  console.error('Uncaught Exception:', error);
  process.exit(1);
});

(async () => {
  try {
    await connectDB();
    if (process.env.USE_INMEMORY_DB === 'true' || process.env.SEED_DEV === 'true') {
      const { seedDevData } = require('./utils/seedDev');
      await seedDevData();
    }
    
    // Initialize automation jobs (email verification cleanup, etc.)
    const { initializeAutomation } = require('./utils/automationService');
    initializeAutomation();
    
    server.listen(port, () => { // Use server.listen instead of app.listen
      console.log(`Backend server listening at http://localhost:${port}`);
    });
  } catch (err) {
    console.error('Failed to start server:', err);
    process.exit(1);
  }
})();