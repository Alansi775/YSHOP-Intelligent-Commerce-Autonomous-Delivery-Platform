// delivery_return_pickup_view.dart
// Driver screen for return order pickups: customer → store

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/api_service.dart';
import '../../config/api_config.dart';

class DeliveryReturnPickupView extends StatefulWidget {
  const DeliveryReturnPickupView({super.key});

  @override
  State<DeliveryReturnPickupView> createState() => _DeliveryReturnPickupViewState();
}

class _DeliveryReturnPickupViewState extends State<DeliveryReturnPickupView> {
  List<Map<String, dynamic>> _returns = [];
  bool _isLoading = true;
  String? _error;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(const Duration(seconds: 20), (_) => _load());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await ApiService.getDriverReturnPickups();
      if (mounted) setState(() { _returns = data; _isLoading = false; _error = null; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  Future<void> _confirmPickup(int returnId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Confirm Pickup', style: TextStyle(color: Colors.white)),
        content: const Text('Did you pick up the item from the customer?',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Yes, Picked Up', style: TextStyle(color: Colors.orange))),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ApiService.driverPickedUpReturn(returnId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Pickup confirmed! Now deliver to the store.'),
            backgroundColor: Colors.orange,
          ),
        );
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _openMaps(double lat, double lng, String label) async {
    final uri = Uri.parse('https://maps.google.com/?q=$lat,$lng');
    if (await canLaunchUrl(uri)) launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String _fullImageUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http')) return path;
    return '${ApiConfig.baseHost}$path';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Return Pickups', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.orange),
            onPressed: _load,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.orange))
          : _error != null
              ? _errorState()
              : _returns.isEmpty
                  ? _emptyState()
                  : RefreshIndicator(
                      color: Colors.orange,
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _returns.length,
                        itemBuilder: (context, i) => _returnCard(_returns[i]),
                      ),
                    ),
    );
  }

  Widget _returnCard(Map<String, dynamic> r) {
    final returnId = r['id'] as int? ?? 0;
    final isPickedUp = (r['driver_picked_up'] == 1 || r['driver_picked_up'] == true);

    final customerName = r['customer_display_name'] ?? r['user_id'] ?? 'Customer';
    final customerPhone = r['customer_phone_direct'] ?? r['driver_phone'] ?? '';
    final customerAddress = r['shipping_address'] ?? r['store_address'] ?? 'Address not available';
    final customerLat = double.tryParse(r['customer_latitude']?.toString() ?? '');
    final customerLng = double.tryParse(r['customer_longitude']?.toString() ?? '');

    final storeName = r['store_name'] ?? 'Store';
    final storePhone = r['store_phone'] ?? '';
    final storeAddress = r['store_address'] ?? '';

    final productName = r['product_name'] ?? 'Product';
    final productImage = _fullImageUrl(r['product_image_url']);
    final returnReason = r['return_reason'] ?? '';
    final orderId = r['order_id'];

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPickedUp ? Colors.green.withOpacity(0.4) : Colors.orange.withOpacity(0.4),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isPickedUp ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Icon(
                  isPickedUp ? Icons.check_circle : Icons.arrow_upward_rounded,
                  color: isPickedUp ? Colors.green : Colors.orange,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isPickedUp ? 'Picked Up — Deliver to Store' : 'Pickup from Customer',
                    style: TextStyle(
                      color: isPickedUp ? Colors.green : Colors.orange,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                Text(
                  'Return #$returnId',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Product info
                Row(
                  children: [
                    if (productImage.isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          productImage,
                          width: 56,
                          height: 56,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _placeholderBox(),
                        ),
                      )
                    else
                      _placeholderBox(),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(productName,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                          Text('Order #$orderId',
                              style: const TextStyle(color: Colors.white54, fontSize: 12)),
                          if (returnReason.isNotEmpty)
                            Text('Reason: $returnReason',
                                style: const TextStyle(color: Colors.orange, fontSize: 11),
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),
                const Divider(color: Color(0xFF333333)),
                const SizedBox(height: 12),

                // Customer section
                _sectionHeader('👤 Customer (Pickup From)', Colors.blue),
                const SizedBox(height: 8),
                _infoRow(Icons.person, customerName),
                if (customerPhone.isNotEmpty) _infoRow(Icons.phone, customerPhone),
                _infoRow(Icons.location_on, customerAddress, maxLines: 2),
                const SizedBox(height: 8),
                if (customerLat != null && customerLng != null)
                  _navButton(
                    label: 'Navigate to Customer',
                    icon: Icons.navigation,
                    color: Colors.blue,
                    onTap: () => _openMaps(customerLat, customerLng, 'Customer'),
                  ),

                const SizedBox(height: 12),
                const Divider(color: Color(0xFF333333)),
                const SizedBox(height: 12),

                // Store section
                _sectionHeader('🏪 Store (Deliver To)', Colors.green),
                const SizedBox(height: 8),
                _infoRow(Icons.storefront, storeName),
                if (storePhone.isNotEmpty) _infoRow(Icons.phone, storePhone),
                if (storeAddress.isNotEmpty) _infoRow(Icons.location_on, storeAddress, maxLines: 2),

                const SizedBox(height: 16),

                // Action button
                if (!isPickedUp)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.check_circle_outline, color: Colors.black),
                      label: const Text('Confirm Pickup from Customer',
                          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => _confirmPickup(returnId),
                    ),
                  )
                else
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.withOpacity(0.4)),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle, color: Colors.green),
                        SizedBox(width: 8),
                        Text('Picked Up — Now go to store',
                            style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholderBox() => Container(
    width: 56, height: 56,
    decoration: BoxDecoration(color: const Color(0xFF333333), borderRadius: BorderRadius.circular(8)),
    child: const Icon(Icons.image, color: Colors.white38),
  );

  Widget _sectionHeader(String title, Color color) => Text(
    title,
    style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13),
  );

  Widget _infoRow(IconData icon, String text, {int maxLines = 1}) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      crossAxisAlignment: maxLines > 1 ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 14, color: Colors.white38),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
              maxLines: maxLines, overflow: TextOverflow.ellipsis),
        ),
      ],
    ),
  );

  Widget _navButton({required String label, required IconData icon, required Color color, required VoidCallback onTap}) =>
    GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );

  Widget _emptyState() => const Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.arrow_back_rounded, size: 60, color: Colors.white24),
        SizedBox(height: 16),
        Text('No Return Pickups', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        SizedBox(height: 8),
        Text('No pending return orders to pick up right now.',
            style: TextStyle(color: Colors.white38, fontSize: 14)),
      ],
    ),
  );

  Widget _errorState() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.error_outline, size: 48, color: Colors.red),
        const SizedBox(height: 12),
        Text(_error ?? 'Error', style: const TextStyle(color: Colors.white70, fontSize: 14)),
        const SizedBox(height: 12),
        ElevatedButton(onPressed: _load, child: const Text('Retry')),
      ],
    ),
  );
}
