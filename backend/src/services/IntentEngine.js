// IntentEngine.js
import { normalizeText, tokenize, unique } from '../utils/textProcessing.js';

export class IntentEngine {
  static detectLanguage(text) {
    return /[\u0600-\u06FF]/.test(text || '') ? 'arabic' : 'english';
  }

  static buildReply(language, englishReply, arabicReply) {
    return language === 'arabic' ? arabicReply : englishReply;
  }

  static detectStoreType(message) {
    const text = normalizeText(message);
    const tokens = new Set(tokenize(message));

    const groups = [
      {
        storeType: 'Pharmacy',
        terms: ['medicine', 'medication', 'pharmacy', 'pill', 'tablet', 'vitamin', 'health', 'sick', 'pain', 'fever', 'headache', 'دواء', 'صيدلية', 'حبة', 'فيتامين', 'ألم', 'صداع'],
      },
      {
        storeType: 'Clothes',
        terms: ['clothes', 'clothing', 'shirt', 'dress', 'shoes', 'fashion', 'jacket', 'outfit', 'wear', 'ملابس', 'قميص', 'فستان', 'حذاء', 'موضة'],
      },
      {
        storeType: 'Market',
        terms: ['market', 'grocery', 'groceries', 'vegetable', 'fruit', 'fresh', 'supermarket', 'خضار', 'فاكهة', 'سوق', 'بقال'],
      },
      {
        storeType: 'Food',
        terms: ['food', 'meal', 'eat', 'eating', 'restaurant', 'burger', 'pizza', 'chicken', 'rice', 'sandwich', 'snack', 'coffee', 'tea', 'water', 'juice', 'breakfast', 'lunch', 'dinner', 'اكل', 'طعام', 'وجبة', 'برجر', 'بيتزا', 'دجاج', 'سناك', 'عصير', 'ماء'],
      },
    ];

    for (const group of groups) {
      const normalizedTerms = group.terms.map(term => normalizeText(term));
      const score = normalizedTerms.reduce((count, term) => {
        if (!term) return count;
        if (text.includes(term)) return count + 1;
        return count + (tokens.has(term) ? 1 : 0);
      }, 0);

      if (score > 0) return group.storeType;
    }

    return null;
  }

  static detectProductDiscussion(message, shownProducts = []) {
    if (!shownProducts.length) return null;

    const messageText = normalizeText(message);
    const messageTokens = new Set(tokenize(messageText));

    const idMatch = messageText.match(/(?:#|id\s*:??\s*|product\s*:??\s*|item\s*:??\s*)(\d{1,12})/i);
    if (idMatch) {
      const matchedId = Number(idMatch[1]);
      const exact = shownProducts.find(product => Number(product.id) === matchedId);
      if (exact) return exact.id;
    }

    let bestId = null;
    let bestScore = 0;

    for (const product of shownProducts) {
      const nameTokens = tokenize(product.name);
      const descTokens = tokenize(product.description);
      const productTokens = unique([...nameTokens, ...descTokens]);

      const overlap = productTokens.reduce((count, token) => count + (messageTokens.has(token) ? 1 : 0), 0);
      const titleOverlap = nameTokens.reduce((count, token) => count + (messageTokens.has(token) ? 1 : 0), 0);
      const descriptionOverlap = descTokens.reduce((count, token) => count + (messageTokens.has(token) ? 1 : 0), 0);
      const exactName = normalizeText(product.name);
      const priceMentioned = messageText.includes(normalizeText(product.price));

      if (priceMentioned || (exactName && messageText.includes(exactName))) {
        return product.id;
      }

      const score = (titleOverlap * 4) + (descriptionOverlap * 2) + overlap;
      if (score > bestScore) {
        bestScore = score;
        bestId = product.id;
      }
    }

    if (bestScore >= 2) return bestId;

    const aboutMatch = messageText.match(/(?:about|tell me about|explain|what about|this|that|these|those|one|it)\s+(.+)/i);
    if (aboutMatch) {
      const askedTokens = tokenize(aboutMatch[1]);
      let bestProduct = null;
      let topScore = 0;

      for (const product of shownProducts) {
        const candidateTokens = new Set([...tokenize(product.name), ...tokenize(product.description)]);
        const score = askedTokens.reduce((total, token) => total + (candidateTokens.has(token) ? 1 : 0), 0);
        if (score > topScore) {
          topScore = score;
          bestProduct = product;
        }
      }

      if (bestProduct && topScore > 0) return bestProduct.id;
      return shownProducts[0].id;
    }

    return null;
  }

  static getDecision(message, shownProducts = []) {
    const language = this.detectLanguage(message);
    const storeType = this.detectStoreType(message);
    const discussionProductId = this.detectProductDiscussion(message, shownProducts);
    const text = normalizeText(message);

    const strongProduct = Boolean(storeType);
    const greetingOnly = ['hello', 'hi', 'hey', 'how are you', 'good morning', 'good evening', 'مرحبا', 'هلا', 'اهلا', 'السلام'];
    const vagueOnly = ['want', 'need', 'looking for', 'find', 'show', 'get me', 'i want', 'ابغى', 'اريد', 'ودي', 'احتاج', 'ايش', 'اشي'];

    const isGreeting = greetingOnly.some(phrase => text.includes(normalizeText(phrase)));
    const isVague = vagueOnly.some(phrase => text.includes(normalizeText(phrase)));

    if (discussionProductId) {
      return {
        showProducts: false,
        storeType: null,
        confidence: 0.97,
        source: 'rule',
        isProductDiscussion: true,
        discussionProductId,
        reply: this.buildReply(
          language,
          'Yep, let me break that product down for you',
          'أكيد، هذا المنتج خلني أوضح لك عنه أكثر'
        ),
      };
    }

    if (strongProduct) {
      const replyMap = {
        Food: ['Awesome! Let me find some good food options for you', 'تمام <break time="0.2s" /> خلني اجيب لك خيارات أكل حلوة'],
        Pharmacy: ['Got it, let me find what you need', 'سلامتك! <break time="0.3s" /> خلني اشوف لك شي يساعدك'],
        Clothes: ['Nice, let me show you some fresh styles', 'حلو! <break time="0.3s" /> خلني اعطيك خيارات أنيقة'],
        Market: ['Fresh and clean, let me see what we have', 'طازج وفريش! <break time="0.3s" /> خلني اشوف ايش عندنا'],
      };

      const [englishReply, arabicReply] = replyMap[storeType] || ['Sure, let me look that up', 'تمام، خلني أبحث لك'];
      return {
        showProducts: true,
        storeType,
        confidence: 0.95,
        source: 'rule',
        isProductDiscussion: false,
        discussionProductId: null,
        reply: this.buildReply(language, englishReply, arabicReply),
      };
    }

    if (isGreeting && !isVague) {
      return {
        showProducts: false,
        storeType: null,
        confidence: 0.88,
        source: 'rule',
        isProductDiscussion: false,
        discussionProductId: null,
        reply: this.buildReply(language, 'Hey! What are you in the mood for today?', '(hmm) يا هلا والله! <break time="0.3s" /> ايش تشتي اليوم؟'),
      };
    }

    if (isVague) {
      return {
        showProducts: true,
        storeType: null,
        confidence: 0.76,
        source: 'rule',
        isProductDiscussion: false,
        discussionProductId: null,
        reply: this.buildReply(language, 'Sure, let me show you some options', 'تفضل، خلني أعطيك خيارات'),
      };
    }

    return {
      showProducts: true,
      storeType: null,
      confidence: 0.5,
      source: 'ml',
      isProductDiscussion: false,
      discussionProductId: null,
      reply: this.buildReply(language, 'Let me find something for you', 'خلني أشوف لك شي'),
    };
  }
}
