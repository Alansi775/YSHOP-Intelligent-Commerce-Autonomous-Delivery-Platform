// EmbeddingService.js — Thin adapter: delegates to VectorStore (real embeddings)
// Kept for backward compatibility with RankingService.
// The old hash-based fake embeddings are removed entirely.
import { VectorStore } from './VectorStore.js';
import { EmbeddingPipeline } from './EmbeddingPipeline.js';

export class EmbeddingService {
  // Used by RankingService.scoreProduct() synchronously.
  // Products coming from ProductRetrievalService now carry a pre-computed
  // `semanticScore` from VectorStore — RankingService will use that instead.
  // These stubs exist only so old call-sites don't crash during the transition.

  static cosineSimilarity(a, b) {
    return EmbeddingPipeline.cosineSimilarity(a, b);
  }

  // RankingService calls this synchronously, but products now carry
  // `product.semanticScore` (pre-computed in ProductRetrievalService).
  // Return an empty placeholder — RankingService checks for the pre-computed
  // score before calling this.
  static embedProduct(_product) {
    return [];
  }

  static embedQuery(_query) {
    return [];
  }

  // Async search — delegates to VectorStore (real Gemini embeddings).
  static async search(query, products, topK = 20) {
    return VectorStore.search(query, products, topK);
  }

  static clearCache() {
    VectorStore.clearQueryCache();
  }
}
