import Order from '../models/Order.js';
import logger from '../config/logger.js';
import { getEmailService, renderReceiptCustomerHTML, renderReceiptStoreHTML } from '../utils/emailService.js';
import { Store } from '../models/Store.js';

export class OrderController {
  static async getAdminOrders(req, res, next) {
    try {
      const { limit = 50 } = req.query;
      const orders = await Order.findRecent(parseInt(limit, 10));
      res.set('Cache-Control', 'no-cache, no-store, must-revalidate, max-age=0');
      res.set('Pragma', 'no-cache');
      res.set('Expires', '0');
      res.json({ success: true, data: orders });
    } catch (error) {
      logger.error('Error in getAdminOrders:', error);
      next(error);
    }
  }
  static async create(req, res, next) {
    try {
      const { storeId, totalPrice, shippingAddress, items, paymentMethod, deliveryOption, currency } = req.body;
      if (!req.user || !req.user.id) {
        return res.status(401).json({ success: false, message: 'Unauthorized: user required' });
      }
      const userId = req.user.id;

      const order = await Order.create({
        userId,
        storeId,
        totalPrice,
        shippingAddress,
        paymentMethod,
        deliveryOption,
        currency,
        items,
      });

      // Send emails after order creation
      try {
        const emailService = await getEmailService();
        
        // Get user and store info for emails
        const userInfo = req.user;
        const store = await Store.findById(storeId);
        
        if (emailService && userInfo && store) {
          // Prepare order object for email templates
          const orderForEmail = {
            id: order.id,
            total_price: totalPrice,
            total: totalPrice,
            created_at: new Date().toISOString(),
            items: items,
            customer: {
              name: userInfo.displayName || userInfo.email || 'Customer',
              email: userInfo.email,
            },
          };

          // Send store owner notification email
          if (store.owner_email || store.ownerEmail) {
            const storeEmail = store.owner_email || store.ownerEmail;
            const storeHTML = renderReceiptStoreHTML({
              order: orderForEmail,
              store: { name: store.name || store.storeName },
              splits: {},
              logoUrl: '',
            });
            await emailService.sendOrderReceiptEmail(
              storeEmail,
              `YSHOP - New Order #${order.id} from ${userInfo.displayName || 'Customer'}`,
              storeHTML
            );
            logger.info(`✓ Order notification email sent to store: ${storeEmail}`);
          }
        }
      } catch (emailError) {
        logger.warn('Email sending failed but order created successfully:', emailError.message);
        // Don't fail the order creation if email fails
      }

      res.status(201).json({
        success: true,
        data: order,
      });
    } catch (error) {
      logger.error('Error in create:', error);
      next(error);
    }
  }

  static async getById(req, res, next) {
    try {
      const { id } = req.params;

      const order = await Order.findById(id);

      if (!order) {
        return res.status(404).json({
          success: false,
          message: 'Order not found',
        });
      }

      // If requester is admin allow access
      if (req.admin && (req.admin.role === 'admin' || req.admin.role === 'superadmin')) {
        // allowed
      } else {
        // Otherwise require an authenticated Firebase user and check ownership
        if (!req.user || !req.user.id) {
          return res.status(401).json({ success: false, message: 'Unauthorized' });
        }
        if (order.user_id !== req.user.id) {
          return res.status(403).json({ success: false, message: 'Forbidden' });
        }
      }

      // Set cache-busting headers
      res.setHeader('Cache-Control', 'max-age=0, no-cache, no-store, must-revalidate');
      res.setHeader('Pragma', 'no-cache');
      res.setHeader('Expires', '0');

      res.json({
        success: true,
        data: order,
      });
    } catch (error) {
      logger.error('Error in getById:', error);
      next(error);
    }
  }

  static async getUserOrders(req, res, next) {
    try {
      const { page = 1, limit = 20 } = req.query;
      if (!req.user || !req.user.id) {
        return res.status(401).json({ success: false, message: 'Unauthorized: user required' });
      }
      const userId = req.user.id;

      // Set cache-busting headers (same as products/admin endpoints)
      res.setHeader('Cache-Control', 'max-age=0, no-cache, no-store, must-revalidate');
      res.setHeader('Pragma', 'no-cache');
      res.setHeader('Expires', '0');

      const orders = await Order.findByUserId(
        userId,
        parseInt(page),
        parseInt(limit)
      );

      res.json({
        success: true,
        data: orders,
        pagination: { page: parseInt(page), limit: parseInt(limit) },
      });
    } catch (error) {
      logger.error('Error in getUserOrders:', error);
      next(error);
    }
  }

  static async getStoreOrders(req, res, next) {
    try {
      const { page = 1, limit = 50 } = req.query;
      // store owner must be authenticated; attempt to derive owner's store
      // If route includes storeId param use it, otherwise try to get store for the current user
      const storeId = req.params.storeId || req.query.storeId;

      if (!storeId) {
        return res.status(400).json({ success: false, message: 'Missing storeId' });
      }

      // Set cache-busting headers (same as user orders)
      res.setHeader('Cache-Control', 'max-age=0, no-cache, no-store, must-revalidate');
      res.setHeader('Pragma', 'no-cache');
      res.setHeader('Expires', '0');

      const orders = await Order.findByStoreId(storeId, parseInt(page), parseInt(limit));

      res.json({ success: true, data: orders, pagination: { page: parseInt(page), limit: parseInt(limit) } });
    } catch (error) {
      logger.error('Error in getStoreOrders:', error);
      next(error);
    }
  }

  static async updateStatus(req, res, next) {
    try {
      const { id } = req.params;
      const { status } = req.body;

      // Validate status
      const validStatuses = ['pending', 'confirmed', 'shipped', 'delivered', 'cancelled', 'return'];
      if (!validStatuses.includes(status)) {
        return res.status(400).json({
          success: false,
          message: 'Invalid status',
        });
      }

      // Get the order first
      const order = await Order.findById(id);
      if (!order) {
        return res.status(404).json({
          success: false,
          message: 'Order not found',
        });
      }

      // Check authorization: user can only request returns on their own orders
      if ((status === 'return' || status === 'delivered') && req.user) {
        if (order.user_id !== req.user.id) {
          return res.status(403).json({
            success: false,
            message: 'Forbidden: cannot modify this order',
          });
        }
      }

      await Order.updateStatus(id, status);

      // Set cache-busting headers after update
      res.setHeader('Cache-Control', 'max-age=0, no-cache, no-store, must-revalidate');
      res.setHeader('Pragma', 'no-cache');
      res.setHeader('Expires', '0');

      res.json({
        success: true,
        message: 'Order status updated',
      });
    } catch (error) {
      logger.error('Error in updateStatus:', error);
      next(error);
    }
  }

  static async assignToDriver(req, res, next) {
    try {
      const { id } = req.params;
      const { driverUid } = req.body;
      if (!driverUid) return res.status(400).json({ success: false, message: 'driverUid required' });

      const ok = await Order.assignToDriver(id, driverUid);
      if (!ok) {
        return res.status(409).json({ success: false, message: 'Order already assigned or not available' });
      }
      res.json({ success: true });
    } catch (error) {
      logger.error('Error in assignToDriver:', error);
      next(error);
    }
  }

  static async pickedUp(req, res, next) {
    try {
      const { id } = req.params;
      // require authenticated driver
      if (!req.user || !req.user.id) return res.status(401).json({ success: false, message: 'Unauthorized' });
      const driverId = req.user.id;

      const order = await Order.findById(id);
      if (!order) return res.status(404).json({ success: false, message: 'Order not found' });

      if (!order.driver_id && order.driver_id !== driverId) {
        // If order has no driver or different driver, still allow if driver matches assigned driver
      }

      // enforce assigned driver if present
      if (order.driver_id && order.driver_id !== driverId) {
        return res.status(403).json({ success: false, message: 'Forbidden: not assigned driver' });
      }

      // mark as shipped (internal DB value) representing 'Out for Delivery'
      await Order.updateStatus(id, 'shipped');

      // return updated order including customer/store info
      const updated = await Order.findById(id);

      try {
        const io = getIO();
        if (io && updated) {
          io.emit('data:delta', {
            type: 'order_updated',
            orderId: String(id),
            id: String(id),
            order: updated,
            data: updated,
            timestamp: new Date().toISOString(),
          });
        }
      } catch (socketErr) {
        logger.warn(`Socket emit failed after order pickup: ${socketErr.message}`);
      }

      res.json({ success: true, data: updated });
    } catch (error) {
      logger.error('Error in pickedUp:', error);
      next(error);
    }
  }

  static async markDelivered(req, res, next) {
    try {
      const { id } = req.params;
      if (!req.user || !req.user.id) return res.status(401).json({ success: false, message: 'Unauthorized' });
      const driverId = req.user.id;

      const order = await Order.findById(id);
      if (!order) return res.status(404).json({ success: false, message: 'Order not found' });

      if (order.driver_id && order.driver_id !== driverId) {
        return res.status(403).json({ success: false, message: 'Forbidden: not assigned driver' });
      }

      await Order.updateStatus(id, 'delivered');

      res.json({ success: true });
    } catch (error) {
      logger.error('Error in markDelivered:', error);
      next(error);
    }
  }

  // POST /api/v1/orders/:id/receipt
  static async sendReceipt(req, res, next) {
    try {
      const { id } = req.params;

      // multer file parser should populate req.file
      const file = req.file;
      const { recipientEmail, recipientType } = req.body || {};

      if (!file) {
        return res.status(400).json({ success: false, message: 'Missing receipt file (multipart field: file)' });
      }

      const order = await Order.findById(id);
      if (!order) {
        return res.status(404).json({ success: false, message: 'Order not found' });
      }

      // Authorization: only order owner or admin can upload/send receipts
      if (!req.admin) {
        if (!req.user || (order.user_id !== req.user.id)) {
          return res.status(403).json({ success: false, message: 'Forbidden' });
        }
      }

      const emailService = await getEmailService();

      // Compose customer email
      const customerEmail = recipientEmail || (order.customer && order.customer.email) || null;
      const store = await Store.findById(order.store_id);
      const storeEmail = store && (store.email || null);

      // Compute simple splits (configurable via env vars)
      const total = parseFloat(order.total_price || order.total || 0) || 0;
      // Default splits: platform 25% (APP_COMMISSION_RATE in Flutter), driver 10%, store gets remaining 65%
      const platformPercent = parseFloat(process.env.PLATFORM_FEE_PERCENT || '0.25');
      const driverPercent = parseFloat(process.env.DRIVER_FEE_PERCENT || '0.10');
      const platformAmount = +(total * platformPercent).toFixed(2);
      const driverAmount = +(total * driverPercent).toFixed(2);
      const storeAmount = +(total - platformAmount - driverAmount).toFixed(2);

      const attachments = [
        { filename: file.originalname || `receipt_${id}.pdf`, content: file.buffer }
      ];

      // Build splits object for templates
      const splits = {
        platform: `${platformAmount.toFixed(2)} ${order.currency || ''}`,
        driver: `${driverAmount.toFixed(2)} ${order.currency || ''}`,
        store: `${storeAmount.toFixed(2)} ${order.currency || ''}`,
      };

      // Customer email (English template)
      if (customerEmail) {
        const frontendOrderUrl = (process.env.FRONTEND_URL || 'http://Mohammeds-Mackbook-MacBook-Air.local:3000') + `/orders/${order.id}`;
        const html = renderReceiptCustomerHTML({ order, frontendOrderUrl });
        await emailService.sendOrderReceiptEmail(customerEmail, `YSHOP - Receipt for Order ${order.id}`, html, attachments);
      }

      // Store owner email
      if (storeEmail) {
        const html = renderReceiptStoreHTML({ order, store, splits });
        await emailService.sendOrderReceiptEmail(storeEmail, `YSHOP - New Order ${order.id}`, html, attachments);
      }

      return res.json({ success: true, message: 'Receipt uploaded and emails queued/sent' });
    } catch (error) {
      logger.error('Error in sendReceipt:', error);
      next(error);
    }
  }
}

export default OrderController;