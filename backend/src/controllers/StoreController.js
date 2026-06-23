import Store from '../models/Store.js';
import logger from '../config/logger.js';
import pool from '../config/database.js';
import admin from '../config/firebase.js';
import { getIO } from '../utils/socketInstance.js';

function emitStoreChange(type, storeId, storeType, status = null) {
  try {
    const io = getIO();
    if (!io) {
      logger.warn(`[Socket] emitStoreChange skipped — no IO instance (${type} store ${storeId})`);
      return;
    }
    io.emit('data:delta', { type, store_id: String(storeId), store_type: storeType, status });
    logger.info(`[Socket] emitStoreChange → type=${type} storeId=${storeId} storeType=${storeType} status=${status}`);
  } catch (err) {
    logger.error(`[Socket] emitStoreChange error: ${err.message}`);
  }
}

export class StoreController {
  /**
   * جلب التحديثات منذ timestamp معين - خفيف جداً للـ polling
   */
  static async getUpdatedStores(req, res, next) {
    try {
      const { timestamp } = req.params;
      const { type } = req.query;
      
      const connection = await pool.getConnection();
      
      let query = `
        SELECT id, name, status, updated_at, store_type
        FROM stores
        WHERE updated_at > ?
        AND status = 'Approved'
      `;
      const params = [new Date(timestamp)];
      
      if (type) {
        query += ` AND LOWER(store_type) = LOWER(?)`;
        params.push(type);
      }
      
      query += ` ORDER BY updated_at DESC LIMIT 100`;
      
      const [rows] = await connection.execute(query, params);
      connection.release();
      
      res.json({
        success: true,
        data: rows,
        timestamp: new Date().toISOString(),
      });
    } catch (error) {
      logger.error('Error in getUpdatedStores:', error);
      res.status(500).json({
        success: false,
        message: 'Failed to fetch store updates',
        error: error.message,
      });
    }
  }

  /**
   * جلب المتاجر العامة للمستخدمين العاديين حسب النوع
   */
  static async getPublicStores(req, res, next) {
  try {
    const { type, page = 1, limit = 20 } = req.query;
    
    // جلب المتاجر المعتمدة (status = 'Approved') حسب النوع
    const stores = await Store.findByType(type, parseInt(page), parseInt(limit));

    res.json({
      success: true,
      data: stores,
      pagination: { page: parseInt(page), limit: parseInt(limit) },
    });
  } catch (error) {
    logger.error('Error in getPublicStores:', error);
    next(error);
  }
}

  static async getAll(req, res, next) {
    try {
      const { page = 1, limit = 20 } = req.query;
      const stores = await Store.findAll(parseInt(page), parseInt(limit));

      res.json({
        success: true,
        data: stores,
        pagination: { page: parseInt(page), limit: parseInt(limit) },
      });
    } catch (error) {
      logger.error('Error in getAll:', error);
      next(error);
    }
  }

  static async getById(req, res, next) {
    try {
      const { id } = req.params;
      const store = await Store.findById(id);

      if (!store) {
        return res.status(404).json({
          success: false,
          message: 'Store not found',
        });
      }

      res.json({
        success: true,
        data: store,
      });
    } catch (error) {
      logger.error('Error in getById:', error);
      next(error);
    }
  }

  static async create(req, res, next) {
    try {
      const { name, description, phone, address, latitude, longitude, storeType, email } = req.body;
      const ownerUid = req.body.ownerUid || req.user?.uid;

      logger.info('Store create request', {
        bodyOwnerUid: req.body.ownerUid,
        userUid: req.user?.uid,
        finalOwnerUid: ownerUid,
        fullBody: req.body,
      });

      if (!ownerUid) {
        return res.status(400).json({
          success: false,
          message: 'Owner UID is required',
        });
      }

      const iconUrl = req.file ? `/uploads/stores/${req.file.filename}` : null;

      const store = await Store.create({
        name,
        description,
        phone,
        address,
        latitude,
        longitude,
        iconUrl,
        ownerUid,
        storeType,
        email,
      });

      res.status(201).json({
        success: true,
        data: store,
      });
    } catch (error) {
      logger.error('Error in create:', error);
      next(error);
    }
  }

  static async update(req, res, next) {
    console.log('StoreController.update req.file:', req.file);
    try {
      const { id } = req.params;
      const updateData = req.body;

      if (req.file) {
        updateData.icon_url = `/uploads/stores/${req.file.filename}`;
      }

      const store = await Store.update(id, updateData);
      if (!store) {
        return res.status(404).json({
          success: false,
          message: 'Store not found',
        });
      }

      const updatedStore = await Store.findById(id);
      emitStoreChange('store_updated', id, updatedStore?.store_type ?? updatedStore?.type, updatedStore?.status);
      res.json({
        success: true,
        data: updatedStore,
      });
    } catch (error) {
      logger.error('Error in update:', error);
      next(error);
    }
  }

  static async delete(req, res, next) {
    try {
      const { id } = req.params;

      const store = await Store.findById(id);
      if (!store) return res.status(404).json({ success: false, message: 'Store not found' });

      // Allow deletion by superadmin/admin or by ownerUid
      const callerAdmin = req.admin;
      if (!callerAdmin) {
        const callerUser = req.user;
        if (!callerUser) return res.status(401).json({ success: false, message: 'Unauthorized' });
        if (String(store.owner_uid) !== String(callerUser.uid)) {
          return res.status(403).json({ success: false, message: 'Forbidden: not owner' });
        }
      } else {
        if (!(callerAdmin.role === 'admin' || callerAdmin.role === 'superadmin')) {
          return res.status(403).json({ success: false, message: 'Forbidden: admin role required' });
        }
      }

      await Store.delete(id);

      res.json({ success: true, message: 'Store deleted successfully' });
    } catch (error) {
      logger.error('Error in delete:', error);
      next(error);
    }
  }

  // ==================== Admin Dashboard Methods ====================

  //  NEW: Single endpoint for ALL dashboard data (replaces 6 separate requests!)
  static async getDashboardStats(req, res, next) {
    try {
      // 🔥 CRITICAL: Prevent all caching levels
      res.set('Cache-Control', 'no-cache, no-store, must-revalidate, max-age=0');
      res.set('Pragma', 'no-cache');
      res.set('Expires', '0');
      
      const [pendingStores, approvedStores, pendingProducts, activeDeliveries, pendingDeliveries, orders] = await Promise.all([
        Store.findPending(),
        Store.findApproved(),
        pool.query('SELECT SQL_NO_CACHE COUNT(*) as count FROM products WHERE status = "pending"'),
        pool.query('SELECT SQL_NO_CACHE COUNT(*) as count FROM delivery_requests WHERE status = "working"'),
        pool.query('SELECT SQL_NO_CACHE COUNT(*) as count FROM delivery_requests WHERE status = "pending"'),
        pool.query('SELECT SQL_NO_CACHE * FROM orders ORDER BY created_at DESC LIMIT 50'),
      ]);

      const pendingProductCount = pendingProducts[0][0]?.count || 0;
      const activeDeliveryCount = activeDeliveries[0][0]?.count || 0;
      const pendingDeliveryCount = pendingDeliveries[0][0]?.count || 0;
      const ordersList = orders[0] || [];

      res.json({
        success: true,
        data: {
          pending_stores: pendingStores || [],
          approved_stores: approvedStores || [],
          pending_products_count: pendingProductCount,
          active_deliveries_count: activeDeliveryCount,
          pending_deliveries_count: pendingDeliveryCount,
          orders: ordersList,
        },
      });
    } catch (error) {
      logger.error('Error in getDashboardStats:', error);
      next(error);
    }
  }

  static async getPendingStores(req, res, next) {
    try {
      const stores = await Store.findPending();
      res.json({
        success: true,
        data: stores,
      });
    } catch (error) {
      logger.error('Error in getPendingStores:', error);
      next(error);
    }
  }

  static async getApprovedStores(req, res, next) {
    try {
      const stores = await Store.findApproved();
      res.json({
        success: true,
        data: stores,
      });
    } catch (error) {
      logger.error('Error in getApprovedStores:', error);
      next(error);
    }
  }

  //  الموافقة على المتجر - يحدّث MySQL و Firestore
  static async approveStore(req, res, next) {
    try {
      const { id } = req.params;

      // جلب بيانات المتجر أولاً
      const storeData = await Store.findById(id);
      
      if (!storeData) {
        return res.status(404).json({
          success: false,
          message: 'Store not found',
        });
      }

      const ownerUid = storeData.owner_uid;

      //  Update MySQL FIRST (sync) for immediate API response
      await Store.update(id, { status: 'Approved' });
      logger.info(` Store ${id} MySQL updated to Approved (sync)`);

      //  Then update Firestore ASYNC (don't wait for it)
      (async () => {
        try {
          const db = admin.firestore();
          await db.collection('storeRequests').doc(ownerUid).set({
            status: 'Approved',
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, { merge: true });
          logger.info(` Store ${id} updated in Firestore to Approved (async)`);
        } catch (firebaseError) {
          logger.error(`⚠️ Failed to update Firestore for store ${id}:`, firebaseError.message);
        }
      })();

      emitStoreChange('store_updated', id, storeData.store_type ?? storeData.type, 'Approved');

      // أرجع البيانات مع owner_uid
      res.json({
        success: true,
        message: 'Store approved successfully',
        data: {
          ...storeData,
          status: 'Approved',
          owner_uid: storeData.owner_uid,
        },
      });
    } catch (error) {
      logger.error('Error in approveStore:', error);
      next(error);
    }
  }

  //  رفض المتجر - يحذف من MySQL، Flutter يحذف من Firestore
  static async rejectStore(req, res, next) {
    try {
      const { id } = req.params;

      // جلب بيانات المتجر قبل الحذف
      const storeData = await Store.findById(id);

      if (!storeData) {
        return res.status(404).json({
          success: false,
          message: 'Store not found',
        });
      }

      const ownerUid = storeData.owner_uid;

      // تحقق من وجود طلبات مرتبطة بمنتجات المتجر لمنع خطأ قيود المفتاح الأجنبي
      const connection = await pool.getConnection();
      try {
        const [productRows] = await connection.execute('SELECT id FROM products WHERE store_id = ?', [id]);
        const productIds = productRows.map((r) => r.id);

        if (productIds.length > 0) {
          // تحقق إذا كانت هناك عناصر طلب مرتبطة بأي من منتجات هذا المتجر
          const placeholders = productIds.map(() => '?').join(',');
          const [orderItemCountRows] = await connection.execute(
            `SELECT COUNT(*) as cnt FROM order_items WHERE product_id IN (${placeholders})`,
            productIds
          );

          const cnt = orderItemCountRows[0]?.cnt || 0;
          if (cnt > 0) {
            // Can't hard-delete: existing orders reference these products.
            // Soft-reject instead: update status so store disappears from customer screens.
            connection.release();
            await Store.update(id, { status: 'rejected' });
            emitStoreChange('store_updated', id, storeData.store_type ?? storeData.type, 'rejected');
            return res.json({
              success: true,
              message: 'Store rejected (preserved due to existing orders)',
              data: { ...storeData, status: 'rejected' },
            });
          }
        }

        // لا توجد طلبات مرتبطة — آمن للحذف
        if (productIds.length > 0) {
          await connection.execute('DELETE FROM products WHERE store_id = ?', [id]);
        }
      } finally {
        connection.release();
      }

      // Notify iOS clients BEFORE the hard delete (after delete the row is gone)
      emitStoreChange('store_deleted', id, storeData.store_type ?? storeData.type);

      // احذف المتجر نهائياً
      await Store.hardDelete(id);

      // أرجع owner_uid عشان Flutter يحذف من Firestore
      res.json({
        success: true,
        message: 'Store rejected and deleted successfully',
        data: {
          owner_uid: ownerUid, // مهم لحذف من Firestore
        },
      });
    } catch (error) {
      logger.error('Error in rejectStore:', error);
      next(error);
    }
  }

  // تعليق المتجر
  static async suspendStore(req, res, next) {
    try {
      const { id } = req.params;
      
      const storeData = await Store.findById(id);
      if (!storeData) {
        return res.status(404).json({
          success: false,
          message: 'Store not found',
        });
      }

      const ownerUid = storeData.owner_uid;

      //  Update MySQL FIRST (sync) for immediate API response
      await Store.update(id, { status: 'Suspended' });
      logger.info(` Store ${id} MySQL updated to Suspended (sync)`);

      // Notify iOS clients immediately — store disappears from customer screens
      emitStoreChange('store_updated', id, storeData.store_type ?? storeData.type, 'Suspended');

      //  Then update Firestore ASYNC (don't wait for it)
      (async () => {
        try {
          const db = admin.firestore();
          await db.collection('storeRequests').doc(ownerUid).set({
            status: 'Suspended',
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, { merge: true });
          logger.info(` Store ${id} updated in Firestore to Suspended (async)`);
        } catch (firebaseError) {
          logger.error(`⚠️ Failed to update Firestore for store ${id}:`, firebaseError.message);
        }
      })();

      res.json({
        success: true,
        message: 'Store suspended successfully',
        data: {
          ...storeData,
          status: 'Suspended',
          owner_uid: storeData.owner_uid,
        },
      });
    } catch (error) {
      logger.error('Error in suspendStore:', error);
      next(error);
    }
  }

  // حذف المتجر مع جميع المنتجات
  static async deleteStoreWithProducts(req, res, next) {
    try {
      const { id } = req.params;

      const storeData = await Store.findById(id);
      const ownerUid = storeData?.owner_uid;

      // Notify iOS BEFORE deleting so clients know which storeType to remove
      if (storeData) {
        emitStoreChange('store_deleted', id, storeData.store_type ?? storeData.type, null);
      }

      // حذف المنتجات
      const connection = await pool.getConnection();
      await connection.execute('DELETE FROM products WHERE store_id = ?', [id]);
      connection.release();

      // حذف المتجر
      await Store.hardDelete(id);

      res.json({
        success: true,
        message: 'Store and all associated products deleted successfully',
        data: {
          owner_uid: ownerUid,
        },
      });
    } catch (error) {
      logger.error('Error in deleteStoreWithProducts:', error);
      next(error);
    }
  }
}

export default StoreController;