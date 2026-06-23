import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Android equivalent of iOS Live Activity — a persistent notification
/// that tracks order status in real-time, matching the iOS design language.
///
/// Shows:
///   • Step progress track (Placed → Prep → On Way → Done)
///   • Status title with emoji
///   • Store name + price + order ID
///   • Status-tinted color bar
///
/// Lifecycle mirrors iOS:
///   startTracking()  → creates the notification when order is placed
///   updateStatus()   → updates in place when socket/poll fires
///   dismissNotification() → removes when delivered/cancelled
class OrderNotificationService {
  static final OrderNotificationService _instance =
      OrderNotificationService._internal();
  factory OrderNotificationService() => _instance;
  OrderNotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const int _notificationId = 9001;
  static const String _channelId = 'yshop_order_tracking';
  static const String _channelName = 'Order Tracking';
  static const String _channelDesc = 'Live order status updates from YShop';

  bool _initialized = false;
  String? _activeOrderId;
  String? _lastStatus;

  // ─── Init ────────────────────────────────────────────────────────────────

  Future<void> init() async {
    if (_initialized) return;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(const InitializationSettings(android: androidInit));

    // Low-importance channel — no sound/vibration on each update
    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.low,
      showBadge: false,
      playSound: false,
      enableVibration: false,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    _initialized = true;
    debugPrint('[OrderNotif] 🔔 Initialized');
  }

  Future<void> requestPermission() async {
    // Required for Android 13+
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  // ─── Public API ──────────────────────────────────────────────────────────

  Future<void> startTracking({
    required String orderId,
    required String storeName,
    required String status,
    required double totalPrice,
    required String currency,
  }) async {
    if (!_initialized) await init();
    if (!_isTrackable(status)) return;

    _activeOrderId = orderId;
    _lastStatus = status;
    await _show(
      orderId: orderId,
      storeName: storeName,
      status: status,
      totalPrice: totalPrice,
      currency: currency,
    );
    debugPrint('[OrderNotif] 🟢 Started tracking order $orderId ($status)');
  }

  Future<void> updateStatus({
    required String orderId,
    required String storeName,
    required String status,
    required double totalPrice,
    required String currency,
  }) async {
    if (!_initialized) return;
    if (_activeOrderId != orderId) {
      // New order that we weren't tracking yet — start now
      if (_isTrackable(status)) {
        await startTracking(
          orderId: orderId,
          storeName: storeName,
          status: status,
          totalPrice: totalPrice,
          currency: currency,
        );
      }
      return;
    }

    if (_lastStatus == status) return; // no change
    _lastStatus = status;

    if (_isTerminal(status)) {
      // Show a brief final notification then dismiss
      await _showFinal(orderId: orderId, storeName: storeName, status: status);
      await Future.delayed(const Duration(seconds: 5));
      await dismissNotification();
      return;
    }

    if (!_isTrackable(status)) {
      await dismissNotification();
      return;
    }

    await _show(
      orderId: orderId,
      storeName: storeName,
      status: status,
      totalPrice: totalPrice,
      currency: currency,
    );
    debugPrint('[OrderNotif] 🔄 Updated order $orderId → $status');
  }

  Future<void> dismissNotification() async {
    if (_activeOrderId == null) return; // nothing active — skip silently
    await _plugin.cancel(_notificationId);
    _activeOrderId = null;
    _lastStatus = null;
    debugPrint('[OrderNotif] ✅ Notification dismissed');
  }

  // ─── Notification builder ─────────────────────────────────────────────────

  Future<void> _show({
    required String orderId,
    required String storeName,
    required String status,
    required double totalPrice,
    required String currency,
  }) async {
    final norm = _normalize(status);
    final step = _step(norm);
    final title = _title(norm);
    final emoji = _emoji(norm);
    final color = _color(norm);
    final currSym = _currencySymbol(currency);

    // Progress track — matches iOS step track visual language
    final progressLine = _progressLine(step);
    final labelsLine = _labelsLine(step);

    final bigBody = '$progressLine\n$labelsLine\n\n'
        '$storeName  ·  $currSym${totalPrice.toStringAsFixed(0)} $currency  ·  #$orderId';

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,          // persistent — cannot be swiped away
      autoCancel: false,
      colorized: true,
      color: color,
      showWhen: false,
      playSound: false,
      enableVibration: false,
      category: AndroidNotificationCategory.status,
      styleInformation: BigTextStyleInformation(
        bigBody,
        contentTitle: '$emoji  $title',
        summaryText: storeName,
        htmlFormatBigText: false,
        htmlFormatContentTitle: false,
      ),
    );

    await _plugin.show(
      _notificationId,
      '$emoji  $title',
      '$storeName  ·  Order #$orderId',
      NotificationDetails(android: androidDetails),
    );
  }

  // Delivered / Cancelled — auto-dismissing, not ongoing
  Future<void> _showFinal({
    required String orderId,
    required String storeName,
    required String status,
  }) async {
    final norm = _normalize(status);
    final title = _title(norm);
    final emoji = _emoji(norm);
    final color = _color(norm);

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      ongoing: false,
      autoCancel: true,
      colorized: true,
      color: color,
      showWhen: true,
      playSound: true,
      category: AndroidNotificationCategory.status,
    );

    await _plugin.show(
      _notificationId,
      '$emoji  $title',
      storeName,
      NotificationDetails(android: androidDetails),
    );
  }

  // ─── Progress track ───────────────────────────────────────────────────────

  // Draws:  ⬤ ━━━ ⬤ ─── ○ ─── ○
  String _progressLine(int step) {
    const f = '⬤';   // filled dot
    const e = '○';   // empty dot
    const fl = '━━━'; // filled segment
    const el = '───'; // empty segment

    final dots = List.generate(4, (i) => i < step ? f : e);
    final segs = List.generate(3, (i) => i < step - 1 ? fl : el);

    return '${dots[0]} ${segs[0]} ${dots[1]} ${segs[1]} ${dots[2]} ${segs[2]} ${dots[3]}';
  }

  // Draws:  Placed  •  Prep  •  On Way  •  Done
  String _labelsLine(int step) {
    const names = ['Placed', 'Prep', 'On Way', 'Done'];
    return names.asMap().entries.map((e) {
      final isCurrent = (e.key + 1) == step;
      return isCurrent ? '[${e.value}]' : e.value;
    }).join('  •  ');
  }

  // ─── Status mappings ──────────────────────────────────────────────────────

  String _normalize(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'pending':           return 'Pending';
      case 'confirmed':
      case 'processing':        return 'Processing';
      case 'shipped':
      case 'out for delivery':
      case 'out_for_delivery':  return 'Out for Delivery';
      case 'delivered':         return 'Delivered';
      case 'cancelled':         return 'Cancelled';
      case 'return':            return 'Return Pending';
      default:                  return raw;
    }
  }

  bool _isTrackable(String status) {
    final s = status.toLowerCase();
    return s != 'delivered' && s != 'cancelled';
  }

  bool _isTerminal(String status) {
    final s = status.toLowerCase();
    return s == 'delivered' || s == 'cancelled';
  }

  int _step(String norm) {
    switch (norm) {
      case 'Pending':           return 1;
      case 'Processing':        return 2;
      case 'Out for Delivery':  return 3;
      case 'Delivered':         return 4;
      default:                  return 1;
    }
  }

  String _title(String norm) {
    switch (norm) {
      case 'Pending':           return 'Order Placed';
      case 'Processing':        return 'Being Prepared';
      case 'Out for Delivery':  return 'On the Way';
      case 'Delivered':         return 'Order Delivered!';
      case 'Cancelled':         return 'Order Cancelled';
      case 'Return Pending':    return 'Return Requested';
      default:                  return 'Order Update';
    }
  }

  String _emoji(String norm) {
    switch (norm) {
      case 'Pending':           return '🕐';
      case 'Processing':        return '👨‍🍳';
      case 'Out for Delivery':  return '🛵';
      case 'Delivered':         return '🎉';
      case 'Cancelled':         return '❌';
      case 'Return Pending':    return '↩️';
      default:                  return '📦';
    }
  }

  // Colors match the existing Flutter app status colors
  Color _color(String norm) {
    switch (norm) {
      case 'Pending':           return const Color(0xFFFF9F1C); // amber
      case 'Processing':        return const Color(0xFF3B82F6); // blue
      case 'Out for Delivery':  return const Color(0xFF22C55E); // green
      case 'Delivered':         return const Color(0xFF22C55E); // green
      case 'Cancelled':         return const Color(0xFFEF4444); // red
      case 'Return Pending':    return const Color(0xFFF59E0B); // amber
      default:                  return const Color(0xFF3B82F6);
    }
  }

  String _currencySymbol(String code) {
    switch (code.toUpperCase()) {
      case 'YER': return 'ر.ي ';
      case 'SAR': return 'ر.س ';
      case 'AED': return 'د.إ ';
      case 'USD': return '\$';
      case 'EUR': return '€';
      case 'TRY': return '₺';
      case 'GBP': return '£';
      case 'INR': return '₹';
      case 'CNY': return '¥';
      default:    return '$code ';
    }
  }
}

// Global singleton — import this anywhere
final orderNotificationService = OrderNotificationService();
