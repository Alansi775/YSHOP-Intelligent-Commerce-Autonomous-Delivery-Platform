import Product from '../models/Product.js';
import logger from '../config/logger.js';

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

      res.json({
        success: true,
        data: products,
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
        data: product,
      });
    } catch (error) {
      logger.error('Error in getById:', error);
      next(error);
    }
  }

  static async create(req, res, next) {
    try {
      const { name, description, price, storeId, categoryId, stock, currency } = req.body;

      const imageUrl = req.file
        ? `/uploads/products/${req.file.filename}`
        : null;

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

      if (req.file) {
        updateData.imageUrl = `/uploads/products/${req.file.filename}`;
      }

      const product = await Product.update(id, updateData);

      if (!product) {
        return res.status(404).json({
          success: false,
          message: 'Product not found',
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
        // check owner by product.store_owner_uid or product.store_owner_uid field
        const ownerUid = product.owner_uid || product.store_owner_uid || product.ownerUid || null;
        if (!ownerUid || String(ownerUid) !== String(callerUser.uid)) {
          return res.status(403).json({ success: false, message: 'Forbidden: not owner' });
        }
      } else {
        // admin exists; require admin or superadmin
        if (!(callerAdmin.role === 'admin' || callerAdmin.role === 'superadmin')) {
          return res.status(403).json({ success: false, message: 'Forbidden: admin role required' });
        }
      }

      await Product.delete(id);

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
      const baseUrl = process.env.API_BASE_URL || 'http://192.168.1.59:3000';
      const productsWithFullUrls = products.map(product => ({
        ...product,
        image_url: product.image_url ? (product.image_url.startsWith('http') ? product.image_url : `${baseUrl}${product.image_url}`) : null
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
      const baseUrl = process.env.API_BASE_URL || 'http://192.168.1.59:3000';
      const productsWithFullUrls = products.map(product => ({
        ...product,
        image_url: product.image_url ? (product.image_url.startsWith('http') ? product.image_url : `${baseUrl}${product.image_url}`) : null
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
      const baseUrl = process.env.API_BASE_URL || 'http://192.168.1.59:3000';
      const productsWithFullUrls = products.map(product => ({
        ...product,
        image_url: product.image_url ? (product.image_url.startsWith('http') ? product.image_url : `${baseUrl}${product.image_url}`) : null
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
      const baseUrl = process.env.API_BASE_URL || 'http://192.168.1.59:3000';
      const productsWithFullUrls = products.map(product => ({
        ...product,
        image_url: product.image_url ? (product.image_url.startsWith('http') ? product.image_url : `${baseUrl}${product.image_url}`) : null
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

      // Delete the product when rejected
      await Product.delete(id);

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