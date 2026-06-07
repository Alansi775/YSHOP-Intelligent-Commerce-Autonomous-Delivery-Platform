// controllers/DeliveryController.js
// ═══════════════════════════════════════════════════════════════════════════════
// 🚚 DELIVERY CONTROLLER - Smart Order Assignment System
// ═══════════════════════════════════════════════════════════════════════════════

import DeliveryRequest from '../models/DeliveryRequest.js';
import Order from '../models/Order.js';
import logger from '../config/logger.js';
import { getIO } from '../utils/socketInstance.js';
import pool from '../config/database.js';
import admin from '../config/firebase.js';
import { getEmailService, renderDeliveryConfirmationHTML } from '../utils/emailService.js';

// ─────────────────────────────────────────────────────────────────────────────
//  CONFIGURATION
// ─────────────────────────────────────────────────────────────────────────────

const CONFIG = {
  OFFER_TIMEOUT_SECONDS: 120,        // 2 minutes to accept/skip
  MAX_SEARCH_RADIUS_METERS: 10000,   // 10km max search radius
  DEFAULT_SEARCH_RADIUS: 5000,       // 5km default
  AUTO_DELIVER_DISTANCE_METERS: 50,  // Auto-complete when within 50m
  DRIVER_COMMISSION_RATE: 0.10,      // 10% of order total for driver
};

class DeliveryController {

  // ═══════════════════════════════════════════════════════════════════════════
  // 📝 BASIC CRUD OPERATIONS
  // ═══════════════════════════════════════════════════════════════════════════

  static async create(req, res, next) {
    try {
      const { uid, email, name, phone, nationalID, address } = req.body;
      if (!uid) {
        return res.status(400).json({ success: false, message: 'uid required' });
      }

      await DeliveryRequest.createOrUpdate({ 
        uid, email, name, phone, 
        national_id: nationalID, 
        address 
      });

      logger.info(`New delivery request created for uid: ${uid}`);
      return res.status(201).json({ success: true, message: 'Delivery request submitted' });
    } catch (error) {
      logger.error('Error creating delivery request', error);
      next(error);
    }
  }

  static async me(req, res, next) {
    try {
      const uid = req.user?.id || req.user?.uid;  // JWT has 'id', fallback to 'uid'
      if (!uid) {
        console.log('[DeliveryController.me] No uid found in req.user:', req.user);
        return res.status(401).json({ success: false, message: 'Unauthorized' });
      }

      console.log('[DeliveryController.me] Looking up driver with uid:', uid);
      const row = await DeliveryRequest.findByUid(uid);
      if (!row) {
        console.log('[DeliveryController.me] No driver found for uid:', uid);
        return res.status(404).json({ success: false, message: 'Not found' });
      }

      console.log('[DeliveryController.me] Found driver:', row.email);
      res.json({ success: true, data: row });
    } catch (error) {
      logger.error('Error fetching delivery request for user', error);
      next(error);
    }
  }

  static async updateLocation(req, res, next) {
    try {
      const { latitude, longitude } = req.body;
      const uid = req.user?.id || req.user?.uid;

      // DEBUG LOG
      logger.info(`📍 updateLocation called: uid=${uid}, latitude=${latitude}, longitude=${longitude}, body=${JSON.stringify(req.body)}`);

      if (!uid) {
        return res.status(401).json({ success: false, message: 'Unauthorized' });
      }

      if (typeof latitude === 'undefined' || typeof longitude === 'undefined') {
        return res.status(400).json({ success: false, message: 'latitude and longitude required' });
      }

      const lat = parseFloat(latitude);
      const lng = parseFloat(longitude);
      
      logger.info(`📍 Parsed coordinates: lat=${lat}, lng=${lng}, isNaN(lat)=${isNaN(lat)}, isNaN(lng)=${isNaN(lng)}`);

      await DeliveryRequest.updateLocationByUid(uid, lat, lng);

      // أرسل موقع الموصل live للزبون عبر Socket
      try {
        const [orderRows] = await pool.execute(
          `SELECT id FROM orders WHERE driver_id = ? AND status IN ('confirmed','processing','shipped') LIMIT 1`,
          [uid]
        );
        if (orderRows.length > 0) {
          const orderId = String(orderRows[0].id);
          const io = getIO();
          if (io) {
            const locationEvent = {
              type: 'driver_location',
              orderId,
              id: orderId,
              driverLocation: { latitude: lat, longitude: lng },
              driver_location: JSON.stringify({ latitude: lat, longitude: lng }),
              timestamp: new Date().toISOString()
            };
            io.emit('data:delta', locationEvent);
            logger.info(`📡 Emitted driver_location for order ${orderId}`);
          }
        }
      } catch (socketErr) {
        logger.warn(`⚠️ Socket emit failed: ${socketErr.message}`);
      }

      res.json({ success: true });
    } catch (error) {
      logger.error('Error updating delivery request location', error);
      next(error);
    }
  }

  static async updateWorking(req, res, next) {
    try {
      const { uid, isWorking } = req.body;
      if (!uid) {
        return res.status(400).json({ success: false, message: 'uid required' });
      }

      await DeliveryRequest.updateIsWorkingByUid(uid, !!isWorking);
      logger.info(`Driver ${uid} is now ${isWorking ? 'ONLINE' : 'OFFLINE'}`);
      res.json({ success: true });
    } catch (error) {
      logger.error('Error updating working status', error);
      next(error);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🎁 ORDER OFFER SYSTEM
  // ═══════════════════════════════════════════════════════════════════════════

  /**
   * Get order offer for driver
   * - If driver is only one available, offer comes back even if they skipped
   * - Skipped list resets if no other drivers available
   */
  static async getOrderOffer(req, res, next) {
    try {
      const uid = req.user?.id || req.user?.uid;
      const { latitude, longitude } = req.query;

      if (!uid) {
        return res.status(401).json({ success: false, message: 'Unauthorized' });
      }

      if (!latitude || !longitude) {
        return res.status(400).json({ success: false, message: 'latitude and longitude required' });
      }

      const lat = parseFloat(latitude);
      const lng = parseFloat(longitude);

      // Update driver location
      await DeliveryRequest.updateLocationByUid(uid, lat, lng);

      // Check if driver already has an active order
      const activeOrder = await Order.findActiveByDriverId(uid);
      if (activeOrder) {
        return res.json({ 
          success: true, 
          data: null, 
          message: 'You already have an active order' 
        });
      }

      // Find orders waiting for assignment
      const pendingOrders = await Order.findPendingForAssignment();
      
      if (!pendingOrders || pendingOrders.length === 0) {
        return res.json({ success: true, data: null });
      }

      // DEBUG: Log all pending orders
      logger.info(`📋 Found ${pendingOrders.length} pending orders`);
      pendingOrders.forEach((order, idx) => {
        logger.info(`  Order ${idx + 1}: ID=${order.id}, currency="${order.currency}", total=${order.total_price}`);
      });

      // Process each order
      for (const order of pendingOrders) {
        // Parse skipped_driver_ids safely
        let skippedDrivers = [];
        if (order.skipped_driver_ids) {
          try {
            // Check if already an array or needs parsing
            if (Array.isArray(order.skipped_driver_ids)) {
              skippedDrivers = order.skipped_driver_ids;
            } else if (typeof order.skipped_driver_ids === 'string') {
              skippedDrivers = JSON.parse(order.skipped_driver_ids);
            }
          } catch (e) {
            logger.warn(`Failed to parse skipped_driver_ids for order ${order.id}: ${e.message}`);
            skippedDrivers = [];
          }
        }

        // Check if there's an active offer for another driver
        if (order.current_offer_driver_id && order.offer_expires_at) {
          const expiresAt = new Date(order.offer_expires_at);
          const now = new Date();

          // If offer is for this driver and still valid, return it
          if (order.current_offer_driver_id === uid && expiresAt > now) {
            // Return existing offer
            return res.json({ 
              success: true, 
              data: buildOfferResponse(order, lat, lng) 
            });
          }

          // If offer is for another driver and still valid, skip this order
          if (order.current_offer_driver_id !== uid && expiresAt > now) {
            continue;
          }

          // If offer expired, clear it
          if (expiresAt <= now) {
            await Order.clearOffer(order.id);
          }
        }

        // Get store location
        const storeLat = parseFloat(order.store_latitude) || 0;
        const storeLng = parseFloat(order.store_longitude) || 0;

        if (storeLat === 0 || storeLng === 0) {
          continue;
        }

        // Calculate distance from driver to store
        const distanceToStore = calculateDistance(lat, lng, storeLat, storeLng);

        // Check if driver is within range
        if (distanceToStore > CONFIG.MAX_SEARCH_RADIUS_METERS) {
          continue;
        }

        // Find all available drivers (excluding those who skipped)
        const availableDrivers = await DeliveryRequest.findDriversNearLocation(
          storeLat, 
          storeLng, 
          CONFIG.MAX_SEARCH_RADIUS_METERS
        );

        // Filter out skipped drivers
        const eligibleDrivers = availableDrivers.filter(d => !skippedDrivers.includes(d.uid));

        // If no eligible drivers left, reset skipped list and try again
        if (eligibleDrivers.length === 0 && availableDrivers.length > 0) {
          logger.info(`Order ${order.id}: All drivers skipped. Resetting skip list.`);
          await Order.resetSkippedDrivers(order.id);
          // This driver can now receive the offer
          const offer = await createOfferForDriver(order, uid, lat, lng);
          return res.json({ success: true, data: offer });
        }

        // Check if this driver is the closest eligible driver
        if (eligibleDrivers.length > 0) {
          const closestDriver = eligibleDrivers[0]; // Already sorted by distance

          if (closestDriver.uid === uid) {
            // This driver is the closest, create offer
            const offer = await createOfferForDriver(order, uid, lat, lng);
            return res.json({ success: true, data: offer });
          }
        }
      }

      // No offer available
      res.json({ success: true, data: null });

    } catch (error) {
      logger.error('Error getting order offer', error);
      next(error);
    }
  }

  /**
   * Accept order offer
   */
  static async acceptOffer(req, res, next) {
    try {
      const uid = req.user?.id || req.user?.uid;
      const { orderId } = req.body;

      if (!uid) {
        return res.status(401).json({ success: false, message: 'Unauthorized' });
      }

      if (!orderId) {
        return res.status(400).json({ success: false, message: 'orderId required' });
      }

      const order = await Order.findById(orderId);
      if (!order) {
        return res.status(404).json({ success: false, message: 'Order not found' });
      }

      // Verify offer
      if (order.current_offer_driver_id && order.current_offer_driver_id !== uid) {
        return res.status(400).json({ 
          success: false, 
          message: 'This offer is not for you' 
        });
      }

      if (order.offer_expires_at) {
        const expiresAt = new Date(order.offer_expires_at);
        if (new Date() > expiresAt) {
          return res.status(400).json({ 
            success: false, 
            message: 'Offer has expired' 
          });
        }
      }

      // Check if already assigned
      if (order.driver_id && order.driver_id !== uid) {
        return res.status(400).json({ 
          success: false, 
          message: 'Order already assigned' 
        });
      }

      // Assign order
      const assigned = await Order.assignToDriver(orderId, uid);
      if (!assigned) {
        return res.status(400).json({ 
          success: false, 
          message: 'Failed to assign order' 
        });
      }

      await Order.clearOffer(orderId);

      logger.info(`Driver ${uid} accepted order ${orderId}`);
      res.json({ 
        success: true, 
        message: 'Order accepted',
        data: { orderId }
      });

    } catch (error) {
      logger.error('Error accepting order offer', error);
      next(error);
    }
  }

  /**
   * Skip order offer
   */
  static async skipOffer(req, res, next) {
    try {
      const uid = req.user?.id || req.user?.uid;
      const { orderId } = req.body;

      if (!uid) {
        return res.status(401).json({ success: false, message: 'Unauthorized' });
      }

      if (!orderId) {
        return res.status(400).json({ success: false, message: 'orderId required' });
      }

      await Order.addSkippedDriver(orderId, uid);
      await Order.clearOffer(orderId);

      logger.info(`Driver ${uid} skipped order ${orderId}`);
      res.json({ success: true, message: 'Order skipped' });

    } catch (error) {
      logger.error('Error skipping order offer', error);
      next(error);
    }
  }

  /**
   * Get skipped orders that driver can reclaim
   */
  static async getSkippedOrders(req, res, next) {
    try {
      const uid = req.user?.id || req.user?.uid;
      const { latitude, longitude } = req.query;

      if (!uid) {
        return res.status(401).json({ success: false, message: 'Unauthorized' });
      }

      if (!latitude || !longitude) {
        return res.status(400).json({ success: false, message: 'latitude and longitude required' });
      }

      const lat = parseFloat(latitude);
      const lng = parseFloat(longitude);

      // Get orders where this driver skipped but no current offer to another driver
      const pendingOrders = await Order.findPendingForAssignment();
      const reclaimable = [];

      for (const order of pendingOrders) {
        // Parse skipped drivers
        let skippedDrivers = [];
        try {
          if (order.skipped_driver_ids) {
            skippedDrivers = Array.isArray(order.skipped_driver_ids) 
              ? order.skipped_driver_ids 
              : JSON.parse(order.skipped_driver_ids);
          }
        } catch (e) {
          skippedDrivers = [];
        }

        // Only show if this driver skipped it
        if (!skippedDrivers.includes(uid)) {
          continue;
        }

        // Check if there's an active offer to someone else
        if (order.current_offer_driver_id && order.offer_expires_at) {
          const expiresAt = new Date(order.offer_expires_at);
          if (new Date() < expiresAt && order.current_offer_driver_id !== uid) {
            // Another driver has active offer
            continue;
          }
        }

        // Can reclaim this order
        const storeLat = parseFloat(order.store_latitude) || 0;
        const storeLng = parseFloat(order.store_longitude) || 0;
        const distanceToStore = calculateDistance(lat, lng, storeLat, storeLng);

        reclaimable.push({
          order_id: order.id,
          store_id: order.store_id,
          store_name: order.store_name || 'Store',
          total_price: parseFloat(order.total_price) || 0,
          distance_to_store: distanceToStore,
          estimated_earnings: (parseFloat(order.total_price) || 0) * CONFIG.DRIVER_COMMISSION_RATE,
          store_latitude: storeLat,
          store_longitude: storeLng,
        });
      }

      res.json({ success: true, data: reclaimable });

    } catch (error) {
      logger.error('Error getting skipped orders', error);
      next(error);
    }
  }

  /**
   * Reclaim a skipped order
   */
  static async reclaimOrder(req, res, next) {
    try {
      const uid = req.user?.id || req.user?.uid;
      const { orderId } = req.body;

      if (!uid) {
        return res.status(401).json({ success: false, message: 'Unauthorized' });
      }

      if (!orderId) {
        return res.status(400).json({ success: false, message: 'orderId required' });
      }

      const order = await Order.findById(orderId);
      if (!order) {
        return res.status(404).json({ success: false, message: 'Order not found' });
      }

      // Check if already assigned
      if (order.driver_id) {
        return res.status(400).json({ 
          success: false, 
          message: 'Order already assigned to another driver' 
        });
      }

      // Check if another driver has active offer
      if (order.current_offer_driver_id && order.offer_expires_at) {
        const expiresAt = new Date(order.offer_expires_at);
        if (new Date() < expiresAt && order.current_offer_driver_id !== uid) {
          return res.status(400).json({ 
            success: false, 
            message: 'Another driver is considering this order' 
          });
        }
      }

      // Assign directly
      const assigned = await Order.assignToDriver(orderId, uid);
      if (!assigned) {
        return res.status(400).json({ 
          success: false, 
          message: 'Failed to assign order' 
        });
      }

      // Clear offer and skipped list
      await Order.clearOffer(orderId);

      logger.info(`Driver ${uid} reclaimed order ${orderId}`);
      res.json({ 
        success: true, 
        message: 'Order reclaimed successfully',
        data: { orderId }
      });

    } catch (error) {
      logger.error('Error reclaiming order', error);
      next(error);
    }
  }

  /**
   * Get driver's active order
   */
  static async getActiveOrder(req, res, next) {
    try {
      const uid = req.user?.id || req.user?.uid;
      if (!uid) {
        return res.status(401).json({ success: false, message: 'Unauthorized' });
      }

      const order = await Order.findActiveByDriverId(uid);
      try {
        const itemsCount = order && Array.isArray(order.items) ? order.items.length : 0;
        logger.info(`[getActiveOrder] Returning order id=${order?.id || 'null'} itemsCount=${itemsCount}`);
      } catch (logErr) {
        logger.warn('[getActiveOrder] Could not log order items count', logErr.message);
      }
      res.json({ success: true, data: order || null });

    } catch (error) {
      logger.error('Error getting active order', error);
      next(error);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  ORDER LIFECYCLE
  // ═══════════════════════════════════════════════════════════════════════════

  static async pickupOrder(req, res, next) {
    try {
      const uid = req.user?.id || req.user?.uid;
      const { orderId } = req.params;

      if (!uid) {
        return res.status(401).json({ success: false, message: 'Unauthorized' });
      }

      const order = await Order.findById(orderId);
      if (!order) {
        return res.status(404).json({ success: false, message: 'Order not found' });
      }

      if (order.driver_id && order.driver_id !== uid) {
        return res.status(403).json({
          success: false,
          message: "Order not assigned to this driver"
        });
      }

      await Order.updateStatus(orderId, 'shipped');
      await Order.setPickedUpAt(orderId);

      const updatedOrder = await Order.findById(orderId);

      // Broadcast the updated order so customer/driver UIs refresh immediately
      try {
        const io = getIO();
        if (io && updatedOrder) {
          io.emit('data:delta', {
            type: 'order_updated',
            orderId: String(orderId),
            id: String(orderId),
            order: updatedOrder,
            data: updatedOrder,
            timestamp: new Date().toISOString(),
          });
          logger.info(`📡 Socket: order_updated for order ${orderId}`);
        }
      } catch (socketErr) {
        logger.warn(`⚠️ Socket emit failed after pickup: ${socketErr.message}`);
      }

      logger.info(`Order ${orderId} picked up by driver ${uid}`);
      res.json({ success: true, data: updatedOrder });

    } catch (error) {
      logger.error('Error marking order as picked up', error);
      next(error);
    }
  }

  static async updateOrderLocation(req, res, next) {
    try {
      const uid = req.user?.id || req.user?.uid;
      const { orderId } = req.params;
      const { latitude, longitude } = req.body;

      if (!uid) {
        return res.status(401).json({ success: false, message: 'Unauthorized' });
      }

      if (typeof latitude === 'undefined' || typeof longitude === 'undefined') {
        return res.status(400).json({ success: false, message: 'latitude and longitude required' });
      }

      const order = await Order.findById(orderId);
      if (!order || order.driver_id !== uid) {
        return res.status(403).json({ success: false, message: 'Not authorized' });
      }

      const lat = parseFloat(latitude);
      const lng = parseFloat(longitude);
      await Order.updateDriverLocation(orderId, lat, lng);

      // أرسل موقع الموصل live للزبون
      try {
        const io = getIO();
        if (io) {
          const event = {
            type: 'driver_location',
            orderId: String(orderId),
            id: String(orderId),
            driver_location: JSON.stringify({ latitude: lat, longitude: lng }),
            timestamp: new Date().toISOString()
          };
          io.emit('data:delta', event);
          logger.info(`📡 Socket: driver_location for order ${orderId} → lat=${lat}, lng=${lng}`);
        }
      } catch (e) {
        logger.warn(`⚠️ Socket emit failed: ${e.message}`);
      }

      res.json({ success: true });

    } catch (error) {
      logger.error('Error updating order location', error);
      next(error);
    }
  }

  static async markDelivered(req, res, next) {
    try {
      const uid = req.user?.id || req.user?.uid;
      const { orderId } = req.params;

      if (!uid) {
        return res.status(401).json({ success: false, message: 'Unauthorized' });
      }

      const order = await Order.findById(orderId);
      if (!order) {
        return res.status(404).json({ success: false, message: 'Order not found' });
      }

      if (order.driver_id !== uid) {
        return res.status(403).json({ success: false, message: 'Not your order' });
      }

      await Order.updateStatus(orderId, 'delivered');
      await Order.setDeliveredAt(orderId);

      const earnings = (parseFloat(order.total_price) || 0) * CONFIG.DRIVER_COMMISSION_RATE;
      await DeliveryRequest.recordCompletedDelivery(uid, orderId, earnings);

      logger.info(`Order ${orderId} delivered by driver ${uid}. Earnings: $${earnings.toFixed(2)}`);

      // Send delivery confirmation email to customer (fire-and-forget)
      setImmediate(async () => {
        try {
          const customerEmail = order.customer_email;
          if (customerEmail) {
            const emailService = await getEmailService();
            if (emailService) {
              const backendUrl = process.env.PUBLIC_BACKEND_URL || process.env.API_BASE_URL || 'http://Mohammeds-Mackbook-MacBook-Air.local:3000';
              const reportUrl = `${backendUrl}/report-problem?orderId=${orderId}`;
              const html = renderDeliveryConfirmationHTML({
                order: { ...order, customer_name: order.customer_name },
                driverName: order.driver_name,
                deliveryTime: new Date().toISOString(),
                reportUrl,
              });
              await emailService.sendOrderReceiptEmail(
                customerEmail,
                `YSHOP — Your Order #${orderId} Has Been Delivered`,
                html
              );
              logger.info(`✓ Delivery confirmation email sent to ${customerEmail} for order ${orderId}`);
            }
          }
        } catch (emailErr) {
          logger.warn(`Delivery confirmation email failed for order ${orderId}:`, emailErr.message);
        }
      });

      res.json({
        success: true,
        message: 'Order delivered',
        data: { earnings }
      });

    } catch (error) {
      logger.error('Error marking order as delivered', error);
      next(error);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  HISTORY & STATS
  // ═══════════════════════════════════════════════════════════════════════════

  static async getDeliveryHistory(req, res, next) {
    try {
      const uid = req.user?.id || req.user?.uid;
      const { month, year, page = 1, limit = 50 } = req.query;

      if (!uid) {
        return res.status(401).json({ success: false, message: 'Unauthorized' });
      }

      const history = await Order.findCompletedByDriverId(uid, {
        month: month ? parseInt(month) : null,
        year: year ? parseInt(year) : null,
        page: parseInt(page),
        limit: parseInt(limit),
      });

      res.json({ success: true, data: history });

    } catch (error) {
      logger.error('Error getting delivery history', error);
      next(error);
    }
  }

  static async getDriverStats(req, res, next) {
    try {
      const uid = req.user?.id || req.user?.uid;
      const { month, year } = req.query;

      if (!uid) {
        return res.status(401).json({ success: false, message: 'Unauthorized' });
      }

      const stats = await DeliveryRequest.getDriverStats(uid, {
        month: month ? parseInt(month) : null,
        year: year ? parseInt(year) : null,
      });

      res.json({ success: true, data: stats });

    } catch (error) {
      logger.error('Error getting driver stats', error);
      next(error);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 👨‍💼 ADMIN OPERATIONS
  // ═══════════════════════════════════════════════════════════════════════════

  static async listPending(req, res, next) {
    try {
      const rows = await DeliveryRequest.listPending();
      res.json({ success: true, data: rows });
    } catch (error) {
      logger.error('Error listing delivery requests', error);
      next(error);
    }
  }

  static async listApproved(req, res, next) {
    try {
      const rows = await DeliveryRequest.listApproved();
      res.json({ success: true, data: rows });
    } catch (error) {
      logger.error('Error listing approved delivery requests', error);
      next(error);
    }
  }

  static async listActive(req, res, next) {
    try {
      const rows = await DeliveryRequest.listActive();
      res.json({ success: true, data: rows });
    } catch (error) {
      logger.error('Error listing active delivery requests', error);
      next(error);
    }
  }

  static async approve(req, res, next) {
    try {
      const { id } = req.params;
      const row = await DeliveryRequest.findById(id);
      if (!row) {
        return res.status(404).json({ success: false, message: 'Not found' });
      }

      // Update status in delivery_requests to 'Approved'
      await DeliveryRequest.updateStatus(id, 'Approved');

      // Create user account in users table (so driver can login normally)
      try {
        const pool = require('../config/database.js').default;
        const connection = await pool.getConnection();
        
        // Check if user already exists
        const [existingUser] = await connection.execute(
          'SELECT id FROM users WHERE uid = ?',
          [row.uid]
        );
        
        if (existingUser.length === 0) {
          // Insert into users table
          await connection.execute(
            `INSERT INTO users (uid, email, password_hash, display_name, phone, national_id, address, email_verified, latitude, longitude) 
             VALUES (?, ?, ?, ?, ?, ?, ?, 1, ?, ?)`,
            [row.uid, row.email, row.password_hash, row.name, row.phone, row.national_id, row.address, row.latitude, row.longitude]
          );
        }
        
        connection.release();
      } catch (userError) {
        logger.warn('Could not create user account for driver', userError.message);
      }

      try {
        await admin.auth().setCustomUserClaims(row.uid, { deliveryApproved: true });
      } catch (e) {
        logger.warn('Could not set custom claim', e.message);
      }

      logger.info(`Driver ${row.uid} approved`);
      res.json({ success: true });

    } catch (error) {
      logger.error('Error approving delivery request', error);
      next(error);
    }
  }

  static async reject(req, res, next) {
    try {
      const { id } = req.params;
      const row = await DeliveryRequest.findById(id);
      if (!row) {
        return res.status(404).json({ success: false, message: 'Not found' });
      }

      await DeliveryRequest.updateStatus(id, 'Rejected');

      try {
        await admin.auth().setCustomUserClaims(row.uid, null);
      } catch (e) {
        logger.warn('Could not remove custom claim', e.message);
      }

      logger.info(`Driver ${row.uid} rejected`);
      res.json({ success: true });

    } catch (error) {
      logger.error('Error rejecting delivery request', error);
      next(error);
    }
  }

  static async setPending(req, res, next) {
    try {
      const { id } = req.params;
      const row = await DeliveryRequest.findById(id);
      if (!row) {
        return res.status(404).json({ success: false, message: 'Not found' });
      }

      await DeliveryRequest.updateStatus(id, 'Pending');
      res.json({ success: true });

    } catch (error) {
      logger.error('Error setting pending status', error);
      next(error);
    }
  }

  static async delete(req, res, next) {
    try {
      const { id } = req.params;
      const row = await DeliveryRequest.findById(id);
      if (!row) {
        return res.status(404).json({ success: false, message: 'Not found' });
      }

      await DeliveryRequest.deleteById(id);
      logger.info(`Driver ${row.uid} deleted`);
      res.json({ success: true });

    } catch (error) {
      logger.error('Error deleting delivery request', error);
      next(error);
    }
  }

  static async getAllDriverLocations(req, res, next) {
    try {
      const drivers = await DeliveryRequest.getAllWithLocations();
      res.json({ success: true, data: drivers });
    } catch (error) {
      logger.error('Error getting all driver locations', error);
      next(error);
    }
  }

  static async nearby(req, res, next) {
    try {
      const { latitude, longitude, radiusMeters = 5000, limit = 10 } = req.body;

      if (typeof latitude === 'undefined' || typeof longitude === 'undefined') {
        return res.status(400).json({ success: false, message: 'latitude and longitude required' });
      }

      const lat = parseFloat(latitude);
      const lng = parseFloat(longitude);

      try {
        const uid = req.user?.id || req.user?.uid;
        if (uid) {
          await DeliveryRequest.updateLocationByUid(uid, lat, lng);
        }
      } catch (e) {
        // Ignore
      }

      const nearby = await Order.findNearby(lat, lng, parseInt(radiusMeters), parseInt(limit));
      res.json({ success: true, data: nearby });

    } catch (error) {
      logger.error('Error fetching nearby orders', error);
      next(error);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 🔧 HELPER FUNCTIONS
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Calculate distance using Haversine formula
 */
function calculateDistance(lat1, lon1, lat2, lon2) {
  const R = 6371000;
  const φ1 = (lat1 * Math.PI) / 180;
  const φ2 = (lat2 * Math.PI) / 180;
  const Δφ = ((lat2 - lat1) * Math.PI) / 180;
  const Δλ = ((lon2 - lon1) * Math.PI) / 180;

  const a = Math.sin(Δφ / 2) * Math.sin(Δφ / 2) +
            Math.cos(φ1) * Math.cos(φ2) *
            Math.sin(Δλ / 2) * Math.sin(Δλ / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));

  return R * c;
}

/**
 * Create offer for driver
 */
async function createOfferForDriver(order, driverUid, driverLat, driverLng) {
  const expiresAt = new Date(Date.now() + CONFIG.OFFER_TIMEOUT_SECONDS * 1000);
  await Order.setOffer(order.id, driverUid, expiresAt);

  const storeLat = parseFloat(order.store_latitude) || 0;
  const storeLng = parseFloat(order.store_longitude) || 0;
  const customerLat = parseFloat(order.customer_latitude) || 0;
  const customerLng = parseFloat(order.customer_longitude) || 0;
  const distanceToStore = calculateDistance(driverLat, driverLng, storeLat, storeLng);

  logger.info(`Offer created for driver ${driverUid} - Order ${order.id}`);

  return {
    order_id: order.id,
    store_id: order.store_id,
    store_name: order.store_name || 'Store',
    total_price: parseFloat(order.total_price) || 0,
    currency: order.currency || 'USD',
    distance_to_store: distanceToStore,
    estimated_earnings: (parseFloat(order.total_price) || 0) * CONFIG.DRIVER_COMMISSION_RATE,
    expires_at: expiresAt.toISOString(),
    remaining_seconds: CONFIG.OFFER_TIMEOUT_SECONDS,
    store_latitude: storeLat,
    store_longitude: storeLng,
    customer_latitude: customerLat,
    customer_longitude: customerLng,
    customer_address: order.shipping_address || order.customer_address || '',
  };
}

/**
 * Build offer response
 */
function buildOfferResponse(order, driverLat, driverLng) {
  const storeLat = parseFloat(order.store_latitude) || 0;
  const storeLng = parseFloat(order.store_longitude) || 0;
  const customerLat = parseFloat(order.customer_latitude) || 0;
  const customerLng = parseFloat(order.customer_longitude) || 0;
  const distanceToStore = calculateDistance(driverLat, driverLng, storeLat, storeLng);

  const expiresAt = new Date(order.offer_expires_at);
  const remainingSeconds = Math.max(0, Math.floor((expiresAt - new Date()) / 1000));

  // DEBUG: Log the order object to see what we're getting
  logger.info(`🔍 Order object keys: ${Object.keys(order).join(', ')}`);
  logger.info(`🔍 Order.currency value: "${order.currency}" (type: ${typeof order.currency})`);
  logger.info(`🔍 Full order object: ${JSON.stringify(order)}`);

  const offerResponse = {
    order_id: order.id,
    store_id: order.store_id,
    store_name: order.store_name || 'Store',
    total_price: parseFloat(order.total_price) || 0,
    currency: order.currency || 'USD',
    distance_to_store: distanceToStore,
    estimated_earnings: (parseFloat(order.total_price) || 0) * CONFIG.DRIVER_COMMISSION_RATE,
    expires_at: expiresAt.toISOString(),
    remaining_seconds: remainingSeconds,
    store_latitude: storeLat,
    store_longitude: storeLng,
    customer_latitude: customerLat,
    customer_longitude: customerLng,
    customer_address: order.shipping_address || order.customer_address || '',
  };

  logger.info(`📦 Offer Response: Order #${offerResponse.order_id}, Price: ${offerResponse.total_price}, Currency: ${offerResponse.currency}`);
  return offerResponse;
}

export default DeliveryController;