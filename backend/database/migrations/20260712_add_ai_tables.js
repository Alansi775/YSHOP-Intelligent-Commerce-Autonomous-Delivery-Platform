// Migration: AI infrastructure tables
// Creates:
//   product_embeddings — Gemini text-embedding-004 vectors (768-dim) per product
//   user_interactions  — user behavior events for the recommendation engine

import pool from '../../src/config/database.js';
import logger from '../../src/config/logger.js';

export async function runAITablesMigration() {
  const connection = await pool.getConnection();
  try {
    // ── product_embeddings ──────────────────────────────────────────────────────
    // One row per product. Embedding is a JSON-serialized float[768].
    // MEDIUMTEXT holds up to 16MB — more than enough for a 768-dim float array (~9KB).
    await connection.execute(`
      CREATE TABLE IF NOT EXISTS product_embeddings (
        product_id  INT            NOT NULL,
        embedding   MEDIUMTEXT     NOT NULL,
        model       VARCHAR(100)   NOT NULL DEFAULT 'text-embedding-004',
        updated_at  TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP
                                   ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (product_id),
        FOREIGN KEY (product_id)
          REFERENCES products(id)
          ON DELETE CASCADE
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    `);
    logger.info('✓ [Migration] product_embeddings table ready');

    // ── user_interactions ───────────────────────────────────────────────────────
    // Records every meaningful user action so the recommendation engine
    // can learn what products people actually want.
    //
    // event_type weights (used in popularity scoring):
    //   purchase    → 10 pts
    //   add_to_cart → 5  pts
    //   view        → 2  pts
    //   ai_shown    → 1  pt   (baseline — product was at least surfaced)
    await connection.execute(`
      CREATE TABLE IF NOT EXISTS user_interactions (
        id          INT            AUTO_INCREMENT PRIMARY KEY,
        user_id     VARCHAR(255)   NOT NULL,
        product_id  INT            NOT NULL,
        store_type  VARCHAR(50)    NULL,
        event_type  ENUM(
                      'ai_shown',
                      'view',
                      'add_to_cart',
                      'purchase'
                    )              NOT NULL,
        query       VARCHAR(500)   NULL,
        created_at  TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP,

        INDEX idx_ui_user        (user_id),
        INDEX idx_ui_product     (product_id),
        INDEX idx_ui_event       (event_type),
        INDEX idx_ui_store       (store_type),
        INDEX idx_ui_created     (created_at),
        INDEX idx_ui_user_event  (user_id, event_type),
        INDEX idx_ui_product_event (product_id, event_type, created_at)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    `);
    logger.info('✓ [Migration] user_interactions table ready');

    // ── user_profiles ───────────────────────────────────────────────────────────
    // One row per user. Built incrementally from interactions via EMA updates.
    //
    // taste_vector: weighted avg Gemini embedding of products user liked → 768-dim
    // store_affinities: {"Food": 0.85, "Clothes": 0.1} — normalized category prefs
    // keyword_affinities: {"دجاج": 0.9, "كوري": 0.8} — keyword prefs from queries
    // avg_price: running average of interacted product prices
    await connection.execute(`
      CREATE TABLE IF NOT EXISTS user_profiles (
        user_id             VARCHAR(255)   NOT NULL,
        taste_vector        MEDIUMTEXT     NULL,
        store_affinities    JSON           NULL,
        keyword_affinities  JSON           NULL,
        avg_price           DECIMAL(10,2)  NULL,
        total_interactions  INT            NOT NULL DEFAULT 0,
        updated_at          TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP
                                           ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (user_id),
        INDEX idx_up_updated (updated_at),
        INDEX idx_up_interactions (total_interactions)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    `);
    logger.info('✓ [Migration] user_profiles table ready');

  } catch (err) {
    logger.error('[AI Tables Migration] failed:', err.message);
    throw err;
  } finally {
    connection.release();
  }
}
