import { Router } from 'express';
import { verifyJWTToken, verifyAdminToken, verifyAdminRole } from '../middleware/auth.js';
import { AnalyticsController } from '../controllers/AnalyticsController.js';

const router = Router();

// Store owner analytics — requires auth
router.get('/store/:storeId', verifyJWTToken, AnalyticsController.getStoreAnalytics);

// Store owner's own itemized settlement view (same shape as the admin
// Sales screen's "current period", scoped to the caller's store).
router.get('/store/:storeId/current-period', verifyJWTToken, AnalyticsController.getStoreCurrentPeriod);
// Public-by-link invoice PDF, same pattern as the POS/admin invoices.
router.get('/store/:storeId/current-period/invoice', AnalyticsController.getStoreInvoice);

// Admin: every store's financial breakdown (online vs in-store, per currency)
router.get('/admin/stores-summary', verifyAdminToken, verifyAdminRole, AnalyticsController.getAdminStoresSummary);

export default router;
