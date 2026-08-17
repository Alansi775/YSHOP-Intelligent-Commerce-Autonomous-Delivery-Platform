// Migration: Product Media (multiple images + one optional video per product)
//
// products.image_url stays as the single "primary" image — every existing
// query/card/list that reads it directly keeps working unchanged. This
// table holds the FULL set (including that same primary image, so a
// gallery never has to special-case "the first one is somewhere else").

import pool from '../../src/config/database.js';
import logger from '../../src/config/logger.js';

export async function runProductMediaMigration() {
  const connection = await pool.getConnection();
  try {
    await connection.execute(`
      CREATE TABLE IF NOT EXISTS product_media (
        id          INT          NOT NULL AUTO_INCREMENT,
        product_id  INT          NOT NULL,
        media_url   VARCHAR(500) NOT NULL,
        media_type  ENUM('image','video') NOT NULL DEFAULT 'image',
        sort_order  INT          NOT NULL DEFAULT 0,
        created_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,

        PRIMARY KEY (id),
        KEY idx_product_id (product_id),
        CONSTRAINT fk_product_media_product FOREIGN KEY (product_id)
          REFERENCES products(id) ON DELETE CASCADE
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    `);
    logger.info('✓ [Product Media Migration] product_media table ready');
  } catch (err) {
    logger.error('[Product Media Migration] failed:', err.message);
    throw err;
  } finally {
    connection.release();
  }
}
