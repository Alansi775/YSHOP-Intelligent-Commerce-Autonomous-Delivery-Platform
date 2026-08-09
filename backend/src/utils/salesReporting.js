// salesReporting.js — shared reporting core for the admin "Sales" screen
// and the store owner's own settlement/analytics screen. Single source of
// truth for: which orders count toward a period, how the charged total
// splits into platform/driver/store shares, and — new — which direction
// money actually needs to move for a given order.
//
// Money-flow direction (this is the part that isn't obvious from the
// numbers alone, so it's centralized here instead of re-derived per call
// site):
//
//   • LOCAL / POS orders — the customer paid the store directly (cash or
//     card at the register). The store is holding 100% of the cash, so
//     the store owes the PLATFORM its platform_share. No driver is ever
//     involved. direction = 'store_owes_platform'.
//
//   • ONLINE orders paid up-front (any payment_method other than "Pay at
//     Door", e.g. a card charge) — the money landed in the platform's
//     payment account first, not the store's. The platform is holding
//     100% of the cash, so the PLATFORM owes the store its store_share
//     (and owes the driver their driver_share). direction =
//     'platform_owes_store'.
//
//   • ONLINE orders paid at the door (payment_method = "Pay at Door") —
//     the driver collects cash from the customer on delivery, so the
//     driver ends up holding it, not the store. The driver reconciles
//     that cash with the platform (not with the store), so from the
//     store's point of view the outcome is identical to a prepaid order:
//     the PLATFORM (not the driver) owes the store its share. direction
//     = 'platform_owes_store', same as prepaid — the two online payment
//     types differ only in the payment_type label, not in who owes the
//     store.
//
// Cancelled orders were never actually charged — they're returned in the
// itemized order list (both this store's owner and the admin explicitly
// need to see them, e.g. cancelled dine-in tickets), but excluded from
// every total/share and carry a null split.
import { splitFromCharged } from './pricing.js';

export async function getPeriodStart(connection, storeId) {
  const [[row]] = await connection.execute(
    `SELECT COALESCE(
       (SELECT MAX(period_end) FROM store_settlements WHERE store_id = ? AND status = 'settled'),
       (SELECT created_at FROM stores WHERE id = ?)
     ) AS period_start`,
    [storeId, storeId]
  );
  return row?.period_start || new Date(0);
}

export async function fetchOrderRows(connection, storeId, periodStart, periodEnd) {
  const [rows] = await connection.execute(
    `SELECT
       o.id AS order_id, o.order_type, o.status, o.created_at, o.currency, o.total_price,
       o.payment_method,
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

// 'local' | 'prepaid' | 'cod' — see module doc comment for what each means.
export function paymentTypeOf(row) {
  if (row.order_type === 'local') return 'local';
  return row.payment_method === 'Pay at Door' ? 'cod' : 'prepaid';
}

export function directionOf(paymentType) {
  return paymentType === 'local' ? 'store_owes_platform' : 'platform_owes_store';
}

// Totals exclude cancelled orders (nothing was actually charged), but the
// itemized order list still includes them.
export function computeTotals(rows) {
  let onlineCharged = 0, onlineCount = 0;
  let localCharged = 0, localCount = 0;
  const countedOrders = new Set();

  for (const r of rows) {
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

  const online = {
    order_count: onlineCount,
    gross_charged: Math.round(onlineCharged * 100) / 100,
    platform_share: onlineSplit.platform,
    driver_share: onlineSplit.driver,
    store_share: onlineSplit.base,
  };
  const local = {
    order_count: localCount,
    gross_charged: Math.round(localCharged * 100) / 100,
    platform_share: localSplit.platform,
    store_share: localSplit.base,
  };

  return {
    online,
    local,
    // The four numbers that actually answer "who owes whom, and how much":
    net: {
      // Store hands this to the platform — only ever from local/POS cash.
      store_owes_platform: local.platform_share,
      // Platform hands this to the store — from online orders, since the
      // platform (not the store) held that cash first, regardless of
      // whether the customer paid up-front or at the door.
      platform_owes_store: online.store_share,
      // Platform hands this to drivers — informational for the store
      // owner, but the admin needs it to actually pay drivers out.
      platform_owes_driver: online.driver_share,
      // The platform's own earned revenue (never owed to/from anyone).
      platform_keeps: Math.round((local.platform_share + online.platform_share) * 100) / 100,
    },
  };
}

export function groupOrders(rows) {
  const byOrder = new Map();
  for (const r of rows) {
    if (!byOrder.has(r.order_id)) {
      const isLocal = r.order_type === 'local';
      const paymentType = paymentTypeOf(r);
      // Cancelled orders were never actually charged — no real split to show.
      const split = r.status === 'cancelled'
        ? null
        : splitFromCharged(Number(r.total_price), { isLocal });
      byOrder.set(r.order_id, {
        order_id: r.order_id,
        order_type: r.order_type,
        payment_type: paymentType, // 'local' | 'prepaid' | 'cod'
        direction: r.status === 'cancelled' ? null : directionOf(paymentType),
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

// Reconstructs the same `net` shape from a saved store_settlements row —
// the row already stores the four component shares, so no recomputation
// is needed for historical periods.
export function netFromSettlementRow(settlement) {
  const localPlatform = Number(settlement.local_platform_share || 0);
  const onlinePlatform = Number(settlement.online_platform_share || 0);
  const onlineStore = Number(settlement.online_store_share || 0);
  const onlineDriver = Number(settlement.online_driver_share || 0);
  return {
    store_owes_platform: localPlatform,
    platform_owes_store: onlineStore,
    platform_owes_driver: onlineDriver,
    platform_keeps: Math.round((localPlatform + onlinePlatform) * 100) / 100,
  };
}
