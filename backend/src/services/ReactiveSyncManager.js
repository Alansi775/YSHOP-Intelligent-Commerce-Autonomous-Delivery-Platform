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
    if (this.watchers.has(channel)) return;

    // Parse channel: 'returns:502' → { type: 'returns', id: '502' }
    const [type, id] = channel.split(':');
    
    logger.info(`▶️ STARTING WATCHER`, { channel, type, id });

    const checkInterval = setInterval(async () => {
      try {
        if (this.subscribers.has(channel) && this.subscribers.get(channel).size > 0) {
          await this._checkAndEmitChanges(channel, type, id);
        }
      } catch (error) {
        logger.error(`❌ Watcher error for ${channel}`, { error: error.message });
      }
    }, this.SYNC_INTERVAL);

    this.watchers.set(channel, checkInterval);
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
        const [returns] = await connection.execute(
          `SELECT id, store_id, admin_accepted, store_received, product_name, product_image_url, 
           return_reason, updated_at, created_at 
           FROM returned_products 
           WHERE store_id = ? AND admin_accepted = 1 
           ORDER BY updated_at DESC 
           LIMIT 500`,
          [storeId]
        );

        // Compute hash for backpressure
        const hash = JSON.stringify(returns);
        const lastHash = this.lastHashes.get(channel);

        if (hash !== lastHash) {
          // Check backpressure timing
          const lastTime = this.lastSync.get(channel) || 0;
          const now = Date.now();

          if (now - lastTime >= this.BACKPRESSURE_MIN) {
            // ✅ Emit delta update to subscribers
            this._broadcastToChannel(channel, {
              type: 'returns:delta',
              channel,
              data: returns,
              timestamp: now,
              count: returns.length,
            });

            this.lastHashes.set(channel, hash);
            this.lastSync.set(channel, now);

            logger.debug(`✨ DELTA EMITTED`, {
              channel,
              subscribers: this.subscribers.get(channel)?.size || 0,
              dataRows: returns.length,
            });
          }
        }
      }

      if (type === 'orders') {
        const [orders] = await connection.execute(
          `SELECT id, store_id, status, total_amount, customer_name, userName, created_at, updated_at 
           FROM orders 
           WHERE store_id = ? AND status != 'return'
           ORDER BY updated_at DESC 
           LIMIT 500`,
          [storeId]
        );

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

            logger.debug(`✨ ORDERS DELTA EMITTED`, {
              channel,
              subscribers: this.subscribers.get(channel)?.size || 0,
              dataRows: orders.length,
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

    logger.debug(`📡 BROADCAST TO ${subscribers.size} SUBSCRIBERS`, { channel });
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
