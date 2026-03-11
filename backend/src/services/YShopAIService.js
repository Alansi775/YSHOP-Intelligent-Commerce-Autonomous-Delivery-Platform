import { GoogleGenerativeAI } from '@google/generative-ai';
import logger from '../config/logger.js';
import pool from '../config/database.js';

/**
 * YSHOP AI Service - v6
 * Conversation flow: AI talks first, products come only when ready
 */
export class YShopAIService {
  static client = null;
  static model = null;
  static conversationMemory = new Map();
  static shownProducts = new Map();

  // ─────────────────────────────────────────────
  // INIT
  // ─────────────────────────────────────────────
  static initialize() {
    if (!process.env.YSHOP_AI_API_KEY) {
      throw new Error('YSHOP_AI_API_KEY not configured in .env');
    }
    const genAI = new GoogleGenerativeAI(process.env.YSHOP_AI_API_KEY);
    this.client = genAI;
    this.model = genAI.getGenerativeModel({
      model: process.env.YSHOP_AI_MODEL || 'gemini-2.0-flash',
    });
    logger.info('✅ YSHOP AI initialized successfully');
  }

  // ─────────────────────────────────────────────
  // PERSONALITY
  // ─────────────────────────────────────────────
  static get PERSONALITY() {
    return `You are "Youssef", a shopping buddy at YSHOP. You talk like a real friend — casual, warm, sometimes funny.

Voice rules:
- Talk like a friend, NOT a customer service bot
- Match the user's language (Arabic = Arabic, English = English)
- NEVER say "Great choice!", "How can I assist you?", "I'd be happy to help"
- Say things like "Ooh nice taste!", "Man you're gonna love this", "Honestly? This one's fire"
- Keep it SHORT — 1-2 sentences, like texting a friend
- NEVER use emojis

TTS tags (use naturally, not every sentence):
- <break time="0.5s" /> for pauses
- (haha) or (hehe) for light laughs
- (hmm) for thinking
- ... for trailing off`;
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
      let cleaned = text
        .replace(/^```json\s*/im, '')
        .replace(/^```\s*/im, '')
        .replace(/```\s*$/im, '')
        .trim();
      if (cleaned.startsWith('{')) {
        try { return JSON.parse(cleaned); } catch { /* continue */ }
      }
      const match = cleaned.match(/\{[\s\S]*\}/);
      if (match) {
        try { return JSON.parse(match[0]); } catch { /* continue */ }
      }
      return null;
    } catch {
      return null;
    }
  }

  // ─────────────────────────────────────────────
  // MEMORY
  // ─────────────────────────────────────────────
  static getMemory(userId) {
    if (!this.conversationMemory.has(userId)) {
      this.conversationMemory.set(userId, []);
    }
    return this.conversationMemory.get(userId);
  }

  static getConversationMemory(userId) { return this.getMemory(userId); }

  static addToMemory(userId, role, text) {
    const mem = this.getMemory(userId);
    mem.push({ role, text, timestamp: Date.now() });
    if (mem.length > 20) mem.shift();
  }

  static setShownProducts(userId, products) {
    this.shownProducts.set(userId, products);
  }

  static getShownProducts(userId) {
    return this.shownProducts.get(userId) || [];
  }

  static clearMemory(userId) {
    this.conversationMemory.delete(userId);
    this.shownProducts.delete(userId);
  }

  // ─────────────────────────────────────────────
  // FETCH PRODUCTS
  // ─────────────────────────────────────────────
  static async fetchProducts(storeType = null) {
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
      query += ` ORDER BY p.stock DESC, p.id LIMIT 60`;

      const [rows] = await connection.execute(query, params);
      connection.release();

      const baseUrl = process.env.BACKEND_URL || 'http://localhost:3000';
      return rows.map(p => ({
        ...p,
        image_url: p.image_url && !p.image_url.startsWith('http')
          ? baseUrl + p.image_url
          : (p.image_url || ''),
      }));
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
  // ─────────────────────────────────────────────
  static async understandMessage(userMessage, history, shownProducts = []) {
    const historyText = history.slice(-6)
      .map(m => `${m.role === 'user' ? 'User' : 'Youssef'}: ${m.text}`)
      .join('\n');

    const shownContext = shownProducts.length > 0
      ? `\nProducts user already saw:\n${shownProducts.map(p => `- ${p.name} (${p.price} ${p.currency}) from ${p.store_name}: ${(p.description || '').substring(0, 100)}`).join('\n')}\n`
      : '';

    const prompt = `${this.PERSONALITY}

Chat so far:
${historyText || '(first message)'}
${shownContext}
User: "${userMessage}"

Store types: Food, Pharmacy, Clothes, Market

Return JSON:
{"showProducts":true/false,"storeType":"Food"/null,"keywords":[],"quantity":3,"reply":"...","isProductDiscussion":false}

CRITICAL RULE — showProducts:
- showProducts = false when you want to TALK first (greetings, asking questions, narrowing down what they want)
- showProducts = true ONLY when you are READY to present products (user gave enough info)

Examples:
- User: "hi" → showProducts:false, reply: greet and ask what they want
- User: "I'm hungry" → showProducts:false, reply: ask what kind of food / what mood
- User: "I want a burger" → showProducts:true, reply: "let me show you..." storeType:"Food" keywords:["burger"]
- User: "anything, surprise me" → showProducts:true, reply: "alright check these out..."
- User: "tell me about the cruncher" → showProducts:false, isProductDiscussion:true, reply: talk about that product

Other rules:
- isProductDiscussion = true if discussing a product already shown
- quantity = number user asked for (1-5), default 3
- reply = your friendly response with TTS tags
- Return ONLY JSON`;

    try {
      const response = await this.model.generateContent({
        contents: [{ role: 'user', parts: [{ text: prompt }] }],
        generationConfig: { temperature: 0.4, maxOutputTokens: 1024 },
      });

      const raw = this.extractText(response);
      logger.info(`[YShopAI] understandMessage raw: "${raw.substring(0, 200)}"`);

      if (!raw) {
        logger.warn('[YShopAI] Empty response — local fallback');
        return this.localIntentDetection(userMessage);
      }

      const parsed = this.parseJSON(raw);
      if (parsed && parsed.reply) {
        // Normalize fields and apply defaults
        parsed.showProducts = parsed.showProducts === true;
        parsed.quantity = Math.min(Math.max(parsed.quantity || 3, 1), 5);
        parsed.isProductDiscussion = parsed.isProductDiscussion || false;

        // Backward compat: map to needsProducts for older code that checks it
        parsed.needsProducts = parsed.showProducts;

        logger.info(`[YShopAI] Intent | show=${parsed.showProducts} | store=${parsed.storeType} | qty=${parsed.quantity} | discussion=${parsed.isProductDiscussion}`);
        return parsed;
      }

      logger.warn('[YShopAI] Parse failed — local fallback');
      return this.localIntentDetection(userMessage);

    } catch (err) {
      logger.error('[YShopAI] understandMessage error:', err.message);
      return this.localIntentDetection(userMessage);
    }
  }

  // ─────────────────────────────────────────────
  // LOCAL INTENT DETECTION (fallback) 
  // ─────────────────────────────────────────────
  static localIntentDetection(msg) {
    const m = msg.toLowerCase();

    const qtyMatch = m.match(/(\d+)\s+\w/);
    const wordQty = { one: 1, two: 2, three: 3, four: 4, five: 5,
      واحد: 1, اثنين: 2, ثلاث: 3, اربع: 4, خمس: 5, حبه: 1, حبتين: 2 };
    let quantity = 3;
    if (qtyMatch) {
      quantity = Math.min(Math.max(parseInt(qtyMatch[1]), 1), 5);
    } else {
      for (const [word, num] of Object.entries(wordQty)) {
        if (m.includes(word)) { quantity = num; break; }
      }
    }

    // Greetings — talk only, no products 
    const greetings = ['hello', 'hi ', 'hey', 'greetings', 'good morning', 'good evening',
      'مرحبا', 'السلام', 'هلا', 'اهلا', 'صباح', 'مساء', 'how are'];
    if (greetings.some(g => m.includes(g)) && m.length < 50 && !m.includes('want') && !m.includes('need') && !m.includes('burger') && !m.includes('pizza')) {
      return {
        needsProducts: false, showProducts: false, storeType: null,
        keywords: [], quantity: 0, isProductDiscussion: false,
        reply: "(hmm) يا هلا والله! <break time=\"0.3s\" /> وش تبي تاكل اليوم؟ قلي وانا ادبرك",
      };
    }

    // Vague hunger — ASK first, don't show products yet 
    const vagueHunger = ['hungry', 'hunger', 'جوعان', 'عطشان', 'i want to eat', 'i want food',
      'اكل', 'جعت', 'ابي اكل'];
    const specificFood = ['burger', 'pizza', 'chicken', 'rice', 'sandwich', 'coffee', 'tea',
      'water', 'juice', 'cake', 'snack', 'برجر', 'بيتزا', 'دجاج', 'ماء'];

    const hasSpecific = specificFood.some(w => m.includes(w));
    const hasVague = vagueHunger.some(w => m.includes(w));

    // User said something specific like "I want a burger" → show products
    if (hasSpecific) {
      const keywords = specificFood.filter(w => m.includes(w)).slice(0, 3);
      return {
        needsProducts: true, showProducts: true, storeType: 'Food',
        keywords, quantity, isProductDiscussion: false,
        reply: "تمام <break time=\"0.2s\" /> خلني اجيب لك خيارات حلوه",
      };
    }

    // User is vague "I'm hungry" → ask what kind, NO products
    if (hasVague) {
      return {
        needsProducts: false, showProducts: false, storeType: null,
        keywords: [], quantity: 0, isProductDiscussion: false,
        reply: "(hmm) وش مودك اليوم؟ <break time=\"0.3s\" /> برجر؟ بيتزا؟ ولا شي خفيف؟",
      };
    }

    // Pharmacy
    const pharmaWords = ['medicine', 'pharmacy', 'health', 'sick', 'pain', 'pill',
      'vitamin', 'headache', 'fever', 'دواء', 'صيدليه'];
    if (pharmaWords.some(w => m.includes(w))) {
      return {
        needsProducts: true, showProducts: true, storeType: 'Pharmacy',
        keywords: pharmaWords.filter(w => m.includes(w)).slice(0, 3),
        reply: "سلامتك! <break time=\"0.3s\" /> خلني اشوف لك شي يساعدك",
        quantity, isProductDiscussion: false,
      };
    }

    // Clothes 
    const clothesWords = ['clothes', 'shirt', 'dress', 'shoes', 'fashion', 'jacket',
      'ملابس', 'قميص', 'فستان'];
    if (clothesWords.some(w => m.includes(w))) {
      return {
        needsProducts: true, showProducts: true, storeType: 'Clothes',
        keywords: clothesWords.filter(w => m.includes(w)).slice(0, 3),
        reply: "تبي تتأنق؟ (haha) <break time=\"0.3s\" /> خلني اعطيك خيارات",
        quantity, isProductDiscussion: false,
      };
    }

    // Market
    const marketWords = ['market', 'grocery', 'vegetable', 'fruit', 'خضار', 'فاكهة', 'سوق'];
    if (marketWords.some(w => m.includes(w))) {
      return {
        needsProducts: true, showProducts: true, storeType: 'Market',
        keywords: marketWords.filter(w => m.includes(w)).slice(0, 3),
        reply: "طازج وفريش! <break time=\"0.3s\" /> خلني اشوف وش عندنا",
        quantity, isProductDiscussion: false,
      };
    }

    // "another" / "different" — show products 
    if (m.includes('another') || m.includes('different') || m.includes('other') ||
        m.includes('change') || m.includes('else') || m.includes('غير') || m.includes('ثاني')) {
      return {
        needsProducts: true, showProducts: true, storeType: null, keywords: [],
        reply: "تبي شي ثاني؟ اوكي <break time=\"0.3s\" /> خلني اغير لك",
        quantity, isProductDiscussion: false,
      };
    }

    // "surprise me" / "anything" — show products
    if (m.includes('surprise') || m.includes('anything') || m.includes('whatever') ||
        m.includes('اي شي') || m.includes('فاجئني')) {
      return {
        needsProducts: true, showProducts: true, storeType: null, keywords: [],
        reply: "<prosody rate=\"fast\">اوكي اوكي</prosody> <break time=\"0.2s\" /> شوف هذي",
        quantity, isProductDiscussion: false,
      };
    }

    // "I want..." (vague) — ask what
    if (m.includes('want') || m.includes('need') || m.includes('looking for') ||
        m.includes('find') || m.includes('show') || m.includes('get me') ||
        m.includes('اريد') || m.includes('ابغى') || m.includes('بغيت')) {
      return {
        needsProducts: false, showProducts: false, storeType: null,
        keywords: [], quantity: 0, isProductDiscussion: false,
        reply: "تمام <break time=\"0.2s\" /> وش بالضبط تدور عليه؟",
      };
    }

    // Default — just chat
    return {
      needsProducts: false, showProducts: false, storeType: null,
      keywords: [], quantity: 0, isProductDiscussion: false,
      reply: "قلي وش تبي وانا اساعدك <break time=\"0.3s\" /> اكل؟ ملابس؟ شي من الصيدلية؟",
    };
  }

  // ─────────────────────────────────────────────
  // STEP 2: Select products with AI (catalog + keywords + memory) 
  // ─────────────────────────────────────────────
  static async selectProductsWithAI(userMessage, products, keywords, history, limit = 3) {
    const catalog = products.slice(0, 50).map(p =>
      `${p.id}|${p.name}|${p.description.substring(0, 50)}|${p.price}${p.currency}`
    ).join('\n');

    const shownIds = [];
    for (const m of history.slice(-6)) {
      const matches = m.text?.match(/\[shown:([^\]]+)\]/g);
      if (matches) {
        matches.forEach(match => {
          const id = parseInt(match.replace('[shown:', '').replace(']', ''));
          if (!isNaN(id)) shownIds.push(id);
        });
      }
    }

    const prompt = `Pick the ${limit} BEST products for: "${userMessage}"
Keywords: ${keywords.join(', ') || 'any'}
${shownIds.length > 0 ? `Already shown (avoid): ${shownIds.join(', ')}` : ''}

Products:
${catalog}

Return JSON only: {"ids":[id1,id2]}`;

    try {
      const response = await this.model.generateContent({
        contents: [{ role: 'user', parts: [{ text: prompt }] }],
        generationConfig: { temperature: 0.1, maxOutputTokens: 256 },
      });

      const raw = this.extractText(response);
      const parsed = this.parseJSON(raw);
      if (parsed?.ids?.length) {
        const selected = products.filter(p => parsed.ids.includes(p.id));
        if (selected.length > 0) return selected.slice(0, limit);
      }
    } catch (err) {
      logger.error('[YShopAI] selectProducts error:', err.message);
    }

    return this.keywordSelect(products, keywords, userMessage, limit);
  }

  // ─────────────────────────────────────────────
  // STEP 3: Generate reasons (human-like + TTS) for each product 
  // ─────────────────────────────────────────────
  static async generateProductReasons(userMessage, products) {
    if (!products || products.length === 0) return products;

    const productList = products.map(p =>
      `- ${p.name}: ${p.description ? p.description.substring(0, 80) : 'No description'} (${p.price} ${p.currency})`
    ).join('\n');

    const prompt = `${this.PERSONALITY}

User asked: "${userMessage}"

Products:
${productList}

For EACH product write 1 short friend-style reason why they'd love it.
Talk like you tried it. Be specific. Use TTS tags where natural.
NEVER use emojis.

Return JSON only:
{"reasons":{"ProductName":"reason"}}`;

    try {
      const response = await this.model.generateContent({
        contents: [{ role: 'user', parts: [{ text: prompt }] }],
        generationConfig: { temperature: 0.5, maxOutputTokens: 512 },
      });

      const raw = this.extractText(response);
      const parsed = this.parseJSON(raw);
      if (parsed?.reasons && typeof parsed.reasons === 'object') {
        return products.map(p => ({
          ...p,
          reason: parsed.reasons[p.name] || 'This one is solid, trust me.',
        }));
      }
    } catch (err) {
      logger.error('[YShopAI] generateReasons error:', err.message);
    }

    return products.map(p => ({ ...p, reason: 'This one is solid, trust me.' }));
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
  static async generateResponse(userMessage, userId) {
    try {
      const history = this.getMemory(userId);
      const previousProducts = this.getShownProducts(userId);

      // Step 1: Understand
      const understanding = await this.understandMessage(userMessage, history, previousProducts);

      let reply = understanding.reply || "(hmm) قلي وش تبي وانا معك";
      let products = [];
      const productLimit = understanding.quantity > 0 ? Math.min(understanding.quantity, 5) : 3;

      // ── Product discussion (about already shown products) ──
      if (understanding.isProductDiscussion && previousProducts.length > 0) {
        this.addToMemory(userId, 'user', userMessage);
        this.addToMemory(userId, 'ai', reply);
        return { reply, products: [] };
      }

      // ── SHOW PRODUCTS only when AI decided it's time ── 
      if (understanding.showProducts) {
        const allProducts = await this.fetchProducts(understanding.storeType);

        if (allProducts.length > 0) {
          products = await this.selectProductsWithAI(
            userMessage, allProducts, understanding.keywords || [], history, productLimit,
          );

          if (products.length === 0) {
            products = this.keywordSelect(allProducts, understanding.keywords || [], userMessage, productLimit);
          }

          if (products.length > 0) {
            products = await this.generateProductReasons(userMessage, products);
            this.setShownProducts(userId, products);
          }
        }

        if (products.length === 0) {
          reply = "(hmm) ما لقيت شي يناسب... <break time=\"0.3s\" /> جرب تكون اوضح شوي؟";
        }
      }
      // If showProducts is false → just return the reply, no products

      this.addToMemory(userId, 'user', userMessage);
      this.addToMemory(userId, 'ai', reply);

      logger.info(
        `[YShopAI] Result | userId=${userId} | show=${understanding.showProducts} | ` +
        `products=${products.length} | reply="${reply.substring(0, 60)}"`
      );

      return { reply, products };

    } catch (err) {
      logger.error('[YShopAI] generateResponse error:', err.message);
      const fallback = "اوف صار شي غلط... <break time=\"0.3s\" /> جرب مره ثانيه";
      this.addToMemory(userId, 'user', userMessage);
      this.addToMemory(userId, 'ai', fallback);
      return { reply: fallback, products: [] };
    }
  }

  // ─────────────────────────────────────────────
  // BACKWARD COMPAT METHODS (for older code that calls these directly)
  // ─────────────────────────────────────────────
  static async findRelevantProducts() { return []; }
  static getRecommendationReason() { return 'Recommended for you'; }
  static extractIntent() { return 'GENERAL_INQUIRY'; }

  // ─────────────────────────────────────────────
  // CLEANUP in memory to prevent bloat (keep only last 2 hours of conversation)
  // ─────────────────────────────────────────────
  static cleanupMemory() {
    const cutoff = Date.now() - 2 * 60 * 60 * 1000;
    for (const [uid, msgs] of this.conversationMemory.entries()) {
      const fresh = msgs.filter(m => m.timestamp > cutoff);
      if (fresh.length === 0) this.conversationMemory.delete(uid);
      else this.conversationMemory.set(uid, fresh);
    }
  }
}

// ─────────────────────────────────────────────
// AUTO INIT and periodic cleanup when enabled via env variable
// ─────────────────────────────────────────────
if (process.env.YSHOP_AI_ENABLED !== 'false') {
  try {
    YShopAIService.initialize();
    setInterval(() => YShopAIService.cleanupMemory(), 30 * 60 * 1000);
  } catch (err) {
    logger.warn('[YShopAI] Init warning:', err.message);
  }
}