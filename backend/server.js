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

dotenv.config();

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
const limiter = rateLimit({ windowMs: 15 * 60 * 1000, max: 100 });
app.use(limiter);

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

// Simple dev sync endpoint to accept offline submissions
app.post('/api/sync', (req, res) => {
  // In a real app, inspect payload by dataType and persist
  res.status(200).json({ message: 'Sync received' });
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

(async () => {
  await connectDB();
  if (process.env.USE_INMEMORY_DB === 'true' || process.env.SEED_DEV === 'true') {
    const { seedDevData } = require('./utils/seedDev');
    await seedDevData();
  }
  server.listen(port, () => { // Use server.listen instead of app.listen
    console.log(`Backend server listening at http://localhost:${port}`);
  });
})();