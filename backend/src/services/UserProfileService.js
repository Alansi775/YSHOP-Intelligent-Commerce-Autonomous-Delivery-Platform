// UserProfileService.js — Personalization Engine
//
// Builds a real-time "taste vector" per user from their interaction history.
// The taste vector is a 768-dim Gemini embedding — it points in the direction
// of products the user has shown interest in.
//
// How it works:
//   1. User adds something to cart → product embedding is blended into their taste vector
//   2. Next time they search → their query vector is nudged toward their taste
//   3. As more users join, we find "similar users" and apply collaborative boost
//
// Update strategy: Exponential Moving Average (EMA)
//   new_vector = normalize( (1-α) * current + α * product_embedding )
//   α depends on event strength (purchase=0.12, add_to_cart=0.06, view=0.02)
//   This means: recent strong signals shift the vector more than old weak ones.

import pool from '../config/database.js';
import logger from '../config/logger.js';
import { EmbeddingPipeline } from './EmbeddingPipeline.js';

export class UserProfileService {
  // In-memory cache: userId → { profile: {...}, ts: number }
  static profileCache = new Map();
  static PROFILE_CACHE_TTL_MS = 5 * 60 * 1000; // 5 min

  // Similar-users cache: userId → { users: [...], ts: number }
  static similarUsersCache = new Map();
  static SIMILAR_USERS_TTL_MS = 5 * 60 * 1000;

  // How much each event shifts the user's taste vector
  static EVENT_ALPHA = {
    purchase:    0.12,  // 12% shift toward this product — strong signal
    add_to_cart: 0.06,  // 6%  — clear intent
    view:        0.02,  // 2%  — weak signal
    ai_shown:    0.003, // 0.3% — almost nothing (product was just surfaced)
  };

  // ─── Get full user profile ────────────────────────────────────────────────────

  static async getProfile(userId) {
    if (!userId) return null;

    const cached = this.profileCache.get(String(userId));
    if (cached && (Date.now() - cached.ts) < this.PROFILE_CACHE_TTL_MS) {
      return cached.profile;
    }

    const connection = await pool.getConnection();
    try {
      const [rows] = await connection.execute(
        `SELECT taste_vector, store_affinities, keyword_affinities,
                avg_price, total_interactions, updated_at
         FROM user_profiles WHERE user_id = ?`,
        [String(userId)],
      );

      if (!rows.length) {
        this.profileCache.set(String(userId), { profile: null, ts: Date.now() });
        return null;
      }

      const row = rows[0];
      const profile = {
        taste_vector:       EmbeddingPipeline.stringToVector(row.taste_vector),
        store_affinities:   this._parseJSON(row.store_affinities, {}),
        keyword_affinities: this._parseJSON(row.keyword_affinities, {}),
        avg_price:          parseFloat(row.avg_price) || 0,
        total_interactions: Number(row.total_interactions) || 0,
        updated_at:         row.updated_at,
      };

      this.profileCache.set(String(userId), { profile, ts: Date.now() });
      return profile;
    } finally {
      connection.release();
    }
  }

  // Convenience: get just the taste vector (used by VectorStore)
  static async getTasteVector(userId) {
    const profile = await this.getProfile(userId);
    return profile?.taste_vector || null;
  }

  // ─── Update profile after an interaction (EMA) ────────────────────────────────

  static async updateProfile(userId, productId, eventType, { storeType = null, query = null } = {}) {
    if (!EmbeddingPipeline.isAvailable() || !userId || !productId) return;

    const alpha = this.EVENT_ALPHA[eventType];
    if (!alpha) return;

    try {
      // Fetch product embedding from DB
      const conn = await pool.getConnection();
      let productEmbedding = null;
      let productPrice     = null;
      try {
        const [embRows] = await conn.execute(
          'SELECT embedding FROM product_embeddings WHERE product_id = ?',
          [Number(productId)],
        );
        if (embRows[0]) {
          productEmbedding = EmbeddingPipeline.stringToVector(embRows[0].embedding);
        }

        const [priceRows] = await conn.execute(
          'SELECT price FROM products WHERE id = ?',
          [Number(productId)],
        );
        if (priceRows[0]) productPrice = parseFloat(priceRows[0].price);
      } finally {
        conn.release();
      }

      // No embedding yet for this product — backfill will handle it later
      if (!productEmbedding?.length) return;

      const current = await this.getProfile(userId) || {};

      // ── 1. Update taste vector (EMA) ─────────────────────────────────────
      const newTasteVector = current.taste_vector?.length
        ? this.blendVectors(current.taste_vector, productEmbedding, 1 - alpha, alpha)
        : productEmbedding;

      // ── 2. Update store affinities ────────────────────────────────────────
      const storeAffinities = { ...(current.store_affinities || {}) };
      if (storeType) {
        storeAffinities[storeType] = Math.min(1, (storeAffinities[storeType] || 0) + (alpha * 1.5));
        const total = Object.values(storeAffinities).reduce((s, v) => s + v, 0);
        if (total > 0) {
          for (const k of Object.keys(storeAffinities)) {
            storeAffinities[k] = storeAffinities[k] / total;
          }
        }
      }

      // ── 3. Update keyword affinities (from query) ─────────────────────────
      const keywordAffinities = { ...(current.keyword_affinities || {}) };
      if (query && alpha >= 0.02) { // Only update on meaningful events (view+)
        const tokens = query
          .toLowerCase()
          .replace(/[^\p{L}\p{N}\s]/gu, ' ')
          .split(/\s+/)
          .filter(t => t.length > 2)
          .slice(0, 8);

        for (const token of tokens) {
          keywordAffinities[token] = Math.min(1, (keywordAffinities[token] || 0) + alpha);
        }

        // Keep top 50 keywords only
        const sorted = Object.entries(keywordAffinities)
          .sort((a, b) => b[1] - a[1])
          .slice(0, 50);
        for (const k of Object.keys(keywordAffinities)) {
          if (!sorted.find(([sk]) => sk === k)) delete keywordAffinities[k];
        }
      }

      // ── 4. Update price average ───────────────────────────────────────────
      let avgPrice = current.avg_price || 0;
      if (productPrice > 0 && alpha >= 0.06) { // Only from meaningful events (cart+)
        const n = Math.min(current.total_interactions || 0, 100);
        avgPrice = (avgPrice * n + productPrice) / (n + 1);
      }

      const totalInteractions = (current.total_interactions || 0) + 1;

      // ── 5. Persist ────────────────────────────────────────────────────────
      const conn2 = await pool.getConnection();
      try {
        await conn2.execute(
          `INSERT INTO user_profiles
             (user_id, taste_vector, store_affinities, keyword_affinities,
              avg_price, total_interactions, updated_at)
           VALUES (?, ?, ?, ?, ?, ?, NOW())
           ON DUPLICATE KEY UPDATE
             taste_vector       = VALUES(taste_vector),
             store_affinities   = VALUES(store_affinities),
             keyword_affinities = VALUES(keyword_affinities),
             avg_price          = VALUES(avg_price),
             total_interactions = VALUES(total_interactions),
             updated_at         = NOW()`,
          [
            String(userId),
            EmbeddingPipeline.vectorToString(newTasteVector),
            JSON.stringify(storeAffinities),
            JSON.stringify(keywordAffinities),
            avgPrice,
            totalInteractions,
          ],
        );
      } finally {
        conn2.release();
      }

      // Invalidate caches
      this.profileCache.delete(String(userId));
      this.similarUsersCache.delete(String(userId));

      logger.info(
        `[UserProfile] updated | userId=${userId} | event=${eventType} | ` +
        `interactions=${totalInteractions} | storeAff=${JSON.stringify(storeAffinities)}`,
      );
    } catch (err) {
      logger.warn(`[UserProfile] update failed userId=${userId}: ${err.message}`);
    }
  }

  // ─── Collaborative Filtering: find similar users ───────────────────────────────
  // Compares taste vectors of recently active users.
  // Scalability note: currently loads up to 200 profiles for comparison.
  // For 100K+ MAU, replace with a vector DB (Qdrant/pgvector) ANN lookup.

  static async findSimilarUsers(userId, { limit = 5, minInteractions = 3 } = {}) {
    if (!userId) return [];

    const cached = this.similarUsersCache.get(String(userId));
    if (cached && (Date.now() - cached.ts) < this.SIMILAR_USERS_TTL_MS) {
      return cached.users;
    }

    const myProfile = await this.getProfile(userId);
    if (!myProfile?.taste_vector?.length || myProfile.total_interactions < minInteractions) {
      return [];
    }

    const connection = await pool.getConnection();
    try {
      const [rows] = await connection.execute(
        `SELECT user_id, taste_vector, total_interactions
         FROM user_profiles
         WHERE user_id != ?
           AND total_interactions >= ?
           AND updated_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
         LIMIT 300`,
        [String(userId), minInteractions],
      );

      if (!rows.length) return [];

      const similarities = rows
        .map(row => {
          const vec = EmbeddingPipeline.stringToVector(row.taste_vector);
          if (!vec?.length) return null;
          const sim = EmbeddingPipeline.cosineSimilarity(myProfile.taste_vector, vec);
          return { userId: row.user_id, similarity: sim };
        })
        .filter(Boolean)
        .sort((a, b) => b.similarity - a.similarity)
        .slice(0, limit);

      this.similarUsersCache.set(String(userId), { users: similarities, ts: Date.now() });
      return similarities;
    } finally {
      connection.release();
    }
  }

  // ─── Get products popular with similar users ───────────────────────────────────
  // Returns Map<productId, collaborativeScore>

  static async getCollaborativeProducts(userId, { storeType = null } = {}) {
    if (!userId) return new Map();

    const similar = await this.findSimilarUsers(userId, { limit: 5, minInteractions: 3 });
    if (!similar.length) return new Map();

    const userIds    = similar.map(u => u.userId);
    const weightMap  = Object.fromEntries(similar.map(u => [u.userId, u.similarity]));
    const eventWeights = { purchase: 10, add_to_cart: 5 };

    const connection = await pool.getConnection();
    try {
      const placeholders = userIds.map(() => '?').join(',');
      const params = storeType
        ? [...userIds, storeType, 30, 500]
        : [...userIds, 30, 500];
      const storeFilter = storeType ? 'AND store_type = ?' : '';

      const [rows] = await connection.execute(
        `SELECT product_id, user_id, event_type
         FROM user_interactions
         WHERE user_id IN (${placeholders})
           ${storeFilter}
           AND created_at >= DATE_SUB(NOW(), INTERVAL ? DAY)
           AND event_type IN ('purchase', 'add_to_cart')
         LIMIT ?`,
        params,
      );

      const scores = new Map();
      for (const row of rows) {
        const userSim  = weightMap[row.user_id] || 0;
        const eventW   = eventWeights[row.event_type] || 1;
        const boost    = userSim * eventW;
        const pid      = Number(row.product_id);
        scores.set(pid, (scores.get(pid) || 0) + boost);
      }

      return scores;
    } finally {
      connection.release();
    }
  }

  // ─── Blend two unit vectors → normalize result ─────────────────────────────────

  static blendVectors(a, b, weightA, weightB) {
    if (!a?.length || !b?.length || a.length !== b.length) return a || b || [];
    const result = new Array(a.length);
    let norm = 0;
    for (let i = 0; i < a.length; i++) {
      result[i] = weightA * a[i] + weightB * b[i];
      norm += result[i] * result[i];
    }
    const mag = Math.sqrt(norm);
    if (mag > 0) {
      for (let i = 0; i < result.length; i++) result[i] /= mag;
    }
    return result;
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────────

  static _parseJSON(raw, fallback) {
    if (!raw) return fallback;
    try { return JSON.parse(raw); } catch { return fallback; }
  }

  static clearCache(userId = null) {
    if (userId) {
      this.profileCache.delete(String(userId));
      this.similarUsersCache.delete(String(userId));
    } else {
      this.profileCache.clear();
      this.similarUsersCache.clear();
    }
  }
}
