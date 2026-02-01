///  Store Categories - Centralized list used across the app
/// Used in: SignUp (store owner), Categories Home, Admin Dashboard
class StoreCategories {
  static const List<String> all = [
    "Food",
    "Pharmacy",
    "Clothes",
    "Market",
  ];

  static bool isValid(String category) => all.contains(category);

  static String? validate(String? category) {
    if (category == null || category.isEmpty) return null;
    if (isValid(category)) return category;
    return null;
  }
}
