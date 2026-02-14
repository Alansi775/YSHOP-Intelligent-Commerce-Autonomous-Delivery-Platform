// lib/screens/checkout_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../state_management/cart_manager.dart';
import 'dart:math';
import '../../services/api_service.dart';
import '../../widgets/checkout_item_widget.dart';
import '../../models/cart_item_model.dart';
import '../../models/product.dart';
import 'dart:ui';
import '../auth/sign_in_ui.dart';

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({Key? key}) : super(key: key);

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  String _selectedPaymentMethod = "**** 4242";
  String _deliveryOption = "Standard";

  TextStyle _getTenorSansStyle(BuildContext context, double size,
      {FontWeight weight = FontWeight.normal, Color? color}) {
    final Color primaryColor = Theme.of(context).colorScheme.primary;
    return TextStyle(
      fontFamily: 'TenorSans',
      fontSize: size,
      fontWeight: weight,
      color: color ?? primaryColor,
    );
  }

  String _formatCurrency(double amount, {String? currencySymbol}) {
    // Use provided symbol or default to ₺ (TRY)
    final symbol = currencySymbol ?? '₺';
    // For currency formatting, we just need the symbol and amount
    return '$symbol${amount.toStringAsFixed(2)}';
  }

  // Build complete address without N/A
  String _buildFullAddress(Map<String, dynamic> customerData) {
    final streetAddress = customerData['address'] as String? ?? '';
    final buildingInfo = customerData['buildingInfo'] as String? ?? customerData['building_info'] as String? ?? '';
    final apartmentNumber = customerData['apartmentNumber'] as String? ?? customerData['apartment_number'] as String? ?? '';

    List<String> parts = [];

    if (streetAddress.isNotEmpty) {
      parts.add(streetAddress);
    }

    if (buildingInfo.isNotEmpty) {
      parts.add('Building: $buildingInfo');
    }

    if (apartmentNumber.isNotEmpty) {
      parts.add('Apt: $apartmentNumber');
    }

    return parts.isNotEmpty ? parts.join(', ') : 'No address provided';
  }

  Future<void> _placeOrder(CartManager cartManager) async {
    // 1. Fetch user profile from backend
    Map<String, dynamic> customerData = {};
    try {
      final profile = await ApiService.getUserProfile();
      if (profile != null) customerData = Map<String, dynamic>.from(profile);
    } catch (e) {
      // If no profile from API, use empty data - backend will extract from JWT
      debugPrint('Could not fetch user profile: $e');
    }

    // Build full address without N/A
    final fullAddress = _buildFullAddress(customerData);

    // Normalize cart items
    final List<CartItemModel> normalizedItems = cartManager.items.map((raw) {
      if (raw is CartItemModel) return raw;
      if (raw is Map) {
        final Map<String, dynamic> map = Map<String, dynamic>.from(raw);
        final productJson = {
          'id': map['product_id']?.toString() ?? map['id']?.toString() ?? '',
          'name': map['name'] ?? map['product_name'] ?? 'Item',
          'description': map['description'] ?? '',
          'price': map['price'] ?? 0,
          'store_id': map['store_id']?.toString() ?? map['storeId']?.toString() ?? '',
          'stock': map['stock'] ?? 0,
          'image_url': map['image_url'] ?? map['imageUrl'] ?? '',
          'video_url': map['video_url'] ?? map['videoUrl'],
          'image_urls': map['image_urls'] ?? map['images'] ?? [],
          'store_name': map['store_name'] ?? map['storeName'],
          'store_phone': map['store_phone'] ?? map['storePhone'],
          'store_owner_email': map['store_owner_email'] ?? map['storeOwnerEmail'],
          'category_id': map['category_id'] ?? map['categoryId'],
        };
        final product = Product.fromJson(productJson);
        final qty = (map['quantity'] is num)
            ? (map['quantity'] as num).toInt()
            : int.tryParse('${map['quantity'] ?? 1}') ?? 1;
        return CartItemModel(product: product, quantity: qty);
      }
      final product = Product(
        id: raw?.toString() ?? '',
        name: raw?.toString() ?? 'Item',
        description: '',
        price: 0.0,
        storeId: '',
        stock: 0,
        imageUrl: '',
      );
      return CartItemModel(product: product, quantity: 1);
    }).toList();

    // Group items by storeId
    final Map<String, List<CartItemModel>> byStore = {};
    for (final item in normalizedItems) {
      final sid = item.product.storeId ?? '';
      byStore.putIfAbsent(sid, () => []).add(item);
    }

    final createdOrderIds = <String>[];

    try {
      for (final entry in byStore.entries) {
        final storeId = entry.key;
        final itemsForStore = entry.value;
        final double totalPrice =
            itemsForStore.fold(0.0, (sum, it) => sum + (it.product.price * it.quantity));


        final apiItems = itemsForStore
            .map((it) => {
                  'productId': it.product.id,
                  'price': it.product.price,
                  'quantity': it.quantity,
                })
            .toList();

        final response = await ApiService.createOrder(
          storeId: storeId,
          totalPrice: totalPrice,
          shippingAddress: fullAddress, // Clean address without N/A
          items: apiItems,
          paymentMethod: _selectedPaymentMethod,
          deliveryOption: _deliveryOption,
          // 🔥 NO CURRENCY - Backend gets it from products table
        );

        final createdId = response != null && response['id'] != null ? response['id'].toString() : null;
        if (createdId != null) createdOrderIds.add(createdId);
      }

      if (createdOrderIds.isNotEmpty) {
        final lastOrderId = createdOrderIds.last;
        cartManager.setLastOrderId(lastOrderId);
        await cartManager.clearCart();
        _showConfirmationSheet(context, lastOrderId);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No orders were created.')),
        );
      }
    } catch (e) {
      print("Error placing order via backend: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to place order: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cartManager = Provider.of<CartManager>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Detect if it's a wide screen (tablet/laptop)
    final bool isWideScreen = MediaQuery.of(context).size.width > 900;
    final double maxWidth = isWideScreen ? 1200 : double.infinity;

    return Scaffold(
      backgroundColor: isDark ? LuxuryTheme.kDarkBackground : LuxuryTheme.kLightBackground,
      appBar: AppBar(
        backgroundColor: isDark ? LuxuryTheme.kDarkBackground : LuxuryTheme.kLightBackground,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: isDark ? LuxuryTheme.kPlatinum : LuxuryTheme.kDeepNavy,
        title: Text(
          "Checkout",
          style: TextStyle(
            fontFamily: 'Didot',
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: isDark ? LuxuryTheme.kPlatinum : LuxuryTheme.kDeepNavy,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: isDark ? LuxuryTheme.kPlatinum : LuxuryTheme.kDeepNavy),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(top: 20, bottom: 100),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: isWideScreen
                    ? _buildWideLayout(context, cartManager)
                    : _buildMobileLayout(context, cartManager),
              ),
            ),
          ),

          // Confirm Order Button
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: _buildConfirmButton(context, cartManager),
            ),
          ),
        ],
      ),
    );
  }

  /// Wide layout: 2-column (left: products, right: delivery/payment/total)
  Widget _buildWideLayout(BuildContext context, CartManager cartManager) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left Column: Order Summary
        Expanded(
          flex: 1,
          child: Padding(
            padding: const EdgeInsets.only(right: 16),
            child: _buildOrderSummarySection(context, cartManager),
          ),
        ),
        
        // Right Column: Delivery, Payment, Total
        Expanded(
          flex: 1,
          child: Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildDeliverySection(context),
                const SizedBox(height: 16),
                _buildPaymentSection(context),
                const SizedBox(height: 16),
                _buildTotalSection(context, cartManager.totalAmount, cartManager.currencySymbol),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Mobile layout: Single column (vertical stack)
  Widget _buildMobileLayout(BuildContext context, CartManager cartManager) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildOrderSummarySection(context, cartManager),
        _buildDeliverySection(context),
        _buildPaymentSection(context),
        _buildTotalSection(context, cartManager.totalAmount, cartManager.currencySymbol),
      ],
    );
  }

  /// Order Summary Section (reusable for both layouts)
  Widget _buildOrderSummarySection(BuildContext context, CartManager cartManager) {
    return _buildSection(
      context,
      child: Column(
        children: [
          ...cartManager.items.map((raw) {
            CartItemModel cartItem;
            if (raw is CartItemModel) {
              cartItem = raw;
            } else if (raw is Map) {
              final Map<String, dynamic> map = Map<String, dynamic>.from(raw);
              final productJson = {
                'id': map['product_id']?.toString() ?? map['id']?.toString() ?? '',
                'name': map['name'] ?? map['product_name'] ?? 'Item',
                'description': map['description'] ?? '',
                'price': map['price'] ?? 0,
                'currency': map['currency']?.toString() ?? 'USD',
                'store_id': map['store_id']?.toString() ?? map['storeId']?.toString() ?? '',
                'stock': map['stock'] ?? 0,
                'image_url': map['image_url'] ?? map['imageUrl'] ?? '',
                'video_url': map['video_url'] ?? map['videoUrl'],
                'image_urls': map['image_urls'] ?? map['images'] ?? [],
                'store_name': map['store_name'] ?? map['storeName'],
                'store_phone': map['store_phone'] ?? map['storePhone'],
                'store_owner_email': map['store_owner_email'] ?? map['storeOwnerEmail'],
                'category_id': map['category_id'] ?? map['categoryId'],
              };
              final product = Product.fromJson(productJson);
              final qty = (map['quantity'] is num)
                  ? (map['quantity'] as num).toInt()
                  : int.tryParse('${map['quantity'] ?? 1}') ?? 1;
              cartItem = CartItemModel(product: product, quantity: qty);
            } else {
              final product = Product(
                id: raw?.toString() ?? '',
                name: raw?.toString() ?? 'Item',
                description: '',
                price: 0.0,
                storeId: '',
                stock: 0,
                imageUrl: '',
              );
              cartItem = CartItemModel(product: product, quantity: 1);
            }

            final isLast = cartItem.product.id ==
                (cartManager.items.isNotEmpty
                    ? (cartManager.items.last is Map
                        ? (cartManager.items.last['product_id']?.toString() ??
                            cartManager.items.last['id']?.toString())
                        : (cartManager.items.last is CartItemModel
                            ? (cartManager.items.last as CartItemModel).product.id
                            : null))
                    : null);

            return Column(
              children: [
                CheckoutItemWidget(item: cartItem),
                if (!isLast)
                  Divider(indent: 80, height: 1, color: Theme.of(context).dividerColor),
              ],
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildSection(BuildContext context, {required Widget child}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? LuxuryTheme.kDarkSurface : LuxuryTheme.kLightSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? LuxuryTheme.kPlatinum.withOpacity(0.15)
              : LuxuryTheme.kDeepNavy.withOpacity(0.08),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.08),
            blurRadius: 16,
            offset: const Offset(0, 8),
            spreadRadius: 1,
          ),
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.1 : 0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16),
        child: child,
      ),
    );
  }

  Widget _buildDeliverySection(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return _buildSection(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Text(
              "Delivery Method",
              style: TextStyle(
                fontFamily: 'Didot',
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDark ? LuxuryTheme.kPlatinum : LuxuryTheme.kDeepNavy,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildDeliveryOption(context, "Standard", Icons.local_shipping)),
              const SizedBox(width: 12),
              Expanded(child: _buildDeliveryOption(context, "Drone", Icons.airplanemode_active)),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildDeliveryOption(BuildContext context, String title, IconData icon) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isSelected = _deliveryOption == title;
    final Color bgColor = isDark
        ? LuxuryTheme.kDarkSurface.withOpacity(0.5)
        : LuxuryTheme.kLightSurface.withOpacity(0.5);

    return GestureDetector(
      onTap: () {
        setState(() {
          _deliveryOption = title;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
          border: isSelected
              ? Border.all(color: Colors.green, width: 2)
              : Border.all(
                  color: isDark
                      ? LuxuryTheme.kPlatinum.withOpacity(0.2)
                      : LuxuryTheme.kDeepNavy.withOpacity(0.2),
                ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 24,
              color: isSelected
                  ? Colors.green.shade700
                  : (isDark ? LuxuryTheme.kPlatinum : LuxuryTheme.kDeepNavy),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontFamily: 'TenorSans',
                fontSize: 16,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isDark ? LuxuryTheme.kPlatinum : LuxuryTheme.kDeepNavy,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentSection(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return _buildSection(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Row(
              children: [
                Text(
                  "Payment Method",
                  style: TextStyle(
                    fontFamily: 'Didot',
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: isDark ? LuxuryTheme.kPlatinum : LuxuryTheme.kDeepNavy,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => _showPaymentSheet(context),
                  child: Text(
                    "Change",
                    style: TextStyle(
                      fontFamily: 'TenorSans',
                      fontSize: 14,
                      color: isDark ? LuxuryTheme.kPlatinum : LuxuryTheme.kDeepNavy,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark
                  ? LuxuryTheme.kDarkSurface.withOpacity(0.5)
                  : LuxuryTheme.kLightSurface.withOpacity(0.5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isDark
                    ? LuxuryTheme.kPlatinum.withOpacity(0.2)
                    : LuxuryTheme.kDeepNavy.withOpacity(0.2),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _selectedPaymentMethod == "Pay at Door" ? Icons.money : Icons.credit_card,
                  size: 30,
                  color: isDark ? LuxuryTheme.kPlatinum : LuxuryTheme.kDeepNavy,
                ),
                const SizedBox(width: 12),
                Text(
                  _selectedPaymentMethod,
                  style: TextStyle(
                    fontFamily: 'TenorSans',
                    fontSize: 16,
                    color: isDark ? LuxuryTheme.kPlatinum : LuxuryTheme.kDeepNavy,
                  ),
                ),
                const Spacer(),
                const Icon(Icons.check_circle_sharp, color: Colors.green),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _showPaymentSheet(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color cardColor = isDark ? LuxuryTheme.kDarkSurface : LuxuryTheme.kLightSurface;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(25.0),
              topRight: Radius.circular(25.0),
            ),
          ),
          padding: const EdgeInsets.only(top: 10, left: 16, right: 16, bottom: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: isDark
                        ? LuxuryTheme.kPlatinum.withOpacity(0.3)
                        : LuxuryTheme.kDeepNavy.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                "Choose Payment Method",
                style: TextStyle(
                  fontFamily: 'Didot',
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: isDark ? LuxuryTheme.kPlatinum : LuxuryTheme.kDeepNavy,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              _buildPaymentOptionSheet(context, "Pay at Door", Icons.money),
              const SizedBox(height: 10),
              _buildPaymentOptionSheet(context, "**** 4242", Icons.credit_card),
              const SizedBox(height: 20),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withOpacity(0.08)
                          : Colors.black.withOpacity(0.05),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withOpacity(0.15)
                            : Colors.black.withOpacity(0.1),
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => Navigator.of(context).pop(),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Text(
                            "Cancel",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'TenorSans',
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: isDark ? LuxuryTheme.kPlatinum : LuxuryTheme.kDeepNavy,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPaymentOptionSheet(BuildContext context, String method, IconData icon) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isSelected = _selectedPaymentMethod == method;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedPaymentMethod = method;
        });
        Navigator.of(context).pop();
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.green.withOpacity(0.1)
              : (isDark
                  ? LuxuryTheme.kDarkSurface.withOpacity(0.5)
                  : LuxuryTheme.kLightSurface.withOpacity(0.5)),
          borderRadius: BorderRadius.circular(12),
          border: isSelected
              ? Border.all(color: Colors.green.shade700, width: 1.5)
              : Border.all(
                  color: isDark
                      ? LuxuryTheme.kPlatinum.withOpacity(0.2)
                      : LuxuryTheme.kDeepNavy.withOpacity(0.2),
                ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 24,
              color: isSelected
                  ? Colors.green.shade700
                  : (isDark ? LuxuryTheme.kPlatinum : LuxuryTheme.kDeepNavy),
            ),
            const SizedBox(width: 12),
            Text(
              method,
              style: TextStyle(
                fontFamily: 'TenorSans',
                fontSize: 16,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isDark ? LuxuryTheme.kPlatinum : LuxuryTheme.kDeepNavy,
              ),
            ),
            const Spacer(),
            if (isSelected) const Icon(Icons.check_circle, color: Colors.green),
          ],
        ),
      ),
    );
  }

  Widget _buildTotalSection(BuildContext context, double subtotal, String currencySymbol) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return _buildSection(
      context,
      child: Column(
        children: [
          Row(
            children: [
              Text(
                "Order Summary",
                style: TextStyle(
                  fontFamily: 'Didot',
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: isDark ? LuxuryTheme.kPlatinum : LuxuryTheme.kDeepNavy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildTotalRow(context, "Subtotal", _formatCurrency(subtotal, currencySymbol: currencySymbol), isBold: false),
          const SizedBox(height: 12),
          _buildTotalRow(context, "Delivery", "Free", isBold: false),
          const SizedBox(height: 12),
          Divider(
            height: 1,
            color: isDark
                ? LuxuryTheme.kPlatinum.withOpacity(0.2)
                : LuxuryTheme.kDeepNavy.withOpacity(0.2),
          ),
          const SizedBox(height: 12),
          _buildTotalRow(context, "Total", _formatCurrency(subtotal, currencySymbol: currencySymbol),
              isBold: true, color: Colors.green.shade700),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildTotalRow(BuildContext context, String label, String value,
      {bool isBold = false, Color? color}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: isBold ? 'Didot' : 'TenorSans',
            fontSize: isBold ? 20 : 16,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            color: isDark ? LuxuryTheme.kPlatinum : LuxuryTheme.kDeepNavy,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontFamily: isBold ? 'Didot' : 'TenorSans',
            fontSize: isBold ? 20 : 16,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            color: color ?? (isDark ? LuxuryTheme.kPlatinum : LuxuryTheme.kDeepNavy),
          ),
        ),
      ],
    );
  }

  Widget _buildConfirmButton(BuildContext context, CartManager cartManager) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      height: 56,
      width: 450,
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.4 : 0.15),
            blurRadius: 20,
            offset: const Offset(0, 8),
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Material(
          color: isDark ? Colors.white : Colors.black,
          child: InkWell(
            onTap: cartManager.items.isEmpty
                ? null
                : () {
                    _placeOrder(cartManager);
                  },
            borderRadius: BorderRadius.circular(14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.shopping_bag_outlined,
                  color: isDark ? Colors.black : Colors.white,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Text(
                  "Confirm Order",
                  style: TextStyle(
                    fontFamily: 'TenorSans',
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.black : Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showConfirmationSheet(BuildContext context, String orderId) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color cardColor = isDark ? LuxuryTheme.kDarkSurface : LuxuryTheme.kLightSurface;

    Navigator.of(context).pop();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(25.0),
              topRight: Radius.circular(25.0),
            ),
          ),
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.check_circle_outline, color: Colors.green, size: 60),
              const SizedBox(height: 20),
              Text(
                "Order Placed Successfully!",
                style: TextStyle(
                  fontFamily: 'Didot',
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: isDark ? LuxuryTheme.kPlatinum : LuxuryTheme.kDeepNavy,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                "Order ID: #$orderId",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'TenorSans',
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? LuxuryTheme.kPlatinum : LuxuryTheme.kDeepNavy,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                "Your order has been successfully placed via $_deliveryOption delivery. We will notify you when it's ready.\nThank you!",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'TenorSans',
                  fontSize: 16,
                  color: isDark
                      ? LuxuryTheme.kPlatinum.withOpacity(0.6)
                      : LuxuryTheme.kDeepNavy.withOpacity(0.6),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withOpacity(0.08)
                            : Colors.black.withOpacity(0.05),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withOpacity(0.15)
                              : Colors.black.withOpacity(0.1),
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => Navigator.of(context).pop(),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: Text(
                              "Continue Shopping",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'TenorSans',
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isDark ? LuxuryTheme.kPlatinum : LuxuryTheme.kDeepNavy,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}