// Migration: Store Settlements (admin monthly billing/reconciliation)
//
// A "settlement" is a permanent, immutable snapshot of what a store owes
// the platform (and, for online orders, what's owed to drivers) over a
// period of time. The admin's "Sales" screen shows a running, unsettled
// total computed live from orders since the last settlement; pressing
// "Done" writes one of these rows and the running total starts fresh from
// that moment. Nothing is ever deleted — "undo" flips status back to
// 'reverted' rather than removing the row, so history is never lost.

import pool from '../../src/config/database.js';
import logger from '../../src/config/logger.js';

export async function runStoreSettlementsMigration() {
  const connection = await pool.getConnection();
  try {
    await connection.execute(`
      CREATE TABLE IF NOT EXISTS store_settlements (
        id                     INT           NOT NULL AUTO_INCREMENT,
        store_id               INT           NOT NULL,
        period_start           DATETIME      NOT NULL,
        period_end             DATETIME      NOT NULL,
        currency                VARCHAR(10)   NOT NULL DEFAULT 'USD',

        online_order_count      INT           NOT NULL DEFAULT 0,
        online_gross_charged    DECIMAL(12,2) NOT NULL DEFAULT 0,
        online_platform_share   DECIMAL(12,2) NOT NULL DEFAULT 0,
        online_driver_share     DECIMAL(12,2) NOT NULL DEFAULT 0,
        online_store_share      DECIMAL(12,2) NOT NULL DEFAULT 0,

        local_order_count       INT           NOT NULL DEFAULT 0,
        local_gross_charged     DECIMAL(12,2) NOT NULL DEFAULT 0,
        local_platform_share    DECIMAL(12,2) NOT NULL DEFAULT 0,
        local_store_share       DECIMAL(12,2) NOT NULL DEFAULT 0,

        status                 ENUM('settled','reverted') NOT NULL DEFAULT 'settled',
        settled_by_admin_id    INT           NULL,
        settled_at             DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
        reverted_at            DATETIME      NULL,
        created_at             DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,

        PRIMARY KEY (id),
        KEY idx_store_id (store_id),
        KEY idx_store_status (store_id, status),
        KEY idx_period_end (period_end)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    `);
    logger.info('✓ [Settlements Migration] store_settlements table ready');
  } catch (err) {
    logger.error('[Settlements Migration] failed:', err.message);
    throw err;
  } finally {
    connection.release();
  }
}
