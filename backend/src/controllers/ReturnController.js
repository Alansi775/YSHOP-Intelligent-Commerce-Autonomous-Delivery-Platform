import pool from '../config/database.js';
import logger from '../config/logger.js';
import path from 'path';
import fs from 'fs';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

/**
 * Return Management Controller
 * Handles return requests, photo uploads, and return status tracking
 */

class ReturnController {
  /**
   * Submit a return request with photos
   * POST /returns/submit
   */
  static async submitReturn(req, res) {
    let connection;
    try {
      let { order_id, reason } = req.body;
      const userId = req.user?.id || req.user?.uid;

      logger.info('📥 Return submission received', {
        order_id,
        reason: reason?.substring(0, 50),
        userId,
        filesCount: req.files?.length || 0,
        requestHeaders: Object.keys(req.headers),
      });

      // Convert order_id to number if it's a string
      order_id = parseInt(order_id, 10);
      logger.info('🔢 Order ID parsed', { order_id, type: typeof order_id });

      if (!order_id || !reason || !userId) {
        logger.warn('⚠️ Missing validation', { order_id, reason: !!reason, userId });
        return res.status(400).json({
          success: false,
          message: 'Missing required fields: order_id, reason, userId',
        });
      }

      if (req.files?.length < 6) {
        logger.warn('⚠️ Insufficient photos', { photosReceived: req.files?.length || 0, required: 6 });
        return res.status(400).json({
          success: false,
          message: `Only ${req.files?.length || 0} photos provided. 6 required.`,
        });
      }

      logger.info('🔗 Getting database connection...');
      connection = await pool.getConnection();
      logger.info('✓ Database connection acquired');

      // Get order details
      const [orders] = await connection.execute(
        `SELECT * FROM orders WHERE id = ? AND user_id = ?`,
        [order_id, userId]
      );

      logger.info(`✓ Order query executed`, { ordersFound: orders?.length || 0, order_id, userId });

      if (!orders || orders.length === 0) {
        return res.status(404).json({
          success: false,
          message: 'Order not found or you are not authorized to return this order',
        });
      }

      const order = orders[0];

      // Get order items
      const [orderItems] = await connection.execute(
        `SELECT * FROM order_items WHERE order_id = ?`,
        [order_id]
      );

      logger.info(`✓ Order items query executed`, { itemsFound: orderItems?.length || 0 });

      // Get product details
      if (orderItems.length > 0) {
        const [products] = await connection.execute(
          `SELECT * FROM products WHERE id IN (${orderItems.map(() => '?').join(',')})`,
          orderItems.map(item => item.product_id)
        );

        logger.info(`✓ Products query executed`, { productsFound: products?.length || 0 });

        // Get store details
        const [stores] = await connection.execute(
          `SELECT * FROM stores WHERE id = ?`,
          [order.store_id]
        );

        logger.info(`✓ Store query executed`, { storesFound: stores?.length || 0 });

        // Get driver details if available
        let driverData = null;
        if (order.driver_id) {
          const [drivers] = await connection.execute(
            `SELECT * FROM delivery_requests WHERE uid = ?`,
            [order.driver_id]
          );
          driverData = drivers?.[0] || null;
          logger.info(`✓ Driver query executed`, { driverFound: !!driverData });
        }

        const store = stores?.[0] || null;

        // Create returned_products entry for each order item
        for (let i = 0; i < orderItems.length; i++) {
          const orderItem = orderItems[i];
          const product = products.find(p => p.id === orderItem.product_id);

          // Build photo paths - req.files is an array when using upload.array('photos', 6)
          const photoObj = {};
          if (req.files && Array.isArray(req.files)) {
            req.files.forEach((file, index) => {
              // Files uploaded via multipart, store path
              photoObj[`photo_${index}`] = `/uploads/returns/${file.filename}`;
            });
          }

          logger.info(`📸 Return photos uploaded: ${Object.keys(photoObj).length} files`, {
            files: Object.keys(photoObj),
            orderId: order_id,
          });

          logger.info(`🔄 Inserting return product ${i + 1}/${orderItems.length}`, {
            product_id: product?.id,
            orderItem_id: orderItem.id,
          });

          // Insert into returned_products
          const insertResult = await connection.execute(
            `INSERT INTO returned_products (
              order_id, product_id, order_item_id, user_id, store_id, driver_id,
              product_name, product_description, product_price, product_currency, product_image_url,
              store_name, store_phone, store_address, store_icon_url, store_owner_uid,
              driver_name, driver_phone, driver_email, driver_national_id,
              quantity, return_reason,
              photo_top, photo_bottom, photo_left, photo_right, photo_front, photo_back,
              delivered_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
            [
              order_id,
              product.id,
              orderItem.id,
              userId,
              order.store_id,
              order.driver_id || null,
              product.name,
              product.description,
              product.price,
              product.currency || order.currency,
              product.image_url,
              store?.name || null,
              store?.phone || null,
              store?.address || null,
              store?.icon_url || null,
              store?.owner_uid || null,
              driverData?.name || null,
              driverData?.phone || null,
              driverData?.email || null,
              driverData?.national_id || null,
              orderItem.quantity,
              reason,
              photoObj.photo_0 || null,
              photoObj.photo_1 || null,
              photoObj.photo_2 || null,
              photoObj.photo_3 || null,
              photoObj.photo_4 || null,
              photoObj.photo_5 || null,
              order.delivered_at,
            ]
          );

          logger.info(`✓ Return product ${i + 1} inserted`, { affectedRows: insertResult?.[0]?.affectedRows });
        }
      }

      // Update order status to 'return'
      await connection.execute(
        `UPDATE orders SET status = 'return', updated_at = NOW() WHERE id = ?`,
        [order_id]
      );

      logger.info(`✓ Order status updated to 'return'`);

      connection.release();

      logger.info(`✓ Return request submitted for order ${order_id}`);

      return res.status(200).json({
        success: true,
        message: 'Return request submitted successfully',
        orderId: order_id,
      });
    } catch (error) {
      logger.error('❌ Error submitting return request:', {
        message: error.message,
        stack: error.stack,
        files: req.files ? (Array.isArray(req.files) ? req.files.length : Object.keys(req.files)) : 'NO_FILES',
        body: req.body,
      });
      if (connection) connection.release();
      return res.status(500).json({
        success: false,
        message: 'Error submitting return request',
        error: error.message,
      });
    }
  }

  /**
   * Get all returned products (admin only)
   * GET /returns/list
   */
  static async getReturnedProducts(req, res) {
    let connection;
    try {
      const adminRole = req.admin?.role;

      // Check if user is admin or superadmin
      if (!adminRole || !['admin', 'admin_staff', 'superadmin'].includes(adminRole.toLowerCase())) {
        return res.status(403).json({
          success: false,
          message: 'Unauthorized: Admin access required',
        });
      }

      connection = await pool.getConnection();

      const [returns] = await connection.execute(`
        SELECT * FROM returned_products
        ORDER BY return_requested_at DESC
        LIMIT 500
      `);

      connection.release();

      return res.status(200).json({
        success: true,
        data: returns || [],
        count: returns?.length || 0,
      });
    } catch (error) {
      logger.error('❌ Error fetching returned products:', error);
      if (connection) connection.release();
      return res.status(500).json({
        success: false,
        message: 'Error fetching returned products',
        error: error.message,
      });
    }
  }

  /**
   * Get returns by store (for store owners)
   * GET /returns/store/:storeId
   */
  static async getReturnsByStore(req, res) {
    let connection;
    try {
      const { storeId } = req.params;
      const userId = req.user?.uid;

      connection = await pool.getConnection();

      // Verify store ownership
      const [stores] = await connection.execute(
        `SELECT * FROM stores WHERE id = ? AND owner_uid = ?`,
        [storeId, userId]
      );

      if (!stores || stores.length === 0) {
        connection.release();
        return res.status(403).json({
          success: false,
          message: 'Unauthorized: You do not own this store',
        });
      }

      // Get returns for this store
      const [returns] = await connection.execute(
        `SELECT * FROM returned_products WHERE store_id = ? ORDER BY return_requested_at DESC LIMIT 500`,
        [storeId]
      );

      connection.release();

      return res.status(200).json({
        success: true,
        data: returns || [],
        count: returns?.length || 0,
      });
    } catch (error) {
      logger.error('❌ Error fetching store returns:', error);
      if (connection) connection.release();
      return res.status(500).json({
        success: false,
        message: 'Error fetching store returns',
        error: error.message,
      });
    }
  }

  /**
   * Update return status (admin only)
   * PUT /returns/:returnId/approve
   */
  static async approveReturn(req, res) {
    let connection;
    try {
      const { returnId } = req.params;
      const adminRole = req.admin?.role;

      if (!adminRole || !['admin', 'admin_staff', 'superadmin'].includes(adminRole.toLowerCase())) {
        return res.status(403).json({
          success: false,
          message: 'Unauthorized: Admin access required',
        });
      }

      connection = await pool.getConnection();

      // Get return details
      const [returns] = await connection.execute(
        `SELECT * FROM returned_products WHERE id = ?`,
        [returnId]
      );

      if (!returns || returns.length === 0) {
        connection.release();
        return res.status(404).json({
          success: false,
          message: 'Return request not found',
        });
      }

      const returnData = returns[0];

      // Delete from returned_products (request approved, processed)
      await connection.execute(
        `DELETE FROM returned_products WHERE id = ?`,
        [returnId]
      );

      // Order status stays 'return' or can be updated by store
      connection.release();

      logger.info(`✓ Return ${returnId} approved and closed`);

      return res.status(200).json({
        success: true,
        message: 'Return approved and processed',
      });
    } catch (error) {
      logger.error('❌ Error approving return:', error);
      if (connection) connection.release();
      return res.status(500).json({
        success: false,
        message: 'Error approving return',
        error: error.message,
      });
    }
  }

  /**
   * Reject return request (admin only)
   * PUT /returns/:returnId/reject
   */
  static async rejectReturn(req, res) {
    let connection;
    try {
      const { returnId } = req.params;
      const { reason } = req.body;
      const adminRole = req.admin?.role;

      if (!adminRole || !['admin', 'admin_staff', 'superadmin'].includes(adminRole.toLowerCase())) {
        return res.status(403).json({
          success: false,
          message: 'Unauthorized: Admin access required',
        });
      }

      connection = await pool.getConnection();

      // Get return details
      const [returns] = await connection.execute(
        `SELECT * FROM returned_products WHERE id = ?`,
        [returnId]
      );

      if (!returns || returns.length === 0) {
        connection.release();
        return res.status(404).json({
          success: false,
          message: 'Return request not found',
        });
      }

      const returnData = returns[0];

      // Delete from returned_products (return rejected)
      await connection.execute(
        `DELETE FROM returned_products WHERE id = ?`,
        [returnId]
      );

      // Update order status back to 'delivered'
      await connection.execute(
        `UPDATE orders SET status = 'delivered' WHERE id = ?`,
        [returnData.order_id]
      );

      connection.release();

      logger.info(`✓ Return ${returnId} rejected`);

      return res.status(200).json({
        success: true,
        message: 'Return rejected, order status updated to delivered',
      });
    } catch (error) {
      logger.error('❌ Error rejecting return:', error);
      if (connection) connection.release();
      return res.status(500).json({
        success: false,
        message: 'Error rejecting return',
        error: error.message,
      });
    }
  }
}

export default ReturnController;
