// lib/screens/delivery_shared.dart
import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// 🚚 DELIVERY SYSTEM - Shared Models & Widgets
// ═══════════════════════════════════════════════════════════════════════════════

// ─────────────────────────────────────────────────────────────────────────────
//  ORDER ITEM MODEL
// ─────────────────────────────────────────────────────────────────────────────

class OrderItem {
  final String id;
  final String productId;
  final String name;
  final int quantity;
  final double price;
  final String storeName;
  final String storeOwnerEmail;
  final String storePhone;
  final String imageUrl;

  OrderItem({
    this.id = '',
    this.productId = '',
    required this.name,
    required this.quantity,
    required this.price,
    required this.storeName,
    this.storeOwnerEmail = '',
    this.storePhone = '',
    this.imageUrl = '',
  });

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    return OrderItem(
      id: (json['id'] ?? '').toString(),
      productId: (json['product_id'] ?? json['productId'] ?? '').toString(),
      name: json['name'] ?? json['product_name'] ?? '',
      quantity: _parseInt(json['quantity']),
      price: _parseDouble(json['price']),
      storeName: json['storeName'] ?? json['store_name'] ?? '',
      storeOwnerEmail: json['storeOwnerEmail'] ?? json['store_owner_email'] ?? '',
      storePhone: json['storePhone'] ?? json['store_phone'] ?? '',
      imageUrl: json['imageUrl'] ?? json['image_url'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'product_id': productId,
    'name': name,
    'quantity': quantity,
    'price': price,
    'storeName': storeName,
    'storeOwnerEmail': storeOwnerEmail,
    'storePhone': storePhone,
    'imageUrl': imageUrl,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// 🚴 DELIVERY REQUEST MODEL (Driver Profile)
// ─────────────────────────────────────────────────────────────────────────────

class DeliveryRequest {
  final String id;
  final String uid;
  final String name;
  final String email;
  final String phoneNumber;
  final String nationalID;
  final String address;
  final String status;
  final bool isWorking;
  final double? latitude;
  final double? longitude;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  DeliveryRequest({
    required this.id,
    this.uid = '',
    required this.name,
    required this.email,
    required this.phoneNumber,
    required this.nationalID,
    required this.address,
    required this.status,
    this.isWorking = false,
    this.latitude,
    this.longitude,
    this.createdAt,
    this.updatedAt,
  });

  bool get isApproved => status == 'Approved';
  bool get isOnline => isWorking && isApproved;

  factory DeliveryRequest.fromJson(Map<String, dynamic> json) {
    return DeliveryRequest(
      id: (json['id'] ?? '').toString(),
      uid: json['uid'] as String? ?? '',
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      phoneNumber: json['phone'] as String? ?? json['phoneNumber'] as String? ?? 'N/A',
      nationalID: json['national_id'] as String? ?? json['nationalID'] as String? ?? 'N/A',
      address: json['address'] as String? ?? 'N/A',
      status: json['status'] as String? ?? 'Pending',
      isWorking: (json['is_working'] ?? json['isWorking'] ?? 0) == 1 || json['isWorking'] == true,
      latitude: _parseDouble(json['latitude'] ?? json['lat']),
      longitude: _parseDouble(json['longitude'] ?? json['lng'] ?? json['long']),
      createdAt: _parseDateTime(json['created_at']),
      updatedAt: _parseDateTime(json['updated_at']),
    );
  }

  factory DeliveryRequest.fromMap(Map<String, dynamic> m) {
    return DeliveryRequest(
      id: (m['id'] ?? m['ID'] ?? m['Id'] ?? '').toString(),
      uid: m['uid'] as String? ?? '',
      name: m['name'] as String? ?? '',
      email: m['email'] as String? ?? '',
      phoneNumber: (m['phone'] ?? m['phoneNumber'])?.toString() ?? 'N/A',
      nationalID: (m['national_id'] ?? m['nationalID'])?.toString() ?? 'N/A',
      address: m['address'] as String? ?? '',
      status: m['status'] as String? ?? 'Pending',
      isWorking: (m['is_working'] ?? m['isWorking'] ?? 0) == 1 || m['isWorking'] == true,
      latitude: _parseDouble(m['latitude'] ?? m['lat']),
      longitude: _parseDouble(m['longitude'] ?? m['lng'] ?? m['long']),
      createdAt: _parseDateTime(m['created_at']),
      updatedAt: _parseDateTime(m['updated_at']),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 📋 ORDER MODEL (Full Order with all delivery info)
// ─────────────────────────────────────────────────────────────────────────────

class Order {
  final String id;
  final String oderId; // user_id
  final String storeId;
  final String storeName;
  final String userName;
  final String userPhone;
  final String userEmail;
  final String addressFull;
  final String addressDeliveryInstructions;
  final String addressBuilding;
  final String addressApartment;
  final String deliveryOption;
  final String status;
  final String paymentMethod;
  final double total;
  final String currency;  // e.g., 'TRY', 'USD', 'EUR'
  final List<OrderItem> items;
  
  // Customer location
  final double locationLatitude;
  final double locationLongitude;
  
  // Store location
  final double? storeLatitude;
  final double? storeLongitude;
  final String? storePhone;
  final String? storeAddress;
  
  // Driver info
  final bool driverAccepted;
  final String? driverId;
  final Map<String, dynamic>? driverLocation;
  
  // Offer system
  final String? currentOfferDriverId;
  final DateTime? offerExpiresAt;
  final List<String> skippedDriverIds;
  
  // Customer data
  final Map<String, dynamic>? customer;
  final String? customerPhone;
  
  // Timestamps
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? pickedUpAt;
  final DateTime? deliveredAt;

  Order({
    required this.id,
    this.oderId = '',
    this.storeId = '',
    this.storeName = '',
    required this.userName,
    required this.userPhone,
    this.userEmail = '',
    required this.addressFull,
    this.addressDeliveryInstructions = '',
    this.addressBuilding = '',
    this.addressApartment = '',
    this.deliveryOption = 'Standard',
    required this.status,
    this.paymentMethod = '',
    required this.total,
    this.currency = 'USD',
    required this.items,
    required this.locationLatitude,
    required this.locationLongitude,
    this.storeLatitude,
    this.storeLongitude,
    this.storePhone,
    this.storeAddress,
    this.driverAccepted = false,
    this.driverId,
    this.driverLocation,
    this.currentOfferDriverId,
    this.offerExpiresAt,
    this.skippedDriverIds = const [],
    this.customer,
    this.customerPhone,
    this.createdAt,
    this.updatedAt,
    this.pickedUpAt,
    this.deliveredAt,
  });

  // Computed properties
  bool get isProcessing => status == 'Processing' || status == 'confirmed';
  bool get isOutForDelivery => status == 'Out for Delivery' || status == 'shipped';
  bool get isDelivered => status == 'Delivered' || status == 'delivered';
  bool get isPending => status == 'pending' || status == 'Pending';
  bool get needsDriver => isProcessing && !driverAccepted && driverId == null;
  
  String get displayStatus {
    switch (status.toLowerCase()) {
      case 'confirmed':
      case 'processing':
        return 'Processing';
      case 'shipped':
      case 'out for delivery':
        return 'Out for Delivery';
      case 'delivered':
        return 'Delivered';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status;
    }
  }



  factory Order.fromJson(Map<String, dynamic> json) {
    final itemsJson = (json['items'] as List?) ?? [];
    final items = itemsJson.map((it) {
      if (it is Map<String, dynamic>) {
        return OrderItem.fromJson(it);
      }
      return OrderItem.fromJson(Map<String, dynamic>.from(it as Map));
    }).toList();

    return Order(
      id: json['id']?.toString() ?? '',
      oderId: json['user_id']?.toString() ?? json['userId']?.toString() ?? '',
      storeId: json['store_id']?.toString() ?? json['storeId']?.toString() ?? '',
      storeName: json['store_name'] ?? json['storeName'] ?? '',
      userName: json['customer']?['name'] ?? json['userName'] ?? json['customerName'] ?? '',
      userPhone: json['customer']?['phone'] ?? json['userPhone'] ?? json['customerPhone'] ?? '',
      userEmail: json['customer']?['email'] ?? json['userEmail'] ?? '',
      addressFull: json['shipping_address'] ?? json['address_Full'] ?? json['address'] ?? '',
      addressDeliveryInstructions: json['delivery_instructions'] ?? json['deliveryInstructions'] ?? json['customer']?['delivery_instructions'] ?? '',
      addressBuilding: json['building_info'] ?? json['buildingInfo'] ?? json['customer']?['building_info'] ?? '',
      addressApartment: json['apartment_number'] ?? json['apartmentNumber'] ?? json['customer']?['apartment_number'] ?? '',
      deliveryOption: json['delivery_option'] ?? json['deliveryOption'] ?? 'Standard',
      status: json['status'] ?? 'Processing',
      paymentMethod: json['payment_method'] ?? json['paymentMethod'] ?? '',
      total: _parseDouble(json['total'] ?? json['total_price']),
      currency: json['currency']?.toString() ?? 'USD',
      items: items.cast<OrderItem>(),
      locationLatitude: _parseDouble(json['location_Latitude'] ?? json['customer']?['latitude']),
      locationLongitude: _parseDouble(json['location_Longitude'] ?? json['customer']?['longitude']),
      storeLatitude: _parseDouble(json['store_latitude'] ?? json['storeLatitude']),
      storeLongitude: _parseDouble(json['store_longitude'] ?? json['storeLongitude']),
      storePhone: json['store_phone'] ?? json['storePhone'],
      storeAddress: json['store_address'] ?? json['storeAddress'],
      driverAccepted: json['driverAccepted'] ?? json['driver_accepted'] ?? false,
      driverId: json['driverId'] ?? json['driver_id'],
      driverLocation: json['driver_location'] is Map ? Map<String, dynamic>.from(json['driver_location']) : 
                      json['driverLocation'] is Map ? Map<String, dynamic>.from(json['driverLocation']) : null,
      currentOfferDriverId: json['current_offer_driver_id'],
      offerExpiresAt: _parseDateTime(json['offer_expires_at']),
      skippedDriverIds: List<String>.from(json['skipped_driver_ids'] ?? []),
      customer: json['customer'] is Map ? Map<String, dynamic>.from(json['customer']) : null,
      customerPhone: json['customer']?['phone'] ?? json['customerPhone'],
      createdAt: _parseDateTime(json['created_at'] ?? json['createdAt']),
      updatedAt: _parseDateTime(json['updated_at'] ?? json['updatedAt']),
      pickedUpAt: _parseDateTime(json['picked_up_at']),
      deliveredAt: _parseDateTime(json['delivered_at']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': oderId,
    'store_id': storeId,
    'store_name': storeName,
    'userName': userName,
    'userPhone': userPhone,
    'userEmail': userEmail,
    'shipping_address': addressFull,
    'delivery_instructions': addressDeliveryInstructions,
    'building_info': addressBuilding,
    'apartment_number': addressApartment,
    'delivery_option': deliveryOption,
    'status': status,
    'payment_method': paymentMethod,
    'total_price': total,
    'items': items.map((i) => i.toJson()).toList(),
    'location_Latitude': locationLatitude,
    'location_Longitude': locationLongitude,
    'store_latitude': storeLatitude,
    'store_longitude': storeLongitude,
    'driverAccepted': driverAccepted,
    'driver_id': driverId,
    'driver_location': driverLocation,
  };

  factory Order.fromOffer(OrderOffer offer) {
    return Order(
      id: offer.orderId,
      // Note: keep fields compatible with Order constructor (no documentId/userId)
      storeId: offer.storeId,
      storeName: offer.storeName,
      storeLatitude: offer.storeLatitude,
      storeLongitude: offer.storeLongitude,
      storePhone: '',
      total: offer.totalPrice,
      status: 'Processing',
      addressFull: offer.customerAddress,
      userName: 'Customer',
      userPhone: '',
      locationLatitude: offer.customerLatitude,
      locationLongitude: offer.customerLongitude,
      items: [],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 🎁 ORDER OFFER MODEL (For driver offer system)
// ─────────────────────────────────────────────────────────────────────────────

class OrderOffer {
  final String orderId;
  final String storeId;
  final String storeName;
  final double totalPrice;
  final String currency;  // e.g., 'TRY', 'USD', 'EUR'
  final double distanceToStore; // in meters
  final double estimatedEarnings;
  final DateTime expiresAt;
  final int remainingSeconds;
  
  // Store location for route drawing
  final double storeLatitude;
  final double storeLongitude;
  
  // Customer location (for after pickup)
  final double customerLatitude;
  final double customerLongitude;
  final String customerAddress;

  OrderOffer({
    required this.orderId,
    required this.storeId,
    required this.storeName,
    required this.totalPrice,
    this.currency = 'USD',
    required this.distanceToStore,
    required this.estimatedEarnings,
    required this.expiresAt,
    required this.remainingSeconds,
    required this.storeLatitude,
    required this.storeLongitude,
    required this.customerLatitude,
    required this.customerLongitude,
    required this.customerAddress,
  });

  factory OrderOffer.fromJson(Map<String, dynamic> json) {
    return OrderOffer(
      orderId: json['order_id']?.toString() ?? '',
      storeId: json['store_id']?.toString() ?? '',
      storeName: json['store_name'] ?? 'Store',
      totalPrice: _parseDouble(json['total_price']),
      currency: json['currency']?.toString() ?? 'USD',
      distanceToStore: _parseDouble(json['distance_to_store']),
      estimatedEarnings: _parseDouble(json['estimated_earnings']),
      expiresAt: _parseDateTime(json['expires_at']) ?? DateTime.now().add(const Duration(minutes: 2)),
      remainingSeconds: _parseInt(json['remaining_seconds'], defaultValue: 120),
      storeLatitude: _parseDouble(json['store_latitude']),
      storeLongitude: _parseDouble(json['store_longitude']),
      customerLatitude: _parseDouble(json['customer_latitude']),
      customerLongitude: _parseDouble(json['customer_longitude']),
      customerAddress: json['customer_address'] ?? '',
    );
  }

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  
  String get formattedDistance {
    if (distanceToStore < 1000) {
      return '${distanceToStore.toStringAsFixed(0)}m';
    }
    return '${(distanceToStore / 1000).toStringAsFixed(1)}km';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 🔧 HELPER FUNCTIONS
// ─────────────────────────────────────────────────────────────────────────────

double _parseDouble(dynamic value, {double defaultValue = 0.0}) {
  if (value == null) return defaultValue;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? defaultValue;
  return defaultValue;
}

int _parseInt(dynamic value, {int defaultValue = 0}) {
  if (value == null) return defaultValue;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? defaultValue;
  return defaultValue;
}

DateTime? _parseDateTime(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String) {
    // Handle MySQL format: "2025-12-23 02:38:01"
    final sqlTs = RegExp(r'^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2}):(\d{2})');
    final match = sqlTs.firstMatch(value);
    if (match != null) {
      return DateTime(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
        int.parse(match.group(4)!),
        int.parse(match.group(5)!),
        int.parse(match.group(6)!),
      );
    }
    return DateTime.tryParse(value);
  }
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is Map && value.containsKey('seconds')) {
    final secs = value['seconds'];
    if (secs is int) return DateTime.fromMillisecondsSinceEpoch(secs * 1000);
  }
  return null;
}

// ─────────────────────────────────────────────────────────────────────────────
//  SHARED UI WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class DetailRow extends StatelessWidget {
  final String label;
  final dynamic value;
  final bool isMultiline;
  final TextAlign valueAlignment;
  final Color? labelColor;
  final Color? valueColor;

  const DetailRow({
    super.key,
    required this.label,
    required this.value,
    this.isMultiline = false,
    this.valueAlignment = TextAlign.end,
    this.labelColor,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final String display = value == null ? '' : value.toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: isMultiline ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: labelColor ?? const Color(0xFFEEEEEE),
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              display,
              textAlign: valueAlignment,
              style: TextStyle(color: valueColor ?? const Color(0xFFB0B0B0)),
              maxLines: isMultiline ? null : 1,
              overflow: isMultiline ? TextOverflow.clip : TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 📍 DELIVERY STATUS ENUM
// ─────────────────────────────────────────────────────────────────────────────

enum DeliveryStatus {
  pending,
  confirmed,
  processing,
  driverAssigned,
  pickedUp,
  outForDelivery,
  delivered,
  cancelled,
}

extension DeliveryStatusExtension on DeliveryStatus {
  String get displayName {
    switch (this) {
      case DeliveryStatus.pending:
        return 'Pending';
      case DeliveryStatus.confirmed:
        return 'Confirmed';
      case DeliveryStatus.processing:
        return 'Processing';
      case DeliveryStatus.driverAssigned:
        return 'Driver Assigned';
      case DeliveryStatus.pickedUp:
        return 'Picked Up';
      case DeliveryStatus.outForDelivery:
        return 'Out for Delivery';
      case DeliveryStatus.delivered:
        return 'Delivered';
      case DeliveryStatus.cancelled:
        return 'Cancelled';
    }
  }

  Color get color {
    switch (this) {
      case DeliveryStatus.pending:
        return Colors.orange;
      case DeliveryStatus.confirmed:
      case DeliveryStatus.processing:
        return Colors.blue;
      case DeliveryStatus.driverAssigned:
        return Colors.indigo;
      case DeliveryStatus.pickedUp:
        return Colors.purple;
      case DeliveryStatus.outForDelivery:
        return Colors.teal;
      case DeliveryStatus.delivered:
        return Colors.green;
      case DeliveryStatus.cancelled:
        return Colors.red;
    }
  }

  static DeliveryStatus fromString(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return DeliveryStatus.pending;
      case 'confirmed':
        return DeliveryStatus.confirmed;
      case 'processing':
        return DeliveryStatus.processing;
      case 'driver_assigned':
      case 'driverassigned':
        return DeliveryStatus.driverAssigned;
      case 'picked_up':
      case 'pickedup':
        return DeliveryStatus.pickedUp;
      case 'shipped':
      case 'out for delivery':
      case 'out_for_delivery':
        return DeliveryStatus.outForDelivery;
      case 'delivered':
        return DeliveryStatus.delivered;
      case 'cancelled':
        return DeliveryStatus.cancelled;
      default:
        return DeliveryStatus.pending;
    }
  }
}

// Currency formatter
String getCurrencySymbol(String? currency) {
  if (currency == null || currency.isEmpty) {
    return '\$'; // Default to USD
  }
  
  // Remove any whitespace and convert to uppercase
  final cleanedCurrency = currency.trim().toUpperCase();
  
  switch (cleanedCurrency) {
    case 'USD':
      return '\$';
    case 'EUR':
      return '€';
    case 'TRY':
      return '₺';
    case 'GBP':
      return '£';
    case 'JPY':
      return '¥';
    case 'INR':
      return '₹';
    case 'SAR':
      return 'ر.س';
    case 'AED':
      return 'د.إ';
    case 'YER':
      return 'ريال';
    default:
      return cleanedCurrency;
  }
}