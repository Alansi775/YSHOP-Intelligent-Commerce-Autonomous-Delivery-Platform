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
import { runAITablesMigration } from '../database/migrations/20260712_add_ai_tables.js';
import { runImageEmbeddingMigration } from '../database/migrations/20260712_add_image_embedding.js';
import { runPOSMigration } from '../database/migrations/20260719_add_pos_system.js';
import { runStoreSettlementsMigration } from '../database/migrations/20260802_add_store_settlements.js';
import { VectorStore } from './services/VectorStore.js';

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
import categoryRoutes from './routes/categoryRoutes.js'; //  Categories
import returnsRoutes from './routes/returnsRoutes.js'; // 📦 Returns Management
import complaintRoutes from './routes/complaintRoutes.js'; // 🚨 Complaints
import aiRoutes from './routes/aiRoutes.js'; //  YSHOP AI Conversational Shopping
import analyticsRoutes from './routes/analyticsRoutes.js'; // 📊 Store Analytics
import adminSalesRoutes from './routes/adminSalesRoutes.js'; // 💰 Admin Sales/Settlements
import posRoutes from './routes/posRoutes.js'; // 🍽️ Local POS System
import POSController from './controllers/POSController.js';

dotenv.config();

const app = express();
const PORT = process.env.PORT || 3000;

// Security Middleware
app.use(helmet());

// CORS Configuration — CORS_ORIGIN accepts a comma-separated list so both
// Firebase Hosting domains (and any future custom domain) can be allowed
// without another code change, just an env var update.
const allowedOrigins = (process.env.CORS_ORIGIN || 'http://Mohammeds-Mackbook-MacBook-Air.local:3000')
  .split(',')
  .map((o) => o.trim())
  .filter(Boolean);

// CORS Configuration
app.use(
  cors({
    origin: process.env.NODE_ENV === 'production'
      ? allowedOrigins
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
  // /uploads/* gets its own long-lived immutable cache below — every upload
  // gets a fresh UUID filename (see productRoutes.js/storeRoutes.js multer
  // config), so a given URL's bytes never change. Skip this 5min JSON-API
  // rule here so it doesn't get clobbered by the static handler.
  if (req.path.startsWith('/uploads')) {
    return next();
  }
  if (req.method === 'GET') {
    //  CRITICAL: Admin + POS endpoints must NOT be cached to prevent stale data
    // POS (cashier/kitchen/tables) is real-time — a 5min public cache here means
    // deleted/updated rows silently keep showing on screen until the cache expires.
    if (req.path.includes('/admin') || req.path.includes('/admins') || req.path.includes('/dashboard') || req.path.includes('/pos')) {
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

// Static files for uploads — every upload gets a brand-new UUID filename
// (see productRoutes.js/storeRoutes.js multer `filename:`), so a given URL's
// bytes are permanently immutable: a store owner editing a photo produces a
// NEW url (new DB row value), never overwrites the old file. Safe to cache
// as long as the browser will let us — the client naturally picks up real
// edits because it's a URL it has never fetched before, no invalidation
// needed. This lets repeat visits (leave the screen, come back) load
// straight from local disk cache with zero request to the server.
app.use('/uploads', express.static('uploads', {
  maxAge: '365d',
  immutable: true,
}));

// Any /uploads/* path that isn't an actual file on disk (missing/never
// migrated image) falls back to a placeholder instead of a broken-image
// icon in Flutter/SwiftUI — express.static() above calls next() on a miss.
app.use('/uploads', (req, res) => {
  res.sendFile('placeholder.png', { root: 'public' });
});

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
app.use('/api/v1/complaints', complaintRoutes); // 🚨 Complaints
app.use('/api/v1/stores', categoryRoutes); //  Categories under stores
app.use('/api/v1/categories', categoryRoutes); //  Categories direct access
app.use('/api/v1', categoryRoutes); //  Products category assignment
app.use('/api/v1/ai', aiRoutes); //  YSHOP AI Conversational Shopping
app.use('/api/v1/analytics', analyticsRoutes); // 📊 Store Analytics
app.use('/api/v1/admin/sales', adminSalesRoutes); // 💰 Admin Sales/Settlements
app.use('/api/v1/pos', posRoutes); // 🍽️ Local POS System

// Public customer tracking page (no auth — scanned from QR on table)
app.get('/pos/track/:token', POSController.customerTrack);

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'ok', message: 'Server is running' });
});

// Discovery endpoint — lets Swift app find the server IP with no auth
app.get('/api/v1/discover', (req, res) => {
  const host = req.headers.host || `${process.env.API_BASE_URL || 'localhost:3000'}`;
  const baseURL = `http://${host}/api/v1`;
  res.json({ success: true, baseURL, name: 'YShop' });
});

// 404 Handler
app.use(notFound);

// Error Handler
app.use(errorHandler);

// ═══════════════════════════════════════════════════════════════════════════
// 🔥 SOCKET.IO SETUP FOR REACTIVE SYNC
// ═══════════════════════════════════════════════════════════════════════════

const httpServer = http.createServer(app);
import { setIO } from './utils/socketInstance.js';

const io = new SocketIOServer(httpServer, {
  cors: {
    origin: process.env.NODE_ENV === 'production'
      ? allowedOrigins
      : ['*'],
    credentials: true,
  },
  transports: ['websocket', 'polling'],
  pingInterval: 25000,
  pingTimeout: 60000,
});

//  Socket.io Connection Handler
setIO(io);
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

  // 🍽️ POS room subscription (kitchen, cashier, customer tracking)
  // Room name: `pos:{storeId}` — all POS events for a store go here
  socket.on('pos:join', (storeId) => {
    const room = `pos:${storeId}`;
    socket.join(room);
    logger.info(`[POS] ${socket.id} joined ${room}`);
  });
  socket.on('pos:leave', (storeId) => {
    socket.leave(`pos:${storeId}`);
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

// ─── Resilience: catch network-level errors before they crash Node ────────────

// Each raw TCP connection that Express/Socket.io uses can emit 'error' when the
// client abruptly disconnects (mobile going background, flaky network, etc.).
// Without this listener Node throws an uncaught 'error' event and crashes.
httpServer.on('connection', (socket) => {
  socket.on('error', (err) => {
    if (err.code === 'ECONNRESET' || err.code === 'EPIPE') return; // normal mobile disconnect
    logger.warn('TCP socket error:', { code: err.code, message: err.message });
  });
});

httpServer.on('error', (err) => {
  logger.error('HTTP server error:', err);
});

// Catch any exception that escapes all try/catch blocks.
// ECONNRESET / EPIPE are transient network events — ignore and stay alive.
// Everything else: log then exit so the process manager can restart cleanly.
process.on('uncaughtException', (err) => {
  if (err.code === 'ECONNRESET' || err.code === 'EPIPE') {
    logger.warn(`Ignoring transient network error: ${err.code}`);
    return;
  }
  logger.error('UNCAUGHT EXCEPTION — exiting:', err);
  process.exit(1);
});

process.on('unhandledRejection', (reason) => {
  logger.error('UNHANDLED REJECTION:', reason);
  // Don't exit — log and keep running; a single rejected promise shouldn't kill the server
});

// ─────────────────────────────────────────────────────────────────────────────

// Start Server
const server = httpServer.listen(PORT, '0.0.0.0', async () => {
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
    
    logger.info(` Server running on http://${process.env.API_BASE_URL ? new URL(process.env.API_BASE_URL).hostname : 'localhost'}:${PORT}`);
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

    // Run AI infrastructure migrations
    try {
      await runAITablesMigration();
      await runImageEmbeddingMigration(); // adds image_embedding column if missing
    } catch (e) {
      logger.warn('⚠ AI tables migration warning:', e.message);
    }

    // Run POS system migration
    try {
      await runPOSMigration();
    } catch (e) {
      logger.warn('⚠ POS migration warning:', e.message);
    }

    // Run store settlements migration
    try {
      await runStoreSettlementsMigration();
    } catch (e) {
      logger.warn('⚠ Store settlements migration warning:', e.message);
    }

    // Backfill product embeddings in background — non-blocking
    setImmediate(() => {
      VectorStore.backfillMissing()
        .then(() => {
          // After text backfill, add image embeddings to products that lack them.
          // Slow (2s/product) to stay under Gemini Vision free-tier rate limits.
          setTimeout(() => VectorStore.backfillImages(50).catch(err =>
            logger.warn(`⚠ Image backfill warning: ${err?.stack || err?.message || String(err)}`),
          ), 5000);
        })
        .catch(err => logger.warn('⚠ Embedding backfill warning:', err.message));
    });
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
