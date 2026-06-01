// IRetrievalService.js
export class IRetrievalService {
  static async search(query, filters = {}) { // eslint-disable-line no-unused-vars
    throw new Error('IRetrievalService.search must be implemented');
  }

  static clearCache() {}
}
