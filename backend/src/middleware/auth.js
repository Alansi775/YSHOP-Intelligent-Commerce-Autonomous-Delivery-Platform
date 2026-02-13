import jwt from 'jsonwebtoken';
import pool from '../config/database.js';
import logger from '../config/logger.js';

const JWT_SECRET = process.env.ADMIN_JWT_SECRET || process.env.JWT_SECRET || 'change_this_secret';

// Verify JWT token for regular users
export const verifyJWTToken = async (req, res, next) => {
  try {
    const authHeader = req.headers.authorization || '';
    const token = authHeader.split(' ')[1];

    if (!token) {
      logger.warn('[verifyJWTToken] No token provided', { path: req.path });
      return res.status(401).json({ success: false, message: 'Unauthorized: No token provided' });
    }

    // Verify JWT
    let decoded;
    try {
      decoded = jwt.verify(token, JWT_SECRET);
      logger.info('[verifyJWTToken] Token verified successfully');
    } catch (err) {
      logger.warn(`[verifyJWTToken] Token verification failed: ${err.message}`, { path: req.path });
      return res.status(401).json({ success: false, message: 'Unauthorized: Invalid or expired token' });
    }

    // Attach user to request
    req.user = {
      id: decoded.id,
      email: decoded.email,
      role: decoded.role,
    };

    logger.info('[verifyJWTToken] User attached to request', {
      userId: req.user.id,
      email: req.user.email,
      role: req.user.role,
      path: req.path,
    });

    next();
  } catch (error) {
    logger.error('Auth middleware error:', error);
    return res.status(401).json({ success: false, message: 'Unauthorized' });
  }
};

// Verify admin JWT token (for admin routes)
export const verifyAdminToken = async (req, res, next) => {
  try {
    const authHeader = req.headers.authorization || '';
    const token = authHeader.split(' ')[1];
    logger.info(`[verifyAdminToken] Endpoint: ${req.path}`);

    if (!token) {
      logger.warn('[verifyAdminToken] No token provided');
      return res.status(401).json({ success: false, message: 'Unauthorized: No token provided' });
    }

    // Try admin JWT first
    let decoded;
    try {
      decoded = jwt.verify(token, JWT_SECRET);
      logger.info(`[verifyAdminToken] Token verified. Role: ${decoded.role}`);
    } catch (err) {
      logger.warn('Invalid admin JWT token:', err.message);
      return res.status(401).json({ success: false, message: 'Unauthorized: Invalid token' });
    }

    // Check if token has admin role claim
    if (decoded.role && (decoded.role === 'admin' || decoded.role === 'superadmin')) {
      // Token claims to be admin, attach to request
      logger.info(`[verifyAdminToken] Admin verified. Role: ${decoded.role}`);
      req.admin = {
        id: decoded.id,
        email: decoded.email,
        role: decoded.role,
      };
      return next();
    }
    logger.warn(`[verifyAdminToken] Token role not admin. Role: ${decoded.role}`);

    // If not admin via role, try to verify from database as fallback
    const connection = await pool.getConnection();
    const [adminRows] = await connection.execute(
      'SELECT id, email, role FROM yshopadmins WHERE id = ? AND (role = ? OR role = ?)',
      [decoded.id, 'admin', 'superadmin']
    );
    connection.release();

    if (adminRows.length === 0) {
      logger.warn(`Admin verification failed for ID: ${decoded.id}`);
      return res.status(403).json({ success: false, message: 'Forbidden: Not an admin' });
    }

    // Attach admin to request
    req.admin = {
      id: decoded.id,
      email: decoded.email,
      role: adminRows[0].role,
    };

    next();
  } catch (error) {
    logger.error('Admin auth middleware error:', error);
    return res.status(401).json({ success: false, message: 'Unauthorized' });
  }
};

// Optional: Verify either user or admin
export const verifyToken = async (req, res, next) => {
  try {
    const authHeader = req.headers.authorization || '';
    const token = authHeader.split(' ')[1];

    if (!token) {
      logger.warn('[verifyToken] No token provided');
      return res.status(401).json({ success: false, message: 'Unauthorized: No token provided' });
    }

    logger.info('[verifyToken] Token provided, attempting to verify...');

    const secret = process.env.ADMIN_JWT_SECRET || process.env.JWT_SECRET || 'change_this_secret';

    let decoded;
    try {
      decoded = jwt.verify(token, secret);
      logger.info(`[verifyToken] Token verified successfully. Role: ${decoded.role}, ID: ${decoded.id}`);
    } catch (err) {
      logger.warn(`[verifyToken] Token verification failed: ${err.message}`);
      return res.status(401).json({ success: false, message: 'Unauthorized: Invalid or expired token' });
    }

    // Attach to request (could be user or admin)
    if (decoded.role && (decoded.role === 'admin' || decoded.role === 'superadmin')) {
      logger.info(`[verifyToken] Authenticated as admin. Role: ${decoded.role}`);
      req.admin = {
        id: decoded.id,
        email: decoded.email,
        role: decoded.role,
      };
    } else {
      logger.info(`[verifyToken] Authenticated as user. Role: ${decoded.role}`);
      req.user = {
        id: decoded.id,
        email: decoded.email,
        role: decoded.role || 'customer',
      };
    }

    next();
  } catch (error) {
    logger.error('[verifyToken] Error:', error);
    return res.status(401).json({ success: false, message: 'Unauthorized' });
  }
};

// Verify admin role (checks if user has admin permissions)
export const verifyAdminRole = async (req, res, next) => {
  try {
    if (req.admin && (req.admin.role === 'admin' || req.admin.role === 'superadmin')) return next();
    return res.status(403).json({ success: false, message: 'Forbidden: Admin role required' });
  } catch (err) {
    logger.error('verifyAdminRole error:', err);
    return res.status(500).json({ success: false, message: 'Internal server error' });
  }
};

// Legacy export for backwards compatibility
export const verifyFirebaseToken = verifyJWTToken;
export const authMiddleware = verifyJWTToken;
export const adminMiddleware = verifyAdminRole;

export default { verifyJWTToken, verifyAdminToken, verifyToken, verifyAdminRole, verifyFirebaseToken, authMiddleware, adminMiddleware };