// ImageEmbeddingService.js — Image understanding layer for product re-ranking
//
// Flow:
//   product.image_url
//     → fetch image bytes (local file or HTTP) → base64
//     → Groq Vision (llama-4-scout) generates a rich product caption
//     → EmbeddingPipeline.embedText(caption) → float[N]
//
// Gemini Vision was hitting free-tier limit=0; switched to Groq Vision which
// uses the same GROQ_API_KEY already in use for chat.
//
// Used as a re-ranking signal only (30% weight) — failures degrade to text-only.

import fs from 'node:fs/promises';
import path from 'node:path';
import { EmbeddingPipeline } from './EmbeddingPipeline.js';
import logger from '../config/logger.js';

export class ImageEmbeddingService {
  static VISION_MODEL = 'meta-llama/llama-4-scout-17b-16e-instruct';
  static GROQ_VISION_URL = 'https://api.groq.com/openai/v1/chat/completions';

  static CAPTION_PROMPT =
    'Describe this product image for a shopping search engine. ' +
    'Include: product type, color, visual appearance, what is shown or contained, and category. ' +
    'Facts only. No opinions. Under 80 words. English only.';

  static isAvailable() {
    return EmbeddingPipeline.isAvailable();
  }

  static _mimeType(url) {
    const ext = (url.split('?')[0].split('.').pop() ?? '').toLowerCase();
    return (
      { jpg: 'image/jpeg', jpeg: 'image/jpeg', png: 'image/png', webp: 'image/webp', gif: 'image/gif' }[ext]
      ?? 'image/jpeg'
    );
  }

  static async _fetchBytes(imageUrl) {
    if (!imageUrl) return null;
    try {
      if (imageUrl.startsWith('/')) {
        const localPath = path.join(process.cwd(), imageUrl);
        return await fs.readFile(localPath);
      }
      if (imageUrl.startsWith('http')) {
        const res = await fetch(imageUrl, { signal: AbortSignal.timeout(12_000) });
        if (!res.ok) {
          logger.warn(`[ImageEmbedding] fetchBytes HTTP ${res.status} for ${imageUrl}`);
          return null;
        }
        return Buffer.from(await res.arrayBuffer());
      }
      return null;
    } catch (err) {
      logger.warn(`[ImageEmbedding] fetchBytes failed (${imageUrl}): ${err.message}`);
      return null;
    }
  }

  static async captionImage(imageUrl, retries = 3) {
    const groqKey = process.env.GROQ_API_KEY;
    if (!groqKey || !imageUrl) return null;

    const bytes = await this._fetchBytes(imageUrl);
    if (!bytes?.length) return null;

    const mimeType = this._mimeType(imageUrl);
    const dataUrl = `data:${mimeType};base64,${bytes.toString('base64')}`;

    for (let attempt = 0; attempt <= retries; attempt++) {
      try {
        const response = await fetch(this.GROQ_VISION_URL, {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${groqKey}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            model: this.VISION_MODEL,
            messages: [{
              role: 'user',
              content: [
                { type: 'image_url', image_url: { url: dataUrl } },
                { type: 'text', text: this.CAPTION_PROMPT },
              ],
            }],
            max_tokens: 150,
            temperature: 0.1,
          }),
          signal: AbortSignal.timeout(30_000),
        });

        if (response.status === 429) {
          if (attempt < retries) {
            const retryAfterSec = parseInt(response.headers.get('retry-after') || '30', 10);
            const waitMs = (retryAfterSec + 2) * 1000;
            logger.warn(`[ImageEmbedding] Groq Vision 429 — retry ${attempt + 1}/${retries} after ${retryAfterSec}s`);
            await new Promise(r => setTimeout(r, waitMs));
            continue;
          }
          logger.warn(`[ImageEmbedding] Groq Vision 429 — exhausted retries for ${imageUrl.slice(-40)}`);
          return null;
        }

        if (!response.ok) {
          const errText = await response.text().catch(() => response.statusText);
          logger.warn(`[ImageEmbedding] Groq Vision ${response.status}: ${errText.slice(0, 200)}`);
          return null;
        }

        const data = await response.json();
        const caption = data?.choices?.[0]?.message?.content?.trim();
        return caption || null;
      } catch (err) {
        logger.warn(`[ImageEmbedding] captionImage error: ${err.message}`);
        return null;
      }
    }
    return null;
  }

  static async embedImage(product) {
    if (!this.isAvailable() || !product?.image_url) return null;

    const caption = await this.captionImage(product.image_url);
    if (!caption) return null;

    try {
      const vector = await EmbeddingPipeline.embedText(caption);
      logger.info(`[ImageEmbedding] embedded product ${product.id} — caption: "${caption.slice(0, 70)}"`);
      return vector;
    } catch (err) {
      logger.warn(`[ImageEmbedding] embedText failed for product ${product.id}: ${err.message}`);
      return null;
    }
  }
}
