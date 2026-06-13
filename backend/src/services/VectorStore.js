// VectorStore.js — MySQL-backed vector storage with in-memory caching
import pool from '../config/database.js';
import logger from '../config/logger.js';
import { EmbeddingPipeline } from './EmbeddingPipeline.js';
import { ImageEmbeddingService } from './ImageEmbeddingService.js';
import { UserProfileService } from './UserProfileService.js';

export class VectorStore {
  // Query embedding cache: normalized_query → { vector: float[], ts: number }
  static queryCache = new Map();
  static QUERY_CACHE_TTL_MS = 10 * 60 * 1000; // 10 min
  static MAX_QUERY_CACHE = 1000;

  // ─── Query Embedding (with cache) ────────────────────────────────────────────

  static async getQueryVector(query) {
    const key = String(query || '').toLowerCase().trim();
    if (!key) return null;

    const cached = this.queryCache.get(key);
    if (cached && (Date.now() - cached.ts) < this.QUERY_CACHE_TTL_MS) {
      return cached.vector;
    }

    const vector = await EmbeddingPipeline.embedText(query);
    this.queryCache.set(key, { vector, ts: Date.now() });

    // LRU eviction
    if (this.queryCache.size > this.MAX_QUERY_CACHE) {
      const oldest = this.queryCache.keys().next().value;
      if (oldest) this.queryCache.delete(oldest);
    }

    return vector;
  }

  // ─── Load product embeddings from DB ─────────────────────────────────────────

  // Returns Map<productId, { text: float[], image: float[] | null }>
  static async loadForProducts(productIds) {
    if (!productIds?.length) return new Map();

    const ids = [...new Set(productIds.map(id => Number(id)))];
    const connection = await pool.getConnection();
    try {
      const placeholders = ids.map(() => '?').join(',');
      const [rows] = await connection.execute(
        `SELECT product_id, embedding, image_embedding
         FROM product_embeddings
         WHERE product_id IN (${placeholders})`,
        ids,
      );

      const map = new Map();
      for (const row of rows) {
        const text = EmbeddingPipeline.stringToVector(row.embedding);
        if (!text) continue;
        const image = row.image_embedding
          ? EmbeddingPipeline.stringToVector(row.image_embedding)
          : null;
        map.set(Number(row.product_id), { text, image });
      }
      return map;
    } finally {
      connection.release();
    }
  }

  // ─── Blend two unit vectors (linear combination + normalize) ─────────────────

  static blendVectors(a, b, weightA, weightB) {
    if (!a?.length || !b?.length || a.length !== b.length) return a || b || [];
    const result = new Array(a.length);
    let norm = 0;
    for (let i = 0; i < a.length; i++) {
      result[i] = weightA * a[i] + weightB * b[i];
      norm += result[i] * result[i];
    }
    const mag = Math.sqrt(norm);
    if (mag > 0) {
      for (let i = 0; i < result.length; i++) result[i] /= mag;
    }
    return result;
  }

  // ─── Semantic Search (base) ───────────────────────────────────────────────────
  // Plain semantic search with no personalization. Used internally.

  static async search(query, products, topK = 20) {
    return this.personalizedSearch(query, products, { userId: null, topK });
  }

  // ─── Personalized Search ──────────────────────────────────────────────────────
  // Core method. Blends user taste vector into the query vector so the search
  // leans toward what this user historically liked.
  //
  // searchVector = 70% query intent + 30% user taste
  //
  // For new users (no taste vector yet): behaves identically to plain search.
  // For returning users: results are biased toward their history.

  static async personalizedSearch(query, products, { userId = null, topK = 20 } = {}) {
    if (!EmbeddingPipeline.isAvailable() || !products?.length) {
      return products.map(p => ({ ...p, semanticScore: 0 }));
    }

    try {
      const queryVector = await this.getQueryVector(query);
      if (!queryVector?.length) {
        logger.warn('[VectorStore] getQueryVector returned null — skipping semantic');
        return products.map(p => ({ ...p, semanticScore: 0 }));
      }

      // Personalize query vector with user taste (gracefully degrades if no profile)
      let searchVector = queryVector;
      let personalized = false;
      if (userId) {
        try {
          const tasteVector = await UserProfileService.getTasteVector(userId);
          if (tasteVector?.length === queryVector.length) {
            searchVector = this.blendVectors(queryVector, tasteVector, 0.70, 0.30);
            personalized = true;
          }
        } catch {
          // Non-fatal — use plain query vector
        }
      }

      const productIds = products.map(p => Number(p.id));
      const embeddingMap = await this.loadForProducts(productIds);

      const missing = productIds.filter(id => !embeddingMap.has(id));
      if (missing.length > 0) {
        setImmediate(() => this._backfillSpecific(missing));
      }

      const withImage = [...embeddingMap.values()].filter(e => e.image).length;
      logger.info(
        `[VectorStore] ${personalized ? 'personalized' : 'semantic'} | ` +
        `query="${String(query).substring(0, 60)}" | userId=${userId || 'none'} | ` +
        `products=${products.length} | embedded=${embeddingMap.size} | withImage=${withImage}`,
      );

      const scored = products.map(product => {
        const entry = embeddingMap.get(Number(product.id));
        if (!entry) return { ...product, semanticScore: 0 };

        const textScore = EmbeddingPipeline.cosineSimilarity(searchVector, entry.text);

        // Image re-ranking: 70% text + 30% image (degrades to 100% text if no image embedding)
        const semanticScore = entry.image
          ? 0.70 * textScore + 0.30 * EmbeddingPipeline.cosineSimilarity(searchVector, entry.image)
          : textScore;

        return { ...product, semanticScore };
      });

      scored.sort((a, b) => b.semanticScore - a.semanticScore || b.stock - a.stock || b.id - a.id);
      return scored.slice(0, topK);
    } catch (err) {
      logger.error(`[VectorStore] personalizedSearch error: ${err?.stack || err?.message || String(err)}`);
      return products.map(p => ({ ...p, semanticScore: 0 }));
    }
  }

  // ─── Upsert a single product embedding ───────────────────────────────────────

  static async upsertEmbedding(productId, textVector, imageVector = null) {
    const connection = await pool.getConnection();
    try {
      await connection.execute(
        `INSERT INTO product_embeddings
           (product_id, embedding, model, image_embedding, image_model, updated_at)
         VALUES (?, ?, ?, ?, ?, NOW())
         ON DUPLICATE KEY UPDATE
           embedding       = VALUES(embedding),
           model           = VALUES(model),
           image_embedding = COALESCE(VALUES(image_embedding), image_embedding),
           image_model     = COALESCE(VALUES(image_model), image_model),
           updated_at      = NOW()`,
        [
          Number(productId),
          EmbeddingPipeline.vectorToString(textVector),
          EmbeddingPipeline.EMBEDDING_MODEL,
          imageVector ? EmbeddingPipeline.vectorToString(imageVector) : null,
          imageVector ? ImageEmbeddingService.VISION_MODEL : null,
        ],
      );
    } finally {
      connection.release();
    }
  }

  // ─── Embed a product and persist ─────────────────────────────────────────────
  // includeImage=false during bulk backfill to avoid vision API rate limits.
  // includeImage=true (default) for single-product approval events.

  static async embedAndStore(product, { includeImage = true } = {}) {
    if (!EmbeddingPipeline.isAvailable()) return false;
    try {
      // Text embedding (always) — RETRIEVAL_DOCUMENT for indexed content
      const textDoc = EmbeddingPipeline.buildProductDocument(product);
      const textVector = await EmbeddingPipeline.embedText(textDoc, 'RETRIEVAL_DOCUMENT');

      // Image embedding — only when explicitly requested (single-product path)
      const imageVector = includeImage ? await ImageEmbeddingService.embedImage(product) : null;

      await this.upsertEmbedding(product.id, textVector, imageVector);
      logger.info(
        `[VectorStore] stored embeddings for product ${product.id}: "${product.name}"` +
        (imageVector ? ' [text+image]' : ' [text only]'),
      );
      return true;
    } catch (err) {
      logger.warn(`[VectorStore] embedAndStore failed for product ${product.id}: ${err.message}`);
      return false;
    }
  }

  // ─── Embed by product ID (loads full data from DB including store info) ─────────
  // Use this instead of embedAndStore when you only have the product ID,
  // so the embedding includes store_type and store_name for richer semantics.
  // Silently skips non-approved or inactive products.

  static async embedAndStoreById(productId) {
    if (!EmbeddingPipeline.isAvailable()) return false;

    const connection = await pool.getConnection();
    let row;
    try {
      const [[result]] = await connection.execute(
        `SELECT p.id, p.name, COALESCE(p.description, '') AS description,
                p.price, p.currency, p.image_url,
                s.store_type, s.name AS store_name
         FROM products p
         JOIN stores s ON p.store_id = s.id
         WHERE p.id = ?
           AND p.status = 'approved'
           AND p.is_active = 1
           AND p.stock > 0
           AND s.status = 'approved'`,
        [Number(productId)],
      );
      row = result;
    } finally {
      connection.release();
    }

    if (!row) {
      logger.debug(`[VectorStore] embedAndStoreById: product ${productId} not eligible (inactive/unapproved/no stock)`);
      return false;
    }

    return this.embedAndStore(row);
  }

  // ─── Delete a product's embedding (call when product is deleted/deactivated) ───

  static async deleteEmbedding(productId) {
    const connection = await pool.getConnection();
    try {
      await connection.execute(
        'DELETE FROM product_embeddings WHERE product_id = ?',
        [Number(productId)],
      );
      logger.debug(`[VectorStore] deleted embedding for product ${productId}`);
    } finally {
      connection.release();
    }
  }

  // ─── Backfill: embed products that are missing embeddings ─────────────────────
  // Called once on server startup (non-blocking, runs in background).

  static async backfillMissing() {
    if (!EmbeddingPipeline.isAvailable()) {
      logger.warn('[VectorStore] Backfill skipped — EmbeddingPipeline unavailable');
      return;
    }

    const connection = await pool.getConnection();
    let rows;
    try {
      const [result] = await connection.execute(`
        SELECT p.id, p.name, COALESCE(p.description, '') AS description,
               p.price, p.currency, p.image_url, s.store_type, s.name AS store_name
        FROM products p
        JOIN stores s ON p.store_id = s.id
        LEFT JOIN product_embeddings pe ON pe.product_id = p.id
        WHERE p.status = 'approved'
          AND p.is_active = 1
          AND s.status = 'approved'
          AND pe.product_id IS NULL
        LIMIT 300
      `);
      rows = result;
    } finally {
      connection.release();
    }

    if (!rows.length) {
      logger.info('[VectorStore] Backfill: all approved products already have embeddings ✅');
      return;
    }

    logger.info(`[VectorStore] Backfill: embedding ${rows.length} products...`);
    let success = 0;
    for (const product of rows) {
      const ok = await this.embedAndStore(product, { includeImage: false });
      if (ok) success++;
      await new Promise(r => setTimeout(r, 80)); // gentle rate limiting
    }
    logger.info(`[VectorStore] Backfill complete: ${success}/${rows.length} products embedded`);

    // If there are still more to process, schedule next batch
    if (success === rows.length && rows.length === 300) {
      logger.info('[VectorStore] Scheduling next backfill batch in 30s...');
      setTimeout(() => this.backfillMissing(), 30_000);
    }
  }

  // ─── Background backfill for specific product IDs ────────────────────────────

  static async _backfillSpecific(productIds) {
    if (!EmbeddingPipeline.isAvailable() || !productIds?.length) return;

    const connection = await pool.getConnection();
    let rows;
    try {
      const placeholders = productIds.map(() => '?').join(',');
      const [result] = await connection.execute(
        `SELECT p.id, p.name, COALESCE(p.description, '') AS description,
                p.price, p.currency, p.image_url, s.store_type, s.name AS store_name
         FROM products p
         JOIN stores s ON p.store_id = s.id
         WHERE p.id IN (${placeholders})
           AND p.status = 'approved' AND p.is_active = 1 AND s.status = 'approved'`,
        productIds,
      );
      rows = result;
    } catch {
      return;
    } finally {
      connection.release();
    }

    for (const product of rows) {
      await this.embedAndStore(product, { includeImage: false });
      await new Promise(r => setTimeout(r, 100));
    }
  }

  // ─── Backfill image embeddings for products that only have text embeddings ────
  // Run this after backfillMissing() to add image vectors to existing text-only rows.
  // Uses a slow 2s delay to stay under Gemini Vision free-tier rate limits.

  static async backfillImages(limit = 50) {
    if (!EmbeddingPipeline.isAvailable()) {
      logger.warn('[VectorStore] Image backfill skipped — EmbeddingPipeline unavailable');
      return;
    }

    const safeLimit = Math.max(1, Math.min(200, Number(limit) || 50));
    let rows = [];

    const connection = await pool.getConnection();
    try {
      const [result] = await connection.query(`
        SELECT p.id, p.name, COALESCE(p.description, '') AS description,
               p.price, p.currency, p.image_url, s.store_type, s.name AS store_name
        FROM products p
        JOIN stores s ON p.store_id = s.id
        JOIN product_embeddings pe ON pe.product_id = p.id
        WHERE p.status = 'approved'
          AND p.is_active = 1
          AND s.status = 'approved'
          AND p.image_url IS NOT NULL
          AND p.image_url != ''
          AND pe.image_embedding IS NULL
        LIMIT ${safeLimit}
      `);
      rows = result ?? [];
    } catch (dbErr) {
      logger.error(`[VectorStore] Image backfill DB query failed: ${dbErr?.message || String(dbErr)}`);
      return;
    } finally {
      connection.release();
    }

    if (!rows.length) {
      logger.info('[VectorStore] Image backfill: all products already have image embeddings ✅');
      return;
    }

    logger.info(`[VectorStore] Image backfill: adding image vectors to ${rows.length} products...`);
    let success = 0;
    for (const product of rows) {
      try {
        const ok = await this.embedAndStore(product, { includeImage: true });
        if (ok) success++;
      } catch (err) {
        logger.warn(`[VectorStore] Image backfill: product ${product.id} failed — ${err?.message || String(err)}`);
      }
      await new Promise(r => setTimeout(r, 4000)); // 4s delay — Groq Vision free tier: ~15 RPM safe zone
    }
    logger.info(`[VectorStore] Image backfill complete: ${success}/${rows.length} products updated`);

    if (rows.length === safeLimit) {
      logger.info('[VectorStore] Scheduling next image backfill batch in 60s...');
      setTimeout(() => this.backfillImages(safeLimit), 60_000);
    }
  }

  // ─── Invalidate query cache (e.g., when products change significantly) ────────

  static clearQueryCache() {
    this.queryCache.clear();
  }
}
