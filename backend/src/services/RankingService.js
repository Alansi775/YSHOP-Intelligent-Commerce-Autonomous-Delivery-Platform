// RankingService.js — Final product ranking after retrieval
//
// Score components (additive):
//   1. Lexical match    — exact/token overlap with user query
//   2. Semantic score   — pre-computed Gemini cosine similarity (from VectorStore)
//   3. Popularity boost — log-scaled global interaction count (max +15 pts)
//   4. Store affinity   — how much THIS user likes this store type (max +20 pts)
//   5. Collaborative    — how much SIMILAR users liked this product (max +25 pts)

import { EmbeddingPipeline } from './EmbeddingPipeline.js';
import { normalizeText, tokenize, unique } from '../utils/textProcessing.js';

export class RankingService {

  static keywordBoost(queryTokens, keywords, productText) {
    const keywordSet = new Set((keywords || []).map(k => normalizeText(k)));
    let score = 0;
    for (const token of queryTokens) {
      if (keywordSet.has(token)) score += 8;
      if (productText.includes(token)) score += 2;
    }
    for (const kw of keywordSet) {
      if (kw && productText.includes(kw)) score += 6;
    }
    return score;
  }

  static storeTypeBoost(storeType, product) {
    if (!storeType || !product?.store_type) return 0;
    return normalizeText(storeType) === normalizeText(product.store_type) ? 15 : 0;
  }

  // Global popularity: log-scaled — very popular products get a real boost,
  // but the diminishing returns prevent one product from dominating.
  // Max practical boost ≈ 15 pts (score ~150 → log1p(150) * 3 ≈ 15)
  static popularityBoost(product) {
    const raw = Number(product._popularityScore) || 0;
    if (raw <= 0) return 0;
    return Math.min(Math.log1p(raw) * 3, 15);
  }

  // Store affinity: how much THIS specific user loves this store type.
  // Value is 0–1 (normalized). Max boost = 20 pts.
  static storeAffinityBoost(product) {
    const aff = Number(product._userStoreAffinity) || 0;
    if (aff <= 0) return 0;
    return aff * 20; // max 20 pts when affinity = 1.0 (loves this category)
  }

  // Collaborative boost: similar users liked/bought this product.
  // Score = sum of (user_similarity × event_weight) for each similar-user interaction.
  // Max boost = 25 pts (capped to prevent runaway).
  static collaborativeBoost(product) {
    const raw = Number(product._collaborativeScore) || 0;
    if (raw <= 0) return 0;
    return Math.min(raw * 4, 25);
  }

  // Keyword affinity: how much THIS user's historical queries match this product's keywords
  static keywordAffinityBoost(product) {
    const aff = Number(product._keywordAffinityScore) || 0;
    if (aff <= 0) return 0;
    return Math.min(aff * 10, 12);
  }

  static scoreProduct(query, product, { keywords = [], storeType = null } = {}) {
    const queryText   = normalizeText(query);
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

    if (name && queryText === name)           score += 50;
    if (name && queryText.includes(name))     score += 35;
    if (name && name.includes(queryText))     score += 25;

    score += overlap * 6;
    score += this.keywordBoost(queryTokens, keywords, productText);
    score += this.storeTypeBoost(storeType, product);

    if (desc && queryText && desc.includes(queryText)) score += 6;
    if (product.price != null && queryText.includes(normalizeText(product.price))) score += 8;
    if ((product.stock || 0) > 0)  score += 1.5;
    if ((product.stock || 0) > 10) score += 1;

    // ── Semantic score (pre-computed by VectorStore, real Gemini 768-dim) ────
    const semanticScore = typeof product.semanticScore === 'number' ? product.semanticScore : 0;
    score += semanticScore * 100;

    // ── Personalization signals ───────────────────────────────────────────────
    score += this.popularityBoost(product);      // global crowd intelligence
    score += this.storeAffinityBoost(product);   // this user's category preference
    score += this.collaborativeBoost(product);   // what similar users liked
    score += this.keywordAffinityBoost(product); // this user's keyword history

    return score;
  }

  static rankProducts(query, products, options = {}) {
    const ranked = (products || [])
      .map(product => ({
        ...product,
        _rankScore: this.scoreProduct(query, product, options),
      }))
      .sort((a, b) => b._rankScore - a._rankScore || b.stock - a.stock || b.id - a.id);

    return ranked
      .slice(0, options.limit || 3)
      .map(({ _rankScore, _popularityScore, _userStoreAffinity, _collaborativeScore, _keywordAffinityScore, ...product }) => product);
  }
}
