import pool from '../../src/config/database.js';
import logger from '../../src/config/logger.js';

async function up() {
  const connection = await pool.getConnection();
  try {
    const [tableRows] = await connection.execute(
      `SELECT COUNT(*) as cnt FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'order_complaints'`
    );
    if (tableRows[0].cnt > 0) {
      logger.info('Table order_complaints already exists — skipping');
      return;
    }

    await connection.execute(`
      CREATE TABLE order_complaints (
        id            INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
        order_id      INT UNSIGNED      NOT NULL,
        customer_id   VARCHAR(255)      NOT NULL,
        driver_id     VARCHAR(255)      NULL,
        store_id      INT UNSIGNED      NULL,
        complaint_type VARCHAR(100)     NOT NULL,
        sub_type      VARCHAR(100)      NULL,
        description   TEXT              NULL,
        photos        JSON              NULL,
        status        ENUM('PENDING','UNDER_REVIEW','APPROVED','REJECTED') NOT NULL DEFAULT 'PENDING',
        admin_notes   TEXT              NULL,
        resolution_type VARCHAR(100)    NULL,
        deadline_at   DATETIME          NULL,
        created_at    DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at    DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        INDEX idx_order_id   (order_id),
        INDEX idx_customer   (customer_id),
        INDEX idx_status     (status)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    `);
    logger.info('✓ Created table order_complaints');
  } catch (e) {
    logger.error('Migration 20260606_add_order_complaints failed:', e);
    throw e;
  } finally {
    connection.release();
  }
}

up().then(() => process.exit(0)).catch(() => process.exit(1));
