import { YShopAIService } from '../services/YShopAIService.js';
import { UserInteractionService } from '../services/UserInteractionService.js';
import { EmbeddingPipeline } from '../services/EmbeddingPipeline.js';
import { isTTSAvailable, synthesizeSpeech } from '../services/TTSProxyService.js';
import logger from '../config/logger.js';

export class AIController {

  // ─────────────────────────────────────────────
  // POST /api/v1/ai/chat
  // ─────────────────────────────────────────────
  static async chat(req, res) {
    try {
      const { message, userId, language = 'auto' } = req.body;
      const traceId = `${userId || 'guest'}-${Date.now()}`;

      if (!message || typeof message !== 'string' || message.trim().length === 0) {
        return res.status(400).json({ success: false, error: 'Message is required' });
      }
      if (!userId) {
        return res.status(400).json({ success: false, error: 'userId is required' });
      }
      if (message.trim().length > 500) {
        return res.status(400).json({ success: false, error: 'Message too long (max 500 characters)' });
      }

      const trimmedMessage = message.trim();
      logger.info(`[AIController] Chat | trace=${traceId} | userId=${userId} | lang=${language} | message="${trimmedMessage.substring(0, 80)}"`);

      const { reply, products, voiceProfile, conversationStage, voiceMood, voiceIntensity, voiceCue } =
        await YShopAIService.generateResponse(trimmedMessage, userId, { traceId });

      // Auto-record ai_shown for every product surfaced — fire-and-forget, never blocks response
      if (products?.length) {
        UserInteractionService.recordAIShown(userId, products, trimmedMessage);
      }

      logger.info(
        `[AIController] Done | trace=${traceId} | userId=${userId} | ` +
        `products=${products?.length || 0} | replyLen=${reply?.length || 0} | ` +
        `voiceMood=${voiceMood || 'neutral'} | voiceIntensity=${Number.isFinite(Number(voiceIntensity)) ? Number(voiceIntensity).toFixed(2) : '0.65'} | ` +
        `voiceCue=${voiceCue || 'none'}`,
      );

      return res.status(200).json({
        success: true,
        data: {
          message: reply || "I'm here to help! What are you looking for?",
          voiceProfile: voiceProfile || null,
          conversationStage: conversationStage || 'browsing',
          voiceMood: voiceMood || 'neutral',
          voiceIntensity: Number.isFinite(Number(voiceIntensity)) ? Number(voiceIntensity) : 0.65,
          voiceCue: typeof voiceCue === 'string' ? voiceCue : '',
          products: (products || []).map(p => ({
            id:                p.id,
            name:              p.name,
            description:       p.description || '',
            price:             p.price,
            currency:          p.currency || 'TRY',
            image_url:         p.image_url,
            image:             p.image_url,
            store_name:        p.store_name,
            storeName:         p.store_name,
            store_owner_email: p.store_owner_email,
            storeOwnerEmail:   p.store_owner_email,
            store_type:        p.store_type,
            stock:             p.stock,
            available:         (p.stock ?? 0) > 0,
            reason:            p.reason || 'Recommended for you',
          })),
          hasProducts: (products?.length ?? 0) > 0,
        },
        meta: { timestamp: new Date().toISOString(), language, traceId },
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
  // POST /api/v1/ai/interact
  // Called by the client when a user acts on a product surfaced by AI.
  // Body: { userId, productId, eventType, query?, storeType? }
  // eventType: 'view' | 'add_to_cart' | 'purchase'
  // ─────────────────────────────────────────────
  static async interact(req, res) {
    try {
      const { userId, productId, eventType, query, storeType } = req.body;

      if (!userId || !productId || !eventType) {
        return res.status(400).json({ success: false, error: 'userId, productId and eventType are required' });
      }

      const allowed = ['view', 'add_to_cart', 'purchase'];
      if (!allowed.includes(eventType)) {
        return res.status(400).json({ success: false, error: `eventType must be one of: ${allowed.join(', ')}` });
      }

      await UserInteractionService.record(userId, productId, eventType, { query, storeType });
      logger.info(`[AIController] interact | userId=${userId} | product=${productId} | event=${eventType}`);
      return res.status(200).json({ success: true });

    } catch (error) {
      logger.error('[AIController] interact error:', error.message);
      return res.status(500).json({ success: false, error: 'Failed to record interaction' });
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
          operational: YShopAIService.isOperational(),
          service: 'YSHOP AI',
          provider: YShopAIService.provider || (YShopAIService.model ? 'gemini' : 'groq'),
          embeddings: EmbeddingPipeline.isAvailable() ? 'gemini/text-embedding-004' : 'disabled',
          features: [
            'Conversational shopping',
            'Semantic retrieval — Gemini text-embedding-004 (768-dim)',
            'Hybrid BM25 + vector search (55/45)',
            'Popularity-boosted ranking',
            'User interaction tracking',
            'Full conversation memory',
            'Multi-language (Arabic & English)',
          ],
        },
      });
    } catch (error) {
      logger.error('[AIController] getStatus error:', error.message);
      return res.status(500).json({ success: false, operational: false });
    }
  }

  // ─────────────────────────────────────────────
  // POST /api/v1/ai/speak
  // Server-side voice synthesis proxy — the provider key never reaches the
  // client (public web builds and decompiled apps can't extract it).
  // ─────────────────────────────────────────────
  static async speak(req, res) {
    try {
      const { voiceId, text, modelId, voiceSettings } = req.body || {};

      if (!isTTSAvailable()) {
        return res.status(503).json({ success: false, error: 'TTS not configured' });
      }
      if (!voiceId || !text || typeof text !== 'string' || !text.trim()) {
        return res.status(400).json({ success: false, error: 'voiceId and text are required' });
      }
      if (text.length > 1000) {
        return res.status(400).json({ success: false, error: 'text too long' });
      }

      const audio = await synthesizeSpeech({ voiceId, text, modelId, voiceSettings });
      res.set('Content-Type', 'audio/mpeg');
      return res.status(200).send(audio);
    } catch (error) {
      logger.error('[AIController] speak error:', error.message);
      const status = error.status && error.status < 500 ? error.status : 502;
      return res.status(status).json({ success: false, error: 'Speech synthesis failed' });
    }
  }

  // ─────────────────────────────────────────────
  // DELETE /api/v1/ai/conversation/:userId
  // ─────────────────────────────────────────────
  static async clearConversation(req, res) {
    try {
      const { userId } = req.params;
      if (!userId) return res.status(400).json({ success: false, error: 'userId required' });
      YShopAIService.clearMemory(userId);
      logger.info(`[AIController] Cleared conversation for userId=${userId}`);
      return res.status(200).json({ success: true, message: 'Conversation cleared' });
    } catch (error) {
      logger.error('[AIController] clearConversation error:', error.message);
      return res.status(500).json({ success: false, error: 'Failed to clear conversation' });
    }
  }

  // ─────────────────────────────────────────────
  // POST /api/v1/ai/chat/history
  // ─────────────────────────────────────────────
  static async getHistory(req, res) {
    try {
      const { userId } = req.body;
      if (!userId) return res.status(400).json({ success: false, error: 'userId required' });
      const memory = YShopAIService.getMemory(userId);
      return res.status(200).json({
        success: true,
        data: {
          messages: memory.map(m => ({ role: m.role, text: m.text, timestamp: m.timestamp })),
          count: memory.length,
        },
      });
    } catch (error) {
      logger.error('[AIController] getHistory error:', error.message);
      return res.status(500).json({ success: false, error: 'Failed to fetch history' });
    }
  }

  // ─────────────────────────────────────────────
  // POST /api/v1/ai/chat/clear
  // ─────────────────────────────────────────────
  static async clearHistory(req, res) {
    try {
      const { userId } = req.body;
      if (!userId) return res.status(400).json({ success: false, error: 'userId required' });
      YShopAIService.clearMemory(userId);
      return res.status(200).json({ success: true, message: 'History cleared' });
    } catch (error) {
      logger.error('[AIController] clearHistory error:', error.message);
      return res.status(500).json({ success: false, error: 'Failed to clear history' });
    }
  }
}

export default AIController;
