import bcrypt from 'bcryptjs';
import { OAuth2Client } from 'google-auth-library';
import pool from '../config/database.js';
import logger from '../config/logger.js';
import { generateJWT, generateVerificationToken, generateTokenExpiry } from '../utils/tokenUtils.js';
import { getEmailService } from '../utils/emailService.js';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const GOOGLE_OAUTH_CLIENT_ID = process.env.GOOGLE_OAUTH_CLIENT_ID;
const googleClient = new OAuth2Client(GOOGLE_OAUTH_CLIENT_ID);

class AuthController {
  // POST /api/v1/auth/signup
  static async signup(req, res, next) {
    try {
      const { 
        email, password, display_name, phone, national_id, address, latitude, longitude, building_info, apartment_number, delivery_instructions
      } = req.body;

      if (!email || !password || !display_name) {
        return res.status(400).json({ 
          success: false, 
          message: 'email, password, and display_name are required' 
        });
      }

      const connection = await pool.getConnection();

      const [existingUsers] = await connection.execute('SELECT id FROM users WHERE email = ?', [email]);
      if (existingUsers.length > 0) {
        connection.release();
        return res.status(409).json({ success: false, message: 'Email already registered' });
      }

      const passwordHash = await bcrypt.hash(password, 10);
      const uid = `user_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;

      const nameParts = display_name.trim().split(/\s+/);
      const firstName = nameParts[0] || '';
      const lastName = nameParts.slice(1).join(' ') || '';

      // Generate token + expiry (24 hours)
      const verificationToken = generateVerificationToken();
      const tokenExpires = generateTokenExpiry(24);

      //  احفظ التوكين في DB
      await connection.execute(
        `INSERT INTO users (uid, email, password_hash, display_name, name, surname, phone, national_id, address, latitude, longitude, building_info, apartment_number, delivery_instructions, email_verified, verification_token, verification_token_expires) 
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, FALSE, ?, ?)`,
        [uid, email, passwordHash, display_name, firstName, lastName, phone || null, national_id || null, address || null, latitude || null, longitude || null, building_info || null, apartment_number || null, delivery_instructions || null, verificationToken, tokenExpires]
      );

      connection.release();

      try {
        const emailService = await getEmailService();
        await emailService.sendVerificationEmail(email, verificationToken, display_name, 'en');
        logger.info(`Verification email sent to ${email}`);
      } catch (emailError) {
        logger.warn(`Failed to send verification email to ${email}:`, emailError.message);
      }

      return res.status(201).json({
        success: true,
        message: 'Account created! Check your email for verification details.',
        email,
        uid,
      });
    } catch (error) {
      logger.error('Error in signup:', error);
      next(error);
    }
  }

  // POST /api/v1/auth/delivery-signup
  static async deliverySignup(req, res, next) {
    try {
      const { 
        email, password, name, phone, national_id, address, latitude, longitude
      } = req.body;

      if (!email || !password || !name || !phone) {
        return res.status(400).json({ 
          success: false, 
          message: 'email, password, name, and phone are required' 
        });
      }

      const connection = await pool.getConnection();

      //  شيك في الجدولين عشان ما يكرر الإيميل
      const [existingUsers] = await connection.execute('SELECT id FROM users WHERE email = ?', [email]);
      const [existingDrivers] = await connection.execute('SELECT id FROM delivery_requests WHERE email = ?', [email]);
      
      if (existingUsers.length > 0 || existingDrivers.length > 0) {
        connection.release();
        return res.status(409).json({ success: false, message: 'Email already registered' });
      }

      const passwordHash = await bcrypt.hash(password, 10);
      const uid = `driver_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;

      const verificationToken = generateVerificationToken();
      const tokenExpires = generateTokenExpiry(24);

      //  احفظ في delivery_requests (مش users)
      await connection.execute(
        `INSERT INTO delivery_requests 
          (uid, email, password_hash, name, phone, national_id, address, latitude, longitude, status, email_verified, verification_token, verification_token_expires) 
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [
          uid, 
          email, 
          passwordHash, 
          name, 
          phone, 
          national_id || null, 
          address || null, 
          latitude || null, 
          longitude || null,
          'Pending',
          0,
          verificationToken,
          tokenExpires
        ]
      );

      connection.release();

      try {
        const emailService = await getEmailService();
        await emailService.sendVerificationEmail(email, verificationToken, name, 'en');
        logger.info(`Verification email sent to ${email}`);
      } catch (emailError) {
        logger.warn(`Failed to send verification email to ${email}:`, emailError.message);
      }

      logger.info(`New delivery driver signup: ${email}`);

      return res.status(201).json({
        success: true,
        message: 'Account created! Please verify your email, then wait for admin approval.',
        email,
        uid,
      });
    } catch (error) {
      logger.error('Error in deliverySignup:', error);
      next(error);
    }
  }

  // POST /api/v1/auth/verify-email
  static async verifyEmail(req, res, next) {
    try {
      const { token } = req.body;

      if (!token) {
        return res.status(400).json({ success: false, message: 'Verification token is required' });
      }

      const connection = await pool.getConnection();

      // Find user with this token
      const [users] = await connection.execute(
        `SELECT id, email FROM users 
         WHERE verification_token = ? AND verification_token_expires > NOW()`,
        [token]
      );

      if (users.length === 0) {
        connection.release();
        return res.status(400).json({ success: false, message: 'Invalid or expired verification token' });
      }

      const user = users[0];

      // Update user to mark email as verified
      await connection.execute(
        `UPDATE users 
         SET email_verified = 1, verification_token = NULL, verification_token_expires = NULL 
         WHERE id = ?`,
        [user.id]
      );

      connection.release();

      return res.json({
        success: true,
        message: 'Email verified successfully. You can now log in.',
      });
    } catch (error) {
      logger.error('Error in verifyEmail:', error);
      next(error);
    }
  }

  // GET /api/v1/auth/verify-email?token=xxx
  static async verifyEmailFromLink(req, res, next) {
    const __filename = fileURLToPath(import.meta.url);
    const __dirname = dirname(__filename);
    const successPath = join(__dirname, '../../public/verify-email-success.html');
    const errorPath = join(__dirname, '../../public/verify-email-error.html');

    try {
      const { token } = req.query;

      if (!token) {
        return res.status(400).sendFile(errorPath);
      }

      const connection = await pool.getConnection();

      // 1) شيك في stores
      const [storesWithToken] = await connection.execute(
        `SELECT id, email FROM stores 
         WHERE email_verified = 0 AND verification_token = ? 
         AND (verification_token_expires IS NULL OR verification_token_expires > NOW()) 
         LIMIT 1`,
        [token]
      );

      if (storesWithToken.length > 0) {
        await connection.execute(
          `UPDATE stores SET email_verified = 1, verification_token = NULL, verification_token_expires = NULL WHERE id = ?`,
          [storesWithToken[0].id]
        );
        logger.info(` Store email verified: ${storesWithToken[0].email}`);
        connection.release();
        return res.status(200).sendFile(successPath);
      }

      // 2) شيك في users (الزبائن)
      const [usersWithToken] = await connection.execute(
        `SELECT id, email FROM users 
         WHERE email_verified = 0 AND verification_token = ? 
         AND (verification_token_expires IS NULL OR verification_token_expires > NOW()) 
         LIMIT 1`,
        [token]
      );

      if (usersWithToken.length > 0) {
        await connection.execute(
          `UPDATE users SET email_verified = 1, verification_token = NULL, verification_token_expires = NULL WHERE id = ?`,
          [usersWithToken[0].id]
        );
        logger.info(` User email verified: ${usersWithToken[0].email}`);
        connection.release();
        return res.status(200).sendFile(successPath);
      }

      // 3)  شيك في delivery_requests (الموصلين)
      const [driversWithToken] = await connection.execute(
        `SELECT id, email FROM delivery_requests 
         WHERE email_verified = 0 AND verification_token = ? 
         AND (verification_token_expires IS NULL OR verification_token_expires > NOW()) 
         LIMIT 1`,
        [token]
      );

      if (driversWithToken.length > 0) {
        await connection.execute(
          `UPDATE delivery_requests SET email_verified = 1, verification_token = NULL, verification_token_expires = NULL WHERE id = ?`,
          [driversWithToken[0].id]
        );
        logger.info(` Driver email verified: ${driversWithToken[0].email}`);
        connection.release();
        return res.status(200).sendFile(successPath);
      }

      connection.release();
      // ما لقى التوكين في أي جدول
      return res.status(400).sendFile(errorPath);

    } catch (error) {
      logger.error('Error in verifyEmailFromLink:', error);
      return res.status(500).sendFile(errorPath);
    }
  }

  // POST /api/v1/auth/login
  static async login(req, res, next) {
    try {
      const { email, password } = req.body;

      if (!email || !password) {
        return res.status(400).json({ success: false, message: 'email and password are required' });
      }

      const connection = await pool.getConnection();

      // Find user
      const [users] = await connection.execute(
        `SELECT id, uid, email, password_hash, display_name, email_verified FROM users WHERE email = ?`,
        [email]
      );

      if (users.length === 0) {
        connection.release();
        return res.status(401).json({ success: false, message: 'Invalid email or password' });
      }

      const user = users[0];

      // Check if email is verified
      if (!user.email_verified) {
        connection.release();
        return res.status(403).json({ 
          success: false, 
          message: 'Please verify your email before logging in',
          requiresVerification: true,
        });
      }

      // Verify password
      const passwordMatch = await bcrypt.compare(password, user.password_hash);
      if (!passwordMatch) {
        connection.release();
        return res.status(401).json({ success: false, message: 'Invalid email or password' });
      }

      // Check if user is a delivery driver
      const [deliveryRequests] = await connection.execute(
        `SELECT id, status FROM delivery_requests WHERE email = ? LIMIT 1`,
        [email]
      );

      let userType = 'customer';
      let isDeliveryDriver = false;
      let driverStatus = null;

      if (deliveryRequests.length > 0) {
        isDeliveryDriver = true;
        driverStatus = deliveryRequests[0].status;

        // Check if driver is approved by admin
        if (driverStatus !== 'approved') {
          connection.release();
          
          if (driverStatus === 'rejected' || driverStatus === 'banned') {
            return res.status(403).json({
              success: false,
              message: `Your delivery driver account has been ${driverStatus} by YSHOP administration. Please contact support.`,
              accountBlocked: true,
            });
          }

          // Status is 'pending'
          return res.status(403).json({
            success: false,
            message: 'Your delivery driver account is pending admin approval. Please wait for YSHOP administration to review your application.',
            requiresApproval: true,
          });
        }

        userType = 'deliveryDriver';
      }

      connection.release();

      // Generate JWT token with UID (required for Foreign Key in cart_items)
      const token = generateJWT(user.uid, user.email, userType);

      return res.json({
        success: true,
        token,
        user: {
          id: user.id,
          uid: user.uid,
          email: user.email,
          display_name: user.display_name,
          userType: userType,
        },
      });
    } catch (error) {
      logger.error('Error in login:', error);
      next(error);
    }
  }

  // POST /api/v1/auth/google — customer sign-in/sign-up via a Google ID token
  // obtained client-side (google_sign_in package). Finds an existing user by
  // email, or creates one (Google already verified the email, so
  // email_verified is set true immediately — no verification email step).
  // The response's needsProfileCompletion flag tells the client whether the
  // required-fields screen (name/surname/national ID/address/etc.) must be
  // shown before the account is usable — mirrors what the email/password
  // signup form already collects.
  static async googleAuth(req, res, next) {
    try {
      const { idToken } = req.body;
      if (!idToken) {
        return res.status(400).json({ success: false, message: 'idToken is required' });
      }
      if (!GOOGLE_OAUTH_CLIENT_ID) {
        logger.error('GOOGLE_OAUTH_CLIENT_ID is not configured on the server');
        return res.status(500).json({ success: false, message: 'Google sign-in is not configured on the server' });
      }

      let payload;
      try {
        const ticket = await googleClient.verifyIdToken({ idToken, audience: GOOGLE_OAUTH_CLIENT_ID });
        payload = ticket.getPayload();
      } catch (err) {
        logger.warn('Google ID token verification failed:', err.message);
        return res.status(401).json({ success: false, message: 'Invalid Google token' });
      }

      const email = payload?.email;
      if (!email) {
        return res.status(400).json({ success: false, message: 'Google account has no email' });
      }

      const connection = await pool.getConnection();
      try {
        const [existing] = await connection.execute('SELECT * FROM users WHERE email = ?', [email]);

        let user;
        let isNewUser = false;

        if (existing.length > 0) {
          user = existing[0];
          if (!user.email_verified) {
            await connection.execute('UPDATE users SET email_verified = TRUE WHERE id = ?', [user.id]);
            user.email_verified = 1;
          }
        } else {
          isNewUser = true;
          const uid = `user_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
          const displayName = payload.name || email.split('@')[0];
          const nameParts = displayName.trim().split(/\s+/);
          const firstName = nameParts[0] || '';
          const lastName = nameParts.slice(1).join(' ') || '';

          await connection.execute(
            `INSERT INTO users (uid, email, password_hash, display_name, name, surname, email_verified)
             VALUES (?, ?, NULL, ?, ?, ?, TRUE)`,
            [uid, email, displayName, firstName, lastName]
          );
          const [rows] = await connection.execute('SELECT * FROM users WHERE uid = ?', [uid]);
          user = rows[0];
        }

        const needsProfileCompletion = !(
          user.name && user.surname && user.national_id && user.address && user.phone
        );

        const token = generateJWT(user.uid, user.email, 'customer');

        return res.json({
          success: true,
          token,
          isNewUser,
          needsProfileCompletion,
          user: {
            id: user.id,
            uid: user.uid,
            email: user.email,
            display_name: user.display_name,
            name: user.name,
            surname: user.surname,
            userType: 'customer',
          },
        });
      } finally {
        connection.release();
      }
    } catch (error) {
      logger.error('Error in googleAuth:', error);
      next(error);
    }
  }

  // POST /api/v1/auth/delivery-login (for delivery drivers)
  static async deliveryLogin(req, res, next) {
    try {
      const { email, password } = req.body;

      if (!email || !password) {
        return res.status(400).json({ success: false, message: 'email and password are required' });
      }

      const connection = await pool.getConnection();

      // Find delivery driver in delivery_requests table
      const [drivers] = await connection.execute(
        `SELECT id, uid, email, password_hash, name, status, email_verified FROM delivery_requests WHERE email = ?`,
        [email]
      );

      if (drivers.length === 0) {
        connection.release();
        return res.status(401).json({ success: false, message: 'Invalid email or password' });
      }

      const driver = drivers[0];

      // Check if email is verified
      if (!driver.email_verified) {
        connection.release();
        return res.status(403).json({ 
          success: false, 
          message: 'Please verify your email before logging in',
          requiresVerification: true,
        });
      }

      // Check if driver is approved by admin
      if (driver.status !== 'Approved' && driver.status !== 'approved') {
        connection.release();
        
        if (driver.status === 'Rejected') {
          return res.status(403).json({
            success: false,
            message: 'Your delivery driver account has been rejected by YSHOP administration. Please contact support.',
            accountBlocked: true,
            uid: driver.uid,
          });
        }

        // Status is 'Pending'
        return res.status(403).json({
          success: false,
          message: 'Your delivery driver account is pending admin approval. Please wait for YSHOP administration to review your application.',
          requiresApproval: true,
          uid: driver.uid,  // Include UID so Frontend can use it
          email: driver.email,
          name: driver.name,
        });
      }

      // Verify password
      const passwordMatch = await bcrypt.compare(password, driver.password_hash);
      if (!passwordMatch) {
        connection.release();
        return res.status(401).json({ success: false, message: 'Invalid email or password' });
      }

      connection.release();

      // Generate JWT token with UID (driver's uid from delivery_requests)
      const token = generateJWT(driver.uid, driver.email, 'deliveryDriver');

      return res.json({
        success: true,
        token,
        user: {
          id: driver.id,
          uid: driver.uid,
          email: driver.email,
          name: driver.name,
          userType: 'deliveryDriver',
        },
      });
    } catch (error) {
      logger.error('Error in deliveryLogin:', error);
      next(error);
    }
  }

  // GET /api/v1/auth/me (get current user profile)
  static async getProfile(req, res, next) {
    try {
      if (!req.user || !req.user.id) {
        return res.status(401).json({ success: false, message: 'Unauthorized' });
      }

      const connection = await pool.getConnection();
      const userRole = req.user.role;

      // If user is a store owner, get store data
      if (userRole === 'storeOwner') {
        const [stores] = await connection.execute(
          `SELECT id, uid, email, name, phone, status, store_type, icon_url, address, latitude, longitude
           FROM stores WHERE uid = ?`,
          [req.user.id]
        );
        connection.release();

        if (stores.length === 0) {
          return res.status(404).json({ success: false, message: 'Store not found' });
        }

        return res.json({
          success: true,
          data: {
            ...stores[0],
            userType: 'storeOwner',
          },
        });
      }

      // If user is a delivery driver, get delivery_requests data
      if (userRole === 'deliveryDriver') {
        const [drivers] = await connection.execute(
          `SELECT id, uid, email, name, phone, status, national_id, address, latitude, longitude
           FROM delivery_requests WHERE uid = ?`,
          [req.user.id]
        );
        connection.release();

        if (drivers.length === 0) {
          return res.status(404).json({ success: false, message: 'Driver not found' });
        }

        return res.json({
          success: true,
          data: {
            ...drivers[0],
            userType: 'deliveryDriver',
          },
        });
      }

      // Otherwise, get regular user data
      const [users] = await connection.execute(
        `SELECT id, uid, email, display_name, phone, address, name, surname, 
                national_id, latitude, longitude, building_info, apartment_number, 
                delivery_instructions, created_at, updated_at 
         FROM users WHERE uid = ?`,
        [req.user.id]
      );

      connection.release();

      if (users.length === 0) {
        return res.status(404).json({ success: false, message: 'User not found' });
      }

      return res.json({
        success: true,
        data: {
          ...users[0],
          userType: userRole || 'customer',
        },
      });
    } catch (error) {
      logger.error('Error in getProfile:', error);
      next(error);
    }
  }

  // PUT /api/v1/auth/me/password
  static async changeMyPassword(req, res, next) {
    try {
      const body = req.body || {};
      const { oldPassword, newPassword } = body;
      if (!oldPassword || !newPassword) return res.status(400).json({ success: false, message: 'oldPassword and newPassword required' });

      const connection = await pool.getConnection();

      // If request authenticated as admin via admin JWT
      if (req.admin && req.admin.id) {
        const adminId = req.admin.id;
        const [adminRows] = await connection.execute('SELECT id, password_hash FROM yshopadmins WHERE id = ?', [adminId]);
        if (adminRows && adminRows.length > 0) {
          const row = adminRows[0];
          const match = await bcrypt.compare(oldPassword, row.password_hash || '');
          if (!match) {
            connection.release();
            return res.status(403).json({ success: false, message: 'Current password is incorrect' });
          }
          const hashed = await bcrypt.hash(newPassword, 10);
          await connection.execute('UPDATE yshopadmins SET password_hash = ? WHERE id = ?', [hashed, row.id]);
          connection.release();
          return res.json({ success: true });
        }
        connection.release();
        return res.status(404).json({ success: false, message: 'Admin not found' });
      }

      // If authenticated as regular user
      if (req.user && req.user.id) {
        const userId = req.user.id;
        const [userRows] = await connection.execute('SELECT id, password_hash FROM users WHERE id = ?', [userId]);
        if (userRows && userRows.length > 0) {
          const row = userRows[0];
          const match = await bcrypt.compare(oldPassword, row.password_hash || '');
          if (!match) {
            connection.release();
            return res.status(403).json({ success: false, message: 'Current password is incorrect' });
          }
          const hashed = await bcrypt.hash(newPassword, 10);
          await connection.execute('UPDATE users SET password_hash = ? WHERE id = ?', [hashed, row.id]);
          connection.release();
          return res.json({ success: true });
        }
        connection.release();
        return res.status(404).json({ success: false, message: 'User not found' });
      }

      connection.release();
      return res.status(401).json({ success: false, message: 'Unauthenticated' });
    } catch (error) {
      logger.error('Error changing password', error);
      next(error);
    }
  }

  // POST /api/v1/auth/store-signup - Store Owner (Merchant) Registration
  static async storeSignup(req, res, next) {
    try {
      const { 
        email, password, phone, address,
        latitude, longitude, storeType, storeName
      } = req.body;

      // storeName is required (اسم المحل)
      if (!email || !password || !phone || !storeName) {
        return res.status(400).json({ 
          success: false, 
          message: 'email, password, phone, and storeName are required' 
        });
      }

      const connection = await pool.getConnection();

      // Check if email already exists in users or stores
      const [existingUsers] = await connection.execute(
        'SELECT id FROM users WHERE email = ?', 
        [email]
      );
      const [existingStores] = await connection.execute(
        'SELECT id FROM stores WHERE email = ?', 
        [email]
      );

      if (existingUsers.length > 0 || existingStores.length > 0) {
        connection.release();
        return res.status(409).json({ success: false, message: 'Email already registered' });
      }

      // Hash password
      const passwordHash = await bcrypt.hash(password, 10);
      
      // Generate verification token
      const verificationToken = generateVerificationToken();
      const tokenExpires = generateTokenExpiry(24);

      // Generate unique UID
      const uid = `store_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;

      // Create store in stores table (NOT in users table)
      // Status should be 'pending' until admin approves
      await connection.execute(
        `INSERT INTO stores (uid, email, password_hash, name, phone, address, 
         latitude, longitude, store_type, status, 
         email_verified, verification_token, verification_token_expires) 
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [uid, email, passwordHash, storeName, phone, address,
         latitude || null, longitude || null, storeType || 'general',
         'pending', 0, verificationToken, tokenExpires]
      );

      connection.release();

      // Send verification email
      try {
        const emailService = await getEmailService();
        await emailService.sendVerificationEmail(email, verificationToken, storeName, 'en');
      } catch (emailError) {
        logger.warn('Failed to send verification email, but store was created:', emailError.message);
      }

      logger.info(`New store signup: ${email} (${storeName})`);

      return res.status(201).json({
        success: true,
        message: 'Store registered successfully. Please verify your email. After email verification, please wait for admin approval.',
        email,
        uid,
      });
    } catch (error) {
      logger.error('Error in storeSignup:', error);
      next(error);
    }
  }

  // POST /api/v1/auth/store-login - Store Owner Login
  static async storeLogin(req, res, next) {
    try {
      const { email, password } = req.body;

      if (!email || !password) {
        return res.status(400).json({ success: false, message: 'email and password are required' });
      }

      const connection = await pool.getConnection();

      // Find store
      const [stores] = await connection.execute(
        `SELECT id, uid, email, password_hash, name, status, email_verified FROM stores WHERE email = ?`,
        [email]
      );

      if (stores.length === 0) {
        connection.release();
        return res.status(401).json({ success: false, message: 'Invalid email or password' });
      }

      const store = stores[0];

      // Check if email is verified
      if (!store.email_verified) {
        connection.release();
        return res.status(403).json({ 
          success: false, 
          message: 'Please verify your email before logging in',
          requiresVerification: true,
        });
      }

      // Check if store is approved by admin
      if (store.status !== 'approved') {
        connection.release();
        
        if (store.status === 'rejected' || store.status === 'banned') {
          return res.status(403).json({
            success: false,
            message: `Your store account has been ${store.status} by YSHOP administration. Please contact support.`,
            accountBlocked: true,
          });
        }

        // Status is 'pending'
        return res.status(403).json({
          success: false,
          message: 'Your store is pending admin approval. Please wait for YSHOP administration to review your application.',
          requiresApproval: true,
        });
      }

      // Verify password
      const passwordMatch = await bcrypt.compare(password, store.password_hash);
      if (!passwordMatch) {
        connection.release();
        return res.status(401).json({ success: false, message: 'Invalid email or password' });
      }

      connection.release();

      // Generate JWT token with 'storeOwner' role (use uid for Foreign Key compatibility)
      const token = generateJWT(store.uid, store.email, 'storeOwner');

      return res.json({
        success: true,
        token,
        user: {
          id: store.id,
          uid: store.uid,
          email: store.email,
          name: store.name,
          userType: 'storeOwner',
        },
      });
    } catch (error) {
      logger.error('Error in storeLogin:', error);
      next(error);
    }
  }
}

export default AuthController;
