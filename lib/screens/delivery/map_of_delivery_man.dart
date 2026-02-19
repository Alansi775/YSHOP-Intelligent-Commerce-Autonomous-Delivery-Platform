// lib/screens/map_of_delivery_man.dart
// ═══════════════════════════════════════════════════════════════════════════════
// 🗺️ DELIVERY MAP VIEW - Navigation for Driver
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../../services/api_service.dart';
import 'delivery_shared.dart' as ds;
import 'delivery_qr_scanner_view.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  CONSTANTS
// ─────────────────────────────────────────────────────────────────────────────

final String MAPBOX_ACCESS_TOKEN = dotenv.env['MAPBOX_ACCESS_TOKEN'] ?? 'MAPBOX_TOKEN_PLACEHOLDER';
const double ARRIVAL_THRESHOLD_METERS = 100.0;

// ─────────────────────────────────────────────────────────────────────────────
// 🚚 DELIVERY MAP VIEW
// ─────────────────────────────────────────────────────────────────────────────

class DeliveryMapView extends StatefulWidget {
  final ds.Order order;
  final Color kDarkBackground;
  final Color kCardBackground;
  final Color kAppBarBackground;
  final Color kPrimaryTextColor;
  final Color kSecondaryTextColor;
  final Color kSeparatorColor;
  final Color kAccentBlue;
  final List<LatLng>? initialRoutePoints;
  final LatLng? initialDriverLocation;
  final Stream<LatLng>? externalDriverLocationStream;
  final Duration routeRefreshInterval;

  const DeliveryMapView({
    super.key,
    required this.order,
    required this.kDarkBackground,
    required this.kCardBackground,
    required this.kAppBarBackground,
    required this.kPrimaryTextColor,
    required this.kSecondaryTextColor,
    required this.kSeparatorColor,
    required this.kAccentBlue,
    this.initialRoutePoints,
    this.initialDriverLocation,
    this.externalDriverLocationStream,
    this.routeRefreshInterval = const Duration(seconds: 60),
  });

  @override
  State<DeliveryMapView> createState() => _DeliveryMapViewState();
}

class _DeliveryMapViewState extends State<DeliveryMapView> with WidgetsBindingObserver {
  final MapController _mapController = MapController();
  
  LatLng? _driverLocation;
  late LatLng _storeLocation;
  late LatLng _customerLocation;
  
  List<LatLng> _routePoints = [];
  String _eta = '...';
  double _distanceRemaining = 0;
  
  DeliveryPhase _phase = DeliveryPhase.goingToStore;
  bool _hasShownArrivalDialog = false;
  bool _isMapReady = false;
  bool _isFollowingDriver = false;
  bool _hasShownDrivingTip = false;
  bool _isAtStore = false;
  String _mapStyle = 'dark';
  
  StreamSubscription<Position>? _positionSub;
  Timer? _locationUpdateTimer;
  Timer? _routeRefreshTimer;
  DateTime _lastRouteFetch = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initLocations();
    // If caller provided initial driver location or route points (from offer dialog), use them
    if (widget.initialDriverLocation != null) {
      _driverLocation = widget.initialDriverLocation;
    }
    if (widget.initialRoutePoints != null && widget.initialRoutePoints!.isNotEmpty) {
      _routePoints = widget.initialRoutePoints!;
      _isMapReady = true;
      _lastRouteFetch = DateTime.now();
      // compute quick distance & ETA from provided polyline so header shows immediately
      try {
        final distCalc = const Distance();
        double meters = 0.0;
        for (var i = 0; i < _routePoints.length - 1; i++) {
          meters += distCalc.as(LengthUnit.Meter, _routePoints[i], _routePoints[i + 1]);
        }
        _distanceRemaining = meters;
        // approximate travel speed: 10 m/s (~36 km/h) for ETA estimate
        final approxSeconds = meters / 10.0;
        _eta = _formatDuration(approxSeconds);
      } catch (e) {
        debugPrint('Failed to compute quick ETA: $e');
      }

      // center map if we have driver location, otherwise center on route start
      if (_driverLocation != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _centerMapOnDriver());
      } else if (_routePoints.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          try {
            _mapController.move(_routePoints.first, 15);
            setState(() => _isFollowingDriver = false);
          } catch (_) {}
        });
      }
    }
    _startTracking();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (!_hasShownDrivingTip && mounted) _showDrivingTipDialog();
      });
    });
  }

  void _initLocations() {
    _storeLocation = LatLng(
      widget.order.storeLatitude ?? 0,
      widget.order.storeLongitude ?? 0,
    );
    
    _customerLocation = LatLng(
      widget.order.locationLatitude,
      widget.order.locationLongitude,
    );
    
    if (widget.order.isOutForDelivery) {
      _phase = DeliveryPhase.goingToCustomer;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionSub?.cancel();
    _locationUpdateTimer?.cancel();
    _routeRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // When returning to the app, restart tracking and refresh the route quickly.
      _restartTracking();
    }
  }

  void _restartTracking() {
    _positionSub?.cancel();
    _locationUpdateTimer?.cancel();
    _routeRefreshTimer?.cancel();
    _startTracking();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 📍 LOCATION TRACKING
  // ─────────────────────────────────────────────────────────────────────────

  void _startTracking() async {
    // On web, getLastKnownPosition is not supported — skip it and try immediate fetch
    if (!kIsWeb) {
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null && mounted) {
          setState(() {
            _driverLocation = LatLng(last.latitude, last.longitude);
          });
          try {
            await _fetchRoute();
            _lastRouteFetch = DateTime.now();
          } catch (_) {}
          _centerMapOnDriver();
        }
      } catch (e) {
        debugPrint('No last-known position: $e');
      }
    }

    // Request a fresh current position (may be slower). Increase timeout on web.
    try {
      final timeout = kIsWeb ? const Duration(seconds: 20) : const Duration(seconds: 10);
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(timeout);

      if (mounted) {
        setState(() {
          _driverLocation = LatLng(pos.latitude, pos.longitude);
        });

        // Fetch route immediately (rate-limited)
        try {
          await _fetchRoute();
          _lastRouteFetch = DateTime.now();
        } catch (e) {
          debugPrint('Route fetch failed: $e');
        }

        _centerMapOnDriver();
      }
    } catch (e) {
      debugPrint('Could not get initial position: $e');
      if (mounted) setState(() => _isMapReady = true);
    }

    // Start position stream
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 15,
      ),
    ).listen(_onPositionUpdate);

    // Update backend every 30 seconds
    _locationUpdateTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _updateLocationInBackend();
    });
    
    // Refresh route every 60 seconds
    _routeRefreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      _fetchRoute();
    });
  }

  void _onPositionUpdate(Position pos) {
    if (!mounted) return;
    
    final newLocation = LatLng(pos.latitude, pos.longitude);
    
    setState(() {
      _driverLocation = newLocation;
    });

    _checkProximity(newLocation);

    // Rate-limit route refreshes when position updates frequently (every 8s)
    try {
      final now = DateTime.now();
      if (now.difference(_lastRouteFetch) > const Duration(seconds: 8)) {
        _lastRouteFetch = now;
        _fetchRoute();
      }
    } catch (e) {
      debugPrint('Failed to refresh route on update: $e');
    }
  }

  void _checkProximity(LatLng driverPos) {
    final distance = const Distance();
    
    if (_phase == DeliveryPhase.goingToStore) {
      final distToStore = distance.as(LengthUnit.Meter, driverPos, _storeLocation);
      setState(() {
        _distanceRemaining = distToStore;
        _isAtStore = distToStore <= ARRIVAL_THRESHOLD_METERS;
      });

      if (distToStore <= ARRIVAL_THRESHOLD_METERS && !_hasShownArrivalDialog) {
        _hasShownArrivalDialog = true;
        _showArrivalAtStoreDialog();
      }
    } else if (_phase == DeliveryPhase.goingToCustomer) {
      final distToCustomer = distance.as(LengthUnit.Meter, driverPos, _customerLocation);
      setState(() => _distanceRemaining = distToCustomer);
      
      if (distToCustomer <= ARRIVAL_THRESHOLD_METERS && !_hasShownArrivalDialog) {
        _hasShownArrivalDialog = true;
        _showArrivalAtCustomerDialog();
      }
    }
  }

  void _showDrivingTipDialog() {
    _hasShownDrivingTip = true;
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: widget.kCardBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.directions_car, size: 56, color: Colors.blueAccent),
            const SizedBox(height: 12),
            Text(
              'Drive safely — don\'t speed',
              style: TextStyle(
                color: widget.kPrimaryTextColor,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Follow the route on the map. The Scan button will be available when you arrive at the store.',
              style: TextStyle(color: widget.kSecondaryTextColor),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                setState(() {
                  _isFollowingDriver = true;
                  if (_driverLocation != null) _mapController.move(_driverLocation!, 16);
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.kAccentBlue,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('OK', style: TextStyle(color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _updateLocationInBackend() async {
    if (_driverLocation == null) return;
    
    try {
      await ApiService.updateMyDeliveryLocation(
        _driverLocation!.latitude,
        _driverLocation!.longitude,
      );
      
      if (_phase == DeliveryPhase.goingToCustomer) {
        await ApiService.updateOrderDriverLocation(
          widget.order.id,
          _driverLocation!.latitude,
          _driverLocation!.longitude,
        );
      }
    } catch (e) {
      debugPrint('Failed to update location: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 🛣️ ROUTE CALCULATION
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _fetchRoute() async {
    if (_driverLocation == null) return;
    
    final destination = _phase == DeliveryPhase.goingToStore 
        ? _storeLocation 
        : _customerLocation;

    if (destination.latitude == 0 || destination.longitude == 0) return;

    try {
      final url = Uri.parse(
        'https://api.mapbox.com/directions/v5/mapbox/driving/'
        '${_driverLocation!.longitude},${_driverLocation!.latitude};'
        '${destination.longitude},${destination.latitude}'
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
          final distanceMeters = (route['distance'] as num).toDouble();
          
          final points = coords.map<LatLng>((c) => 
            LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())
          ).toList();

          if (mounted) {
            setState(() {
              _routePoints = points;
              _eta = _formatDuration(duration);
              _distanceRemaining = distanceMeters;
              _isMapReady = true;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to fetch route: $e');
      if (mounted) setState(() => _isMapReady = true);
    }
  }

  String _formatDuration(double seconds) {
    final minutes = (seconds / 60).round();
    if (minutes < 1) return '< 1 min';
    if (minutes == 1) return '1 min';
    return '$minutes min';
  }

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.toStringAsFixed(0)}m';
    return '${(meters / 1000).toStringAsFixed(1)}km';
  }

  void _centerMapOnDriver() {
    if (_driverLocation != null) {
      try {
        _mapController.move(_driverLocation!, 15);
        setState(() {
          _isFollowingDriver = true;
        });
      } catch (e) {
        debugPrint('Could not center map: $e');
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  ARRIVAL DIALOGS
  // ─────────────────────────────────────────────────────────────────────────

  void _showArrivalAtStoreDialog() {
    HapticFeedback.heavyImpact();
    
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: widget.kCardBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.store, color: Colors.orange, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                "Arrived at Store",
                style: TextStyle(color: widget.kPrimaryTextColor, fontSize: 18),
              ),
            ),
          ],
        ),
        content: Text(
          "Scan the QR code to pick up the order.",
          style: TextStyle(color: widget.kSecondaryTextColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text("Later", style: TextStyle(color: widget.kSecondaryTextColor)),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _openQRScanner();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.kAccentBlue,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.qr_code_scanner, color: Colors.white, size: 18),
            label: const Text("Scan QR", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showArrivalAtCustomerDialog() {
    HapticFeedback.heavyImpact();
    
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: widget.kCardBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle, color: Colors.green, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                "You've Arrived!",
                style: TextStyle(color: widget.kPrimaryTextColor, fontSize: 18),
              ),
            ),
          ],
        ),
        content: Text(
          "Hand the order to ${widget.order.userName} and mark as delivered.",
          style: TextStyle(color: widget.kSecondaryTextColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text("Later", style: TextStyle(color: widget.kSecondaryTextColor)),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _markAsDelivered();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.check, color: Colors.white, size: 18),
            label: const Text("Mark Delivered", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  ACTIONS
  // ─────────────────────────────────────────────────────────────────────────

  void _openQRScanner() {
    if (!_isAtStore) {
      _showSnackBar('Scan available only when you are at the store', isError: true);
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => QRScannerView(
          orderId: widget.order.id,
          kDarkBackground: widget.kDarkBackground,
          kCardBackground: widget.kCardBackground,
          kAppBarBackground: widget.kAppBarBackground,
          kPrimaryTextColor: widget.kPrimaryTextColor,
          kSecondaryTextColor: widget.kSecondaryTextColor,
          kAccentBlue: widget.kAccentBlue,
          onScanSuccess: _onOrderPickedUp,
        ),
      ),
    );
  }

  void _onOrderPickedUp() async {
    try {
      await ApiService.postOrderPickedUp(widget.order.id);
      
      if (mounted) {
        Navigator.pop(context); // Close scanner

        setState(() {
          _phase = DeliveryPhase.goingToCustomer;
          _hasShownArrivalDialog = false;
          _routePoints = [];
        });

        await _fetchRoute();
        _showSnackBar("Order picked up! Head to the customer.");
      }
    } catch (e) {
      _showSnackBar("Failed: $e", isError: true);
    }
  }

  Future<void> _markAsDelivered() async {
    HapticFeedback.heavyImpact();
    
    try {
      final result = await ApiService.postMarkDelivered(widget.order.id);
      
      if (result && mounted) {
        _showDeliveryCompleteDialog();
      }
    } catch (e) {
      _showSnackBar("Failed: $e", isError: true);
    }
  }

  void _showDeliveryCompleteDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: widget.kCardBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle, color: Colors.green, size: 60),
            ),
            const SizedBox(height: 20),
            Text(
              "Delivery Complete! 🎉",
              style: TextStyle(
                color: widget.kPrimaryTextColor,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Great job!",
              textAlign: TextAlign.center,
              style: TextStyle(color: widget.kSecondaryTextColor),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.kAccentBlue,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text(
                "Back to Dashboard",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _launchGoogleMaps() async {
    // Toggle follow-driving mode instead of launching external maps
    setState(() {
      _isFollowingDriver = !_isFollowingDriver;
    });

    if (_isFollowingDriver && _driverLocation != null) {
      _mapController.move(_driverLocation!, 16);
    }
  }

  void _toggleMapStyle() {
    setState(() {
      _mapStyle = _mapStyle == 'dark' ? 'satellite' : 'dark';
    });
  }

  void _callPhone(String? phone) async {
    if (phone == null || phone.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  BUILD UI
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final destination = _phase == DeliveryPhase.goingToStore
        ? (widget.order.storeName.isNotEmpty 
            ? widget.order.storeName 
            : (widget.order.items.isNotEmpty ? widget.order.items.first.storeName : 'Store'))
        : widget.order.userName;

    final phaseLabel = _phase == DeliveryPhase.goingToStore ? "Pick up from" : "Deliver to";

    return Scaffold(
      backgroundColor: widget.kDarkBackground,
      body: Stack(
        children: [
          // Map
          _buildMap(),
          
          // Header
          _buildHeader(phaseLabel, destination),
          
          // Bottom card
          _buildBottomCard(),
          
          // Recenter button
          if (_driverLocation != null)
            Positioned(
              right: 16,
              bottom: 200,
              child: FloatingActionButton.small(
                heroTag: 'recenter',
                backgroundColor: widget.kCardBackground,
                onPressed: _centerMapOnDriver,
                child: Icon(Icons.my_location, color: widget.kAccentBlue),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    final initialCenter = _driverLocation ?? _storeLocation;

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: initialCenter,
        initialZoom: 15,
        minZoom: 5,
        maxZoom: 19,
        onMapReady: () {
          if (_driverLocation != null) {
            _centerMapOnDriver();
          }
        },
        onPositionChanged: (mapPosition, hasGesture) {
          // If user manually interacts with the map, stop auto-following.
          if (hasGesture == true && _isFollowingDriver) {
            setState(() {
              _isFollowingDriver = false;
            });
          }
        },
      ),
      children: [
        TileLayer(
          urlTemplate: _mapStyle == 'dark'
              ? 'https://api.mapbox.com/styles/v1/mapbox/dark-v11/tiles/{z}/{x}/{y}?access_token=$MAPBOX_ACCESS_TOKEN'
              : 'https://api.mapbox.com/styles/v1/mapbox/satellite-v9/tiles/{z}/{x}/{y}?access_token=$MAPBOX_ACCESS_TOKEN',
          userAgentPackageName: 'com.yshop.delivery',
        ),

        // Route line
        if (_routePoints.isNotEmpty)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _routePoints,
                color: _phase == DeliveryPhase.goingToStore ? Colors.white : Colors.blueAccent,
                strokeWidth: 5,
              ),
            ],
          ),
        
        // Markers
        MarkerLayer(
          markers: [
            // Store marker
            if (_storeLocation.latitude != 0)
              Marker(
                point: _storeLocation,
                width: 44,
                height: 44,
                child: Container(
                  decoration: BoxDecoration(
                    color: _phase == DeliveryPhase.goingToStore ? Colors.orange : Colors.grey,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
                  ),
                  child: const Icon(Icons.store, color: Colors.white, size: 22),
                ),
              ),
            
            // Customer marker
            Marker(
              point: _customerLocation,
              width: 44,
              height: 44,
              child: Container(
                decoration: BoxDecoration(
                  color: _phase == DeliveryPhase.goingToCustomer ? Colors.green : Colors.grey,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
                ),
                child: const Icon(Icons.person_pin, color: Colors.white, size: 22),
              ),
            ),
            
            // Driver marker
            if (_driverLocation != null)
              Marker(
                point: _driverLocation!,
                width: 50,
                height: 50,
                child: Container(
                  decoration: BoxDecoration(
                    color: widget.kAccentBlue,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: widget.kAccentBlue.withOpacity(0.4),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.navigation, color: Colors.white, size: 24),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildHeader(String phaseLabel, String destination) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 8,
          left: 16,
          right: 16,
          bottom: 12,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              widget.kDarkBackground,
              widget.kDarkBackground.withOpacity(0.9),
              Colors.transparent,
            ],
          ),
        ),
        child: Row(
          children: [
            // Back button
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: widget.kCardBackground,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
              ),
            ),
            
            const SizedBox(width: 12),
            
            // Info
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: widget.kCardBackground.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(phaseLabel, style: TextStyle(color: widget.kSecondaryTextColor, fontSize: 11)),
                          Text(
                            destination,
                            style: TextStyle(color: widget.kPrimaryTextColor, fontWeight: FontWeight.bold, fontSize: 15),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: widget.kAccentBlue.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.access_time, color: widget.kAccentBlue, size: 14),
                          const SizedBox(width: 4),
                          Text(_eta, style: TextStyle(color: widget.kAccentBlue, fontWeight: FontWeight.bold, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(width: 12),
            
            // Call button
            GestureDetector(
              onTap: () => _callPhone(
                _phase == DeliveryPhase.goingToStore
                    ? widget.order.storePhone
                    : widget.order.customerPhone ?? widget.order.userPhone,
              ),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                child: const Icon(Icons.phone, color: Colors.white, size: 20),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _toggleMapStyle,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: widget.kCardBackground, shape: BoxShape.circle),
                child: Icon(_mapStyle == 'dark' ? Icons.map : Icons.satellite, color: widget.kAccentBlue, size: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomCard() {
    return Positioned(
      left: 16,
      right: 16,
      bottom: 16 + MediaQuery.of(context).padding.bottom,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: widget.kCardBackground,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 15)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Phase indicator
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildPhaseIcon(Icons.store, "Store", _phase == DeliveryPhase.goingToStore, _phase != DeliveryPhase.goingToStore),
                Container(width: 40, height: 2, color: _phase != DeliveryPhase.goingToStore ? Colors.green : widget.kSeparatorColor),
                _buildPhaseIcon(Icons.person_pin, "Customer", _phase == DeliveryPhase.goingToCustomer, false),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Distance info
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.route, color: widget.kSecondaryTextColor, size: 16),
                const SizedBox(width: 6),
                Text(_formatDistance(_distanceRemaining), style: TextStyle(color: widget.kSecondaryTextColor, fontSize: 13)),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // If heading to customer, show customer address + quick call buttons
            if (_phase == DeliveryPhase.goingToCustomer) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Column(
                  children: [
                    Text(
                      widget.order.locationLatitude == 0 && widget.order.locationLongitude == 0
                          ? ''
                          : widget.order.userName + ' — ' + (widget.order.addressFull ?? ''),
                      style: TextStyle(color: widget.kPrimaryTextColor, fontSize: 13, fontWeight: FontWeight.w600),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () => _callPhone(widget.order.storePhone),
                          style: ElevatedButton.styleFrom(backgroundColor: widget.kAccentBlue, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                          icon: const Icon(Icons.store, size: 16, color: Colors.white),
                          label: const Text('Call Store', style: TextStyle(color: Colors.white)),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: () => _callPhone(widget.order.customerPhone ?? widget.order.userPhone),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                          icon: const Icon(Icons.person, size: 16, color: Colors.white),
                          label: const Text('Call Customer', style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],

            // Action buttons (stacked for mobile)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Drive / Follow toggle (full width)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _launchGoogleMaps,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(color: widget.kAccentBlue),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: Icon(Icons.navigation, color: widget.kAccentBlue, size: 18),
                    label: Text(_isFollowingDriver ? "Following" : "Drive", style: TextStyle(color: widget.kAccentBlue, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 12),
                // Main action button (Scan / Mark Delivered) - full width with iOS-like styling
                SizedBox(
                  width: double.infinity,
                  child: Column(
                    children: [
                      if (_phase == DeliveryPhase.goingToStore)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Text(
                            'When you arrive, ask the store to show the QR code. The button enables at the store.',
                            style: TextStyle(color: widget.kSecondaryTextColor, fontSize: 12),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ElevatedButton.icon(
                        onPressed: _phase == DeliveryPhase.goingToStore ? (_isAtStore ? _openQRScanner : null) : _markAsDelivered,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _phase == DeliveryPhase.goingToStore ? (_isAtStore ? widget.kAccentBlue : Colors.grey) : Colors.green,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 2,
                        ),
                        icon: Icon(
                          _phase == DeliveryPhase.goingToStore ? Icons.qr_code_scanner : Icons.check_circle,
                          color: Colors.white,
                          size: 20,
                        ),
                        label: Text(
                          _phase == DeliveryPhase.goingToStore ? "Scan QR to Pick Up" : "Mark Delivered",
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhaseIcon(IconData icon, String label, bool isActive, bool isCompleted) {
    final color = isCompleted ? Colors.green : isActive ? widget.kAccentBlue : widget.kSeparatorColor;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w500)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 📍 DELIVERY PHASE
// ─────────────────────────────────────────────────────────────────────────────

enum DeliveryPhase {
  goingToStore,
  goingToCustomer,
}