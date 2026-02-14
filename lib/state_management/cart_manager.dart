import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';

/// Cart Manager - Backend Only with FIXED synchronization
class CartManager with ChangeNotifier {
  List<dynamic> _cartItems = [];
  bool _isLoading = false;
  String? _errorMessage;
  double _totalPrice = 0;
  String? _lastOrderId;

  // Getters for compatibility
  List<dynamic> get cartItems => _cartItems;
  List<dynamic> get items => _cartItems;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  double get totalPrice => _totalPrice;
  double get totalAmount => _totalPrice;
  int get itemCount => _cartItems.length;
  int get totalItems => _cartItems.length;
  String? get lastOrderId => _lastOrderId;
  
  /// Get currency symbol from first item or default to TRY
  String get currencySymbol {
    if (_cartItems.isEmpty) return '₺'; // Default to TRY
    final firstItem = _cartItems.first;
    final currency = firstItem['currency'] ?? 'TRY';
    switch (currency.toUpperCase()) {
      case 'USD': return '\$';
      case 'EUR': return '€';
      case 'GBP': return '£';
      case 'TRY': return '₺';
      default: return currency;
    }
  }

  CartManager() {
    _init();
  }

  Future<void> _init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getString('last_order_id');
      if (last != null && last.isNotEmpty) {
        _lastOrderId = last;
      }
    } catch (e) {
      print('Error loading lastOrderId: $e');
    }
    await _fetchCart();
  }

  Future<void> _fetchCart() async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      // 🔥 CRITICAL: Clear ALL pending requests to ensure fresh fetch
      ApiService.clearPendingRequests();
      
      // Add small delay to ensure backend transaction is committed
      await Future.delayed(const Duration(milliseconds: 100));

      // 🚀 Always fetch fresh (no caching)
      final serverCart = await ApiService.getCart();
      print('CartManager._fetchCart - serverCart raw: ${serverCart.length} items');
      
      // Verify data integrity
      for (var item in serverCart) {
        print('  Item: id=${item['id']}, product_id=${item['product_id']}, qty=${item['quantity']}, name=${item['name']}');
      }
      
      _cartItems = serverCart;
      _calculateTotal();
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      print('Error fetching cart: $e');
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshCart() async {
    // 🔥 Force clear cache on manual refresh
    ApiService.clearPendingRequests();
    await _fetchCart();
  }

  Future<void> addToCart({
    String? productId,
    dynamic product,
    required int quantity,
  }) async {
    try {
      final id = productId ?? product?.id?.toString();
      if (id == null) {
        throw Exception('Product ID is required');
      }

      print('🛒 CartManager.addToCart START - productId=$id quantity=$quantity');

      // 🚀 OPTIMISTIC UPDATE: Add to local cart immediately for seamless UX
      final productName = product is Map ? product['name'] : product?.name ?? 'Loading...';
      final productPrice = product is Map ? product['price'] : product?.price ?? 0.0;
      final productImage = product is Map ? product['image_url'] : product?.imageUrl ?? '';
      final productStoreId = product is Map ? product['store_id'] : product?.storeId ?? '';
      final productStock = product is Map ? product['stock'] : product?.stock ?? 999999;
      final productCurrency = product is Map ? product['currency'] : product?.currency ?? 'USD';

      final newItem = {
        'id': null, // Will be set by backend
        'product_id': int.tryParse(id) ?? id,
        'quantity': quantity,
        'name': productName,
        'price': productPrice is String ? double.tryParse(productPrice) ?? 0.0 : productPrice,
        'image_url': productImage,
        'store_id': productStoreId,
        'stock': productStock,
        'currency': productCurrency,
      };

      print('🛒 CartManager.addToCart - OPTIMISTIC: adding to local cart');
      _cartItems.add(newItem);
      _calculateTotal();
      _isLoading = false;
      notifyListeners(); // UI updates IMMEDIATELY

      // 📡 Send to backend
      print('🛒 CartManager.addToCart - sending to backend');
      await ApiService.addToCart(productId: id, quantity: quantity);
      print('🛒 CartManager.addToCart - backend SUCCESS');

      // 🔥 CRITICAL FIX: Wait longer + clear cache before refresh
      await Future.delayed(const Duration(milliseconds: 300));
      ApiService.clearPendingRequests();
      
      //  Refresh from backend with retry logic
      int retries = 0;
      while (retries < 3) {
        await _fetchCart();
        
        // Verify item exists in fetched cart
        final exists = _cartItems.any((item) => 
          item['product_id'].toString() == id
        );
        
        if (exists) {
          print('🛒 CartManager.addToCart - VERIFIED: item found in cart');
          break;
        }
        
        retries++;
        print('🛒 CartManager.addToCart - RETRY $retries: item not found yet');
        await Future.delayed(Duration(milliseconds: 200 * retries));
        ApiService.clearPendingRequests();
      }
      
      print('🛒 CartManager.addToCart - COMPLETE');
    } catch (e) {
      print('❌ CartManager.addToCart ERROR: $e');
      _errorMessage = e.toString();
      _isLoading = false;
      // Refresh cart to undo optimistic update if failed
      ApiService.clearPendingRequests();
      await _fetchCart();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> updateQuantity({
    required String cartItemId,
    required int quantity,
  }) async {
    try {
      final localIndex = _cartItems.indexWhere((item) => item['id']?.toString() == cartItemId);
      if (localIndex == -1) {
        throw Exception('Item not found in cart');
      }

      final int stock = (_cartItems[localIndex]['stock'] as num?)?.toInt() ?? 999999;
      if (quantity > stock) {
        _errorMessage = 'Only $stock items available in stock.';
        notifyListeners();
        throw Exception(_errorMessage);
      }

      // 🚀 OPTIMISTIC UPDATE: Update quantity immediately
      if (quantity <= 0) {
        print(' CartManager.updateQuantity - removing item (qty=$quantity)');
        await removeFromCart(_cartItems[localIndex]);
      } else {
        print(' CartManager.updateQuantity - OPTIMISTIC: updating local quantity to $quantity');
        final oldQuantity = _cartItems[localIndex]['quantity'];
        _cartItems[localIndex]['quantity'] = quantity;
        _calculateTotal();
        notifyListeners(); // UI updates IMMEDIATELY

        try {
          // 📡 Send update to backend
          print(' CartManager.updateQuantity - sending update to backend');
          await ApiService.updateCartItemQuantity(itemId: cartItemId, quantity: quantity);
          print(' CartManager.updateQuantity - backend SUCCESS');

          // 🔥 CRITICAL FIX: Wait + clear cache before refresh
          await Future.delayed(const Duration(milliseconds: 200));
          ApiService.clearPendingRequests();

          //  Refresh from backend
          await _fetchCart();
          print(' CartManager.updateQuantity - COMPLETE');
        } catch (e) {
          // Rollback on error
          _cartItems[localIndex]['quantity'] = oldQuantity;
          _calculateTotal();
          notifyListeners();
          rethrow;
        }
      }
    } catch (e) {
      print('❌ Error updating quantity: $e');
      _errorMessage = e.toString();
      // Refresh cart to undo optimistic update if failed
      ApiService.clearPendingRequests();
      await _fetchCart();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> removeFromCart(dynamic item) async {
    try {
      String? itemId;
      if (item is String) {
        itemId = item;
      } else if (item is Map) {
        itemId = item['id']?.toString();
      } else if (item is int) {
        itemId = item.toString();
      } else {
        itemId = item?.id?.toString();
      }

      if (itemId == null) {
        print('Warning: Could not determine item ID from: $item');
        return;
      }

      print('🗑️ CartManager.removeFromCart - itemId=$itemId');

      // 🚀 OPTIMISTIC UPDATE: Remove from local cart immediately
      final indexToRemove = _cartItems.indexWhere((i) => i['id']?.toString() == itemId);
      dynamic removedItem;
      if (indexToRemove != -1) {
        print('🗑️ CartManager.removeFromCart - OPTIMISTIC: removing from local cart');
        removedItem = _cartItems[indexToRemove];
        _cartItems.removeAt(indexToRemove);
        _calculateTotal();
        notifyListeners(); // UI updates IMMEDIATELY
      }

      try {
        // 📡 Send delete to backend
        print('🗑️ CartManager.removeFromCart - sending delete to backend');
        await ApiService.removeFromCart(itemId: itemId);
        print('🗑️ CartManager.removeFromCart - backend SUCCESS');

        // 🔥 CRITICAL FIX: Wait + clear cache before refresh
        await Future.delayed(const Duration(milliseconds: 300));
        ApiService.clearPendingRequests();

        //  Refresh from backend with retry to verify deletion
        int retries = 0;
        while (retries < 3) {
          await _fetchCart();
          
          // Verify item is deleted
          final stillExists = _cartItems.any((i) => i['id']?.toString() == itemId);
          
          if (!stillExists) {
            print('🗑️ CartManager.removeFromCart - VERIFIED: item deleted');
            break;
          }
          
          retries++;
          print('🗑️ CartManager.removeFromCart - RETRY $retries: item still exists');
          await Future.delayed(Duration(milliseconds: 200 * retries));
          ApiService.clearPendingRequests();
        }
        
        print('🗑️ CartManager.removeFromCart - COMPLETE');
      } catch (e) {
        // Rollback on error - restore removed item
        if (removedItem != null && indexToRemove != -1) {
          _cartItems.insert(indexToRemove, removedItem);
          _calculateTotal();
          notifyListeners();
        }
        rethrow;
      }
    } catch (e) {
      print('❌ Error removing from cart: $e');
      _errorMessage = e.toString();
      // Refresh cart to ensure consistency
      ApiService.clearPendingRequests();
      await _fetchCart();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> removeItem(String itemId) async {
    await removeFromCart(itemId);
  }

  bool isInCart(String productId) {
    return _cartItems.any((item) => item['product_id'].toString() == productId);
  }

  Future<void> clearCart() async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      // 🚀 OPTIMISTIC: Clear local cart immediately
      final oldItems = List.from(_cartItems);
      _cartItems.clear();
      _totalPrice = 0;
      notifyListeners();

      try {
        await ApiService.clearCart();
        
        // 🔥 CRITICAL FIX: Wait + clear cache
        await Future.delayed(const Duration(milliseconds: 200));
        ApiService.clearPendingRequests();
        
        await _fetchCart();
      } catch (e) {
        // Rollback on error
        _cartItems = oldItems;
        _calculateTotal();
        print('Warning: server clearCart failed: $e');
        rethrow;
      }

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      print('Error clearing cart: $e');
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  void _calculateTotal() {
    _totalPrice = 0;
    for (var item in _cartItems) {
      try {
        final dynamic rawPrice = item['price'];
        double price;
        if (rawPrice is num) {
          price = rawPrice.toDouble();
        } else if (rawPrice is String) {
          price = double.tryParse(rawPrice) ?? 0.0;
        } else {
          price = 0.0;
        }

        final dynamic rawQuantity = item['quantity'];
        final int quantity = rawQuantity is num ? rawQuantity.toInt() : int.tryParse(rawQuantity?.toString() ?? '') ?? 1;

        _totalPrice += price * quantity;
      } catch (e) {
        print('Error calculating price: $e');
      }
    }
  }

  List<dynamic> getItemsByStore(String storeId) {
    return _cartItems.where((item) => item['store_id'].toString() == storeId).toList();
  }

  Map<String, List<dynamic>> getItemsGroupedByStore() {
    final grouped = <String, List<dynamic>>{};
    for (var item in _cartItems) {
      final storeId = item['store_id'].toString();
      grouped.putIfAbsent(storeId, () => []).add(item);
    }
    return grouped;
  }

  void setLastOrderId(String? id) {
    _lastOrderId = id;
    try {
      SharedPreferences.getInstance().then((prefs) {
        if (id == null) {
          prefs.remove('last_order_id');
        } else {
          prefs.setString('last_order_id', id);
        }
      });
    } catch (e) {
      print('Failed to persist lastOrderId: $e');
    }
    notifyListeners();
  }

  @override
  void dispose() {
    super.dispose();
  }
}