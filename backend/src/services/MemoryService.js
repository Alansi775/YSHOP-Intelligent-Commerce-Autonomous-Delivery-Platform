// MemoryService.js
import logger from '../config/logger.js';

export class MemoryService {
  static conversationMemory = new Map();
  static shownProducts = new Map();
  static accessOrder = [];
  static MAX_USERS = 5000;
  static TTL_MS = 2 * 60 * 60 * 1000;

  static touch(userId) {
    const index = this.accessOrder.indexOf(userId);
    if (index >= 0) this.accessOrder.splice(index, 1);
    this.accessOrder.push(userId);

    while (this.accessOrder.length > this.MAX_USERS) {
      const evicted = this.accessOrder.shift();
      if (evicted) {
        this.conversationMemory.delete(evicted);
        this.shownProducts.delete(evicted);
      }
    }
  }

  static get(userId) {
    if (!this.conversationMemory.has(userId)) {
      this.conversationMemory.set(userId, []);
    }
    this.touch(userId);
    return this.conversationMemory.get(userId);
  }

  static add(userId, role, text) {
    const memory = this.get(userId);
    memory.push({ role, text, timestamp: Date.now() });
    if (memory.length > 20) memory.shift();
    this.touch(userId);
  }

  static getShownProducts(userId) {
    return this.shownProducts.get(userId) || [];
  }

  static setShownProducts(userId, products) {
    this.shownProducts.set(userId, products);
    this.touch(userId);
  }

  static clear(userId) {
    this.conversationMemory.delete(userId);
    this.shownProducts.delete(userId);
    const index = this.accessOrder.indexOf(userId);
    if (index >= 0) this.accessOrder.splice(index, 1);
  }

  static summarize(userId) {
    const memory = this.get(userId);
    const recent = memory.slice(-8);
    return recent.map(item => `${item.role}: ${item.text}`).join(' | ');
  }

  static updatePreferences(userId, interaction = {}) {
    const memory = this.get(userId);
    memory.preferences = {
      ...(memory.preferences || {}),
      ...interaction,
      updatedAt: Date.now(),
    };
  }

  static cleanup() {
    const cutoff = Date.now() - this.TTL_MS;
    for (const [userId, messages] of this.conversationMemory.entries()) {
      const fresh = messages.filter(message => message.timestamp > cutoff);
      if (fresh.length === 0) {
        this.conversationMemory.delete(userId);
        this.shownProducts.delete(userId);
      } else {
        this.conversationMemory.set(userId, fresh);
      }
    }

    while (this.accessOrder.length > this.MAX_USERS) {
      const evicted = this.accessOrder.shift();
      if (evicted) {
        this.conversationMemory.delete(evicted);
        this.shownProducts.delete(evicted);
      }
    }
  }
}

export function ensureMemoryCleanup(loggerInstance = logger) {
  loggerInstance?.info?.('[MemoryService] cleanup scheduled');
}
