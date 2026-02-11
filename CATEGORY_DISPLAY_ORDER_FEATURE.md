# 📋 ميزة ترتيب Categories (Category Display Order)

## نظرة عامة
تم إضافة ميزة جديدة تسمح لصاحب المحل بترتيب الفئات (Categories) الخاصة به بالطريقة التي يريدها. كل فئة لها رقم ترتيب (display_order) يحدد موضعها في القائمة.

---

## الميزات الرئيسية ✨

1. **ترتيب مخصص**: صاحب المحل يقدر يرتب فئاته بأي ترتيب يريده
2. **Drag & Drop**: واجهة سهلة لسحب وإفلات الفئات
3. **حفظ فوري**: التغييرات تُحفظ تلقائياً في قاعدة البيانات
4. **عرض مباشر**: الترتيب يظهر مباشرة عند المستخدمين

---

## التغييرات الجديدة

### 1️⃣ نموذج Category (في `lib/models/category.dart`)

```dart
class Category {
  final int? id;
  final int storeId;
  final String name;
  final String displayName;
  final String? icon;
  final int displayOrder;  // ✅ جديد: رقم الترتيب (1, 2, 3, ...)
  final DateTime? createdAt;
  final DateTime? updatedAt;
  // ...
}
```

### 2️⃣ Backend API

#### جدول قاعدة البيانات
تم إضافة عمود جديد:
```sql
ALTER TABLE categories ADD COLUMN display_order INT DEFAULT 0
```

#### Endpoints الجديدة والمحدثة

**GET `/stores/:storeId/categories`** (محدّث)
- الآن يعيد الفئات **مرتبة حسب `display_order`**
```javascript
ORDER BY display_order ASC, created_at ASC
```

**POST `/stores/:storeId/categories`** (محدّث)
- عند إنشاء فئة جديدة، يتم إسناد `display_order` تلقائياً
- القيمة = أعلى `display_order` موجود + 1

**PUT `/stores/:storeId/categories/reorder`** (جديد)
- لتحديث ترتيب الفئات
- Body:
```json
{
  "categories": [
    { "id": 1, "display_order": 1 },
    { "id": 2, "display_order": 2 },
    { "id": 3, "display_order": 3 }
  ]
}
```

### 3️⃣ واجهة إعادة الترتيب الجديدة

**ملف جديد**: `lib/screens/stores/category_reorder_view.dart`

الميزات:
- عرض جميع الفئات في قائمة
- إمكانية سحب (Drag) والإفلات (Drop) لإعادة الترتيب
- عرض رقم الترتيب الحالي لكل فئة
- زر "Save" لحفظ التغييرات

### 4️⃣ تحديثات API Service

```dart
// في lib/services/api_service.dart

static Future<bool> reorderCategories(
  int storeId,
  List<Map<String, dynamic>> categories,
) async {
  // إرسال الترتيب الجديد للـ Backend
}
```

### 5️⃣ تحديثات في Store Admin View

تم إضافة **زر "Reorder"** بجانب زر "Add Category":
- يظهر فقط عندما تكون هناك أكثر من فئة واحدة
- لون برتقالي (Orange) للتمييز

```dart
if (_categories.length > 1)
  ElevatedButton.icon(
    onPressed: () {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => CategoryReorderView(...)
        ),
      );
    },
    icon: const Icon(Icons.swap_vert),
    label: const Text('Reorder'),
  )
```

---

## Migration Script

تم إنشاء script لتحديث قواعد البيانات الموجودة:

**ملف**: `backend/scripts/add_display_order_to_categories.js`

**الاستخدام**:
```bash
cd backend
node scripts/add_display_order_to_categories.js
```

**ما يفعله**:
1. ✅ يضيف العمود `display_order` إذا لم يكن موجوداً
2. ✅ يرقم الفئات الموجودة حسب `created_at`
3. ✅ لكل متجر، الفئات تُرقم من 1 إلى n

---

## كيفية الاستخدام

### للعميل (صاحب المحل) 🏪

1. **الدخول إلى Dashboard**
   - اذهب إلى Store Admin View

2. **الوصول إلى Reorder**
   - اضغط على زر "Reorder" بجانب الفئات

3. **إعادة الترتيب**
   - اسحب الفئات وأرتبها كما تريد
   - سترى الترقيم يتحدث تلقائياً

4. **حفظ**
   - اضغط "حفظ الترتيب"
   - سيظهر فوراً للعملاء

### للعميل (المشتري) 👤

- سيرى الفئات مرتبة حسب ترتيب صاحب المحل
- عند دخول متجر، الفئات تظهر بالترتيب المحدد

---

## مثال عملي

### قبل الميزة:
```
متجر الهمبرجر
├── الفئة 1: Pizza (created_at: 2026-01-22)
├── الفئة 2: Burgers (created_at: 2026-01-20)
└── الفئة 3: Desserts (created_at: 2026-01-25)
```
الترتيب كان عشوائياً حسب تاريخ الإنشاء!

### بعد الميزة:
صاحب المحل يفتح شاشة Reorder:
```
1. Burgers       ☰ (Drag to reorder)
2. Pizza         ☰
3. Desserts      ☰
```

يسحب Burgers للأعلى:
```
1. Burgers       ☰ ✓ (الآن الأول!)
2. Pizza         ☰
3. Desserts      ☰
```

يضغط "حفظ الترتيب" ✅

المشترين يرون الآن Burgers أولاً! 🍔

---

## البيانات في قاعدة البيانات

### جدول categories
```
id    | store_id | name       | display_name | display_order | created_at
------|----------|------------|--------------|---------------|-----------
13    | 502      | Burgers    | Burgers      | 1             | 2026-01-20
14    | 502      | Pizza      | Pizza        | 2             | 2026-01-22
15    | 502      | Desserts   | Desserts     | 3             | 2026-01-25
```

---

## ملفات التعديل

### ملفات تم تحديثها:
1. ✅ `lib/models/category.dart` - إضافة `displayOrder`
2. ✅ `lib/services/api_service.dart` - إضافة `reorderCategories()`
3. ✅ `backend/src/routes/categoryRoutes.js` - تحديث الـ endpoints
4. ✅ `lib/screens/customers/store_detail_view.dart` - ترتيب حسب `displayOrder`
5. ✅ `lib/screens/stores/store_admin_view.dart` - إضافة زر Reorder

### ملفات جديدة:
1. ✨ `lib/screens/stores/category_reorder_view.dart` - واجهة إعادة الترتيب
2. ✨ `backend/scripts/add_display_order_to_categories.js` - Migration script

---

## خطوات التثبيت والتفعيل

### 1️⃣ قاعدة البيانات
```bash
cd backend
node scripts/add_display_order_to_categories.js
```

### 2️⃣ Rebuild Flutter App
```bash
cd ..
flutter clean
flutter pub get
flutter run
```

---

## ملاحظات تقنية

- القيمة الافتراضية لـ `display_order` هي **0**
- يتم الترتيب تصاعدياً: **1 ← 2 ← 3 ← ...**
- إذا كانت لديك نفس `display_order`، يتم الترتيب الثانوي حسب `created_at`
- يتم حذف Cache تلقائياً عند حفظ ترتيب جديد

---

## الأمان والتحقق

- ✅ يتم التحقق من أن الفئات تخص المتجر الصحيح (store_id check)
- ✅ يتم التحقق من أن المستخدم مصرح بتعديل هذا المتجر (auth check)
- ✅ جميع العمليات تستخدم Transactions (atomicity)

---

## الدعم والمشاكل

إذا حدثت مشكلة:
1. ✅ تأكد من تشغيل Migration script
2. ✅ امسح Cache في Flutter: `flutter clean`
3. ✅ تحقق من أن Backend يعيد `display_order` في الـ response

---

آخر تحديث: 11 فبراير 2026
