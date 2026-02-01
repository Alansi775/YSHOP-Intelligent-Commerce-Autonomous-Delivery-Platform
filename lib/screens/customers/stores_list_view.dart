// lib/screens/stores_list_view.dart

import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:provider/provider.dart';
import '../../state_management/cart_manager.dart';
import '../../state_management/theme_manager.dart';
import '../../services/api_service.dart'; //  استخدام API
import '../auth/sign_in_ui.dart'; // LuxuryTheme

// استيراد الشاشات والمكونات
import 'store_detail_view.dart';
import '../../widgets/side_menu_view_contents.dart';
import '../../widgets/side_cart_view_contents.dart';
import '../../models/store.dart';
import '../../widgets/store_card.dart';
import '../../widgets/cart_icon_with_badge.dart';

class StoresListView extends StatefulWidget {
  final String categoryName;
  const StoresListView({Key? key, required this.categoryName}) : super(key: key);

  @override
  State<StoresListView> createState() => _StoresListViewState();
}

class _StoresListViewState extends State<StoresListView> {
  // MARK: - State Variables
  List<Store> _stores = [];
  bool _isLoading = false;
  String _errorMessage = "";

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // MARK: - Lifecycle
  @override
  void initState() {
    super.initState();
    _loadStores();
  }

  //  MARK: - Load Stores from API (MySQL)
  void _loadStores() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = "";
    });

    try {
      //  استخدم API بدلاً من Firestore
      final storesData = await ApiService.getPublicStoresByType(widget.categoryName);

      debugPrint(' Loaded ${storesData.length} stores for ${widget.categoryName}');

      if (!mounted) return;
      setState(() {
        _stores = storesData.map((data) => Store.fromJson(data)).toList();
        _isLoading = false;
      });
    } catch (error) {
      debugPrint('❌ Error loading stores: $error');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = "Error loading stores: ${error.toString()}";
      });
    }
  }

  // MARK: - Widgets

  Widget _buildLoadingIndicator(BuildContext context, bool isDark) {
    return Positioned.fill(
      child: Container(
        color: isDark 
            ? Colors.black.withOpacity(0.4)
            : Colors.white.withOpacity(0.4),
        child: const Center(
          child: CircularProgressIndicator(
            color: LuxuryTheme.kLightBlueAccent,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyStateView(BuildContext context, Color textColor, Color secondaryText) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 80.0),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              Icons.storefront,
              size: 60,
              color: secondaryText.withOpacity(0.4),
            ),
            const SizedBox(height: 20),
            Text(
              "No Stores Available",
              style: TextStyle(
                fontFamily: 'Didot',
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: textColor,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 5),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40.0),
              child: Text(
                "We couldn't find any ${widget.categoryName.toLowerCase()} stores in your area.",
                style: TextStyle(
                  fontFamily: 'TenorSans',
                  fontSize: 14,
                  color: secondaryText,
                  fontWeight: FontWeight.w400,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebContainer({required Widget child}) {
    if (MediaQuery.of(context).size.width > 600) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 1000,
          ),
          child: child,
        ),
      );
    }
    return child;
  }

  // MARK: - Main Build Method
  @override
  Widget build(BuildContext context) {
    final themeManager = Provider.of<ThemeManager>(context);
    final isDark = themeManager.isDarkMode;
    
    // Luxury Colors
    final bgColor = isDark ? LuxuryTheme.kDarkBackground : LuxuryTheme.kLightBackground;
    final textColor = isDark ? LuxuryTheme.kPlatinum : LuxuryTheme.kDeepNavy;
    final secondaryText = isDark ? LuxuryTheme.kPlatinum.withOpacity(0.7) : LuxuryTheme.kDeepNavy.withOpacity(0.7);

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: bgColor,
      extendBodyBehindAppBar: true,
      drawer: const Drawer(child: SideMenuViewContents()),
      endDrawer: const Drawer(child: SideCartViewContents()),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            margin: const EdgeInsets.only(left: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05),
              shape: BoxShape.circle,
              border: Border.all(
                color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.08),
                width: 1,
              ),
            ),
            child: Icon(Icons.arrow_back, color: textColor, size: 20),
          ),
        ),
        title: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Text(
            "YSHOP",
            style: TextStyle(
              fontFamily: 'CinzelDecorative',
              fontSize: 28,
              color: textColor,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 5.0),
            child: CartIconWithBadge(),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? [const Color(0xFF0A0A0A), const Color(0xFF0A0A0A), const Color(0xFF1A1A1A)]
                : [const Color(0xFFF5F5F5), const Color(0xFFF5F5F5), const Color(0xFFE8E8E8)],
            stops: const [0.0, 1.8, 1.1],
          ),
        ),
        child: Stack(
          children: [
            SingleChildScrollView(
              child: Column(
                children: [
                  _buildWebContainer(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Content Header
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 100),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.categoryName,
                                style: TextStyle(
                                  fontFamily: 'Didot',
                                  fontSize: 36,
                                  fontWeight: FontWeight.w600,
                                  color: textColor,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                "${_stores.length} locations available",
                                style: TextStyle(
                                  fontFamily: 'TenorSans',
                                  fontSize: 14,
                                  color: secondaryText,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Store Grid
                        if (_stores.isEmpty && !_isLoading)
                          _buildEmptyStateView(context, textColor, secondaryText)
                        else if (_stores.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20.0),
                            child: GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 250,
                                crossAxisSpacing: 20,
                                mainAxisSpacing: 20,
                                childAspectRatio: 0.8,
                              ),
                              itemCount: _stores.length,
                              itemBuilder: (context, index) {
                                final store = _stores[index];
                                return StoreCard(
                                  store: store,
                                  onTap: () {
                                    Navigator.of(context).push(
                                      PageRouteBuilder(
                                        pageBuilder: (context, animation, secondaryAnimation) =>
                                            StoreDetailView(store: store),
                                        transitionsBuilder:
                                            (context, animation, secondaryAnimation, child) {
                                          return FadeTransition(
                                            opacity: animation.drive(Tween(begin: 0.0, end: 1.0)),
                                            child: child,
                                          );
                                        },
                                        transitionDuration: const Duration(milliseconds: 200),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                        const SizedBox(height: 30),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Loading Indicator
            if (_isLoading) _buildLoadingIndicator(context, isDark),
          ],
        ),
      ),
    );
  }
}