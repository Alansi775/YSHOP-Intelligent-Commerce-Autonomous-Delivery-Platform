import { Router } from 'express';
import UserController from '../controllers/UserController.js';
import { verifyFirebaseToken, verifyAdminToken, verifyAdminRole, verifyToken } from '../middleware/auth.js';

const router = Router();

// Get profile (requires auth)
router.get('/', verifyAdminToken, verifyAdminRole, UserController.listAll);
router.get('/profile', verifyAdminToken, UserController.getProfile);

// Get user's store (requires auth)
router.get('/store', verifyToken, UserController.getUserStore);

// Update profile (requires auth - allows both admin and regular users)
router.put('/profile', verifyToken, UserController.updateProfile);

// Admin-scoped: update user status (ban/approve)
router.put('/admin/:userId/status', verifyAdminToken, verifyAdminRole, UserController.updateUserStatusAdmin);

// Admin-scoped: delete user (also expose generic delete)
router.delete('/admin/:userId', verifyAdminToken, verifyAdminRole, UserController.deleteUserAdmin);
router.delete('/:userId', verifyAdminToken, verifyAdminRole, UserController.deleteUserAdmin);

// Create user if not exists (called after Firebase signup)
router.post('/sync', UserController.createIfNotExists);

export default router;
