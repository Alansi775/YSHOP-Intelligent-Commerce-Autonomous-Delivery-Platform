import { Router } from 'express';
import { verifyJWTToken } from '../middleware/auth.js';
import { AnalyticsController } from '../controllers/AnalyticsController.js';

const router = Router();

// Store owner analytics — requires auth
router.get('/store/:storeId', verifyJWTToken, AnalyticsController.getStoreAnalytics);

export default router;
