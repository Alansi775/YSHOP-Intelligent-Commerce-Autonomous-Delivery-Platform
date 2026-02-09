import { Router } from 'express';
import OrderController from '../controllers/OrderController.js';
import { verifyFirebaseToken, verifyAdminToken, verifyToken } from '../middleware/auth.js';

const router = Router();

// Admin route - requires admin token
router.get('/admin', verifyAdminToken, OrderController.getAdminOrders);

// All other order routes require firebase authentication
router.use(verifyFirebaseToken);

// Specific routes BEFORE generic routes to prevent /:id from matching /user
router.post('/', OrderController.create);
router.get('/user', OrderController.getUserOrders);
router.get('/store/:storeId', OrderController.getStoreOrders);

// Generic ID-based routes - MUST come after specific routes
router.get('/:id', OrderController.getById);
router.put('/:id/status', OrderController.updateStatus);
router.post('/:id/assign', OrderController.assignToDriver);
router.post('/:id/picked-up', OrderController.pickedUp);
router.post('/:id/mark-delivered', OrderController.markDelivered);

export default router;
