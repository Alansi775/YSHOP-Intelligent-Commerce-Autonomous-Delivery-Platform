// ProductRetrievalService.js
import pool from '../config/database.js';
import logger from '../config/logger.js';
import { IRetrievalService } from './IRetrievalService.js';
import { VectorStore } from './VectorStore.js';
import { EmbeddingPipeline } from './EmbeddingPipeline.js';
import { normalizeText, tokenize, unique } from '../utils/textProcessing.js';

export class ProductRetrievalService extends IRetrievalService {
  static cache = new Map();
  static CACHE_TTL_MS = 2 * 60 * 1000;
  static MAX_CANDIDATES = 250;

  static storeTypeSynonyms = {
    Food:     ['food', 'meal', 'eat', 'eating', 'burger', 'pizza', 'chicken', 'drink', 'drinks', 'soda', 'water', 'juice', 'snack', 'breakfast', 'lunch', 'dinner', 'restaurant', 'مطعم', 'اكل', 'طعام', 'وجبة', 'برجر', 'بيتزا', 'دجاج', 'عصير', 'ماء', 'سناك'],
    Pharmacy: ['pharmacy', 'medicine', 'medication', 'health', 'sick', 'pain', 'pill', 'tablet', 'vitamin', 'dose', 'دواء', 'صيدلية', 'صحة', 'مريض', 'حبة', 'فيتامين', 'صداع'],
    Clothes:  ['clothes', 'clothing', 'shirt', 'dress', 'shoes', 'fashion', 'jacket', 'wear', 'outfit', 'ملابس', 'قميص', 'فستان', 'حذاء', 'موضة'],
    Market:   ['market', 'grocery', 'vegetable', 'fruit', 'fresh', 'groceries', 'supermarket', 'خضار', 'فاكهة', 'سوق', 'بقال', 'تموينات'],
  };

  static getStoreTypeKey(storeType) { return storeType || '__all__'; }
  static getCacheEntry(storeType)   { return this.cache.get(this.getStoreTypeKey(storeType)) || null; }
  static setCacheEntry(storeType, entry) { this.cache.set(this.getStoreTypeKey(storeType), entry); }

  static normalizeText(text) { return normalizeText(text); }
  static tokenize(text)      { return tokenize(text); }

  static buildDocument(product) {
    return [product.name, product.description, product.store_name, product.store_type, product.currency, product.price]
      .filter(Boolean).join(' ');
  }

  static buildSearchIndex(items) {
    const invertedIndex = new Map();
    const docFreq = new Map();
    const byId = new Map();
    let totalDocLength = 0;

    for (const item of items) {
      const nameTokens = this.tokenize(item.name);
      const descTokens = this.tokenize(item.description);
      const storeTokens = this.tokenize(item.store_name);
      const allTokens = unique([...nameTokens, ...nameTokens, ...descTokens, ...storeTokens]);
      const docLength = allTokens.length || 1;

      totalDocLength += docLength;
      byId.set(String(item.id), {
        ...item,
        _nameTokens: nameTokens,
        _descTokens: descTokens,
        _docLength: docLength,
      });

      for (const token of new Set(allTokens)) {
        docFreq.set(token, (docFreq.get(token) || 0) + 1);
        if (!invertedIndex.has(token)) invertedIndex.set(token, new Set());
        invertedIndex.get(token).add(String(item.id));
      }
    }

    return {
      items,
      byId,
      invertedIndex,
      docFreq,
      avgDocLength: items.length > 0 ? totalDocLength / items.length : 1,
      loadedAt: Date.now(),
    };
  }

  static buildQueryHints(query) {
    const tokens = this.tokenize(query);
    const hints = tokens.filter(t => t.length >= 3);
    const text = this.normalizeText(query);
    const phrases = [
      'zero sugar', 'no sugar', 'without sugar', 'low sugar', 'sugar free',
      'no caffeine', 'gluten free', 'fresh', 'summer', 'cold', 'hot',
      'بدون سكر', 'قليل السكر', 'صيف', 'بارد', 'طازج', 'خفيف',
    ];
    for (const phrase of phrases) {
      const np = this.normalizeText(phrase);
      if (text.includes(np)) hints.push(np);
    }
    return [...new Set(hints)];
  }

  static getStoreTypeBoost(query, product) {
    const queryText = this.normalizeText(query);
    const storeType = product.store_type ? this.normalizeText(product.store_type) : '';
    if (!storeType) return 0;

    const synonymList = this.storeTypeSynonyms[product.store_type] || [];
    const normalizedSynonyms = synonymList.map(t => this.normalizeText(t));
    const queryTokens = new Set(this.tokenize(query));

    if (queryText.includes(storeType)) return 18;
    if (normalizedSynonyms.some(t => queryText.includes(t))) return 15;
    if ([...queryTokens].some(t => normalizedSynonyms.includes(t))) return 12;
    return 0;
  }

  static scoreProductWithStats(product, query, queryHints, stats) {
    const queryTokens   = this.tokenize(query);
    const queryText     = this.normalizeText(query);
    const productText   = this.normalizeText(this.buildDocument(product));
    const productName   = this.normalizeText(product.name);
    const productDesc   = this.normalizeText(product.description);
    const nameTokens    = product._nameTokens || this.tokenize(product.name);
    const descTokens    = product._descTokens || this.tokenize(product.description);
    const docLength     = product._docLength  || Math.max((nameTokens.length + descTokens.length), 1);
    const avgDocLength  = stats?.avgDocLength || 1;
    const docFreq       = stats?.docFreq      || new Map();

    let score = 0;
    if (!queryText) return 0;

    const queryTokenSet  = new Set(queryTokens);
    const productTokenSet = new Set([...nameTokens, ...descTokens]);
    let overlap = 0;
    for (const token of queryTokenSet) {
      if (productTokenSet.has(token)) overlap += 1;
    }

    const titleCoverage = nameTokens.filter(t => queryTokenSet.has(t)).length;
    const descCoverage  = descTokens.filter(t => queryTokenSet.has(t)).length;

    if (productName && queryText === productName)         score += 45;
    if (productName && queryText.includes(productName))  score += 35;
    if (productName && productName.includes(queryText))  score += 28;

    score += titleCoverage * 12;
    score += descCoverage  * 4;
    score += overlap       * 6;

    for (const token of queryTokens) {
      const df  = docFreq.get(token) || 0;
      const idf = Math.log((1 + (stats?.items?.length || 1)) / (1 + df)) + 1;
      const tfTitle = nameTokens.filter(t => t === token).length;
      const tfDesc  = descTokens.filter(t => t === token).length;
      score += tfTitle * idf * 10;
      score += tfDesc  * idf * 3;
      if (productName.includes(token)) score += 4;
      if (productDesc.includes(token)) score += 1.5;
      if (productText.includes(token)) score += 1;
    }

    for (const hint of queryHints) {
      if (productText.includes(hint)) score += 5;
    }

    score += this.getStoreTypeBoost(query, product);

    if (product.price != null && queryText.includes(this.normalizeText(product.price))) score += 10;
    if ((product.stock || 0) > 0)  score += 1.5;
    if ((product.stock || 0) > 10) score += 1;

    const lengthPenalty = Math.max(0, docLength - avgDocLength) / Math.max(avgDocLength, 1);
    score -= Math.min(lengthPenalty * 1.5, 8);

    return score;
  }

  static async loadCatalog(storeType = null) {
    const cacheEntry = this.getCacheEntry(storeType);
    if (cacheEntry && (Date.now() - cacheEntry.loadedAt) < this.CACHE_TTL_MS) {
      return cacheEntry.items;
    }

    const connection = await pool.getConnection();
    try {
      let query = `
        SELECT
          p.id, p.name,
          COALESCE(p.description, '') AS description,
          p.price, p.currency, p.stock, p.image_url,
          s.name AS store_name, s.store_type,
          s.email AS store_owner_email
        FROM products p
        JOIN stores s ON p.store_id = s.id
        WHERE p.status = 'approved'
          AND p.is_active = 1
          AND p.stock > 0
          AND s.status = 'approved'
      `;
      const params = [];
      if (storeType) {
        query += ` AND s.store_type = ?`;
        params.push(storeType);
      }
      query += ` ORDER BY p.id DESC LIMIT ${this.MAX_CANDIDATES}`;

      const [rows] = await connection.execute(query, params);

      const baseUrl = process.env.BACKEND_URL || 'http://10.155.83.72:3000';
      const items = rows.map(p => ({
        ...p,
        image_url: p.image_url && !p.image_url.startsWith('http')
          ? baseUrl + p.image_url
          : (p.image_url || ''),
      }));

      this.setCacheEntry(storeType, this.buildSearchIndex(items));
      return items;
    } finally {
      connection.release();
    }
  }

  // ─── Main search ─────────────────────────────────────────────────────────────
  // Strategy:
  //   1. BM25-like lexical scoring on all candidates
  //   2. Real semantic scoring via VectorStore (Gemini embeddings, always-on)
  //   3. Hybrid merge: 55% lexical + 45% semantic
  //
  // The semantic step is always executed when EmbeddingPipeline is available.
  // Query embeddings are cached in VectorStore (10-min TTL) so repeated queries
  // are near-instant.

  static async search(query, { storeType = null, limit = 60, excludeIds = [], userId = null } = {}) {
    let catalog;
    try {
      catalog = await this.loadCatalog(storeType);
    } catch (err) {
      logger.error('[ProductRetrieval] loadCatalog error:', err.message);
      return [];
    }
    if (!catalog.length) return [];

    const queryHints = this.buildQueryHints(query);
    const excludeSet = new Set((excludeIds || []).map(id => Number(id)));
    const cacheEntry = this.getCacheEntry(storeType) || this.buildSearchIndex(catalog);
    const queryTokens = this.tokenize(query);
    const candidateIds = new Set();

    for (const token of queryTokens) {
      const matches = cacheEntry.invertedIndex.get(token);
      if (matches) { for (const id of matches) candidateIds.add(id); }
    }

    const candidateProducts = candidateIds.size > 0
      ? [...candidateIds].map(id => cacheEntry.byId.get(String(id))).filter(Boolean)
      : catalog;

    // ── Step 1: Lexical scoring ───────────────────────────────────────────────
    const lexicalScored = candidateProducts
      .filter(p => !excludeSet.has(Number(p.id)))
      .map(p => ({ ...p, lexicalScore: this.scoreProductWithStats(p, query, queryHints, cacheEntry) }))
      .sort((a, b) => b.lexicalScore - a.lexicalScore || b.stock - a.stock || b.id - a.id);

    const maxLexical = lexicalScored[0]?.lexicalScore || 0;

    // ── Step 2: Semantic scoring (always-on when Gemini available) ────────────
    if (EmbeddingPipeline.isAvailable()) {
      logger.info(
        `[Retrieval] mode=hybrid | query="${String(query).substring(0, 60)}" | ` +
        `candidates=${lexicalScored.length} | maxLexical=${maxLexical.toFixed(1)}`,
      );

      // Semantic search on the full catalog (not just lexical candidates)
      // so we don't miss semantically relevant products with no keyword overlap.
      const semanticRanked = await VectorStore.personalizedSearch(
        query,
        catalog.filter(p => !excludeSet.has(Number(p.id))),
        { userId, topK: Math.max(limit, 30) },
      );

      // ── Step 3: Hybrid merge ──────────────────────────────────────────────
      const merged = new Map();

      // Seed with lexical scores (normalized to 0–1 range)
      const lexNorm = maxLexical > 0 ? maxLexical : 1;
      for (const item of lexicalScored) {
        merged.set(String(item.id), {
          ...item,
          _lexScore: item.lexicalScore / lexNorm,
          _semScore: 0,
        });
      }

      // Merge in semantic scores
      for (const item of semanticRanked) {
        const key = String(item.id);
        const existing = merged.get(key) || { ...item, _lexScore: 0, _semScore: 0 };
        merged.set(key, {
          ...existing,
          ...item,
          _lexScore: existing._lexScore,
          _semScore: item.semanticScore || 0,
          // Keep semanticScore on product so RankingService can use it
          semanticScore: item.semanticScore || 0,
        });
      }

      const hybridList = [...merged.values()]
        .map(item => ({
          ...item,
          _hybridScore: (0.55 * (item._lexScore || 0)) + (0.45 * (item._semScore || 0)),
        }))
        .sort((a, b) => b._hybridScore - a._hybridScore || b.stock - a.stock || b.id - a.id)
        .slice(0, limit);

      return hybridList.map(({ lexicalScore, _lexScore, _semScore, _hybridScore, ...product }) => product);
    }

    // ── Lexical-only fallback (EmbeddingPipeline not available) ──────────────
    logger.info(`[Retrieval] mode=lexical | query="${String(query).substring(0, 60)}" | maxScore=${maxLexical.toFixed(1)}`);
    return lexicalScored
      .slice(0, limit)
      .map(({ lexicalScore, ...product }) => product);
  }

  static clearCache() {
    this.cache.clear();
  }
}
