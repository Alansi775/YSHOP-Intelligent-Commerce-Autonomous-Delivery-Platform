// invoicePdf.js — shared, nicely-laid-out itemized invoice PDF, used by
// both the admin "Sales" screen and the store owner's own settlement
// screen. Embeds real product thumbnails from disk when available.
import fs from 'fs';
import path from 'path';
import PDFDocument from 'pdfkit';
import sharp from 'sharp';

const INK = '#1a1a1a';
const MUTED = '#6b6b70';
const LINE = '#e2e2e5';
const ACCENT = '#3B82F6';
const GREEN = '#16A34A';
const RED = '#DC2626';
const ROW_ALT = '#f7f8fa';

function resolveImagePath(imageUrl) {
  if (!imageUrl) return null;
  const rel = imageUrl.startsWith('/') ? imageUrl.slice(1) : imageUrl;
  const abs = path.join(process.cwd(), rel);
  try {
    if (fs.existsSync(abs) && fs.statSync(abs).isFile()) return abs;
  } catch (_) {}
  return null;
}

// Thumbnails only need to render at ~26pt in the PDF — the same product
// photo often repeats across many order line items (one popular dish sold
// many times), so downscaling + caching by path keeps a busy invoice from
// ballooning to multiple megabytes of full-resolution JPEGs.
const _thumbCache = new Map();
async function getThumbBuffer(absPath) {
  if (_thumbCache.has(absPath)) return _thumbCache.get(absPath);
  try {
    const buf = await sharp(absPath).resize(80, 80, { fit: 'cover' }).jpeg({ quality: 70 }).toBuffer();
    _thumbCache.set(absPath, buf);
    return buf;
  } catch (_) {
    _thumbCache.set(absPath, null);
    return null;
  }
}

function money(v, currency) {
  return `${Number(v ?? 0).toFixed(2)} ${currency}`;
}

function paymentBadge(order) {
  if (order.payment_type === 'local') return 'In-Store';
  if (order.payment_type === 'prepaid') return 'Paid Online';
  if (order.payment_type === 'cod') return 'Pay at Door';
  return '';
}

/**
 * @param {import('express').Response} res
 * @param {{name:string,address:string,phone:string,email:string}} store
 * @param {Date|string} periodStart
 * @param {Date|string} periodEnd
 * @param {string} label
 * @param {{online:object, local:object, net:object}} totals
 * @param {Array} orders  — from groupOrders(), each with items[]
 * @param {string} currency
 */
export async function renderInvoicePDF(res, { store, periodStart, periodEnd, label, totals, orders, currency, forStoreOwner = false }) {
  const filenameSafe = `${(store?.name || 'store').replace(/[^a-z0-9]+/gi, '_')}_${label.replace(/[^a-z0-9]+/gi, '_')}`;
  res.setHeader('Content-Type', 'application/pdf');
  res.setHeader('Content-Disposition', `attachment; filename="invoice_${filenameSafe}.pdf"`);

  const doc = new PDFDocument({ size: 'A4', margin: 0 });
  doc.pipe(res);

  // ── Header band ──────────────────────────────────────────────────────
  const pageW = doc.page.width;
  doc.rect(0, 0, pageW, 96).fill('#111318');
  doc.fillColor('#ffffff').font('Helvetica-Bold').fontSize(20).text('YSHOP', 40, 26);
  doc.font('Helvetica').fontSize(9).fillColor('#9a9aa0').text('Settlement Invoice', 40, 50);

  doc.font('Helvetica-Bold').fontSize(13).fillColor('#ffffff').text(store?.name || 'Store', 40, 0, { width: pageW - 80, align: 'right' });
  const contactLine = [store?.address, store?.phone, store?.email].filter(Boolean).join('  ·  ');
  doc.font('Helvetica').fontSize(8).fillColor('#9a9aa0').text(contactLine, 40, 20, { width: pageW - 80, align: 'right' });
  doc.text(
    `${new Date(periodStart).toLocaleDateString()} – ${new Date(periodEnd).toLocaleDateString()}  ·  ${label}`,
    40, 38, { width: pageW - 80, align: 'right' }
  );

  let y = 120;
  const left = 40, right = pageW - 40, contentW = right - left;

  // ── Summary cards ────────────────────────────────────────────────────
  doc.fillColor(INK).font('Helvetica-Bold').fontSize(11).text('Summary', left, y);
  y += 18;

  const cardW = (contentW - 16) / 2;
  const drawSummaryCard = (x, title, rows, accent) => {
    const h = 20 + rows.length * 15 + 10;
    doc.roundedRect(x, y, cardW, h, 8).fillAndStroke('#ffffff', LINE);
    doc.fillColor(accent).font('Helvetica-Bold').fontSize(10).text(title, x + 12, y + 10);
    let ry = y + 28;
    for (const [k, v] of rows) {
      doc.font('Helvetica').fontSize(9).fillColor(MUTED).text(k, x + 12, ry, { continued: false });
      doc.font('Helvetica-Bold').fontSize(9).fillColor(INK).text(v, x + 12, ry, { width: cardW - 24, align: 'right' });
      ry += 15;
    }
    return h;
  };

  const onlineRows = [
    ['Orders', String(totals.online.order_count)],
    ['Gross charged', money(totals.online.gross_charged, currency)],
    ['Platform share', money(totals.online.platform_share, currency)],
    ['Driver share', money(totals.online.driver_share, currency)],
    ['Store share', money(totals.online.store_share, currency)],
  ];
  const localRows = [
    ['Orders', String(totals.local.order_count)],
    ['Gross charged', money(totals.local.gross_charged, currency)],
    ['Platform share', money(totals.local.platform_share, currency)],
    ['Store share', money(totals.local.store_share, currency)],
  ];
  const h1 = totals.online.order_count > 0 ? drawSummaryCard(left, 'Online (delivery)', onlineRows, ACCENT) : 0;
  const h2 = totals.local.order_count > 0 ? drawSummaryCard(left + cardW + 16, 'In-store / dine-in', localRows, '#0891B2') : 0;
  y += Math.max(h1, h2, 20) + 16;

  // ── Net settlement box ──────────────────────────────────────────────
  const net = totals.net;
  doc.roundedRect(left, y, contentW, 64, 8).fillAndStroke('#f0fdf4', '#bbf7d0');
  const netCol = (x, w, title, value, color) => {
    doc.font('Helvetica').fontSize(8).fillColor(MUTED).text(title, x, y + 12, { width: w, align: 'center' });
    doc.font('Helvetica-Bold').fontSize(13).fillColor(color).text(value, x, y + 28, { width: w, align: 'center' });
  };
  const colW = contentW / 3;
  netCol(left, colW, forStoreOwner ? 'You owe platform' : 'Store owes platform', money(net.store_owes_platform, currency), RED);
  netCol(left + colW, colW, forStoreOwner ? 'Platform owes you' : 'Platform owes store', money(net.platform_owes_store, currency), GREEN);
  netCol(left + colW * 2, colW, 'Platform owes driver', money(net.platform_owes_driver, currency), '#D97706');
  y += 80;

  // ── Itemized orders ──────────────────────────────────────────────────
  doc.font('Helvetica-Bold').fontSize(11).fillColor(INK).text('Orders', left, y);
  y += 18;

  const ensureSpace = (needed) => {
    if (y + needed > doc.page.height - 50) {
      doc.addPage();
      y = 40;
    }
  };

  for (const order of orders) {
    const itemsH = order.items.length * 34;
    ensureSpace(56 + itemsH);

    const cancelled = order.status === 'cancelled';
    doc.roundedRect(left, y, contentW, 30, 6).fill(cancelled ? '#fef2f2' : ROW_ALT);
    doc.font('Helvetica-Bold').fontSize(9.5).fillColor(cancelled ? RED : INK)
      .text(`#${order.order_id}`, left + 10, y + 10);
    const tag = order.order_type === 'local' ? `Table ${order.table_name || '—'}` : paymentBadge(order);
    doc.font('Helvetica').fontSize(8.5).fillColor(MUTED)
      .text(tag, left + 60, y + 10.5);
    doc.text(new Date(order.created_at).toLocaleString(), left + 200, y + 10.5);
    doc.font('Helvetica-Bold').fontSize(8.5).fillColor(cancelled ? RED : (order.order_type === 'local' ? '#0891B2' : ACCENT))
      .text(cancelled ? 'CANCELLED' : order.status.toUpperCase(), left, y + 10.5, { width: contentW - 10, align: 'right' });
    y += 34;

    for (const item of order.items) {
      ensureSpace(34);
      const imgPath = resolveImagePath(item.image_url);
      const thumb = imgPath ? await getThumbBuffer(imgPath) : null;
      if (thumb) {
        try { doc.image(thumb, left + 10, y, { width: 26, height: 26, fit: [26, 26] }); } catch (_) {}
      } else {
        doc.roundedRect(left + 10, y, 26, 26, 4).fillAndStroke('#eef0f3', LINE);
      }
      doc.font('Helvetica').fontSize(9).fillColor(INK)
        .text(`${item.quantity}x ${item.product_name || 'Product'}`, left + 46, y + 7, { width: contentW - 200 });
      doc.font('Helvetica-Bold').fontSize(9).fillColor(INK)
        .text(money(item.price, order.currency), left, y + 7, { width: contentW - 10, align: 'right' });
      y += 30;
    }

    if (!cancelled) {
      doc.font('Helvetica').fontSize(8).fillColor(MUTED).text(
        `Total ${money(order.total_price, order.currency)}   ·   Platform ${money(order.platform_share, order.currency)}` +
        (order.order_type === 'local' ? '' : `   ·   Driver ${money(order.driver_share, order.currency)}`) +
        `   ·   Store ${money(order.store_share, order.currency)}`,
        left + 10, y, { width: contentW - 20 }
      );
      y += 16;
    } else {
      doc.font('Helvetica-Oblique').fontSize(8).fillColor(RED).text('Excluded from totals — no charge occurred', left + 10, y);
      y += 16;
    }
    y += 8;
  }

  doc.end();
}
