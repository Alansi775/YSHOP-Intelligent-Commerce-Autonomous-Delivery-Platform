import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';

/// High-performance API Service optimized for millions of users
/// Features: Connection pooling, smart caching, request deduplication, retry logic
class ApiService {
  // ==================== CONFIGURATION ====================

  /// Singleton HTTP client for connection reuse (critical for performance)
  static final http.Client _httpClient = http.Client();

  /// Base API URL with platform detection
  static String get _baseUrl {
    if (kIsWeb) return 'http://localhost:3000/api/v1';
    try {
      if (Platform.isAndroid) return 'http://10.0.2.2:3000/api/v1';
    } catch (_) {}
    return 'http://localhost:3000/api/v1';
  }

  static String get baseUrl => _baseUrl;
  static String get baseHost => _baseUrl.replaceFirst(RegExp(r'/api/v1/?$'), '');

  /// Timeout configuration
  static const Duration _timeout = Duration(seconds: 30);
  static const Duration _shortTimeout = Duration(seconds: 10);

  // ==================== CACHING SYSTEM ====================

  /// Request deduplication - prevents duplicate in-flight requests
  static final Map<String, Future<dynamic>> _pendingRequests = {};

  /// Debounce timers for rapid repeated calls
  static final Map<String, Future<dynamic>?> _debouncedRequests = {};
  static final Map<String, Future<void>?> _debounceTimers = {};

  /// Cache statistics for monitoring
  static int _cacheHits = 0;
  static int _cacheMisses = 0;

  static dynamic _cacheGet(String key) {
    // Caching disabled - always return null for real-time data
    return null;
  }

  static void _cacheSet(String key, dynamic value, {int ttlSeconds = 120}) {
    // Caching disabled - no cache storage
  }

  static void _clearExpiredCache() {
    // Caching disabled - nothing to clear
  }

  /// Clear all cache (useful after logout or major updates)
  static void clearCache() {
    // Cache is now disabled for real-time data
    _pendingRequests.clear();
    _debouncedRequests.clear();
    _debounceTimers.forEach((key, timer) {
      timer?.ignore();
    });
    _debounceTimers.clear();
  }

  /// Clear pending requests only (useful when switching between stores)
  static void clearPendingRequests() {
    _pendingRequests.clear();
  }

  /// Get cache statistics for monitoring
  static Map<String, int> getCacheStats() => {
        'hits': _cacheHits,
        'misses': _cacheMisses,
        'size': 0,
        'hitRate': 0,
      };

  // ==================== AUTHENTICATION ====================

  /// Cached JWT token from backend database
  static String? _cachedToken;
  static DateTime? _tokenExpiry;
  // Admin JWT cached separately
  static String? _cachedAdminToken;
  static DateTime? _cachedAdminTokenExpiry;
  static Map<String, dynamic>? _cachedAdminProfile;
  static String? _cachedAdminRole;
  
  /// ValueNotifier to track admin role changes for UI updates
  static final ValueNotifier<String?> adminRoleNotifier = ValueNotifier<String?>(null);

  /// Set user JWT token from AuthManager
  static void setUserToken(String? token) {
    _cachedToken = token;
    if (token != null) {
      _tokenExpiry = DateTime.now().add(const Duration(days: 7));
      debugPrint(' Token set in ApiService (length: ${token.length})');
    } else {
      _tokenExpiry = null;
      debugPrint(' Token cleared from ApiService');
    }
  }

  /// Expose cached admin role (if available)
  static String? get cachedAdminRole {
    if (_cachedAdminRole != null) return _cachedAdminRole;
    try {
      final r = _cachedAdminProfile?['role'];
      if (r is String) return r;
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Set admin role
  static void setAdminRole(String? role) {
    _cachedAdminRole = role;
    adminRoleNotifier.value = role;
  }

  /// Set admin profile
  static void setAdminProfile(Map<String, dynamic>? profile) {
    _cachedAdminProfile = profile;
  }

  /// Expose cached admin id (if available)
  static String? get cachedAdminId {
    try {
      final id = _cachedAdminProfile?['id'] ?? _cachedAdminProfile?['admin_id'];
      if (id == null) return null;
      return id.toString();
    } catch (_) {
      return null;
    }
  }

  /// Get JWT token from cache or SharedPreferences
  static Future<String?> _getJwtToken() async {
    try {
      // Prefer a cached admin JWT when available (admin sessions)
      if (_cachedAdminToken != null && _cachedAdminTokenExpiry != null) {
        if (DateTime.now().isBefore(_cachedAdminTokenExpiry!.subtract(const Duration(minutes: 1)))) {
          debugPrint(' [_getJwtToken] Using cached admin token from memory');
          return _cachedAdminToken;
        } else {
          debugPrint(' [_getJwtToken] Admin token expired, clearing');
          _cachedAdminToken = null;
          _cachedAdminTokenExpiry = null;
        }
      }

      // Try restoring admin token from SharedPreferences
      try {
        final prefs = await SharedPreferences.getInstance();
        final savedToken = prefs.getString('admin_token');
        final savedExpiry = prefs.getInt('admin_token_expiry');
        debugPrint(' [_getJwtToken] Checking SharedPreferences for admin_token: ${savedToken != null ? "✓ FOUND" : "✗ NOT FOUND"}');
        if (savedToken != null && savedExpiry != null) {
          final expiry = DateTime.fromMillisecondsSinceEpoch(savedExpiry);
          if (DateTime.now().isBefore(expiry)) {
            debugPrint(' [_getJwtToken] Restored admin token from SharedPreferences');
            _cachedAdminToken = savedToken;
            _cachedAdminTokenExpiry = expiry;
            final profileJson = prefs.getString('admin_profile');
            if (profileJson != null) {
              _cachedAdminProfile = jsonDecode(profileJson) as Map<String, dynamic>;
              try {
                _cachedAdminRole = prefs.getString('admin_role');
              } catch (_) {}
            }
            return _cachedAdminToken;
          }
        }
      } catch (e) {
        debugPrint(' [_getJwtToken] Error restoring admin token: $e');
      }

      // Return cached JWT token if still valid (with 5 min buffer)
      if (_cachedToken != null && _tokenExpiry != null) {
        if (DateTime.now().isBefore(_tokenExpiry!.subtract(const Duration(minutes: 5)))) {
          debugPrint(' [_getJwtToken] Using cached JWT token from memory');
          return _cachedToken;
        }
      }

      // If cached token is expired or no expiry info, try to reload from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      if (token != null && token.isNotEmpty) {
        _cachedToken = token;
        // Reset expiry to 7 days from now
        _tokenExpiry = DateTime.now().add(const Duration(days: 7));
        debugPrint(' [_getJwtToken] Loaded JWT token from SharedPreferences');
        return _cachedToken;
      }

      debugPrint(' [_getJwtToken] No JWT token available');
      return null;
    } catch (e) {
      debugPrint('Error getting JWT token: $e');
      _cachedToken = null;
      _tokenExpiry = null;
      return null;
    }
  }

  /// Clear cached token (call on logout)
  static void clearAuthCache() {
    _cachedToken = null;
    _tokenExpiry = null;
    _cachedAdminToken = null;
    _cachedAdminTokenExpiry = null;
    _cachedAdminProfile = null;
  }

  // ==================== GENERIC REQUEST METHODS ====================

  /// Generic GET request with JWT authentication
  static Future<dynamic> getRequest(String endpoint) async {
    try {
      final token = await _getJwtToken();
      final url = Uri.parse('$_baseUrl$endpoint');

      final response = await _httpClient
          .get(
            url,
            headers: {
              'Content-Type': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
          )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else if (response.statusCode == 401) {
        throw Exception('Unauthorized: Invalid or expired token');
      } else {
        throw Exception('Error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('GET $endpoint error: $e');
      rethrow;
    }
  }

  /// Generic POST request with JWT authentication
  static Future<dynamic> postRequest(String endpoint, Map<String, dynamic> body) async {
    try {
      final token = await _getJwtToken();
      final url = Uri.parse('$_baseUrl$endpoint');

      final response = await _httpClient
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode(body),
          )
          .timeout(_timeout);

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      } else if (response.statusCode == 401) {
        throw Exception('Unauthorized: Invalid or expired token');
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('POST $endpoint error: $e');
      rethrow;
    }
  }

  /// Generic PUT request with JWT authentication
  static Future<dynamic> putRequest(String endpoint, Map<String, dynamic> body) async {
    try {
      final token = await _getJwtToken();
      final url = Uri.parse('$_baseUrl$endpoint');

      final response = await _httpClient
          .put(
            url,
            headers: {
              'Content-Type': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode(body),
          )
          .timeout(_timeout);

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      } else if (response.statusCode == 401) {
        throw Exception('Unauthorized: Invalid or expired token');
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('PUT $endpoint error: $e');
      rethrow;
    }
  }

  // Admin/staff login - tries admin then staff automatically when role='auto'
  static Future<dynamic> adminLogin(String email, String password, {String role = 'auto'}) async {
    final List<String> endpoints;
    if (role == 'admin') {
      endpoints = ['/admin/login'];
    } else if (role == 'employee' || role == 'staff') {
      endpoints = ['/staff/login'];
    } else {
      endpoints = ['/admin/login', '/staff/login'];
    }

    ApiException? lastApiEx;
    dynamic lastResponse;

    for (final endpoint in endpoints) {
      try {
        final response = await _request('POST', endpoint, body: {'email': email, 'password': password}, requiresAuth: false);
        lastResponse = response;
        final token = response['token'] as String?;
        final dynamic profileCandidate = response['data'] ?? response['admin'] ?? response['user'] ?? response['data']?['admin'];
        final Map<String, dynamic>? profile = profileCandidate is Map<String, dynamic>
          ? profileCandidate
          : (profileCandidate is Map ? Map<String, dynamic>.from(profileCandidate) : null);

        if (token != null) {
          _cachedAdminToken = token;
          try {
            final parts = token.split('.');
            if (parts.length == 3) {
              final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
              final expSec = payload['exp'];
              if (expSec is int) {
                _cachedAdminTokenExpiry = DateTime.fromMillisecondsSinceEpoch(expSec * 1000);
              } else {
                _cachedAdminTokenExpiry = DateTime.now().add(const Duration(hours: 8));
              }
            }
          } catch (_) {
            _cachedAdminTokenExpiry = DateTime.now().add(const Duration(hours: 8));
          }

          // determine actual role
          String actualRole = 'admin';
          if (endpoint.contains('/staff')) actualRole = 'employee';
          if (profile != null && profile['role'] is String) {
            actualRole = profile['role'];
            profile['role'] = actualRole;
          } else if (profile != null) {
            profile['role'] = actualRole;
          }

          // persist token/profile/role
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('admin_token', _cachedAdminToken!);
            await prefs.setInt('admin_token_expiry', _cachedAdminTokenExpiry!.millisecondsSinceEpoch);
            await prefs.setString('admin_role', actualRole);
            debugPrint(' [adminLogin] Admin token saved to SharedPreferences. Role: $actualRole');
            if (profile != null) {
              final profileJson = jsonEncode(profile);
              await prefs.setString('admin_profile', profileJson);
              _cachedAdminProfile = Map<String, dynamic>.from(profile);
              debugPrint(' [adminLogin] Admin profile saved: ${profile['email']}');
            }
          } catch (_) {}

          return response;
        }
      } on ApiException catch (ae) {
        lastApiEx = ae;
        // try next endpoint for 401/404 only; for other errors rethrow
        if (ae.statusCode != 401 && ae.statusCode != 404) rethrow;
        continue;
      }
    }

    if (lastApiEx != null) throw lastApiEx;
    return lastResponse;
  }

  static void adminLogout() {
    _cachedAdminToken = null;
    _cachedAdminTokenExpiry = null;
    _cachedAdminProfile = null;
    SharedPreferences.getInstance().then((p) {
      p.remove('admin_token');
      p.remove('admin_token_expiry');
      p.remove('admin_profile');
      p.remove('admin_role');
    });
  }

  /// Return cached admin profile if available
  static Map<String, dynamic>? get cachedAdminProfile => _cachedAdminProfile;

  // ==================== HTTP REQUEST ENGINE ====================

  /// Debounce rapid repeated requests (e.g., search, filter)
  /// Only the LAST request in the sequence will execute
  static Future<dynamic> _debounceRequest(
    String debounceKey,
    Duration delay,
    Future<dynamic> Function() requestFn,
  ) async {
    // Cancel previous timer if exists
    _debounceTimers[debounceKey]?.ignore();

    // Create new future that will execute after delay
    var completed = false;
    var result;
    
    final timerFuture = Future.delayed(delay, () async {
      if (!completed) {
        completed = true;
        result = await requestFn();
      }
    });
    
    _debounceTimers[debounceKey] = timerFuture;
    
    try {
      await timerFuture;
      return result;
    } finally {
      if (_debounceTimers[debounceKey] == timerFuture) {
        _debounceTimers.remove(debounceKey);
      }
    }
  }

  static Future<dynamic> _request(
    String method,
    String endpoint, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
    bool requiresAuth = true,
    Duration? timeout,
    bool useCache = false,
    int cacheTtl = 120,
    bool skipDedup = false,
  }) async {
    final cacheKey = useCache ? '${method}_$endpoint' : null;
    final requestKey = '${method}_$endpoint${body?.toString() ?? ''}';

    // Check cache first
    if (useCache && method == 'GET') {
      final cached = _cacheGet(cacheKey!);
      if (cached != null) {
        return cached;
      }
    }

    // Deduplicate concurrent identical requests (unless skipDedup is true)
    if (!skipDedup && _pendingRequests.containsKey(requestKey)) {
      debugPrint(' Deduplicating request: $requestKey');
      return _pendingRequests[requestKey];
    }

    // If skipDedup is true, remove any existing pending request to force fresh fetch
    if (skipDedup && _pendingRequests.containsKey(requestKey)) {
      debugPrint(' Removing pending duplicate for fresh request: $requestKey');
      _pendingRequests.remove(requestKey);
    }

    final future = _executeRequest(
      method,
      endpoint,
      body: body,
      headers: headers,
      requiresAuth: requiresAuth,
      timeout: timeout ?? _timeout,
    );

    _pendingRequests[requestKey] = future;

    try {
      final result = await future;
      if (useCache && method == 'GET' && cacheKey != null) {
        _cacheSet(cacheKey, result, ttlSeconds: cacheTtl);
      }
      return result;
    } finally {
      _pendingRequests.remove(requestKey);
    }
  }

  static Future<dynamic> _executeRequest(
    String method,
    String endpoint, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
    bool requiresAuth = true,
    required Duration timeout,
  }) async {
    final url = Uri.parse('$_baseUrl$endpoint');
    final requestHeaders = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      ...?headers,
    };

    if (requiresAuth) {
      final token = await _getJwtToken();
      if (token != null) {
        requestHeaders['Authorization'] = 'Bearer $token';
        debugPrint(' [_executeRequest] $method $endpoint - Token added to headers (${token.substring(0, 20)}...)');
      } else {
        debugPrint('❌ [_executeRequest] $method $endpoint - No token available!');
        throw ApiException('Unauthorized: No valid token', statusCode: 401);
      }
    }

    int retries = 0;
    const int maxRetries = 3;

    while (true) {
      try {
        final http.Response response;
        final encodedBody = body != null ? jsonEncode(body) : null;

        switch (method.toUpperCase()) {
          case 'GET':
            response = await _httpClient.get(url, headers: requestHeaders).timeout(timeout);
            break;
          case 'POST':
            response = await _httpClient
                .post(url, headers: requestHeaders, body: encodedBody ?? '{}')
                .timeout(timeout);
            break;
          case 'PUT':
            response = await _httpClient
                .put(url, headers: requestHeaders, body: encodedBody ?? '{}')
                .timeout(timeout);
            break;
          case 'PATCH':
            response = await _httpClient
                .patch(url, headers: requestHeaders, body: encodedBody ?? '{}')
                .timeout(timeout);
            break;
          case 'DELETE':
            response = await _httpClient.delete(url, headers: requestHeaders).timeout(timeout);
            break;
          default:
            throw ApiException('Invalid HTTP method: $method');
        }

        // If server returned 429 Too Many Requests, avoid automatic client-side retries for non-idempotent methods (POST/PUT/PATCH/DELETE)
        if (response.statusCode == 429 && method.toUpperCase() != 'GET') {
          // Bubble up a clear ApiException so callers can handle rate-limit (e.g., show cooldown)
          throw ApiException('Too many requests. Please try again later.', statusCode: 429);
        }

        try {
          return await _handleResponse(response, retries, maxRetries, () async {
            retries++;
            final waitSeconds = 2 * retries;
            await Future.delayed(Duration(seconds: waitSeconds));
          });
        } on _RetryException {
          // _handleResponse signaled a retry (e.g., 429 on GET). Loop will retry the request.
          if (retries >= maxRetries) {
            throw ApiException('Too many requests. Please try again later.', statusCode: 429);
          }
          continue;
        }
      } on TimeoutException {
        if (retries < maxRetries) {
          retries++;
          await Future.delayed(Duration(milliseconds: 500 * retries));
          continue;
        }
        throw ApiException('Request timed out', isRetryable: true);
      } on http.ClientException catch (e) {
        if (retries < maxRetries) {
          retries++;
          await Future.delayed(Duration(milliseconds: 500 * retries));
          continue;
        }
        throw ApiException('Connection error: ${e.message}', isRetryable: true);
      }
    }
  }

  static dynamic _handleResponse(
    http.Response response,
    int retries,
    int maxRetries,
    Future<void> Function() onRetry,
  ) async {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return {};
      return jsonDecode(response.body);
    }

    switch (response.statusCode) {
      case 401:
        clearAuthCache();
        throw ApiException('Unauthorized: Invalid or expired token', statusCode: 401);
      case 404:
        throw ApiException('Resource not found', statusCode: 404);
      case 429:
        if (retries < maxRetries) {
          await onRetry();
          throw _RetryException();
        }
        throw ApiException('Too many requests. Please try again later.', statusCode: 429);
      default:
        String message = 'Request failed with status ${response.statusCode}';
        try {
          final errorBody = jsonDecode(response.body);
          message = errorBody['message'] ?? message;
        } catch (_) {}
        throw ApiException(message, statusCode: response.statusCode);
    }
  }

  // ==================== PRODUCTS ====================

  static Future<List<dynamic>> getStoreProductsById(String storeId, {bool bypassCache = false}) async {
    // ⚠️ CRITICAL: Products change frequently (approval/rejection), so disable cache
    // to ensure customers always see latest products
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final response = await _request(
      'GET',
      '/products?storeId=$storeId&t=$timestamp',
      requiresAuth: false,
      useCache: false,  //  NO CACHE - products change too frequently
      cacheTtl: 0,
    );
    
    // 🔥 Filter to approved products only for customers
    final allProducts = List<dynamic>.from(response['data'] ?? []);
    final approvedProducts = allProducts.where((product) {
      final status = product['status']?.toString().toLowerCase() ?? '';
      final isActive = product['is_active'] == 1 || product['is_active'] == true;
      return (status == 'approved' || status == '') && isActive;
    }).toList();
    
    debugPrint(' Store $storeId: Got ${allProducts.length} total, ${approvedProducts.length} approved');
    return approvedProducts;
  }

  static Future<List<dynamic>> getStoreProductsByIdAdmin(String storeId) async {
    // Admin endpoint to get ALL products for a store (including inactive)
    // Uses dedicated admin endpoint, not the public products endpoint
    final response = await _request(
      'GET',
      '/products/admin/store/$storeId', //  Correct admin endpoint
      requiresAuth: true,
      useCache: false,
    );
    return List<dynamic>.from(response['data'] ?? []);
  }

  static Future<List<dynamic>> getProducts({
    int page = 1,
    int limit = 20,
    String? storeId,
    String? categoryId,
    String? search,
  }) async {
    final params = <String, String>{
      'page': page.toString(),
      'limit': limit.toString(),
      if (storeId != null) 'storeId': storeId,
      if (categoryId != null) 'categoryId': categoryId,
      if (search != null) 'search': search,
    };
    final query = params.entries.map((e) => '${e.key}=${e.value}').join('&');

    final response = await _request(
      'GET',
      '/products?$query',
      requiresAuth: false,
      useCache: true,
      cacheTtl: 120,
    );
    return List<dynamic>.from(response['data'] ?? []);
  }

  static Future<dynamic> getProductById(String productId) async {
    final response = await _request(
      'GET',
      '/products/$productId',
      requiresAuth: false,
      useCache: true,
      cacheTtl: 300,
    );
    return response['data'];
  }

  static Future<dynamic> createProductWithImage(
    Map<String, dynamic> productData,
    dynamic imageFile,
  ) async {
    final url = Uri.parse('$_baseUrl/products');
    final request = http.MultipartRequest('POST', url);

    final token = await _getJwtToken();
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    request.fields.addAll({
      'name': productData['name']?.toString() ?? '',
      'description': productData['description']?.toString() ?? '',
      'price': productData['price'].toString(),
      'storeId': productData['storeId'].toString(),
      'stock': (productData['stock'] ?? 10).toString(),
      'currency': productData['currencyCode']?.toString() ?? 'USD',
      if (productData['category_id'] != null) 'category_id': productData['category_id'].toString(),
    });

    if (imageFile != null) {
      if (imageFile is http.MultipartFile) {
        request.files.add(imageFile);
      } else {
        final fileBytes = await imageFile.readAsBytes();
        request.files.add(http.MultipartFile.fromBytes(
          'image',
          fileBytes,
          filename: 'product_${DateTime.now().millisecondsSinceEpoch}.jpg',
        ));
      }
    }

    final streamedResponse = await request.send().timeout(_timeout);
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = jsonDecode(response.body);
      return data['data'] ?? data;
    }
    throw ApiException('Failed to create product', statusCode: response.statusCode);
  }

  static Future<dynamic> createProduct({
    required String name,
    required String description,
    required double price,
    required String storeId,
    String? categoryId,
    required int stock,
  }) async {
    final response = await _request('POST', '/products', body: {
      'name': name,
      'description': description,
      'price': price,
      'storeId': storeId,
      'categoryId': categoryId,
      'stock': stock,
    });
    return response['data'];
  }

  static Future<dynamic> updateProduct(
    String productId, {
    String? name,
    String? description,
    double? price,
    int? stock,
    String? currency,
  }) async {
    final body = <String, dynamic>{
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (price != null) 'price': price,
      if (stock != null) 'stock': stock,
      if (currency != null) 'currency': currency,
    };
    final response = await _request('PUT', '/products/$productId', body: body);
    // Cache disabled - no invalidation needed
    return response['data'];
  }

  static Future<bool> deleteProduct(String productId) async {
    await _request('DELETE', '/products/$productId', requiresAuth: true);
    // Cache disabled - no invalidation needed
    return true;
  }

  // ==================== STORES ====================

  static Future<dynamic> getUserStore({String? uid}) async {
    try {
      // uid parameter is provided, or API will use current user from JWT
      final endpoint = uid != null ? '/users/store?uid=$uid' : '/users/store';
      final response = await _request('GET', endpoint);
      return response['data'];
    } catch (e) {
      debugPrint('Error getting user store: $e');
      return null;
    }
  }

  static Future<List<dynamic>> getStores({int page = 1, int limit = 20}) async {
    final response = await _request(
      'GET',
      '/stores?page=$page&limit=$limit',
      requiresAuth: false,
      useCache: true,
      cacheTtl: 120,
    );
    return List<dynamic>.from(response['data'] ?? []);
  }

  static Future<dynamic> getStoreById(String storeId) async {
    final response = await _request(
      'GET',
      '/stores/$storeId',
      requiresAuth: false,
      useCache: true,
      cacheTtl: 300,
    );
    return response['data'];
  }

  static Future<dynamic> createStore({
    required String name,
    String? description,
    required String phone,
    required String address,
    required double latitude,
    required double longitude,
    required String ownerUid,
    String? storeType,
    String? email,
  }) async {
    final response = await _request('POST', '/stores', body: {
      'name': name,
      'description': description,
      'phone': phone,
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
      'ownerUid': ownerUid,
      if (storeType != null) 'storeType': storeType,
      if (email != null) 'email': email,
    });
    return response['data'];
  }

  static Future<dynamic> updateStore(
    String storeId, {
    String? name,
    String? description,
    String? phone,
    String? address,
  }) async {
    final body = <String, dynamic>{
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (phone != null) 'phone': phone,
      if (address != null) 'address': address,
    };
    final response = await _request('PUT', '/stores/$storeId', body: body);
    return response['data'];
  }

  static Future<dynamic> updateStoreLocation(String storeId, {required double latitude, required double longitude}) async {
    final body = <String, dynamic>{
      'latitude': latitude,
      'longitude': longitude,
    };
    final response = await _request('PUT', '/stores/$storeId', body: body);
    return response['data'];
  }

  static Future<bool> deleteStore(String storeId) async {
    await _request('DELETE', '/stores/$storeId');
    return true;
  }

  // ==================== ORDERS ====================

  static Future<dynamic> createOrder({
    required String storeId,
    required double totalPrice,
    required String shippingAddress,
    required List<Map<String, dynamic>> items,
    String? paymentMethod,
    String? deliveryOption,
    String? currency,
  }) async {
    final response = await _request('POST', '/orders', body: {
      'storeId': storeId,
      'totalPrice': totalPrice,
      'shippingAddress': shippingAddress,
      'items': items,
      if (paymentMethod != null) 'paymentMethod': paymentMethod,
      if (deliveryOption != null) 'deliveryOption': deliveryOption,
      if (currency != null) 'currency': currency,
    });
    return response['data'];
  }

  static Future<List<dynamic>> getUserOrders({int page = 1, int limit = 20}) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final response = await _request(
      'GET',
      '/orders/user?page=$page&limit=$limit&t=$timestamp',
      useCache: false,
      cacheTtl: 0,
      requiresAuth: true,
    );
    return List<dynamic>.from(response['data'] ?? []);
  }

  static Future<Map<String, dynamic>> requestOrderReturn(int orderId) async {
    final response = await _request(
      'PUT',
      '/orders/$orderId/status',
      body: {'status': 'return'},
      requiresAuth: true,
    );
    return response as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> cancelOrderReturn(int orderId) async {
    final response = await _request(
      'PUT',
      '/orders/$orderId/status',
      body: {'status': 'delivered'},
      requiresAuth: true,
    );
    return response as Map<String, dynamic>;
  }

  static Future<List<dynamic>> getStoreOrders({
    required String storeId,
    int page = 1,
    int limit = 50,
  }) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final response = await _request(
      'GET',
      '/orders/store/$storeId?page=$page&limit=$limit&t=$timestamp',
      useCache: false,
      cacheTtl: 0,
    );
    return List<dynamic>.from(response['data'] ?? []);
  }

  static Future<dynamic> getOrderById(String orderId, {bool requiresAuth = false}) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final response = await _request(
      'GET',
      '/orders/$orderId?t=$timestamp',
      requiresAuth: requiresAuth,
      useCache: false,
      cacheTtl: 0,
    );
    return response['data'];
  }

  static Future<List<dynamic>> getNearbyOrders({required double latitude, required double longitude, int radiusMeters = 5000, int limit = 10}) async {
    final response = await _request('POST', '/delivery-requests/nearby', body: {
      'latitude': latitude,
      'longitude': longitude,
      'radiusMeters': radiusMeters,
      'limit': limit,
    }, requiresAuth: true);
    return List<dynamic>.from(response['data'] ?? []);
  }

  static Future<bool> assignOrderToDriver(String orderId, String driverUid) async {
    final response = await _request('POST', '/orders/$orderId/assign', body: {'driverUid': driverUid}, requiresAuth: true);
    return response['success'] == true;
  }

  // جديد 
  static Future<dynamic> postOrderPickedUp(String orderId) async {
    final response = await _request('POST', '/delivery-requests/orders/$orderId/pickup', requiresAuth: true);
    return response['data'];
  }

  // جديد 
  static Future<bool> postMarkDelivered(String orderId) async {
    final response = await _request('POST', '/delivery-requests/orders/$orderId/delivered', requiresAuth: true);
    return response['success'] == true;
  }

  static Future<bool> updateOrderStatus(String orderId, String status) async {
    await _request('PUT', '/orders/$orderId/status', body: {'status': status});
    // Cache disabled - no invalidation needed
    return true;
  }

  /// Get skipped orders that driver can reclaim
  static Future<List<Map<String, dynamic>>> getSkippedOrders({
    required double latitude,
    required double longitude,
  }) async {
    try {
      final response = await _request(
        'GET',
        '/delivery-requests/skipped-orders?latitude=$latitude&longitude=$longitude',
        requiresAuth: true,
      );
      final data = response['data'];
      if (data is List) {
        return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Error getting skipped orders: $e');
      return [];
    }
  }

  /// Reclaim a skipped order
  static Future<Map<String, dynamic>?> reclaimOrder({
    required String orderId,
  }) async {
    try {
      final response = await _request(
        'POST',
        '/delivery-requests/reclaim',
        body: {'orderId': orderId},
        requiresAuth: true,
      );
      return response as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('Error reclaiming order: $e');
      return null;
    }
  }

  // ==================== USERS ====================

  static Future<dynamic> getUserProfile() async {
    final response = await _request(
      'GET',
      '/auth/me',
      requiresAuth: true,
      useCache: true,
      cacheTtl: 120,
    );
    // Backend returns { success: true, data: {...} }
    return response['data'];
  }

  static Future<dynamic> updateUserProfile({
    String? displayName,
    String? phone,
    String? address,
    double? latitude,
    double? longitude,
    String? nationalId,
    String? buildingInfo,
    String? apartmentNumber,
    String? deliveryInstructions,
    String? surname,
  }) async {
    final body = <String, dynamic>{
      if (displayName != null) 'displayName': displayName,
      if (surname != null) 'surname': surname,
      if (phone != null) 'phone': phone,
      if (address != null) 'address': address,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (nationalId != null) 'nationalId': nationalId,
      if (buildingInfo != null) 'buildingInfo': buildingInfo,
      if (apartmentNumber != null) 'apartmentNumber': apartmentNumber,
      if (deliveryInstructions != null) 'deliveryInstructions': deliveryInstructions,
    };
    final response = await _request('PUT', '/users/profile', body: body);
    // Cache disabled - no invalidation needed
    return response['data'];
  }

  static Future<dynamic> syncUser({
    required String uid,
    required String email,
    String? displayName,
  }) async {
    final response = await _request(
      'POST',
      '/users/sync',
      body: {'uid': uid, 'email': email, 'displayName': displayName},
      requiresAuth: false,
    );
    return response['data'];
  }

  static Future<dynamic> deliverySignup({
    required String email,
    required String password,
    required String name,
    required String phone,
    String? nationalID,
    String? address,
  }) async {
    final response = await _request(
      'POST',
      '/auth/delivery-signup',
      body: {
        'email': email,
        'password': password,
        'name': name,
        'phone': phone,
        if (nationalID != null && nationalID.isNotEmpty) 'nationalID': nationalID,
        if (address != null && address.isNotEmpty) 'address': address,
      },
      requiresAuth: false,
    );
    return response;
  }

  static Future<dynamic> submitDeliveryRequest({
    required String uid,
    String? email,
    String? name,
    String? phone,
    String? nationalID,
    String? address,
  }) async {
    final response = await _request(
      'POST',
      '/delivery-requests',
      body: {
        'uid': uid,
        if (email != null) 'email': email,
        if (name != null) 'name': name,
        if (phone != null) 'phone': phone,
        if (nationalID != null) 'nationalID': nationalID,
        if (address != null) 'address': address,
      },
      requiresAuth: false,
      timeout: _shortTimeout,
    );
    return response;
  }

  // ==================== DELIVERY REQUESTS (ADMIN) ====================

  static Future<List<dynamic>> getPendingDeliveryRequests() async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final response = await _request(
      'GET',
      '/admins/drivers/pending?t=$timestamp',
      requiresAuth: true,
      useCache: false,
      skipDedup: true,
    );
    return List<dynamic>.from(response['data'] ?? []);
  }

  // Admin: fetch approved delivery requests
  static Future<List<dynamic>> getApprovedDeliveryRequests() async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final response = await _request(
      'GET',
      '/admins/drivers/approved?t=$timestamp',
      requiresAuth: true,
      useCache: false,
      skipDedup: true,
    );
    return List<dynamic>.from(response['data'] ?? []);
  }

  // Admin: fetch active drivers (working)
  static Future<List<dynamic>> getActiveDeliveryRequests() async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final response = await _request(
      'GET',
      '/admins/drivers/active?t=$timestamp',
      requiresAuth: true,
      useCache: false,
      skipDedup: true,
    );
    return List<dynamic>.from(response['data'] ?? []);
  }

  // ================ ADMIN MANAGEMENT ================
  static Future<List<dynamic>> getAdmins() async {
    final response = await _request('GET', '/admins', requiresAuth: true);
    return List<dynamic>.from(response['data'] ?? []);
  }

  static Future<dynamic> createAdmin({String? email, required String password, String? firstName, String? lastName, String role = 'admin'}) async {
    final genEmail = email ??
        ((firstName != null && firstName.isNotEmpty) || (lastName != null && lastName.isNotEmpty)
            ? '${(firstName ?? '').trim().toLowerCase()}.${(lastName ?? '').trim().toLowerCase()}@yshop.com'
            : '');
    final response = await _request('POST', '/admins', body: {
      'email': genEmail,
      'password': password,
      'first_name': firstName,
      'last_name': lastName,
      'role': role,
    }, requiresAuth: true);
    return response['data'];
  }

  static Future<List<dynamic>> getUsersForAdmin(String adminId) async {
    final response = await _request('GET', '/admins/$adminId/users', requiresAuth: true);
    return List<dynamic>.from(response['data'] ?? []);
  }

  static Future<dynamic> createUserUnderAdmin(String adminId, {required String firstName, required String lastName, required String password}) async {
    final response = await _request('POST', '/admins/$adminId/users', body: {
      'first_name': firstName,
      'last_name': lastName,
      'password': password,
    }, requiresAuth: true);
    return response['data'];
  }

  // Admin-level: list all users
  static Future<List<dynamic>> getUsers() async {
    final response = await _request('GET', '/users', requiresAuth: true);
    return List<dynamic>.from(response['data'] ?? []);
  }

  // Convenience wrapper: create user under admin (keeps existing name)
  static Future<dynamic> createUser({required String firstName, required String lastName, required String password, required String adminId}) async {
    return await createUserUnderAdmin(adminId, firstName: firstName, lastName: lastName, password: password);
  }

  // Delete a user by id
  static Future<bool> deleteUser(String id) async {
    try {
      await _request('DELETE', '/users/$id', requiresAuth: true);
      return true;
    } on ApiException catch (ae) {
      if (ae.statusCode == 404) {
        // Try admin-scoped endpoint as a fallback
        await _request('DELETE', '/users/admin/$id', requiresAuth: true);
        return true;
      }
      rethrow;
    }
  }

  /// Admin action: update user status (e.g., 'banned', 'active')
  static Future<bool> updateUserStatus(String userId, String status) async {
    await _request('PUT', '/users/admin/$userId/status', body: {'status': status}, requiresAuth: true);
    return true;
  }

  // Delete an admin by id
  static Future<bool> deleteAdmin(String id) async {
    await _request('DELETE', '/admins/$id', requiresAuth: true);
    return true;
  }

  static Future<bool> approveDeliveryRequest(String id) async {
    await _request('POST', '/admins/drivers/$id/approve', requiresAuth: true);
    return true;
  }

  static Future<bool> rejectDeliveryRequest(String id) async {
    await _request('POST', '/admins/drivers/$id/reject', requiresAuth: true);
    return true;
  }

  static Future<bool> banDeliveryRequest(String id) async {
    await _request('POST', '/admins/drivers/$id/ban', requiresAuth: true);
    return true;
  }

  static Future<Map<String, dynamic>?> getDeliveryRequestByUid(String uid) async {
    // First try dedicated endpoint for current user (server verifies Firebase token)
    try {
      debugPrint(' [getDeliveryRequestByUid] Trying /delivery-requests/me endpoint');
      final resp = await _request('GET', '/delivery-requests/me', requiresAuth: true);
      final data = resp['data'];
      if (data != null) {
        debugPrint(' [getDeliveryRequestByUid] Got profile from /me endpoint');
        return Map<String, dynamic>.from(data as Map);
      }
    } catch (e) {
      debugPrint('⚠️ [getDeliveryRequestByUid] /me endpoint failed: $e');
      // ignore and fallback to admin endpoints
    }

    // Fallback 1: Try to fetch approved drivers list and filter by uid
    try {
      debugPrint(' [getDeliveryRequestByUid] Trying /admins/drivers/approved endpoint');
      final response = await _request('GET', '/admins/drivers/approved', requiresAuth: true, useCache: false);
      final list = List<dynamic>.from(response['data'] ?? []);
      final found = list.firstWhere((e) => (e['uid'] ?? e['UID'] ?? '') == uid, orElse: () => null);
      if (found != null) {
        debugPrint(' [getDeliveryRequestByUid] Found in approved drivers');
        return found as Map<String, dynamic>?;
      }
    } catch (e) {
      debugPrint('⚠️ [getDeliveryRequestByUid] /approved endpoint failed: $e');
    }

    // Fallback 2: Try pending list
    try {
      debugPrint(' [getDeliveryRequestByUid] Trying /delivery-requests/pending endpoint');
      final response = await _request('GET', '/delivery-requests/pending', requiresAuth: true, useCache: false);
      final list = List<dynamic>.from(response['data'] ?? []);
      final found = list.firstWhere((e) => (e['uid'] ?? e['UID'] ?? '') == uid, orElse: () => null);
      if (found != null) {
        debugPrint(' [getDeliveryRequestByUid] Found in pending drivers');
        return found as Map<String, dynamic>?;
      }
    } catch (e) {
      debugPrint('⚠️ [getDeliveryRequestByUid] /pending endpoint failed: $e');
    }

    debugPrint('❌ [getDeliveryRequestByUid] No profile found for UID: $uid');
    return null;
  }

  static Future<bool> updateDriverWorkingStatus(String uid, bool isWorking) async {
    await _request('PUT', '/delivery-requests/working', body: {'uid': uid, 'isWorking': isWorking}, requiresAuth: true);
    return true;
  }

  static Future<bool> updateMyDeliveryLocation(double latitude, double longitude) async {
    await _request('PUT', '/delivery-requests/location', body: {
      'latitude': latitude,
      'longitude': longitude,
    }, requiresAuth: true);
    return true;
  }

  static Future<bool> setDeliveryRequestPending(String id) async {
    await _request('PUT', '/delivery-requests/$id/pending', requiresAuth: true);
    return true;
  }

  static Future<bool> deleteDeliveryRequest(String id) async {
    await _request('DELETE', '/delivery-requests/$id', requiresAuth: true);
    return true;
  }

  // Change own password (user/admin). Backend verifies old password and updates.
  static Future<bool> changeMyPassword({required String oldPassword, required String newPassword}) async {
    final response = await _request('PUT', '/auth/me/password', body: {
      'oldPassword': oldPassword,
      'newPassword': newPassword,
    }, requiresAuth: true);
    return response['success'] == true;
  }

  // ==================== CART ====================

  static Future<List<dynamic>> getCart() async {
    final token = await _getJwtToken();
    debugPrint(' ApiService.getCart - token exists: ${token != null}');
    debugPrint(' ApiService.getCart - token length: ${token?.length ?? 0}');
    if (token == null) {
      debugPrint('❌ ApiService.getCart - NO TOKEN!');
    }
    // 🔥 Add cache buster query param to force fresh response
    final cacheBuster = DateTime.now().millisecondsSinceEpoch;
    final response = await _request(
      'GET', 
      '/cart?t=$cacheBuster', 
      requiresAuth: token != null
    );
    debugPrint(' ApiService.getCart - response: $response');
    return List<dynamic>.from(response['data'] ?? []);
  }

  /// Get cart with dedup bypass - for after delete/remove operations
  static Future<List<dynamic>> getCartFresh() async {
    final token = await _getJwtToken();
    debugPrint(' ApiService.getCartFresh - forcing fresh request (bypass dedup)');
    if (token == null) {
      debugPrint('❌ ApiService.getCartFresh - NO TOKEN!');
    }
    // Force fresh request by removing pending dedup
    const requestKey = 'GET_/cart';
    _pendingRequests.remove(requestKey);
    debugPrint(' ApiService.getCartFresh - cleared pending request');
    
    final response = await _request('GET', '/cart', requiresAuth: token != null);
    debugPrint(' ApiService.getCartFresh - response: $response');
    return List<dynamic>.from(response['data'] ?? []);
  }

  static Future<bool> addToCart({required String productId, required int quantity}) async {
    final token = await _getJwtToken();
    await _request(
      'POST',
      '/cart/add',
      body: {'productId': productId, 'quantity': quantity},
      requiresAuth: token != null,
    );
    return true;
  }

  static Future<bool> updateCartItemQuantity({required String itemId, required int quantity}) async {
    await _request('PUT', '/cart/item/$itemId', body: {'quantity': quantity});
    return true;
  }

  static Future<bool> removeFromCart({required String itemId}) async {
    await _request('DELETE', '/cart/item/$itemId');
    return true;
  }

  static Future<bool> clearCart() async {
    await _request('DELETE', '/cart');
    return true;
  }

  // ==================== ADMIN - STORES ====================

  //  NEW: Single endpoint for ALL dashboard stats (replaces 6 separate requests!)
  static Future<Map<String, dynamic>> getDashboardStats() async {
    // Add timestamp to bypass all caching
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final response = await _request(
      'GET',
      '/stores/admin/dashboard-stats?t=$timestamp',
      requiresAuth: true,
      useCache: false,
    );
    return response['data'] ?? {};
  }

  static Future<List<dynamic>> getPendingStores() async {
    final response = await _request('GET', '/admins/stores/pending', requiresAuth: true, skipDedup: true);
    return List<dynamic>.from(response['data'] ?? []);
  }

  static Future<List<dynamic>> getApprovedStores() async {
    final response = await _request('GET', '/admins/stores/approved', requiresAuth: true, skipDedup: true);
    return List<dynamic>.from(response['data'] ?? []);
  }

  /// 🔥 CRITICAL FIX: Get ALL stores with REAL status from database
  /// This reads the actual status column, not approval timestamps
  /// Returns pending, approved, and rejected stores
  static Future<List<dynamic>> getAllStoresAdmin() async {
    debugPrint('📡 [getAllStoresAdmin] Fetching all stores from backend...');
    // Add timestamp to bypass all caching
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final response = await _request(
      'GET',
      '/admins/stores/all?t=$timestamp',
      requiresAuth: true,
      useCache: false,
      skipDedup: true,
    );
    final stores = List<dynamic>.from(response['data'] ?? []);
    debugPrint('📡 [getAllStoresAdmin] Received ${stores.length} stores');
    for (var store in stores) {
      debugPrint('  - ${store['name']}: ${store['status']}');
    }
    return stores;
  }

  static Future<Map<String, dynamic>> approveStoreWithData(String storeId) async {
    final response = await _request('POST', '/admins/stores/$storeId/approve', requiresAuth: true);
    return {
      'success': true,
      'owner_uid': response['data']?['owner_uid'],
      'data': response['data'],
    };
  }

  static Future<Map<String, dynamic>> rejectStoreWithData(String storeId) async {
    final response = await _request('POST', '/admins/stores/$storeId/reject', requiresAuth: true);
    return {
      'success': true,
      'owner_uid': response['data']?['owner_uid'],
    };
  }

  static Future<bool> approveStore(String storeId) async {
    debugPrint('🟢 [approveStore] Sending approval request for store: $storeId');
    final response = await _request('POST', '/admins/stores/$storeId/approve', requiresAuth: true);
    debugPrint('🟢 [approveStore] Response: $response');
    return true;
  }

  static Future<bool> rejectStore(String storeId) async {
    debugPrint('🔴 [rejectStore] Sending rejection request for store: $storeId');
    final response = await _request('POST', '/admins/stores/$storeId/reject', requiresAuth: true);
    debugPrint('🔴 [rejectStore] Response: $response');
    return true;
  }

  static Future<bool> banStore(String storeId) async {
    await _request('POST', '/admins/stores/$storeId/ban', requiresAuth: true);
    return true;
  }

  static Future<Map<String, dynamic>> deleteStoreWithProductsAndGetData(String storeId) async {
    final response = await _request('DELETE', '/stores/admin/$storeId/delete', requiresAuth: true);
    return {
      'success': true,
      'owner_uid': response['data']?['owner_uid'],
    };
  }

  static Future<bool> deleteStoreWithProducts(String storeId) async {
    await _request('DELETE', '/stores/admin/$storeId/delete', requiresAuth: true);
    return true;
  }

  // ==================== ADMIN - PRODUCTS ====================

  static Future<List<dynamic>> getPendingProducts() async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final response = await _request('GET', '/products/admin/pending?t=$timestamp', requiresAuth: true);
    return List<dynamic>.from(response['data'] ?? []);
  }

  //  NEW: Get approved products from admin endpoint (includes inactive products)
  static Future<List<dynamic>> getApprovedProducts() async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final response = await _request('GET', '/products/admin/approved?t=$timestamp', requiresAuth: true);
    return List<dynamic>.from(response['data'] ?? []);
  }

  // Admin: fetch all orders (for dashboard overview)
  static Future<List<dynamic>> getAdminOrders({int limit = 50}) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final response = await _request(
      'GET',
      '/orders/admin?limit=$limit&t=$timestamp',
      requiresAuth: true,
      useCache: false,
    );
    return List<dynamic>.from(response['data'] ?? []);
  }

  static Future<List<dynamic>> getStoreProducts(String storeOwnerUid, {bool bypassCache = false}) async {
    // Store owner should see ALL their products (pending, approved, rejected)
    if (bypassCache) {
      clearCache();
      clearPendingRequests();
    }
    
    // Add unique timestamp to bypass deduplication
    final uniqueParam = bypassCache ? '&t=${DateTime.now().millisecondsSinceEpoch}' : '';
    final endpoint = '/products?storeOwnerUid=$storeOwnerUid&includeUnapproved=1$uniqueParam';
    
    final response = await _request(
      'GET',
      endpoint,
      requiresAuth: false,
    );
    
    return List<dynamic>.from(response['data'] ?? []);
  }

  static Future<List<dynamic>> getStoreProductsByEmail(String email) async {
    final response = await _request(
      'GET',
      '/products/admin/by-email?email=${Uri.encodeComponent(email)}',
      requiresAuth: true,
    );
    return List<dynamic>.from(response['data'] ?? []);
  }

  static Future<List<dynamic>> getPublicStoresByType(String type) async {
    final response = await _request(
      'GET',
      '/stores/public?type=${Uri.encodeComponent(type.toLowerCase())}',
      requiresAuth: false,
      useCache: true,
      cacheTtl: 120,
    );
    return List<dynamic>.from(response['data'] ?? []);
  }

  static Future<bool> updateProductStatus(String productId, String status) async {
    await _request(
      'PUT',
      '/products/admin/$productId/status',
      body: {'status': status},
      requiresAuth: true,
    );
    return true;
  }

  static Future<bool> approveProduct(String productId) => updateProductStatus(productId, 'approved');
  static Future<bool> rejectProduct(String productId) => updateProductStatus(productId, 'rejected');
  static Future<bool> setProductPending(String productId) => updateProductStatus(productId, 'pending');

  // ==================== BATCH OPERATIONS (for high volume) ====================

  /// Fetch multiple products in parallel
  static Future<List<dynamic>> getProductsBatch(List<String> productIds) async {
    final futures = productIds.map((id) => getProductById(id));
    final results = await Future.wait(futures, eagerError: false);
    return results.where((r) => r != null).toList();
  }

  /// Prefetch products for better UX
  static void prefetchProducts(List<String> productIds) {
    for (final id in productIds.take(10)) {
      getProductById(id).catchError((_) => null);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🚚 DELIVERY DRIVER - Order Offer System (NEW!)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get order offer for this driver
  static Future<Map<String, dynamic>?> getOrderOfferForDriver({
    required String driverId,
    required double latitude,
    required double longitude,
  }) async {
    try {
      final response = await _request(
        'GET',
        '/delivery-requests/offer?latitude=$latitude&longitude=$longitude',
        requiresAuth: true,
      );
      return response['data'] as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('Error getting order offer: $e');
      return null;
    }
  }

  /// Accept order offer
  static Future<Map<String, dynamic>?> acceptOrderOffer({
    required String orderId,
    required String driverId,
  }) async {
    try {
      final response = await _request(
        'POST',
        '/delivery-requests/offer/accept',
        body: {'orderId': orderId},
        requiresAuth: true,
      );
      return response as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('Error accepting order offer: $e');
      return null;
    }
  }

  /// Skip order offer
  static Future<bool> skipOrderOffer({
    required String orderId,
    required String driverId,
  }) async {
    try {
      await _request(
        'POST',
        '/delivery-requests/offer/skip',
        body: {'orderId': orderId},
        requiresAuth: true,
      );
      return true;
    } catch (e) {
      debugPrint('Error skipping order offer: $e');
      return false;
    }
  }

  /// Get driver's active order
  static Future<Map<String, dynamic>?> getDriverActiveOrder(String driverId) async {
    try {
      final response = await _request(
        'GET',
        '/delivery-requests/active-order',
        requiresAuth: true,
      );
      return response['data'] as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('Error getting active order: $e');
      return null;
    }
  }

  /// Update driver location on order (for customer tracking)
  static Future<bool> updateOrderDriverLocation(
    String orderId,
    double latitude,
    double longitude,
  ) async {
    try {
      await _request(
        'PUT',
        '/delivery-requests/orders/$orderId/location',
        body: {'latitude': latitude, 'longitude': longitude},
        requiresAuth: true,
      );
      return true;
    } catch (e) {
      debugPrint('Error updating order driver location: $e');
      return false;
    }
  }

  // ==================== CATEGORY MANAGEMENT ====================

  /// Get all categories for a store
  static Future<List<Map<String, dynamic>>> getStoreCategories(
    int storeId, {
    bool bypassCache = false,
  }) async {
    try {
      final cacheKey = 'store_categories_$storeId';
      if (!bypassCache) {
        final cached = _cacheGet(cacheKey);
        if (cached != null) return cached;
      }

      final response = await _request(
        'GET',
        '/stores/$storeId/categories?t=${DateTime.now().millisecondsSinceEpoch}',
        requiresAuth: true,
      );

      if (response is Map && response['data'] is List) {
        final data = response['data'] as List;
        final result = data.cast<Map<String, dynamic>>();
        _cacheSet(cacheKey, result, ttlSeconds: 300);
        return result;
      }
      return [];
    } catch (e) {
      debugPrint('❌ Error fetching categories: $e');
      return [];
    }
  }

  /// Create a new category
  static Future<Map<String, dynamic>?> createCategory(
    int storeId,
    String categoryName,
  ) async {
    try {
      final response = await _request(
        'POST',
        '/stores/$storeId/categories',
        body: {
          'name': categoryName,
        },
        requiresAuth: true,
      );

      if (response is Map) {
        // Cache disabled - no invalidation needed
        return response['data'] as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      debugPrint('❌ Error creating category: $e');
      return null;
    }
  }

  /// Delete a category
  static Future<bool> deleteCategory(int storeId, int categoryId) async {
    try {
      await _request(
        'DELETE',
        '/stores/$storeId/categories/$categoryId',
        requiresAuth: true,
      );
      // Cache disabled - no invalidation needed
      return true;
    } catch (e) {
      debugPrint('❌ Error deleting category: $e');
      return false;
    }
  }

  /// Assign product to category
  static Future<bool> assignProductToCategory(
    int productId,
    int categoryId,
  ) async {
    try {
      await _request(
        'PUT',
        '/products/$productId/category',
        body: {'category_id': categoryId},
        requiresAuth: true,
      );
      return true;
    } catch (e) {
      debugPrint('❌ Error assigning product to category: $e');
      return false;
    }
  }

  /// Remove product from category
  static Future<bool> removeProductFromCategory(int productId) async {
    try {
      await _request(
        'PUT',
        '/products/$productId/category',
        body: {'category_id': null},
        requiresAuth: true,
      );
      return true;
    } catch (e) {
      debugPrint('❌ Error removing product from category: $e');
      return false;
    }
  }

  /// Get products in a category
  static Future<List<Map<String, dynamic>>> getCategoryProducts(
    int categoryId,
  ) async {
    try {
      final cacheKey = 'category_products_$categoryId';
      final cached = _cacheGet(cacheKey);
      if (cached != null) return cached;

      final response = await _request(
        'GET',
        '/categories/$categoryId/products?t=${DateTime.now().millisecondsSinceEpoch}',
        requiresAuth: true,
      );

      if (response is Map && response['data'] is List) {
        final data = response['data'] as List;
        final result = data.cast<Map<String, dynamic>>();
        _cacheSet(cacheKey, result, ttlSeconds: 120);
        return result;
      }
      return [];
    } catch (e) {
      debugPrint('❌ Error fetching category products: $e');
      return [];
    }
  }
}

// ==================== HELPER CLASSES ====================

class _RetryException implements Exception {}

/// Custom API Exception with rich error information
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final bool isRetryable;

  ApiException(this.message, {this.statusCode, this.isRetryable = false});

  @override
  String toString() => 'ApiException: $message (status: $statusCode)';

  bool get isUnauthorized => statusCode == 401;
  bool get isNotFound => statusCode == 404;
  bool get isRateLimited => statusCode == 429;
}