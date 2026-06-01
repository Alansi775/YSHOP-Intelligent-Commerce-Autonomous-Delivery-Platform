// EmbeddingService.js
import { normalizeText, tokenize, unique } from '../utils/textProcessing.js';

export class EmbeddingService {
  static cache = new Map();

  static textToVector(text) {
    const tokens = unique(tokenize(text));
    const vector = new Map();

    for (const token of tokens) {
      const hash = token.split('').reduce((acc, char) => ((acc * 31) + char.charCodeAt(0)) >>> 0, 7);
      const bucket = hash % 128;
      vector.set(bucket, (vector.get(bucket) || 0) + 1);
    }

    return vector;
  }

  static cosineSimilarity(a, b) {
    if (!a.size || !b.size) return 0;

    let dot = 0;
    let normA = 0;
    let normB = 0;

    for (const value of a.values()) normA += value * value;
    for (const value of b.values()) normB += value * value;

    const smaller = a.size <= b.size ? a : b;
    const larger = a.size <= b.size ? b : a;

    for (const [bucket, value] of smaller.entries()) {
      dot += value * (larger.get(bucket) || 0);
    }

    if (normA === 0 || normB === 0) return 0;
    return dot / (Math.sqrt(normA) * Math.sqrt(normB));
  }

  static buildDocument(product) {
    return normalizeText([
      product.name,
      product.description,
      product.store_type,
      product.store_name,
    ].filter(Boolean).join(' '));
  }

  static embedProduct(product) {
    const key = String(product.id);
    if (this.cache.has(key)) return this.cache.get(key);

    const vector = this.textToVector(this.buildDocument(product));
    this.cache.set(key, vector);
    return vector;
  }

  static embedQuery(query) {
    return this.textToVector(query);
  }

  static async search(query, products, topK = 20) {
    const queryVector = this.embedQuery(query);
    const scored = (products || []).map(product => {
      const semanticScore = this.cosineSimilarity(queryVector, this.embedProduct(product));
      return { ...product, semanticScore };
    });

    scored.sort((a, b) => b.semanticScore - a.semanticScore || b.stock - a.stock || b.id - a.id);
    return scored.slice(0, topK);
  }

  static clearCache() {
    this.cache.clear();
  }
}
