import Product from '../models/Product.js';
import logger from '../config/logger.js';
import { ProductRetrievalService } from '../services/ProductRetrievalService.js';
import { VectorStore } from '../services/VectorStore.js';
import { getIO } from '../utils/socketInstance.js';
import { chargedPrice } from '../utils/pricing.js';

// Customers never see the store owner's raw base price or a fee
// breakdown — only the final online price (base + platform + delivery),
// applied here at the API boundary so every customer-facing screen gets
// it automatically. Store owners see their real entered price when
// listing their own products (storeOwnerUid present) or when editing.
function withCustomerPrice(product) {
  if (!product) return product;
  return { ...product, price: chargedPrice(product.price, { isLocal: false }) };
}

function emitProductChange(type, productId, storeId, status = null) {
  try {
    getIO()?.emit('data:delta', { type, product_id: String(productId), store_id: String(storeId), status });
  } catch {}
}

export class ProductController {
  static async getAll(req, res, next) {
    try {
      const { page = 1, limit = 100, storeId, storeOwnerUid, categoryId, search, includeUnapproved } = req.query;

      // Set cache-busting headers for products (same as admin)
      res.setHeader('Cache-Control', 'max-age=0, no-cache, no-store, must-revalidate');
      res.setHeader('Pragma', 'no-cache');
      res.setHeader('Expires', '0');

      const products = await Product.findAll(
        { storeId, storeOwnerUid, categoryId, search, includeInactive: includeUnapproved === '1' || includeUnapproved === 'true' },
        parseInt(page),
        parseInt(limit)
      );

      // storeOwnerUid present = the store owner viewing/managing their own
      // catalog (e.g. getStoreProducts) — show their real entered price.
      // Otherwise this is a customer browsing — show the final online price.
      const responseProducts = storeOwnerUid ? products : products.map(withCustomerPrice);

      res.json({
        success: true,
        data: responseProducts,
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

      const product = await Product.findById(id);

      if (!product) {
        return res.status(404).json({
          success: false,
          message: 'Product not found',
        });
      }

      res.json({
        success: true,
        data: withCustomerPrice(product),
      });
    } catch (error) {
      logger.error('Error in getById:', error);
      next(error);
    }
  }

  static async create(req, res, next) {
    try {
      const { name, description, price, storeId, categoryId, stock, currency } = req.body;

      // req.files holds every image plus the optional single video, all
      // under one 'media' field (see productRoutes.js) — sorted by
      // mimetype here rather than trusting upload order, since a store
      // owner can pick the video from anywhere in their selection.
      const files = req.files || [];
      const imageFiles = files.filter(f => f.mimetype.startsWith('image/'));
      const videoFiles = files.filter(f => f.mimetype.startsWith('video/'));

      const imageUrl = imageFiles[0] ? `/uploads/products/${imageFiles[0].filename}` : null;

      const product = await Product.create({
        name,
        description,
        price,
        storeId,
        categoryId,
        stock,
        imageUrl,
        currency: currency || 'USD', // Default to USD if not provided
      });

      const mediaItems = [
        ...imageFiles.map(f => ({ url: `/uploads/products/${f.filename}`, type: 'image' })),
        ...videoFiles.slice(0, 1).map(f => ({ url: `/uploads/products/${f.filename}`, type: 'video' })),
      ];
      if (mediaItems.length > 0) {
        await Product.replaceMedia(product.id, mediaItems);
      }

      // New product starts as pending — clear cache so stale data doesn't linger
      ProductRetrievalService.clearCache();
      emitProductChange('product_created', product.id, storeId, 'pending');

      res.status(201).json({
        success: true,
        data: product,
      });
    } catch (error) {
      logger.error('Error in create:', error);
      next(error);
    }
  }

  static async update(req, res, next) {
    try {
      const { id } = req.params;
      const updateData = req.body;

      const files = req.files || [];
      const imageFiles = files.filter(f => f.mimetype.startsWith('image/'));
      const videoFiles = files.filter(f => f.mimetype.startsWith('video/'));

      if (imageFiles[0]) {
        updateData.imageUrl = `/uploads/products/${imageFiles[0].filename}`;
      }

      const product = await Product.update(id, updateData);

      if (!product) {
        return res.status(404).json({
          success: false,
          message: 'Product not found',
        });
      }

      if (files.length > 0) {
        const mediaItems = [
          ...imageFiles.map(f => ({ url: `/uploads/products/${f.filename}`, type: 'image' })),
          ...videoFiles.slice(0, 1).map(f => ({ url: `/uploads/products/${f.filename}`, type: 'video' })),
        ];
        await Product.replaceMedia(id, mediaItems);
      }

      // Invalidate catalog cache immediately
      ProductRetrievalService.clearCache();
      emitProductChange('product_updated', id, product.store_id ?? product.storeId, product.status ?? updateData.status ?? 'approved');

      // If name or description changed, the old embedding is stale — re-embed in background
      if (product && (updateData.name !== undefined || updateData.description !== undefined)) {
        setImmediate(() => {
          VectorStore.embedAndStoreById(product.id)
            .catch(err => logger.debug(`[ProductController] re-embed after update failed: ${err.message}`));
        });
      }

      res.json({
        success: true,
        data: product,
      });
    } catch (error) {
      logger.error('Error in update:', error);
      next(error);
    }
  }

  static async delete(req, res, next) {
    try {
      const { id } = req.params;

      // Check permissions: allow if admin (req.admin.role) or owner of the store
      const product = await Product.findById(id);
      if (!product) return res.status(404).json({ success: false, message: 'Product not found' });

      const callerAdmin = req.admin;
      if (!callerAdmin) {
        // try user-based auth
        const callerUser = req.user;
        if (!callerUser) return res.status(401).json({ success: false, message: 'Unauthorized' });

        // verify ownership through the store attached to the product
        const ownerUid = product.owner_uid || product.store_owner_uid || product.ownerUid || null;
        const callerUid = callerUser.uid || callerUser.id || null;
        if (!ownerUid || !callerUid || String(ownerUid) !== String(callerUid)) {
          return res.status(403).json({ success: false, message: 'Forbidden: not owner' });
        }
      } else {
        // admin exists; require admin or superadmin
        if (!(callerAdmin.role === 'admin' || callerAdmin.role === 'superadmin')) {
          return res.status(403).json({ success: false, message: 'Forbidden: admin role required' });
        }
      }

      const storeId = product.store_id ?? product.storeId;
      await Product.delete(id);

      // FK CASCADE deletes the embedding from product_embeddings automatically.
      // Still clear catalog cache so the product vanishes from recommendations immediately.
      ProductRetrievalService.clearCache();
      emitProductChange('product_deleted', id, storeId);

      res.json({ success: true, message: 'Product deleted successfully' });
    } catch (error) {
      logger.error('Error in delete:', error);
      next(error);
    }
  }

  // ==================== ADMIN METHODS ====================

  // Get pending products
  static async getPendingProducts(req, res, next) {
    try {
      const { page = 1, limit = 100 } = req.query;

      const products = await Product.findByStatus('pending', parseInt(page), parseInt(limit));

      // Convert relative image URLs to absolute URLs
      const baseUrl = process.env.PUBLIC_BACKEND_URL || process.env.API_BASE_URL || 'http://Mohammeds-Mackbook-MacBook-Air.local:3000';
      const productsWithFullUrls = products.map(product => ({
        ...product,
        image_url: product.image_url ? (product.image_url.startsWith('http') ? (baseUrl + new URL(product.image_url).pathname) : `${baseUrl}${product.image_url}`) : null
      }));

      res.set('Cache-Control', 'no-cache, no-store, must-revalidate, max-age=0');
      res.set('Pragma', 'no-cache');
      res.set('Expires', '0');
      res.json({
        success: true,
        data: productsWithFullUrls,
        pagination: { page: parseInt(page), limit: parseInt(limit) },
      });
    } catch (error) {
      logger.error('Error in getPendingProducts:', error);
      next(error);
    }
  }

  //  NEW: Get approved products (admin endpoint)
  static async getApprovedProducts(req, res, next) {
    try {
      const { page = 1, limit = 100 } = req.query;

      const products = await Product.findByStatus('approved', parseInt(page), parseInt(limit));

      // Convert relative image URLs to absolute URLs
      const baseUrl = process.env.PUBLIC_BACKEND_URL || process.env.API_BASE_URL || 'http://Mohammeds-Mackbook-MacBook-Air.local:3000';
      const productsWithFullUrls = products.map(product => ({
        ...product,
        image_url: product.image_url ? (product.image_url.startsWith('http') ? (baseUrl + new URL(product.image_url).pathname) : `${baseUrl}${product.image_url}`) : null
      }));

      res.set('Cache-Control', 'no-cache, no-store, must-revalidate, max-age=0');
      res.set('Pragma', 'no-cache');
      res.set('Expires', '0');
      res.json({
        success: true,
        data: productsWithFullUrls,
        pagination: { page: parseInt(page), limit: parseInt(limit) },
      });
    } catch (error) {
      logger.error('Error in getApprovedProducts:', error);
      next(error);
    }
  }

  //  NEW: Get products by store owner email
  static async getProductsByEmail(req, res, next) {
    try {
      const { email } = req.query;
      const { page = 1, limit = 50 } = req.query;

      if (!email) {
        return res.status(400).json({
          success: false,
          message: 'Email parameter is required',
        });
      }

      const products = await Product.findByOwnerEmail(email, parseInt(page), parseInt(limit));

      // Convert relative image URLs to absolute URLs
      const baseUrl = process.env.PUBLIC_BACKEND_URL || process.env.API_BASE_URL || 'http://Mohammeds-Mackbook-MacBook-Air.local:3000';
      const productsWithFullUrls = products.map(product => ({
        ...product,
        image_url: product.image_url ? (product.image_url.startsWith('http') ? (baseUrl + new URL(product.image_url).pathname) : `${baseUrl}${product.image_url}`) : null
      }));

      res.json({
        success: true,
        data: productsWithFullUrls,
        pagination: { page: parseInt(page), limit: parseInt(limit) },
      });
    } catch (error) {
      logger.error('Error in getProductsByEmail:', error);
      next(error);
    }
  }

  //  NEW: Admin endpoint to view ALL products of a store (including inactive/unapproved)
  static async getStoreProductsAdmin(req, res, next) {
    try {
      const { storeId } = req.params;
      const { page = 1, limit = 100 } = req.query;

      if (!storeId) {
        return res.status(400).json({
          success: false,
          message: 'Store ID is required',
        });
      }

      // Call Product.findAll with storeId filter and includeInactive flag
      const products = await Product.findAll(
        { storeId, includeInactive: true },  //  Return ALL products regardless of status/active
        parseInt(page),
        parseInt(limit)
      );

      // Convert relative image URLs to absolute URLs
      const baseUrl = process.env.PUBLIC_BACKEND_URL || process.env.API_BASE_URL || 'http://Mohammeds-Mackbook-MacBook-Air.local:3000';
      const productsWithFullUrls = products.map(product => ({
        ...product,
        image_url: product.image_url ? (product.image_url.startsWith('http') ? (baseUrl + new URL(product.image_url).pathname) : `${baseUrl}${product.image_url}`) : null
      }));

      res.json({
        success: true,
        data: productsWithFullUrls,
        pagination: { page: parseInt(page), limit: parseInt(limit) },
      });
    } catch (error) {
      logger.error('Error in getStoreProductsAdmin:', error);
      next(error);
    }
  }

  //  NEW: Update product status (approve/pending/reject)
  static async updateProductStatus(req, res, next) {
    try {
      const { id } = req.params;
      const { status } = req.body;

      // Validate status
      const validStatuses = ['approved', 'pending', 'rejected'];
      if (!validStatuses.includes(status)) {
        return res.status(400).json({
          success: false,
          message: `Invalid status. Must be one of: ${validStatuses.join(', ')}`,
        });
      }

      const product = await Product.updateStatus(id, status);

      if (!product) {
        return res.status(404).json({
          success: false,
          message: 'Product not found',
        });
      }

      ProductRetrievalService.clearCache();
      emitProductChange('product_updated', id, product.store_id ?? product.storeId, status);

      // Generate embedding when product becomes approved for the first time
      if (status === 'approved') {
        setImmediate(() => {
          VectorStore.embedAndStoreById(product.id)
            .catch(err => logger.debug(`[ProductController] embed after status=approved failed: ${err.message}`));
        });
      }

      res.json({
        success: true,
        message: `Product status updated to ${status}`,
        data: product,
      });
    } catch (error) {
      logger.error('Error in updateProductStatus:', error);
      next(error);
    }
  }

  // Approve product
  static async approveProduct(req, res, next) {
    try {
      const { id } = req.params;

      const product = await Product.updateStatus(id, 'approved');

      if (!product) {
        return res.status(404).json({
          success: false,
          message: 'Product not found',
        });
      }

      ProductRetrievalService.clearCache();
      emitProductChange('product_updated', id, product.store_id ?? product.storeId);

      // Generate embedding immediately so the product is searchable right away
      setImmediate(() => {
        VectorStore.embedAndStoreById(product.id)
          .catch(err => logger.debug(`[ProductController] embed after approve failed: ${err.message}`));
      });

      res.json({
        success: true,
        message: 'Product approved successfully',
        data: product,
      });
    } catch (error) {
      logger.error('Error in approveProduct:', error);
      next(error);
    }
  }

  // Reject product (delete)
  static async rejectProduct(req, res, next) {
    try {
      const { id } = req.params;

      const product = await Product.findById(id).catch(() => null);
      emitProductChange('product_deleted', id, product?.store_id ?? product?.storeId ?? 0);

      // Delete the product when rejected — FK CASCADE removes embedding automatically
      await Product.delete(id);
      ProductRetrievalService.clearCache();

      res.json({
        success: true,
        message: 'Product rejected and deleted successfully',
      });
    } catch (error) {
      logger.error('Error in rejectProduct:', error);
      next(error);
    }
  }

  // Toggle product active status
  static async toggleProductStatus(req, res, next) {
    try {
      const { id } = req.params;
      const { isActive } = req.body;

      const product = await Product.update(id, { isActive });

      if (!product) {
        return res.status(404).json({
          success: false,
          message: 'Product not found',
        });
      }

      ProductRetrievalService.clearCache();
      emitProductChange('product_updated', id, product.store_id ?? product.storeId);

      if (isActive) {
        // Re-activated: generate/refresh embedding so it shows up in search immediately
        setImmediate(() => {
          VectorStore.embedAndStoreById(product.id)
            .catch(err => logger.debug(`[ProductController] embed after re-activate failed: ${err.message}`));
        });
      } else {
        // Deactivated: remove embedding to keep DB clean
        setImmediate(() => {
          VectorStore.deleteEmbedding(product.id)
            .catch(err => logger.debug(`[ProductController] delete embedding after deactivate failed: ${err.message}`));
        });
      }

      res.json({
        success: true,
        message: `Product ${isActive ? 'activated' : 'deactivated'} successfully`,
        data: product,
      });
    } catch (error) {
      logger.error('Error in toggleProductStatus:', error);
      next(error);
    }
  }
}

export default ProductController;