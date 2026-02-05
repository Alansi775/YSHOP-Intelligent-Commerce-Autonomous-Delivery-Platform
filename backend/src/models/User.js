import pool from '../config/database.js';
import logger from '../config/logger.js';

/**
 * User Model
 */
export class User {
  static async create(userData) {
    try {
      const { uid, email, displayName, phone, name, surname } = userData;

      // If explicit name/surname not provided, try to derive from displayName
      let firstName = name || '';
      let lastName = surname || '';
      if ((firstName == null || firstName === '') && displayName) {
        const parts = displayName.trim().split(/\s+/);
        if (parts.length === 1) {
          firstName = parts[0];
        } else if (parts.length >= 2) {
          firstName = parts.slice(0, parts.length - 1).join(' ');
          lastName = parts[parts.length - 1];
        }
      }

      const connection = await pool.getConnection();
      const [result] = await connection.execute(
        `INSERT INTO users 
         (uid, email, display_name, name, surname, phone, created_at) 
         VALUES (?, ?, ?, ?, ?, ?, NOW())`,
        [uid, email || null, displayName || null, firstName || null, lastName || null, phone || null]
      );
      connection.release();

      return { id: result.insertId, ...userData };
    } catch (error) {
      logger.error('Error creating user:', error);
      throw error;
    }
  }

  static async findByUid(uid) {
    try {
      const connection = await pool.getConnection();
      const [rows] = await connection.execute(
        'SELECT * FROM users WHERE uid = ?',
        [uid]
      );
      connection.release();
      return rows[0];
    } catch (error) {
      logger.error('Error finding user by uid:', error);
      throw error;
    }
  }

  static async findById(id) {
    try {
      const connection = await pool.getConnection();
      const [rows] = await connection.execute(
        'SELECT * FROM users WHERE id = ?',
        [id]
      );
      connection.release();
      return rows[0];
    } catch (error) {
      logger.error('Error finding user by id:', error);
      throw error;
    }
  }

  static async findByEmail(email) {
    try {
      const connection = await pool.getConnection();
      const [rows] = await connection.execute(
        'SELECT * FROM users WHERE email = ?',
        [email]
      );
      connection.release();
      return rows[0];
    } catch (error) {
      logger.error('Error finding user by email:', error);
      throw error;
    }
  }

  static async update(userId, userData) {
    try {
      // 🔥 CRITICAL: userId is uid from JWT token (string like 'user_1768935031597_3j88p2h5e')
      // We need to use uid in WHERE clause, not numeric id
      const updates = [];
      const values = [];

      // 🔥 CRITICAL: Strictly validate ALL values before adding to query
      // Skip undefined, null, empty strings, and NaN values
      Object.entries(userData).forEach(([key, value]) => {
        // Skip if: undefined, null, empty string, NaN, or key is 'id' or 'uid'
        if (
          key === 'id' || 
          key === 'uid' ||
          value === undefined || 
          value === null || 
          value === '' ||
          (typeof value === 'number' && isNaN(value))
        ) {
          logger.debug(`Skipping field ${key} with value:`, value);
          return; // Skip this field
        }
        
        // Add to query only valid values
        const snakeKey = this.camelToSnake(key);
        updates.push(`${snakeKey} = ?`);
        
        // Ensure value is safe for SQL binding
        // Convert to string if it's not a number to prevent type issues
        let safeValue = value;
        if (typeof value === 'string') {
          safeValue = value.trim();
        } else if (typeof value === 'number') {
          safeValue = parseFloat(value);
        }
        
        values.push(safeValue);
        logger.debug(`Adding field ${key} (${snakeKey}) with value:`, { value, safeValue });
      });

      // If no valid fields to update, return existing data
      if (updates.length === 0) {
        logger.info('No valid fields to update, returning existing user');
        const user = await this.findByUid(userId);
        return user;
      }

      values.push(userId);

      logger.info('Executing UPDATE query:', {
        query: `UPDATE users SET ${updates.join(', ')} WHERE uid = ?`,
        valueCount: values.length,
        values: values.map(v => typeof v === 'string' ? v.substring(0, 50) : v)
      });

      const connection = await pool.getConnection();
      await connection.execute(
        `UPDATE users SET ${updates.join(', ')} WHERE uid = ?`,
        values
      );
      connection.release();

      return { id: userId, ...userData };
    } catch (error) {
      logger.error('Error updating user:', error);
      throw error;
    }
  }

  static camelToSnake(str) {
    return str.replace(/[A-Z]/g, (letter) => `_${letter.toLowerCase()}`);
  }
}

export default User;
