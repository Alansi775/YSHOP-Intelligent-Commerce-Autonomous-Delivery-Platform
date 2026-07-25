// pos_service.dart — Local POS System API + WebSocket service

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as sio;
import '../config/api_config.dart';
import '../models/pos_models.dart';
import 'api_service.dart';

class POSService {
  static final POSService _instance = POSService._internal();
  factory POSService() => _instance;
  POSService._internal();

  sio.Socket? _socket;
  int? _joinedStoreId;

  // Stream controllers for real-time updates
  final _orderStreamCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _tableStreamCtrl = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get orderStream => _orderStreamCtrl.stream;
  Stream<Map<String, dynamic>> get tableStream => _tableStreamCtrl.stream;

  // ── WebSocket ────────────────────────────────────────────────────────────────

  void joinStoreRoom(int storeId) {
    final socket = _getSocket();
    if (_joinedStoreId != null && _joinedStoreId != storeId) {
      socket.emit('pos:leave', _joinedStoreId);
    }
    _joinedStoreId = storeId;
    // Always emit join — onConnect also does this on reconnect
    if (socket.connected) socket.emit('pos:join', storeId);
    debugPrint('[POS] joinStoreRoom pos:$storeId (connected=${socket.connected})');
  }

  void leaveStoreRoom() {
    if (_joinedStoreId != null) {
      _socket?.emit('pos:leave', _joinedStoreId);
      _joinedStoreId = null;
    }
  }

  sio.Socket _getSocket() {
    if (_socket != null) {
      // Already have a socket — reconnect if dropped, don't recreate
      if (!_socket!.connected) _socket!.connect();
      return _socket!;
    }

    final baseHost = ApiConfig.baseHost;
    _socket = sio.io(baseHost, sio.OptionBuilder()
      .setTransports(['websocket'])
      .disableAutoConnect()
      .enableReconnection()
      .setReconnectionAttempts(99999)
      .setReconnectionDelay(500)        // first retry after 500ms
      .setReconnectionDelayMax(3000)    // never wait more than 3 seconds
      .build());

    _socket!.onConnect((_) {
      debugPrint('[POS] Socket connected: ${_socket!.id}');
      // Always re-join room on connect (covers first connect + every reconnect)
      if (_joinedStoreId != null) _socket!.emit('pos:join', _joinedStoreId);
    });

    _socket!.onDisconnect((_) => debugPrint('[POS] Socket disconnected — reconnecting...'));
    _socket!.onConnectError((e) => debugPrint('[POS] Connect error: $e'));

    _socket!.on('pos:order_new', (data) {
      _orderStreamCtrl.add({'event': 'new', ...Map<String, dynamic>.from(data)});
    });
    _socket!.on('pos:order_updated', (data) {
      _orderStreamCtrl.add({'event': 'updated', ...Map<String, dynamic>.from(data)});
    });
    _socket!.on('pos:table_updated', (data) {
      _tableStreamCtrl.add(Map<String, dynamic>.from(data));
    });

    _socket!.connect();
    return _socket!;
  }

  void dispose() {
    leaveStoreRoom();
    _socket?.disconnect();
    _socket = null;
    _orderStreamCtrl.close();
    _tableStreamCtrl.close();
  }

  // ── Tables ────────────────────────────────────────────────────────────────────

  Future<List<POSTable>> getTables(int storeId) async {
    final res = await ApiService.getRequest('/pos/tables?storeId=$storeId');
    return (res['tables'] as List).map((e) => POSTable.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<POSTable> createTable(int storeId, String name, {int capacity = 4}) async {
    final res = await ApiService.postRequest('/pos/tables', {
      'storeId': storeId, 'name': name, 'capacity': capacity,
    });
    return POSTable.fromJson(Map<String, dynamic>.from(res['table']));
  }

  Future<POSTable> updateTable(int tableId, {String? name, int? capacity, String? status}) async {
    final res = await ApiService.putRequest('/pos/tables/$tableId', {
      if (name != null) 'name': name,
      if (capacity != null) 'capacity': capacity,
      if (status != null) 'status': status,
    });
    return POSTable.fromJson(Map<String, dynamic>.from(res['table']));
  }

  Future<void> deleteTable(int tableId) async {
    await ApiService.deleteRequest('/pos/tables/$tableId');
  }

  // QR URL for a table — embeds the customer tracking page URL
  String tableQrUrl(POSTable table) {
    final base = ApiConfig.baseHost;
    return '$base/pos/track/${table.qrToken}';
  }

  // ── Orders ────────────────────────────────────────────────────────────────────

  Future<POSOrder> createOrder({
    required int storeId,
    int? tableId,
    required List<POSOrderItem> items,
    String? cashierNotes,
    String? paymentMethod,
  }) async {
    final res = await ApiService.postRequest('/pos/orders', {
      'storeId': storeId,
      if (tableId != null) 'tableId': tableId,
      'items': items.map((e) => e.toJson()).toList(),
      if (cashierNotes != null) 'cashierNotes': cashierNotes,
      if (paymentMethod != null) 'paymentMethod': paymentMethod,
    });
    return POSOrder.fromJson(Map<String, dynamic>.from(res['order']));
  }

  Future<List<POSOrder>> getOrders(int storeId, {String? date, bool activeOnly = false}) async {
    String q = '/pos/orders?storeId=$storeId';
    if (date != null) q += '&date=$date';
    if (activeOnly) q += '&status=active';
    final res = await ApiService.getRequest(q);
    return (res['orders'] as List)
        .map((e) => POSOrder.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<POSOrder> getOrder(int orderId) async {
    final res = await ApiService.getRequest('/pos/orders/$orderId');
    return POSOrder.fromJson(Map<String, dynamic>.from(res['order']));
  }

  Future<POSOrder> updateOrderItems(int orderId, List<POSOrderItem> items) async {
    final res = await ApiService.putRequest('/pos/orders/$orderId/items', {
      'items': items.map((e) => e.toJson()).toList(),
    });
    return POSOrder.fromJson(Map<String, dynamic>.from(res['order']));
  }

  Future<POSOrder> updateKitchenStatus(int orderId, String status) async {
    final res = await ApiService.putRequest('/pos/orders/$orderId/kitchen-status', {'status': status});
    return POSOrder.fromJson(Map<String, dynamic>.from(res['order']));
  }

  Future<POSOrder> processPayment(int orderId, String paymentMethod) async {
    final res = await ApiService.putRequest('/pos/orders/$orderId/payment', {'paymentMethod': paymentMethod});
    return POSOrder.fromJson(Map<String, dynamic>.from(res['order']));
  }

  Future<void> cancelOrder(int orderId) async {
    await ApiService.deleteRequest('/pos/orders/$orderId');
  }

  // Returns the URL for the invoice HTML page (open in browser or WebView)
  String invoiceUrl(int orderId) {
    return '${ApiConfig.baseUrl}/pos/orders/$orderId/invoice';
  }

  // ── Kitchen ───────────────────────────────────────────────────────────────────

  Future<List<POSOrder>> getKitchenOrders(int storeId) async {
    final res = await ApiService.getRequest('/pos/kitchen?storeId=$storeId');
    return (res['orders'] as List)
        .map((e) => POSOrder.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  // ── Analytics ────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getAnalytics(int storeId, {String? from, String? to}) async {
    String q = '/pos/analytics?storeId=$storeId';
    if (from != null) q += '&from=$from';
    if (to != null) q += '&to=$to';
    return Map<String, dynamic>.from(await ApiService.getRequest(q));
  }
}
