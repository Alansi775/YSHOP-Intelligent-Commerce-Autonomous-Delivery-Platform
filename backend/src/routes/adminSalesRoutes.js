// adminSalesRoutes.js — the admin "Sales" screen (per-store settlement/billing)
import express from 'express';
import AdminSalesController from '../controllers/AdminSalesController.js';
import { verifyAdminToken, verifyAdminRole } from '../middleware/auth.js';

const router = express.Router();

// Invoices are handed to store owners as a link/printout, same pattern as
// the existing POS invoice route — no auth on the PDF itself.
router.get('/stores/:storeId/current/invoice', AdminSalesController.getInvoice);
router.get('/settlements/:id/invoice', AdminSalesController.getInvoice);

router.use(verifyAdminToken, verifyAdminRole);

router.get('/categories', AdminSalesController.getCategories);
router.get('/stores', AdminSalesController.getStoresInCategory);
router.get('/stores/:storeId/current', AdminSalesController.getCurrentPeriod);
router.post('/stores/:storeId/settle', AdminSalesController.settleStore);
router.post('/stores/:storeId/undo-settle', AdminSalesController.undoSettle);
router.get('/stores/:storeId/settlements', AdminSalesController.getSettlementHistory);
router.get('/settlements/:id', AdminSalesController.getSettlementDetail);

export default router;
