import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../services/api_service.dart';
import '../config/api_config.dart';

/// Auth Manager with Backend JWT Authentication
/// No Firebase - all authentication through backend server
class AuthManager with ChangeNotifier {
  static const String _tokenKey = 'jwt_token';
  static const String _userKey = 'user_profile';
  static const String _emailVerifiedKey = 'email_verified';

  String? _token;
  Map<String, dynamic>? _userProfile;
  bool _isLoading = false;
  String? _errorMessage;
  bool _emailVerified = false;
  DateTime? _lastProfileFetch; // Throttle profile fetch

  // Getters
  String? get token => _token;
  Map<String, dynamic>? get userProfile => _userProfile;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _token != null && _emailVerified;
  bool get isEmailVerified => _emailVerified;

  AuthManager() {
    // Don't call _loadCachedAuth() here - call initializeAsync() from main() instead
  }

  /// Initialize authentication - MUST be called from main() before runApp
  Future<void> initializeAsync() async {
    await _loadCachedAuth();
    notifyListeners();
  }

  /// Load cached authentication from SharedPreferences
  Future<void> _loadCachedAuth() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // FIRST: Try to restore admin token (if admin is logged in)
      final adminToken = prefs.getString('admin_token');
      if (adminToken != null) {
        final adminTokenExpiry = prefs.getInt('admin_token_expiry');
        debugPrint(' [_loadCachedAuth] Found admin token in SharedPreferences');
        
        if (adminTokenExpiry != null) {
          final expiry = DateTime.fromMillisecondsSinceEpoch(adminTokenExpiry);
          if (DateTime.now().isBefore(expiry)) {
            // Restore admin token to ApiService
            debugPrint(' [_loadCachedAuth] Restoring admin token - expires in ${expiry.difference(DateTime.now()).inMinutes} minutes');
            // The ApiService._getJwtToken() will automatically find this in SharedPreferences
            // No need to manually restore it here - it will be picked up on first API call
          } else {
            debugPrint(' [_loadCachedAuth] Admin token expired, clearing');
            await prefs.remove('admin_token');
            await prefs.remove('admin_token_expiry');
            await prefs.remove('admin_role');
            await prefs.remove('admin_profile');
          }
        }
      }
      
      _token = prefs.getString(_tokenKey);
      
      // If token exists, validate it with backend before using
      if (_token != null) {
        //  CRITICAL: Propagate token to ApiService so we can validate it
        ApiService.setUserToken(_token);
        
        // Try to validate the token by calling /auth/me
        try {
          debugPrint(' Validating cached token with backend...');
          final response = await ApiService.getUserProfile();
          
          if (response != null) {
            _emailVerified = true;
            _userProfile = response;
            debugPrint(' Token validated successfully');
            
            // Save validated profile to SharedPreferences
            try {
              final userJson = jsonEncode(response);
              await prefs.setString(_userKey, userJson);
            } catch (_) {
              // Silent fail on save
            }
            return; // Success, exit early
          } else {
            throw Exception('Profile fetch returned null');
          }
        } catch (e) {
          debugPrint('❌ Token validation failed: $e');
          // Token is invalid/expired, clear it
          _token = null;
          _emailVerified = false;
          _userProfile = null;
          // Clear from SharedPreferences
          await prefs.remove(_tokenKey);
          await prefs.remove(_userKey);
          ApiService.setUserToken(null);
          return;
        }
      } else {
        // No token in SharedPreferences
        _emailVerified = prefs.getBool(_emailVerifiedKey) ?? false;
        
        // Try to load cached profile if no token
        final userJson = prefs.getString(_userKey);
        if (userJson != null) {
          try {
            _userProfile = jsonDecode(userJson) as Map<String, dynamic>;
          } catch (_) {
            _userProfile = null;
          }
        }
      }

      notifyListeners();
    } catch (e) {
      debugPrint('Error loading cached auth: $e');
    }
  }

  /// Save authentication token and user profile
  Future<void> _saveAuth(String token, Map<String, dynamic> profile, bool emailVerified) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, token);
      await prefs.setBool(_emailVerifiedKey, emailVerified);

      // Save user profile as JSON string
      final userJson = jsonEncode(profile);
      await prefs.setString(_userKey, userJson);

      _token = token;
      _userProfile = profile;
      _emailVerified = emailVerified;
      
      //  CRITICAL: Propagate token to ApiService immediately
      ApiService.setUserToken(token);
    } catch (e) {
      debugPrint('Error saving auth: $e');
    }
  }

  /// Force a profile refetch, bypassing the throttle — for call sites that
  /// just wrote a change (e.g. completing required profile fields) and need
  /// the in-memory profile to reflect it immediately.
  Future<void> refreshProfile() async {
    _lastProfileFetch = null;
    await _fetchUserProfile();
  }

  /// Fetch user profile from backend (throttled to every 5 seconds)
  Future<void> _fetchUserProfile() async {
    if (_token == null) return;

    // Throttle: only fetch if last fetch was > 5 seconds ago
    final now = DateTime.now();
    if (_lastProfileFetch != null &&
        now.difference(_lastProfileFetch!).inSeconds < 5) {
      return;
    }
    _lastProfileFetch = now;

    try {
      final response = await ApiService.getRequest('/auth/me');

      if (response != null && response['success'] == true) {
        // Backend returns { success: true, data: {...} }
        _userProfile = response['data'] ?? response['user'] ?? {};
        debugPrint(' AuthManager._fetchUserProfile - Updated profile: ${_userProfile?.keys}');
        _emailVerified = _userProfile?['email_verified'] ?? false;
        
        //  CRITICAL: Save profile to SharedPreferences for persistence
        try {
          final prefs = await SharedPreferences.getInstance();
          final userJson = jsonEncode(_userProfile);
          await prefs.setString(_userKey, userJson);
          debugPrint(' AuthManager._fetchUserProfile - Profile saved to SharedPreferences');
        } catch (e) {
          debugPrint('Error saving profile to SharedPreferences: $e');
        }
        
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error fetching user profile: $e');
    }
  }

  /// Sign up with email and password
  Future<void> register({
    required String email,
    required String password,
    required String displayName,
    String? phone,
    String? nationalId,
    String? address,
    double? latitude,
    double? longitude,
    String? buildingInfo,
    String? apartmentNumber,
    String? deliveryInstructions,
  }) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      final response = await ApiService.postRequest('/auth/signup', {
        'email': email,
        'password': password,
        'display_name': displayName,
        'phone': phone,
        'national_id': nationalId,
        'address': address,
        'latitude': latitude,
        'longitude': longitude,
        'building_info': buildingInfo,
        'apartment_number': apartmentNumber,
        'delivery_instructions': deliveryInstructions,
      });

      if (response != null && response['success'] == true) {
        _isLoading = false;
        _errorMessage = null;
        notifyListeners();
        // User registered but needs to verify email
        return;
      }

      throw Exception(response?['message'] ?? 'Registration failed');
    } catch (e) {
      _errorMessage = 'Registration failed: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  /// Verify email with token
  Future<void> verifyEmail({required String token}) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      final response = await ApiService.postRequest('/auth/verify-email', {
        'token': token,
      });

      if (response != null && response['success'] == true) {
        _isLoading = false;
        _errorMessage = null;
        _emailVerified = true;
        notifyListeners();
        return;
      }

      throw Exception(response?['message'] ?? 'Email verification failed');
    } catch (e) {
      _errorMessage = 'Email verification failed: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  /// Sign in with email and password
  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      // Clear cache before signing in
      ApiService.clearCache();
      ApiService.clearPendingRequests();

      final response = await ApiService.postRequest('/auth/login', {
        'email': email,
        'password': password,
      });

      if (response != null && response['success'] == true) {
        final token = response['token'];
        final user = response['user'] ?? {};

        if (token == null) {
          throw Exception('No authentication token received');
        }

        // Check if email is verified
        if (response['requiresVerification'] == true) {
          _errorMessage = 'Please verify your email before logging in';
          _isLoading = false;
          notifyListeners();
          throw Exception('Email not verified');
        }

        // Save token and user info
        await _saveAuth(token, user, true);

        _isLoading = false;
        _errorMessage = null;
        notifyListeners();
        return;
      }

      throw Exception(response?['message'] ?? 'Sign in failed');
    } on Exception {
      _isLoading = false;
      notifyListeners();
      rethrow;
    } catch (e) {
      _errorMessage = 'Sign in failed: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  // Reused across calls (not recreated per sign-in attempt) — on web this
  // matters: the constructor kicks off the platform's async init, and the
  // rendered GIS button (see google_web_signin_web.dart) and the
  // onCurrentUserChanged stream below both need to be bound to the SAME
  // instance for the button's sign-in to actually surface here.
  GoogleSignIn? _googleSignInInstance;
  GoogleSignIn get googleSignInInstance {
    return _googleSignInInstance ??= GoogleSignIn(
      clientId: kIsWeb ? ApiConfig.googleWebClientId : null,
      scopes: ['email', 'profile'],
    );
  }

  /// Sign in (or sign up, transparently) with Google — mobile path only.
  /// google_sign_in_web's own source is explicit that this imperative
  /// `.signIn()` flow "can't reliably provide an idToken" on web (Google
  /// Identity Services requires their own rendered button for that), so on
  /// web the UI must use `googleSignInInstance` + the GIS button widget +
  /// `completeGoogleAuth` instead of calling this method.
  /// Returns a small result map rather than throwing on a plain
  /// user-cancelled picker, since that's not really an error condition:
  ///   {'success': false, 'cancelled': true}                                  — user closed the picker
  ///   {'success': true, 'needsProfileCompletion': bool, 'isNewUser': bool}   — signed in
  Future<Map<String, dynamic>> signInWithGoogle() async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      final account = await googleSignInInstance.signIn();
      if (account == null) {
        _isLoading = false;
        notifyListeners();
        return {'success': false, 'cancelled': true};
      }

      return await completeGoogleAuth(account);
    } catch (e) {
      _errorMessage = 'Google sign-in failed: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  /// Shared tail end of Google sign-in, given an already-authenticated
  /// [GoogleSignInAccount] — obtained via `.signIn()` on mobile, or via the
  /// web's onCurrentUserChanged stream after the user interacts with the
  /// rendered GIS button. Exchanges the Google ID token for a YSHOP session.
  Future<Map<String, dynamic>> completeGoogleAuth(GoogleSignInAccount account) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      final googleAuth = await account.authentication;
      final idToken = googleAuth.idToken;
      if (idToken == null) {
        throw Exception('Google sign-in did not return an ID token');
      }

      ApiService.clearCache();
      ApiService.clearPendingRequests();

      final response = await ApiService.postRequest('/auth/google', {
        'idToken': idToken,
      });

      if (response != null && response['success'] == true) {
        final token = response['token'];
        final user = response['user'] ?? {};
        if (token == null) {
          throw Exception('No authentication token received');
        }

        await _saveAuth(token, user, true);

        _isLoading = false;
        _errorMessage = null;
        notifyListeners();
        return {
          'success': true,
          'needsProfileCompletion': response['needsProfileCompletion'] == true,
          'isNewUser': response['isNewUser'] == true,
        };
      }

      throw Exception(response?['message'] ?? 'Google sign-in failed');
    } catch (e) {
      _errorMessage = 'Google sign-in failed: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  /// Delivery Driver Login
  Future<void> deliveryLogin({
    required String email,
    required String password,
  }) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      // Clear cache before signing in
      ApiService.clearCache();
      ApiService.clearPendingRequests();

      final response = await ApiService.postRequest('/auth/delivery-login', {
        'email': email,
        'password': password,
      });

      if (response != null && response['success'] == true) {
        final token = response['token'];
        final user = response['user'] ?? {};

        if (token == null) {
          throw Exception('No authentication token received');
        }

        // Check if email is verified
        if (response['requiresVerification'] == true) {
          _errorMessage = 'Please verify your email before logging in';
          _isLoading = false;
          notifyListeners();
          throw Exception('Email not verified');
        }

        // Check if admin approval is pending
        if (response['requiresApproval'] == true) {
          _errorMessage = 'Your account is pending admin approval';
          _isLoading = false;
          notifyListeners();
          throw Exception('Pending admin approval');
        }

        // Save token and user info
        await _saveAuth(token, user, true);

        _isLoading = false;
        _errorMessage = null;
        notifyListeners();
        return;
      }

      // Check if the error is about pending approval or verification
      if (response?['requiresApproval'] == true) {
        _errorMessage = response?['message'] ?? 'Your account is pending admin approval. Please wait.';
        _isLoading = false;
        notifyListeners();
        throw Exception(_errorMessage);
      }

      if (response?['requiresVerification'] == true) {
        _errorMessage = response?['message'] ?? 'Please verify your email before logging in';
        _isLoading = false;
        notifyListeners();
        throw Exception(_errorMessage);
      }

      throw Exception(response?['message'] ?? 'Login failed');
    } on Exception {
      _isLoading = false;
      notifyListeners();
      rethrow;
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  /// Sign out
  Future<void> signOut() async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      // Clear all cache
      ApiService.clearCache();
      ApiService.clearPendingRequests();

      // Call logout endpoint
      try {
        await ApiService.postRequest('/auth/logout', {});
      } catch (e) {
        debugPrint('Logout endpoint error (non-critical): $e');
      }

      // Clear local storage
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tokenKey);
      await prefs.remove(_userKey);
      await prefs.remove(_emailVerifiedKey);

      _token = null;
      _userProfile = null;
      _emailVerified = false;
      _isLoading = false;
      
      //  CRITICAL: Clear token from ApiService on logout
      ApiService.setUserToken(null);
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Sign out failed: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  /// Update user profile
  Future<void> updateProfile({
    required Map<String, dynamic> data,
  }) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      final response = await ApiService.putRequest('/auth/me', data);

      if (response != null && response['success'] == true) {
        _userProfile = response['user'] ?? _userProfile;
        _isLoading = false;
        _errorMessage = null;
        notifyListeners();
        return;
      }

      throw Exception(response?['message'] ?? 'Update failed');
    } catch (e) {
      _errorMessage = 'Update failed: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  /// Change password
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      final response = await ApiService.putRequest('/auth/me/password', {
        'oldPassword': oldPassword,
        'newPassword': newPassword,
      });

      if (response != null && response['success'] == true) {
        _isLoading = false;
        _errorMessage = null;
        notifyListeners();
        return;
      }

      throw Exception(response?['message'] ?? 'Password change failed');
    } catch (e) {
      _errorMessage = 'Password change failed: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  /// Refresh user profile from backend
  Future<void> refreshUserProfile() async {
    if (_token == null) return;
    try {
      final response = await ApiService.getRequest('/auth/me');
      if (response != null && response['success'] == true) {
        final user = response['user'] ?? {};
        _userProfile = user;
        _emailVerified = user['email_verified'] ?? false;
        
        // Save updated profile
        final userJson = jsonEncode(user);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_userKey, userJson);
        
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error refreshing user profile: $e');
    }
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Update cached profile from fresh API data (used by SettingsView after fetching)
  void updateCachedProfile(Map<String, dynamic> profile) {
    _userProfile = profile;
    // Also save to SharedPreferences for persistence
    Future.microtask(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final userJson = jsonEncode(profile);
        await prefs.setString(_userKey, userJson);
      } catch (_) {}
    });
    notifyListeners();
  }

  /// Store Owner Sign Up
  /// Creates account in 'stores' table (not users table)
  /// Sets status='pending' and requires admin approval before login
  Future<void> storeSignup({
    required String email,
    required String password,
    required String storeName,
    required String storeType,
    required String phone,
    required String address,
    required double latitude,
    required double longitude,
    String? ownerName,
  }) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      final response = await ApiService.postRequest('/auth/store-signup', {
        'email': email,
        'password': password,
        'storeName': storeName,
        'storeType': storeType,
        'phone': phone,
        'address': address,
        'latitude': latitude,
        'longitude': longitude,
      });

      if (response != null && response['success'] == true) {
        _isLoading = false;
        _errorMessage = null;
        notifyListeners();
        // Store owner registered but needs to:
        // 1. Verify email (24 hours)
        // 2. Wait for admin approval
        return;
      }

      throw Exception(response?['message'] ?? 'Store registration failed');
    } catch (e) {
      _errorMessage = 'Store registration failed: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  /// Store Owner Sign In
  /// Checks: email verified + status='approved'
  Future<void> storeLogin({
    required String email,
    required String password,
  }) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      // Clear cache before signing in
      ApiService.clearCache();
      ApiService.clearPendingRequests();

      final response = await ApiService.postRequest('/auth/store-login', {
        'email': email,
        'password': password,
      });

      if (response != null && response['success'] == true) {
        final token = response['token'];
        final user = response['user'] ?? response['data'] ?? {};

        if (token == null) {
          throw Exception('No authentication token received');
        }

        // Save token and user info with storeOwner role
        await _saveAuth(token, user, true);

        _isLoading = false;
        _errorMessage = null;
        notifyListeners();
        return;
      }

      throw Exception(response?['message'] ?? 'Store login failed');
    } on Exception {
      _isLoading = false;
      notifyListeners();
      rethrow;
    } catch (e) {
      _errorMessage = 'Store login failed: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }
}