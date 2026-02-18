import express from 'express';
import cors from 'cors';
import compression from 'compression';
import rateLimit from 'express-rate-limit';
import helmet from 'helmet';
import dotenv from 'dotenv';
import http from 'http';
import { Server as SocketIOServer } from 'socket.io';
import logger from './config/logger.js';
import pool from './config/database.js';
import startFirestoreSync from './utils/firestoreSync.js';
import { getEmailService } from './utils/emailService.js';
import { errorHandler, notFound } from './middleware/errorHandler.js';
import ReactiveSyncManager from './services/ReactiveSyncManager.js';

// Routes
import productRoutes from './routes/productRoutes.js';
import storeRoutes from './routes/storeRoutes.js';
import orderRoutes from './routes/orderRoutes.js';
import userRoutes from './routes/userRoutes.js';
import cartRoutes from './routes/cartRoutes.js';
import deliveryRoutes from './routes/deliveryRoutes.js';
import adminRoutes from './routes/adminRoutes.js'; // this is yahop admin routes
import adminsMgmtRoutes from './routes/adminsRoutes.js';
import staffRoutes from './routes/staffRoutes.js';
import authRoutes from './routes/authRoutes.js';
import categoryRoutes from './routes/categoryRoutes.js'; // ✨ Categories
import returnsRoutes from './routes/returnsRoutes.js'; // 📦 Returns Management
import aiRoutes from './routes/aiRoutes.js'; // 🤖 YSHOP AI Conversational Shopping

dotenv.config();

const app = express();
const PORT = process.env.PORT || 3000;

// Security Middleware
app.use(helmet());

// CORS Configuration
app.use(
  cors({
    origin: process.env.NODE_ENV === 'production' 
      ? ['http://localhost:3000'] // Update with production domain
      : '*',
    credentials: true,
  })
);

// Body Parser
app.use(express.json({ limit: '50mb' }));
app.use(express.urlencoded({ limit: '50mb', extended: true }));

// Request logger - only log non-static requests in development
app.use((req, res, next) => {
  // Skip logging for static files and health checks
  if (!req.url.includes('/uploads/') && !req.url.includes('/health')) {
    if (process.env.NODE_ENV === 'development') {
      const authHeader = req.headers.authorization ? '[AUTH]' : '[NO-AUTH]';
      console.log(`[${new Date().toISOString()}] ${req.method} ${req.originalUrl} ${authHeader}`);
    }
  }
  next();
});

// Compression
app.use(compression());

//  Smart caching: Admin endpoints should NOT be cached, public endpoints can be
app.use((req, res, next) => {
  if (req.method === 'GET') {
    //  CRITICAL: Admin endpoints must NOT be cached to prevent stale data
    if (req.path.includes('/admin') || req.path.includes('/admins') || req.path.includes('/dashboard')) {
      res.set('Cache-Control', 'no-cache, no-store, must-revalidate, max-age=0');
      res.set('Pragma', 'no-cache');
      res.set('Expires', '0');
    } else {
      // Public endpoints can use cache (5 minutes)
      res.set('Cache-Control', 'public, max-age=300');
    }
  } else {
    res.set('Cache-Control', 'no-cache, no-store, must-revalidate');
  }
  next();
});

// Rate Limiting (prevent abuse)
// Global IP-based rate limiter
const globalLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 500, // limit each IP to 500 requests per windowMs
  message: 'Too many requests from this IP, please try again later.',
  standardHeaders: true,
  legacyHeaders: false,
});

//  NEW: Per-user rate limiter (prevent one user from flooding)
const userLimiter = rateLimit({
  keyGenerator: (req, res) => {
    // Use user ID if authenticated (JWT now contains uid)
    if (req.user?.id) return `user_${req.user.id}`;
    if (req.admin?.id) return `admin_${req.admin.id}`;
    return req.ip || 'unknown';
  },
  windowMs: 1 * 60 * 1000, // 1 minute window
  max: 300, // 🔥 INCREASED from 100 to 300 requests per user per minute (previously was too restrictive)
  message: 'Too many requests from this user, please try again later.',
  standardHeaders: false,
  legacyHeaders: false,
  // Skip rate limit for health checks
  skip: (req) => req.url === '/health',
});

app.use(globalLimiter);
app.use(userLimiter);

// Static files for uploads
app.use('/uploads', express.static('uploads'));

// Static files for verification emails
app.use(express.static('public'));

// API Routes
app.use('/api/v1/products', productRoutes);
app.use('/api/v1/stores', storeRoutes);
app.use('/api/v1/orders', orderRoutes);
app.use('/api/v1/users', userRoutes);
app.use('/api/v1/cart', cartRoutes);
app.use('/api/v1/delivery-requests', deliveryRoutes);
app.use('/api/v1/admin', adminRoutes);
app.use('/api/v1/admins', adminsMgmtRoutes);
app.use('/api/v1/staff', staffRoutes);
app.use('/api/v1/auth', authRoutes);
app.use('/api/v1/returns', returnsRoutes); // 📦 Returns Management
app.use('/api/v1/stores', categoryRoutes); // ✨ Categories under stores
app.use('/api/v1/categories', categoryRoutes); // ✨ Categories direct access
app.use('/api/v1', categoryRoutes); // ✨ Products category assignment
app.use('/api/v1/ai', aiRoutes); // 🤖 YSHOP AI Conversational Shopping

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'ok', message: 'Server is running' });
});

// 404 Handler
app.use(notFound);

// Error Handler
app.use(errorHandler);

// ═══════════════════════════════════════════════════════════════════════════
// 🔥 SOCKET.IO SETUP FOR REACTIVE SYNC
// ═══════════════════════════════════════════════════════════════════════════

const httpServer = http.createServer(app);
const io = new SocketIOServer(httpServer, {
  cors: {
    origin: process.env.NODE_ENV === 'production' 
      ? ['http://localhost:3000']
      : ['http://localhost', 'http://localhost:3000', '*'],
    credentials: true,
  },
  transports: ['websocket', 'polling'],
  pingInterval: 25000,
  pingTimeout: 60000,
});

// ✅ Socket.io Connection Handler
io.on('connection', (socket) => {
  logger.info(`🔗 NEW SOCKET CONNECTION`, { socketId: socket.id });

  // 📡 Subscribe to data channel
  socket.on('subscribe', (channel) => {
    logger.info(`>>> SUBSCRIBE REQUEST`, { socketId: socket.id, channel });
    socket.join(channel); // Join Socket.io room
    ReactiveSyncManager.subscribe(channel, socket.id);
  });

  // ❌ Unsubscribe from channel
  socket.on('unsubscribe', (channel) => {
    logger.info(`>>> UNSUBSCRIBE REQUEST`, { socketId: socket.id, channel });
    socket.leave(channel);
    ReactiveSyncManager.unsubscribe(channel, socket.id);
  });

  // 💻 Get sync stats
  socket.on('get-stats', () => {
    socket.emit('stats', ReactiveSyncManager.getStats());
  });

  // ❌ Disconnect
  socket.on('disconnect', () => {
    logger.info(`🔌 SOCKET DISCONNECTED`, { socketId: socket.id });
    // Clean up all subscriptions for this socket
    for (const [channel, sockets] of ReactiveSyncManager.subscribers ?? new Map()) {
      if (sockets && sockets.has(socket.id)) {
        ReactiveSyncManager.unsubscribe(channel, socket.id);
      }
    }
  });

  socket.on('error', (error) => {
    logger.error(`❌ SOCKET ERROR`, { socketId: socket.id, error });
  });
});

// 📡 Connect ReactiveSyncManager broadcasts to Socket.io
ReactiveSyncManager.on('broadcast', (msg) => {
  const { channel, message } = msg;
  io.to(channel).emit('data:delta', message);
  logger.debug(`📡 BROADCASTED TO SOCKET.IO ROOM`, {
    channel,
    subscribers: msg.subscribers?.length,
  });
});

// Start Server
const server = httpServer.listen(PORT, async () => {
  try {
    // Test database connection
    const connection = await pool.getConnection();
    await connection.execute('SELECT 1');
    
    // Initialize required database columns
    try {
      // Ensure latitude and longitude columns exist
      await connection.execute(`
        ALTER TABLE delivery_requests 
        ADD COLUMN IF NOT EXISTS latitude DECIMAL(10,8) NULL,
        ADD COLUMN IF NOT EXISTS longitude DECIMAL(11,8) NULL
      `);
      logger.info('✓ Delivery request location columns verified');
    } catch (dbErr) {
      logger.warn('⚠ Could not verify location columns:', dbErr.message);
    }
    
    // Ensure currency column exists
    try {
      await connection.execute(`
        ALTER TABLE orders 
        ADD COLUMN IF NOT EXISTS currency VARCHAR(10) DEFAULT 'USD'
      `);
      logger.info('✓ Orders currency column verified');
    } catch (dbErr) {
      logger.warn('⚠ Could not verify currency column:', dbErr.message);
    }
    
    connection.release();
    
    logger.info(` Server running on http://localhost:${PORT}`);
    logger.info(` Database connected successfully`);
    
    // Initialize email service
    try {
      await getEmailService();
      logger.info('✓ Email service initialized');
    } catch (e) {
      logger.warn('⚠ Email service initialization warning:', e.message);
    }
    
    // Start Firestore -> MySQL sync task (if Firebase configured)
    try {
      startFirestoreSync();
    } catch (e) {
      logger.warn('Could not start Firestore sync:', e.message);
    }
  } catch (error) {
    logger.error('❌ Failed to connect to database:', error);
    process.exit(1);
  }
});

// Graceful Shutdown
process.on('SIGINT', async () => {
  logger.info('Shutting down gracefully...');
  ReactiveSyncManager.cleanup();
  io.close();
  server.close(async () => {
    await pool.end();
    logger.info('Server closed');
    process.exit(0);
  });
});

export default app;
