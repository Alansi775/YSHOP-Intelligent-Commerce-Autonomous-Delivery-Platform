import pool from '../config/database.js';

export class Complaint {
  static async create({ orderId, customerId, driverId, storeId, complaintType, subType, description, photos }) {
    const deadline = new Date(Date.now() + 30 * 60 * 1000);
    const [result] = await pool.execute(
      `INSERT INTO order_complaints
         (order_id, customer_id, driver_id, store_id, complaint_type, sub_type, description, photos, status, deadline_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'PENDING', ?)`,
      [orderId, customerId, driverId || null, storeId || null, complaintType, subType || null,
       description || null, photos ? JSON.stringify(photos) : null, deadline]
    );
    return result.insertId;
  }

  static async findById(id) {
    const [rows] = await pool.execute(
      `SELECT
         oc.*,
         o.total_price, o.payment_method, o.currency, o.shipping_address,
         u.display_name  AS customer_name,
         u.email         AS customer_email,
         u.phone         AS customer_phone,
         u.address       AS customer_address,
         s.name          AS store_name,
         s.email         AS store_email,
         s.phone         AS store_phone,
         s.address       AS store_address,
         s.icon_url      AS store_icon_url,
         dr.name         AS driver_name,
         dr.email        AS driver_email,
         dr.phone        AS driver_phone
       FROM order_complaints oc
       LEFT JOIN orders        o  ON oc.order_id    = o.id
       LEFT JOIN users         u  ON oc.customer_id = u.uid
       LEFT JOIN stores        s  ON oc.store_id    = s.id
       LEFT JOIN delivery_requests dr ON oc.driver_id COLLATE utf8mb4_unicode_ci = dr.uid COLLATE utf8mb4_unicode_ci
       WHERE oc.id = ?`,
      [id]
    );
    if (!rows[0]) return null;

    const [items] = await pool.execute(
      `SELECT oi.product_id, oi.quantity, oi.price,
              p.name AS product_name, p.description AS product_description,
              p.image_url AS product_image
       FROM order_items oi
       LEFT JOIN products p ON oi.product_id = p.id
       WHERE oi.order_id = ?`,
      [rows[0].order_id]
    );

    return { ...rows[0], order_items: items };
  }

  static async findByCustomer(customerId, { page = 1, limit = 20 } = {}) {
    const offset = (page - 1) * limit;
    const [rows] = await pool.execute(
      `SELECT oc.*, s.name AS store_name, s.icon_url AS store_icon_url
       FROM order_complaints oc
       LEFT JOIN stores s ON oc.store_id = s.id
       WHERE oc.customer_id = ?
       ORDER BY oc.created_at DESC LIMIT ${parseInt(limit)} OFFSET ${parseInt(offset)}`,
      [customerId]
    );
    return rows;
  }

  static async findAll({ page = 1, limit = 50, status } = {}) {
    const offset = (page - 1) * limit;
    let sql = `SELECT
                 oc.*,
                 o.total_price, o.payment_method,
                 u.display_name AS customer_name,
                 s.name         AS store_name,
                 dr.name        AS driver_name
               FROM order_complaints oc
               LEFT JOIN orders o ON oc.order_id = o.id
               LEFT JOIN users  u ON oc.customer_id = u.uid
               LEFT JOIN stores s ON oc.store_id   = s.id
               LEFT JOIN delivery_requests dr ON oc.driver_id COLLATE utf8mb4_unicode_ci = dr.uid COLLATE utf8mb4_unicode_ci`;
    const params = [];
    if (status) { sql += ` WHERE oc.status = ?`; params.push(status); }
    sql += ` ORDER BY oc.created_at DESC LIMIT ${parseInt(limit)} OFFSET ${parseInt(offset)}`;
    const [rows] = await pool.execute(sql, params);
    return rows;
  }

  static async findByStore(storeId, { page = 1, limit = 50 } = {}) {
    const offset = (page - 1) * limit;
    const [rows] = await pool.execute(
      `SELECT
         oc.id, oc.order_id, oc.complaint_type, oc.sub_type, oc.description,
         oc.status, oc.admin_notes, oc.responsible_party, oc.created_at,
         u.display_name AS customer_name,
         o.total_price, o.currency
       FROM order_complaints oc
       LEFT JOIN orders o ON oc.order_id = o.id
       LEFT JOIN users  u ON oc.customer_id = u.uid
       WHERE oc.store_id = ?
         AND (oc.responsible_party LIKE '%store%' OR oc.status IN ('PENDING','UNDER_REVIEW'))
       ORDER BY oc.created_at DESC LIMIT ${parseInt(limit)} OFFSET ${parseInt(offset)}`,
      [storeId]
    );

    // For each complaint, fetch order items
    const enriched = await Promise.all(rows.map(async (c) => {
      const [items] = await pool.execute(
        `SELECT oi.quantity, oi.price,
                p.name AS product_name, p.description AS product_description,
                p.image_url AS product_image
         FROM order_items oi
         LEFT JOIN products p ON oi.product_id = p.id
         WHERE oi.order_id = ?`,
        [c.order_id]
      );
      return { ...c, order_items: items };
    }));

    return enriched;
  }

  static async findByDriver(driverId, { page = 1, limit = 50 } = {}) {
    const offset = (page - 1) * limit;
    const [rows] = await pool.execute(
      `SELECT
         oc.id, oc.order_id, oc.complaint_type, oc.sub_type, oc.description,
         oc.status, oc.admin_notes, oc.responsible_party, oc.created_at,
         u.display_name AS customer_name,
         o.total_price, o.currency,
         s.name AS store_name
       FROM order_complaints oc
       LEFT JOIN orders o ON oc.order_id = o.id
       LEFT JOIN users  u ON oc.customer_id = u.uid
       LEFT JOIN stores s ON oc.store_id = s.id
       WHERE oc.driver_id COLLATE utf8mb4_unicode_ci = ? COLLATE utf8mb4_unicode_ci
         AND (oc.responsible_party LIKE '%driver%' OR oc.status IN ('PENDING','UNDER_REVIEW'))
       ORDER BY oc.created_at DESC LIMIT ${parseInt(limit)} OFFSET ${parseInt(offset)}`,
      [driverId]
    );
    return rows;
  }

  static async updateStatus(id, status, adminNotes, resolutionType, responsibleParty) {
    await pool.execute(
      `UPDATE order_complaints
       SET status           = ?,
           admin_notes      = COALESCE(?, admin_notes),
           resolution_type  = COALESCE(?, resolution_type),
           responsible_party = COALESCE(?, responsible_party)
       WHERE id = ?`,
      [status, adminNotes || null, resolutionType || null, responsibleParty || null, id]
    );
  }
}

export default Complaint;
