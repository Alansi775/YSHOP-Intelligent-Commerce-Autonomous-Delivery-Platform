// pos_models.dart — Local POS System data models

class POSTable {
  final int id;
  final int storeId;
  final String name;
  final int capacity;
  final String status; // available | occupied | preparing | waiting_payment | disabled
  final String qrToken;
  final int sortOrder;
  final bool hasActiveOrder;

  const POSTable({
    required this.id,
    required this.storeId,
    required this.name,
    required this.capacity,
    required this.status,
    required this.qrToken,
    this.sortOrder = 0,
    this.hasActiveOrder = false,
  });

  factory POSTable.fromJson(Map<String, dynamic> j) => POSTable(
    id: j['id'] as int,
    storeId: j['store_id'] as int,
    name: j['name'] as String,
    capacity: j['capacity'] as int? ?? 4,
    status: j['status'] as String? ?? 'available',
    qrToken: j['qr_token'] as String? ?? '',
    sortOrder: j['sort_order'] as int? ?? 0,
    hasActiveOrder: (j['has_active_order'] as int? ?? 0) > 0,
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'store_id': storeId, 'name': name, 'capacity': capacity,
    'status': status, 'qr_token': qrToken, 'sort_order': sortOrder,
  };

  POSTable copyWith({String? name, int? capacity, String? status, bool? hasActiveOrder}) => POSTable(
    id: id, storeId: storeId, qrToken: qrToken, sortOrder: sortOrder,
    name: name ?? this.name,
    capacity: capacity ?? this.capacity,
    status: status ?? this.status,
    hasActiveOrder: hasActiveOrder ?? this.hasActiveOrder,
  );

  bool get isAvailable => status == 'available';
  bool get isOccupied => status == 'occupied';
  bool get isPreparing => status == 'preparing';
  bool get isWaitingPayment => status == 'waiting_payment';
  bool get isDisabled => status == 'disabled';
}

// ─── POS Order Item ──────────────────────────────────────────────────────────

class POSOrderItem {
  final int? id;
  final int productId;
  final String productName;
  final String? imageUrl;
  final int quantity;
  final double price;
  final String? notes;
  final String currency; // taken from the product, NOT from a widget param
  final DateTime? createdAt; // when this line was added to the order

  const POSOrderItem({
    this.id,
    required this.productId,
    required this.productName,
    this.imageUrl,
    required this.quantity,
    required this.price,
    this.notes,
    this.currency = '',
    this.createdAt,
  });

  factory POSOrderItem.fromJson(Map<String, dynamic> j) => POSOrderItem(
    id: j['id'] as int?,
    productId: j['product_id'] as int,
    productName: j['product_name'] as String? ?? '',
    imageUrl: j['image_url'] as String?,
    quantity: j['quantity'] as int,
    price: double.tryParse(j['price']?.toString() ?? '0') ?? 0,
    notes: j['notes'] as String?,
    currency: j['currency'] as String? ?? '',
    createdAt: j['created_at'] != null ? DateTime.tryParse(j['created_at'].toString()) : null,
  );

  Map<String, dynamic> toJson() => {
    'productId': productId,
    'price': price,
    'quantity': quantity,
    if (notes != null) 'notes': notes,
  };

  double get subtotal => price * quantity;
  POSOrderItem copyWith({int? quantity, String? notes}) => POSOrderItem(
    id: id, productId: productId, productName: productName, imageUrl: imageUrl,
    price: price, currency: currency, createdAt: createdAt,
    quantity: quantity ?? this.quantity,
    notes: notes ?? this.notes,
  );
}

// ─── POS Order ───────────────────────────────────────────────────────────────

class POSOrder {
  final int id;
  final int storeId;
  final int? tableId;
  final String? tableName;
  final double totalPrice;
  final String currency;
  final String status;
  final String kitchenStatus; // pending | preparing | ready | delivered
  final String? localPaymentMethod;
  final bool localPaid;
  final String? cashierNotes;
  final List<POSOrderItem> items;
  final DateTime createdAt;
  final DateTime? kitchenUpdatedAt; // last time the kitchen touched this ticket

  const POSOrder({
    required this.id,
    required this.storeId,
    this.tableId,
    this.tableName,
    required this.totalPrice,
    required this.currency,
    required this.status,
    required this.kitchenStatus,
    this.localPaymentMethod,
    required this.localPaid,
    this.cashierNotes,
    required this.items,
    required this.createdAt,
    this.kitchenUpdatedAt,
  });

  factory POSOrder.fromJson(Map<String, dynamic> j) {
    List<POSOrderItem> parseItems(dynamic raw) {
      if (raw == null) return [];
      if (raw is List) {
        return raw
            .where((e) => e != null && e['product_id'] != null)
            .map((e) => POSOrderItem.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
      return [];
    }

    return POSOrder(
      id: j['id'] as int,
      storeId: j['store_id'] as int,
      tableId: j['table_id'] as int?,
      tableName: j['table_name'] as String?,
      totalPrice: double.tryParse(j['total_price']?.toString() ?? '0') ?? 0,
      currency: j['currency'] as String? ?? '',
      status: j['status'] as String? ?? 'pending',
      kitchenStatus: j['kitchen_status'] as String? ?? 'pending',
      localPaymentMethod: j['local_payment_method'] as String?,
      localPaid: (j['local_paid'] as int? ?? 0) > 0,
      cashierNotes: j['cashier_notes'] as String?,
      items: parseItems(j['items']),
      createdAt: j['created_at'] != null
          ? DateTime.tryParse(j['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      kitchenUpdatedAt: j['kitchen_updated_at'] != null
          ? DateTime.tryParse(j['kitchen_updated_at'].toString())
          : null,
    );
  }

  bool get isPaid => localPaid;
  bool get isCancelled => status == 'cancelled';
  bool get isCompleted => status == 'completed' || status == 'delivered';
  bool get isActive => !isCancelled && !isCompleted && !localPaid;

  // An item is "new" if it was added after the kitchen last acted on this ticket
  // (started cooking, or marked delivered) — lets the kitchen screen tell
  // freshly-added items apart from ones it already started/served.
  bool isNewItem(POSOrderItem item) =>
      kitchenUpdatedAt != null &&
      item.createdAt != null &&
      item.createdAt!.isAfter(kitchenUpdatedAt!);

  POSOrder copyWith({String? kitchenStatus, bool? localPaid, String? localPaymentMethod, String? status, List<POSOrderItem>? items, double? totalPrice}) => POSOrder(
    id: id, storeId: storeId, tableId: tableId, tableName: tableName,
    currency: currency, cashierNotes: cashierNotes, createdAt: createdAt,
    kitchenUpdatedAt: kitchenUpdatedAt,
    totalPrice: totalPrice ?? this.totalPrice,
    status: status ?? this.status,
    kitchenStatus: kitchenStatus ?? this.kitchenStatus,
    localPaymentMethod: localPaymentMethod ?? this.localPaymentMethod,
    localPaid: localPaid ?? this.localPaid,
    items: items ?? this.items,
  );
}
