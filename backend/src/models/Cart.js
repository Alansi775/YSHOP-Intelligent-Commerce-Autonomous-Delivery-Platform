import pool from '../config/database.js';
import logger from '../config/logger.js';
import { chargedPrice } from '../utils/pricing.js';

/**
 * Cart Model - FINAL FIX: Added missing currency field
 */
export class Cart {
  static async addItem(userId, productId, quantity) {
    let connection;
    try {
      connection = await pool.getConnection();
      
      // Start transaction
      await connection.beginTransaction();
      
      // Check if product already in cart
      const [existing] = await connection.execute(
        'SELECT * FROM cart_items WHERE user_id = ? AND product_id = ?',
        [userId, productId]
      );

      logger.info('Cart.addItem - checked existing items', { userId, productId, existingCount: existing.length });

      if (existing.length > 0) {
        // Update quantity
        logger.info('Cart.addItem - updating existing cart item', { userId, productId, addQuantity: quantity });
        await connection.execute(
          'UPDATE cart_items SET quantity = quantity + ? WHERE user_id = ? AND product_id = ?',
          [quantity, userId, productId]
        );
        logger.info('Cart.addItem - update executed', { userId, productId });
      } else {
        // Insert new item
        logger.info('Cart.addItem - inserting new cart item', { userId, productId, quantity });
        const result = await connection.execute(
          `INSERT INTO cart_items (user_id, product_id, quantity, added_at) 
           VALUES (?, ?, ?, NOW())`,
          [userId, productId, quantity]
        );
        logger.info('Cart.addItem - insert executed', { userId, productId, insertId: result[0]?.insertId });
      }

      // Commit transaction
      await connection.commit();
      logger.info('Cart.addItem - transaction committed successfully', { userId, productId });

      // Verify the insert/update is visible
      const [verification] = await connection.execute(
        'SELECT * FROM cart_items WHERE user_id = ? AND product_id = ?',
        [userId, productId]
      );
      logger.info('Cart.addItem - verification check', { 
        userId, 
        productId, 
        found: verification.length > 0,
        quantity: verification[0]?.quantity 
      });

      return true;
    } catch (error) {
      if (connection) {
        try {
          await connection.rollback();
          logger.error('Cart.addItem - transaction rolled back', { userId, productId, error: error.message });
        } catch (rollbackError) {
          logger.error('Cart.addItem - rollback failed', { error: rollbackError.message });
        }
      }
      logger.error('Error adding to cart:', error);
      throw error;
    } finally {
      if (connection) connection.release();
    }
  }

  static async getCart(userId) {
    let connection;
    try {
      connection = await pool.getConnection();
      logger.info('Cart.getCart - START', { userId });
      
      // 🔥 CRITICAL FIX: Added p.currency to SELECT
      const [items] = await connection.execute(
        `SELECT 
          ci.id,
          ci.product_id,
          ci.quantity,
          p.name,
          p.price,
          p.currency,
          p.image_url,
          p.store_id,
          p.stock,
          p.is_active,
          p.status
        FROM cart_items ci
        LEFT JOIN products p ON ci.product_id = p.id
        WHERE ci.user_id = ?
        ORDER BY ci.added_at DESC`,
        [userId]
      );

      logger.info('Cart.getCart - JOIN query success', { 
        userId, 
        itemsCount: items ? items.length : 0,
        firstItem: items && items.length > 0 ? {
          id: items[0].id,
          product_id: items[0].product_id,
          name: items[0].name,
          price: items[0].price,
          currency: items[0].currency
        } : null
      });
      
      // Check raw cart items for debugging
      const [rawItems] = await connection.execute(
        `SELECT id, user_id, product_id, quantity FROM cart_items WHERE user_id = ?`,
        [userId]
      );
      logger.info('Cart.getCart - RAW cart_items', { userId, count: rawItems ? rawItems.length : 0 });

      // Normalize types
      const normalized = (items || []).map((row) => {
        const r = { ...row };
        try {
          if (r.price !== undefined && typeof r.price === 'string') r.price = parseFloat(r.price);
          // p.price above is the store owner's raw base price straight off
          // the products table — this must match what ProductController's
          // withCustomerPrice() shows on the product/store screens, or the
          // cart displays a different number than what the customer just
          // saw. Order.create() already applies this same chargedPrice()
          // at checkout time, so this only fixes the *display* mismatch.
          r.price = chargedPrice(r.price, { isLocal: false });
        } catch (e) {
          // ignore
        }
        try {
          if (r.stock !== undefined && typeof r.stock !== 'number') r.stock = parseInt(r.stock, 10) || 0;
        } catch (e) {}
        
        // Ensure currency exists with fallback
        if (!r.currency) r.currency = 'TRY';
        
        return r;
      });

      logger.info('Cart.getCart - COMPLETE', { 
        userId, 
        count: normalized.length,
        normalizedFirstItem: normalized.length > 0 ? {
          id: normalized[0].id,
          name: normalized[0].name,
          price: normalized[0].price,
          currency: normalized[0].currency
        } : null
      });
      
      return normalized;
    } catch (error) {
      logger.error('Cart.getCart - ERROR', { userId, error: error.message, stack: error.stack });
      throw error;
    } finally {
      if (connection) connection.release();
    }
  }

  static async removeItem(userId, cartItemId) {
    let connection;
    try {
      connection = await pool.getConnection();
      logger.info('Cart.removeItem - START', { userId, cartItemId });
      
      // Start transaction
      await connection.beginTransaction();
      
      // Hard delete - remove completely from database
      const result = await connection.execute(
        'DELETE FROM cart_items WHERE id = ? AND user_id = ?',
        [cartItemId, userId]
      );
      
      logger.info('Cart.removeItem - DELETE executed', { 
        userId, 
        cartItemId, 
        affectedRows: result[0]?.affectedRows 
      });
      
      // Commit and verify
      await connection.commit();
      logger.info('Cart.removeItem - transaction committed successfully', { userId, cartItemId });
      
      // Verify deletion
      const [verification] = await connection.execute(
        'SELECT * FROM cart_items WHERE id = ? AND user_id = ?',
        [cartItemId, userId]
      );
      logger.info('Cart.removeItem - verification check', { 
        userId, 
        cartItemId,
        stillExists: verification.length > 0
      });
      
      return true;
    } catch (error) {
      if (connection) {
        try {
          await connection.rollback();
          logger.error('Cart.removeItem - transaction rolled back', { userId, cartItemId });
        } catch (rollbackError) {
          logger.error('Cart.removeItem - rollback failed', { error: rollbackError.message });
        }
      }
      logger.error('Error removing from cart:', error);
      throw error;
    } finally {
      if (connection) connection.release();
    }
  }

  static async updateQuantity(userId, cartItemId, quantity) {
    let connection;
    try {
      if (quantity <= 0) {
        return this.removeItem(userId, cartItemId);
      }

      connection = await pool.getConnection();
      
      // Start transaction
      await connection.beginTransaction();
      
      await connection.execute(
        'UPDATE cart_items SET quantity = ? WHERE id = ? AND user_id = ?',
        [quantity, cartItemId, userId]
      );
      
      // Commit and verify
      await connection.commit();
      logger.info('Cart.updateQuantity - transaction committed successfully', { userId, cartItemId, quantity });
      
      // Verify update
      const [verification] = await connection.execute(
        'SELECT quantity FROM cart_items WHERE id = ? AND user_id = ?',
        [cartItemId, userId]
      );
      logger.info('Cart.updateQuantity - verification check', { 
        userId, 
        cartItemId,
        expectedQuantity: quantity,
        actualQuantity: verification[0]?.quantity
      });
      
      return true;
    } catch (error) {
      if (connection) {
        try {
          await connection.rollback();
          logger.error('Cart.updateQuantity - transaction rolled back', { userId, cartItemId });
        } catch (rollbackError) {
          logger.error('Cart.updateQuantity - rollback failed', { error: rollbackError.message });
        }
      }
      logger.error('Error updating cart quantity:', error);
      throw error;
    } finally {
      if (connection) connection.release();
    }
  }

  static async clearCart(userId) {
    let connection;
    try {
      connection = await pool.getConnection();
      
      // Start transaction
      await connection.beginTransaction();
      
      // Hard delete - remove all cart items completely from database
      const result = await connection.execute(
        'DELETE FROM cart_items WHERE user_id = ?',
        [userId]
      );
      
      logger.info('Cart.clearCart - DELETE executed', { 
        userId, 
        affectedRows: result[0]?.affectedRows 
      });
      
      // Commit and verify
      await connection.commit();
      logger.info('Cart.clearCart - transaction committed successfully', { userId });
      
      // Verify clear
      const [verification] = await connection.execute(
        'SELECT COUNT(*) as count FROM cart_items WHERE user_id = ?',
        [userId]
      );
      logger.info('Cart.clearCart - verification check', { 
        userId,
        remainingItems: verification[0]?.count
      });
      
      return true;
    } catch (error) {
      if (connection) {
        try {
          await connection.rollback();
          logger.error('Cart.clearCart - transaction rolled back', { userId });
        } catch (rollbackError) {
          logger.error('Cart.clearCart - rollback failed', { error: rollbackError.message });
        }
      }
      logger.error('Error clearing cart:', error);
      throw error;
    } finally {
      if (connection) connection.release();
    }
  }
}

export default Cart;