import 'package:flutter/foundation.dart';

/// ═══════════════════════════════════════════════════════════════
/// 🧠 AI CONVERSATION PROVIDER
/// Clean state management for AI chat conversations
/// ═══════════════════════════════════════════════════════════════
class AIConversationProvider extends ChangeNotifier {
  List<Map<String, dynamic>> _currentConversation = [];
  List<Map<String, dynamic>>? _currentProducts;
  String? _currentMessage;
  bool _isLoading = false;

  // Getters
  List<Map<String, dynamic>> get conversation => _currentConversation;
  List<Map<String, dynamic>>? get currentProducts => _currentProducts;
  String? get currentMessage => _currentMessage;
  bool get hasActiveConversation => _currentConversation.isNotEmpty;
  bool get isLoading => _isLoading;

  // Set loading state
  void setLoading(bool val) {
    _isLoading = val;
    notifyListeners();
  }

  // Add message to conversation
  void addMessage({
    required String role,
    required String message,
    List<Map<String, dynamic>>? products,
  }) {
    _currentConversation.add({
      'role': role,
      'message': message,
      'products': products,
      'timestamp': DateTime.now(),
    });
    notifyListeners();
  }

  // Update products
  void setProducts(List<Map<String, dynamic>>? products, String? message) {
    _currentProducts = products;
    _currentMessage = message;
    notifyListeners();
  }

  // Clear current search results (keep conversation)
  void clearResults() {
    _currentProducts = null;
    _currentMessage = null;
    notifyListeners();
  }

  // Start new conversation
  void startNewConversation() {
    _currentConversation = [];
    _currentProducts = null;
    _currentMessage = null;
    _isLoading = false;
    notifyListeners();
  }

  // Resume conversation
  void resumeConversation() {
    clearResults();
    notifyListeners();
  }

  // Get last user message
  String? getLastUserQuery() {
    for (var msg in _currentConversation.reversed) {
      if (msg['role'] == 'user') {
        return msg['message'];
      }
    }
    return null;
  }
}