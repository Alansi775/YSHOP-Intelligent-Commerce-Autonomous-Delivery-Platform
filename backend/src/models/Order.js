// models/Order.js
// ═══════════════════════════════════════════════════════════════════════════════
//  ORDER MODEL - Complete with Delivery Assignment System
// ═══════════════════════════════════════════════════════════════════════════════

import pool from '../config/database.js';
import logger from '../config/logger.js';

// ═══════════════════════════════════════════════════════════════════════════
// UTILITY FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════════

function _safeParseJSON(value) {
  if (!value) return null;
  if (typeof value === 'object') return value;
  if (typeof value === 'string') {
    try {
      return JSON.parse(value);
    } catch (e) {
      logger.warn(`Failed to parse JSON: "${value}"`);
      return null;
    }
  }
  return null;
}

export class Order {
  
  // ═══════════════════════════════════════════════════════════════════════════
  // 📝 CREATE ORDER
  // ═══════════════════════════════════════════════════════════════════════════

  static async create(orderData) {
    const connection = await pool.getConnection();
    try {
      const {
        userId, storeId, totalPrice, status, shippingAddress,
        paymentMethod, deliveryOption, currency, items,
      } = orderData;

      await connection.beginTransaction();

      // Get currency from products if not provided, default to USD
      let finalCurrency = currency || 'USD';
      if (!currency) {
        try {
          const [currencyRows] = await connection.execute(
            `SELECT COALESCE(p.currency, 'USD') as currency
             FROM products p
             WHERE p.store_id = ?
             LIMIT 1`,
            [storeId]
          );
          if (currencyRows.length > 0) {
            finalCurrency = currencyRows[0].currency || 'USD';
          }
        } catch (e) {
          logger.warn('Could not fetch currency from products, using USD');
          finalCurrency = 'USD';
        }
      }

      const [result] = await connection.execute(
        `INSERT INTO orders 
         (user_id, store_id, total_price, currency, status, shipping_address, payment_method, delivery_option, created_at) 
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, NOW())`,
        [userId, storeId, totalPrice, finalCurrency, status || 'pending', shippingAddress, paymentMethod || null, deliveryOption || null]
      );

      const orderId = result.insertId;

      if (items && items.length > 0) {
        for (const item of items) {
          await connection.execute(
            `INSERT INTO order_items (order_id, product_id, quantity, price) VALUES (?, ?, ?, ?)`,
            [orderId, item.productId, item.quantity, item.price]
          );

          await connection.execute(
            `UPDATE products SET stock = GREATEST(stock - ?, 0) WHERE id = ?`,
            [item.quantity, item.productId]
          );
        }
      }

      await connection.commit();
      connection.release();

      return {
        id: orderId,
        user_id: userId,
        store_id: storeId,
        total_price: totalPrice,
        currency: finalCurrency,
        status: status || 'pending',
        shipping_address: shippingAddress,
        payment_method: paymentMethod,
        delivery_option: deliveryOption,
        created_at: new Date().toISOString(),
        items: items || [],
      };
    } catch (err) {
      try { await connection.rollback(); } catch (e) {}
      connection.release();
      throw err;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  FIND ORDERS
  // ═══════════════════════════════════════════════════════════════════════════

  static async findRecent(limit = 50) {
    const l = Number.parseInt(limit, 10) || 50;
    const connection = await pool.getConnection();
    try {
      const sql = `
        SELECT SQL_NO_CACHE o.id, o.user_id, o.store_id, o.total_price, o.currency, o.status, o.shipping_address,
          o.payment_method, o.delivery_option, o.driver_location, o.driver_id,
          DATE_FORMAT(o.created_at, '%Y-%m-%d %H:%i:%s') as created_at,
          s.name as store_name,
          dr.name as driver_name,
          dr.phone as driver_phone,
          dr.latitude as driver_latitude,
          dr.longitude as driver_longitude
        FROM orders o
        LEFT JOIN stores s ON o.store_id = s.id
        LEFT JOIN delivery_requests dr ON o.driver_id = CAST(dr.uid AS CHAR) COLLATE utf8mb4_unicode_ci
        ORDER BY o.created_at DESC
        LIMIT ${l}`;

      const [rows] = await connection.execute(sql);
      connection.release();
      return rows;
    } catch (error) {
      connection.release();
      throw error;
    }
  }

  static async findById(id) {
    const connection = await pool.getConnection();
    try {
      const [rows] = await connection.execute(
        `SELECT SQL_NO_CACHE
          o.*,
          DATE_FORMAT(o.created_at, '%Y-%m-%d %H:%i:%s') as created_at_str,
          DATE_FORMAT(o.updated_at, '%Y-%m-%d %H:%i:%s') as updated_at_str,
          s.name as store_name,
          s.latitude as store_latitude,
          s.longitude as store_longitude,
          s.phone as store_phone,
          s.address as store_address,
          u.display_name as customer_name,
          u.phone as customer_phone,
          u.address as customer_address,
          u.latitude as customer_latitude,
          u.longitude as customer_longitude,
          u.delivery_instructions as customer_delivery_instructions,
          u.building_info as customer_building_info,
          u.apartment_number as customer_apartment_number,
          u.email as customer_email
        FROM orders o
        LEFT JOIN stores s ON o.store_id = s.id
        LEFT JOIN users u ON o.user_id = u.uid
        WHERE o.id = ?`,
        [id]
      );

      connection.release();

      if (rows.length === 0) return null;

      const r = rows[0];
      
      // Get items separately
      const conn2 = await pool.getConnection();
      const [itemRows] = await conn2.execute(
        `SELECT oi.*, p.name as product_name, p.image_url
         FROM order_items oi
         LEFT JOIN products p ON oi.product_id = p.id
         WHERE oi.order_id = ?`,
        [id]
      );
      conn2.release();

      const items = itemRows.map(item => ({
        id: item.id,
        product_id: item.product_id,
        quantity: item.quantity,
        price: item.price,
        name: item.product_name,
        imageUrl: item.image_url,
        storeName: r.store_name,
      }));

      return {
        id: r.id,
        documentId: r.id.toString(),
        user_id: r.user_id,
        store_id: r.store_id,
        total_price: r.total_price,
        total: r.total_price,
        status: _mapStatus(r.status),
        shipping_address: r.shipping_address,
        address_Full: r.shipping_address,
        payment_method: r.payment_method,
        delivery_option: r.delivery_option,
        created_at: r.created_at_str,
        
        driver_id: r.driver_id,
        driverId: r.driver_id,
        driver_location: _safeParseJSON(r.driver_location),
        
        current_offer_driver_id: r.current_offer_driver_id,
        offer_expires_at: r.offer_expires_at,
        skipped_driver_ids: r.skipped_driver_ids,
        picked_up_at: r.picked_up_at,
        delivered_at: r.delivered_at,

        store_name: r.store_name,
        storeName: r.store_name,
        store_latitude: r.store_latitude,
        storeLatitude: r.store_latitude,
        store_longitude: r.store_longitude,
        storeLongitude: r.store_longitude,
        store_phone: r.store_phone,
        storePhone: r.store_phone,

        customer: {
          name: r.customer_name,
          email: r.customer_email,
          phone: r.customer_phone,
          address: r.customer_address,
          latitude: r.customer_latitude,
          longitude: r.customer_longitude,
          building_info: r.customer_building_info,
          apartment_number: r.customer_apartment_number,
          delivery_instructions: r.customer_delivery_instructions,
        },
        customerName: r.customer_name,
        customerPhone: r.customer_phone,
        
        location_Latitude: r.customer_latitude,
        location_Longitude: r.customer_longitude,
        building_info: r.customer_building_info,
        apartment_number: r.customer_apartment_number,
        delivery_instructions: r.customer_delivery_instructions,

        items,
      };
    } catch (error) {
      connection.release();
      throw error;
    }
  }

  static async findByUserId(userId, page = 1, limit = 20) {
    const l = Number.parseInt(limit, 10) || 20;
    const p = Number.parseInt(page, 10) || 1;
    const offset = (p - 1) * l;
    const connection = await pool.getConnection();

    try {
      // First get the orders for pagination with all necessary fields
      const sql = `
        SELECT SQL_NO_CACHE 
          o.*, 
          s.name as store_name,
          s.latitude as store_latitude,
          s.longitude as store_longitude,
          s.phone as store_phone,
          u.display_name as customer_name,
          u.phone as customer_phone,
          u.address as customer_address,
          u.latitude as customer_latitude,
          u.longitude as customer_longitude
        FROM orders o 
        LEFT JOIN stores s ON o.store_id = s.id
        LEFT JOIN users u ON o.user_id = u.uid
        WHERE o.user_id = ? 
        ORDER BY o.created_at DESC 
        LIMIT ${l} OFFSET ${offset}`;

      const [rows] = await connection.execute(sql, [userId]);
      
      // For each order, fetch its items and process data
      for (const order of rows) {
        // Process driver_location safely
        order.driver_location = _safeParseJSON(order.driver_location);
        
        // Map customer location
        order.location_Latitude = order.customer_latitude;
        order.location_Longitude = order.customer_longitude;
        
        const itemsSql = `
          SELECT oi.id, oi.order_id, oi.product_id, oi.quantity, oi.price,
                 p.name, p.description, p.image_url as imageUrl, p.category_id
          FROM order_items oi
          LEFT JOIN products p ON oi.product_id = p.id
          WHERE oi.order_id = ?`;
        
        const [items] = await connection.execute(itemsSql, [order.id]);
        order.items = items || [];
      }
      
      connection.release();
      return rows;
    } catch (error) {
      connection.release();
      throw error;
    }
  }

  static async findByStoreId(storeId, page = 1, limit = 50) {
    const l = Number.parseInt(limit, 10) || 50;
    const p = Number.parseInt(page, 10) || 1;
    const offset = (p - 1) * l;
    const connection = await pool.getConnection();

    try {
      const sql = `
        SELECT SQL_NO_CACHE
          o.id, o.user_id, o.store_id, o.total_price, o.status, o.shipping_address,
          o.payment_method, o.delivery_option, o.driver_id,
          DATE_FORMAT(o.created_at, '%Y-%m-%d %H:%i:%s') as created_at,
          o.driver_location,
          u.display_name as customerName,
          u.phone as customerPhone,
          u.address as customerAddress,
          dr.name as driver_name,
          dr.phone as driver_phone,
          dr.latitude as driver_latitude,
          dr.longitude as driver_longitude
        FROM orders o
        LEFT JOIN users u ON o.user_id = u.uid COLLATE utf8mb4_unicode_ci
        LEFT JOIN delivery_requests dr ON o.driver_id = CAST(dr.uid AS CHAR) COLLATE utf8mb4_unicode_ci
        WHERE o.store_id = ?
        ORDER BY o.created_at DESC
        LIMIT ${l} OFFSET ${offset}`;

      const [orders] = await connection.execute(sql, [storeId]);

      if (orders.length > 0) {
        const orderIds = orders.map(o => o.id);
        const placeholders = orderIds.map(() => '?').join(',');

        const [allItems] = await connection.execute(
          `SELECT oi.*, p.name as product_name, p.image_url
           FROM order_items oi
           LEFT JOIN products p ON oi.product_id = p.id
           WHERE oi.order_id IN (${placeholders})`,
          orderIds
        );

        const itemsByOrder = {};
        for (const item of allItems) {
          if (!itemsByOrder[item.order_id]) itemsByOrder[item.order_id] = [];
          itemsByOrder[item.order_id].push(item);
        }

        for (const order of orders) {
          order.items = itemsByOrder[order.id] || [];
        }
      }

      connection.release();
      return orders;
    } catch (error) {
      connection.release();
      throw error;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🎁 ORDER OFFER SYSTEM
  // ═══════════════════════════════════════════════════════════════════════════

  static async findPendingForAssignment() {
    const connection = await pool.getConnection();
    try {
      const sql = `
        SELECT 
          o.id, o.user_id, o.store_id, o.total_price, o.currency, o.status,
          o.shipping_address, o.delivery_option, o.driver_id,
          o.current_offer_driver_id, o.offer_expires_at, o.skipped_driver_ids,
          s.name as store_name,
          s.latitude as store_latitude,
          s.longitude as store_longitude,
          s.phone as store_phone,
          u.latitude as customer_latitude,
          u.longitude as customer_longitude,
          u.address as customer_address
        FROM orders o
        LEFT JOIN stores s ON o.store_id = s.id
        LEFT JOIN users u ON o.user_id = u.uid
        WHERE o.status = 'confirmed'
          AND (o.delivery_option = 'Standard' OR o.delivery_option IS NULL)
          AND (o.driver_id IS NULL OR o.driver_id = '')
        ORDER BY o.created_at ASC`;

      const [rows] = await connection.execute(sql);
      connection.release();
      return rows;
    } catch (error) {
      connection.release();
      throw error;
    }
  }

  static async setOffer(orderId, driverId, expiresAt) {
    const connection = await pool.getConnection();
    try {
      await connection.execute(
        `UPDATE orders 
         SET current_offer_driver_id = ?, offer_expires_at = ?, updated_at = NOW()
         WHERE id = ?`,
        [driverId, expiresAt, orderId]
      );
      connection.release();
      return true;
    } catch (error) {
      connection.release();
      throw error;
    }
  }

  static async clearOffer(orderId) {
    const connection = await pool.getConnection();
    try {
      await connection.execute(
        `UPDATE orders 
         SET current_offer_driver_id = NULL, offer_expires_at = NULL, updated_at = NOW()
         WHERE id = ?`,
        [orderId]
      );
      connection.release();
      return true;
    } catch (error) {
      connection.release();
      throw error;
    }
  }

  static async addSkippedDriver(orderId, driverId) {
    const connection = await pool.getConnection();
    try {
      const [rows] = await connection.execute(
        'SELECT skipped_driver_ids FROM orders WHERE id = ?',
        [orderId]
      );

      let skippedIds = [];
      if (rows.length > 0 && rows[0].skipped_driver_ids) {
        try {
          const raw = rows[0].skipped_driver_ids;
          skippedIds = Array.isArray(raw) ? raw : JSON.parse(raw);
        } catch (e) {
          skippedIds = [];
        }
      }

      if (!skippedIds.includes(driverId)) {
        skippedIds.push(driverId);
      }

      await connection.execute(
        `UPDATE orders 
         SET skipped_driver_ids = ?,
             current_offer_driver_id = NULL,
             offer_expires_at = NULL,
             updated_at = NOW()
         WHERE id = ?`,
        [JSON.stringify(skippedIds), orderId]
      );

      connection.release();
      return true;
    } catch (error) {
      connection.release();
      throw error;
    }
  }

  /**
   * Reset skipped drivers list (when all drivers have skipped)
   */
  static async resetSkippedDrivers(orderId) {
    const connection = await pool.getConnection();
    try {
      await connection.execute(
        `UPDATE orders 
         SET skipped_driver_ids = NULL, updated_at = NOW()
         WHERE id = ?`,
        [orderId]
      );
      connection.release();
      logger.info(`Reset skipped drivers for order ${orderId}`);
      return true;
    } catch (error) {
      connection.release();
      throw error;
    }
  }

  static async findActiveByDriverId(driverId) {
    const connection = await pool.getConnection();
    try {
      const [rows] = await connection.execute(
        `SELECT o.*, s.name as store_name,
           s.latitude as store_latitude, s.longitude as store_longitude,
           s.phone as store_phone,
           u.display_name as customer_name, u.phone as customer_phone,
           u.latitude as customer_latitude, u.longitude as customer_longitude,
           u.address as customer_address, u.delivery_instructions,
           u.building_info, u.apartment_number,
           COALESCE(o.currency, 'USD') as currency
         FROM orders o
         LEFT JOIN stores s ON o.store_id = s.id
         LEFT JOIN users u ON o.user_id = u.uid
         WHERE o.driver_id = ?
           AND o.status IN ('confirmed', 'shipped')
         ORDER BY o.updated_at DESC
         LIMIT 1`,
        [driverId]
      );

      connection.release();

      if (rows.length === 0) return null;

      const r = rows[0];
      return {
        id: r.id,
        user_id: r.user_id,
        store_id: r.store_id,
        total_price: r.total_price,
        total: r.total_price,
        currency: r.currency || 'USD',
        status: _mapStatus(r.status),
        shipping_address: r.shipping_address,
        delivery_option: r.delivery_option,
        driver_id: r.driver_id,
        store_name: r.store_name,
        storeName: r.store_name,
        store_latitude: r.store_latitude,
        storeLatitude: r.store_latitude,
        store_longitude: r.store_longitude,
        storeLongitude: r.store_longitude,
        store_phone: r.store_phone,
        storePhone: r.store_phone,
        customer: {
          name: r.customer_name,
          phone: r.customer_phone,
          latitude: r.customer_latitude,
          longitude: r.customer_longitude,
          address: r.customer_address,
          delivery_instructions: r.delivery_instructions,
          building_info: r.building_info,
          apartment_number: r.apartment_number,
        },
        customerName: r.customer_name,
        customerPhone: r.customer_phone,
        location_Latitude: r.customer_latitude,
        location_Longitude: r.customer_longitude,
        addressFull: r.customer_address,
        address_Full: r.customer_address,
      };
    } catch (error) {
      connection.release();
      throw error;
    }
  }

  static async findNearby(latitude, longitude, radiusMeters = 5000, limit = 10) {
    const connection = await pool.getConnection();
    try {
      const l = Number(limit) || 10;
      const sql = `
        SELECT o.id, o.user_id, o.store_id, o.total_price, COALESCE(o.currency, 'USD') as currency, o.status, o.shipping_address,
          o.delivery_option, 
          u.latitude as customer_latitude, u.longitude as customer_longitude,
          s.name as store_name, s.latitude as store_latitude, s.longitude as store_longitude,
          (6371000 * ACOS(
            COS(RADIANS(?)) * COS(RADIANS(s.latitude)) * COS(RADIANS(s.longitude) - RADIANS(?))
            + SIN(RADIANS(?)) * SIN(RADIANS(s.latitude))
          )) AS distance
        FROM orders o
        LEFT JOIN users u ON o.user_id = u.uid
        LEFT JOIN stores s ON o.store_id = s.id
        WHERE o.status = 'confirmed' 
          AND (o.delivery_option = 'Standard' OR o.delivery_option IS NULL)
          AND (o.driver_id IS NULL OR o.driver_id = '')
          AND s.latitude IS NOT NULL
          AND s.longitude IS NOT NULL
        HAVING distance <= ?
        ORDER BY distance ASC
        LIMIT ${l}`;

      const [rows] = await connection.execute(sql, [latitude, longitude, latitude, radiusMeters]);
      connection.release();
      return rows;
    } catch (error) {
      connection.release();
      throw error;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 📝 UPDATE OPERATIONS
  // ═══════════════════════════════════════════════════════════════════════════

  static async updateStatus(orderId, status) {
    const connection = await pool.getConnection();
    try {
      await connection.execute(
        'UPDATE orders SET status = ?, updated_at = NOW() WHERE id = ?', 
        [status, orderId]
      );
      connection.release();
      return true;
    } catch (error) {
      connection.release();
      throw error;
    }
  }

  static async updateDriverLocation(orderId, latitude, longitude) {
    const connection = await pool.getConnection();
    try {
      const location = JSON.stringify({ latitude, longitude });
      await connection.execute(
        'UPDATE orders SET driver_location = ?, updated_at = NOW() WHERE id = ?',
        [location, orderId]
      );
      connection.release();
      return true;
    } catch (error) {
      connection.release();
      throw error;
    }
  }

  static async assignToDriver(orderId, driverUid) {
    const connection = await pool.getConnection();
    try {
      const [res] = await connection.execute(
        `UPDATE orders 
         SET driver_id = ?, 
             status = 'confirmed',
             current_offer_driver_id = NULL,
             offer_expires_at = NULL,
             updated_at = NOW() 
         WHERE id = ? 
           AND (driver_id IS NULL OR driver_id = '') 
           AND status = 'confirmed'`,
        [driverUid, orderId]
      );
      connection.release();
      return res?.affectedRows > 0;
    } catch (error) {
      connection.release();
      throw error;
    }
  }

  static async setPickedUpAt(orderId) {
    const connection = await pool.getConnection();
    try {
      await connection.execute(
        'UPDATE orders SET picked_up_at = NOW(), updated_at = NOW() WHERE id = ?',
        [orderId]
      );
      connection.release();
      return true;
    } catch (error) {
      connection.release();
      throw error;
    }
  }

  static async setDeliveredAt(orderId) {
    const connection = await pool.getConnection();
    try {
      await connection.execute(
        'UPDATE orders SET delivered_at = NOW(), updated_at = NOW() WHERE id = ?',
        [orderId]
      );
      connection.release();
      return true;
    } catch (error) {
      connection.release();
      throw error;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  DRIVER HISTORY
  // ═══════════════════════════════════════════════════════════════════════════

  static async findCompletedByDriverId(driverId, options = {}) {
    const { month, year, page = 1, limit = 50 } = options;
    const l = Number.parseInt(limit, 10) || 50;
    const p = Number.parseInt(page, 10) || 1;
    const offset = (p - 1) * l;
    
    const connection = await pool.getConnection();
    try {
      let dateFilter = '';
      const params = [driverId];

      if (month && year) {
        dateFilter = 'AND MONTH(o.delivered_at) = ? AND YEAR(o.delivered_at) = ?';
        params.push(month, year);
      } else if (year) {
        dateFilter = 'AND YEAR(o.delivered_at) = ?';
        params.push(year);
      }

      const sql = `
        SELECT 
          o.id, o.store_id, o.total_price, o.status, o.shipping_address,
          DATE_FORMAT(o.delivered_at, '%Y-%m-%d %H:%i:%s') as delivered_at,
          DATE_FORMAT(o.created_at, '%Y-%m-%d %H:%i:%s') as created_at,
          s.name as store_name,
          u.display_name as customer_name
        FROM orders o
        LEFT JOIN stores s ON o.store_id = s.id
        LEFT JOIN users u ON o.user_id = u.uid
        WHERE o.driver_id = ?
          AND o.status = 'delivered'
          ${dateFilter}
        ORDER BY o.delivered_at DESC
        LIMIT ${l} OFFSET ${offset}`;

      const [rows] = await connection.execute(sql, params);

      const countSql = `
        SELECT COUNT(*) as total
        FROM orders o
        WHERE o.driver_id = ? AND o.status = 'delivered' ${dateFilter}`;

      const [countRows] = await connection.execute(countSql, params);
      const total = countRows[0]?.total || 0;

      connection.release();

      return {
        orders: rows,
        pagination: { page: p, limit: l, total, totalPages: Math.ceil(total / l) },
      };
    } catch (error) {
      connection.release();
      throw error;
    }
  }
}

function _mapStatus(status) {
  const statusMap = {
    'pending': 'Pending',
    'confirmed': 'Processing',
    'shipped': 'Out for Delivery',
    'delivered': 'Delivered',
    'cancelled': 'Cancelled',
  };
  return statusMap[status] || status;
}

export default Order;