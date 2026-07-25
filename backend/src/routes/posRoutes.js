// posRoutes.js — Local Restaurant POS System routes
// Auth middleware protects all /api/v1/pos routes.
// Public tracking page is registered separately in server.js as /pos/track/:token

import express from 'express';
import POSController from '../controllers/POSController.js';
import { verifyToken } from '../middleware/auth.js';

const router = express.Router();

// Public — no auth needed (browser opens this as a receipt page)
router.get('/orders/:orderId/invoice', POSController.getInvoice);

// All other routes require store-owner auth
router.use(verifyToken);

// ─── Tables ─────────────────────────────────────────────────────────────────
router.get('/tables',            POSController.getTables);
router.post('/tables',           POSController.createTable);
router.put('/tables/:tableId',   POSController.updateTable);
router.delete('/tables/:tableId', POSController.deleteTable);

// ─── Orders (Cashier) ────────────────────────────────────────────────────────
router.post('/orders',                          POSController.createOrder);
router.get('/orders',                           POSController.getOrders);
router.get('/orders/:orderId',                  POSController.getOrder);
router.put('/orders/:orderId/items',            POSController.updateOrderItems);
router.put('/orders/:orderId/kitchen-status',   POSController.updateKitchenStatus);
router.put('/orders/:orderId/payment',          POSController.processPayment);
router.delete('/orders/:orderId',               POSController.cancelOrder);

// ─── Kitchen screen ──────────────────────────────────────────────────────────
router.get('/kitchen', POSController.getKitchenOrders);

// ─── Analytics extension ─────────────────────────────────────────────────────
router.get('/analytics', POSController.getAnalytics);

export default router;
