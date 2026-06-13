// EmbeddingPipeline.js — Real semantic embeddings via Gemini REST API
//
// Model selection: tries candidates in order, permanently switches on first success.
// text-embedding-004 → supports taskType (better retrieval quality)
// embedding-001      → universal fallback, works with all Google AI Studio keys

import { GoogleGenerativeAI } from '@google/generative-ai';
import logger from '../config/logger.js';

export class EmbeddingPipeline {
  static apiKey = null;
  static client = null; // kept for ImageEmbeddingService (Gemini Vision)
  static EMBEDDING_DIM = 3072; // gemini-embedding-001 = 3072-dim
  static BASE_URL = 'https://generativelanguage.googleapis.com/v1beta/models';

  // Models tried in order; _modelIndex advances on 404 until one works
  static _models = [
    { name: 'gemini-embedding-001', taskType: true },
    { name: 'gemini-embedding-2',   taskType: true },
  ];
  static _modelIndex = 0;

  static get EMBEDDING_MODEL() {
    return this._models[this._modelIndex]?.name ?? null;
  }

  static initialize() {
    const apiKey = process.env.YSHOP_AI_API_KEY;
    if (!apiKey) {
      logger.warn('[EmbeddingPipeline] YSHOP_AI_API_KEY not set — real embeddings disabled');
      return false;
    }
    this.apiKey = apiKey;
    this.client = new GoogleGenerativeAI(apiKey); // used by ImageEmbeddingService
    logger.info('[EmbeddingPipeline] initialized — will auto-detect embedding model');
    return true;
  }

  static isAvailable() {
    return Boolean(this.apiKey);
  }

  // Build rich text document for a product
  static buildProductDocument(product) {
    return [
      product.name,
      product.description,
      product.store_type,
      product.store_name,
      product.currency,
    ]
      .filter(Boolean)
      .join(' ')
      .trim()
      .slice(0, 2000);
  }

  // Embed text → float[768] via direct REST call.
  // Tries models in priority order; on 404 permanently advances to the next candidate.
  // taskType is only sent when the current model supports it.
  static async embedText(text, taskType = 'RETRIEVAL_QUERY') {
    if (!this.apiKey) throw new Error('EmbeddingPipeline not initialized');
    const clean = String(text || '').trim().slice(0, 2000);
    if (!clean) throw new Error('embedText received empty string');

    while (this._modelIndex < this._models.length) {
      const { name, taskType: supportsTaskType } = this._models[this._modelIndex];
      const url = `${this.BASE_URL}/${name}:embedContent?key=${this.apiKey}`;
      const body = { content: { parts: [{ text: clean }] } };
      if (supportsTaskType) body.taskType = taskType;

      let response;
      try {
        response = await fetch(url, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(body),
          signal: AbortSignal.timeout(30_000),
        });
      } catch (fetchErr) {
        throw new Error(`Embedding fetch error: ${fetchErr.message}`);
      }

      // 404 = model not available for this key → try next
      if (response.status === 404) {
        logger.warn(`[EmbeddingPipeline] ${name} not available (404) — trying next model`);
        this._modelIndex++;
        continue;
      }

      if (!response.ok) {
        const errBody = await response.text().catch(() => response.statusText);
        throw new Error(`Embedding API ${response.status}: ${errBody.slice(0, 300)}`);
      }

      const data = await response.json();
      const values = data?.embedding?.values;
      if (!Array.isArray(values) || values.length === 0) {
        throw new Error('Gemini returned empty embedding');
      }

      // Log which model we settled on (only on first successful use)
      if (this._models[this._modelIndex]._confirmed !== true) {
        this._models[this._modelIndex]._confirmed = true;
        logger.info(`[EmbeddingPipeline] using model: ${name} (${values.length}-dim)`);
      }

      return values;
    }

    // Exhausted all candidates
    this.apiKey = null;
    throw new Error('[EmbeddingPipeline] No embedding model available — AI search disabled');
  }

  // Cosine similarity between two float[] vectors — range [0, 1]
  static cosineSimilarity(a, b) {
    if (!Array.isArray(a) || !Array.isArray(b) || a.length !== b.length || a.length === 0) {
      return 0;
    }
    let dot = 0;
    let normA = 0;
    let normB = 0;
    for (let i = 0; i < a.length; i++) {
      dot   += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    const denom = Math.sqrt(normA) * Math.sqrt(normB);
    return denom === 0 ? 0 : dot / denom;
  }

  static vectorToString(vector) { return JSON.stringify(vector); }

  static stringToVector(raw) {
    if (!raw) return null;
    try {
      const parsed = typeof raw === 'string' ? JSON.parse(raw) : raw;
      return Array.isArray(parsed) && parsed.length > 0 ? parsed : null;
    } catch {
      return null;
    }
  }
}

// Auto-initialize on import
if (process.env.YSHOP_AI_ENABLED !== 'false') {
  EmbeddingPipeline.initialize();
}
