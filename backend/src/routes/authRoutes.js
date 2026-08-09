import { Router } from 'express';
import AuthController from '../controllers/AuthController.js';
import { verifyJWTToken } from '../middleware/auth.js';

const router = Router();

// Public routes
router.post('/signup', AuthController.signup);
router.post('/delivery-signup', AuthController.deliverySignup);
router.post('/store-signup', AuthController.storeSignup);
router.post('/login', AuthController.login);
router.post('/google', AuthController.googleAuth);
router.post('/google/complete-signup', AuthController.completeGoogleSignup);
router.post('/store-login', AuthController.storeLogin);
router.post('/delivery-login', AuthController.deliveryLogin);
router.post('/verify-email', AuthController.verifyEmail);
router.get('/verify-email', AuthController.verifyEmailFromLink);

// Protected routes
router.get('/me', verifyJWTToken, AuthController.getProfile);
router.put('/me/password', verifyJWTToken, AuthController.changeMyPassword);

// Logout endpoint for cleanup on backend if needed
router.post('/logout', verifyJWTToken, (req, res) => {
  // Token-based auth means logout happens client-side
  // Backend just confirms the logout
  res.json({
    success: true,
    message: 'Logout successful',
  });
});

export default router;
