// AdminSalesController.js — the admin "Sales" screen: browse stores by
// category, see running (unsettled) totals since the last settlement,
// settle ("Done") to snapshot + reset the counter, browse settlement
// history, and pull a fully-itemized invoice for any period.
import pool from '../config/database.js';
import logger from '../config/logger.js';
import PDFDocument from 'pdfkit';
import { splitFromCharged } from '../utils/pricing.js';

// ── Shared helpers ──────────────────────────────────────────────────────

async function getPeriodStart(connection, storeId) {
  const [[row]] = await connection.execute(
    `SELECT COALESCE(
       (SELECT MAX(period_end) FROM store_settlements WHERE store_id = ? AND status = 'settled'),
       (SELECT created_at FROM stores WHERE id = ?)
     ) AS period_start`,
    [storeId, storeId]
  );
  return row?.period_start || new Date(0);
}

async function fetchOrderRows(connection, storeId, periodStart, periodEnd) {
  const [rows] = await connection.execute(
    `SELECT
       o.id AS order_id, o.order_type, o.status, o.created_at, o.currency, o.total_price,
       t.name AS table_name,
       oi.id AS item_id, oi.quantity, oi.price AS item_price, oi.notes,
       p.id AS product_id, p.name AS product_name, p.image_url, p.description
     FROM orders o
     JOIN order_items oi ON oi.order_id = o.id
     LEFT JOIN products p ON p.id = oi.product_id
     LEFT JOIN pos_tables t ON t.id = o.table_id
     WHERE o.store_id = ?
       AND o.created_at > ?
       AND o.created_at <= ?
     ORDER BY o.created_at DESC, o.id DESC`,
    [storeId, periodStart, periodEnd]
  );
  return rows;
}

// Totals exclude cancelled orders (nothing was actually charged), but the
// itemized order list below still includes them — the admin explicitly
// wants to see cancelled in-store tickets too, just not counted in totals.
function computeTotals(rows) {
  let onlineCharged = 0, onlineCount = 0;
  let localCharged = 0, localCount = 0;
  const seenOrders = new Set();
  const countedOrders = new Set();

  for (const r of rows) {
    if (!seenOrders.has(r.order_id)) {
      seenOrders.add(r.order_id);
    }
    if (r.status === 'cancelled') continue;
    const itemTotal = Number(r.item_price) * Number(r.quantity);
    if (r.order_type === 'local') {
      localCharged += itemTotal;
      if (!countedOrders.has(r.order_id)) { localCount++; countedOrders.add(r.order_id); }
    } else {
      onlineCharged += itemTotal;
      if (!countedOrders.has(`o${r.order_id}`)) { onlineCount++; countedOrders.add(`o${r.order_id}`); }
    }
  }

  const onlineSplit = splitFromCharged(onlineCharged, { isLocal: false });
  const localSplit = splitFromCharged(localCharged, { isLocal: true });

  return {
    online: {
      order_count: onlineCount,
      gross_charged: Math.round(onlineCharged * 100) / 100,
      platform_share: onlineSplit.platform,
      driver_share: onlineSplit.driver,
      store_share: onlineSplit.base,
    },
    local: {
      order_count: localCount,
      gross_charged: Math.round(localCharged * 100) / 100,
      platform_share: localSplit.platform,
      store_share: localSplit.base,
    },
  };
}

function groupOrders(rows) {
  const byOrder = new Map();
  for (const r of rows) {
    if (!byOrder.has(r.order_id)) {
      const isLocal = r.order_type === 'local';
      // Cancelled orders were never actually charged, so there's no real
      // split to show — just null it out rather than reporting a phantom cut.
      const split = r.status === 'cancelled'
        ? null
        : splitFromCharged(Number(r.total_price), { isLocal });
      byOrder.set(r.order_id, {
        order_id: r.order_id,
        order_type: r.order_type,
        status: r.status,
        created_at: r.created_at,
        currency: r.currency,
        total_price: Number(r.total_price),
        table_name: r.table_name,
        platform_share: split?.platform ?? null,
        driver_share: isLocal ? null : (split?.driver ?? null),
        store_share: split?.base ?? null,
        items: [],
      });
    }
    byOrder.get(r.order_id).items.push({
      item_id: r.item_id,
      product_id: r.product_id,
      product_name: r.product_name,
      image_url: r.image_url,
      description: r.description,
      quantity: r.quantity,
      price: Number(r.item_price),
      notes: r.notes,
    });
  }
  return Array.from(byOrder.values());
}

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
          owed_to_platform: Math.round((totals.online.platform_share + totals.local.platform_share) * 100) / 100,
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
                online_driver_share, settled_at
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
      return res.json({
        success: true,
        data: {
          settlement,
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
  // Fully itemized PDF for a period — every order, every product (with
  // image reference, quantity, table if local), grand totals split by
  // online/local. Public-by-link like the POS invoice (no auth check on
  // the route itself, since it's meant to be handed to the store owner).
  static async getInvoice(req, res) {
    let connection;
    try {
      connection = await pool.getConnection();
      let storeId, periodStart, periodEnd, label;

      if (req.params.id) {
        const [[settlement]] = await connection.execute(`SELECT * FROM store_settlements WHERE id = ?`, [req.params.id]);
        if (!settlement) return res.status(404).send('Settlement not found');
        storeId = settlement.store_id;
        periodStart = settlement.period_start;
        periodEnd = settlement.period_end;
        label = `Settled ${new Date(periodEnd).toISOString().split('T')[0]}`;
      } else {
        storeId = req.params.storeId;
        periodStart = await getPeriodStart(connection, storeId);
        periodEnd = new Date();
        label = 'Current period (unsettled)';
      }

      const [[store]] = await connection.execute(`SELECT name, address, phone, email FROM stores WHERE id = ?`, [storeId]);
      const rows = await fetchOrderRows(connection, storeId, periodStart, periodEnd);
      const totals = computeTotals(rows);
      const orders = groupOrders(rows);

      res.setHeader('Content-Type', 'application/pdf');
      res.setHeader('Content-Disposition', `inline; filename="invoice-store${storeId}-${label.replace(/\s/g, '_')}.pdf"`);

      const doc = new PDFDocument({ size: 'A4', margin: 40 });
      doc.pipe(res);

      doc.fontSize(18).text('YShop — Store Settlement Invoice', { align: 'center' });
      doc.moveDown(0.5);
      doc.fontSize(11).text(store?.name || `Store #${storeId}`, { align: 'center' });
      doc.fontSize(9).fillColor('gray').text(
        [store?.address, store?.phone, store?.email].filter(Boolean).join(' · '),
        { align: 'center' }
      );
      doc.fillColor('black').moveDown();
      doc.fontSize(10).text(`Period: ${new Date(periodStart).toLocaleString()} → ${new Date(periodEnd).toLocaleString()}`);
      doc.text(`Status: ${label}`);
      doc.moveDown();

      doc.fontSize(13).text('Summary', { underline: true });
      doc.fontSize(10);
      doc.text(`Online orders: ${totals.online.order_count} · Gross: ${totals.online.gross_charged} · Platform: ${totals.online.platform_share} · Driver: ${totals.online.driver_share} · Store keeps: ${totals.online.store_share}`);
      doc.text(`In-store orders: ${totals.local.order_count} · Gross: ${totals.local.gross_charged} · Platform: ${totals.local.platform_share} · Store keeps: ${totals.local.store_share}`);
      doc.moveDown();

      doc.fontSize(13).text('Orders', { underline: true });
      doc.moveDown(0.3);
      for (const order of orders) {
        doc.fontSize(10).fillColor(order.status === 'cancelled' ? 'red' : 'black').text(
          `#${order.order_id} · ${order.order_type === 'local' ? `Table ${order.table_name || '—'}` : 'Online'} · ${new Date(order.created_at).toLocaleString()} · ${order.status}${order.status === 'cancelled' ? ' (CANCELLED — excluded from totals)' : ''}`
        );
        doc.fillColor('black');
        if (order.status !== 'cancelled') {
          const shareParts = [`Platform: ${order.platform_share}`, `Store: ${order.store_share}`];
          if (order.order_type !== 'local') shareParts.push(`Driver: ${order.driver_share}`);
          doc.fontSize(8).fillColor('gray').text(`   ${shareParts.join(' · ')}`);
          doc.fillColor('black');
        }
        for (const item of order.items) {
          doc.fontSize(9).text(`   ${item.quantity}x ${item.product_name || 'Product #' + item.product_id} — ${item.price} ${order.currency}`);
        }
        doc.moveDown(0.3);
      }

      doc.end();
    } catch (err) {
      logger.error('[AdminSales] getInvoice error:', err.message);
      return res.status(500).send('Failed to generate invoice');
    } finally {
      if (connection) connection.release();
    }
  }
}

export default AdminSalesController;
