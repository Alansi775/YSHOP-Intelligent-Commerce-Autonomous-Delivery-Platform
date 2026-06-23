// lib/models/store.dart
import '../services/api_service.dart';
import 'product.dart';

class Store {
  final String id;
  final String storeName;
  final String storeType;
  final String storeIconUrl;
  final String? address;
  final String? storePhoneNumber;
  final String? status;
  final String? email;
  final String? ownerUid;
  final String? uid;  // UID من جدول stores

  // use ApiService.baseUrl for platform-aware host

  Store({
    required this.id,
    required this.storeName,
    required this.storeType,
    required this.storeIconUrl,
    this.address,
    this.storePhoneNumber,
    this.status,
    this.email,
    this.ownerUid,
    this.uid,
  });

  // Factory for backend API (MySQL)
  factory Store.fromJson(Map<String, dynamic> json) {
    // Always run through Product.getFullImageUrl — rewrites .local hostnames for Android
    String iconUrl = Product.getFullImageUrl(json['icon_url'] as String? ?? '');

    //  تحديد الـ status من قاعدة البيانات مباشرة
    String status = json['status'] ?? 'Pending';

    return Store(
      id: json['id']?.toString() ?? '',
      storeName: json['name'] ?? 'Unknown Store',
      storeType: json['store_type'] ?? json['storeType'] ?? '', //  تصحيح
      storeIconUrl: iconUrl,
      address: json['address'],
      storePhoneNumber: json['phone']?.toString(),
      status: status,
      email: json['email'],
      ownerUid: json['owner_uid'] ?? json['ownerUid'],
      uid: json['uid'] ?? json['owner_uid'],  // استخدم uid من الـ response
    );
  }

  //  Helper method لتحويل أي مسار نسبي إلى URL كامل
  static String getFullImageUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http')) return path;
    return '${ApiService.baseHost}$path';
  }

  //  Convert to JSON (للإرسال للـ API)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': storeName,
      'store_type': storeType,
      'icon_url': storeIconUrl,
      'address': address,
      'phone': storePhoneNumber,
      'status': status,
      'email': email,
      'owner_uid': ownerUid,
    };
  }
}