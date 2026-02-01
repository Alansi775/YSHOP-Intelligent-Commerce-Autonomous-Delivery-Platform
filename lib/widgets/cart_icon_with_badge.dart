import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state_management/cart_manager.dart';

class CartIconWithBadge extends StatelessWidget {
  final VoidCallback? onTap;
  final double iconSize;

  const CartIconWithBadge({Key? key, this.onTap, this.iconSize = 28}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<CartManager>(
      builder: (context, cartManager, child) {
        final totalItems = cartManager.totalItems;
        final primaryIconColor = Theme.of(context).colorScheme.onSurface;

        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Stack(
          alignment: Alignment.center,
          children: [
            GestureDetector(
              onTap: onTap ?? () => Scaffold.of(context).openEndDrawer(),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.08),
                    width: 1,
                  ),
                ),
                child: Icon(
                  Icons.shopping_bag_outlined,
                  color: Theme.of(context).colorScheme.onSurface,
                  size: iconSize,
                ),
              ),
            ),
            if (totalItems > 0)
              Positioned(
                right: 2,
                top: 0,
                child: Builder(builder: (context) {
                  final isDark = Theme.of(context).brightness == Brightness.dark;
                  final badgeColor = isDark ? const Color(0xFF4A9FFF) : const Color(0xFF2196F3);
                  return Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: badgeColor,
                      shape: BoxShape.circle,
                    ),
                  constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                  child: Center(
                    child: Text(
                      totalItems > 99 ? '99+' : totalItems.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  );
                }),
              ),
          ],
        );
      },
    );
  }
}
