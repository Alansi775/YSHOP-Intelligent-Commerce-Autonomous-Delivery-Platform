import 'package:flutter/foundation.dart';
import 'dart:io' show Platform;

/// 🌍 Centralized API Configuration
/// Update base URLs here and all endpoints will use them automatically
class ApiConfig {
  // ================== ENVIRONMENT DETECTION ==================
  /// Production API host, baked in at build time via:
  ///   flutter build web --dart-define=API_BASE_URL=https://<host>
  /// Falls back to the stable production backend so a plain `flutter build web`
  /// still produces a working release build.
  static const String _prodApiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://yshop-imac.tail11c7de.ts.net',
  );

  /// Detects platform and returns appropriate base URL
  static String get baseUrl {
    if (kIsWeb) {
      // Never derive the backend host from the page's own host — Flutter Web
      // is served from Firebase Hosting, which is a completely different
      // origin from the API server. Always use the fixed production API host.
      return '$_prodApiBaseUrl/api/v1';
    }
    try {
      if (Platform.isAndroid) {
        return 'http://127.0.0.1:3000/api/v1';
      }
    } catch (_) {}
    return 'http://Mohammeds-Mackbook-MacBook-Air.local:3000/api/v1';
  }

  /// Raw host without /api/v1
  static String get baseHost => baseUrl.replaceFirst(RegExp(r'/api/v1/?$'), '');

  /// Server port (extracted from baseUrl)
  static const int serverPort = 3000;

  // ================== AUTHENTICATION ENDPOINTS ==================
  static const String customerLoginEndpoint = '/auth/login';
  static const String customerSignupEndpoint = '/auth/signup';
  static const String storeLoginEndpoint = '/auth/store-login';
  static const String storeSignupEndpoint = '/auth/store-signup';
  static const String deliveryLoginEndpoint = '/auth/delivery-login';
  static const String deliverySignupEndpoint = '/auth/delivery-signup';
  static const String adminLoginEndpoint = '/admin/login';

  // ================== ADMIN ENDPOINTS ==================
  /// Dashboard and statistics
  static const String adminDashboardStatsEndpoint = '/stores/admin/dashboard-stats';
  
  /// Stores management
  static const String adminGetAllStoresEndpoint = '/admins/stores/all';
  static const String adminGetPendingStoresEndpoint = '/admins/stores/pending';
  static const String adminGetApprovedStoresEndpoint = '/admins/stores/approved';
  static const String adminApproveStoreEndpoint = '/admins/stores/{storeId}/approve';
  static const String adminRejectStoreEndpoint = '/admins/stores/{storeId}/reject';
  static const String adminBanStoreEndpoint = '/admins/stores/{storeId}/ban';

  /// Products management
  static const String adminGetPendingProductsEndpoint = '/products/admin/pending';
  static const String adminGetApprovedProductsEndpoint = '/products/admin/approved';

  // ================== STORE ENDPOINTS ==================
  static const String storePublicEndpoint = '/stores/public';
  static const String storeUpdatesEndpoint = '/stores/updates-since';

  // ================== USER ENDPOINTS ==================
  static const String userProfileEndpoint = '/users/profile';
  static const String userUpdateProfileEndpoint = '/users/profile/update';

  // ================== TIMEOUT CONFIGURATION ==================
  static const Duration requestTimeout = Duration(seconds: 30);
  static const Duration shortTimeout = Duration(seconds: 10);

  // ================== RETRY CONFIGURATION ==================
  static const int maxRetries = 3;
  static const Duration retryDelay = Duration(milliseconds: 500);

  // ================== CACHING CONFIGURATION ==================
  /// Enable/disable response caching
  static const bool enableCaching = true;
  
  /// Cache duration for different endpoints
  static const Duration cacheDurationDefault = Duration(minutes: 5);
  static const Duration cacheDurationShort = Duration(minutes: 1);
  static const Duration cacheDurationLong = Duration(hours: 1);

  // ================== LOGGING ==================
  /// Enable API request/response logging
  static const bool enableLogging = true;

  // ================== VALIDATION ==================
  /// Validate URLs before making requests
  static bool validateUrl(String path) {
    try {
      final url = '$baseUrl$path';
      Uri.parse(url);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Get complete URL for an endpoint
  static String getUrl(String endpoint) {
    return '$baseUrl$endpoint';
  }

  /// Replace path parameters in endpoint
  /// Example: replacePath('/stores/{storeId}', {'storeId': '123'})
  static String replacePath(String endpoint, Map<String, String> params) {
    String result = endpoint;
    params.forEach((key, value) {
      result = result.replaceAll('{$key}', value);
    });
    return result;
  }
}
