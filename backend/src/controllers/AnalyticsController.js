import pool from '../config/database.js';
import logger from '../config/logger.js';

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

      // ── Q1: Summary ──────────────────────────────────────────────────────
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
            COALESCE(SUM(oi.quantity), 0)                                          AS total_items_sold,
            MIN(o.currency)                                                         AS currency
          FROM orders o
          JOIN order_items oi ON oi.order_id = o.id
          WHERE o.store_id = ?
            AND o.status NOT IN ('cancelled')
            ${periodFilter}
        `, [storeId, storeId, storeId]);
      } catch (e) { logger.error('[Analytics] Q1-summary failed', { error: e.message, period }); }

      // ── Q2: Returns deduction ────────────────────────────────────────────
      let returnsRow = null;
      try {
        [[returnsRow]] = await connection.execute(`
          SELECT COALESCE(SUM(rp.product_price * rp.quantity), 0) AS returns_total
          FROM returned_products rp
          WHERE rp.store_id = ?
            AND rp.admin_accepted = 1
            ${returnsPeriodFilter}
        `, [storeId]);
      } catch (e) { logger.error('[Analytics] Q2-returns failed', { error: e.message, period }); }

      // ── Q3: Top products ─────────────────────────────────────────────────
      let topProducts = [];
      try {
        [topProducts] = await connection.execute(`
          SELECT
            p.id                          AS product_id,
            p.name                        AS product_name,
            p.image_url,
            SUM(oi.quantity)                          AS total_sold,
            COALESCE(SUM(oi.quantity * oi.price), 0)  AS items_revenue,
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

      // ── Q5: Revenue trend (follows selected period) ──────────────────────
      let revenueTrend = [];
      try {
        [revenueTrend] = await connection.execute(`
          SELECT
            ${trend.expr}                             AS date,
            COUNT(DISTINCT o.id)                      AS orders,
            COALESCE(SUM(oi.quantity * oi.price), 0)  AS revenue
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

      const STORE_RATE   = 0.65;
      const grossRevenue = Number(summary?.gross_revenue  ?? 0);
      const returnsTotal = Number(returnsRow?.returns_total ?? 0);
      // Store owner earns 65% of sales, loses 65% of approved returns
      const storeRevenue = (grossRevenue - returnsTotal) * STORE_RATE;
      const storeReturnsDeducted = returnsTotal * STORE_RATE;

      return res.status(200).json({
        success: true,
        period,
        data: {
          summary: {
            total_orders:     Number(summary?.total_orders    ?? 0),
            gross_revenue:    grossRevenue,
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
            revenue:         Number(p.items_revenue) * STORE_RATE,
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
            // trend also shows store's 65% share
            revenue: Number(r.revenue) * STORE_RATE,
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
}
