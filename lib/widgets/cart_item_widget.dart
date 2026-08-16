// lib/widgets/cart_item_widget.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state_management/cart_manager.dart';
import '../models/currency.dart';
import 'centered_notification.dart';
import '../models/product.dart';

// دالة للحصول على رمز العملة الصحيح
String getCurrencySymbol(String? currencyCode) {
  if (currencyCode == null || currencyCode.isEmpty) return '';
  final currency = Currency.fromCode(currencyCode);
  return currency?.symbol ?? '';
}

class CartItemWidget extends StatelessWidget {
  final dynamic item; 
  const CartItemWidget({Key? key, required this.item}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final cartManager = Provider.of<CartManager>(context, listen: false);
    final theme = Theme.of(context);
    
    //  مطابقة الحقول مع استعلام الـ SQL في الباك اند (p.name, p.price, p.image_url)
    final String cartItemId = item['id'].toString();
    final String name = item['name'] ?? 'Product';
    // Robust numeric parsing: API may return numbers as String or num
    final dynamic rawPrice = item['price'];
    double price;
    if (rawPrice is num) {
      price = rawPrice.toDouble();
    } else if (rawPrice is String) {
      price = double.tryParse(rawPrice) ?? 0.0;
    } else {
      price = 0.0;
    }

    final String rawImage = item['image_url'] ?? '';
    final String imageUrl = Product.getFullImageUrl(rawImage);

    final dynamic rawQuantity = item['quantity'];
    final int quantity = rawQuantity is num ? rawQuantity.toInt() : int.tryParse(rawQuantity?.toString() ?? '') ?? 1;

    final dynamic rawStock = item['stock'];
    final int stock = rawStock is num ? rawStock.toInt() : int.tryParse(rawStock?.toString() ?? '') ?? 999999;

    final String? currencyCode = item['currency'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(15),
        // ظل خفيف جداً للأناقة
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))
        ],
      ),
      child: Row(
        children: [
          // 1. الصورة
          ClipRRect(
            borderRadius: const BorderRadius.horizontal(left: Radius.circular(15)),
            child: Image.network(
              imageUrl,
              width: 100,
              height: 100,
              fit: BoxFit.cover,
              cacheWidth: 200,
              cacheHeight: 200,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return Container(width: 100, height: 100, color: theme.dividerColor.withOpacity(0.1));
              },
              errorBuilder: (context, error, stack) => Container(
                width: 100,
                height: 100,
                color: theme.dividerColor.withOpacity(0.1),
                child: const Icon(Icons.image_not_supported),
              ),
            ),
          ),
          
          // 2. المحتوى
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(fontFamily: 'TenorSans', fontSize: 14, fontWeight: FontWeight.bold),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "${getCurrencySymbol(currencyCode)}${price.toStringAsFixed(2)}",
                    style: TextStyle(color: theme.primaryColor, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  
                  // أزرار التحكم
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: theme.dividerColor.withOpacity(0.2)),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                            children: [
                            _qtyAction(Icons.remove, () async {
                               try {
                                 await cartManager.updateQuantity(cartItemId: cartItemId, quantity: quantity - 1);
                               } catch (e) {
                                 ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
                               }
                            }),
                            Text("$quantity", style: const TextStyle(fontWeight: FontWeight.bold)),
                            _qtyAction(Icons.add, () async {
                              if (quantity >= stock) {
                                CenteredNotification.show(context, 'Sorry, only $stock items available in stock.', success: false);
                                return;
                              }
                               try {
                                 await cartManager.updateQuantity(cartItemId: cartItemId, quantity: quantity + 1);
                               } catch (e) {
                                 CenteredNotification.show(context, e.toString(), success: false);
                               }
                            }),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                        onPressed: () async {
                          try {
                            await cartManager.removeItem(cartItemId);
                          } catch (e) {
                            CenteredNotification.show(context, e.toString(), success: false);
                          }
                        },
                      ),
                    ],
                  )
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _qtyAction(IconData icon, Future<void> Function() onTap) {
    return InkWell(
      onTap: () {
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Icon(icon, size: 16),
      ),
    );
  }
}