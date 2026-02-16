import 'dart:async';
import 'package:flutter/material.dart';
import 'reactive_sync_service.dart';

/// 🔥 Reactive Sync Mixin
/// 
/// Add to any StatefulWidget to enable real-time data syncing
/// 
/// Usage:
/// ```dart
/// class MyView extends StatefulWidget {
///   @override
///   State<MyView> createState() => _MyViewState();
/// }
/// 
/// class _MyViewState extends State<MyView> with ReactiveSyncMixin {
///   @override
///   String get reactiveChannel => 'orders:502';
///   
///   @override
///   void onReactiveUpdate(Map<String, dynamic> update) {
///     setState(() {
///       _orders = update['data'] as List<dynamic>;
///     });
///   }
/// }
/// ```

mixin ReactiveSyncMixin<T extends StatefulWidget> on State<T> {
  late StreamSubscription<Map<String, dynamic>> _reactiveSubscription;
  
  /// Override this to return the channel name
  /// Examples: 'returns:502', 'orders:502', 'customer:orders:123'
  String get reactiveChannel;
  
  /// Override this to handle reactive updates
  void onReactiveUpdate(Map<String, dynamic> update);
  
  /// Optional: Called when reactive sync connects
  void onReactiveSyncConnected() {}
  
  /// Optional: Called on error
  void onReactiveSyncError(String error) {}

  @override
  void initState() {
    super.initState();
    _initializeReactiveSync();
  }

  /// Initialize reactive sync listener
  Future<void> _initializeReactiveSync() async {
    try {
      // Initialize Socket.io (first time only)
      if (!reactiveSyncService.isConnected) {
        reactiveSyncService.initialize(serverUrl: 'http://localhost:3000');
        await Future.delayed(const Duration(milliseconds: 500));
      }

      // Subscribe to channel
      reactiveSyncService.subscribe(reactiveChannel);
      debugPrint('🔥 REACTIVE SYNC: Subscribed to $reactiveChannel');
      
      onReactiveSyncConnected();

      // Listen to updates
      _reactiveSubscription =
          reactiveSyncService.dataStream.listen((update) {
        final channel = update['channel'] as String?;
        
        if (channel == reactiveChannel && mounted) {
          debugPrint('✨ REACTIVE UPDATE on $reactiveChannel: ${update['count']} items');
          onReactiveUpdate(update);
        }
      }, onError: (error) {
        debugPrint('❌ Reactive sync error: $error');
        onReactiveSyncError(error.toString());
      });
    } catch (e) {
      debugPrint('❌ Reactive sync init error: $e');
      onReactiveSyncError(e.toString());
    }
  }

  @override
  void dispose() {
    // ⚠️ IMPORTANT: DO NOT unsubscribe here!
    // The subscription should persist across widget rebuilds and navigation
    // Only close the stream listener, not the server subscription
    _reactiveSubscription.cancel();
    
    // Keep the server subscription active - it will be cleaned up when app closes
    // This allows smooth navigation without re-subscribing delays
    
    super.dispose();
  }
}
