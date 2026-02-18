import { GoogleGenerativeAI } from '@google/generative-ai';
import logger from '../config/logger.js';
import pool from '../config/database.js';

/**
 * YSHOP AI Service - v4
 * Fixed: Proper response extraction + safety filter handling
 */
export class YShopAIService {
  static client = null;
  static model = null;
  static conversationMemory = new Map();

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
  // SAFE TEXT EXTRACTOR
  // Handles all the ways Gemini can return text
  // ─────────────────────────────────────────────
  static extractText(response) {
    try {
      // Method 1: Standard .text() method
      if (response?.response?.text) {
        const t = response.response.text();
        if (t && t.trim().length > 0) return t.trim();
      }

      // Method 2: Direct candidates access
      const candidates = response?.response?.candidates;
      if (candidates && candidates.length > 0) {
        const candidate = candidates[0];

        // Check finish reason
        if (candidate.finishReason && candidate.finishReason !== 'STOP') {
          logger.warn(`[YShopAI] Finish reason: ${candidate.finishReason}`);
        }

        const parts = candidate?.content?.parts;
        if (parts && parts.length > 0) {
          const text = parts.map(p => p.text || '').join('');
          if (text.trim().length > 0) return text.trim();
        }
      }

      // Method 3: promptFeedback check
      const feedback = response?.response?.promptFeedback;
      if (feedback?.blockReason) {
        logger.warn(`[YShopAI] Blocked: ${feedback.blockReason}`);
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
      // Remove markdown fences
      let cleaned = text
        .replace(/^```json\s*/im, '')
        .replace(/^```\s*/im, '')
        .replace(/```\s*$/im, '')
        .trim();

      // Try direct parse
      if (cleaned.startsWith('{')) {
        try { return JSON.parse(cleaned); } catch { /* continue */ }
      }

      // Extract JSON object
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
  static shownProducts = new Map(); // userId → last shown products

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
          p.id,
          p.name,
          COALESCE(p.description, '') AS description,
          p.price,
          p.currency,
          p.stock,
          p.image_url,
          s.name      AS store_name,
          s.store_type,
          s.email AS store_owner_email
        FROM products p
        JOIN stores s ON p.store_id = s.id
        WHERE p.status  = 'approved'
          AND p.is_active = 1
          AND s.status  = 'approved'
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
  // Simple & focused prompt — avoids safety filters
  // ─────────────────────────────────────────────
  static async understandMessage(userMessage, history, shownProducts = []) {
    const historyText = history.slice(-6)
      .map(m => `${m.role === 'user' ? 'User' : 'AI'}: ${m.text}`)
      .join('\n');

    // Build context of previously shown products
    const shownContext = shownProducts.length > 0
      ? `\nProducts currently shown to user:\n${shownProducts.map(p => `- ${p.name} (${p.price} ${p.currency}) from ${p.store_name}: ${(p.description || '').substring(0, 80)}`).join('\n')}\n`
      : '';

    const prompt = `Task: Analyze this shopping assistant message and return JSON.

Previous chat:
${historyText || 'none'}
${shownContext}
User said: "${userMessage}"

Store types available: Food, Pharmacy, Clothes, Market

Return this exact JSON format:
{"needsProducts":true,"storeType":"Food","keywords":["burger","meal"],"quantity":3,"reply":"Great choice! Let me find something delicious for you.","isProductDiscussion":false}

OR if user is asking/discussing about a product already shown (e.g. "tell me more about X", "is it good?", "what's in the cruncher?"):
{"needsProducts":false,"storeType":null,"keywords":[],"quantity":0,"reply":"The Cruncher is a crispy chicken sandwich with ...","isProductDiscussion":true}

OR if casual greeting:
{"needsProducts":false,"storeType":null,"keywords":[],"quantity":0,"reply":"Hello! What can I help you find today?","isProductDiscussion":false}

Rules:
- needsProducts = true if user wants to buy/find products
- isProductDiscussion = true if user is asking about a product already shown to them. In this case, use the product details shown above to give a helpful, convincing answer about that product.
- storeType = Food if hungry/thirsty/food/drink, Pharmacy if medicine/health, Clothes if fashion, Market if groceries
- keywords = specific product words only
- quantity = how many products the user asked for. If user says "one water" or "1 burger" return 1. If they say "2 meals" return 2. If no specific quantity, default to 3. Maximum is 5.
- reply = friendly 1 sentence, same language as user. If isProductDiscussion, give a detailed helpful answer about that product (price, description, store, etc.)
- NEVER use emojis in the reply
- Return ONLY the JSON, nothing else`;

    try {
      const response = await this.model.generateContent({
        contents: [{ role: 'user', parts: [{ text: prompt }] }],
        generationConfig: {
          temperature: 0.1,
          maxOutputTokens: 1024,
          stopSequences: [],
        },
      });

      const raw = this.extractText(response);
      logger.info(`[YShopAI] understandMessage raw: "${raw.substring(0, 200)}"`);

      if (!raw) {
        logger.warn('[YShopAI] Empty AI response — using local intent detection');
        return this.localIntentDetection(userMessage);
      }

      const parsed = this.parseJSON(raw);
      if (parsed && parsed.reply) {
        logger.info(`[YShopAI] Understood | needsProducts=${parsed.needsProducts} | store=${parsed.storeType} | qty=${parsed.quantity || 3} | discussion=${parsed.isProductDiscussion || false}`);
        // Ensure quantity defaults
        parsed.quantity = Math.min(Math.max(parsed.quantity || 3, 1), 5);
        parsed.isProductDiscussion = parsed.isProductDiscussion || false;
        return parsed;
      }

      logger.warn('[YShopAI] Could not parse JSON — using local detection');
      return this.localIntentDetection(userMessage);

    } catch (err) {
      logger.error('[YShopAI] understandMessage error:', err.message);
      return this.localIntentDetection(userMessage);
    }
  }

  // ─────────────────────────────────────────────
  // LOCAL INTENT DETECTION
  // Runs when AI fails — no API call needed
  // ─────────────────────────────────────────────
  static localIntentDetection(msg) {
    const m = msg.toLowerCase();

    // Extract quantity from message
    const qtyMatch = m.match(/(\d+)\s+\w/);
    const wordQty = { one: 1, two: 2, three: 3, four: 4, five: 5,
      واحد: 1, اثنين: 2, ثلاث: 3, اربع: 4, خمس: 5,
      حبه: 1, حبتين: 2 };
    let quantity = 3; // default
    if (qtyMatch) {
      quantity = Math.min(Math.max(parseInt(qtyMatch[1]), 1), 5);
    } else {
      for (const [word, num] of Object.entries(wordQty)) {
        if (m.includes(word)) { quantity = num; break; }
      }
    }

    // Greetings
    const greetings = ['hello', 'hi ', 'hey', 'greetings', 'good morning', 'good evening',
      'مرحبا', 'السلام', 'هلا', 'اهلا', 'صباح', 'مساء'];
    if (greetings.some(g => m.includes(g)) && m.length < 40 && !m.includes('want') && !m.includes('need')) {
      return {
        needsProducts: false,
        storeType: null,
        keywords: [],
        quantity: 0,
        isProductDiscussion: false,
        reply: "Hello! Welcome to YSHOP. What can I help you find today?",
      };
    }

    // Food / Hunger / Thirst
    const foodWords = ['food', 'eat', 'hungry', 'hunger', 'hungary', 'meal', 'lunch', 'dinner',
      'breakfast', 'burger', 'pizza', 'chicken', 'rice', 'drink', 'water', 'juice',
      'thirsty', 'beverage', 'coffee', 'tea', 'snack', 'dessert', 'cake', 'sandwich',
      'جوعان', 'عطشان', 'اكل', 'طعام', 'شرب', 'ماء'];
    if (foodWords.some(w => m.includes(w))) {
      const keywords = foodWords.filter(w => m.includes(w) && w.length > 3);
      return {
        needsProducts: true,
        storeType: 'Food',
        keywords: keywords.slice(0, 3),
        reply: "Great! Let me find some delicious options for you.",
        quantity: quantity,
        isProductDiscussion: false,
      };
    }

    // Pharmacy / Health
    const pharmaWords = ['medicine', 'pharmacy', 'health', 'sick', 'pain', 'pill', 'tablet',
      'vitamin', 'doctor', 'headache', 'fever', 'cold', 'treatment', 'دواء', 'صيدليه'];
    if (pharmaWords.some(w => m.includes(w))) {
      return {
        needsProducts: true,
        storeType: 'Pharmacy',
        keywords: pharmaWords.filter(w => m.includes(w)).slice(0, 3),
        reply: "I'll find the right healthcare products for you.",
        quantity: quantity,
        isProductDiscussion: false,
      };
    }

    // Clothes / Fashion
    const clothesWords = ['clothes', 'shirt', 'dress', 'shoes', 'fashion', 'jacket', 'pants',
      'outfit', 'wear', 'style', 'ملابس', 'قميص', 'فستان'];
    if (clothesWords.some(w => m.includes(w))) {
      return {
        needsProducts: true,
        storeType: 'Clothes',
        keywords: clothesWords.filter(w => m.includes(w)).slice(0, 3),
        reply: "Let me show you some great fashion options.",
        quantity: quantity,
        isProductDiscussion: false,
      };
    }

    // Market / Grocery
    const marketWords = ['market', 'grocery', 'vegetable', 'fruit', 'fresh', 'organic', 'produce',
      'خضار', 'فاكهة', 'سوق'];
    if (marketWords.some(w => m.includes(w))) {
      return {
        needsProducts: true,
        storeType: 'Market',
        keywords: marketWords.filter(w => m.includes(w)).slice(0, 3),
        reply: "I'll find fresh market products for you.",
        quantity: quantity,
        isProductDiscussion: false,
      };
    }

    // "Give me another", "different option"
    if (m.includes('another') || m.includes('different') || m.includes('other') ||
        m.includes('change') || m.includes('else') || m.includes('more')) {
      return {
        needsProducts: true,
        storeType: null,
        keywords: [],
        reply: "Sure! Let me find you something different.",
        quantity: quantity,
        isProductDiscussion: false,
      };
    }

    // "I want ..."
    if (m.includes('want') || m.includes('need') || m.includes('looking for') ||
        m.includes('find') || m.includes('show') || m.includes('get me') ||
        m.includes('اريد') || m.includes('ابغى') || m.includes('بغيت')) {
      return {
        needsProducts: true,
        storeType: null,
        keywords: [],
        reply: "I'll help you find that! Let me search our products for you.",
        quantity: quantity,
        isProductDiscussion: false,
      };
    }

    // Default — ask what they want
    return {
      needsProducts: false,
      storeType: null,
      keywords: [],
      reply: "I'm here to help! What would you like to find today?",
      quantity: 0,
      isProductDiscussion: false,
    };
  }

  // ─────────────────────────────────────────────
  // STEP 2: Select products with AI
  // ─────────────────────────────────────────────
  static async selectProductsWithAI(userMessage, products, keywords, history, limit = 3) {
    // Build compact catalog
    const catalog = products.slice(0, 50).map(p =>
      `${p.id}|${p.name}|${p.description.substring(0, 50)}|${p.price}${p.currency}`
    ).join('\n');

    // Get IDs shown before (to avoid repeating)
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

    const prompt = `Pick ${limit} products for: "${userMessage}"
Keywords: ${keywords.join(', ') || 'any'}
${shownIds.length > 0 ? `Already shown IDs (avoid): ${shownIds.join(', ')}` : ''}

Products (id|name|description|price):
${catalog}

Return JSON only:
{"ids":[id1,id2,id3]}`;

    try {
      const response = await this.model.generateContent({
        contents: [{ role: 'user', parts: [{ text: prompt }] }],
        generationConfig: { temperature: 0.1, maxOutputTokens: 256 },
      });

      const raw = this.extractText(response);
      logger.info(`[YShopAI] selectProducts raw: "${raw.substring(0, 100)}"`);

      const parsed = this.parseJSON(raw);
      if (parsed?.ids?.length) {
        const selected = products.filter(p => parsed.ids.includes(p.id));
        if (selected.length > 0) return selected.slice(0, limit);
      }
    } catch (err) {
      logger.error('[YShopAI] selectProducts error:', err.message);
    }

    // Fallback: keyword-based selection
    return this.keywordSelect(products, keywords, userMessage, limit);
  }

  // ─────────────────────────────────────────────
  // STEP 3: Generate smart reasons for products using AI
  // ─────────────────────────────────────────────
  static async generateProductReasons(userMessage, products) {
    if (!products || products.length === 0) return products;

    const productList = products.map(p =>
      `- ${p.name}: ${p.description ? p.description.substring(0, 60) : 'No description'}`
    ).join('\n');

    const prompt = `User asked: "${userMessage}"

Here are the products we're showing them:
${productList}

For EACH product, write ONE short, catchy reason why they should try it (1-2 sentences max).
Be specific, relevant to their request, and enthusiastic but professional.
NEVER use emojis.

Return JSON only:
{"reasons":{"<product_name>":"reason text here", "<product_name_2>":"reason text here"}}`;

    try {
      const response = await this.model.generateContent({
        contents: [{ role: 'user', parts: [{ text: prompt }] }],
        generationConfig: { temperature: 0.3, maxOutputTokens: 512 },
      });

      const raw = this.extractText(response);
      logger.info(`[YShopAI] generateReasons raw: "${raw.substring(0, 150)}"`);

      const parsed = this.parseJSON(raw);
      if (parsed?.reasons && typeof parsed.reasons === 'object') {
        return products.map(p => ({
          ...p,
          reason: parsed.reasons[p.name] || 'Great choice for you!',
        }));
      }
    } catch (err) {
      logger.error('[YShopAI] generateReasons error:', err.message);
    }

    // Fallback: generic reasons
    return products.map(p => ({
      ...p,
      reason: 'Excellent choice for you!',
    }));
  }

  // ─────────────────────────────────────────────
  // KEYWORD-BASED PRODUCT SELECTION (no AI needed)
  // ─────────────────────────────────────────────
  static keywordSelect(products, keywords, userMessage, limit = 3) {
    const msg = userMessage.toLowerCase();
    const kws = [...keywords, ...msg.split(/\s+/).filter(w => w.length > 3)];

    // Score each product
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

    // Sort by score, then by stock
    scored.sort((a, b) => b._score - a._score || b.stock - a.stock);

    logger.info(`[YShopAI] keywordSelect top 3: ${scored.slice(0, 3).map(p => `${p.name}(${p._score})`).join(', ')}`);

    return scored.slice(0, limit);
  }

  // ─────────────────────────────────────────────
  // MAIN ENTRY: generateResponse
  // ─────────────────────────────────────────────
  static async generateResponse(userMessage, userId) {
    try {
      const history = this.getMemory(userId);
      const previousProducts = this.getShownProducts(userId);

      // Step 1: Understand message (pass shown products for context)
      const understanding = await this.understandMessage(userMessage, history, previousProducts);

      let reply = understanding.reply || "I'm here to help! What would you like today?";
      let products = [];

      // Determine product limit from quantity (default 3, max 5)
      const productLimit = understanding.quantity > 0 ? Math.min(understanding.quantity, 5) : 3;

      // Handle product discussion (user asking about previously shown products)
      if (understanding.isProductDiscussion && previousProducts.length > 0) {
        // No new product fetch — just return the AI's discussion reply
        this.addToMemory(userId, 'user', userMessage);
        this.addToMemory(userId, 'ai', reply);

        logger.info(
          `[YShopAI] ProductDiscussion | userId=${userId} | ` +
          `shownProducts=${previousProducts.length} | reply="${reply.substring(0, 60)}"`
        );

        return { reply, products: [] };
      }

      // Step 2: Find products if needed
      if (understanding.needsProducts) {
        const allProducts = await this.fetchProducts(understanding.storeType);

        if (allProducts.length > 0) {
          // Try AI selection first
          products = await this.selectProductsWithAI(
            userMessage,
            allProducts,
            understanding.keywords || [],
            history,
            productLimit,
          );

          // If AI selection failed, use keyword selection
          if (products.length === 0) {
            logger.warn('[YShopAI] AI selection failed, using keyword select');
            products = this.keywordSelect(
              allProducts,
              understanding.keywords || [],
              userMessage,
              productLimit,
            );
          }

          // Step 3: Generate smart reasons for each product using AI
          if (products.length > 0) {
            products = await this.generateProductReasons(userMessage, products);
            // Save shown products for future discussion
            this.setShownProducts(userId, products);
          }
        }

        if (products.length === 0) {
          reply = "I couldn't find matching products right now. Try being more specific!";
        }
      }

      // Save to memory
      this.addToMemory(userId, 'user', userMessage);
      this.addToMemory(userId, 'ai', reply);

      logger.info(
        `[YShopAI] Result | userId=${userId} | ` +
        `products=${products.length} | limit=${productLimit} | reply="${reply.substring(0, 60)}"`
      );

      return { reply, products };

    } catch (err) {
      logger.error('[YShopAI] generateResponse error:', err.message);
      const fallback = "Sorry, I'm having trouble. Please try again!";
      this.addToMemory(userId, 'user', userMessage);
      this.addToMemory(userId, 'ai', fallback);
      return { reply: fallback, products: [] };
    }
  }

  // ─────────────────────────────────────────────
  // BACKWARD COMPAT
  // ─────────────────────────────────────────────
  static async findRelevantProducts() { return []; }
  static getRecommendationReason() { return 'Recommended for you'; }
  static extractIntent() { return 'GENERAL_INQUIRY'; }

  // ─────────────────────────────────────────────
  // CLEANUP
  // ─────────────────────────────────────────────
  static cleanupMemory() {
    const cutoff = Date.now() - 2 * 60 * 60 * 1000;
    for (const [uid, msgs] of this.conversationMemory.entries()) {
      const fresh = msgs.filter(m => m.timestamp > cutoff);
      if (fresh.length === 0) this.conversationMemory.delete(uid);
      else this.conversationMemory.set(uid, fresh);
    }
    logger.debug('[YShopAI] Memory cleanup done');
  }
}

// ─────────────────────────────────────────────
// AUTO INIT
// ─────────────────────────────────────────────
if (process.env.YSHOP_AI_ENABLED !== 'false') {
  try {
    YShopAIService.initialize();
    setInterval(() => YShopAIService.cleanupMemory(), 30 * 60 * 1000);
  } catch (err) {
    logger.warn('[YShopAI] Init warning:', err.message);
  }
}