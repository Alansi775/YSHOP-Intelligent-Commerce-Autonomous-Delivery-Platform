// POSController.js — Local Restaurant POS System
// Reuses existing products, stock, orders tables.
// order_type='local' + table_id distinguish POS orders from online orders.

import pool from '../config/database.js';
import logger from '../config/logger.js';
import { getIO } from '../utils/socketInstance.js';
import { v4 as uuidv4 } from 'uuid';
import PDFDocument from 'pdfkit';
import path from 'path';
import fs from 'fs';

// ─── WebSocket helper ───────────────────────────────────────────────────────
// All POS events go to room `pos:{storeId}` so cashier, kitchen,
// and customer tracking page can subscribe to the same room.
function emitPOS(storeId, event, data) {
  const io = getIO();
  if (io) {
    io.to(`pos:${storeId}`).emit(event, data);
    logger.debug(`[POS] emit ${event} → pos:${storeId}`);
  }
}

// ─── Guard: FOOD-only features ───────────────────────────────────────────────
// Store must be type food/restaurant/cafe/bakery to use tables & kitchen.
function isFoodStore(storeType) {
  const t = (storeType || '').toLowerCase().trim();
  return ['food', 'restaurant', 'cafe', 'bakery', 'مطعم', 'كافيه', 'مخبز'].includes(t);
}

// ─── PDF receipt for POS orders ─────────────────────────────────────────────
// Resolve a local /uploads/... URL to its file on disk (uploads are served
// straight off the filesystem — see server.js `app.use('/uploads', ...)`).
function resolveUploadPath(url) {
  if (!url || !url.startsWith('/uploads/')) return null;
  const abs = path.join(process.cwd(), url);
  return fs.existsSync(abs) ? abs : null;
}

function streamPOSReceiptPDF(res, { order, items, store, tableName }) {
  const date = new Date(order.created_at || Date.now()).toLocaleString('en-US', {
    year: 'numeric', month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit',
  });
  const currency = order.currency || '';
  const total = Number(order.total_price || 0).toFixed(2);

  const doc = new PDFDocument({ size: 'A5', margin: 36 });
  res.setHeader('Content-Type', 'application/pdf');
  res.setHeader('Content-Disposition', `attachment; filename="receipt_${order.id}.pdf"`);
  doc.pipe(res);

  // Header — logo (if a local file is available) or the store name as text
  const logoPath = resolveUploadPath(store?.icon_url);
  if (logoPath) {
    try { doc.image(logoPath, { fit: [120, 60], align: 'center' }); } catch { /* corrupt/unsupported image — skip */ }
    doc.moveDown(0.5);
  } else {
    doc.fontSize(20).font('Helvetica-Bold').text(store?.name || 'YSHOP', { align: 'center' });
    doc.moveDown(0.5);
  }

  doc.fontSize(14).font('Helvetica-Bold').text(`Receipt #${order.id}`, { align: 'center' });
  doc.fontSize(9).font('Helvetica').fillColor('#888')
    .text([tableName ? `Table: ${tableName}` : null, date, order.local_payment_method || 'Pay later']
      .filter(Boolean).join('   •   '), { align: 'center' });
  doc.fillColor('#000').moveDown(1);

  // Item table — columns are computed from the actual page width instead of
  // hardcoded, so the price column always has real room (a fixed x=380 on an
  // A5 page left ~4pt for "PRICE", which wrapped every letter onto its own line).
  const left  = 36;
  const right = doc.page.width - 36;
  const qtyW   = 40;
  const priceW = 100;
  const qtyX   = right - priceW - 10 - qtyW;
  const priceX = right - priceW;
  const itemW  = qtyX - left - 8;

  doc.fontSize(9).font('Helvetica-Bold').fillColor('#888');
  let y = doc.y;
  doc.text('ITEM', left, y, { width: itemW });
  doc.text('QTY', qtyX, y, { width: qtyW, align: 'center' });
  doc.text('PRICE', priceX, y, { width: priceW, align: 'right' });
  doc.fillColor('#000').moveDown(0.3);
  doc.moveTo(left, doc.y).lineTo(right, doc.y).strokeColor('#ddd').stroke();
  doc.moveDown(0.4);

  for (const it of (items || [])) {
    const name = it.product_name || it.name || '—';
    const lineTotal = (Number(it.price) * Number(it.quantity)).toFixed(2);
    y = doc.y;
    doc.fontSize(10).font('Helvetica').fillColor('#000').text(name, left, y, { width: itemW });
    doc.text(`${it.quantity}`, qtyX, y, { width: qtyW, align: 'center' });
    doc.text(`${lineTotal} ${currency}`, priceX, y, { width: priceW, align: 'right' });
    if (it.notes) {
      doc.fontSize(8).fillColor('#888').text(it.notes, left, doc.y, { width: itemW });
      doc.fillColor('#000');
    }
    doc.moveDown(0.5);
  }

  doc.moveTo(left, doc.y).lineTo(right, doc.y).strokeColor('#ddd').stroke();
  doc.moveDown(0.5);
  y = doc.y;
  doc.fontSize(13).font('Helvetica-Bold').fillColor('#000');
  doc.text('TOTAL', left, y, { width: itemW + 8 + qtyW });
  doc.text(`${total} ${currency}`, priceX, y, { width: priceW, align: 'right' });

  if (store?.name) {
    doc.moveDown(2);
    doc.fontSize(9).font('Helvetica').fillColor('#aaa')
      .text(`Thank you for visiting ${store.name}`, { align: 'center' });
  }

  doc.end();
}

// ─── HTML for customer tracking page (served to QR scan) ───────────────────
function renderCustomerTrackingHTML({ store, tableName, order, items }) {
  const statusMap = {
    pending:    { label: 'Order Received',  color: '#2196f3', emoji: '📋' },
    preparing:  { label: 'Being Prepared',  color: '#ff9800', emoji: '👨‍🍳' },
    ready:      { label: 'Ready!',          color: '#4caf50', emoji: '✅' },
    delivered:  { label: 'Delivered',       color: '#9c27b0', emoji: '🎉' },
  };
  const st = statusMap[order?.kitchen_status || 'pending'] || statusMap.pending;
  const currency = order?.currency || '';
  const total = order ? Number(order.total_price || 0).toFixed(2) : '—';

  const itemList = (items || []).map(it =>
    `<li style="padding:6px 0;border-bottom:1px solid #f0f0f0">${it.product_name || it.name} × ${it.quantity}
      <span style="float:right">${Number(it.price).toFixed(2)} ${currency}</span></li>`
  ).join('');

  const logoBlock = store?.icon_url
    ? `<img src="${store.icon_url}" style="max-height:48px;max-width:130px">`
    : `<strong>${store?.name || 'YSHOP'}</strong>`;

  const autoRefresh = order && !['delivered'].includes(order.kitchen_status)
    ? `<meta http-equiv="refresh" content="10">` : '';

  return `<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  ${autoRefresh}
  <title>Order Status — ${store?.name || 'YSHOP'}</title>
  <style>
    *{box-sizing:border-box}
    body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Arial;margin:0;background:#f9f9f9;color:#111}
    .header{background:#111;color:#fff;padding:16px 20px;display:flex;align-items:center;gap:12px}
    .card{max-width:480px;margin:24px auto;background:#fff;border-radius:12px;overflow:hidden;box-shadow:0 2px 12px rgba(0,0,0,.08)}
    .status-block{padding:28px 24px;text-align:center}
    .emoji{font-size:52px;margin-bottom:8px}
    .status-label{font-size:22px;font-weight:700;color:${st.color}}
    .table-name{color:#888;font-size:14px;margin-top:4px}
    .items-block{padding:0 20px 20px}
    h3{font-size:14px;color:#888;margin:0 0 8px;text-transform:uppercase;letter-spacing:.05em}
    ul{list-style:none;padding:0;margin:0}
    .total{padding:12px 20px;background:#f9f9f9;font-weight:700;display:flex;justify-content:space-between}
    .refresh-note{text-align:center;color:#bbb;font-size:12px;padding:12px}
    @media(prefers-color-scheme:dark){body{background:#0a0a0a;color:#eee}.card{background:#1a1a1a;box-shadow:none}.total{background:#111}.header{background:#000}li{border-color:#2a2a2a!important}}
  </style>
</head>
<body>
  <div class="header">
    ${logoBlock}
    <span style="margin-left:auto;font-size:13px;opacity:.7">Powered by YSHOP</span>
  </div>
  <div class="card">
    <div class="status-block">
      <div class="emoji">${st.emoji}</div>
      <div class="status-label">${st.label}</div>
      <div class="table-name">${tableName ? `Table: ${tableName}` : ''}</div>
    </div>
    ${order ? `
    <div class="items-block">
      <h3>Your Order</h3>
      <ul>${itemList}</ul>
    </div>
    <div class="total"><span>Total</span><span>${total} ${currency}</span></div>
    ` : '<div style="padding:20px;text-align:center;color:#888">No active order for this table.</div>'}
    ${order && !['delivered'].includes(order.kitchen_status) ? `<div class="refresh-note">Auto-refreshes every 10 seconds</div>` : ''}
  </div>
</body>
</html>`;
}

class POSController {

  // ═══════════════════════════════════════════════════════════════════════════
  // TABLE MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  // GET /api/v1/pos/tables?storeId=X
  static async getTables(req, res, next) {
    try {
      const { storeId } = req.query;
      if (!storeId) return res.status(400).json({ success: false, message: 'storeId required' });

      const [rows] = await pool.execute(
        `SELECT SQL_NO_CACHE t.*,
                (SELECT COUNT(*) FROM orders o
                 WHERE o.table_id = t.id AND o.order_type = 'local'
                   AND o.status NOT IN ('cancelled','completed')
                   AND o.local_paid = 0) AS has_active_order
         FROM pos_tables t
         WHERE t.store_id = ?
         ORDER BY t.sort_order ASC, t.id ASC`,
        [storeId]
      );
      res.json({ success: true, tables: rows });
    } catch (err) {
      next(err);
    }
  }

  // POST /api/v1/pos/tables
  static async createTable(req, res, next) {
    try {
      const { storeId, name, capacity = 4 } = req.body;
      if (!storeId || !name) return res.status(400).json({ success: false, message: 'storeId and name required' });

      const qrToken = uuidv4().replace(/-/g, '');
      const [r] = await pool.execute(
        `INSERT INTO pos_tables (store_id, name, capacity, qr_token) VALUES (?, ?, ?, ?)`,
        [storeId, name.trim(), Number(capacity) || 4, qrToken]
      );
      const [rows] = await pool.execute(`SELECT SQL_NO_CACHE * FROM pos_tables WHERE id = ?`, [r.insertId]);
      const table = rows[0];

      emitPOS(storeId, 'pos:table_updated', { action: 'created', table });
      res.status(201).json({ success: true, table });
    } catch (err) {
      next(err);
    }
  }

  // PUT /api/v1/pos/tables/:tableId
  static async updateTable(req, res, next) {
    try {
      const { tableId } = req.params;
      const { name, capacity, status, sort_order } = req.body;

      const updates = [];
      const values = [];
      if (name !== undefined)       { updates.push('name = ?');       values.push(name.trim()); }
      if (capacity !== undefined)   { updates.push('capacity = ?');   values.push(Number(capacity)); }
      if (status !== undefined)     { updates.push('status = ?');     values.push(status); }
      if (sort_order !== undefined) { updates.push('sort_order = ?'); values.push(Number(sort_order)); }
      if (!updates.length) return res.status(400).json({ success: false, message: 'Nothing to update' });

      values.push(tableId);
      await pool.execute(`UPDATE pos_tables SET ${updates.join(', ')} WHERE id = ?`, values);
      const [rows] = await pool.execute(`SELECT SQL_NO_CACHE * FROM pos_tables WHERE id = ?`, [tableId]);
      const table = rows[0];

      if (table) emitPOS(table.store_id, 'pos:table_updated', { action: 'updated', table });
      res.json({ success: true, table });
    } catch (err) {
      next(err);
    }
  }

  // DELETE /api/v1/pos/tables/:tableId
  static async deleteTable(req, res, next) {
    try {
      const { tableId } = req.params;
      const [rows] = await pool.execute(`SELECT SQL_NO_CACHE * FROM pos_tables WHERE id = ?`, [tableId]);
      if (!rows.length) return res.status(404).json({ success: false, message: 'Table not found' });
      const table = rows[0];

      await pool.execute(`DELETE FROM pos_tables WHERE id = ?`, [tableId]);
      emitPOS(table.store_id, 'pos:table_updated', { action: 'deleted', tableId: Number(tableId) });
      res.json({ success: true });
    } catch (err) {
      next(err);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // POS ORDERS — Cashier
  // ═══════════════════════════════════════════════════════════════════════════

  // POST /api/v1/pos/orders
  // Body: { storeId, tableId?, items: [{productId, quantity, price, notes?}], cashierNotes?, paymentMethod? }
  static async createOrder(req, res, next) {
    const connection = await pool.getConnection();
    try {
      const { storeId, tableId, items, cashierNotes, paymentMethod } = req.body;
      // POS orders always go to kitchen first — cashier settles payment after delivery
      const payNow = false;
      // Local POS orders have no customer account — user_id is NULL
      if (!storeId || !items?.length) {
        connection.release();
        return res.status(400).json({ success: false, message: 'storeId and items required' });
      }

      // Block a second order for a table that already has an open (unpaid) tab —
      // even if the kitchen already marked it "delivered" (pay-later: the guest
      // is still at the table and may order more). The cashier should add items
      // to that order instead — this just guards against a duplicate ticket.
      if (tableId) {
        const [existing] = await connection.execute(
          `SELECT SQL_NO_CACHE id FROM orders
           WHERE table_id = ? AND order_type = 'local' AND local_paid = 0
             AND status NOT IN ('cancelled','delivered')
           LIMIT 1`,
          [tableId]
        );
        if (existing.length > 0) {
          connection.release();
          return res.status(409).json({
            success: false,
            message: 'Table already has an open order. Add items to it instead.',
            existingOrderId: existing[0].id,
          });
        }
      }

      // Currency from store's products
      let currency = 'SAR';
      const [cRows] = await connection.execute(
        `SELECT SQL_NO_CACHE COALESCE(currency,'SAR') AS currency FROM products WHERE store_id = ? LIMIT 1`,
        [storeId]
      );
      if (cRows.length) currency = cRows[0].currency;

      const totalPrice = items.reduce((s, it) => s + (Number(it.price) * Number(it.quantity)), 0);

      await connection.beginTransaction();

      const [res1] = await connection.execute(
        `INSERT INTO orders
         (user_id, store_id, total_price, currency, status, order_type, table_id, kitchen_status,
          local_payment_method, local_paid, cashier_notes, payment_method, created_at)
         VALUES (?, ?, ?, ?, 'pending', 'local', ?, 'pending', ?, 0, ?, 'pos', NOW())`,
        [
          null,
          storeId, totalPrice.toFixed(2), currency,
          tableId || null,
          paymentMethod || null,
          cashierNotes || null,
        ]
      );
      const orderId = res1.insertId;

      for (const item of items) {
        await connection.execute(
          `INSERT INTO order_items (order_id, product_id, quantity, price, notes)
           VALUES (?, ?, ?, ?, ?)
           ON DUPLICATE KEY UPDATE quantity = VALUES(quantity)`,
          [orderId, item.productId, item.quantity, item.price, item.notes || null]
        );
        // Reserve stock
        await connection.execute(
          `UPDATE products SET stock = GREATEST(stock - ?, 0) WHERE id = ?`,
          [item.quantity, item.productId]
        );
      }

      // Update table status to 'occupied'
      if (tableId) {
        await connection.execute(
          `UPDATE pos_tables SET status = 'occupied' WHERE id = ?`,
          [tableId]
        );
      }

      await connection.commit();
      connection.release();

      const [oRows] = await pool.execute(`SELECT SQL_NO_CACHE * FROM orders WHERE id = ?`, [orderId]);
      const [iRows] = await pool.execute(
        `SELECT SQL_NO_CACHE oi.*, p.name AS product_name, p.image_url FROM order_items oi
         JOIN products p ON p.id = oi.product_id WHERE oi.order_id = ?`,
        [orderId]
      );
      const order = { ...oRows[0], items: iRows };

      emitPOS(storeId, 'pos:order_new', { order });
      if (tableId) {
        const [tRows] = await pool.execute(`SELECT SQL_NO_CACHE * FROM pos_tables WHERE id = ?`, [tableId]);
        if (tRows.length) emitPOS(storeId, 'pos:table_updated', { action: 'updated', table: tRows[0] });
      }

      res.status(201).json({ success: true, order });
    } catch (err) {
      await connection.rollback().catch(() => {});
      connection.release();
      next(err);
    }
  }

  // GET /api/v1/pos/orders?storeId=X&date=YYYY-MM-DD&status=active
  static async getOrders(req, res, next) {
    try {
      const { storeId, date, status } = req.query;
      if (!storeId) return res.status(400).json({ success: false, message: 'storeId required' });

      let where = `o.store_id = ? AND o.order_type = 'local'`;
      const params = [storeId];

      if (date) {
        where += ` AND DATE(o.created_at) = ?`;
        params.push(date);
      }
      if (status === 'active') {
        where += ` AND o.status NOT IN ('cancelled','completed') AND o.local_paid = 0`;
      }

      const [orders] = await pool.execute(
        `SELECT SQL_NO_CACHE o.*, t.name AS table_name,
                JSON_ARRAYAGG(JSON_OBJECT(
                  'id', oi.id, 'product_id', oi.product_id, 'product_name', p.name,
                  'image_url', p.image_url, 'quantity', oi.quantity, 'price', oi.price,
                  'notes', oi.notes, 'currency', p.currency, 'created_at', oi.created_at
                )) AS items
         FROM orders o
         LEFT JOIN pos_tables t ON t.id = o.table_id
         LEFT JOIN order_items oi ON oi.order_id = o.id
         LEFT JOIN products p ON p.id = oi.product_id
         WHERE ${where}
         GROUP BY o.id
         ORDER BY o.created_at DESC`,
        params
      );

      // Parse JSON items string
      const parsed = orders.map(o => ({
        ...o,
        items: typeof o.items === 'string' ? JSON.parse(o.items) : (o.items || []),
      }));

      res.json({ success: true, orders: parsed });
    } catch (err) {
      next(err);
    }
  }

  // GET /api/v1/pos/orders/:orderId
  static async getOrder(req, res, next) {
    try {
      const { orderId } = req.params;
      const [oRows] = await pool.execute(
        `SELECT SQL_NO_CACHE o.*, t.name AS table_name FROM orders o
         LEFT JOIN pos_tables t ON t.id = o.table_id
         WHERE o.id = ? AND o.order_type = 'local'`,
        [orderId]
      );
      if (!oRows.length) return res.status(404).json({ success: false, message: 'Order not found' });

      const [iRows] = await pool.execute(
        `SELECT SQL_NO_CACHE oi.*, p.name AS product_name, p.image_url FROM order_items oi
         JOIN products p ON p.id = oi.product_id WHERE oi.order_id = ?`,
        [orderId]
      );
      res.json({ success: true, order: { ...oRows[0], items: iRows } });
    } catch (err) {
      next(err);
    }
  }

  // PUT /api/v1/pos/orders/:orderId/items
  // Replace items for an in-progress (unpaid) order
  static async updateOrderItems(req, res, next) {
    const connection = await pool.getConnection();
    try {
      const { orderId } = req.params;
      const { items } = req.body; // [{productId, quantity, price, notes}]
      if (!items?.length) {
        connection.release();
        return res.status(400).json({ success: false, message: 'items required' });
      }

      const [oRows] = await connection.execute(
        `SELECT SQL_NO_CACHE * FROM orders WHERE id = ? AND order_type = 'local' AND local_paid = 0`, [orderId]
      );
      if (!oRows.length) {
        connection.release();
        return res.status(404).json({ success: false, message: 'Order not found or already paid' });
      }
      const order = oRows[0];

      await connection.beginTransaction();

      // Restore old stock
      const [oldItems] = await connection.execute(
        `SELECT SQL_NO_CACHE product_id, quantity FROM order_items WHERE order_id = ?`, [orderId]
      );
      for (const oi of oldItems) {
        await connection.execute(
          `UPDATE products SET stock = stock + ? WHERE id = ?`,
          [oi.quantity, oi.product_id]
        );
      }

      // Upsert items — UPDATE existing rows in place (keeps their original
      // created_at) and only INSERT rows for genuinely new products. The kitchen
      // screen compares order_items.created_at against orders.kitchen_updated_at
      // to flag which items were added after the kitchen last touched the ticket,
      // so a plain delete-all/insert-all here would wipe that signal.
      const existingProductIds = new Set(oldItems.map(oi => oi.product_id));
      const incomingProductIds = new Set(items.map(it => Number(it.productId)));
      const removedProductIds = [...existingProductIds].filter(id => !incomingProductIds.has(id));
      if (removedProductIds.length) {
        await connection.query(
          `DELETE FROM order_items WHERE order_id = ? AND product_id IN (?)`,
          [orderId, removedProductIds]
        );
      }

      const totalPrice = items.reduce((s, it) => s + (Number(it.price) * Number(it.quantity)), 0);

      for (const item of items) {
        if (existingProductIds.has(Number(item.productId))) {
          await connection.execute(
            `UPDATE order_items SET quantity = ?, price = ?, notes = ? WHERE order_id = ? AND product_id = ?`,
            [item.quantity, item.price, item.notes || null, orderId, item.productId]
          );
        } else {
          await connection.execute(
            `INSERT INTO order_items (order_id, product_id, quantity, price, notes) VALUES (?, ?, ?, ?, ?)`,
            [orderId, item.productId, item.quantity, item.price, item.notes || null]
          );
        }
        await connection.execute(
          `UPDATE products SET stock = GREATEST(stock - ?, 0) WHERE id = ?`,
          [item.quantity, item.productId]
        );
      }

      // Reopen the kitchen ticket if it was already delivered (pay-later order
      // still sitting on the table) — otherwise the newly added items would
      // silently never reach the kitchen screen (it only lists pending/preparing/
      // ready orders). Leave kitchen_updated_at untouched so the new items still
      // read as "added after the kitchen last acted" once it reappears.
      const reopening = order.kitchen_status === 'delivered';
      if (reopening) {
        await connection.execute(`UPDATE orders SET total_price = ?, kitchen_status = 'pending' WHERE id = ?`,
          [totalPrice.toFixed(2), orderId]);
        if (order.table_id) {
          await connection.execute(`UPDATE pos_tables SET status = 'occupied' WHERE id = ?`, [order.table_id]);
        }
      } else {
        await connection.execute(`UPDATE orders SET total_price = ? WHERE id = ?`, [totalPrice.toFixed(2), orderId]);
      }

      await connection.commit();
      connection.release();

      const [iRows] = await pool.execute(
        `SELECT SQL_NO_CACHE oi.*, p.name AS product_name, p.image_url FROM order_items oi
         JOIN products p ON p.id = oi.product_id WHERE oi.order_id = ?`, [orderId]
      );
      const updated = {
        ...order,
        total_price: totalPrice.toFixed(2),
        kitchen_status: reopening ? 'pending' : order.kitchen_status,
        items: iRows,
      };
      emitPOS(order.store_id, 'pos:order_updated', { order: updated, trigger: reopening ? 'kitchen' : undefined });

      if (reopening && order.table_id) {
        const [tRows] = await pool.execute(`SELECT SQL_NO_CACHE * FROM pos_tables WHERE id = ?`, [order.table_id]);
        if (tRows.length) emitPOS(order.store_id, 'pos:table_updated', { action: 'updated', table: tRows[0] });
      }

      res.json({ success: true, order: updated });
    } catch (err) {
      await connection.rollback().catch(() => {});
      connection.release();
      next(err);
    }
  }

  // PUT /api/v1/pos/orders/:orderId/kitchen-status
  // Body: { status: 'preparing'|'ready'|'delivered' }
  static async updateKitchenStatus(req, res, next) {
    try {
      const { orderId } = req.params;
      const { status } = req.body;
      const allowed = ['pending', 'preparing', 'ready', 'delivered'];
      if (!allowed.includes(status)) {
        return res.status(400).json({ success: false, message: `status must be one of: ${allowed.join(', ')}` });
      }

      const [oRows] = await pool.execute(
        `SELECT SQL_NO_CACHE o.*, t.name AS table_name FROM orders o
         LEFT JOIN pos_tables t ON t.id = o.table_id
         WHERE o.id = ? AND o.order_type = 'local'`,
        [orderId]
      );
      if (!oRows.length) return res.status(404).json({ success: false, message: 'Order not found' });
      const order = oRows[0];

      // Update table status when kitchen progresses
      const tableStatus = status === 'preparing' ? 'preparing' : 'available';

      let finalOrderStatus = order.status;
      let finalLocalPaid   = order.local_paid;
      const kitchenUpdatedAt = new Date();

      if (status === 'delivered') {
        // Auto-complete the order only if payment was pre-collected at order time.
        if (order.local_payment_method) {
          // Pre-paid — the customer is done, free the table for the next guest.
          if (order.table_id) {
            await pool.execute(`UPDATE pos_tables SET status = 'available' WHERE id = ?`, [order.table_id]);
          }
          await pool.execute(
            `UPDATE orders SET kitchen_status = 'delivered', kitchen_updated_at = ?, local_paid = 1, status = 'delivered' WHERE id = ?`,
            [kitchenUpdatedAt, orderId]
          );
          finalOrderStatus = 'delivered';
          finalLocalPaid   = 1;
        } else {
          // Pay-later: food is served but the guest is still at the table and may
          // order more — keep it occupied (as "awaiting payment"), don't free it.
          if (order.table_id) {
            await pool.execute(`UPDATE pos_tables SET status = 'waiting_payment' WHERE id = ?`, [order.table_id]);
          }
          await pool.execute(
            `UPDATE orders SET kitchen_status = 'delivered', kitchen_updated_at = ? WHERE id = ?`,
            [kitchenUpdatedAt, orderId]
          );
        }
      } else {
        await pool.execute(`UPDATE orders SET kitchen_status = ?, kitchen_updated_at = ? WHERE id = ?`, [status, kitchenUpdatedAt, orderId]);
        if (order.table_id) {
          await pool.execute(`UPDATE pos_tables SET status = ? WHERE id = ?`, [tableStatus, order.table_id]);
        }
      }

      const [iRows] = await pool.execute(
        `SELECT SQL_NO_CACHE oi.*, p.name AS product_name, p.image_url FROM order_items oi
         JOIN products p ON p.id = oi.product_id WHERE oi.order_id = ?`, [orderId]
      );
      const updated = {
        ...order,
        kitchen_status: status,
        kitchen_updated_at: kitchenUpdatedAt,
        status: finalOrderStatus,
        local_paid: finalLocalPaid,
        items: iRows,
      };
      emitPOS(order.store_id, 'pos:order_updated', { order: updated, trigger: 'kitchen' });

      if (order.table_id) {
        const [tRows] = await pool.execute(`SELECT SQL_NO_CACHE * FROM pos_tables WHERE id = ?`, [order.table_id]);
        if (tRows.length) emitPOS(order.store_id, 'pos:table_updated', { action: 'updated', table: tRows[0] });
      }

      res.json({ success: true, order: updated });
    } catch (err) {
      next(err);
    }
  }

  // PUT /api/v1/pos/orders/:orderId/payment
  // Body: { paymentMethod: 'cash'|'card'|'mixed' }
  static async processPayment(req, res, next) {
    try {
      const { orderId } = req.params;
      const { paymentMethod } = req.body;
      if (!paymentMethod) return res.status(400).json({ success: false, message: 'paymentMethod required' });

      const [oRows] = await pool.execute(
        `SELECT SQL_NO_CACHE * FROM orders WHERE id = ? AND order_type = 'local' AND local_paid = 0`,
        [orderId]
      );
      if (!oRows.length) return res.status(404).json({ success: false, message: 'Order not found or already paid' });
      const order = oRows[0];

      await pool.execute(
        `UPDATE orders SET local_paid = 1, local_payment_method = ?, status = 'delivered' WHERE id = ?`,
        [paymentMethod, orderId]
      );

      // Free the table
      if (order.table_id) {
        await pool.execute(
          `UPDATE pos_tables SET status = 'available' WHERE id = ?`,
          [order.table_id]
        );
        const [tRows] = await pool.execute(`SELECT SQL_NO_CACHE * FROM pos_tables WHERE id = ?`, [order.table_id]);
        if (tRows.length) emitPOS(order.store_id, 'pos:table_updated', { action: 'updated', table: tRows[0] });
      }

      const updated = { ...order, local_paid: 1, local_payment_method: paymentMethod, status: 'delivered' };
      emitPOS(order.store_id, 'pos:order_updated', { order: updated, trigger: 'payment' });
      res.json({ success: true, order: updated });
    } catch (err) {
      next(err);
    }
  }

  // DELETE /api/v1/pos/orders/:orderId
  static async cancelOrder(req, res, next) {
    const connection = await pool.getConnection();
    try {
      const { orderId } = req.params;
      const [oRows] = await connection.execute(
        `SELECT SQL_NO_CACHE * FROM orders WHERE id = ? AND order_type = 'local'`, [orderId]
      );
      if (!oRows.length) {
        connection.release();
        return res.status(404).json({ success: false, message: 'Order not found' });
      }
      const order = oRows[0];

      await connection.beginTransaction();
      // Restore stock
      const [items] = await connection.execute(
        `SELECT SQL_NO_CACHE product_id, quantity FROM order_items WHERE order_id = ?`, [orderId]
      );
      for (const it of items) {
        await connection.execute(`UPDATE products SET stock = stock + ? WHERE id = ?`, [it.quantity, it.product_id]);
      }
      await connection.execute(`UPDATE orders SET status = 'cancelled' WHERE id = ?`, [orderId]);
      // Free table if no other active orders on it
      if (order.table_id) {
        const [otherOrders] = await connection.execute(
          `SELECT SQL_NO_CACHE id FROM orders WHERE table_id = ? AND order_type = 'local'
           AND status NOT IN ('cancelled','completed') AND local_paid = 0 AND id != ?`,
          [order.table_id, orderId]
        );
        if (!otherOrders.length) {
          await connection.execute(`UPDATE pos_tables SET status = 'available' WHERE id = ?`, [order.table_id]);
        }
      }
      await connection.commit();
      connection.release();

      emitPOS(order.store_id, 'pos:order_updated', { order: { ...order, status: 'cancelled' }, trigger: 'cancel' });
      if (order.table_id) {
        const [tRows] = await pool.execute(`SELECT SQL_NO_CACHE * FROM pos_tables WHERE id = ?`, [order.table_id]);
        if (tRows.length) emitPOS(order.store_id, 'pos:table_updated', { action: 'updated', table: tRows[0] });
      }
      res.json({ success: true });
    } catch (err) {
      await connection.rollback().catch(() => {});
      connection.release();
      next(err);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // KITCHEN SCREEN
  // ═══════════════════════════════════════════════════════════════════════════

  // GET /api/v1/pos/kitchen?storeId=X
  static async getKitchenOrders(req, res, next) {
    try {
      const { storeId } = req.query;
      if (!storeId) return res.status(400).json({ success: false, message: 'storeId required' });

      const [orders] = await pool.execute(
        `SELECT SQL_NO_CACHE o.*, t.name AS table_name,
                JSON_ARRAYAGG(JSON_OBJECT(
                  'id', oi.id, 'product_id', oi.product_id,
                  'product_name', p.name, 'image_url', p.image_url,
                  'quantity', oi.quantity, 'price', oi.price, 'notes', oi.notes,
                  'created_at', oi.created_at
                )) AS items
         FROM orders o
         LEFT JOIN pos_tables t ON t.id = o.table_id
         LEFT JOIN order_items oi ON oi.order_id = o.id
         LEFT JOIN products p ON p.id = oi.product_id
         WHERE o.store_id = ? AND o.order_type = 'local'
           AND o.kitchen_status IN ('pending','preparing','ready')
           AND o.status NOT IN ('cancelled','completed')
         GROUP BY o.id
         ORDER BY o.created_at ASC`,
        [storeId]
      );

      const parsed = orders.map(o => ({
        ...o,
        items: typeof o.items === 'string' ? JSON.parse(o.items) : (o.items || []),
      }));
      res.json({ success: true, orders: parsed });
    } catch (err) {
      next(err);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INVOICE DOWNLOAD
  // ═══════════════════════════════════════════════════════════════════════════

  // GET /api/v1/pos/orders/:orderId/invoice
  static async getInvoice(req, res, next) {
    try {
      const { orderId } = req.params;
      const [oRows] = await pool.execute(
        `SELECT SQL_NO_CACHE o.*, t.name AS table_name,
                s.name AS store_name, s.icon_url AS store_icon_url
         FROM orders o
         LEFT JOIN pos_tables t ON t.id = o.table_id
         LEFT JOIN stores s ON s.id = o.store_id
         WHERE o.id = ? AND o.order_type = 'local'`,
        [orderId]
      );
      if (!oRows.length) return res.status(404).json({ success: false, message: 'Order not found' });

      const [iRows] = await pool.execute(
        `SELECT SQL_NO_CACHE oi.*, p.name AS product_name, p.image_url FROM order_items oi
         JOIN products p ON p.id = oi.product_id WHERE oi.order_id = ?`,
        [orderId]
      );
      const row = oRows[0];
      const store = { name: row.store_name, icon_url: row.store_icon_url };
      streamPOSReceiptPDF(res, { order: row, items: iRows, store, tableName: row.table_name });
    } catch (err) {
      next(err);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CUSTOMER TRACKING (public — no auth required)
  // ═══════════════════════════════════════════════════════════════════════════

  // GET /pos/track/:token  (public route, not under /api/v1)
  static async customerTrack(req, res, next) {
    try {
      const { token } = req.params;

      const [tRows] = await pool.execute(
        `SELECT SQL_NO_CACHE t.*, s.name AS store_name, s.icon_url FROM pos_tables t
         JOIN stores s ON s.id = t.store_id
         WHERE t.qr_token = ?`,
        [token]
      );
      if (!tRows.length) {
        return res.send('<html><body style="font-family:sans-serif;text-align:center;padding:40px"><h2>Table not found</h2></body></html>');
      }
      const tableRow = tRows[0];
      const store = { name: tableRow.store_name, icon_url: tableRow.icon_url };

      // Latest active order for this table
      const [oRows] = await pool.execute(
        `SELECT SQL_NO_CACHE o.* FROM orders o
         WHERE o.table_id = ? AND o.order_type = 'local'
           AND o.status NOT IN ('cancelled','completed')
         ORDER BY o.created_at DESC LIMIT 1`,
        [tableRow.id]
      );

      let order = null;
      let items = [];
      if (oRows.length) {
        order = oRows[0];
        const [iRows] = await pool.execute(
          `SELECT SQL_NO_CACHE oi.*, p.name AS product_name FROM order_items oi
           JOIN products p ON p.id = oi.product_id WHERE oi.order_id = ?`,
          [order.id]
        );
        items = iRows;
      }

      const html = renderCustomerTrackingHTML({ store, tableName: tableRow.name, order, items });
      res.setHeader('Content-Type', 'text/html; charset=utf-8');
      res.send(html);
    } catch (err) {
      next(err);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ANALYTICS EXTENSION — local vs online breakdown
  // ═══════════════════════════════════════════════════════════════════════════

  // GET /api/v1/pos/analytics?storeId=X&from=YYYY-MM-DD&to=YYYY-MM-DD
  static async getAnalytics(req, res, next) {
    try {
      const { storeId, from, to } = req.query;
      if (!storeId) return res.status(400).json({ success: false, message: 'storeId required' });

      let dateFilter = '';
      const params = [storeId];
      if (from) { dateFilter += ` AND DATE(created_at) >= ?`; params.push(from); }
      if (to)   { dateFilter += ` AND DATE(created_at) <= ?`; params.push(to); }

      const [rows] = await pool.execute(
        `SELECT SQL_NO_CACHE
           order_type,
           COUNT(*) AS order_count,
           SUM(total_price) AS revenue,
           currency
         FROM orders
         WHERE store_id = ? AND status NOT IN ('cancelled') ${dateFilter}
         GROUP BY order_type, currency`,
        params
      );

      const [topProducts] = await pool.execute(
        `SELECT SQL_NO_CACHE p.id, p.name, p.image_url, SUM(oi.quantity) AS sold_qty,
                SUM(oi.quantity * oi.price) AS revenue, o.order_type
         FROM order_items oi
         JOIN orders o ON o.id = oi.order_id
         JOIN products p ON p.id = oi.product_id
         WHERE o.store_id = ? AND o.status NOT IN ('cancelled') ${dateFilter}
         GROUP BY p.id, o.order_type
         ORDER BY sold_qty DESC
         LIMIT 10`,
        params
      );

      res.json({ success: true, summary: rows, topProducts });
    } catch (err) {
      next(err);
    }
  }
}

export default POSController;
