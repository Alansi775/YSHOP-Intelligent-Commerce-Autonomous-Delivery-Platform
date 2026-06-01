import { GoogleGenerativeAI } from '@google/generative-ai';
import logger from '../config/logger.js';
import pool from '../config/database.js';
import { ProductRetrievalService } from './ProductRetrievalService.js';
import { IntentEngine } from './IntentEngine.js';
import { MemoryService } from './MemoryService.js';
import { RankingService } from './RankingService.js';
import { normalizeText, tokenize } from '../utils/textProcessing.js';

/**
 * YSHOP AI Service - v6
 * Conversation flow: AI talks first, products come only when ready
 */
export class YShopAIService {
  static client = null;
  static model = null;
  static provider = 'gemini';
  static CLEANUP_INTERVAL_MS = 10 * 60 * 1000;
  static intentCache = new Map();
  static reasonCache = new Map();
  static MAX_REASON_CACHE = 500;

  // ─────────────────────────────────────────────
  // INIT
  // ─────────────────────────────────────────────
  static initialize() {
    const geminiKey = process.env.YSHOP_AI_API_KEY;
    const groqKey = process.env.GROQ_API_KEY;

    if (!geminiKey && !groqKey) {
      throw new Error('YSHOP_AI_API_KEY or GROQ_API_KEY not configured in .env');
    }

    if (geminiKey) {
      const genAI = new GoogleGenerativeAI(geminiKey);
      this.client = genAI;
      this.model = genAI.getGenerativeModel({
        model: process.env.YSHOP_AI_MODEL || 'gemini-2.0-flash',
      });
      this.provider = 'gemini';
      logger.info('✅ YSHOP AI initialized successfully with Gemini primary');
      return;
    }

    this.client = null;
    this.model = null;
    this.provider = 'groq';
    logger.info('✅ YSHOP AI initialized successfully with Groq-only mode');
  }

  // ─────────────────────────────────────────────
  // DETECT LANGUAGE
  // ─────────────────────────────────────────────
  static detectLanguage(text) {
    return IntentEngine.detectLanguage(text);
  }

  // ─────────────────────────────────────────────
  // PERSONALITY
  // ─────────────────────────────────────────────
  static get PERSONALITY() {
    return `You are "Youssef", a shopping assistant at YSHOP. You speak plainly, calmly, and naturally.

Voice rules:
- Talk plainly, NOT like a hype bot or a sales person
- MATCH the user's language exactly: if they write in Arabic→reply ONLY in Arabic, if English→reply ONLY in English
- Infer subtle delivery from user tone and conversation state (hungry, confused, thankful, frustrated, amused), but keep it natural and never theatrical
- Keep it SHORT — 1-2 sentences, plain and natural
- NEVER use emojis
- NEVER mix languages

TTS tags (use naturally, not every sentence):
- <break time="0.5s" /> for pauses
- only if the model truly needs them, otherwise avoid them entirely
- (hmm) for thinking
- ... for trailing off`;
  }

  static getSupportedVoiceMoods() {
    return new Set(['neutral', 'excited', 'playful', 'curious', 'caring', 'whisper', 'disappointed', 'apologetic', 'warm']);
  }

  static getTextScriptCounts(text) {
    const value = String(text || '');
    const arabic = (value.match(/[\u0600-\u06FF]/g) || []).length;
    const latin = (value.match(/[A-Za-z]/g) || []).length;
    return { arabic, latin, total: arabic + latin };
  }

  static isMostlyLanguage(text, language, threshold = 0.7) {
    const { arabic, latin, total } = this.getTextScriptCounts(text);
    if (total === 0) return true;
    const ratio = language === 'arabic' ? arabic / total : latin / total;
    return ratio >= threshold;
  }

  // ─────────────────────────────────────────────
  // SAFE TEXT EXTRACTOR
  // ─────────────────────────────────────────────
  static extractText(response) {
    try {
      if (response?.response?.text) {
        const t = response.response.text();
        if (t && t.trim().length > 0) return t.trim();
      }
      const candidates = response?.response?.candidates;
      if (candidates && candidates.length > 0) {
        const parts = candidates[0]?.content?.parts;
        if (parts && parts.length > 0) {
          const text = parts.map(p => p.text || '').join('');
          if (text.trim().length > 0) return text.trim();
        }
      }
      return '';
    } catch (err) {
      logger.error('[YShopAI] extractText error:', err.message);
      return '';
    }
  }

  // ─────────────────────────────────────────────
  // SAFE JSON PARSER
  // ─────────────────────────────────────────────
  static parseJSON(text) {
    if (!text) return null;
    try {
      const cleaned = text
        .replace(/^```json\s*/im, '')
        .replace(/^```\s*/im, '')
        .replace(/```\s*$/im, '')
        .trim();
      const balanced = this.extractBalancedJSONObject(cleaned);
      if (balanced) {
        try { return JSON.parse(balanced); } catch { /* continue */ }
      }
      return null;
    } catch {
      return null;
    }
  }

  static extractBalancedJSONObject(text) {
    const start = text.indexOf('{');
    if (start < 0) return null;

    let depth = 0;
    let inString = false;
    let escaped = false;

    for (let index = start; index < text.length; index += 1) {
      const char = text[index];

      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (char === '\\') {
          escaped = true;
        } else if (char === '"') {
          inString = false;
        }
        continue;
      }

      if (char === '"') {
        inString = true;
        continue;
      }

      if (char === '{') depth += 1;
      if (char === '}') depth -= 1;

      if (depth === 0) {
        return text.slice(start, index + 1);
      }
    }

    return null;
  }

  static normalizeText(text) {
    return normalizeText(text);
  }

  static tokenize(text) {
    return tokenize(text);
  }

  static sanitizeUserMessage(message) {
    return String(message || '')
      .replace(/```/g, ' ')
      .replace(/[\u0000-\u001f\u007f]/g, ' ')
      .replace(/\s+/g, ' ')
      .trim()
      .slice(0, 500);
  }

  static buildConversationContext(userId, history, shownProducts) {
    const memorySummary = userId ? MemoryService.summarize(userId) : '';
    const historyText = history.slice(-6)
      .map(m => `${m.role === 'user' ? 'User' : 'Youssef'}: ${m.text}`)
      .join('\n');

    const shownContext = shownProducts.length > 0
      ? `\nProducts user already saw:\n${shownProducts.map(p => `- ID:${p.id} | ${p.name} | ${p.price}${p.currency} | from ${p.store_name} | ${(p.description || '').substring(0, 100)}`).join('\n')}\n`
      : '';

    return [
      memorySummary ? `Memory summary: ${memorySummary}` : '',
      historyText || '(first message)',
      shownContext,
    ].filter(Boolean).join('\n');
  }

  static buildIntentPrompt(userMessage, contextText, userLang) {
    const safeMessage = this.sanitizeUserMessage(userMessage);
    return `${this.PERSONALITY}

User's language: ${userLang === 'arabic' ? 'ARABIC' : 'ENGLISH'} — REPLY ONLY IN ${userLang === 'arabic' ? 'ARABIC' : 'ENGLISH'}

Conversation context:
${contextText}

USER_MESSAGE_START
${safeMessage}
USER_MESSAGE_END

Store types: Food, Pharmacy, Clothes, Market

Return JSON only:
{"showProducts":true/false,"storeType":"Food"/null,"keywords":[],"quantity":3,"reply":"...","isProductDiscussion":false,"discussionProductId":null,"conversationStage":"browsing","voiceProfile":{"emotion":"neutral","energy":0.65,"pace":1,"volume":1,"pitch":1,"pause":"normal","cue":"","formality":0.6,"playfulness":0.1},"voiceMood":"neutral","voiceIntensity":0.65,"voiceCue":""}

CRITICAL RULES:
1. showProducts logic:
   - showProducts = false when you want to TALK first (greetings, asking questions, narrowing down)
   - showProducts = true ONLY when you are READY to present products (user gave enough info)

2. Product Discussion Detection (isProductDiscussion):
   - TRUE if user mentions a product name/price/description from "Products user already saw" above
   - TRUE if user says "tell me about...", "explain...", "why this...", "about that..."
   - Include discussionProductId with the ID from the shown products
   - FALSE if asking for new products

3. Language Rule (CRITICAL):
   - If user spoke Arabic → ALL your reply MUST be Arabic
   - If user spoke English → ALL your reply MUST be English
   - NEVER mix languages in the reply

Voice mood:
 Choose one: neutral, excited, playful, curious, caring, whisper, disappointed, apologetic, warm
 Keep it aligned to the reply and user intent.
 Do not force neutral when a clearer subtle emotion exists.
 Default to neutral only when tone is ambiguous.
 Return voiceCue only when the model is explicitly choosing a non-neutral delivery.
 Keep emotion subtle and professional.

Conversation stage:
 Choose one: greeting, browsing, shopping, checkout, finished, support
 Use browsing when the user is still exploring, shopping when they are choosing products, checkout when they are ready to confirm, finished when the order is done, support when they need help or changes, and greeting for the first contact.

Voice profile:
 Return a structured voiceProfile object when possible.
 emotion: neutral, excited, playful, curious, caring, whisper, disappointed, apologetic, warm
 energy: 0 to 1
 pace: 0.75 to 1.35
 volume: 0.7 to 1.2
 pitch: 0.8 to 1.25
 pause: normal, short, long
 cue: keep it short and natural
 formality: 0 to 1
 playfulness: 0 to 1

Voice cues (use at most one, or leave empty):
- laugh
- deep_breath
- pause
- sigh
- whisper

Examples:
- "[laughing]" when the reply is playful or amused
- "[deep breath]" when the reply is thoughtful, heavy, or a little dramatic
- "[pause]" when the reply needs a beat before the next line
- "[sigh]" when the reply is disappointed, tired, or apologetic
- "[whisper]" when the reply should feel secretive or quiet

Alternative products rule:
- If the user asks for other options, another option, different options, new options, more options, something else, or rejects the current item, set showProducts=true.
- In that case, do NOT classify it as product discussion.
- Reuse the same store type if the previous products make it clear.
- Keep the reply neutral and short.

Other:
- quantity = number user asked for (1-5), default 3
- reply = friendly response in user's language
- Return ONLY JSON`;
  }

  static validateIntentPayload(payload, userLang) {
    if (!payload || typeof payload !== 'object') return null;
    const reply = typeof payload.reply === 'string' ? payload.reply.trim() : '';
    if (!reply) return null;

    const legacyMood = payload.voiceMood ?? payload.mood;
    const legacyIntensity = payload.voiceIntensity ?? payload.intensity;
    const legacyCue = payload.voiceCue ?? payload.cue;

    const voiceProfile = this.normalizeVoiceProfile(
      payload.voiceProfile,
      legacyMood,
      legacyCue,
      legacyIntensity,
    );

    const normalized = {
      showProducts: payload.showProducts === true,
      storeType: ['Food', 'Pharmacy', 'Clothes', 'Market'].includes(payload.storeType) ? payload.storeType : null,
      keywords: Array.isArray(payload.keywords) ? payload.keywords.filter(item => typeof item === 'string').slice(0, 5) : [],
      quantity: Math.min(Math.max(Number(payload.quantity) || 3, 1), 5),
      reply,
      isProductDiscussion: payload.isProductDiscussion === true,
      discussionProductId: Number.isFinite(Number(payload.discussionProductId)) ? Number(payload.discussionProductId) : null,
      conversationStage: this.normalizeConversationStage(payload.conversationStage, payload.showProducts === true),
      voiceProfile,
      voiceMood: voiceProfile.emotion,
      voiceIntensity: voiceProfile.energy,
      voiceCue: this.normalizeVoiceCue(legacyCue || voiceProfile.cue),
      userLanguage: userLang,
    };

    if (!this.isMostlyLanguage(normalized.reply, userLang)) return null;

    return normalized;
  }

  static normalizeVoiceMood(value) {
    const mood = String(value || '').trim().toLowerCase();
    const aliases = {
      calm: 'neutral',
      happy: 'warm',
      sad: 'disappointed',
      sorry: 'apologetic',
      cheerful: 'warm',
      serious: 'neutral',
    };
    const allowed = this.getSupportedVoiceMoods();
    const normalized = aliases[mood] || mood;
    return allowed.has(normalized) ? normalized : 'neutral';
  }

  static getSupportedConversationStages() {
    return new Set(['greeting', 'browsing', 'shopping', 'checkout', 'finished', 'support']);
  }

  static normalizeConversationStage(value, showProducts = false) {
    const stage = String(value || '').trim().toLowerCase();
    const aliases = {
      browse: 'browsing',
      browsing: 'browsing',
      explore: 'browsing',
      shopping: 'shopping',
      order: 'shopping',
      choosing: 'shopping',
      checkout: 'checkout',
      confirm: 'checkout',
      finish: 'finished',
      finished: 'finished',
      done: 'finished',
      complete: 'finished',
      support: 'support',
      help: 'support',
      greeting: 'greeting',
      hello: 'greeting',
    };

    const normalized = aliases[stage] || stage;
    if (this.getSupportedConversationStages().has(normalized)) {
      return normalized;
    }

    return showProducts ? 'shopping' : 'browsing';
  }

  static baseVoiceProfileForMood(mood) {
    const profiles = {
      neutral: { emotion: 'neutral', energy: 0.55, pace: 1, volume: 1, pitch: 1, pause: 'normal', cue: '', formality: 0.6, playfulness: 0.1 },
      excited: { emotion: 'excited', energy: 0.9, pace: 1.15, volume: 1.08, pitch: 1.1, pause: 'short', cue: 'deep_breath', formality: 0.25, playfulness: 0.5 },
      playful: { emotion: 'playful', energy: 0.7, pace: 1.08, volume: 1, pitch: 1.06, pause: 'short', cue: 'laugh', formality: 0.2, playfulness: 0.8 },
      curious: { emotion: 'curious', energy: 0.6, pace: 0.95, volume: 0.98, pitch: 1.02, pause: 'short', cue: 'pause', formality: 0.55, playfulness: 0.25 },
      caring: { emotion: 'caring', energy: 0.6, pace: 0.92, volume: 0.98, pitch: 0.98, pause: 'normal', cue: '', formality: 0.65, playfulness: 0.15 },
      whisper: { emotion: 'whisper', energy: 0.2, pace: 0.88, volume: 0.82, pitch: 0.95, pause: 'long', cue: 'whisper', formality: 0.4, playfulness: 0.05 },
      disappointed: { emotion: 'disappointed', energy: 0.35, pace: 0.9, volume: 0.92, pitch: 0.95, pause: 'long', cue: 'sigh', formality: 0.7, playfulness: 0.05 },
      apologetic: { emotion: 'apologetic', energy: 0.35, pace: 0.9, volume: 0.92, pitch: 0.95, pause: 'normal', cue: 'sigh', formality: 0.7, playfulness: 0.05 },
      warm: { emotion: 'warm', energy: 0.65, pace: 0.96, volume: 1, pitch: 1.02, pause: 'normal', cue: '', formality: 0.45, playfulness: 0.2 },
    };

    return profiles[mood] || profiles.neutral;
  }

  static normalizePause(value, fallback = 'normal') {
    const pause = String(value || '').trim().toLowerCase();
    if (['normal', 'short', 'long'].includes(pause)) return pause;
    return fallback;
  }

  static clampNumber(value, min, max, fallback) {
    const parsed = Number(value);
    if (!Number.isFinite(parsed)) return fallback;
    return Math.min(Math.max(parsed, min), max);
  }

  static normalizeVoiceProfile(profile, fallbackMood = 'neutral', fallbackCue = '', fallbackIntensity = 0.65) {
    const fallbackEmotion = this.normalizeVoiceMood(fallbackMood);
    const base = this.baseVoiceProfileForMood(fallbackEmotion);
    if (!profile || typeof profile !== 'object') {
      return {
        ...base,
        cue: this.normalizeVoiceProfileCue(fallbackCue) || base.cue,
        energy: this.normalizeVoiceIntensity(fallbackIntensity),
      };
    }

    const emotion = this.normalizeVoiceMood(profile.emotion || profile.mood || fallbackEmotion);
    const defaults = this.baseVoiceProfileForMood(emotion);
    const cue = this.normalizeVoiceProfileCue(profile.cue || fallbackCue || defaults.cue);

    return {
      emotion,
      energy: this.normalizeVoiceIntensity(profile.energy ?? profile.intensity ?? fallbackIntensity ?? defaults.energy),
      pace: this.clampNumber(profile.pace, 0.75, 1.35, defaults.pace),
      volume: this.clampNumber(profile.volume, 0.7, 1.2, defaults.volume),
      pitch: this.clampNumber(profile.pitch, 0.8, 1.25, defaults.pitch),
      pause: this.normalizePause(profile.pause, defaults.pause),
      cue,
      formality: this.clampNumber(profile.formality, 0, 1, defaults.formality),
      playfulness: this.clampNumber(profile.playfulness, 0, 1, defaults.playfulness),
    };
  }

  static normalizeVoiceIntensity(value) {
    const parsed = Number(value);
    if (!Number.isFinite(parsed)) return 0.65;
    return Math.min(Math.max(parsed, 0), 1);
  }

  static normalizeVoiceProfileCue(value) {
    const cue = String(value || '').trim().replace(/\s+/g, ' ').slice(0, 32);
    if (!cue) return '';

    const lowered = cue.toLowerCase();
    if (
      lowered === 'hey' ||
      lowered.startsWith('hey ') ||
      lowered === 'hello' ||
      lowered.startsWith('hello ') ||
      lowered === 'hi' ||
      lowered.startsWith('hi ') ||
      lowered === 'ya hla' ||
      lowered === 'يا هلا' ||
      lowered === 'اهلا' ||
      lowered === 'أهلا' ||
      lowered === 'مرحبا' ||
      lowered === 'thanks' ||
      lowered === 'thank you'
    ) {
      return '';
    }

    const aliases = {
      laugh: 'laugh_soft',
      laughing: 'laugh_soft',
      laugh_soft: 'laugh_soft',
      laugh_big: 'laugh_big',
      lol: 'laugh_soft',
      haha: 'laugh_soft',
      hehe: 'laugh_soft',
      chuckle: 'laugh_soft',
      'deep breath': 'deep_breath',
      deep_breath: 'deep_breath',
      breath: 'deep_breath',
      pause: 'pause',
      thinking: 'thinking',
      hmm: 'thinking',
      sigh: 'sigh',
      whisper: 'whisper',
      psst: 'whisper',
    };

    return aliases[lowered] || cue;
  }

  static normalizeVoiceCue(value) {
    const cue = String(value || '').trim().replace(/\s+/g, ' ').slice(0, 32);
    if (!cue) return '';

    const lowered = cue.toLowerCase();
    if (
      lowered === 'hey' ||
      lowered.startsWith('hey ') ||
      lowered === 'hello' ||
      lowered.startsWith('hello ') ||
      lowered === 'hi' ||
      lowered.startsWith('hi ') ||
      lowered === 'ya hla' ||
      lowered === 'يا هلا' ||
      lowered === 'اهلا' ||
      lowered === 'أهلا' ||
      lowered === 'مرحبا' ||
      lowered === 'thanks' ||
      lowered === 'thank you'
    ) {
      return '';
    }

    const aliases = {
      'laughing': 'laugh',
      'laugh': 'laugh',
      'laugh_soft': 'laugh',
      'laugh_big': 'laugh',
      'lol': 'laugh',
      'haha': 'laugh',
      'hehe': 'laugh',
      'chuckle': 'laugh',
      'thinking': 'pause',
      'hmm': 'pause',
      'deep breath': 'deep_breath',
      'deep_breath': 'deep_breath',
      'breath': 'deep_breath',
      'pause': 'pause',
      'sigh': 'sigh',
      'whisper': 'whisper',
    };

    const normalized = aliases[lowered] || lowered;
    const allowed = new Set(['laugh', 'deep_breath', 'pause', 'sigh', 'whisper']);
    return allowed.has(normalized) ? normalized : cue;
  }

  static isFallbackEligibleError(err) {
    const status = Number(err?.response?.status || err?.status);
    const message = String(err?.message || err?.toString?.() || '').toLowerCase();
    return status === 429 || message.includes('quota') || message.includes('rate limit') || message.includes('too many requests') || message.includes('resource exhausted');
  }

  static async callGemini(prompt, temperature = 0.35, maxOutputTokens = 512) {
    if (!this.model) {
      throw new Error('Gemini unavailable');
    }

    const response = await this.model.generateContent({
      contents: [{ parts: [{ text: prompt }] }],
      generationConfig: { temperature, maxOutputTokens },
    });

    return this.extractText(response);
  }

  static async callGroq(prompt, temperature = 0.35, maxOutputTokens = 512) {
    const apiKey = process.env.GROQ_API_KEY;
    const apiUrl = process.env.GROQ_API_URL || 'https://api.groq.com/openai/v1/chat/completions';
    const model = process.env.GROQ_MODEL || 'llama-3.3-70b-versatile';

    if (!apiKey) {
      throw new Error('GROQ_API_KEY not configured');
    }

    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 15000);

    try {
      const response = await fetch(apiUrl, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${apiKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          model,
          messages: [{ role: 'user', content: prompt }],
          temperature,
          max_tokens: maxOutputTokens,
        }),
        signal: controller.signal,
      });

      const rawText = await response.text();
      if (!response.ok) {
        throw new Error(`Groq HTTP ${response.status}: ${rawText.substring(0, 300)}`);
      }

      const payload = JSON.parse(rawText);
      const content = payload?.choices?.[0]?.message?.content?.trim();
      if (!content) {
        throw new Error('Groq returned empty content');
      }

      return content;
    } finally {
      clearTimeout(timeoutId);
    }
  }

  static async generateLLMText(prompt, { temperature = 0.35, maxOutputTokens = 512 } = {}) {
    let geminiError = null;

    if (this.model) {
      try {
        const raw = await this.callGemini(prompt, temperature, maxOutputTokens);
        if (raw && raw.trim()) {
          if (this.provider !== 'gemini') this.provider = 'gemini';
          logger.info(`[LLMRouter] provider=gemini raw=${raw.trim().substring(0, 240)}`);
          return raw.trim();
        }
        geminiError = new Error('Empty Gemini response');
      } catch (err) {
        geminiError = err;
        logger.warn(`[LLMRouter] Gemini failed, trying Groq: ${err.message}`);
      }
    }

    try {
      const raw = await this.callGroq(prompt, temperature, maxOutputTokens);
      this.provider = 'groq';
      logger.info(`[LLMRouter] Using Groq fallback${geminiError ? ` after Gemini error: ${geminiError.message}` : ''}`);
      logger.info(`[LLMRouter] provider=groq raw=${raw.trim().substring(0, 240)}`);
      return raw.trim();
    } catch (groqError) {
      if (!this.model || !this.isFallbackEligibleError(geminiError)) {
        throw groqError;
      }
      throw groqError;
    }
  }

  static isOperational() {
    return Boolean(this.model) || Boolean(process.env.GROQ_API_KEY);
  }

  static voiceCueForMood(mood, userLang) {
    const cues = {
      curious: 'pause',
      whisper: 'whisper',
      apologetic: 'sigh',
      disappointed: 'sigh',
      warm: 'pause',
      caring: 'pause',
      playful: 'laugh',
      warm: '',
      laugh: 'laugh',
      excited: 'deep_breath',
      neutral: '',
      calm: '',
    };

    return cues[mood] || '';
  }

  static validateSelectedProducts(catalog, selectedProducts) {
    const validIds = new Set((catalog || []).map(product => Number(product.id)));
    return (selectedProducts || []).filter(product => validIds.has(Number(product.id)));
  }

  static getReasonCacheKey(userMessage, products, userLang) {
    const ids = (products || []).map(product => product.id).join(',');
    return `${userLang}|${normalizeText(userMessage)}|${ids}`;
  }

  static getCachedReasons(cacheKey) {
    const value = this.reasonCache.get(cacheKey);
    if (!value) return null;
    if (Date.now() - value.timestamp > 15 * 60 * 1000) {
      this.reasonCache.delete(cacheKey);
      return null;
    }
    return value.reasons;
  }

  static setCachedReasons(cacheKey, reasons) {
    this.reasonCache.set(cacheKey, { timestamp: Date.now(), reasons });
    while (this.reasonCache.size > this.MAX_REASON_CACHE) {
      const oldestKey = this.reasonCache.keys().next().value;
      if (!oldestKey) break;
      this.reasonCache.delete(oldestKey);
    }
  }

  static getStrongIntentOverride(userMessage, shownProducts = []) {
    const decision = IntentEngine.getDecision(userMessage, shownProducts);
    return decision && decision.source === 'rule' ? decision : null;
  }

  // ─────────────────────────────────────────────
  // MEMORY
  // ─────────────────────────────────────────────
  static getMemory(userId) {
    return MemoryService.get(userId);
  }

  static getConversationMemory(userId) { return this.getMemory(userId); }

  static addToMemory(userId, role, text) {
    MemoryService.add(userId, role, text);
  }

  static setShownProducts(userId, products) {
    MemoryService.setShownProducts(userId, products);
  }

  static getShownProducts(userId) {
    return MemoryService.getShownProducts(userId);
  }

  static clearMemory(userId) {
    MemoryService.clear(userId);
  }

  // ─────────────────────────────────────────────
  // FETCH PRODUCTS
  // ─────────────────────────────────────────────
  static async fetchProducts(storeType = null, query = '', excludeIds = []) {
    try {
      const products = await ProductRetrievalService.search(query || storeType || '', {
        storeType,
        limit: 60,
        excludeIds,
      });

      if (products.length > 0) {
        return products;
      }

      // Fallback to the old broad catalog path if semantic retrieval returns nothing.
      const connection = await pool.getConnection();
      try {
        let sql = `
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
          sql += ` AND s.store_type = ?`;
          params.push(storeType);
        }
        sql += ` ORDER BY p.stock DESC, p.id LIMIT 60`;

        const [rows] = await connection.execute(sql, params);

        const baseUrl = process.env.BACKEND_URL || 'http://192.168.1.59:3000';
        return rows.map(p => ({
          ...p,
          image_url: p.image_url && !p.image_url.startsWith('http')
            ? baseUrl + p.image_url
            : (p.image_url || ''),
        }));
      } finally {
        connection.release();
      }
    } catch (err) {
      logger.error('[YShopAI] fetchProducts error:', err.message);
      return [];
    }
  }

  // ─────────────────────────────────────────────
  // STEP 1: Understand intent
  //
  // KEY CHANGE: "showProducts" controls when products appear
  //   - showProducts = true  → fetch and display products NOW
  //   - showProducts = false → just talk, no products yet
  //   - isProductDiscussion = true → user asking about already-shown product
  // ─────────────────────────────────────────────
  static async understandMessage(userMessage, history, shownProducts = [], userId = null) {
    const userLang = this.detectLanguage(userMessage);

    const cacheKey = [
      userLang,
      normalizeText(userMessage),
      shownProducts.map(product => product.id).join(','),
    ].join('|');

    const cachedIntent = this.intentCache.get(cacheKey);
    if (cachedIntent && Date.now() - cachedIntent.timestamp < 10 * 60 * 1000) {
      return cachedIntent.value;
    }

    const contextText = this.buildConversationContext(userId, history, shownProducts);
    const prompt = this.buildIntentPrompt(userMessage, contextText, userLang);

    let lastError = null;
    for (let attempt = 0; attempt < 2; attempt += 1) {
      try {
        const raw = await this.generateLLMText(prompt, {
          temperature: attempt === 0 ? 0.35 : 0.2,
          maxOutputTokens: 512,
        });
        logger.info(`[YShopAI] understandMessage raw: "${raw.substring(0, 200)}"`);

        if (!raw) {
          lastError = new Error('Empty response');
          continue;
        }

        const parsed = this.parseJSON(raw);
        logger.info(`[YShopAI] understandMessage parsed=${JSON.stringify(parsed)?.substring(0, 240) || 'null'}`);
        const validated = this.validateIntentPayload(parsed, userLang);
        if (validated) {
          logger.info(
            `[PARSED VOICE] ${JSON.stringify({
              mood: validated.voiceMood,
              intensity: validated.voiceIntensity,
              cue: validated.voiceCue,
              stage: validated.conversationStage,
            })}`
          );
          if (validated.voiceMood && !this.getSupportedVoiceMoods().has(validated.voiceMood)) {
            validated.voiceMood = 'neutral';
          }
          const intent = {
            ...validated,
            needsProducts: validated.showProducts,
            userLanguage: userLang,
          };

          this.intentCache.set(cacheKey, { timestamp: Date.now(), value: intent });
          logger.info(
            `[IntentEngine] source=llm provider=${this.provider || 'unknown'} show=${intent.showProducts} storeType=${intent.storeType || 'null'} ` +
            `discussion=${intent.isProductDiscussion} mood=${intent.voiceMood || 'neutral'} intensity=${intent.voiceIntensity?.toFixed?.(2) || '0.65'} cue=${intent.voiceCue || 'none'} stage=${intent.conversationStage || 'browsing'}`
          );
          return intent;
        }

        lastError = new Error('Invalid intent JSON');
      } catch (err) {
        lastError = err;
      }
    }

    logger.warn(`[IntentEngine] source=fallback reason=${lastError?.message || 'unknown'}`);
    const fallback = this.localIntentDetection(userMessage);
    return {
      ...fallback,
      needsProducts: fallback.showProducts,
      userLanguage: userLang,
    };
  }

  // ─────────────────────────────────────────────
  // DETECT IF USER DISCUSSING A SPECIFIC PRODUCT
  // ─────────────────────────────────────────────
  static detectProductDiscussion(userMessage, shownProducts) {
    if (!shownProducts || shownProducts.length === 0) return null;

    const messageText = this.normalizeText(userMessage);
    const messageTokens = this.tokenize(messageText);
    const messageTokenSet = new Set(messageTokens);

    const idMatch = messageText.match(/(?:#|id\s*:?\s*|product\s*:?\s*|item\s*:?\s*)(\d{1,12})/i);
    if (idMatch) {
      const matchedId = Number(idMatch[1]);
      const exact = shownProducts.find(product => Number(product.id) === matchedId);
      if (exact) return exact.id;
    }

    for (const product of shownProducts) {
      const prodNameTokens = this.tokenize(product.name);
      const prodDescTokens = this.tokenize(product.description);
      const productTokens = [...prodNameTokens, ...prodDescTokens];
      const overlap = productTokens.reduce((count, token) => count + (messageTokenSet.has(token) ? 1 : 0), 0);
      const titleOverlap = prodNameTokens.reduce((count, token) => count + (messageTokenSet.has(token) ? 1 : 0), 0);
      const descriptionOverlap = prodDescTokens.reduce((count, token) => count + (messageTokenSet.has(token) ? 1 : 0), 0);
      const priceMentioned = messageText.includes(this.normalizeText(product.price));

      if (priceMentioned) return product.id;

      const exactName = this.normalizeText(product.name);
      if (exactName && messageText.includes(exactName)) return product.id;

      const score = (titleOverlap * 4) + (descriptionOverlap * 2) + overlap;
      if (score >= 2) return product.id;
    }

    const aboutMatch = messageText.match(/(?:about|tell me about|explain|what about|this|that|these|those|one|it)\s+(.+)/i);
    if (aboutMatch) {
      const askedTokens = this.tokenize(aboutMatch[1]);
      if (askedTokens.length > 0) {
        let bestProduct = null;
        let bestScore = 0;

        for (const product of shownProducts) {
          const candidateTokens = new Set([
            ...this.tokenize(product.name),
            ...this.tokenize(product.description),
          ]);
          const score = askedTokens.reduce((total, token) => total + (candidateTokens.has(token) ? 1 : 0), 0);
          if (score > bestScore) {
            bestScore = score;
            bestProduct = product;
          }
        }

        if (bestProduct && bestScore > 0) return bestProduct.id;
      }

      return shownProducts[0].id;
    }

    return null;
  }

  // ─────────────────────────────────────────────
  // LOCAL INTENT DETECTION (fallback) 
  // ─────────────────────────────────────────────
  static localIntentDetection(msg) {
    const lang = this.detectLanguage(msg);

    const defaultReplyEn = "Please tell me a bit more.";
    const defaultReplyAr = "وضح لي أكثر.";
    const voiceProfile = this.baseVoiceProfileForMood('neutral');
    return {
      needsProducts: false, showProducts: false, storeType: null,
      keywords: [], quantity: 0, isProductDiscussion: false,
      reply: lang === 'english' ? defaultReplyEn : defaultReplyAr,
      conversationStage: 'browsing',
      voiceProfile,
      voiceMood: voiceProfile.emotion,
      voiceIntensity: voiceProfile.energy,
      voiceCue: voiceProfile.cue,
      userLanguage: lang,
    };
  }

  static inferVoiceMood(userMessage, understanding, reply, products = []) {
    const text = `${userMessage} ${reply}`.toLowerCase();

    if (understanding?.isProductDiscussion) return 'warm';
    if (text.includes('sorry') || text.includes('oops') || text.includes('couldn') || text.includes('لم') || text.includes('ما لقيت')) return 'apologetic';
    if (text.includes('whisper') || text.includes('psst')) return 'whisper';
    if (text.includes('(haha)') || text.includes('(hehe)')) return 'playful';
    if (text.includes('(hmm)') || text.includes('what exactly') || text.includes('what are you craving') || text.includes('ايش مودك') || text.includes('ايش بالضبط')) return 'curious';
    if (products.length > 0) return 'excited';
    if (understanding?.showProducts) return 'excited';
    if (text.includes('pharmacy') || text.includes('سلامتك') || text.includes('ساعدك')) return 'caring';
    return 'neutral';
  }

  static resolveVoiceMood(userMessage, understanding, reply, products = []) {
    if (understanding?.voiceProfile?.emotion) {
      return this.normalizeVoiceMood(understanding.voiceProfile.emotion);
    }

    const rawMood = understanding?.voiceMood;
    if (typeof rawMood === 'string' && rawMood.trim()) {
      return this.normalizeVoiceMood(rawMood);
    }

    return 'neutral';
  }

  static resolveVoiceCue(userMessage, understanding, reply, products = []) {
    if (typeof understanding?.voiceProfile?.cue === 'string' && understanding.voiceProfile.cue.trim()) {
      return this.normalizeVoiceCue(understanding.voiceProfile.cue);
    }

    const cue = this.normalizeVoiceCue(understanding?.voiceCue);
    return cue || '';
  }

  static resolveVoiceProfile(userMessage, understanding, reply, products = []) {
    const profile = this.normalizeVoiceProfile(
      understanding?.voiceProfile,
      understanding?.voiceMood,
      understanding?.voiceCue,
      understanding?.voiceIntensity,
    );

    // If LLM returns a flat neutral profile, add a subtle context-based profile.
    if (profile.emotion === 'neutral' && !profile.cue) {
      return this.inferVoiceProfileFromContext(userMessage, reply, understanding, products) || profile;
    }

    return profile;
  }

  static resolveConversationStage(userMessage, understanding, reply, products = [], previousProducts = []) {
    const rawStage = String(understanding?.conversationStage || '').trim();
    if (rawStage) {
      return this.normalizeConversationStage(rawStage, understanding?.showProducts === true);
    }

    const text = `${userMessage} ${reply}`.toLowerCase();
    if (/thank(s| you)|thanks a lot|perfect|great choice|i have chosen|done|that's all|that is all/.test(text)) {
      return 'finished';
    }
    if (products.length > 0) return 'shopping';
    if (understanding?.isProductDiscussion || previousProducts.length > 0) return 'support';
    if (understanding?.showProducts) return 'shopping';
    return 'browsing';
  }

  static inferVoiceProfileFromContext(userMessage, reply, understanding, products = []) {
    const text = `${userMessage} ${reply}`.toLowerCase();

    if (/(haha|hehe|lol|lmao|funny|ضحك|هههه)/.test(text)) {
      return {
        ...this.baseVoiceProfileForMood('playful'),
        cue: 'laugh_soft',
        energy: 0.68,
      };
    }

    if (/(secret|whisper|psst|سر|بالسر|همس)/.test(text)) {
      return {
        ...this.baseVoiceProfileForMood('whisper'),
        cue: 'whisper',
        energy: 0.22,
      };
    }

    if (/(i\s*am hungry|i'm hungry|hungry|starving|what should i eat|ما ادري ايش|مش عارف ايش|جوعان)/.test(text)) {
      return {
        ...this.baseVoiceProfileForMood('curious'),
        cue: 'thinking',
        energy: 0.62,
      };
    }

    if (/(didn'?t like|don't like|not good|another option|other options|something else|ما عجبني|خيار اخر|خيارات اخرى)/.test(text)) {
      return {
        ...this.baseVoiceProfileForMood('disappointed'),
        cue: 'sigh',
        energy: 0.42,
      };
    }

    if (/(wow|awesome|great deal|cheap|perfect|amazing|رهيب|ممتاز|واو)/.test(text)) {
      return {
        ...this.baseVoiceProfileForMood('excited'),
        cue: 'deep_breath',
        energy: 0.82,
      };
    }

    if (/(thank(s| you)|appreciate|great choice|i have chosen|done|تم|شكرا|يعطيك العافية)/.test(text)) {
      return {
        ...this.baseVoiceProfileForMood('warm'),
        cue: '',
        energy: 0.62,
      };
    }

    if (products.length > 0 || understanding?.showProducts) {
      return {
        ...this.baseVoiceProfileForMood('warm'),
        cue: '',
        energy: 0.6,
      };
    }

    return null;
  }

  // ─────────────────────────────────────────────
  // STEP 2: Select products with AI (catalog + keywords + memory) 
  // ─────────────────────────────────────────────
  static async selectProductsWithAI(userMessage, products, keywords, history, limit = 3) {
    const storeType = products?.[0]?.store_type || null;
    const ranked = RankingService.rankProducts(userMessage, products, {
      keywords,
      limit,
      storeType,
    });

    return this.validateSelectedProducts(products, ranked).slice(0, limit);
  }

  // ─────────────────────────────────────────────
  // STEP 3: Generate reasons (human-like + TTS) for each product 
  // ─────────────────────────────────────────────
  static async generateProductReasons(userMessage, products) {
    if (!products || products.length === 0) return products;

    const userLang = this.detectLanguage(userMessage);
    const cacheKey = this.getReasonCacheKey(userMessage, products, userLang);
    const cachedReasons = this.getCachedReasons(cacheKey);
    if (cachedReasons) {
      return products.map((product, index) => ({
        ...product,
        reason: cachedReasons[index] || (userLang === 'arabic' ? 'هذا حلو جداً، صدقني' : 'This one is solid, trust me.'),
      }));
    }

    const productList = products.map(p =>
      `- ${p.name}: ${p.description ? p.description.substring(0, 80) : 'No description'} (${p.price} ${p.currency})`
    ).join('\n');

    const prompt = `${this.PERSONALITY}

User's language: ${userLang === 'arabic' ? 'ARABIC' : 'ENGLISH'}
User asked: "${userMessage}"

Products:
${productList}

For EACH product write 1 short reason why they'd love it.
REPLY ONLY IN ${userLang === 'arabic' ? 'ARABIC' : 'ENGLISH'}
Talk like you tried it. Be specific.
NEVER use emojis. NEVER mix languages.

Return JSON only:
{"reasons":{"ProductName":"reason in ${userLang === 'arabic' ? 'ARABIC' : 'ENGLISH'}"}}`;

    try {
      const raw = await this.generateLLMText(prompt, {
        temperature: 0.5,
        maxOutputTokens: 512,
      });
      const parsed = this.parseJSON(raw);
      if (parsed?.reasons && typeof parsed.reasons === 'object') {
        const reasons = products.map(p => parsed.reasons[p.name] || (userLang === 'arabic' ? 'هذا حلو جداً، صدقني' : 'This one is solid, trust me.'));
        this.setCachedReasons(cacheKey, reasons);
        return products.map((p, index) => ({
          ...p,
          reason: reasons[index],
        }));
      }
    } catch (err) {
      logger.error('[YShopAI] generateReasons error:', err.message);
    }

    const defaultReason = userLang === 'arabic' ? 'هذا حلو جداً، صدقني' : 'This one is solid, trust me.';
    const reasons = products.map(() => defaultReason);
    this.setCachedReasons(cacheKey, reasons);
    return products.map(p => ({ ...p, reason: defaultReason }));
  }

  // ─────────────────────────────────────────────
  // KEYWORD-BASED SELECTION (no AI) for fallback or when AI doesn't return products
  // ─────────────────────────────────────────────
  static keywordSelect(products, keywords, userMessage, limit = 3) {
    const msg = userMessage.toLowerCase();
    const kws = [...keywords, ...msg.split(/\s+/).filter(w => w.length > 3)];

    const scored = products.map(p => {
      let score = 0;
      const name = (p.name || '').toLowerCase();
      const desc = (p.description || '').toLowerCase();
      for (const kw of kws) {
        if (name === kw) score += 10;
        else if (name.startsWith(kw)) score += 6;
        else if (name.includes(kw)) score += 4;
        else if (desc.includes(kw)) score += 2;
      }
      return { ...p, _score: score };
    });

    scored.sort((a, b) => b._score - a._score || b.stock - a.stock);
    return scored.slice(0, limit);
  }

  // ─────────────────────────────────────────────
  // MAIN: generateResponse - the single method to call from outside
  // ─────────────────────────────────────────────
  static async generateResponse(userMessage, userId, options = {}) {
    const traceId = options?.traceId || `${userId || 'guest'}-${Date.now()}`;
    try {
      const history = this.getMemory(userId);
      const previousProducts = this.getShownProducts(userId);
      const userLang = this.detectLanguage(userMessage);

      logger.info(
        `[YShopAI] Start | trace=${traceId} | userId=${userId} | lang=${userLang} | ` +
        `message="${String(userMessage || '').substring(0, 120)}" | history=${history.length} | previousProducts=${previousProducts.length}`
      );

      // Step 1: Understand
      const understanding = await this.understandMessage(userMessage, history, previousProducts, userId);
      logger.info(
        `[YShopAI] Intent | trace=${traceId} | userId=${userId} | lang=${userLang} | show=${understanding.showProducts} | ` +
        `store=${understanding.storeType || 'null'} | qty=${understanding.quantity || 0} | discussion=${understanding.isProductDiscussion} | ` +
        `source=${understanding.source || 'unknown'} | mood=${understanding.voiceMood || 'neutral'} | stage=${understanding.conversationStage || 'browsing'} | cue=${understanding.voiceCue || 'none'}`
      );

      let reply = understanding.reply || (userLang === 'arabic' ? "قلي ايش تشتي وانا معك" : "Tell me what you need and I'll help");
      let products = [];
      const productLimit = understanding.quantity > 0 ? Math.min(understanding.quantity, 5) : 3;
      logger.info(
        `[YShopAI] Understand | trace=${traceId} | reply="${String(reply).substring(0, 120)}" | productLimit=${productLimit}`
      );

      // ── Product discussion (about already shown products) ──
      if (understanding.isProductDiscussion && previousProducts.length > 0) {
        // If discussing a specific product, provide details about it
        let discussedProduct = null;
        if (understanding.discussionProductId) {
          discussedProduct = previousProducts.find(p => p.id === understanding.discussionProductId);
        }
        
        // If we found the product, add more detail to the reply
        if (discussedProduct && !reply.includes(discussedProduct.name)) {
          const desc = discussedProduct.description || 'No details available';
          const langNote = userLang === 'arabic' 
            ? `\n\n📦 ${discussedProduct.name}\n💰 ${discussedProduct.price}${discussedProduct.currency}\n📝 ${desc}`
            : `\n\n📦 ${discussedProduct.name}\n💰 ${discussedProduct.price}${discussedProduct.currency}\n📝 ${desc}`;
          reply += langNote;
        }
        
        this.addToMemory(userId, 'user', userMessage);
        this.addToMemory(userId, 'ai', reply);
        logger.info(
          `[YShopAI] Discussion | trace=${traceId} | productId=${discussedProduct?.id || 'none'} | reply="${String(reply).substring(0, 120)}"`
        );
        return {
          reply,
          products: [],
          voiceProfile: this.resolveVoiceProfile(userMessage, understanding, reply, []),
          conversationStage: this.resolveConversationStage(userMessage, understanding, reply, [], previousProducts),
          voiceMood: this.resolveVoiceMood(userMessage, understanding, reply, []),
          voiceIntensity: this.normalizeVoiceIntensity(understanding?.voiceIntensity),
          voiceCue: this.resolveVoiceCue(userMessage, understanding, reply, []),
        };
      }

      // ── SHOW PRODUCTS only when AI decided it's time ── 
      if (understanding.showProducts) {
        const allProducts = await this.fetchProducts(
          understanding.storeType,
          userMessage,
          previousProducts.map(p => p.id),
        );

        logger.info(
          `[YShopAI] Fetch | trace=${traceId} | store=${understanding.storeType || 'null'} | fetched=${allProducts.length} | ` +
          `exclude=${previousProducts.map(p => p.id).join(',') || 'none'}`
        );

        if (allProducts.length > 0) {
          products = await this.selectProductsWithAI(
            userMessage, allProducts, understanding.keywords || [], history, productLimit,
          );

          logger.info(
            `[YShopAI] Rank | trace=${traceId} | selected=${products.map(p => p.id).join(',') || 'none'} | keywords=${(understanding.keywords || []).join(',') || 'none'}`
          );

          if (products.length === 0) {
            products = this.keywordSelect(allProducts, understanding.keywords || [], userMessage, productLimit);
            logger.info(
              `[YShopAI] KeywordFallback | trace=${traceId} | selected=${products.map(p => p.id).join(',') || 'none'}`
            );
          }

          if (products.length > 0) {
            products = await this.generateProductReasons(userMessage, products);
            this.setShownProducts(userId, products);
            logger.info(
              `[YShopAI] Reasons | trace=${traceId} | products=${products.map(p => `${p.id}:${String(p.reason || '').substring(0, 40)}`).join(' | ')}`
            );
          }
        }

        if (products.length === 0) {
          reply = userLang === 'arabic' 
            ? "(hmm) ما لقيت شي يناسب... <break time=\"0.3s\" /> جرب تكون اوضح شوي؟"
            : "(hmm) Couldn't find anything matching... <break time=\"0.3s\" /> Can you be more specific?";
          logger.info(`[YShopAI] EmptyResults | trace=${traceId} | reply="${reply}"`);
        }
      }
      // If showProducts is false → just return the reply, no products

      this.addToMemory(userId, 'user', userMessage);
      this.addToMemory(userId, 'ai', reply);
      const voiceProfile = this.resolveVoiceProfile(userMessage, understanding, reply, products);
      const voiceMood = this.resolveVoiceMood(userMessage, understanding, reply, products);
      const voiceIntensity = this.normalizeVoiceIntensity(voiceProfile.energy ?? understanding?.voiceIntensity);
      const voiceCue = this.resolveVoiceCue(userMessage, understanding, reply, products);
      const conversationStage = this.resolveConversationStage(userMessage, understanding, reply, products, previousProducts);

      logger.info(
        `[YShopAI] Voice | trace=${traceId} | mood=${voiceMood} | stage=${conversationStage} | intensity=${voiceIntensity.toFixed(2)} | cue=${voiceCue || 'none'}`
      );

      logger.info(
        `[YShopAI] Result | trace=${traceId} | userId=${userId} | lang=${userLang} | show=${understanding.showProducts} | ` +
        `products=${products.length} | reply="${reply.substring(0, 120)}"`
      );

      return { reply, products, voiceProfile, conversationStage, voiceMood, voiceIntensity, voiceCue };

    } catch (err) {
      logger.error('[YShopAI] generateResponse error:', err.message);
      const userLang = this.detectLanguage(userMessage);
      const fallback = userLang === 'arabic' 
        ? "اوف صار شي غلط... <break time=\"0.3s\" /> جرب مره ثانيه"
        : "Oops something went wrong... <break time=\"0.3s\" /> Try again?";
      this.addToMemory(userId, 'user', userMessage);
      this.addToMemory(userId, 'ai', fallback);
      const voiceProfile = this.baseVoiceProfileForMood('neutral');
      return {
        reply: fallback,
        products: [],
        voiceProfile,
        conversationStage: 'browsing',
        voiceMood: voiceProfile.emotion,
        voiceIntensity: voiceProfile.energy,
        voiceCue: voiceProfile.cue,
      };
    }
  }

  // ─────────────────────────────────────────────
  // BACKWARD COMPAT METHODS (for older code that calls these directly)
  // ─────────────────────────────────────────────
  static async findRelevantProducts() { return []; }
  static getRecommendationReason() { return 'Recommended for you'; }
  static extractIntent() { return 'GENERAL_INQUIRY'; }

  // ─────────────────────────────────────────────
  // CLEANUP
  // ─────────────────────────────────────────────
  static cleanupMemory() {
    MemoryService.cleanup();

    for (const [key, value] of this.intentCache.entries()) {
      if (Date.now() - value.timestamp > 10 * 60 * 1000) {
        this.intentCache.delete(key);
      }
    }

    for (const [key, value] of this.reasonCache.entries()) {
      if (Date.now() - value.timestamp > 15 * 60 * 1000) {
        this.reasonCache.delete(key);
      }
    }
  }
}

// ─────────────────────────────────────────────
// AUTO INIT
// ─────────────────────────────────────────────
if (process.env.YSHOP_AI_ENABLED !== 'false') {
  try {
    YShopAIService.initialize();
    setInterval(() => YShopAIService.cleanupMemory(), YShopAIService.CLEANUP_INTERVAL_MS);
  } catch (err) {
    logger.warn('[YShopAI] Init warning:', err.message);
  }
}