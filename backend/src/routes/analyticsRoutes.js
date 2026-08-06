import { Router } from 'express';
import { verifyJWTToken, verifyAdminToken, verifyAdminRole } from '../middleware/auth.js';
import { AnalyticsController } from '../controllers/AnalyticsController.js';

const router = Router();

// Store owner analytics — requires auth
router.get('/store/:storeId', verifyJWTToken, AnalyticsController.getStoreAnalytics);

// Admin: every store's financial breakdown (online vs in-store, per currency)
router.get('/admin/stores-summary', verifyAdminToken, verifyAdminRole, AnalyticsController.getAdminStoresSummary);

export default router;
