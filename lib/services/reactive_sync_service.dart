import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter/material.dart';

/// 🔥 Reactive Sync Service
/// 
/// Real-time data synchronization using Socket.io
/// - Subscribe to specific data channels (e.g., 'returns:502')
/// - Receive instant delta updates when database changes
/// - Event-driven architecture (NO POLLING!)
/// - Targeted updates only to subscribed clients

class ReactiveSyncService extends ChangeNotifier {
  static final ReactiveSyncService _instance = ReactiveSyncService._internal();

  factory ReactiveSyncService() {
    return _instance;
  }

  ReactiveSyncService._internal();

  late IO.Socket socket;
  bool _isConnected = false;
  final Set<String> _subscribedChannels = {};
  final Map<String, dynamic> _latestData = {};
  final StreamController<Map<String, dynamic>> _dataStreamController =
      StreamController<Map<String, dynamic>>.broadcast();

  // 📊 Stats
  int _messageCount = 0;
  int _subscriberCount = 0;

  // Getters
  bool get isConnected => _isConnected;
  Stream<Map<String, dynamic>> get dataStream => _dataStreamController.stream;
  int get messageCount => _messageCount;
  int get subscriberCount => _subscriberCount;

  /// 🔗 Initialize Socket.io connection
  void initialize({required String serverUrl}) {
    try {
      debugPrint('🔌 SOCKET.IO: Initializing connection to $serverUrl');

      socket = IO.io(
        serverUrl,
        IO.OptionBuilder()
            .setTransports(['websocket', 'polling'])
            .enableAutoConnect()
            .enableForceNew()
            .setReconnectionDelay(1000)
            .setReconnectionDelayMax(5000)
            .setReconnectionAttempts(10)
            .build(),
      );

      //  Connected
      socket.onConnect((_) {
        _isConnected = true;
        debugPrint(' SOCKET.IO: Connected');
        notifyListeners();
      });

      // 🔌 Disconnected
      socket.onDisconnect((_) {
        _isConnected = false;
        debugPrint('🔌 SOCKET.IO: Disconnected');
        notifyListeners();
      });

      // 📡 Receive delta updates
      socket.on('data:delta', (data) {
        _handleDeltaUpdate(data);
      });

      // 📊 Receive stats
      socket.on('stats', (stats) {
        debugPrint('📊 SOCKET.IO STATS: $stats');
        _subscriberCount = stats['totalSubscribers'] ?? 0;
        notifyListeners();
      });

      // ❌ Error handling
      socket.onError((error) {
        debugPrint('❌ SOCKET.IO ERROR: $error');
      });

      socket.connect();
    } catch (e) {
      debugPrint('❌ SOCKET.IO INIT ERROR: $e');
    }
  }

  /// 📡 Subscribe to a data channel
  /// Example: subscribe('returns:502') → Get all returns for store 502
  void subscribe(String channel) {
    if (_subscribedChannels.contains(channel)) {
      debugPrint('⚠️ Already subscribed to $channel');
      return;
    }

    if (!_isConnected) {
      debugPrint('⚠️ Socket not connected. Retrying subscription...');
      Future.delayed(const Duration(seconds: 1), () => subscribe(channel));
      return;
    }

    _subscribedChannels.add(channel);
    socket.emit('subscribe', channel);
    debugPrint(' SUBSCRIBED to: $channel');
    notifyListeners();
  }

  /// ❌ Unsubscribe from a channel
  void unsubscribe(String channel) {
    if (!_subscribedChannels.contains(channel)) return;

    _subscribedChannels.remove(channel);
    socket.emit('unsubscribe', channel);
    _latestData.remove(channel);
    debugPrint('❌ UNSUBSCRIBED from: $channel');
    notifyListeners();
  }

  /// 📥 Handle incoming delta updates
  void _handleDeltaUpdate(dynamic data) {
    try {
      final Map<String, dynamic> updateData = data is String
          ? {'raw': data}
          : Map<String, dynamic>.from(data as Map);

      final channel = updateData['channel'] as String?;
      final updatesList =
          (updateData['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];

      if (channel != null) {
        _latestData[channel] = updatesList;
        _messageCount++;

        debugPrint(
            ' DELTA UPDATE: $channel - ${updatesList.length} items (Total: $_messageCount)');

        // Emit to listeners
        _dataStreamController.add({
          'channel': channel,
          'data': updatesList,
          'count': updatesList.length,
          'timestamp': DateTime.now(),
        });

        notifyListeners();
      }
    } catch (e) {
      debugPrint('❌ ERROR HANDLING DELTA UPDATE: $e');
    }
  }

  ///  Get latest data for a channel
  List<dynamic> getChannelData(String channel) {
    return _latestData[channel] ?? [];
  }

  ///  Request stats from server
  void requestStats() {
    socket.emit('get-stats');
  }

  /// 🧹 Cleanup
  @override
  void dispose() {
    unsubscribeAll();
    _dataStreamController.close();
    socket.dispose();
    super.dispose();
  }

  /// ❌ Unsubscribe from all channels
  void unsubscribeAll() {
    for (final channel in _subscribedChannels.toList()) {
      unsubscribe(channel);
    }
  }

  /// 📊 Get connection info
  Map<String, dynamic> getInfo() {
    return {
      'connected': _isConnected,
      'subscribed_channels': _subscribedChannels.toList(),
      'message_count': _messageCount,
      'latest_data': _latestData,
    };
  }
}

// 🏭 Global instance
final reactiveSyncService = ReactiveSyncService();
