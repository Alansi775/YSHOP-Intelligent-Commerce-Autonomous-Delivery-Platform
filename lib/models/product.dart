// lib/models/product.dart

import '../services/api_service.dart';

class Product {
  final String id;
  final String name;
  final String description;
  final double price;
  final String storeId;
  final String? storeName;
  final String? storeOwnerEmail;
  final String? storePhone;
  final String? categoryId;
  final int stock;
  final String imageUrl;
  final String? videoUrl;
  final List<String> imageUrls; //  قائمة الصور المتعددة
  final bool isActive;
  final String status;
  final String? currency; //  حقل العملة
  final String? storeIconUrl;

  // use ApiService.baseUrl for platform-aware host

  Product({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.storeId,
    this.storeName,
    this.storePhone,
    this.categoryId,
    required this.stock,
    required this.imageUrl,
    this.videoUrl,
    this.imageUrls = const [],
    this.isActive = true,
    this.status = 'approved',
    this.storeOwnerEmail,
    this.currency,
    this.storeIconUrl,
  });

  // Factory for backend API (MySQL)
  factory Product.fromJson(Map<String, dynamic> json) {
    // Always run through getFullImageUrl — rewrites .local hostnames for Android
    String imageUrl = getFullImageUrl(json['image_url'] as String? ?? '');

    String? videoUrl = json['video_url'] as String?;
    if (videoUrl != null && videoUrl.isNotEmpty) {
      videoUrl = getFullImageUrl(videoUrl);
    }

    List<String> imageUrls = [];
    if (json['image_urls'] != null) {
      imageUrls = (json['image_urls'] as List).map((url) {
        return getFullImageUrl(url?.toString() ?? '');
      }).toList();
    }
    
    // إذا لم تكن هناك قائمة صور، استخدم الصورة الرئيسية
    if (imageUrls.isEmpty && imageUrl.isNotEmpty) {
      imageUrls = [imageUrl];
    }

    double parsedPrice = 0.0;
    if (json['price'] is String) {
      parsedPrice = double.tryParse(json['price']) ?? 0.0;
    } else if (json['price'] != null) {
      parsedPrice = (json['price']).toDouble();
    }
    return Product(
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? 'Unknown Product',
      description: json['description'] ?? '',
      price: parsedPrice,
      storeId: json['store_id']?.toString() ?? '',
      storeName: json['store_name'],
      storePhone: json['store_phone'],
      categoryId: json['category_id']?.toString(),
      stock: json['stock'] ?? 0,
      imageUrl: imageUrl,
      videoUrl: videoUrl,
      imageUrls: imageUrls,
      isActive: json['status'] == 'approved',
      status: json['status'] ?? 'pending',
      storeOwnerEmail: json['store_owner_email'] ?? json['storeOwnerEmail'],
      currency: json['currency'] as String? ?? 'USD',
      storeIconUrl: json['store_icon_url'] as String? ?? json['store_icon'] as String? ?? json['storeIconUrl'] as String?,
    );
  }

  // Returns true if product is approved
  bool get approved => status == 'approved';

  // Returns storeName or 'N/A' if null
  String get storeNameOrNA => storeName ?? 'N/A';

  //  Helper method لتحويل أي مسار نسبي إلى URL كامل
  static String getFullImageUrl(String? path) {
    if (path == null || path.isEmpty) return '';

    // Strip file:// prefix (backend sometimes stores absolute local paths)
    if (path.startsWith('file://')) {
      path = path.replaceFirst(RegExp(r'^file://'), '');
    }

    try {
      if (path.startsWith('http')) {
        final uri = Uri.parse(path);
        final base = Uri.parse(ApiService.baseHost);
        final srcHost = uri.host;
        final baseHost = base.host;

        // Rewrite if the URL's host is a dev machine hostname/IP that differs from our base.
        // Covers: LAN IPs, loopback, and mDNS .local hostnames (not resolvable on Android).
        final needsRewrite = srcHost != baseHost && (
            srcHost.startsWith('192.168.') ||
            srcHost.startsWith('10.') ||
            srcHost == '127.0.0.1' ||
            srcHost == 'localhost' ||
            srcHost.endsWith('.local'));
        if (needsRewrite) {
          final replaced = base.replace(path: uri.path, query: uri.hasQuery ? uri.query : null);
          return replaced.toString();
        }

        return path;
      }
    } catch (_) {
      // parsing failed — fall through to treat as relative
    }

    // relative path — prefix with base host
    return '${ApiService.baseHost}$path';
  }

  //  Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'price': price,
      'store_id': storeId,
      'store_name': storeName,
      'store_phone': storePhone,
      'category_id': categoryId,
      'stock': stock,
      'image_url': imageUrl,
      'video_url': videoUrl,
      'image_urls': imageUrls,
      'is_active': isActive,
      'status': status,
      'storeOwnerEmail': storeOwnerEmail,
      'currency': currency,
      'store_icon_url': storeIconUrl,
    };
  }
}