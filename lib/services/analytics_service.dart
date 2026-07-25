import 'api_service.dart';

class AnalyticsService {
  static Future<Map<String, dynamic>?> getStoreAnalytics(
    String storeId, {
    String period = 'month',
  }) async {
    try {
      final response = await ApiService.request(
        'GET',
        '/analytics/store/$storeId?period=$period',
        requiresAuth: true,
      );
      if (response['success'] == true) return response['data'];
      return null;
    } catch (_) {
      return null;
    }
  }
}
