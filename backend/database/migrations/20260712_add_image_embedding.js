// Migration: add image_embedding column to product_embeddings
// Adds two columns:
//   image_embedding  MEDIUMTEXT NULL — 768-dim float[] from Gemini Vision caption
//   image_model      VARCHAR(100) NULL — model used (e.g. "gemini-1.5-flash")
//
// Safe to run multiple times — checks information_schema before ALTER.

import pool from '../../src/config/database.js';
import logger from '../../src/config/logger.js';

export async function runImageEmbeddingMigration() {
  const connection = await pool.getConnection();
  try {
    // Check if column already exists
    const [[existing]] = await connection.execute(`
      SELECT COLUMN_NAME
      FROM information_schema.COLUMNS
      WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_NAME   = 'product_embeddings'
        AND COLUMN_NAME  = 'image_embedding'
    `);

    if (existing) {
      logger.info('✓ [Migration] product_embeddings.image_embedding already exists — skipping');
      return;
    }

    await connection.execute(`
      ALTER TABLE product_embeddings
        ADD COLUMN image_embedding  MEDIUMTEXT    NULL AFTER embedding,
        ADD COLUMN image_model      VARCHAR(100)  NULL AFTER image_embedding
    `);

    logger.info('✓ [Migration] product_embeddings: image_embedding + image_model columns added');
  } catch (err) {
    logger.error('[Image Embedding Migration] failed:', err.message);
    throw err;
  } finally {
    connection.release();
  }
}
