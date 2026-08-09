// AdminSalesController.js — the admin "Sales" screen: browse stores by
// category, see running (unsettled) totals since the last settlement,
// settle ("Done") to snapshot + reset the counter, browse settlement
// history, and pull a fully-itemized invoice for any period.
import pool from '../config/database.js';
import logger from '../config/logger.js';
import {
  getPeriodStart,
  fetchOrderRows,
  computeTotals,
  groupOrders,
  netFromSettlementRow,
} from '../utils/salesReporting.js';
import { renderInvoicePDF } from '../utils/invoicePdf.js';

export class AdminSalesController {
  // GET /api/v1/admin/sales/categories
  static async getCategories(req, res) {
    try {
      const [rows] = await pool.execute(
        `SELECT COALESCE(NULLIF(store_type,''),'General') AS category, COUNT(*) AS store_count
         FROM stores
         WHERE status = 'approved'
         GROUP BY category
         ORDER BY category`
      );
      return res.json({ success: true, data: rows });
    } catch (err) {
      logger.error('[AdminSales] getCategories error:', err.message);
      return res.status(500).json({ success: false, message: err.message });
    }
  }

  // GET /api/v1/admin/sales/stores?category=Food
  static async getStoresInCategory(req, res) {
    const { category } = req.query;
    let connection;
    try {
      connection = await pool.getConnection();
      const [stores] = await connection.execute(
        `SELECT id, name, address, phone, email, store_type, currency
         FROM stores s
         LEFT JOIN (SELECT store_id, MIN(currency) AS currency FROM products GROUP BY store_id) p ON p.store_id = s.id
         WHERE s.status = 'approved' AND COALESCE(NULLIF(s.store_type,''),'General') = ?
         ORDER BY s.name`,
        [category]
      );

      const results = [];
      for (const store of stores) {
        const periodStart = await getPeriodStart(connection, store.id);
        const rows = await fetchOrderRows(connection, store.id, periodStart, new Date());
        const totals = computeTotals(rows);
        results.push({
          store_id: store.id,
          store_name: store.name,
          address: store.address,
          phone: store.phone,
          email: store.email,
          currency: store.currency || 'USD',
          period_start: periodStart,
          totals,
        });
      }

      return res.json({ success: true, data: results });
    } catch (err) {
      logger.error('[AdminSales] getStoresInCategory error:', err.message);
      return res.status(500).json({ success: false, message: err.message });
    } finally {
      if (connection) connection.release();
    }
  }

  // GET /api/v1/admin/sales/stores/:storeId/current
  static async getCurrentPeriod(req, res) {
    const { storeId } = req.params;
    let connection;
    try {
      connection = await pool.getConnection();
      const periodStart = await getPeriodStart(connection, storeId);
      const periodEnd = new Date();
      const rows = await fetchOrderRows(connection, storeId, periodStart, periodEnd);
      return res.json({
        success: true,
        data: {
          period_start: periodStart,
          period_end: periodEnd,
          totals: computeTotals(rows),
          orders: groupOrders(rows),
        },
      });
    } catch (err) {
      logger.error('[AdminSales] getCurrentPeriod error:', err.message);
      return res.status(500).json({ success: false, message: err.message });
    } finally {
      if (connection) connection.release();
    }
  }

  // POST /api/v1/admin/sales/stores/:storeId/settle  ("Done")
  static async settleStore(req, res) {
    const { storeId } = req.params;
    const adminId = req.admin?.id || null;
    let connection;
    try {
      connection = await pool.getConnection();
      const periodStart = await getPeriodStart(connection, storeId);
      const periodEnd = new Date();
      const rows = await fetchOrderRows(connection, storeId, periodStart, periodEnd);
      const totals = computeTotals(rows);

      const [[currRow]] = await connection.execute(
        `SELECT MIN(currency) AS currency FROM orders WHERE store_id = ? AND created_at > ? AND created_at <= ?`,
        [storeId, periodStart, periodEnd]
      );
      const currency = currRow?.currency || 'USD';

      const [result] = await connection.execute(
        `INSERT INTO store_settlements
         (store_id, period_start, period_end, currency,
          online_order_count, online_gross_charged, online_platform_share, online_driver_share, online_store_share,
          local_order_count, local_gross_charged, local_platform_share, local_store_share,
          status, settled_by_admin_id)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'settled', ?)`,
        [
          storeId, periodStart, periodEnd, currency,
          totals.online.order_count, totals.online.gross_charged, totals.online.platform_share, totals.online.driver_share, totals.online.store_share,
          totals.local.order_count, totals.local.gross_charged, totals.local.platform_share, totals.local.store_share,
          adminId,
        ]
      );

      logger.info(`[AdminSales] Settled store ${storeId}: settlement #${result.insertId}, period ${periodStart} → ${periodEnd}`);
      return res.json({ success: true, data: { settlement_id: result.insertId, period_start: periodStart, period_end: periodEnd, totals } });
    } catch (err) {
      logger.error('[AdminSales] settleStore error:', err.message);
      return res.status(500).json({ success: false, message: err.message });
    } finally {
      if (connection) connection.release();
    }
  }

  // POST /api/v1/admin/sales/stores/:storeId/undo-settle  (toggle "Done" off)
  // Reverts the MOST RECENT settlement for this store — soft: status flips
  // to 'reverted', the row is never deleted, so nothing is ever lost.
  static async undoSettle(req, res) {
    const { storeId } = req.params;
    let connection;
    try {
      connection = await pool.getConnection();
      const [[latest]] = await connection.execute(
        `SELECT id FROM store_settlements WHERE store_id = ? AND status = 'settled' ORDER BY period_end DESC LIMIT 1`,
        [storeId]
      );
      if (!latest) {
        return res.status(404).json({ success: false, message: 'No settlement to undo' });
      }
      await connection.execute(
        `UPDATE store_settlements SET status = 'reverted', reverted_at = NOW() WHERE id = ?`,
        [latest.id]
      );
      logger.info(`[AdminSales] Reverted settlement #${latest.id} for store ${storeId}`);
      return res.json({ success: true, data: { reverted_settlement_id: latest.id } });
    } catch (err) {
      logger.error('[AdminSales] undoSettle error:', err.message);
      return res.status(500).json({ success: false, message: err.message });
    } finally {
      if (connection) connection.release();
    }
  }

  // GET /api/v1/admin/sales/stores/:storeId/settlements  (history list)
  static async getSettlementHistory(req, res) {
    const { storeId } = req.params;
    try {
      const [rows] = await pool.execute(
        `SELECT id, period_start, period_end, currency,
                online_order_count, online_gross_charged, local_order_count, local_gross_charged,
                (online_platform_share + local_platform_share) AS total_platform_share,
                online_driver_share, online_store_share, local_store_share, settled_at
         FROM store_settlements
         WHERE store_id = ? AND status = 'settled'
         ORDER BY period_end DESC`,
        [storeId]
      );
      return res.json({ success: true, data: rows });
    } catch (err) {
      logger.error('[AdminSales] getSettlementHistory error:', err.message);
      return res.status(500).json({ success: false, message: err.message });
    }
  }

  // GET /api/v1/admin/sales/settlements/:id  (full detail for one settled period)
  static async getSettlementDetail(req, res) {
    const { id } = req.params;
    let connection;
    try {
      connection = await pool.getConnection();
      const [[settlement]] = await connection.execute(`SELECT * FROM store_settlements WHERE id = ?`, [id]);
      if (!settlement) {
        return res.status(404).json({ success: false, message: 'Settlement not found' });
      }
      const rows = await fetchOrderRows(connection, settlement.store_id, settlement.period_start, settlement.period_end);
      const totals = {
        online: {
          order_count: settlement.online_order_count,
          gross_charged: Number(settlement.online_gross_charged),
          platform_share: Number(settlement.online_platform_share),
          driver_share: Number(settlement.online_driver_share),
          store_share: Number(settlement.online_store_share),
        },
        local: {
          order_count: settlement.local_order_count,
          gross_charged: Number(settlement.local_gross_charged),
          platform_share: Number(settlement.local_platform_share),
          store_share: Number(settlement.local_store_share),
        },
        net: netFromSettlementRow(settlement),
      };
      return res.json({
        success: true,
        data: {
          settlement,
          totals,
          orders: groupOrders(rows),
        },
      });
    } catch (err) {
      logger.error('[AdminSales] getSettlementDetail error:', err.message);
      return res.status(500).json({ success: false, message: err.message });
    } finally {
      if (connection) connection.release();
    }
  }

  // GET /api/v1/admin/sales/stores/:storeId/current/invoice
  // GET /api/v1/admin/sales/settlements/:id/invoice
  // Fully itemized PDF for a period. Public-by-link like the POS invoice
  // (no auth check on the route itself, since it's meant to be handed to
  // the store owner).
  static async getInvoice(req, res) {
    let connection;
    try {
      connection = await pool.getConnection();
      let storeId, periodStart, periodEnd, label, totals;

      if (req.params.id) {
        const [[settlement]] = await connection.execute(`SELECT * FROM store_settlements WHERE id = ?`, [req.params.id]);
        if (!settlement) return res.status(404).send('Settlement not found');
        storeId = settlement.store_id;
        periodStart = settlement.period_start;
        periodEnd = settlement.period_end;
        label = `Settled ${new Date(periodEnd).toISOString().split('T')[0]}`;
        totals = {
          online: {
            order_count: settlement.online_order_count,
            gross_charged: Number(settlement.online_gross_charged),
            platform_share: Number(settlement.online_platform_share),
            driver_share: Number(settlement.online_driver_share),
            store_share: Number(settlement.online_store_share),
          },
          local: {
            order_count: settlement.local_order_count,
            gross_charged: Number(settlement.local_gross_charged),
            platform_share: Number(settlement.local_platform_share),
            store_share: Number(settlement.local_store_share),
          },
          net: netFromSettlementRow(settlement),
        };
      } else {
        storeId = req.params.storeId;
        periodStart = await getPeriodStart(connection, storeId);
        periodEnd = new Date();
        label = 'Current period (unsettled)';
      }

      const [[store]] = await connection.execute(`SELECT name, address, phone, email FROM stores WHERE id = ?`, [storeId]);
      const rows = await fetchOrderRows(connection, storeId, periodStart, periodEnd);
      if (!totals) totals = computeTotals(rows);
      const orders = groupOrders(rows);
      const currency = rows[0]?.currency || 'USD';

      renderInvoicePDF(res, { store, periodStart, periodEnd, label, totals, orders, currency, forStoreOwner: false });
    } catch (err) {
      logger.error('[AdminSales] getInvoice error:', err.message);
      return res.status(500).send('Failed to generate invoice');
    } finally {
      if (connection) connection.release();
    }
  }
}

export default AdminSalesController;
