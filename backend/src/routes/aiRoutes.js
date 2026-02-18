import express from 'express';
import AIController from '../controllers/AIController.js';
import { verifyJWTToken } from '../middleware/auth.js';

const router = express.Router();

/**
 * YSHOP AI Routes
 * All routes require authentication
 */

/**
 * POST /api/v1/ai/chat
 * Send message and get AI response with product recommendations
 * 
 * Request Body:
 * {
 *   "message": "I'm hungry, what do you recommend?",
 *   "userId": 123,
 *   "language": "ar" or "en" (optional, auto-detects)
 * }
 * 
 * Response:
 * {
 *   "success": true,
 *   "data": {
 *     "message": "Here are some great food options...",
 *     "intent": "FOOD_SEARCH",
 *     "products": [
 *       {
 *         "id": 1,
 *         "name": "Delicious Burger",
 *         "price": 2.50,
 *         "image": "...",
 *         "storeName": "Burger House",
 *         "reason": "Perfect match for your request"
 *       },
 *       ...
 *     ]
 *   }
 * }
 */
router.post('/chat', verifyJWTToken, AIController.chat);

/**
 * POST /api/v1/ai/chat/history
 * Get conversation history for the current user
 * 
 * Request Body:
 * {
 *   "userId": 123
 * }
 */
router.post('/chat/history', verifyJWTToken, AIController.getHistory);

/**
 * POST /api/v1/ai/chat/clear
 * Clear conversation history for the current user
 * 
 * Request Body:
 * {
 *   "userId": 123
 * }
 */
router.post('/chat/clear', verifyJWTToken, AIController.clearHistory);

/**
 * GET /api/v1/ai/status
 * Check YSHOP AI service status
 * No authentication required for status endpoint
 */
router.get('/status', AIController.getStatus);

export default router;
