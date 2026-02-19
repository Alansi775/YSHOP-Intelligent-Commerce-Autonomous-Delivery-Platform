// lib/screens/admin/common.dart

import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  YSHOP BRAND DESIGN SYSTEM - Matching Current App Style
// ═══════════════════════════════════════════════════════════════════════════════

// Primary Background Colors - Matching your app
const Color kDarkBackground = Color(0xFF1A1A1E);      // الخلفية الرئيسية
const Color kDeepBackground = Color(0xFF141417);      // أغمق قليلاً للـ sidebar

// Surface Colors - Cards & Containers
const Color kSurfaceColor = Color(0xFF252529);        // لون البطاقات
const Color kSurfaceLight = Color(0xFF2D2D32);        // بطاقة أفتح
const Color kSurfaceDark = Color(0xFF1E1E22);         // بطاقة أغمق

// Glass Effect - Subtle
const Color kGlassBackground = Color(0xFF252529);     // خلفية زجاجية
const Color kGlassBorder = Color(0xFF3A3A3F);         // حدود خفيفة
const Color kGlassHighlight = Color(0xFF2F2F34);      // لمعة

// Card Colors
const Color kCardBackground = Color(0xFF252529);      // خلفية البطاقة
const Color kCardBackgroundHover = Color(0xFF2D2D32); // عند التحويم
const Color kCardBorder = Color(0xFF3A3A3F);          // حدود البطاقة

// App Bar
const Color kAppBarBackground = Color(0xFF1A1A1E);

// Text Colors - Clean Hierarchy
const Color kPrimaryTextColor = Color(0xFFFFFFFF);    // أبيض للعناوين
const Color kSecondaryTextColor = Color(0xFF9A9A9F);  // رمادي للنص الثانوي
const Color kTertiaryTextColor = Color(0xFF6B6B70);   // رمادي أغمق
const Color kMutedTextColor = Color(0xFF505055);      // رمادي خافت

// Primary Accent - Blue (للأزرار والعناصر المحددة فقط)
const Color kAccentBlue = Color(0xFF3B82F6);          // الأزرق الرئيسي
const Color kAccentBlueLight = Color(0xFF60A5FA);     // أزرق فاتح
const Color kAccentBlueDark = Color(0xFF2563EB);      // أزرق غامق

// Status/Icon Colors - للأيقونات فقط
const Color kAccentGreen = Color(0xFF22C55E);         // أخضر
const Color kAccentOrange = Color(0xFFF97316);        // برتقالي
const Color kAccentRed = Color(0xFFEF4444);           // أحمر
const Color kAccentPurple = Color(0xFF3A3A3F);        // بنفسجي
const Color kAccentYellow = Color(0xFFEAB308);        // أصفر
const Color kAccentCyan = Color(0xFF06B6D4);          // سماوي
const Color kAccentPink = Color(0xFFEC4899);          // وردي

// Status Colors
const Color kStatusApproved = Color(0xFF22C55E);
const Color kStatusPending = Color(0xFFF97316);
const Color kStatusRejected = Color(0xFFEF4444);

// Borders & Separators
const Color kSeparatorColor = Color(0xFF2D2D32);
const Color kBorderColor = Color(0xFF3A3A3F);

// Sidebar specific
const Color kSidebarBackground = Color(0xFF141417);
const Color kSidebarItemHover = Color(0xFF252529);
const Color kSidebarItemActive = Color(0xFF2D2D32);

// ═══════════════════════════════════════════════════════════════════════════════
//  GRADIENT DEFINITIONS - Minimal & Clean
// ═══════════════════════════════════════════════════════════════════════════════

class AppGradients {
  // Primary Blue - للأزرار فقط
  static const LinearGradient primary = LinearGradient(
    colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  // Surface Gradients - للبطاقات
  static const LinearGradient surface = LinearGradient(
    colors: [Color(0xFF2D2D32), Color(0xFF252529)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  static const LinearGradient dark = LinearGradient(
    colors: [Color(0xFF252529), Color(0xFF1E1E22)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  static const LinearGradient glass = LinearGradient(
    colors: [Color(0xFF2D2D32), Color(0xFF252529)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
  
  // Status Gradients - للأيقونات فقط
  static const LinearGradient success = LinearGradient(
    colors: [Color(0xFF22C55E), Color(0xFF16A34A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  static const LinearGradient warning = LinearGradient(
    colors: [Color(0xFFF97316), Color(0xFFEA580C)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  static const LinearGradient danger = LinearGradient(
    colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  static const LinearGradient purple = LinearGradient(
    colors: [Color(0xFF8B5CF6), Color(0xFF7C3AED)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  static const LinearGradient cyan = LinearGradient(
    colors: [Color(0xFF06B6D4), Color(0xFF0891B2)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  static const LinearGradient pink = LinearGradient(
    colors: [Color(0xFFEC4899), Color(0xFFDB2777)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
//  DATA MODELS
// ═══════════════════════════════════════════════════════════════════════════════

class ProductSS {
  final String id;
  final String storeName;
  final String storeId;
  final String name;
  final String price;
  final String description;
  final String? imageUrl;
  final String? videoUrl;
  final int? stock;
  final String storeOwnerEmail;
  final String storePhone;
  final String status;
  final bool approved;
  final String? currency;
  final int? categoryId;
  final String? categoryName;

  ProductSS({
    required this.id,
    required this.storeName,
    this.storeId = '',
    required this.name,
    required this.price,
    required this.description,
    this.imageUrl,
    this.videoUrl,
    this.stock,
    required this.storeOwnerEmail,
    required this.storePhone,
    required this.status,
    required this.approved,
    this.currency,
    this.categoryId,
    this.categoryName,
  });

  factory ProductSS.fromJson(Map<String, dynamic> json) {
    return ProductSS(
      id: json["id"]?.toString() ?? "",
      storeName: json["store_name"] as String? ?? "",
      storeId: json["store_id"]?.toString() ?? "",
      name: json["name"] as String? ?? "",
      price: (json["price"] is num) ? json["price"].toString() : json["price"] as String? ?? "0.00",
      description: json["description"] as String? ?? "",
      imageUrl: json["image_url"] as String?,
      storeOwnerEmail: json["store_owner_email"] as String? ?? "",
      storePhone: json["store_phone"] as String? ?? "No Phone",
      status: json["status"] as String? ?? "Pending",
      approved: json["approved"] as bool? ?? false,
      currency: json["currency"] as String? ?? "USD",
      categoryId: json["category_id"] as int?,
      categoryName: json["category_name"] as String?,
    );
  }

  factory ProductSS.fromMap(Map<String, dynamic> m) {
    return ProductSS(
      id: (m['id'] ?? '').toString(),
      storeName: m['store_name'] as String? ?? m['storeName'] as String? ?? 'Unknown Store',
      storeId: (m['store_id'] ?? m['storeId'] ?? '').toString(),
      name: m['name'] as String? ?? '',
      price: (m['price'] ?? '0.00').toString(),
      description: m['description'] as String? ?? '',
      imageUrl: m['image_url'] as String? ?? m['imageUrl'] as String?,
      videoUrl: m['video_url'] as String?,
      stock: m['stock'] is int ? m['stock'] : int.tryParse((m['stock'] ?? '').toString()),
      storeOwnerEmail: m['owner_email'] as String? ?? m['storeOwnerEmail'] as String? ?? '',
      storePhone: (m['store_phone'] ?? m['storePhone'] ?? '').toString(),
      status: m['status'] as String? ?? 'Pending',
      currency: m['currency'] as String? ?? 'USD',
      approved: m['status']?.toString().toLowerCase() == 'approved',
      categoryId: m['category_id'] as int?,
      categoryName: m['category_name'] as String?,
    );
  }
}

class StoreRequest {
  final String id;
  final String ownerUid;
  final String storeName;
  final String storeType;
  final String address;
  final String email;
  final String storeIconUrl;
  final String storePhone;
  final String status;

  StoreRequest({
    required this.id,
    required this.ownerUid,
    required this.storeName,
    required this.storeType,
    required this.address,
    required this.email,
    required this.storeIconUrl,
    required this.storePhone,
    required this.status,
  });

  factory StoreRequest.fromJson(Map<String, dynamic> json) {
    return StoreRequest(
      id: json['id']?.toString() ?? "",
      ownerUid: json['owner_uid'] as String? ?? "",
      storeName: json["name"] as String? ?? "",
      storeType: json["store_type"] as String? ?? "",
      address: json["address"] as String? ?? "",
      email: json["email"] as String? ?? "",
      storeIconUrl: json["icon_url"] as String? ?? "",
      storePhone: json["phone"] as String? ?? "",
      status: json["status"] as String? ?? "Pending",
    );
  }

  factory StoreRequest.fromMap(Map<String, dynamic> m) {
    return StoreRequest(
      id: (m['id'] ?? '').toString(),
      ownerUid: m['owner_uid'] as String? ?? '',
      storeName: m['name'] as String? ?? m['storeName'] as String? ?? '',
      storeType: m['store_type'] as String? ?? m['storeType'] as String? ?? '',
      address: m['address'] as String? ?? '',
      email: m['email'] as String? ?? '',
      storeIconUrl: m['icon_url'] as String? ?? m['storeIconUrl'] as String? ?? '',
      storePhone: (m['phone'] ?? m['storePhone'] ?? '').toString(),
      status: m['status'] as String? ?? 'Pending',
    );
  }
}

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
  final DateTime? createdAt;

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
    this.createdAt,
  });

  factory DeliveryRequest.fromJson(Map<String, dynamic> json) {
    return DeliveryRequest(
      id: json['id']?.toString() ?? "",
      uid: json["uid"] as String? ?? "",
      name: json["name"] as String? ?? "",
      email: json["email"] as String? ?? "",
      phoneNumber: json["phone"] as String? ?? "N/A",
      nationalID: json["national_id"] as String? ?? "N/A",
      address: json["address"] as String? ?? "N/A",
      status: json["status"] as String? ?? "Pending",
    );
  }

  factory DeliveryRequest.fromMap(Map<String, dynamic> m) {
    return DeliveryRequest(
      id: (m['id'] ?? m['ID'] ?? m['Id'] ?? '').toString(),
      uid: m['uid'] as String? ?? '',
      name: m['name'] as String? ?? m['full_name'] as String? ?? '',
      email: m['email'] as String? ?? '',
      phoneNumber: m['phone'] as String? ?? m['phoneNumber'] as String? ?? 'N/A',
      nationalID: m['national_id'] as String? ?? m['nationalID'] as String? ?? 'N/A',
      address: m['address'] as String? ?? '',
      status: m['status'] as String? ?? 'Pending',
      isWorking: m['is_working'] == 1 || m['is_working'] == true,
      createdAt: m['created_at'] != null ? DateTime.tryParse(m['created_at'].toString()) : null,
    );
  }
}

class OrderModel {
  final String id;
  final String oderId;
  final String storeId;
  final String storeName;
  final double totalPrice;
  final String currency;
  final String status;
  final String shippingAddress;
  final String paymentMethod;
  final String deliveryOption;
  final String? driverLocation;
  final String? driverName;
  final String? driverPhone;
  final double? driverLatitude;
  final double? driverLongitude;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<OrderItem> items;

  OrderModel({
    required this.id,
    required this.oderId,
    required this.storeId,
    this.storeName = '',
    required this.totalPrice,
    this.currency = 'USD',
    required this.status,
    required this.shippingAddress,
    required this.paymentMethod,
    required this.deliveryOption,
    this.driverLocation,
    this.driverName,
    this.driverPhone,
    this.driverLatitude,
    this.driverLongitude,
    this.createdAt,
    this.updatedAt,
    this.items = const [],
  });

  factory OrderModel.fromMap(Map<String, dynamic> m) {
    List<OrderItem> orderItems = [];
    if (m['items'] != null && m['items'] is List) {
      orderItems = (m['items'] as List).map((item) => OrderItem.fromMap(item)).toList();
    }
    
    // Handle driverLocation - can be String or Map
    String? driverLocationStr;
    if (m['driver_location'] != null) {
      if (m['driver_location'] is String) {
        driverLocationStr = m['driver_location'] as String;
      } else if (m['driver_location'] is Map) {
        // Convert Map to JSON string
        driverLocationStr = m['driver_location'].toString();
      }
    }
    
    return OrderModel(
      id: (m['id'] ?? '').toString(),
      oderId: (m['user_id'] ?? '').toString(),
      storeId: (m['store_id'] ?? '').toString(),
      storeName: m['store_name'] as String? ?? '',
      totalPrice: double.tryParse((m['total_price'] ?? '0').toString()) ?? 0.0,
      currency: (m['currency'] as String? ?? 'USD').toUpperCase(),
      status: (m['status'] as String? ?? 'pending').toLowerCase(),
      shippingAddress: m['shipping_address'] as String? ?? '',
      paymentMethod: m['payment_method'] as String? ?? '',
      deliveryOption: m['delivery_option'] as String? ?? 'Standard',
      driverLocation: driverLocationStr,
      driverName: m['driver_name'] as String?,
      driverPhone: m['driver_phone'] as String?,
      driverLatitude: m['driver_latitude'] != null ? double.tryParse(m['driver_latitude'].toString()) : null,
      driverLongitude: m['driver_longitude'] != null ? double.tryParse(m['driver_longitude'].toString()) : null,
      createdAt: m['created_at'] != null ? DateTime.tryParse(m['created_at'].toString()) : null,
      updatedAt: m['updated_at'] != null ? DateTime.tryParse(m['updated_at'].toString()) : null,
      items: orderItems,
    );
  }
}

class OrderItem {
  final String id;
  final String productId;
  final String name;
  final int quantity;
  final double price;
  final String? imageUrl;

  OrderItem({
    required this.id,
    required this.productId,
    required this.name,
    required this.quantity,
    required this.price,
    this.imageUrl,
  });

  factory OrderItem.fromMap(Map<String, dynamic> m) {
    return OrderItem(
      id: (m['id'] ?? '').toString(),
      productId: (m['product_id'] ?? '').toString(),
      name: m['name'] as String? ?? 'Product',
      quantity: int.tryParse((m['quantity'] ?? '1').toString()) ?? 1,
      price: double.tryParse((m['price'] ?? '0').toString()) ?? 0.0,
      imageUrl: m['image_url'] as String?,
    );
  }
}

class AdminModel {
  final String id;
  final String email;
  final String firstName;
  final String lastName;
  final String role;
  final String status;
  final DateTime? createdAt;

  AdminModel({
    required this.id,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.role,
    this.status = 'active',
    this.createdAt,
  });

  String get fullName => '$firstName $lastName'.trim();

  factory AdminModel.fromMap(Map<String, dynamic> m) {
    return AdminModel(
      id: (m['id'] ?? '').toString(),
      email: m['email'] as String? ?? '',
      firstName: m['first_name'] as String? ?? '',
      lastName: m['last_name'] as String? ?? '',
      role: m['role'] as String? ?? 'admin',
      createdAt: m['created_at'] != null ? DateTime.tryParse(m['created_at'].toString()) : null,
    );
  }
}

class UserModel {
  final String id;
  final String email;
  final String firstName;
  final String lastName;
  final String adminId;
  final String role;
  final String status;
  final DateTime? createdAt;

  UserModel({
    required this.id,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.adminId,
    required this.role,
    this.status = 'active',
    this.createdAt,
  });

  String get fullName => '$firstName $lastName'.trim();

  factory UserModel.fromMap(Map<String, dynamic> m) {
    return UserModel(
      id: (m['id'] ?? '').toString(),
      email: m['email'] as String? ?? '',
      firstName: m['first_name'] as String? ?? '',
      lastName: m['last_name'] as String? ?? '',
      adminId: (m['admin_id'] ?? '').toString(),
      role: m['role'] as String? ?? 'user',
      status: (() {
        // Support different backend representations
        if (m.containsKey('status') && m['status'] != null) return m['status'].toString();
        if (m.containsKey('is_banned')) {
          final v = m['is_banned'];
          if (v is bool) return v ? 'banned' : 'active';
          if (v is int) return v == 1 ? 'banned' : 'active';
        }
        return 'active';
      })(),
      createdAt: m['created_at'] != null ? DateTime.tryParse(m['created_at'].toString()) : null,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// 💰 REVENUE CALCULATOR
// ═══════════════════════════════════════════════════════════════════════════════

class RevenueCalculator {
  static const double APP_COMMISSION_RATE = 0.25;  // 25% of total price goes to app/admin
  static const double DRIVER_RATE = 0.10;           // 10% of total price goes to driver
  static const double STORE_OWNER_RATE = 0.65;      // 65% of total price goes to store owner (75% - 10% driver)

  static double calculateAppRevenue(double totalPrice) {
    return totalPrice * APP_COMMISSION_RATE;
  }

  static double calculateStoreOwnerRevenue(double totalPrice) {
    return totalPrice * STORE_OWNER_RATE;
  }

  static double calculateDriverRevenue(double totalPrice) {
    return totalPrice * DRIVER_RATE;
  }

  static Map<String, double> calculateOrderRevenue(double totalPrice) {
    return {
      'app': calculateAppRevenue(totalPrice),
      'store': calculateStoreOwnerRevenue(totalPrice),
      'driver': calculateDriverRevenue(totalPrice),
      'total': totalPrice,
    };
  }

  static Map<String, double> calculateTotalRevenue(List<OrderModel> orders) {
    double totalOrdersValue = 0.0;
    double totalAppRevenue = 0.0;
    double totalStoreRevenue = 0.0;
    double totalDriverRevenue = 0.0;

    for (final order in orders) {
      totalOrdersValue += order.totalPrice;
      totalAppRevenue += calculateAppRevenue(order.totalPrice);
      totalStoreRevenue += calculateStoreOwnerRevenue(order.totalPrice);
      totalDriverRevenue += calculateDriverRevenue(order.totalPrice);
    }

    return {
      'totalOrders': totalOrdersValue,
      'appRevenue': totalAppRevenue,
      'storeRevenue': totalStoreRevenue,
      'driverRevenue': totalDriverRevenue,
    };
  }
}