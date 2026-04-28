import pool from '../config/database.js';
import logger from '../config/logger.js';

/**
 * Store Model
 */
export class Store {
  /**
   * جلب المتاجر حسب النوع (store_type) و status = 'approved'
   */
  static async findByType(type, page = 1, limit = 20) {
    try {
      const offset = (page - 1) * limit;
      const connection = await pool.getConnection();
      
      //  استخدم template literals للـ LIMIT و OFFSET بدل placeholders
      const [rows] = await connection.execute(
        `SELECT 
          s.*,
          COALESCE(NULLIF(u.email, ''), s.email) as email
        FROM stores s
        LEFT JOIN users u ON s.owner_uid = u.uid
        WHERE s.status = 'approved' AND LOWER(s.store_type) = LOWER(?)
        ORDER BY s.created_at DESC 
        LIMIT ${parseInt(limit)} OFFSET ${parseInt(offset)}`,
        [type]
      );
      
      connection.release();
      return rows;
    } catch (error) {
      logger.error('Error fetching stores by type:', error);
      throw error;
    }
  }

  static async findAll(page = 1, limit = 20) {
    try {
      const offset = (page - 1) * limit;
      const connection = await pool.getConnection();
      const [rows] = await connection.execute(
        `SELECT 
          s.*,
          COALESCE(NULLIF(u.email, ''), s.email) as email
        FROM stores s
        LEFT JOIN users u ON s.owner_uid = u.uid
        WHERE s.status = 'approved' 
        ORDER BY s.created_at DESC 
        LIMIT ${parseInt(limit)} OFFSET ${parseInt(offset)}`
      );
      connection.release();
      return rows;
    } catch (error) {
      logger.error('Error fetching stores:', error);
      throw error;
    }
  }

  static async findById(id) {
    try {
      const connection = await pool.getConnection();
      const [rows] = await connection.execute(
        `SELECT 
          s.*,
          COALESCE(NULLIF(u.email, ''), s.email) as email
        FROM stores s
        LEFT JOIN users u ON s.owner_uid = u.uid
        WHERE s.id = ?`,
        [id]
      );
      connection.release();
      return rows[0];
    } catch (error) {
      logger.error('Error finding store:', error);
      throw error;
    }
  }

  static async findByOwnerUid(ownerUid) {
    try {
      const connection = await pool.getConnection();
      const [rows] = await connection.execute(
        `SELECT 
          s.*,
          COALESCE(NULLIF(u.email, ''), s.email) as email
        FROM stores s
        LEFT JOIN users u ON s.uid = u.uid
        WHERE s.uid = ?
        LIMIT 1`,
        [ownerUid]
      );
      connection.release();
      return rows[0];
    } catch (error) {
      logger.error('Error finding store by owner:', error);
      throw error;
    }
  }

  static async findByOwnerEmail(email) {
    try {
      const connection = await pool.getConnection();
      const [rows] = await connection.execute(
        `SELECT 
          s.*, 
          COALESCE(NULLIF(u.email, ''), s.email) as email
         FROM stores s
         LEFT JOIN users u ON s.owner_uid = u.uid
         WHERE LOWER(COALESCE(NULLIF(u.email, ''), s.email)) = LOWER(?)
         LIMIT 1`,
        [email]
      );
      connection.release();
      return rows[0];
    } catch (error) {
      logger.error('Error finding store by owner email:', error);
      throw error;
    }
  }

  static async create(storeData) {
    try {
      const {
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
      } = storeData;

      // Debug logging
      logger.info('Store.create called with:', {
        name,
        description,
        phone,
        address,
        latitude,
        longitude,
        iconUrl,
        ownerUid,
        storeType,
        ownerUidType: typeof ownerUid,
        email,
      });

      if (!ownerUid) {
        logger.error('Store.create: ownerUid is missing or falsy', { ownerUid });
        throw new Error('ownerUid is required');
      }

      const connection = await pool.getConnection();

      //  أضف أو حدّث المستخدم بأمر واحد (لا يسبب خطأ duplicate)
      await connection.execute(
        `INSERT INTO users (uid, email, name) 
         VALUES (?, ?, ?) 
         ON DUPLICATE KEY UPDATE 
         email = IF(VALUES(email) != '', VALUES(email), email),
         name = IF(VALUES(name) != '', VALUES(name), name)`,
        [ownerUid, email || '', name || '']
      );
      logger.info(` User synced: ${ownerUid}`);

      //  أنشئ المتجر (status = 'pending')
      const [result] = await connection.execute(
        `INSERT INTO stores 
        (name, description, phone, address, latitude, longitude, icon_url, owner_uid, store_type, email, created_at, status) 
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW(), 'pending')`,
        [name || null, description || null, phone || null, address || null, latitude || 0, longitude || 0, iconUrl || null, ownerUid, storeType || null, email || null]
      );
      
      connection.release();
      logger.info(` Store created with id: ${result.insertId}`);

      return { id: result.insertId, ...storeData };
    } catch (error) {
      logger.error('Error creating store:', error);
      throw error;
    }
  }

  static async update(id, storeData) {
    try {
      const updates = [];
      const values = [];

      Object.entries(storeData).forEach(([key, value]) => {
        if (value !== undefined && value !== null) {
          updates.push(`${this.camelToSnake(key)} = ?`);
          values.push(value);
        }
      });

      if (updates.length === 0) return null;

      values.push(id);

      const connection = await pool.getConnection();
      await connection.execute(
        `UPDATE stores SET ${updates.join(', ')} WHERE id = ?`,
        values
      );
      connection.release();

      return { id, ...storeData };
    } catch (error) {
      logger.error('Error updating store:', error);
      throw error;
    }
  }

  static async delete(id) {
    try {
      const connection = await pool.getConnection();
      await connection.execute(
        'UPDATE stores SET status = ? WHERE id = ?',
        ['suspended', id]
      );
      connection.release();
      return true;
    } catch (error) {
      logger.error('Error deleting store:', error);
      throw error;
    }
  }

  // جلب المتاجر المعلقة (pending/suspended) - كل اللي ليست approved
  static async findPending() {
    try {
      const connection = await pool.getConnection();
      const [rows] = await connection.execute(
        `SELECT SQL_NO_CACHE
          s.*,
          COALESCE(NULLIF(u.email, ''), s.email) as email
        FROM stores s
        LEFT JOIN users u ON s.owner_uid = u.uid
        WHERE s.status != 'approved' AND s.email_verified = 1
        ORDER BY s.created_at DESC`
      );
      connection.release();
      return rows;
    } catch (error) {
      logger.error('Error finding pending stores:', error);
      throw error;
    }
  }

  // جلب المتاجر المعتمدة (approved) - status = 'approved'
  static async findApproved() {
    try {
      const connection = await pool.getConnection();
      const [rows] = await connection.execute(
        `SELECT SQL_NO_CACHE
          s.*,
          COALESCE(NULLIF(u.email, ''), s.email) as email
        FROM stores s
        LEFT JOIN users u ON s.owner_uid = u.uid
        WHERE s.status = 'approved' AND s.email_verified = 1
        ORDER BY s.created_at DESC`
      );
      connection.release();
      return rows;
    } catch (error) {
      logger.error('Error finding approved stores:', error);
      throw error;
    }
  }

  static async hardDelete(id) {
    try {
      const connection = await pool.getConnection();
      const [result] = await connection.execute(
        'DELETE FROM stores WHERE id = ?',
        [id]
      );
      connection.release();
      return result.affectedRows > 0;
    } catch (error) {
      logger.error('Error hard deleting store:', error);
      throw error;
    }
  }

  static camelToSnake(str) {
    return str.replace(/[A-Z]/g, (letter) => `_${letter.toLowerCase()}`);
  }
}

export default Store;