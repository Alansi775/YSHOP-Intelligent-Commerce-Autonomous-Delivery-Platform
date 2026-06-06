// ProductRetrievalService.js
import pool from '../config/database.js';
import logger from '../config/logger.js';
import { IRetrievalService } from './IRetrievalService.js';
import { EmbeddingService } from './EmbeddingService.js';
import { normalizeText, tokenize, unique } from '../utils/textProcessing.js';

export class ProductRetrievalService extends IRetrievalService {
  static cache = new Map();
  static CACHE_TTL_MS = 2 * 60 * 1000;
  static MAX_CANDIDATES = 250;

  static storeTypeSynonyms = {
    Food: ['food', 'meal', 'eat', 'eating', 'burger', 'pizza', 'chicken', 'drink', 'drinks', 'soda', 'water', 'juice', 'snack', 'breakfast', 'lunch', 'dinner', 'restaurant', 'مطعم', 'اكل', 'طعام', 'وجبة', 'برجر', 'بيتزا', 'دجاج', 'عصير', 'ماء', 'سناك'],
    Pharmacy: ['pharmacy', 'medicine', 'medication', 'health', 'sick', 'pain', 'pill', 'tablet', 'vitamin', 'dose', 'دواء', 'صيدلية', 'صحة', 'مريض', 'حبة', 'فيتامين', 'صداع'],
    Clothes: ['clothes', 'clothing', 'shirt', 'dress', 'shoes', 'fashion', 'jacket', 'wear', 'outfit', 'ملابس', 'قميص', 'فستان', 'حذاء', 'موضة'],
    Market: ['market', 'grocery', 'vegetable', 'fruit', 'fresh', 'groceries', 'supermarket', 'خضار', 'فاكهة', 'سوق', 'بقال', 'تموينات'],
  };

  static getStoreTypeKey(storeType) {
    return storeType || '__all__';
  }

  static getCacheEntry(storeType) {
    return this.cache.get(this.getStoreTypeKey(storeType)) || null;
  }

  static setCacheEntry(storeType, entry) {
    this.cache.set(this.getStoreTypeKey(storeType), entry);
  }

  static normalizeText(text) {
    return normalizeText(text);
  }

  static tokenize(text) {
    return tokenize(text);
  }

  static buildDocument(product) {
    return [
      product.name,
      product.description,
      product.store_name,
      product.store_type,
      product.currency,
      product.price,
    ].filter(Boolean).join(' ');
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

      const uniqueTokens = new Set(allTokens);
      for (const token of uniqueTokens) {
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
    const hints = [];

    for (const token of tokens) {
      if (token.length >= 3) hints.push(token);
    }

    const text = this.normalizeText(query);
    const phrases = [
      'zero sugar', 'no sugar', 'without sugar', 'low sugar', 'sugar free',
      'no caffeine', 'gluten free', 'fresh', 'summer', 'cold', 'hot',
      'بدون سكر', 'قليل السكر', 'صيف', 'بارد', 'طازج', 'خفيف',
    ];

    for (const phrase of phrases) {
      const normalizedPhrase = this.normalizeText(phrase);
      if (text.includes(normalizedPhrase)) hints.push(normalizedPhrase);
    }

    return [...new Set(hints)];
  }

  static getStoreTypeBoost(query, product) {
    const queryText = this.normalizeText(query);
    const storeType = product.store_type ? this.normalizeText(product.store_type) : '';
    if (!storeType) return 0;

    const synonymList = this.storeTypeSynonyms[product.store_type] || this.storeTypeSynonyms[
      Object.keys(this.storeTypeSynonyms).find(key => this.normalizeText(key) === storeType)
    ] || [];
    const normalizedSynonyms = synonymList.map(term => this.normalizeText(term));
    const queryTokens = new Set(this.tokenize(query));

    if (queryText.includes(storeType)) return 18;
    if (normalizedSynonyms.some(term => queryText.includes(term))) return 15;
    if ([...queryTokens].some(token => normalizedSynonyms.includes(token))) return 12;
    return 0;
  }

  static scoreProductWithStats(product, query, queryHints, stats) {
    const queryTokens = this.tokenize(query);
    const queryText = this.normalizeText(query);
    const productText = this.normalizeText(this.buildDocument(product));
    const productName = this.normalizeText(product.name);
    const productDesc = this.normalizeText(product.description);
    const nameTokens = product._nameTokens || this.tokenize(product.name);
    const descTokens = product._descTokens || this.tokenize(product.description);
    const docLength = product._docLength || Math.max((nameTokens.length + descTokens.length), 1);
    const avgDocLength = stats?.avgDocLength || 1;
    const docFreq = stats?.docFreq || new Map();

    let score = 0;
    if (!queryText) return 0;

    const queryTokenSet = new Set(queryTokens);
    const productTokenSet = new Set([...nameTokens, ...descTokens]);
    let overlap = 0;
    for (const token of queryTokenSet) {
      if (productTokenSet.has(token)) overlap += 1;
    }

    const titleCoverage = nameTokens.filter(token => queryTokenSet.has(token)).length;
    const descCoverage = descTokens.filter(token => queryTokenSet.has(token)).length;

    if (productName && queryText === productName) score += 45;
    if (productName && queryText.includes(productName)) score += 35;
    if (productName && productName.includes(queryText)) score += 28;

    score += titleCoverage * 12;
    score += descCoverage * 4;
    score += overlap * 6;

    for (const token of queryTokens) {
      const df = docFreq.get(token) || 0;
      const idf = Math.log((1 + (stats?.items?.length || 1)) / (1 + df)) + 1;
      const tfTitle = nameTokens.filter(t => t === token).length;
      const tfDesc = descTokens.filter(t => t === token).length;

      score += tfTitle * idf * 10;
      score += tfDesc * idf * 3;

      if (productName.includes(token)) score += 4;
      if (productDesc.includes(token)) score += 1.5;
      if (productText.includes(token)) score += 1;
    }

    for (const hint of queryHints) {
      if (productText.includes(hint)) score += 5;
    }

    score += this.getStoreTypeBoost(query, product);

    const priceText = this.normalizeText(product.price);
    if (priceText && queryText.includes(priceText)) score += 10;

    if (product.stock != null) {
      if (product.stock > 0) score += 1.5;
      if (product.stock > 10) score += 1;
    }

    const lengthPenalty = Math.max(0, docLength - avgDocLength) / Math.max(avgDocLength, 1);
    score -= Math.min(lengthPenalty * 1.5, 8);

    return score;
  }

  static async loadCatalog(storeType = null) {
    const cacheEntry = this.getCacheEntry(storeType);
    const now = Date.now();
    if (cacheEntry && (now - cacheEntry.loadedAt) < this.CACHE_TTL_MS) {
      return cacheEntry.items;
    }

    try {
      const connection = await pool.getConnection();
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
          AND s.status = 'approved'
      `;
      const params = [];
      if (storeType) {
        query += ` AND s.store_type = ?`;
        params.push(storeType);
      }
      query += ` ORDER BY p.id DESC LIMIT ${this.MAX_CANDIDATES}`;

      const [rows] = await connection.execute(query, params);
      connection.release();

      const baseUrl = process.env.PUBLIC_BACKEND_URL || process.env.BACKEND_URL || 'http://Mohammeds-Mackbook-MacBook-Air.local:3000';
      const items = rows.map(p => ({
        ...p,
        image_url: p.image_url
          ? (p.image_url.startsWith('http') ? baseUrl + new URL(p.image_url).pathname : baseUrl + p.image_url)
          : '',
      }));

      this.setCacheEntry(storeType, this.buildSearchIndex(items));
      return items;
    } catch (err) {
      logger.error('[ProductRetrieval] loadCatalog error:', err.message);
      return [];
    }
  }

  static async search(query, { storeType = null, limit = 60, excludeIds = [] } = {}) {
    const catalog = await this.loadCatalog(storeType);
    if (!catalog.length) return [];

    const queryHints = this.buildQueryHints(query);
    const excludeSet = new Set((excludeIds || []).map(id => Number(id)));
    const cacheEntry = this.getCacheEntry(storeType) || this.buildSearchIndex(catalog);
    const queryTokens = this.tokenize(query);
    const candidateIds = new Set();

    for (const token of queryTokens) {
      const matches = cacheEntry.invertedIndex.get(token);
      if (matches) {
        for (const id of matches) candidateIds.add(id);
      }
    }

    const candidateProducts = candidateIds.size > 0
      ? [...candidateIds].map(id => cacheEntry.byId.get(String(id))).filter(Boolean)
      : catalog;

    const scored = candidateProducts
      .filter(product => !excludeSet.has(Number(product.id)))
      .map(product => ({
        ...product,
        _score: this.scoreProductWithStats(product, query, queryHints, cacheEntry),
      }))
      .sort((a, b) => b._score - a._score || b.stock - a.stock || b.id - a.id);

    const relevant = scored.filter(product => product._score > 0);
    const topScore = relevant[0]?._score || scored[0]?._score || 0;

    let finalList = (relevant.length > 0 ? relevant : scored).slice(0, limit);

    if (topScore < 25) {
      logger.info('[Retrieval] mode=hybrid');
      const semanticRanked = (await EmbeddingService.search(query, catalog, Math.max(limit, 20)))
        .filter(item => !excludeSet.has(Number(item.id)));
      const merged = new Map();

      for (const item of scored) {
        if (excludeSet.has(Number(item.id))) continue;
        merged.set(String(item.id), {
          ...item,
          lexicalScore: item._score || 0,
          semanticScore: 0,
        });
      }

      for (const item of semanticRanked) {
        if (excludeSet.has(Number(item.id))) continue;
        const current = merged.get(String(item.id)) || {
          ...item,
          lexicalScore: 0,
          semanticScore: 0,
        };

        merged.set(String(item.id), {
          ...current,
          ...item,
          lexicalScore: current.lexicalScore || 0,
          semanticScore: item.semanticScore || 0,
        });
      }

      finalList = [...merged.values()]
        .map(item => ({
          ...item,
          hybridScore: (0.6 * (item.lexicalScore || 0)) + (0.4 * ((item.semanticScore || 0) * 100)),
        }))
        .sort((a, b) => b.hybridScore - a.hybridScore || b.stock - a.stock || b.id - a.id)
        .slice(0, limit);
    }

    return finalList.map(({ _score, lexicalScore, semanticScore, hybridScore, ...product }) => product);
  }

  static clearCache() {
    this.cache.clear();
  }
}
