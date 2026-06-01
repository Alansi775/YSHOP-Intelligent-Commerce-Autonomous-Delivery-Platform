import { EmbeddingService } from './EmbeddingService.js';
import { normalizeText, tokenize, unique } from '../utils/textProcessing.js';

export class RankingService {
  static keywordBoost(queryTokens, keywords, productText) {
    const keywordSet = new Set((keywords || []).map(term => normalizeText(term)));
    let score = 0;

    for (const token of queryTokens) {
      if (keywordSet.has(token)) score += 8;
      if (productText.includes(token)) score += 2;
    }

    for (const keyword of keywordSet) {
      if (keyword && productText.includes(keyword)) score += 6;
    }

    return score;
  }

  static storeTypeBoost(storeType, product) {
    if (!storeType || !product?.store_type) return 0;
    return normalizeText(storeType) === normalizeText(product.store_type) ? 15 : 0;
  }

  static scoreProduct(query, product, { keywords = [], storeType = null } = {}) {
    const queryText = normalizeText(query);
    const queryTokens = unique(tokenize(queryText));
    const productText = normalizeText([
      product.name,
      product.description,
      product.store_name,
      product.store_type,
    ].filter(Boolean).join(' '));

    let score = 0;
    if (!queryText && !keywords.length && !storeType) return 1;

    const name = normalizeText(product.name);
    const desc = normalizeText(product.description);
    const overlap = queryTokens.reduce((count, token) => count + (productText.includes(token) ? 1 : 0), 0);

    if (name && queryText === name) score += 50;
    if (name && queryText.includes(name)) score += 35;
    if (name && name.includes(queryText)) score += 25;

    score += overlap * 6;
    score += this.keywordBoost(queryTokens, keywords, productText);
    score += this.storeTypeBoost(storeType, product);

    if (desc && queryText && desc.includes(queryText)) score += 6;
    if (product.price != null && queryText.includes(normalizeText(product.price))) score += 8;
    if ((product.stock || 0) > 0) score += 1.5;
    if ((product.stock || 0) > 10) score += 1;

    const semanticScore = EmbeddingService.cosineSimilarity(
      EmbeddingService.embedQuery(queryText),
      EmbeddingService.embedProduct(product),
    );

    score += semanticScore * 100;
    return score;
  }

  static rankProducts(query, products, options = {}) {
    const ranked = (products || [])
      .map(product => ({
        ...product,
        _rankScore: this.scoreProduct(query, product, options),
      }))
      .sort((a, b) => b._rankScore - a._rankScore || b.stock - a.stock || b.id - a.id);

    return ranked.slice(0, options.limit || 3).map(({ _rankScore, ...product }) => product);
  }
}