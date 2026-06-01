import pool from '../config/database.js';
import logger from '../config/logger.js';

/**
 * Product Model
 */
export class Product {
  static async findAll(filters = {}, page = 1, limit = 100) {
    try {
      const offset = (page - 1) * limit;
      let query = `SELECT SQL_NO_CACHE
        p.*, 
        s.name as store_name, 
        s.phone as store_phone, 
        COALESCE(u.email, s.email) as owner_email,
        s.uid as owner_uid,
        c.name as category_name
      FROM products p 
      LEFT JOIN stores s ON p.store_id = s.id 
      LEFT JOIN users u ON s.owner_uid = u.uid 
      LEFT JOIN categories c ON p.category_id = c.id 
      WHERE 1=1`;
      const values = [];

      // Add filters only if defined and not empty
      // If includeInactive not provided or falsy, restrict to active products only
      if (!filters.includeInactive) {
        //  For public/customer view: ONLY show approved AND active products
        query += ' AND p.status = ? AND p.is_active = ?';
        values.push('approved', 1);
      }
      //  If includeInactive = true, don't filter by status (show ALL products regardless of status)

      if (filters.storeId) {
        query += ' AND p.store_id = ?';
        values.push(filters.storeId);
      }

      if (filters.storeOwnerUid) {
        query += ' AND s.uid = ?';
        values.push(String(filters.storeOwnerUid));
      }

      if (filters.categoryId) {
        query += ' AND p.category_id = ?';
        values.push(filters.categoryId);
      }

      if (filters.search) {
        query += ' AND (p.name LIKE ? OR p.description LIKE ?)';
        const searchTerm = `%${filters.search}%`;
        values.push(searchTerm, searchTerm);
      }

      const safeLimit = parseInt(limit, 10);
      const safeOffset = parseInt(offset, 10);
      query += ` ORDER BY p.created_at DESC LIMIT ${safeLimit} OFFSET ${safeOffset}`;

      //  Only log SQL in debug mode (not production)
      if (process.env.NODE_ENV === 'development') {
        logger.debug('Executing SQL:', { query, values });
      }

      // Extra debug: print number of ? and values
      const numPlaceholders = (query.match(/\?/g) || []).length;
      if (process.env.NODE_ENV === 'development' && values.length !== numPlaceholders) {
        logger.debug('SQL placeholders vs values', { numPlaceholders, valuesLength: values.length });
      }

      if (values.length !== numPlaceholders) {
        throw new Error(`SQL placeholders (${numPlaceholders}) do not match values (${values.length}): ` + JSON.stringify(values));
      }

      if (values.some(v => v === undefined)) {
        throw new Error('One or more SQL parameters are undefined: ' + JSON.stringify(values));
      }

      const connection = await pool.getConnection();
      const [rows] = await connection.execute(query, values);
      connection.release();

      // Debug: Print the first row to verify store_phone
      if (rows && rows.length > 0) {
        console.log('Sample row from SQL:', rows[0]);
      }

      // Ensure image_url is a full URL and store_phone is always present
      const baseUrl = process.env.BASE_URL || 'http://192.168.1.59:3000';
      rows.forEach(row => {
        if (row.image_url && typeof row.image_url === 'string' && !row.image_url.startsWith('http')) {
          row.image_url = baseUrl + row.image_url;
        }
        if (row.store_phone === undefined) {
          row.store_phone = '';
        }
      });

      return rows;
    } catch (error) {
      logger.error('Error fetching products:', error);
      throw error;
    }
  }

  static async findById(id) {
    try {
      const connection = await pool.getConnection();
      const [rows] = await connection.execute(
        `SELECT 
          p.*, 
          s.name as store_name, 
          s.phone as store_phone, 
          COALESCE(u.email, s.email) as owner_email,
          s.uid as owner_uid
        FROM products p 
        LEFT JOIN stores s ON p.store_id = s.id 
        LEFT JOIN users u ON s.owner_uid = u.uid 
        WHERE p.id = ?`,
        [id]
      );
      connection.release();
      return rows[0];
    } catch (error) {
      logger.error('Error finding product:', error);
      throw error;
    }
  }

  static async create(productData) {
    try {
      const {
        name,
        description,
        price,
        storeId,
        categoryId = null,
        stock = 10,
        imageUrl = null,
        currency = 'USD',
      } = productData;

      const connection = await pool.getConnection();
      const [result] = await connection.execute(
        `INSERT INTO products 
         (name, description, price, store_id, category_id, stock, image_url, currency, status, created_at) 
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, NOW())`,
        [name, description, price, storeId, categoryId, stock, imageUrl, currency, 'pending']
      );
      connection.release();

      return { id: result.insertId, ...productData, status: 'pending' };
    } catch (error) {
      logger.error('Error creating product:', error);
      throw error;
    }
  }

  static async update(id, productData) {
    try {
      const updates = [];
      const values = [];

      Object.entries(productData).forEach(([key, value]) => {
        if (value !== undefined && value !== null) {
          updates.push(`${this.camelToSnake(key)} = ?`);
          values.push(value);
        }
      });

      if (updates.length === 0) return null;

      values.push(id);

      const connection = await pool.getConnection();
      await connection.execute(
        `UPDATE products SET ${updates.join(', ')} WHERE id = ?`,
        values
      );
      connection.release();

      return { id, ...productData };
    } catch (error) {
      logger.error('Error updating product:', error);
      throw error;
    }
  }

  static async delete(id) {
    try {
      const connection = await pool.getConnection();
      
      // First, delete all order items that reference this product
      await connection.execute(
        'DELETE FROM order_items WHERE product_id = ?',
        [id]
      );
      
      // Then delete the product itself
      await connection.execute(
        'DELETE FROM products WHERE id = ?',
        [id]
      );
      
      connection.release();
      return true;
    } catch (error) {
      logger.error('Error deleting product:', error);
      throw error;
    }
  }

  // ==================== ADMIN METHODS ====================

  static async findByStatus(status, page = 1, limit = 100) {
    try {
      const offset = (page - 1) * limit;
      const connection = await pool.getConnection();

      // Join with stores table and categories to get store email, phone, and category info
      const query = `
        SELECT 
          p.id,
          p.name,
          p.description,
          p.price,
          p.currency,
          p.stock,
          p.image_url,
          p.status,
          p.created_at,
          p.store_id,
          p.category_id,
          s.name as store_name,
          s.phone as store_phone,
          COALESCE(u.email, s.email) as owner_email,
          c.name as category_name
        FROM products p
        LEFT JOIN stores s ON p.store_id = s.id
        LEFT JOIN users u ON s.owner_uid = u.uid
        LEFT JOIN categories c ON p.category_id = c.id
        WHERE p.status = ?
        ORDER BY p.created_at DESC
        LIMIT ${parseInt(limit)} OFFSET ${parseInt(offset)}
      `;

      const [rows] = await connection.execute(query, [status]);
      connection.release();

      return rows;
    } catch (error) {
      logger.error('Error finding products by status:', error);
      throw error;
    }
  }

  //  NEW: Find products by store owner email
  static async findByOwnerEmail(email, page = 1, limit = 50) {
    try {
      const offset = (page - 1) * limit;
      const connection = await pool.getConnection();

      const query = `
        SELECT 
          p.id,
          p.name,
          p.description,
          p.price,
          p.currency,
          p.stock,
          p.image_url,
          p.video_url,
          p.status,
          p.created_at,
          p.updated_at,
          p.store_id,
          s.name as store_name,
          s.phone as store_phone,
          COALESCE(u.email, s.email) as owner_email
        FROM products p
        LEFT JOIN stores s ON p.store_id = s.id
        LEFT JOIN users u ON s.owner_uid = u.uid
        WHERE u.email = ?
        ORDER BY p.created_at DESC
        LIMIT ${parseInt(limit)} OFFSET ${parseInt(offset)}
      `;

      const [rows] = await connection.execute(query, [email]);
      connection.release();

      // Ensure image_url is a full URL
      const baseUrl = process.env.BASE_URL || 'http://192.168.1.59:3000';
      rows.forEach(row => {
        if (row.image_url && typeof row.image_url === 'string' && !row.image_url.startsWith('http')) {
          row.image_url = baseUrl + row.image_url;
        }
        // Ensure store_phone is never undefined
        if (row.store_phone === undefined || row.store_phone === null) {
          row.store_phone = '';
        }
      });

      logger.info(`Found ${rows.length} products for email: ${email}`);
      return rows;
    } catch (error) {
      logger.error('Error finding products by owner email:', error);
      throw error;
    }
  }

  static async updateStatus(id, status) {
    try {
      const connection = await pool.getConnection();
      //  Update status AND is_active based on status
      // If approved → is_active = 1 (visible)
      // If pending/rejected → is_active = 0 (hidden from public view)
      const isActive = status === 'approved' ? 1 : 0;
      
      await connection.execute(
        'UPDATE products SET status = ?, is_active = ?, updated_at = NOW() WHERE id = ?',
        [status, isActive, id]
      );
      connection.release();

      return this.findById(id);
    } catch (error) {
      logger.error('Error updating product status:', error);
      throw error;
    }
  }

  static camelToSnake(str) {
    return str.replace(/[A-Z]/g, (letter) => `_${letter.toLowerCase()}`);
  }
}

export default Product;