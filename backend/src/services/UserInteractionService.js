// UserInteractionService.js — Records user behavior for the recommendation engine
import pool from '../config/database.js';
import logger from '../config/logger.js';
import { UserProfileService } from './UserProfileService.js';

export class UserInteractionService {
  static VALID_EVENTS = new Set(['ai_shown', 'view', 'add_to_cart', 'purchase']);

  // Event weights for popularity scoring
  static EVENT_WEIGHTS = {
    purchase:    10,
    add_to_cart: 5,
    view:        2,
    ai_shown:    1,
  };

  // ─── Record a single interaction ─────────────────────────────────────────────

  static async record(userId, productId, eventType, { query = null, storeType = null } = {}) {
    if (!userId || !productId || !this.VALID_EVENTS.has(eventType)) return;

    const connection = await pool.getConnection();
    try {
      await connection.execute(
        `INSERT INTO user_interactions
           (user_id, product_id, store_type, event_type, query, created_at)
         VALUES (?, ?, ?, ?, ?, NOW())`,
        [
          String(userId),
          Number(productId),
          storeType || null,
          eventType,
          query ? String(query).slice(0, 500) : null,
        ],
      );
    } catch (err) {
      // Non-fatal: interaction tracking should never break the main flow
      logger.warn(`[InteractionService] record failed (${eventType} product=${productId}): ${err.message}`);
    } finally {
      connection.release();
    }

    // Update user taste profile in background — never blocks the response
    // Only meaningful events shift the taste vector (not ai_shown)
    if (['view', 'add_to_cart', 'purchase'].includes(eventType)) {
      setImmediate(() => {
        UserProfileService
          .updateProfile(userId, productId, eventType, { storeType, query })
          .catch(err => logger.debug(`[InteractionService] profile update error: ${err.message}`));
      });
    }
  }

  // ─── Record multiple ai_shown events (fire-and-forget) ───────────────────────

  static recordAIShown(userId, products, query) {
    if (!userId || !products?.length) return;
    setImmediate(async () => {
      for (const product of products) {
        await this.record(userId, product.id, 'ai_shown', {
          query,
          storeType: product.store_type,
        });
      }
    });
  }

  // ─── Get weighted popularity scores for a set of product IDs ─────────────────
  // Returns Map<productId (number), score (number)>

  static async getPopularityScores(productIds, { windowDays = 30 } = {}) {
    if (!productIds?.length) return new Map();

    const ids = productIds.map(id => Number(id));
    const connection = await pool.getConnection();
    try {
      const placeholders = ids.map(() => '?').join(',');
      const [rows] = await connection.execute(
        `SELECT
           product_id,
           SUM(CASE
             WHEN event_type = 'purchase'    THEN ${this.EVENT_WEIGHTS.purchase}
             WHEN event_type = 'add_to_cart' THEN ${this.EVENT_WEIGHTS.add_to_cart}
             WHEN event_type = 'view'        THEN ${this.EVENT_WEIGHTS.view}
             WHEN event_type = 'ai_shown'    THEN ${this.EVENT_WEIGHTS.ai_shown}
             ELSE 0
           END) AS score
         FROM user_interactions
         WHERE product_id IN (${placeholders})
           AND created_at >= DATE_SUB(NOW(), INTERVAL ? DAY)
         GROUP BY product_id`,
        [...ids, windowDays],
      );

      const map = new Map();
      for (const row of rows) {
        map.set(Number(row.product_id), Number(row.score) || 0);
      }
      return map;
    } finally {
      connection.release();
    }
  }

  // ─── Get trending product IDs for a store type (last 7 days) ─────────────────

  static async getTrendingProductIds(storeType, { limit = 20, windowDays = 7 } = {}) {
    const connection = await pool.getConnection();
    try {
      const params = storeType ? [windowDays, storeType, limit] : [windowDays, limit];
      const storeFilter = storeType ? 'AND store_type = ?' : '';
      const [rows] = await connection.execute(
        `SELECT product_id,
           SUM(CASE
             WHEN event_type = 'purchase'    THEN ${this.EVENT_WEIGHTS.purchase}
             WHEN event_type = 'add_to_cart' THEN ${this.EVENT_WEIGHTS.add_to_cart}
             WHEN event_type = 'view'        THEN ${this.EVENT_WEIGHTS.view}
             ELSE 1
           END) AS score
         FROM user_interactions
         WHERE created_at >= DATE_SUB(NOW(), INTERVAL ? DAY)
           ${storeFilter}
         GROUP BY product_id
         ORDER BY score DESC
         LIMIT ?`,
        params,
      );
      return rows.map(r => Number(r.product_id));
    } finally {
      connection.release();
    }
  }
}
