import jwt from 'jsonwebtoken';
import crypto from 'crypto';

// Use ADMIN_JWT_SECRET first for consistency across all token generation
const JWT_SECRET = process.env.ADMIN_JWT_SECRET || process.env.JWT_SECRET || 'change_this_secret';
const JWT_EXPIRES_IN = '7d';

export const generateJWT = (userId, email, role = 'user') => {
  return jwt.sign(
    {
      id: userId,
      email,
      role,
    },
    JWT_SECRET,
    { expiresIn: JWT_EXPIRES_IN }
  );
};

export const verifyJWT = (token) => {
  try {
    return jwt.verify(token, JWT_SECRET);
  } catch (error) {
    return null;
  }
};

// Short-lived, not a real session token — carries a Google identity that's
// been verified (ID token checked) but has no `users` row yet. Only
// AuthController.completeGoogleSignup accepts these, and only to create the
// row atomically with the required profile fields. If the user abandons the
// flow, this token just expires; nothing was ever written to the DB.
export const generatePendingGoogleSignupToken = (email, givenName, familyName) => {
  return jwt.sign(
    { pendingGoogleSignup: true, email, givenName, familyName },
    JWT_SECRET,
    { expiresIn: '15m' }
  );
};

export const verifyPendingGoogleSignupToken = (token) => {
  try {
    const payload = jwt.verify(token, JWT_SECRET);
    return payload.pendingGoogleSignup === true ? payload : null;
  } catch (error) {
    return null;
  }
};

export const generateVerificationToken = () => {
  return crypto.randomBytes(32).toString('hex');
};

export const generateTokenExpiry = (hours = 24) => {
  const now = new Date();
  now.setHours(now.getHours() + hours);
  return now;
};
