import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Product recommendation data class
class ProductRecommendation {
  final int id;
  final String name;
  final String description;
  final double price;
  final String currency;
  final String? image;
  final String storeName;
  final String storeType;
  final String? category;
  final String reason;
  final int stock;
  final bool available;

  ProductRecommendation({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.currency,
    this.image,
    required this.storeName,
    required this.storeType,
    this.category,
    required this.reason,
    required this.stock,
    required this.available,
  });

  factory ProductRecommendation.fromJson(Map<String, dynamic> json) {
    return ProductRecommendation(
      id: json['id'] ?? 0,
      name: json['name'] ?? 'Unknown Product',
      description: json['description'] ?? '',
      price: (json['price'] is String)
          ? double.tryParse(json['price']) ?? 0.0
          : (json['price'] ?? 0.0).toDouble(),
      currency: json['currency'] ?? 'KWD',
      image: json['image'],
      storeName: json['storeName'] ?? 'Unknown Store',
      storeType: json['storeType'] ?? 'Market',
      category: json['category'],
      reason: json['reason'] ?? 'Recommended for you',
      stock: json['stock'] ?? 0,
      available: json['available'] ?? false,
    );
  }
}

/// Chat message data class
class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final List<ProductRecommendation>? products;
  final String? intent;

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.products,
    this.intent,
  });
}

/// YSHOP AI Chat Provider
/// Manages conversation state, message history, and API communication
class AIChatProvider extends ChangeNotifier {
  static const String _cacheKey = 'ai_chat_messages';
  static const String _conversationLengthKey = 'ai_conversation_length';
  
  late SharedPreferences _prefs;
  
  final List<ChatMessage> _messages = [];
  bool _isLoading = false;
  String? _currentUserId;
  int _conversationLength = 0;

  // Getters
  List<ChatMessage> get messages => _messages;
  bool get isLoading => _isLoading;
  String? get currentUserId => _currentUserId;
  int get conversationLength => _conversationLength;

  /// Initialize provider
  Future<void> initialize(String userId) async {
    _currentUserId = userId;
    _prefs = await SharedPreferences.getInstance();
    
    // Load cached messages
    _loadCachedMessages();
    notifyListeners();
  }

  /// Load cached messages from SharedPreferences
  void _loadCachedMessages() {
    try {
      final cachedJson = _prefs.getString(_cacheKey);
      if (cachedJson != null && cachedJson.isNotEmpty) {
        // Parse and restore messages
        // Note: This is a simplified cache - in production, store full JSON
        _conversationLength = _prefs.getInt(_conversationLengthKey) ?? 0;
      }
    } catch (e) {
      print('Error loading cached messages: $e');
    }
  }

  /// Send message to AI and get response with products
  Future<void> sendMessage(String message) async {
    if (message.trim().isEmpty || _isLoading || _currentUserId == null) return;

    try {
      // Add user message
      _addMessage(
        text: message,
        isUser: true,
        products: null,
      );

      // Set loading state
      _isLoading = true;
      notifyListeners();

      // Call AI API
      final response = await ApiService.postRequest(
        '/ai/chat',
        {
          'message': message,
          'userId': _currentUserId,
          'language': 'auto',
        },
      );

      if (response['success'] != true) {
        _addMessage(
          text: response['error'] ?? 'Sorry, I encountered an error. Please try again.',
          isUser: false,
          products: null,
        );
        return;
      }

      final data = response['data'] ?? {};
      final aiReply = data['message'] ?? '';
      final intent = data['intent'];
      final conversationLength = data['conversationLength'] ?? 0;

      // Parse products if available
      List<ProductRecommendation>? products;
      if (data['products'] is List && (data['products'] as List).isNotEmpty) {
        products = (data['products'] as List)
            .map((p) => ProductRecommendation.fromJson(p))
            .toList();
      }

      // Update conversation length
      _conversationLength = conversationLength;
      _prefs.setInt(_conversationLengthKey, conversationLength);

      // Add AI response
      _addMessage(
        text: aiReply,
        isUser: false,
        products: products,
        intent: intent,
      );

      // Cache messages
      _cacheMessages();
    } catch (e) {
      print('Error sending message: $e');
      _addMessage(
        text: 'Oops! Something went wrong. Please check your connection and try again.',
        isUser: false,
        products: null,
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Add message to conversation
  void _addMessage({
    required String text,
    required bool isUser,
    required List<ProductRecommendation>? products,
    String? intent,
  }) {
    _messages.add(
      ChatMessage(
        text: text,
        isUser: isUser,
        timestamp: DateTime.now(),
        products: products,
        intent: intent,
      ),
    );
    notifyListeners();
  }

  /// Cache messages to SharedPreferences
  void _cacheMessages() {
    try {
      // Simple cache - store last message states
      // In production, use more sophisticated caching strategy
      _prefs.setInt(_conversationLengthKey, _conversationLength);
    } catch (e) {
      print('Error caching messages: $e');
    }
  }

  /// Clear conversation history
  Future<void> clearHistory() async {
    try {
      if (_currentUserId == null) return;

      // Call API to clear on backend
      await ApiService.postRequest(
        '/ai/chat/clear',
        {'userId': _currentUserId},
      );

      // Clear local cache
      _messages.clear();
      _conversationLength = 0;
      await _prefs.remove(_cacheKey);
      await _prefs.remove(_conversationLengthKey);

      notifyListeners();
    } catch (e) {
      print('Error clearing history: $e');
    }
  }

  /// Get conversation history from backend
  Future<void> loadHistory() async {
    try {
      if (_currentUserId == null) return;

      final response = await ApiService.postRequest(
        '/ai/chat/history',
        {'userId': _currentUserId},
      );

      if (response['success'] != true) return;

      final data = response['data'] ?? {};
      final messagesList = data['messages'] as List? ?? [];

      _messages.clear();
      for (var msg in messagesList) {
        _addMessage(
          text: msg['text'] ?? '',
          isUser: msg['role'] == 'user',
          products: null,
        );
      }

      _conversationLength = data['count'] ?? 0;
      notifyListeners();
    } catch (e) {
      print('Error loading history: $e');
    }
  }

  /// Check AI service status
  Future<bool> checkAIStatus() async {
    try {
      final response = await ApiService.getRequest('/ai/status');
      return response['success'] == true && response['data']['operational'] == true;
    } catch (e) {
      print('Error checking AI status: $e');
      return false;
    }
  }

  @override
  void dispose() {
    _messages.clear();
    super.dispose();
  }
}
