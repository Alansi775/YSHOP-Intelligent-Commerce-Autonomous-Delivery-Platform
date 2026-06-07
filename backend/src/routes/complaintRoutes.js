import { Router } from 'express';
import ComplaintController from '../controllers/ComplaintController.js';
import { verifyFirebaseToken, verifyAdminToken } from '../middleware/auth.js';

const router = Router();

// Customer routes
router.post('/',  verifyFirebaseToken, ComplaintController.create);
router.get('/my', verifyFirebaseToken, ComplaintController.getMine);

// Driver route — JWT token, extracts uid from req.user
router.get('/driver', verifyFirebaseToken, ComplaintController.getForDriver);

// Store owner route — any valid JWT (store owners have role 'storeOwner', not admin)
router.get('/store', verifyFirebaseToken, ComplaintController.getForStore);
router.get('/',             verifyAdminToken, ComplaintController.getAll);
router.patch('/:id/status', verifyAdminToken, ComplaintController.updateStatus);

// Single complaint detail — admin only (full details with JOINs)
router.get('/:id', verifyAdminToken, ComplaintController.getById);

export default router;
