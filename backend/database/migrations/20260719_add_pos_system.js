// Migration: Local POS System
// Creates:
//   pos_tables    — restaurant/café tables per store
//   Extends orders with: order_type, table_id, kitchen_status, local_payment_method, local_paid, cashier_notes

import pool from '../../src/config/database.js';
import logger from '../../src/config/logger.js';

export async function runPOSMigration() {
  const connection = await pool.getConnection();
  try {
    // ── pos_tables ──────────────────────────────────────────────────────────────
    await connection.execute(`
      CREATE TABLE IF NOT EXISTS pos_tables (
        id          INT           NOT NULL AUTO_INCREMENT,
        store_id    INT           NOT NULL,
        name        VARCHAR(100)  NOT NULL,
        capacity    INT           NOT NULL DEFAULT 4,
        status      ENUM('available','occupied','preparing','waiting_payment','disabled')
                    NOT NULL DEFAULT 'available',
        qr_token    VARCHAR(64)   NOT NULL,
        sort_order  INT           NOT NULL DEFAULT 0,
        created_at  DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at  DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        UNIQUE KEY uk_qr_token (qr_token),
        KEY idx_store_id (store_id)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    `);
    logger.info('✓ [POS Migration] pos_tables table ready');

    // ── Extend orders table ─────────────────────────────────────────────────────
    const [columnRows] = await connection.execute(
      `SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS
       WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'orders'`
    );
    const cols = new Set(columnRows.map(r => r.COLUMN_NAME));

    const alterStmts = [];
    if (!cols.has('order_type'))
      alterStmts.push(`ALTER TABLE orders ADD COLUMN order_type ENUM('online','local') NOT NULL DEFAULT 'online'`);
    if (!cols.has('table_id'))
      alterStmts.push(`ALTER TABLE orders ADD COLUMN table_id INT NULL`);
    if (!cols.has('kitchen_status'))
      alterStmts.push(`ALTER TABLE orders ADD COLUMN kitchen_status ENUM('pending','preparing','ready','delivered') NULL`);
    if (!cols.has('local_payment_method'))
      alterStmts.push(`ALTER TABLE orders ADD COLUMN local_payment_method ENUM('cash','card','mixed') NULL`);
    if (!cols.has('local_paid'))
      alterStmts.push(`ALTER TABLE orders ADD COLUMN local_paid TINYINT(1) NOT NULL DEFAULT 0`);
    if (!cols.has('cashier_notes'))
      alterStmts.push(`ALTER TABLE orders ADD COLUMN cashier_notes TEXT NULL`);
    if (!cols.has('kitchen_updated_at'))
      // Timestamp of the last kitchen_status change — lets the kitchen screen tell
      // which order_items were added AFTER the kitchen last touched the ticket
      // (started cooking / marked delivered), so newly-added items can be flagged.
      alterStmts.push(`ALTER TABLE orders ADD COLUMN kitchen_updated_at DATETIME NULL`);

    // ── Extend order_items table ────────────────────────────────────────────────
    const [itemColRows] = await connection.execute(
      `SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS
       WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'order_items'`
    );
    const itemCols = new Set(itemColRows.map(r => r.COLUMN_NAME));
    if (!itemCols.has('notes')) {
      await connection.execute(`ALTER TABLE order_items ADD COLUMN notes TEXT NULL`);
      logger.info('✓ [POS Migration] order_items.notes added');
    }

    for (const sql of alterStmts) {
      await connection.execute(sql);
      logger.info(`✓ [POS Migration] ${sql.split(' ADD COLUMN ')[1]?.split(' ')[0] || 'column'} added to orders`);
    }

    if (alterStmts.length === 0)
      logger.info('✓ [POS Migration] orders columns already up to date');

    // Add bank_transfer to local_payment_method ENUM if not already present
    const [pmColRows] = await connection.execute(
      `SELECT COLUMN_TYPE FROM INFORMATION_SCHEMA.COLUMNS
       WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'orders' AND COLUMN_NAME = 'local_payment_method'`
    );
    if (pmColRows[0] && !pmColRows[0].COLUMN_TYPE.includes('bank_transfer')) {
      await connection.execute(
        `ALTER TABLE orders MODIFY COLUMN local_payment_method ENUM('cash','card','mixed','bank_transfer') NULL`
      );
      logger.info('✓ [POS Migration] orders.local_payment_method: bank_transfer added');
    }

    // Make user_id nullable so local POS orders don't require a customer account
    const [nullableRows] = await connection.execute(
      `SELECT IS_NULLABLE FROM INFORMATION_SCHEMA.COLUMNS
       WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'orders' AND COLUMN_NAME = 'user_id'`
    );
    if (nullableRows[0]?.IS_NULLABLE === 'NO') {
      await connection.execute(`ALTER TABLE orders MODIFY COLUMN user_id VARCHAR(255) NULL`);
      logger.info('✓ [POS Migration] orders.user_id made nullable');
    }

    logger.info('✅ [POS Migration] complete');
  } finally {
    connection.release();
  }
}
