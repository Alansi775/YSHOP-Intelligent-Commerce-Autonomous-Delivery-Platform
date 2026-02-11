// lib/models/category.dart

class Category {
  final int? id;
  final int storeId;
  final String name;
  final String displayName;
  final String? icon;
  final int displayOrder; // ترتيب العرض (1, 2, 3, ...)
  final DateTime? createdAt;
  final DateTime? updatedAt;
  
  // For UI purposes
  int productCount = 0;
  String lastProductName = "";

  Category({
    this.id,
    required this.storeId,
    required this.name,
    required this.displayName,
    this.icon,
    this.displayOrder = 0,
    this.createdAt,
    this.updatedAt,
  });

  // From JSON
  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id'] as int?,
      storeId: json['store_id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      icon: json['icon'] as String?,
      displayOrder: json['display_order'] as int? ?? 0,
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null 
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }

  // To JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'store_id': storeId,
      'name': name,
      'display_name': displayName,
      'icon': icon,
      'display_order': displayOrder,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  @override
  String toString() => 'Category($id, $name, $displayName)';
}

// 📋 الفئات المتاحة للماركتات
class CategoryTemplates {
  static const List<Map<String, String>> marketCategories = [
    {'name': 'fruits', 'displayName': 'Fruits'},
    {'name': 'vegetables', 'displayName': 'Vegetables'},
    {'name': 'beverages', 'displayName': 'Beverages'},
    {'name': 'meat', 'displayName': 'Meat'},
    {'name': 'chicken', 'displayName': 'Chicken'},
    {'name': 'bakery', 'displayName': 'Bakery'},
    {'name': 'canned_goods', 'displayName': 'Canned Goods'},
    {'name': 'grains', 'displayName': 'Grains & Pasta'},
    {'name': 'spices', 'displayName': 'Spices & Herbs'},
    {'name': 'oils', 'displayName': 'Oils & Vinegars'},
    {'name': 'frozen_foods', 'displayName': 'Frozen Foods'},
    {'name': 'snacks', 'displayName': 'Snacks'},
    {'name': 'dairy', 'displayName': 'Dairy Products'},
    {'name': 'household', 'displayName': 'Household Items'},
    {'name': 'cleaning', 'displayName': 'Cleaning Supplies'},
    {'name': 'dairy', 'displayName': 'Dairy '},
    {'name': 'frozen', 'displayName': 'Frozen Foods '},
    {'name': 'snacks', 'displayName': 'Snacks'},
    {'name': 'condiments', 'displayName': 'Condiments'},
  ];

  static const List<Map<String, String>> restaurantCategories = [
    {'name': 'Burgers', 'displayName': 'Burgers'},
    {'name': 'Pizzas', 'displayName': 'Pizzas'},
    {'name': 'Sandwiches', 'displayName': 'Sandwiches'},
    {'name': 'Pasta', 'displayName': 'Pasta'},
    {'name': 'Rice_dishes', 'displayName': 'Rice Dishes'},
    {'name': 'Fries', 'displayName': 'Fries'},
    {'name': 'Chicken', 'displayName': 'Chicken'},
    {'name': 'Meat', 'displayName': 'Meat'},
    {'name': 'Seafood', 'displayName': 'Seafood'},
    {'name': 'Salads', 'displayName': 'Salads'},
    {'name': 'Soups', 'displayName': 'Soups'},
    {'name': 'Appetizers', 'displayName': 'Appetizers'},
    {'name': 'Sides', 'displayName': 'Sides'},
    {'name': 'Sauces', 'displayName': 'Sauces'},
    {'name': 'Desserts', 'displayName': 'Desserts'},
    {'name': 'Drinks', 'displayName': 'Drinks'},
    {'name': 'Juices', 'displayName': 'Juices'},
    {'name': 'Coffee', 'displayName': 'Coffee'},
    {'name': 'Smoothies', 'displayName': 'Smoothies'},
    {'name': 'Milkshakes', 'displayName': 'Milkshakes'},
    {'name': 'Campaigns', 'displayName': 'Campaigns'},
    {'name': 'Wraps', 'displayName': 'Wraps'},
    {'name': 'Boxes', 'displayName': 'Boxes'},
    {'name': 'Buckets', 'displayName': 'Buckets'},
    {'name': 'Chickens with Sauce', 'displayName': 'Chickens with Sauce'},
    {'name': 'Side Products and Desserts', 'displayName': 'Side Products and Desserts'},
    {'name': 'Sandwiches', 'displayName': 'Sandwiches'},
    {'name': 'Pasta', 'displayName': 'Pasta'},
    {'name': 'Rice_dishes', 'displayName': 'Rice Dishes'},
    {'name': 'Fries', 'displayName': 'Fries'},
    {'name': 'Chicken', 'displayName': 'Chicken'},
    {'name': 'Meat', 'displayName': 'Meat'},
    {'name': 'Seafood', 'displayName': 'Seafood'},
    {'name': 'Salads', 'displayName': 'Salads'},
    {'name': 'Soups', 'displayName': 'Soups'},
    {'name': 'Appetizers', 'displayName': 'Appetizers'},
    {'name': 'Sides', 'displayName': 'Sides'},
    {'name': 'Desserts', 'displayName': 'Desserts'},
    {'name': 'Juices', 'displayName': 'Juices'},
    {'name': 'Coffee', 'displayName': 'Coffee'},
    {'name': 'Smoothies', 'displayName': 'Smoothies'},
    {'name': 'Milkshakes', 'displayName': 'Milkshakes'},
  ];

  static const List<Map<String, String>> pharmacyCategories = [
    {'name': 'medicines', 'displayName': 'Medicines'},
    {'name': 'supplements', 'displayName': 'Supplements'},
    {'name': 'first_aid', 'displayName': 'First Aid'},
    {'name': 'medical_devices', 'displayName': 'Medical Devices'},
    {'name': 'personal_care', 'displayName': 'Personal Care'},
    {'name': 'vitamins', 'displayName': 'Vitamins'},
  ];

  static const List<Map<String, String>> clothingCategories = [
    {'name': 'men', 'displayName': 'Men'},
    {'name': 'women', 'displayName': 'Women'},
    {'name': 'kids', 'displayName': 'Kids'},
    {'name': 'accessories', 'displayName': 'Accessories'},
    {'name': 'shoes', 'displayName': 'Shoes'},
    {'name': 'sports', 'displayName': 'Sports'},
  ];

  static String getDisplayName(String categoryName) {
    try {
      return marketCategories
          .firstWhere((cat) => cat['name'] == categoryName)['displayName'] ??
          categoryName;
    } catch (e) {
      return categoryName;
    }
  }

  static List<Map<String, String>> getAvailableCategories(
      List<Category> existingCategories, String storeType) {
    // اختر الفئات حسب نوع المتجر
    List<Map<String, String>> templateCategories;
    
    if (storeType.toLowerCase() == 'food' || storeType.toLowerCase() == 'restaurant') {
      templateCategories = restaurantCategories;
    } else if (storeType.toLowerCase() == 'pharmacy') {
      templateCategories = pharmacyCategories;
    } else if (storeType.toLowerCase() == 'clothing') {
      templateCategories = clothingCategories;
    } else {
      templateCategories = marketCategories;
    }

    final existingNames =
        existingCategories.map((c) => c.name).toSet();
    return templateCategories
        .where((cat) => !existingNames.contains(cat['name']))
        .toList();
  }
}
