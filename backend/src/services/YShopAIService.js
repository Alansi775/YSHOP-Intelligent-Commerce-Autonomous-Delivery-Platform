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
  // DETECT LANGUAGE
  // ─────────────────────────────────────────────
  static detectLanguage(text) {
    const arabicRegex = /[\u0600-\u06FF]/;
    return arabicRegex.test(text) ? 'arabic' : 'english';
  }

  // ─────────────────────────────────────────────
  // PERSONALITY
  // ─────────────────────────────────────────────
  static get PERSONALITY() {
    return `You are "Youssef", a shopping buddy at YSHOP. You talk like a real friend — casual, warm, sometimes funny.

Voice rules:
- Talk like a friend, NOT a customer service bot
- MATCH the user's language exactly: if they write in Arabic→reply ONLY in Arabic, if English→reply ONLY in English
- NEVER say "Great choice!", "How can I assist you?", "I'd be happy to help"
- Say things like "Ooh nice taste!", "Man you're gonna love this", "Honestly? This one's fire" (in user's language)
- Keep it SHORT — 1-2 sentences, like texting a friend
- NEVER use emojis
- NEVER mix languages

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
  //   - isProductDiscussion = true → user asking about already-shown product
  // ─────────────────────────────────────────────
  static async understandMessage(userMessage, history, shownProducts = []) {
    const userLang = this.detectLanguage(userMessage);

    const historyText = history.slice(-6)
      .map(m => `${m.role === 'user' ? 'User' : 'Youssef'}: ${m.text}`)
      .join('\n');

    const shownContext = shownProducts.length > 0
      ? `\nProducts user already saw:\n${shownProducts.map(p => `- ID:${p.id} | ${p.name} | ${p.price}${p.currency} | from ${p.store_name} | ${(p.description || '').substring(0, 100)}`).join('\n')}\n`
      : '';

    const prompt = `${this.PERSONALITY}

User's language: ${userLang === 'arabic' ? 'ARABIC' : 'ENGLISH'} — REPLY ONLY IN ${userLang === 'arabic' ? 'ARABIC' : 'ENGLISH'}

Chat so far:
${historyText || '(first message)'}
${shownContext}
User: "${userMessage}"

Store types: Food, Pharmacy, Clothes, Market

Return JSON:
{"showProducts":true/false,"storeType":"Food"/null,"keywords":[],"quantity":3,"reply":"...","isProductDiscussion":false,"discussionProductId":null}

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

Examples:
- User: "hi" → showProducts:false, isProductDiscussion:false, reply: greet in same language
- User: "tell me about burger" (with burger shown) → showProducts:false, isProductDiscussion:true, discussionProductId:XXX
- User: "I want a burger" (new request) → showProducts:true
- User: "why this one?" (about shown product) → showProducts:false, isProductDiscussion:true

Other:
- quantity = number user asked for (1-5), default 3
- reply = friendly response in user's language
- Return ONLY JSON`;

    try {
      const response = await this.model.generateContent({
        contents: [{ parts: [{ text: prompt }] }],
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
        parsed.discussionProductId = parsed.discussionProductId || this.detectProductDiscussion(userMessage, shownProducts);
        parsed.userLanguage = userLang;

        // Backward compat: map to needsProducts for older code that checks it
        parsed.needsProducts = parsed.showProducts;

        logger.info(`[YShopAI] Intent | lang=${userLang} | show=${parsed.showProducts} | store=${parsed.storeType} | qty=${parsed.quantity} | discussion=${parsed.isProductDiscussion}`);
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
  // DETECT IF USER DISCUSSING A SPECIFIC PRODUCT
  // ─────────────────────────────────────────────
  static detectProductDiscussion(userMessage, shownProducts) {
    if (!shownProducts || shownProducts.length === 0) return null;
    
    const m = userMessage.toLowerCase();
    
    // Check if user mentions product by name, price, or description
    for (const product of shownProducts) {
      const prodName = product.name.toLowerCase();
      const prodPrice = String(product.price).toLowerCase();
      const prodDesc = (product.description || '').toLowerCase();
      
      // Match by name
      if (m.includes(prodName) || prodName.includes(m.split(' ')[0])) {
        return product.id;
      }
      
      // Match by price
      if (m.includes(prodPrice) || m.includes(`${product.price}`)) {
        return product.id;
      }
      
      // Match by keywords in description
      const keywords = prodDesc.split(/\s+/).filter(w => w.length > 3);
      if (keywords.some(kw => m.includes(kw))) {
        return product.id;
      }
    }
    
    // Check if asking "about this/that" + descriptor
    const aboutMatch = m.match(/(?:about|tell me about|explain|what about|this|that|these|those|one|it)\s+(.+)/);
    if (aboutMatch && shownProducts.length > 0) {
      // Usually refers to the first or last shown product if context is unclear
      return shownProducts[0].id;
    }
    
    return null;
  }

  // ─────────────────────────────────────────────
  // LOCAL INTENT DETECTION (fallback) 
  // ─────────────────────────────────────────────
  static localIntentDetection(msg) {
    const m = msg.toLowerCase();
    const lang = this.detectLanguage(msg);

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
    const greetingsEn = ['hello', 'hi ', 'hey', 'greetings', 'good morning', 'good evening', 'how are'];
    const greetingsAr = ['مرحبا', 'السلام', 'هلا', 'اهلا', 'صباح', 'مساء'];
    const isGreeting = (lang === 'english' && greetingsEn.some(g => m.includes(g))) || 
                       (lang === 'arabic' && greetingsAr.some(g => m.includes(g)));
    
    if (isGreeting && m.length < 50 && !m.includes('want') && !m.includes('need') && !m.includes('burger') && !m.includes('pizza') &&
        !m.includes('ابي') && !m.includes('ابغى') && !m.includes('اريد')) {
      const replyEn = "Hey! What are you in the mood for today? Hungry for something?";
      const replyAr = "(hmm) يا هلا والله! <break time=\"0.3s\" /> ايش تشتي تاكل اليوم؟ قلي وانا اساعدك";
      return {
        needsProducts: false, showProducts: false, storeType: null,
        keywords: [], quantity: 0, isProductDiscussion: false,
        reply: lang === 'english' ? replyEn : replyAr,
        userLanguage: lang,
      };
    }

    // Vague hunger — ASK first, don't show products yet 
    const vagueHungerEn = ['hungry', 'hunger', 'i want to eat', 'i want food', 'starving'];
    const vagueHungerAr = ['جوعان', 'عطشان', 'اكل', 'جعت', 'ابي اكل'];
    const specificFoodEn = ['burger', 'pizza', 'chicken', 'rice', 'sandwich', 'coffee', 'tea', 'water', 'juice', 'cake', 'snack'];
    const specificFoodAr = ['برجر', 'بيتزا', 'دجاج', 'ماء', 'عصير', 'قهوة', 'شاي', 'كيك', 'ساندوتش'];

    const hasSpecific = (lang === 'english' && specificFoodEn.some(w => m.includes(w))) ||
                        (lang === 'arabic' && specificFoodAr.some(w => m.includes(w)));
    const hasVague = (lang === 'english' && vagueHungerEn.some(w => m.includes(w))) ||
                     (lang === 'arabic' && vagueHungerAr.some(w => m.includes(w)));

    // User said something specific like "I want a burger" → show products
    if (hasSpecific) {
      const keywordsEn = specificFoodEn.filter(w => m.includes(w)).slice(0, 3);
      const keywordsAr = specificFoodAr.filter(w => m.includes(w)).slice(0, 3);
      const keywords = lang === 'english' ? keywordsEn : keywordsAr;
      const replyEn = "Awesome! Let me find some great options for you";
      const replyAr = "تمام <break time=\"0.2s\" /> خلني اجيب لك خيارات حلوه";
      return {
        needsProducts: true, showProducts: true, storeType: 'Food',
        keywords, quantity, isProductDiscussion: false,
        reply: lang === 'english' ? replyEn : replyAr,
        userLanguage: lang,
      };
    }

    // User is vague "I'm hungry" → ask what kind, NO products
    if (hasVague) {
      const replyEn = "(hmm) What are you craving? Burger? Pizza? Something light?";
      const replyAr = "(hmm) ايش مودك اليوم؟ <break time=\"0.3s\" /> برجر؟ بيتزا؟ ولا شي خفيف؟";
      return {
        needsProducts: false, showProducts: false, storeType: null,
        keywords: [], quantity: 0, isProductDiscussion: false,
        reply: lang === 'english' ? replyEn : replyAr,
        userLanguage: lang,
      };
    }

    // Pharmacy
    const pharmaWordsEn = ['medicine', 'pharmacy', 'health', 'sick', 'pain', 'pill', 'vitamin', 'headache', 'fever'];
    const pharmaWordsAr = ['دواء', 'صيدليه', 'صحة', 'مريض', 'ألم', 'حبة', 'فيتامين', 'صداع'];
    const pharmaWords = lang === 'english' ? pharmaWordsEn : pharmaWordsAr;
    const hasPharm = pharmaWords.some(w => m.includes(w));
    
    if (hasPharm) {
      const replyEn = "Got it, let me find what you need";
      const replyAr = "سلامتك! <break time=\"0.3s\" /> خلني اشوف لك شي يساعدك";
      return {
        needsProducts: true, showProducts: true, storeType: 'Pharmacy',
        keywords: pharmaWords.filter(w => m.includes(w)).slice(0, 3),
        reply: lang === 'english' ? replyEn : replyAr,
        quantity, isProductDiscussion: false,
        userLanguage: lang,
      };
    }

    // Clothes 
    const clothesWordsEn = ['clothes', 'shirt', 'dress', 'shoes', 'fashion', 'jacket'];
    const clothesWordsAr = ['ملابس', 'قميص', 'فستان', 'حذاء'];
    const clothesWords = lang === 'english' ? clothesWordsEn : clothesWordsAr;
    const hasClothes = clothesWords.some(w => m.includes(w));
    
    if (hasClothes) {
      const replyEn = "Let me show you some fresh styles";
      const replyAr = "تشتي تتأنق؟ (haha) <break time=\"0.3s\" /> خلني اعطيك خيارات";
      return {
        needsProducts: true, showProducts: true, storeType: 'Clothes',
        keywords: clothesWords.filter(w => m.includes(w)).slice(0, 3),
        reply: lang === 'english' ? replyEn : replyAr,
        quantity, isProductDiscussion: false,
        userLanguage: lang,
      };
    }

    // Market
    const marketWordsEn = ['market', 'grocery', 'vegetable', 'fruit'];
    const marketWordsAr = ['خضار', 'فاكهة', 'سوق', 'بقال'];
    const marketWords = lang === 'english' ? marketWordsEn : marketWordsAr;
    const hasMarket = marketWords.some(w => m.includes(w));
    
    if (hasMarket) {
      const replyEn = "Fresh and clean! Let me see what we have";
      const replyAr = "طازج وفريش! <break time=\"0.3s\" /> خلني اشوف ايش عندنا";
      return {
        needsProducts: true, showProducts: true, storeType: 'Market',
        keywords: marketWords.filter(w => m.includes(w)).slice(0, 3),
        reply: lang === 'english' ? replyEn : replyAr,
        quantity, isProductDiscussion: false,
        userLanguage: lang,
      };
    }

    // "another" / "different" — show products 
    if ((lang === 'english' && (m.includes('another') || m.includes('different') || m.includes('other') || m.includes('change') || m.includes('else'))) ||
        (lang === 'arabic' && (m.includes('غير') || m.includes('ثاني') || m.includes('تاني')))) {
      const replyEn = "Want something different? Let me grab some new ones";
      const replyAr = "تشتي شي ثاني؟ اوكي <break time=\"0.3s\" /> خلني اغير لك";
      return {
        needsProducts: true, showProducts: true, storeType: null, keywords: [],
        reply: lang === 'english' ? replyEn : replyAr,
        quantity, isProductDiscussion: false,
        userLanguage: lang,
      };
    }

    // "surprise me" / "anything" — show products
    if ((lang === 'english' && (m.includes('surprise') || m.includes('anything') || m.includes('whatever'))) ||
        (lang === 'arabic' && (m.includes('اي شي') || m.includes('فاجئني') || m.includes('ادهشني')))) {
      const replyEn = "Alright, let me blow your mind with these";
      const replyAr = "<prosody rate=\"fast\">اوكي اوكي</prosody> <break time=\"0.2s\" /> شوف هذي";
      return {
        needsProducts: true, showProducts: true, storeType: null, keywords: [],
        reply: lang === 'english' ? replyEn : replyAr,
        quantity, isProductDiscussion: false,
        userLanguage: lang,
      };
    }

    // "I want..." (vague) — ask what
    if ((lang === 'english' && (m.includes('want') || m.includes('need') || m.includes('looking for') || m.includes('find') || m.includes('show') || m.includes('get me'))) ||
        (lang === 'arabic' && (m.includes('اريد') || m.includes('ابغى') || m.includes('بغيت') || m.includes('ودي') || m.includes('احتاج')))) {
      const replyEn = "Sure! What exactly are you looking for?";
      const replyAr = "تمام <break time=\"0.2s\" /> ايش بالضبط تدور عليه؟";
      return {
        needsProducts: false, showProducts: false, storeType: null,
        keywords: [], quantity: 0, isProductDiscussion: false,
        reply: lang === 'english' ? replyEn : replyAr,
        userLanguage: lang,
      };
    }

    // Default — just chat
    const defaultReplyEn = "Tell me what you're looking for and I'll help you! Food? Clothes? Pharmacy?";
    const defaultReplyAr = "قلي ايش تشتي وانا اساعدك <break time=\"0.3s\" /> اكل؟ ملابس؟ شي من الصيدلية؟";
    return {
      needsProducts: false, showProducts: false, storeType: null,
      keywords: [], quantity: 0, isProductDiscussion: false,
      reply: lang === 'english' ? defaultReplyEn : defaultReplyAr,
      userLanguage: lang,
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

    const userLang = this.detectLanguage(userMessage);

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
Talk like you tried it. Be specific. Use TTS tags where natural.
NEVER use emojis. NEVER mix languages.

Return JSON only:
{"reasons":{"ProductName":"reason in ${userLang === 'arabic' ? 'ARABIC' : 'ENGLISH'}"}}`;

    try {
      const response = await this.model.generateContent({
        contents: [{ parts: [{ text: prompt }] }],
        generationConfig: { temperature: 0.5, maxOutputTokens: 512 },
      });

      const raw = this.extractText(response);
      const parsed = this.parseJSON(raw);
      if (parsed?.reasons && typeof parsed.reasons === 'object') {
        return products.map(p => ({
          ...p,
          reason: parsed.reasons[p.name] || (userLang === 'arabic' ? 'ده حلو جداً، صدقني' : 'This one is solid, trust me.'),
        }));
      }
    } catch (err) {
      logger.error('[YShopAI] generateReasons error:', err.message);
    }

    const defaultReason = userLang === 'arabic' ? 'ده حلو جداً، صدقني' : 'This one is solid, trust me.';
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
  static async generateResponse(userMessage, userId) {
    try {
      const history = this.getMemory(userId);
      const previousProducts = this.getShownProducts(userId);
      const userLang = this.detectLanguage(userMessage);

      // Step 1: Understand
      const understanding = await this.understandMessage(userMessage, history, previousProducts);

      let reply = understanding.reply || (userLang === 'arabic' ? "قلي ايش تشتي وانا معك" : "Tell me what you need and I'll help");
      let products = [];
      const productLimit = understanding.quantity > 0 ? Math.min(understanding.quantity, 5) : 3;

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
          reply = userLang === 'arabic' 
            ? "(hmm) ما لقيت شي يناسب... <break time=\"0.3s\" /> جرب تكون اوضح شوي؟"
            : "(hmm) Couldn't find anything matching... <break time=\"0.3s\" /> Can you be more specific?";
        }
      }
      // If showProducts is false → just return the reply, no products

      this.addToMemory(userId, 'user', userMessage);
      this.addToMemory(userId, 'ai', reply);

      logger.info(
        `[YShopAI] Result | userId=${userId} | lang=${userLang} | show=${understanding.showProducts} | ` +
        `products=${products.length} | reply="${reply.substring(0, 60)}"`
      );

      return { reply, products };

    } catch (err) {
      logger.error('[YShopAI] generateResponse error:', err.message);
      const userLang = this.detectLanguage(userMessage);
      const fallback = userLang === 'arabic' 
        ? "اوف صار شي غلط... <break time=\"0.3s\" /> جرب مره ثانيه"
        : "Oops something went wrong... <break time=\"0.3s\" /> Try again?";
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
  // CLEANUP
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