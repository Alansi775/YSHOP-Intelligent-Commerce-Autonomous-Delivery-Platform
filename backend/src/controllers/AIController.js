import { YShopAIService } from '../services/YShopAIService.js';
import logger from '../config/logger.js';

/**
 * YSHOP AI Controller
 * Handles all AI chat requests
 */
export class AIController {

  // ─────────────────────────────────────────────
  // POST /api/v1/ai/chat
  // ─────────────────────────────────────────────
  static async chat(req, res) {
    try {
      const { message, userId, language = 'auto' } = req.body;

      // ── Validation ──────────────────────────────────────────────
      if (!message || typeof message !== 'string' || message.trim().length === 0) {
        return res.status(400).json({
          success: false,
          error: 'Message is required',
        });
      }

      if (!userId) {
        return res.status(400).json({
          success: false,
          error: 'userId is required',
        });
      }

      if (message.trim().length > 500) {
        return res.status(400).json({
          success: false,
          error: 'Message too long (max 500 characters)',
        });
      }

      const trimmedMessage = message.trim();

      logger.info(`[AIController] Chat | userId=${userId} | message="${trimmedMessage.substring(0, 60)}"`);

      // ── Single call does everything ──────────────────────────────
      // generateResponse:
      //   ✅ Loads full conversation history
      //   ✅ Loads ALL real products from DB
      //   ✅ AI sees real data and selects best products
      //   ✅ AI understands context ("give me another" = different product)
      //   ✅ Protects identity (never mentions Google/Gemini)
      //   ✅ Saves to conversation memory automatically
      const { reply, products } = await YShopAIService.generateResponse(
        trimmedMessage,
        userId,
      );

      logger.info(
        `[AIController] Done | userId=${userId} | ` +
        `products=${products?.length || 0} | replyLen=${reply?.length || 0}`,
      );

      // ── Return response ──────────────────────────────────────────
      return res.status(200).json({
        success: true,
        data: {
          message: reply || "I'm here to help! What are you looking for?",
          products: (products || []).map(p => ({
            id:          p.id,
            name:        p.name,
            description: p.description || '',
            price:       p.price,
            currency:    p.currency || 'TRY',
            image_url:   p.image_url,
            image:       p.image_url,          // alias for Flutter compatibility
            store_name:  p.store_name,
            storeName:   p.store_name,         // alias for Flutter compatibility
            store_owner_email: p.store_owner_email,
            storeOwnerEmail:   p.store_owner_email,  // alias for Flutter compatibility
            store_type:  p.store_type,
            stock:       p.stock,
            available:   (p.stock ?? 0) > 0,
            reason:      p.reason || 'Recommended for you',
          })),
          hasProducts: (products?.length ?? 0) > 0,
        },
        meta: {
          timestamp: new Date().toISOString(),
          language,
        },
      });

    } catch (error) {
      logger.error('[AIController] chat error:', error.message);
      return res.status(500).json({
        success: false,
        error: 'AI service temporarily unavailable. Please try again.',
        debug: process.env.NODE_ENV === 'development' ? error.message : undefined,
      });
    }
  }

  // ─────────────────────────────────────────────
  // GET /api/v1/ai/status
  // ─────────────────────────────────────────────
  static async getStatus(req, res) {
    try {
      return res.status(200).json({
        success: true,
        data: {
          operational: YShopAIService.model !== null,
          service: 'YSHOP AI',
          features: [
            'Conversational shopping',
            'Intelligent product selection',
            'Full conversation memory',
            'Multi-language (Arabic & English)',
            'Real-time inventory awareness',
          ],
        },
      });
    } catch (error) {
      logger.error('[AIController] getStatus error:', error.message);
      return res.status(500).json({ success: false, operational: false });
    }
  }

  // ─────────────────────────────────────────────
  // DELETE /api/v1/ai/conversation/:userId
  // ─────────────────────────────────────────────
  static async clearConversation(req, res) {
    try {
      const { userId } = req.params;
      if (!userId) {
        return res.status(400).json({ success: false, error: 'userId required' });
      }
      YShopAIService.clearMemory(userId);
      logger.info(`[AIController] Cleared conversation for userId=${userId}`);
      return res.status(200).json({ success: true, message: 'Conversation cleared' });
    } catch (error) {
      logger.error('[AIController] clearConversation error:', error.message);
      return res.status(500).json({ success: false, error: 'Failed to clear conversation' });
    }
  }

  // ─────────────────────────────────────────────
  // POST /api/v1/ai/chat/history  (kept for backward compat)
  // ─────────────────────────────────────────────
  static async getHistory(req, res) {
    try {
      const { userId } = req.body;
      if (!userId) {
        return res.status(400).json({ success: false, error: 'userId required' });
      }
      const memory = YShopAIService.getMemory(userId);
      return res.status(200).json({
        success: true,
        data: {
          messages: memory.map(m => ({
            role:      m.role,
            text:      m.text,
            timestamp: m.timestamp,
          })),
          count: memory.length,
        },
      });
    } catch (error) {
      logger.error('[AIController] getHistory error:', error.message);
      return res.status(500).json({ success: false, error: 'Failed to fetch history' });
    }
  }

  // ─────────────────────────────────────────────
  // POST /api/v1/ai/chat/clear  (kept for backward compat)
  // ─────────────────────────────────────────────
  static async clearHistory(req, res) {
    try {
      const { userId } = req.body;
      if (!userId) {
        return res.status(400).json({ success: false, error: 'userId required' });
      }
      YShopAIService.clearMemory(userId);
      return res.status(200).json({ success: true, message: 'History cleared' });
    } catch (error) {
      logger.error('[AIController] clearHistory error:', error.message);
      return res.status(500).json({ success: false, error: 'Failed to clear history' });
    }
  }
}

export default AIController;