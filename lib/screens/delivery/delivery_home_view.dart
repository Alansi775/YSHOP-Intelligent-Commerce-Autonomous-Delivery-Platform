// lib/screens/delivery_home_view.dart
// ═══════════════════════════════════════════════════════════════════════════════
// 🚚 DELIVERY DRIVER HOME - Dashboard with Smart Order Offer System
// ═══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../../services/api_service.dart';
import '../../state_management/auth_manager.dart';
import '../auth/sign_in_view.dart';
import 'delivery_shared.dart' as ds;
import 'delivery_qr_scanner_view.dart';
import 'map_of_delivery_man.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  DESIGN CONSTANTS
// ─────────────────────────────────────────────────────────────────────────────

const Color kDarkBackground = Color(0xFF121212);
const Color kCardBackground = Color(0xFF1E1E1E);
const Color kAppBarBackground = Color(0xFF121212);
const Color kPrimaryTextColor = Color(0xFFEEEEEE);
const Color kSecondaryTextColor = Color(0xFFB0B0B0);
const Color kAccentBlue = Color(0xFF2979FF);
const Color kAccentGreen = Color(0xFF00E676);
const Color kAccentRed = Color(0xFFFF5252);
const Color kAccentOrange = Color(0xFFFF9800);
const Color kSeparatorColor = Color(0xFF333333);

final String MAPBOX_ACCESS_TOKEN = dotenv.env['MAPBOX_ACCESS_TOKEN'] ?? 'MAPBOX_TOKEN_PLACEHOLDER';

// ─────────────────────────────────────────────────────────────────────────────
// 🏠 DELIVERY HOME VIEW
// ─────────────────────────────────────────────────────────────────────────────

class DeliveryHomeView extends StatefulWidget {
  final String driverName;
  const DeliveryHomeView({super.key, required this.driverName});

  @override
  State<DeliveryHomeView> createState() => _DeliveryHomeViewState();
}

class _DeliveryHomeViewState extends State<DeliveryHomeView> with TickerProviderStateMixin {

  bool _isWorking = false;
  ds.DeliveryRequest? _driverProfile;
  LatLng? _currentLocation;
  StreamSubscription<Position>? _positionSub;
  Timer? _locationUpdateTimer;
  Timer? _orderCheckTimer;
  ds.Order? _activeOrder;
  bool _isOfferDialogShowing = false;
  bool _isOpenNavLoading = false;
  
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _loadDriverStatus();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _locationUpdateTimer?.cancel();
    _orderCheckTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  String? _getUserUid() {
    return Provider.of<AuthManager>(context, listen: false).userProfile?['uid'] as String?;
  }

  Future<void> _loadDriverStatus() async {
    final uid = _getUserUid();
    if (uid == null) {
      debugPrint('❌ [_loadDriverStatus] No UID found in profile');
      return;
    }
    
    debugPrint(' [_loadDriverStatus] Loading profile for UID: $uid');
    try {
      final drv = await ApiService.getDeliveryRequestByUid(uid);
      if (drv != null) {
        debugPrint(' [_loadDriverStatus] Got driver profile: ${drv['email']}, Status: ${drv['status']}');
        if (mounted) {
          setState(() {
            _driverProfile = ds.DeliveryRequest.fromMap(drv);
            _isWorking = _driverProfile!.isWorking;
            debugPrint('📋 [_loadDriverStatus] Profile loaded - Status: ${_driverProfile!.status}, Working: $_isWorking');
          });
        }
        await _checkForActiveOrder();
        if (_isWorking) {
          _startLocationTracking();
          _startOrderChecking();
        }
      } else {
        debugPrint('❌ [_loadDriverStatus] No driver profile found for UID: $uid');
      }
    } catch (e) {
      debugPrint('Failed to load driver status: $e');
    }
  }

  Future<void> _checkForActiveOrder() async {
    final uid = _getUserUid();
    if (uid == null) return;
    
    try {
      final activeOrder = await ApiService.getDriverActiveOrder(uid);
      if (mounted) {
        setState(() {
          _activeOrder = activeOrder != null ? ds.Order.fromJson(activeOrder) : null;
        });
      }
    } catch (e) {
      debugPrint('Error getting active order: $e');
    }
  }

  Future<void> _toggleWorkingStatus() async {
    final uid = _getUserUid();
    if (uid == null || _driverProfile?.status != "Approved") {
      _showSnackBar('Your account is not approved yet.', isError: true);
      return;
    }

    final newStatus = !_isWorking;
    HapticFeedback.mediumImpact();

    try {
      if (newStatus) {
        LocationPermission perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) {
          perm = await Geolocator.requestPermission();
        }
        if (perm == LocationPermission.deniedForever) {
          _showSnackBar('Location permission required', isError: true);
          return;
        }
        
        try {
          final pos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
          ).timeout(const Duration(seconds: 10));
          _currentLocation = LatLng(pos.latitude, pos.longitude);
          await ApiService.updateMyDeliveryLocation(pos.latitude, pos.longitude);
        } catch (e) {
          debugPrint('Could not get initial position: $e');
        }
      }

      await ApiService.updateDriverWorkingStatus(uid, newStatus);
      setState(() => _isWorking = newStatus);
      
      if (newStatus) {
        _startLocationTracking();
        _startOrderChecking();
        _showSnackBar('You are now online!', isError: false);
      } else {
        _stopAllTracking();
        _showSnackBar('You are now offline.', isError: false);
      }
    } catch (e) {
      _showSnackBar('Failed: $e', isError: true);
    }
  }

  void _startLocationTracking() {
    _positionSub?.cancel();
    _locationUpdateTimer?.cancel();
    
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 20,
      ),
    ).listen((pos) {
      if (mounted) {
        setState(() => _currentLocation = LatLng(pos.latitude, pos.longitude));
      }
    });
    
    // Update backend every 30 seconds (reduced to avoid rate limiting)
    _locationUpdateTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (_currentLocation != null && _isWorking) {
        try {
          await ApiService.updateMyDeliveryLocation(
            _currentLocation!.latitude,
            _currentLocation!.longitude,
          );
        } catch (e) {
          debugPrint('Failed to update location: $e');
        }
      }
    });
  }

  void _startOrderChecking() {
    _orderCheckTimer?.cancel();
    
    // Check every 15 seconds (balanced)
    _orderCheckTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      if (_activeOrder != null || !_isWorking || _isOfferDialogShowing) return;
      await _checkForNewOrders();
    });
    
    // Check immediately after 2 seconds
    Future.delayed(const Duration(seconds: 2), () {
      if (_activeOrder == null && _isWorking && !_isOfferDialogShowing) {
        _checkForNewOrders();
      }
    });
  }

  void _stopAllTracking() {
    _positionSub?.cancel();
    _locationUpdateTimer?.cancel();
    _orderCheckTimer?.cancel();
  }

  Future<void> _checkForNewOrders() async {
    if (_currentLocation == null || _activeOrder != null || _isOfferDialogShowing) return;
    
    final uid = _getUserUid();
    if (uid == null) return;

    try {
      final offerData = await ApiService.getOrderOfferForDriver(
        driverId: uid,
        latitude: _currentLocation!.latitude,
        longitude: _currentLocation!.longitude,
      );
      
      if (offerData != null && mounted && !_isOfferDialogShowing) {
        final offer = ds.OrderOffer.fromJson(offerData);
        debugPrint('🎁 Got offer: Order #${offer.orderId} from ${offer.storeName}, Currency: ${offer.currency ?? "NOT SET"}, Price: ${offer.totalPrice}');
        _showOrderOfferDialog(offer);
      }
    } catch (e) {
      debugPrint('Error getting offer: $e');
    }
  }

  void _showOrderOfferDialog(ds.OrderOffer offer) {
    if (_isOfferDialogShowing) return;
    _isOfferDialogShowing = true;
    HapticFeedback.heavyImpact();
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => OrderOfferDialog(
        offer: offer,
        driverLocation: _currentLocation,
        onAccept: (routeToStore, routeToCustomer, driverLocation) => _acceptOfferWithRoutes(offer, routeToStore, routeToCustomer, driverLocation),
        onSkip: () => _skipOffer(offer),
        onTimeout: () => _onOfferTimeout(offer),
      ),
    ).then((_) => _isOfferDialogShowing = false);
  }

  Future<void> _acceptOffer(ds.OrderOffer offer) async {
    final uid = _getUserUid();
    if (uid == null) return;

    Navigator.of(context).pop();
    _isOfferDialogShowing = false;
    HapticFeedback.heavyImpact();

    try {
      final result = await ApiService.acceptOrderOffer(orderId: offer.orderId, driverId: uid);
      
      if (result != null && result['success'] == true) {
        // Use getDriverActiveOrder instead of getOrderById
        final orderData = await ApiService.getDriverActiveOrder(uid);
        if (orderData != null && mounted) {
          final order = ds.Order.fromJson(orderData);
          setState(() => _activeOrder = order);
          _showSnackBar('Order accepted!', isError: false);
          _navigateToDeliveryMap(order);
        } else {
          // Fallback: create order from offer data
          setState(() {
            _activeOrder = ds.Order.fromOffer(offer);
          });
          _showSnackBar('Order accepted!', isError: false);
          if (_activeOrder != null) {
            _navigateToDeliveryMap(_activeOrder!);
          }
        }
      } else {
        _showSnackBar('Order taken by another driver', isError: true);
      }
    } catch (e) {
      _showSnackBar('Failed: $e', isError: true);
    }
  }

  Future<void> _acceptOfferWithRoutes(ds.OrderOffer offer, List<LatLng> routeToStore, List<LatLng> routeToCustomer, LatLng? driverLocation) async {
    final uid = _getUserUid();
    if (uid == null) return;

    Navigator.of(context).pop();
    _isOfferDialogShowing = false;
    HapticFeedback.heavyImpact();

    try {
      final result = await ApiService.acceptOrderOffer(orderId: offer.orderId, driverId: uid);

      if (result != null && result['success'] == true) {
        // Use getDriverActiveOrder to retrieve official order data
        final orderData = await ApiService.getDriverActiveOrder(uid);
        if (orderData != null && mounted) {
          final order = ds.Order.fromJson(orderData);
          setState(() => _activeOrder = order);
          _showSnackBar('Order accepted!', isError: false);
          // Navigate and supply precomputed route and driver location for instant display
          _navigateToDeliveryMap(order, initialDriverLocation: driverLocation, initialRoutePoints: routeToStore);
        } else {
          // Fallback: create order from offer data
          setState(() {
            _activeOrder = ds.Order.fromOffer(offer);
          });
          _showSnackBar('Order accepted!', isError: false);
          if (_activeOrder != null) {
            _navigateToDeliveryMap(_activeOrder!, initialDriverLocation: driverLocation, initialRoutePoints: routeToStore);
          }
        }
      } else {
        _showSnackBar('Order taken by another driver', isError: true);
      }
    } catch (e) {
      _showSnackBar('Failed: $e', isError: true);
    }
  }

  Future<void> _skipOffer(ds.OrderOffer offer) async {
    final uid = _getUserUid();
    if (uid == null) return;

    Navigator.of(context).pop();
    _isOfferDialogShowing = false;

    try {
      await ApiService.skipOrderOffer(orderId: offer.orderId, driverId: uid);
      _showSnackBar('Order skipped', isError: false);
    } catch (e) {
      debugPrint('Failed to skip: $e');
    }
  }

  void _onOfferTimeout(ds.OrderOffer offer) {
    Navigator.of(context).pop();
    _isOfferDialogShowing = false;
    _showSnackBar('Offer timed out', isError: false);
  }

  void _navigateToDeliveryMap(ds.Order order, {LatLng? initialDriverLocation, List<LatLng>? initialRoutePoints}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => DeliveryMapView(
          order: order,
          kDarkBackground: kDarkBackground,
          kCardBackground: kCardBackground,
          kAppBarBackground: kAppBarBackground,
          kPrimaryTextColor: kPrimaryTextColor,
          kSecondaryTextColor: kSecondaryTextColor,
          kSeparatorColor: kSeparatorColor,
          kAccentBlue: kAccentBlue,
          initialDriverLocation: initialDriverLocation,
          initialRoutePoints: initialRoutePoints,
        ),
      ),
    ).then((_) {
      setState(() => _activeOrder = null);
      _checkForActiveOrder();
    });
  }

  Future<List<LatLng>> _fetchRoutePoints(LatLng from, LatLng to) async {
    try {
      final url = Uri.parse(
        'https://api.mapbox.com/directions/v5/mapbox/driving/'
        '${from.longitude},${from.latitude};${to.longitude},${to.latitude}'
        '?geometries=geojson&overview=full&access_token=$MAPBOX_ACCESS_TOKEN'
      );
      final resp = await http.get(url).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final routes = data['routes'] as List?;
        if (routes != null && routes.isNotEmpty) {
          final route = routes[0];
          final coords = route['geometry']['coordinates'] as List;
          final points = coords.map<LatLng>((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())).toList();
          return points;
        }
      }
    } catch (e) {
      debugPrint('Route fetch error (home): $e');
    }
    return [];
  }

  Future<void> _openNavigationWithPreload(ds.Order order) async {
    if (_isOpenNavLoading) return;
    // If we have a current GPS fix, try to fetch routes quickly and pass them to the map.
    if (_currentLocation == null) {
      _navigateToDeliveryMap(order);
      return;
    }

    setState(() => _isOpenNavLoading = true);
    try {
      final storeLoc = LatLng(order.storeLatitude ?? 0, order.storeLongitude ?? 0);
      // fetch route from driver -> store
      final routeToStore = await _fetchRoutePoints(_currentLocation!, storeLoc);
      // optionally prefetch store -> customer as well (not forwarded currently)
      // final routeToCustomer = await _fetchRoutePoints(storeLoc, LatLng(order.locationLatitude, order.locationLongitude));

      if (routeToStore.isNotEmpty) {
        _navigateToDeliveryMap(order, initialDriverLocation: _currentLocation, initialRoutePoints: routeToStore);
      } else {
        _navigateToDeliveryMap(order);
      }
    } finally {
      if (mounted) setState(() => _isOpenNavLoading = false);
    }
  }

  void _logout() async {
    _stopAllTracking();
    
    final authManager = Provider.of<AuthManager>(context, listen: false);
    await authManager.signOut();
    
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const SignInView()),
        (route) => false,
      );
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? kAccentRed : kAccentGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isApproved = _driverProfile?.status == "Approved";
    debugPrint('🏗️ [build] Rendering - _driverProfile: ${_driverProfile != null ? "✓ LOADED" : "✗ NULL"}, status: ${_driverProfile?.status}, isApproved: $isApproved');

    return Scaffold(
      backgroundColor: kDarkBackground,
      appBar: AppBar(
        title: const Text('Dashboard', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: kAppBarBackground,
        foregroundColor: kPrimaryTextColor,
        elevation: 0,
        centerTitle: false,
        automaticallyImplyLeading: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: GestureDetector(
              onTap: () => _showProfileSheet(),
              child: CircleAvatar(
                radius: 20,
                backgroundColor: kCardBackground,
                child: Text(
                  _driverProfile?.name.isNotEmpty == true
                      ? _driverProfile!.name[0].toUpperCase()
                      : '?',
                  style: const TextStyle(color: kAccentBlue, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              children: [
                const SizedBox(height: 16),
                _buildWorkingToggle(isApproved),
                const SizedBox(height: 24),
                Expanded(child: _buildMainContent(isApproved)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWorkingToggle(bool isApproved) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          gradient: _isWorking 
              ? const LinearGradient(colors: [Color(0xFF00C853), Color(0xFF69F0AE)]) 
              : LinearGradient(colors: [Colors.grey.shade800, Colors.grey.shade700]),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: _isWorking ? Colors.green.withOpacity(0.3) : Colors.black12,
              blurRadius: 15,
              offset: const Offset(0, 5),
            )
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: isApproved ? _toggleWorkingStatus : null,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isWorking ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isWorking ? "You are Online" : "You are Offline",
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        Text(
                          _isWorking ? "Receiving orders..." : "Go online to work",
                          style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.8)),
                        ),
                      ],
                    ),
                  ),
                  Transform.scale(
                    scale: 0.8,
                    child: CupertinoSwitch(
                      value: _isWorking,
                      onChanged: isApproved ? (val) => _toggleWorkingStatus() : null,
                      activeColor: Colors.white,
                      trackColor: Colors.black26,
                      thumbColor: _isWorking ? const Color(0xFF00C853) : Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMainContent(bool isApproved) {
    debugPrint('🏠 [_buildMainContent] isApproved: $isApproved, _driverProfile: ${_driverProfile?.status}, _isWorking: $_isWorking');
    if (!isApproved) {
      debugPrint('❌ [_buildMainContent] Showing Pending Approval - profile not approved');
      return _buildEmptyState(Icons.hourglass_top_rounded, "Pending Approval", "Your application is under review.");
    }
    if (!_isWorking) {
      debugPrint('📴 [_buildMainContent] Showing Offline state');
      return _buildEmptyState(Icons.power_settings_new_rounded, "You are Offline", "Go online to receive orders.");
    }
    if (_activeOrder != null) {
      return _buildActiveOrderView();
    }
    return _buildWaitingView();
  }

  Widget _buildEmptyState(IconData icon, String title, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(color: kCardBackground, shape: BoxShape.circle),
              child: Icon(icon, size: 48, color: kSecondaryTextColor.withOpacity(0.5)),
            ),
            const SizedBox(height: 24),
            Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: kPrimaryTextColor)),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, color: kSecondaryTextColor)),
          ],
        ),
      ),
    );
  }

  Widget _buildWaitingView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ScaleTransition(
              scale: _pulseAnimation,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: kAccentBlue.withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: Border.all(color: kAccentBlue.withOpacity(0.3), width: 2),
                ),
                child: const Icon(Icons.delivery_dining, color: kAccentBlue, size: 48),
              ),
            ),
            const SizedBox(height: 24),
            const Text("Looking for orders nearby...", style: TextStyle(color: kPrimaryTextColor, fontSize: 18, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Text("Stay close to restaurants", style: TextStyle(color: kSecondaryTextColor.withOpacity(0.7), fontSize: 14)),
            if (_currentLocation != null) ...[
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(color: kCardBackground, borderRadius: BorderRadius.circular(20)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.location_on, color: kAccentGreen, size: 16),
                    const SizedBox(width: 8),
                    Text("GPS Active", style: TextStyle(color: kAccentGreen.withOpacity(0.9), fontSize: 13)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActiveOrderView() {
    final storeName = _activeOrder!.storeName.isNotEmpty 
        ? _activeOrder!.storeName 
        : (_activeOrder!.items.isNotEmpty ? _activeOrder!.items.first.storeName : 'Store');

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Active Delivery", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: kPrimaryTextColor)),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: _isOpenNavLoading ? null : () => _openNavigationWithPreload(_activeOrder!),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: kCardBackground,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kAccentBlue.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: kAccentBlue.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.delivery_dining, color: kAccentBlue),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(storeName, style: const TextStyle(color: kPrimaryTextColor, fontWeight: FontWeight.bold, fontSize: 16)),
                            Text("Order #${_activeOrder!.id}", style: const TextStyle(color: kSecondaryTextColor, fontSize: 13)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: kAccentGreen.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                        child: Text("${ds.getCurrencySymbol(_activeOrder!.currency ?? 'USD')}${_activeOrder!.total.toStringAsFixed(2)}", style: const TextStyle(color: kAccentGreen, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(children: [
                    const Icon(Icons.person, color: kSecondaryTextColor, size: 18),
                    const SizedBox(width: 8),
                    Text(_activeOrder!.userName, style: const TextStyle(color: kPrimaryTextColor)),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    const Icon(Icons.location_on, color: kSecondaryTextColor, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_activeOrder!.addressFull, style: const TextStyle(color: kSecondaryTextColor, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ]),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.orange.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.monetization_on_rounded, color: Colors.orange, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Your Earnings: ${ds.getCurrencySymbol(_activeOrder!.currency ?? 'USD')}${(_activeOrder!.total * 0.10).toStringAsFixed(2)}',
                          style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isOpenNavLoading ? null : () => _openNavigationWithPreload(_activeOrder!),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kAccentBlue,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: _isOpenNavLoading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.map, color: Colors.white),
                      label: _isOpenNavLoading ? const Text("Loading...", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)) : const Text("Open Navigation", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showProfileSheet() {
    if (_driverProfile == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: kDarkBackground,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24.0),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade800, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 24),
              CircleAvatar(
                radius: 40,
                backgroundColor: kAccentBlue.withOpacity(0.2),
                child: Text(_driverProfile!.name.isNotEmpty ? _driverProfile!.name[0].toUpperCase() : '?', style: const TextStyle(fontSize: 32, color: kAccentBlue)),
              ),
              const SizedBox(height: 16),
              Text(_driverProfile!.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: kPrimaryTextColor)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _driverProfile!.status == "Approved" ? kAccentGreen.withOpacity(0.15) : kAccentOrange.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(_driverProfile!.status.toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _driverProfile!.status == "Approved" ? kAccentGreen : kAccentOrange)),
              ),
              const SizedBox(height: 32),
              Row(children: [const Icon(Icons.email_outlined, color: kSecondaryTextColor, size: 20), const SizedBox(width: 16), Text(_driverProfile!.email, style: const TextStyle(color: kPrimaryTextColor, fontSize: 16))]),
              const SizedBox(height: 16),
              Row(children: [const Icon(Icons.phone_outlined, color: kSecondaryTextColor, size: 20), const SizedBox(width: 16), Text(_driverProfile!.phoneNumber, style: const TextStyle(color: kPrimaryTextColor, fontSize: 16))]),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _logout,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red.withOpacity(0.1), foregroundColor: Colors.red, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text("Log Out"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// 🎁 ORDER OFFER DIALOG
// ═══════════════════════════════════════════════════════════════════════════════

class OrderOfferDialog extends StatefulWidget {
  final ds.OrderOffer offer;
  final LatLng? driverLocation;
  final void Function(List<LatLng> routeToStore, List<LatLng> routeToCustomer, LatLng? driverLocation) onAccept;
  final VoidCallback onSkip;
  final VoidCallback onTimeout;

  const OrderOfferDialog({
    super.key,
    required this.offer,
    required this.driverLocation,
    required this.onAccept,
    required this.onSkip,
    required this.onTimeout,
  });

  @override
  State<OrderOfferDialog> createState() => _OrderOfferDialogState();
}

class _OrderOfferDialogState extends State<OrderOfferDialog> {
  late int _secondsRemaining;
  Timer? _countdownTimer;
  List<LatLng> _routeToStore = [];
  List<LatLng> _routeToCustomer = [];
  bool _showFullRoute = false;
  bool _isLoading = false;
  String _storeEta = '';
  String _customerEta = '';
  double _totalDistanceMeters = 0;

  @override
  void initState() {
    super.initState();
    _secondsRemaining = widget.offer.remainingSeconds.clamp(1, 120);
    debugPrint('💰 OrderOfferDialog - Currency: ${widget.offer.currency}, Total: ${widget.offer.totalPrice}');
    _startCountdown();
    _fetchRoutes();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() => _secondsRemaining--);
        if (_secondsRemaining <= 0) {
          timer.cancel();
          widget.onTimeout();
        }
      }
    });
  }

  Future<void> _fetchRoutes() async {
    if (widget.driverLocation == null) return;
    
    try {
      final storeRoute = await _fetchRoute(
        widget.driverLocation!,
        LatLng(widget.offer.storeLatitude, widget.offer.storeLongitude),
      );
      
      final customerRoute = await _fetchRoute(
        LatLng(widget.offer.storeLatitude, widget.offer.storeLongitude),
        LatLng(widget.offer.customerLatitude, widget.offer.customerLongitude),
      );
      
      if (mounted) {
        setState(() {
          _routeToStore = storeRoute['points'] ?? [];
          _storeEta = storeRoute['eta'] ?? '';
          _routeToCustomer = customerRoute['points'] ?? [];
          _customerEta = customerRoute['eta'] ?? '';
          _totalDistanceMeters = (storeRoute['distance'] ?? 0.0) + (customerRoute['distance'] ?? 0.0);
        });
      }
    } catch (e) {
      debugPrint('Failed to fetch routes: $e');
    }
  }

  Future<Map<String, dynamic>> _fetchRoute(LatLng from, LatLng to) async {
    try {
      final url = Uri.parse(
        'https://api.mapbox.com/directions/v5/mapbox/driving/'
        '${from.longitude},${from.latitude};${to.longitude},${to.latitude}'
        '?geometries=geojson&overview=full&access_token=$MAPBOX_ACCESS_TOKEN'
      );
      final resp = await http.get(url).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final routes = data['routes'] as List?;
        if (routes != null && routes.isNotEmpty) {
          final route = routes[0];
          final coords = route['geometry']['coordinates'] as List;
          final duration = (route['duration'] as num).toDouble();
          final distance = (route['distance'] as num).toDouble();
          final points = coords.map<LatLng>((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())).toList();
          return {'points': points, 'eta': _formatDuration(duration), 'distance': distance};
        }
      }
    } catch (e) {
      debugPrint('Route fetch error: $e');
    }
    return {};
  }

  String _formatDuration(double seconds) {
    final minutes = (seconds / 60).round();
    if (minutes < 1) return '< 1 min';
    return '$minutes min';
  }

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.toStringAsFixed(0)}m';
    return '${(meters / 1000).toStringAsFixed(1)}km';
  }

  @override
  Widget build(BuildContext context) {
    final progress = _secondsRemaining / 120;
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth > 600;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Container(
        width: isWide ? 500 : screenWidth,
        height: isWide ? screenHeight * 0.85 : screenHeight * 0.9,
        margin: EdgeInsets.symmetric(horizontal: isWide ? (screenWidth - 500) / 2 : 16, vertical: 32),
        decoration: BoxDecoration(color: kDarkBackground, borderRadius: BorderRadius.circular(24)),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(color: kCardBackground, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
              child: Row(
                children: [
                  SizedBox(
                    width: 56, height: 56,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircularProgressIndicator(
                          value: progress,
                          strokeWidth: 4,
                          backgroundColor: Colors.grey.shade800,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            _secondsRemaining > 30 ? kAccentGreen : _secondsRemaining > 10 ? kAccentOrange : kAccentRed,
                          ),
                        ),
                        Text('${_secondsRemaining}s', style: TextStyle(
                          color: _secondsRemaining > 30 ? kAccentGreen : _secondsRemaining > 10 ? kAccentOrange : kAccentRed,
                          fontWeight: FontWeight.bold, fontSize: 14,
                        )),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("New Delivery Request!", style: TextStyle(color: kPrimaryTextColor, fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(widget.offer.storeName, style: const TextStyle(color: kSecondaryTextColor, fontSize: 14)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            // Map
            Expanded(flex: 3, child: _buildMap()),
            
            // Route toggle
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _showFullRoute = !_showFullRoute),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                        decoration: BoxDecoration(
                          color: _showFullRoute ? kAccentBlue.withOpacity(0.2) : kCardBackground,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _showFullRoute ? kAccentBlue : kSeparatorColor),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(_showFullRoute ? Icons.route : Icons.store, color: _showFullRoute ? kAccentBlue : kSecondaryTextColor, size: 18),
                            const SizedBox(width: 8),
                            Text(_showFullRoute ? "Full Route" : "To Store Only", style: TextStyle(color: _showFullRoute ? kAccentBlue : kSecondaryTextColor, fontWeight: FontWeight.w500, fontSize: 13)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    decoration: BoxDecoration(color: kCardBackground, borderRadius: BorderRadius.circular(10)),
                    child: Row(
                      children: [
                        const Icon(Icons.access_time, color: kAccentGreen, size: 16),
                        const SizedBox(width: 6),
                        Text(_showFullRoute ? "$_storeEta + $_customerEta" : _storeEta.isEmpty ? "..." : _storeEta, style: const TextStyle(color: kPrimaryTextColor, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            // Order info
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildInfoChip(Icons.attach_money, "${ds.getCurrencySymbol(widget.offer.currency)}${widget.offer.totalPrice.toStringAsFixed(2)}", "Order"),
                  _buildInfoChip(Icons.route, _totalDistanceMeters > 0 ? _formatDistance(_totalDistanceMeters) : widget.offer.formattedDistance, "Distance"),
                  _buildInfoChip(Icons.monetization_on, "${ds.getCurrencySymbol(widget.offer.currency)}${widget.offer.estimatedEarnings.toStringAsFixed(2)}", "Earn"),
                ],
              ),
            ),
            
            // Buttons
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: widget.onSkip,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: kAccentRed),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text("Skip", style: TextStyle(color: kAccentRed, fontWeight: FontWeight.bold, fontSize: 15)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : () {
                        setState(() => _isLoading = true);
                        widget.onAccept(_routeToStore, _routeToCustomer, widget.driverLocation);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kAccentGreen,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isLoading
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text("Accept Order", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMap() {
    final storeLocation = LatLng(widget.offer.storeLatitude, widget.offer.storeLongitude);
    final customerLocation = LatLng(widget.offer.customerLatitude, widget.offer.customerLongitude);
    final center = widget.driverLocation ?? storeLocation;

    return FlutterMap(
      options: MapOptions(initialCenter: center, initialZoom: 13),
      children: [
        TileLayer(
          urlTemplate: 'https://api.mapbox.com/styles/v1/mapbox/dark-v11/tiles/{z}/{x}/{y}?access_token=$MAPBOX_ACCESS_TOKEN',
          userAgentPackageName: 'com.yshop.delivery',
        ),
        if (_routeToStore.isNotEmpty)
          PolylineLayer(polylines: [Polyline(points: _routeToStore, color: Colors.white, strokeWidth: 4) as Polyline<Object>]),
        if (_showFullRoute && _routeToCustomer.isNotEmpty)
          PolylineLayer(polylines: [Polyline(points: _routeToCustomer, color: kAccentGreen.withOpacity(0.7), strokeWidth: 4) as Polyline<Object>]),
        MarkerLayer(
          markers: [
            Marker(
              point: storeLocation, width: 44, height: 44,
              child: Container(
                decoration: BoxDecoration(color: kAccentOrange, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                child: const Icon(Icons.store, color: Colors.white, size: 22),
              ),
            ),
            if (_showFullRoute)
              Marker(
                point: customerLocation, width: 44, height: 44,
                child: Container(
                  decoration: BoxDecoration(color: kAccentGreen, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                  child: const Icon(Icons.person_pin, color: Colors.white, size: 22),
                ),
              ),
            if (widget.driverLocation != null)
              Marker(
                point: widget.driverLocation!, width: 44, height: 44,
                child: Container(
                  decoration: BoxDecoration(color: kAccentBlue, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                  child: const Icon(Icons.navigation, color: Colors.white, size: 22),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildInfoChip(IconData icon, String value, String label) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: kCardBackground, borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: kAccentBlue, size: 20),
        ),
        const SizedBox(height: 6),
        Text(value, style: const TextStyle(color: kPrimaryTextColor, fontWeight: FontWeight.bold, fontSize: 14)),
        Text(label, style: const TextStyle(color: kSecondaryTextColor, fontSize: 10)),
      ],
    );
  }
}