// textProcessing.js
export const TEXT_STOP_WORDS = new Set([
  'the', 'and', 'for', 'with', 'from', 'this', 'that', 'these', 'those', 'want', 'need', 'show',
  'me', 'you', 'your', 'our', 'are', 'is', 'to', 'of', 'a', 'an', 'in', 'on', 'at', 'it', 'its',
  'what', 'which', 'about', 'tell', 'give', 'get', 'find', 'something', 'some', 'any', 'more',
  'hello', 'hi', 'hey', 'please', 'product', 'products',
  'شي', 'اشي', 'اي', 'ايش', 'ابغى', 'ابغي', 'اريد', 'أريد', 'احتاج', 'ودي', 'فيه', 'هذا', 'هذه',
  'على', 'عن', 'من', 'الى', 'إلى', 'مع', 'و', 'أو', 'ليش', 'لش', 'وين', 'متى', 'كيف', 'ليش',
]);

export function normalizeText(text) {
  return String(text || '')
    .toLowerCase()
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^\p{L}\p{N}\s]+/gu, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

export function tokenize(text, { minLength = 2, stopWords = TEXT_STOP_WORDS } = {}) {
  const normalized = normalizeText(text);
  if (!normalized) return [];

  return normalized
    .split(/\s+/)
    .map(token => token.trim())
    .filter(token => token.length >= minLength && !stopWords.has(token));
}

export function ngrams(tokens, size = 2) {
  const items = Array.isArray(tokens) ? tokens : tokenize(tokens);
  const result = [];
  for (let index = 0; index <= items.length - size; index += 1) {
    result.push(items.slice(index, index + size).join(' '));
  }
  return result;
}

export function unique(items) {
  return [...new Set(items)];
}
