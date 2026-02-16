import { EventEmitter } from 'events';
import pool from '../config/database.js';
import logger from '../config/logger.js';

/**
 * 🔥 Reactive Sync Manager
 * 
 * Real-time database change detection without polling
 * - Monitors specific tables for changes
 * - Emits events to subscribed clients
 * - Uses delta updates (only changed data)
 * - Implements backpressure control
 */

class ReactiveSyncManager extends EventEmitter {
  constructor() {
    super();
    this.subscribers = new Map(); // Map<channel, Set<socketId>>
    this.lastSync = new Map(); // Map<channel, timestamp>
    this.lastHashes = new Map(); // Map<channel, hash> for backpressure
    this.SYNC_INTERVAL = 500; // 500ms check interval (न 5 دقائق!)
    this.BACKPRESSURE_MIN = 100; // Min 100ms between same updates
    this.watchers = new Map();
  }

  /**
   * ✅ Subscribe socket to data channel
   * Example: 'returns:502' for store 502 returns
   */
  subscribe(channel, socketId) {
    if (!this.subscribers.has(channel)) {
      this.subscribers.set(channel, new Set());
      logger.info(`🔔 NEW CHANNEL SUBSCRIBED`, { channel, initiator: socketId });
      this._startWatcher(channel);
    }
    
    this.subscribers.get(channel).add(socketId);
    logger.info(`✅ SOCKET SUBSCRIBED`, { channel, socketId, totalSubscribers: this.subscribers.get(channel).size });
  }

  /**
   * ❌ Unsubscribe socket from channel
   */
  unsubscribe(channel, socketId) {
    if (!this.subscribers.has(channel)) return;
    
    this.subscribers.get(channel).delete(socketId);
    const remaining = this.subscribers.get(channel).size;
    
    logger.info(`❌ SOCKET UNSUBSCRIBED`, { channel, socketId, remaining });
    
    if (remaining === 0) {
      this.subscribers.delete(channel);
      this._stopWatcher(channel);
      logger.info(`🛑 CHANNEL CLOSED - no subscribers`, { channel });
    }
  }

  /**
   * 🔍 Start watching a channel for changes
   */
  _startWatcher(channel) {
    if (this.watchers.has(channel)) {
      logger.info(`⚠️ WATCHER ALREADY STARTED`, { channel });
      return;
    }

    // Parse channel: 'returns:502' → { type: 'returns', id: '502' }
    const [type, id] = channel.split(':');
    
    logger.info(`▶️ STARTING WATCHER`, { channel, type, id });

    const checkInterval = setInterval(async () => {
      try {
        // 🔥 Check for changes without logging
        await this._checkAndEmitChanges(channel, type, id);
      } catch (error) {
        logger.error(`❌ Watcher error for ${channel}`, { error: error.message });
      }
    }, this.SYNC_INTERVAL);

    this.watchers.set(channel, checkInterval);
    logger.info(`✅ WATCHER STARTED - will check every ${this.SYNC_INTERVAL}ms`, { channel });
  }

  /**
   * ⏹️ Stop watching a channel
   */
  _stopWatcher(channel) {
    if (this.watchers.has(channel)) {
      clearInterval(this.watchers.get(channel));
      this.watchers.delete(channel);
      logger.info(`⏹️ WATCHER STOPPED`, { channel });
    }
  }

  /**
   * 🔍 Check database for changes and emit delta
   */
  async _checkAndEmitChanges(channel, type, storeId) {
    let connection;
    try {
      connection = await pool.getConnection();

      if (type === 'returns') {
        // 🔥 Store owner returns - ONLY admin_accepted=1, with order details
        // 📝 IMPORTANT: Filter in backend so frontend receives clean data
        const [returns] = await connection.execute(
          `SELECT 
             rp.*,
             o.total_price as order_total_price,
             o.currency as order_currency
           FROM returned_products rp
           LEFT JOIN orders o ON rp.order_id = o.id
           WHERE rp.store_id = ? AND rp.admin_accepted = 1
           ORDER BY rp.return_requested_at DESC 
           LIMIT 500`,
          [storeId]
        );

        const hash = JSON.stringify(returns);
        const lastHash = this.lastHashes.get(channel);
        const hashChanged = hash !== lastHash;

        if (hashChanged) {
          const lastTime = this.lastSync.get(channel) || 0;
          const now = Date.now();
          const timeSinceLastSync = now - lastTime;

          if (timeSinceLastSync >= this.BACKPRESSURE_MIN) {
            // ✅ Emit delta update to subscribers
            const subCount = this.subscribers.get(channel)?.size || 0;
            
            this._broadcastToChannel(channel, {
              type: 'returns:delta',
              channel,
              data: returns,
              timestamp: now,
              count: returns.length,
            });

            this.lastHashes.set(channel, hash);
            this.lastSync.set(channel, now);

            logger.info(`✨ DELTA EMITTED`, {
              channel,
              subscribers: subCount,
              dataRows: returns.length,
              timestamp: now,
            });
          }
        }
      }
      

      if (type === 'orders') {
        const [orders] = await connection.execute(
          `SELECT o.id, o.store_id, o.status, o.total_price, o.user_id,
           u.display_name as customerName, u.phone as customerPhone,
           o.created_at, o.updated_at 
           FROM orders o
           LEFT JOIN users u ON o.user_id = u.uid
           WHERE o.store_id = ? AND o.status != 'return'
           ORDER BY o.updated_at DESC 
           LIMIT 500`,
          [storeId]
        );

        // 🔥 GET ITEMS FOR EACH ORDER (with product images!)
        if (orders.length > 0) {
          const orderIds = orders.map(o => o.id);
          const placeholders = orderIds.map(() => '?').join(',');
          
          const [items] = await connection.execute(
            `SELECT oi.id, oi.order_id, oi.product_id, oi.quantity, oi.price, 
                    p.name as product_name, p.image_url
             FROM order_items oi
             LEFT JOIN products p ON oi.product_id = p.id
             WHERE oi.order_id IN (${placeholders})`,
            orderIds
          );
          
          // Group items by order_id
          const itemsByOrderId = {};
          for (const item of items) {
            if (!itemsByOrderId[item.order_id]) {
              itemsByOrderId[item.order_id] = [];
            }
            itemsByOrderId[item.order_id].push(item);
          }
          
          // Attach items to each order
          for (const order of orders) {
            order.items = itemsByOrderId[order.id] || [];
          }
        } else {
          orders.forEach(o => o.items = []);
        }

        // Compute hash for backpressure
        const hash = JSON.stringify(orders);
        const lastHash = this.lastHashes.get(channel);

        if (hash !== lastHash) {
          const lastTime = this.lastSync.get(channel) || 0;
          const now = Date.now();

          if (now - lastTime >= this.BACKPRESSURE_MIN) {
            this._broadcastToChannel(channel, {
              type: 'orders:delta',
              channel,
              data: orders,
              timestamp: now,
              count: orders.length,
            });

            this.lastHashes.set(channel, hash);
            this.lastSync.set(channel, now);

            logger.info(`✨ ORDERS DELTA EMITTED`, {
              channel,
              subscribers: this.subscribers.get(channel)?.size || 0,
              dataRows: orders.length,
            });
          }
        }
      }

      if (type === 'admin:returns') {
        // 🔥 ALL returns (for admin panel) - with complete data
        const [returns] = await connection.execute(
          `SELECT 
             rp.*,
             o.total_price as order_total_price,
             o.currency as order_currency,
             s.name as store_name,
             d.display_name as driver_name
           FROM returned_products rp
           LEFT JOIN orders o ON rp.order_id = o.id
           LEFT JOIN stores s ON rp.store_id = s.id
           LEFT JOIN drivers d ON rp.driver_id = d.id
           ORDER BY rp.return_requested_at DESC 
           LIMIT 1000`
        );

        const hash = JSON.stringify(returns);
        const lastHash = this.lastHashes.get(channel);
        const hashChanged = hash !== lastHash;

        if (hashChanged) {
          const lastTime = this.lastSync.get(channel) || 0;
          const now = Date.now();
          const timeSinceLastSync = now - lastTime;

          if (timeSinceLastSync >= this.BACKPRESSURE_MIN) {
            const subCount = this.subscribers.get(channel)?.size || 0;

            this._broadcastToChannel(channel, {
              type: 'admin:returns:delta',
              channel,
              data: returns,
              timestamp: now,
              count: returns.length,
            });

            this.lastHashes.set(channel, hash);
            this.lastSync.set(channel, now);

            logger.info(`✨ ADMIN RETURNS DELTA EMITTED`, {
              channel,
              subscribers: subCount,
              dataRows: returns.length,
            });
          } else {
            // Backpressure - skip this update
          }
        }
      }

      if (type === 'admin:orders') {
        // ALL orders (for admin panel)
        const [orders] = await connection.execute(
          `SELECT o.id, o.store_id, o.status, o.total_price, o.user_id,
           u.display_name as customerName, u.phone as customerPhone,
           o.created_at, o.updated_at 
           FROM orders o
           LEFT JOIN users u ON o.user_id = u.uid
           ORDER BY o.updated_at DESC 
           LIMIT 1000`
        );

        // 🔥 GET ITEMS FOR EACH ORDER (with product images!)
        if (orders.length > 0) {
          const orderIds = orders.map(o => o.id);
          const placeholders = orderIds.map(() => '?').join(',');
          
          const [items] = await connection.execute(
            `SELECT oi.id, oi.order_id, oi.product_id, oi.quantity, oi.price, 
                    p.name as product_name, p.image_url
             FROM order_items oi
             LEFT JOIN products p ON oi.product_id = p.id
             WHERE oi.order_id IN (${placeholders})`,
            orderIds
          );
          
          // Group items by order_id
          const itemsByOrderId = {};
          for (const item of items) {
            if (!itemsByOrderId[item.order_id]) {
              itemsByOrderId[item.order_id] = [];
            }
            itemsByOrderId[item.order_id].push(item);
          }
          
          // Attach items to each order
          for (const order of orders) {
            order.items = itemsByOrderId[order.id] || [];
          }
        } else {
          orders.forEach(o => o.items = []);
        }

        const hash = JSON.stringify(orders);
        const lastHash = this.lastHashes.get(channel);

        if (hash !== lastHash) {
          const lastTime = this.lastSync.get(channel) || 0;
          const now = Date.now();

          if (now - lastTime >= this.BACKPRESSURE_MIN) {
            this._broadcastToChannel(channel, {
              type: 'admin:orders:delta',
              channel,
              data: orders,
              timestamp: now,
              count: orders.length,
            });

            this.lastHashes.set(channel, hash);
            this.lastSync.set(channel, now);

            logger.info(`✨ ADMIN ORDERS DELTA EMITTED`, {
              channel,
              dataRows: orders.length,
            });
          }
        }
      }

      if (type === 'customer' && id) {
        // Customer orders (customer:orders:123)
        const [orders] = await connection.execute(
          `SELECT o.id, o.store_id, o.status, o.total_price, o.user_id,
           o.currency, o.created_at, o.updated_at 
           FROM orders o
           WHERE o.user_id = ?
           ORDER BY o.updated_at DESC 
           LIMIT 500`,
          [id]
        );

        // 🔥 GET ITEMS FOR EACH ORDER (with product images!)
        if (orders.length > 0) {
          const orderIds = orders.map(o => o.id);
          const placeholders = orderIds.map(() => '?').join(',');
          
          const [items] = await connection.execute(
            `SELECT oi.id, oi.order_id, oi.product_id, oi.quantity, oi.price, 
                    p.name as product_name, p.image_url
             FROM order_items oi
             LEFT JOIN products p ON oi.product_id = p.id
             WHERE oi.order_id IN (${placeholders})`,
            orderIds
          );
          
          // Group items by order_id
          const itemsByOrderId = {};
          for (const item of items) {
            if (!itemsByOrderId[item.order_id]) {
              itemsByOrderId[item.order_id] = [];
            }
            itemsByOrderId[item.order_id].push(item);
          }
          
          // Attach items to each order
          for (const order of orders) {
            order.items = itemsByOrderId[order.id] || [];
          }
        } else {
          orders.forEach(o => o.items = []);
        }

        const hash = JSON.stringify(orders);
        const lastHash = this.lastHashes.get(channel);

        if (hash !== lastHash) {
          const lastTime = this.lastSync.get(channel) || 0;
          const now = Date.now();

          if (now - lastTime >= this.BACKPRESSURE_MIN) {
            this._broadcastToChannel(channel, {
              type: 'customer:orders:delta',
              channel,
              data: orders,
              timestamp: now,
              count: orders.length,
            });

            this.lastHashes.set(channel, hash);
            this.lastSync.set(channel, now);

            logger.debug(`✨ CUSTOMER ORDERS DELTA EMITTED`, {
              channel,
              customerId: id,
              dataRows: orders.length,
            });
          }
        }
      }

      if (type === 'delivery' && id) {
        // Delivery requests (delivery:requests:driverId)
        const [requests] = await connection.execute(
          `SELECT id, driver_id, status, from_location, to_location, 
           order_id, created_at, updated_at 
           FROM delivery_requests 
           WHERE driver_id = ?
           ORDER BY updated_at DESC 
           LIMIT 500`,
          [id]
        );

        const hash = JSON.stringify(requests);
        const lastHash = this.lastHashes.get(channel);

        if (hash !== lastHash) {
          const lastTime = this.lastSync.get(channel) || 0;
          const now = Date.now();

          if (now - lastTime >= this.BACKPRESSURE_MIN) {
            this._broadcastToChannel(channel, {
              type: 'delivery:requests:delta',
              channel,
              data: requests,
              timestamp: now,
              count: requests.length,
            });

            this.lastHashes.set(channel, hash);
            this.lastSync.set(channel, now);

            logger.debug(`✨ DELIVERY REQUESTS DELTA EMITTED`, {
              channel,
              driverId: id,
              dataRows: requests.length,
            });
          }
        }
      }

      if (connection) connection.release();
    } catch (error) {
      logger.error(`❌ Error checking changes for ${channel}`, { error: error.message });
      if (connection) connection.release();
    }
  }

  /**
   * 📡 Broadcast message only to subscribers of this channel
   */
  _broadcastToChannel(channel, message) {
    const subscribers = this.subscribers.get(channel);
    if (!subscribers || subscribers.size === 0) return;

    // Emit to all subscribers (will connect via Socket.io)
    this.emit('broadcast', {
      channel,
      subscribers: Array.from(subscribers),
      message,
    });
  }

  /**
   * 📊 Get stats
   */
  getStats() {
    const stats = {
      activeChannels: this.subscribers.size,
      channels: {},
      totalSubscribers: 0,
    };

    for (const [channel, sockets] of this.subscribers.entries()) {
      stats.channels[channel] = sockets.size;
      stats.totalSubscribers += sockets.size;
    }

    return stats;
  }

  /**
   * 🧹 Cleanup on shutdown
   */
  cleanup() {
    for (const interval of this.watchers.values()) {
      clearInterval(interval);
    }
    this.watchers.clear();
    this.subscribers.clear();
    logger.info(`🧹 ReactiveSyncManager cleaned up`);
  }
}

export default new ReactiveSyncManager();
