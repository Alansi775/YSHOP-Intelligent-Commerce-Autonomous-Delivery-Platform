import pool from '../config/database.js';
import logger from '../config/logger.js';
import { splitFromCharged } from '../utils/pricing.js';

const PERIOD_SQL = {
  hour:  `AND o.created_at >= DATE_SUB(NOW(), INTERVAL 1 HOUR)`,
  today: `AND DATE(o.created_at) = CURDATE()`,
  week:  `AND o.created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)`,
  month: `AND o.created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)`,
  year:  `AND o.created_at >= DATE_SUB(NOW(), INTERVAL 365 DAY)`,
};

// SELECT and GROUP BY use the same expr — required for MySQL strict/ONLY_FULL_GROUP_BY mode
const TREND_CONFIG = {
  hour:  { filter: `AND o.created_at >= DATE_SUB(NOW(), INTERVAL 24 HOUR)`, expr: `DATE_FORMAT(o.created_at, '%m-%d %H:00')` },
  today: { filter: `AND o.created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)`,   expr: `DATE_FORMAT(o.created_at, '%m-%d')` },
  week:  { filter: `AND o.created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)`,   expr: `DATE_FORMAT(o.created_at, '%m-%d')` },
  month: { filter: `AND o.created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)`,  expr: `DATE_FORMAT(o.created_at, '%m-%d')` },
  year:  { filter: `AND o.created_at >= DATE_SUB(NOW(), INTERVAL 365 DAY)`, expr: `DATE_FORMAT(o.created_at, '%Y-%m')` },
};

const RETURNS_PERIOD_SQL = {
  hour:  `AND rp.return_requested_at >= DATE_SUB(NOW(), INTERVAL 1 HOUR)`,
  today: `AND DATE(rp.return_requested_at) = CURDATE()`,
  week:  `AND rp.return_requested_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)`,
  month: `AND rp.return_requested_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)`,
  year:  `AND rp.return_requested_at >= DATE_SUB(NOW(), INTERVAL 365 DAY)`,
};

const fmtDate = (d) => d instanceof Date ? d.toISOString().split('T')[0] : String(d || '');

// Charged totals already have the fee baked in on top of the store's base
// price (see utils/pricing.js) — reverse each bucket back to the store's
// share rather than assuming a flat percentage of the charged total.
const storeShare = (localCharged, onlineCharged) =>
  splitFromCharged(localCharged, { isLocal: true }).base +
  splitFromCharged(onlineCharged, { isLocal: false }).base;

export class AnalyticsController {

  static async getStoreAnalytics(req, res) {
    const { storeId } = req.params;
    const period = req.query.period || 'month';
    const periodFilter = PERIOD_SQL[period] || PERIOD_SQL.month;
    const periodFilterRaw = periodFilter.replace(/\bo\./g, '');
    const returnsPeriodFilter = RETURNS_PERIOD_SQL[period] || RETURNS_PERIOD_SQL.month;
    const trend = TREND_CONFIG[period] || TREND_CONFIG.month;

    let connection;
    try {
      connection = await pool.getConnection();
      await connection.execute('SET SESSION group_concat_max_len = 65535');

      // ── Q0: Store currency (independent of period — always available) ────
      let storeCurrency = 'USD';
      try {
        const [[currRow]] = await connection.execute(
          `SELECT MIN(currency) AS c FROM orders WHERE store_id = ? LIMIT 1`,
          [storeId]
        );
        storeCurrency = currRow?.c || 'USD';
      } catch (_) {}

      // ── Q1: Summary — online vs local split so the driver cut only ever
      // applies to online/delivered revenue ─────────────────────────────────
      let summary = null;
      try {
        [[summary]] = await connection.execute(`
          SELECT
            (SELECT COUNT(*)
             FROM orders
             WHERE store_id = ? AND status NOT IN ('cancelled') ${periodFilterRaw})   AS total_orders,
            (SELECT COUNT(*)
             FROM orders
             WHERE store_id = ? AND status = 'cancelled' ${periodFilterRaw})          AS cancelled_orders,
            COALESCE(SUM(oi.quantity * oi.price), 0)                               AS gross_revenue,
            COALESCE(SUM(CASE WHEN o.order_type = 'local' THEN oi.quantity * oi.price ELSE 0 END), 0) AS gross_revenue_local,
            COALESCE(SUM(CASE WHEN o.order_type != 'local' THEN oi.quantity * oi.price ELSE 0 END), 0) AS gross_revenue_online,
            COALESCE(SUM(oi.quantity), 0)                                          AS total_items_sold,
            MIN(o.currency)                                                         AS currency
          FROM orders o
          JOIN order_items oi ON oi.order_id = o.id
          WHERE o.store_id = ?
            AND o.status NOT IN ('cancelled')
            ${periodFilter}
        `, [storeId, storeId, storeId]);
      } catch (e) { logger.error('[Analytics] Q1-summary failed', { error: e.message, period }); }

      // ── Q2: Returns deduction — also split by order_type ─────────────────
      let returnsRow = null;
      try {
        [[returnsRow]] = await connection.execute(`
          SELECT
            COALESCE(SUM(rp.product_price * rp.quantity), 0) AS returns_total,
            COALESCE(SUM(CASE WHEN o.order_type = 'local' THEN rp.product_price * rp.quantity ELSE 0 END), 0) AS returns_local,
            COALESCE(SUM(CASE WHEN o.order_type != 'local' THEN rp.product_price * rp.quantity ELSE 0 END), 0) AS returns_online
          FROM returned_products rp
          LEFT JOIN orders o ON o.id = rp.order_id
          WHERE rp.store_id = ?
            AND rp.admin_accepted = 1
            ${returnsPeriodFilter}
        `, [storeId]);
      } catch (e) { logger.error('[Analytics] Q2-returns failed', { error: e.message, period }); }

      // ── Q3: Top products — per-product online/local split ───────────────
      let topProducts = [];
      try {
        [topProducts] = await connection.execute(`
          SELECT
            p.id                          AS product_id,
            p.name                        AS product_name,
            p.image_url,
            SUM(oi.quantity)                          AS total_sold,
            COALESCE(SUM(oi.quantity * oi.price), 0)  AS items_revenue,
            COALESCE(SUM(CASE WHEN o.order_type = 'local' THEN oi.quantity * oi.price ELSE 0 END), 0) AS items_revenue_local,
            COALESCE(SUM(CASE WHEN o.order_type != 'local' THEN oi.quantity * oi.price ELSE 0 END), 0) AS items_revenue_online,
            COUNT(DISTINCT o.id)                       AS order_count,
            MAX(o.created_at)             AS last_ordered_at,
            MIN(o.currency)               AS currency
          FROM order_items oi
          JOIN orders   o ON o.id  = oi.order_id
          JOIN products p ON p.id  = oi.product_id
          WHERE o.store_id = ?
            AND o.status != 'cancelled'
            ${periodFilter}
          GROUP BY p.id, p.name, p.image_url
          ORDER BY total_sold DESC
          LIMIT 10
        `, [storeId]);
      } catch (e) { logger.error('[Analytics] Q3-topProducts failed', { error: e.message, period }); }

      // ── Q4: Return analysis ──────────────────────────────────────────────
      let returnedProducts = [];
      try {
        [returnedProducts] = await connection.execute(`
          SELECT
            rp.product_id,
            rp.product_name,
            rp.product_image_url                      AS image_url,
            COUNT(*)                                   AS return_count,
            MAX(rp.return_requested_at)               AS last_returned_at,
            MIN(rp.product_currency)                  AS currency,
            GROUP_CONCAT(
              SUBSTRING(rp.return_reason, 1, 100)
              ORDER BY rp.return_requested_at DESC
              SEPARATOR '||'
            )                                          AS reasons
          FROM returned_products rp
          WHERE rp.store_id = ?
            AND rp.return_requested_at >= DATE_SUB(NOW(), INTERVAL 365 DAY)
          GROUP BY rp.product_id, rp.product_name, rp.product_image_url
          ORDER BY return_count DESC
          LIMIT 10
        `, [storeId]);
      } catch (e) { logger.error('[Analytics] Q4-returns failed', { error: e.message, period }); }

      // ── Q5: Revenue trend (follows selected period) — online/local split ─
      let revenueTrend = [];
      try {
        [revenueTrend] = await connection.execute(`
          SELECT
            ${trend.expr}                             AS date,
            COUNT(DISTINCT o.id)                      AS orders,
            COALESCE(SUM(oi.quantity * oi.price), 0)  AS revenue,
            COALESCE(SUM(CASE WHEN o.order_type = 'local' THEN oi.quantity * oi.price ELSE 0 END), 0) AS revenue_local,
            COALESCE(SUM(CASE WHEN o.order_type != 'local' THEN oi.quantity * oi.price ELSE 0 END), 0) AS revenue_online
          FROM orders o
          JOIN order_items oi ON oi.order_id = o.id
          WHERE o.store_id = ?
            AND o.status != 'cancelled'
            ${trend.filter}
          GROUP BY ${trend.expr}
          ORDER BY ${trend.expr} ASC
        `, [storeId]);
      } catch (e) { logger.error('[Analytics] Q5-trend failed', { error: e.message, period }); }

      // ── Build response ───────────────────────────────────────────────────
      const returnMap = {};
      for (const r of returnedProducts) {
        returnMap[String(r.product_id)] = Number(r.return_count);
      }

      const grossRevenue = Number(summary?.gross_revenue ?? 0);
      const grossRevenueLocal = Number(summary?.gross_revenue_local ?? 0);
      const grossRevenueOnline = Number(summary?.gross_revenue_online ?? 0);
      const returnsTotal = Number(returnsRow?.returns_total ?? 0);
      const returnsLocal = Number(returnsRow?.returns_local ?? 0);
      const returnsOnline = Number(returnsRow?.returns_online ?? 0);

      // Store owner earns 75%/65% of sales (local/online), loses the same
      // rate on approved returns of that same type.
      const storeRevenue = storeShare(grossRevenueLocal - returnsLocal, grossRevenueOnline - returnsOnline);
      const storeReturnsDeducted = storeShare(returnsLocal, returnsOnline);

      return res.status(200).json({
        success: true,
        period,
        data: {
          summary: {
            total_orders:     Number(summary?.total_orders    ?? 0),
            gross_revenue:    grossRevenue,
            gross_revenue_local:  grossRevenueLocal,
            gross_revenue_online: grossRevenueOnline,
            returns_deducted: storeReturnsDeducted,
            total_revenue:    storeRevenue,
            total_items_sold: Number(summary?.total_items_sold ?? 0),
            cancelled_orders: Number(summary?.cancelled_orders ?? 0),
            currency:         summary?.currency || storeCurrency,
          },
          top_products: topProducts.map(p => ({
            product_id:      p.product_id,
            product_name:    p.product_name,
            image_url:       p.image_url,
            total_sold:      Number(p.total_sold),
            revenue:         storeShare(p.items_revenue_local, p.items_revenue_online),
            order_count:     Number(p.order_count),
            return_count:    returnMap[String(p.product_id)] || 0,
            last_ordered_at: fmtDate(p.last_ordered_at),
            currency:        p.currency || storeCurrency,
          })),
          returned_products: returnedProducts.map(r => ({
            product_id:       r.product_id,
            product_name:     r.product_name,
            image_url:        r.image_url,
            return_count:     Number(r.return_count),
            last_returned_at: fmtDate(r.last_returned_at),
            currency:         r.currency || storeCurrency,
            reasons:          (r.reasons || '').split('||').filter(Boolean),
          })),
          revenue_trend: revenueTrend.map(r => ({
            date:    r.date instanceof Date ? r.date.toISOString().split('T')[0] : String(r.date),
            orders:  Number(r.orders),
            // store's share, correctly split between local (75%) and online (65%)
            revenue: storeShare(r.revenue_local, r.revenue_online),
          })),
        },
      });

    } catch (err) {
      logger.error('[Analytics] getStoreAnalytics fatal error', { error: err.message, storeId, period });
      return res.status(500).json({ success: false, message: err.message });
    } finally {
      if (connection) connection.release();
    }
  }

  // ── Admin: per-store financial breakdown ──────────────────────────────
  // GET /api/v1/analytics/admin/stores-summary?period=today|week|month|year
  //
  // For every store: online (delivered) vs in-store (dine-in/POS) revenue,
  // in that store's own currency, with the platform/driver/store split
  // reversed out of each charged total — plus a per-table breakdown of
  // in-store sales so the admin can reconcile against a specific ticket.
  static async getAdminStoresSummary(req, res) {
    const period = req.query.period || 'month';
    const periodFilter = PERIOD_SQL[period] || PERIOD_SQL.month;

    let connection;
    try {
      connection = await pool.getConnection();

      const [rows] = await connection.execute(`
        SELECT
          s.id                        AS store_id,
          s.name                      AS store_name,
          s.store_type,
          o.order_type,
          t.name                      AS table_name,
          COUNT(DISTINCT o.id)        AS order_count,
          COALESCE(SUM(oi.quantity * oi.price), 0) AS gross_charged,
          MIN(o.currency)             AS currency
        FROM orders o
        JOIN order_items oi ON oi.order_id = o.id
        JOIN stores s       ON s.id = o.store_id
        LEFT JOIN pos_tables t ON t.id = o.table_id
        WHERE o.status NOT IN ('cancelled')
          ${periodFilter}
        GROUP BY s.id, s.name, s.store_type, o.order_type, t.name
        ORDER BY s.name
      `);

      const storesByid = new Map();
      for (const r of rows) {
        if (!storesByid.has(r.store_id)) {
          storesByid.set(r.store_id, {
            store_id: r.store_id,
            store_name: r.store_name,
            store_type: r.store_type,
            currency: r.currency || 'USD',
            online: { order_count: 0, gross_charged: 0 },
            local: { order_count: 0, gross_charged: 0 },
            local_by_table: [],
          });
        }
        const entry = storesByid.get(r.store_id);
        const isLocal = r.order_type === 'local';
        const bucket = isLocal ? entry.local : entry.online;
        bucket.order_count += Number(r.order_count);
        bucket.gross_charged += Number(r.gross_charged);
        if (isLocal) {
          entry.local_by_table.push({
            table_name: r.table_name || 'Unassigned table',
            order_count: Number(r.order_count),
            gross_charged: Number(r.gross_charged),
          });
        }
      }

      const stores = Array.from(storesByid.values()).map((entry) => {
        const onlineSplit = splitFromCharged(entry.online.gross_charged, { isLocal: false });
        const localSplit = splitFromCharged(entry.local.gross_charged, { isLocal: true });
        return {
          store_id: entry.store_id,
          store_name: entry.store_name,
          store_type: entry.store_type,
          currency: entry.currency,
          online: {
            order_count: entry.online.order_count,
            gross_charged: Math.round(entry.online.gross_charged * 100) / 100,
            store_owes_platform: onlineSplit.platform,
            store_owes_driver: onlineSplit.driver,
            store_keeps: onlineSplit.base,
          },
          local: {
            order_count: entry.local.order_count,
            gross_charged: Math.round(entry.local.gross_charged * 100) / 100,
            store_owes_platform: localSplit.platform,
            store_keeps: localSplit.base,
            by_table: entry.local_by_table,
          },
          totals: {
            order_count: entry.online.order_count + entry.local.order_count,
            gross_charged: Math.round((entry.online.gross_charged + entry.local.gross_charged) * 100) / 100,
            owed_to_platform: Math.round((onlineSplit.platform + localSplit.platform) * 100) / 100,
            owed_to_drivers: onlineSplit.driver,
            store_keeps: Math.round((onlineSplit.base + localSplit.base) * 100) / 100,
          },
        };
      });

      return res.status(200).json({ success: true, period, data: { stores } });
    } catch (err) {
      logger.error('[Analytics] getAdminStoresSummary fatal error', { error: err.message, period });
      return res.status(500).json({ success: false, message: err.message });
    } finally {
      if (connection) connection.release();
    }
  }
}
