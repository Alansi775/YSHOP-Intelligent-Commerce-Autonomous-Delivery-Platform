// lib/screens/admin/admin_home_view.dart

import 'dart:ui';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../services/api_service.dart';
import '../../models/store.dart';
import '../auth/admin_login_view.dart' as admin_login;
import '../stores/store_products_view.dart' as sp;
import 'common.dart';
import 'widgets.dart' as w;
import 'sidebar.dart';
import 'stores_view.dart';
import 'products_view.dart';
import 'drivers_view.dart';
import 'orders_view.dart';
import 'admins_view.dart';
import 'users_view.dart';
import 'returns_view.dart';
import '../customers/settings_view.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// 🏠 ADMIN HOME VIEW - Modern Dashboard
// ═══════════════════════════════════════════════════════════════════════════════

class AdminHomeView extends StatefulWidget {
  const AdminHomeView({super.key});

  @override
  State<AdminHomeView> createState() => _AdminHomeViewState();
}

class _AdminHomeViewState extends State<AdminHomeView> {
  // Navigation state
  int _selectedIndex = 0;
  
  //  Unique keys to force rebuild views when navigating
  Key _storesKey = UniqueKey();
  Key _productsKey = UniqueKey();
  Key _driversKey = UniqueKey();
  
  // Tab indices for each view
  int _storesTabIndex = 0;
  int _productsTabIndex = 0;
  int _driversTabIndex = 0;

  // Active store context when viewing a specific store's products
  String? _activeStoreId;
  String? _activeStoreName;
  
  // Dashboard data
  Map<String, dynamic> _dashboardData = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
    _loadAdminProfile();
    _loadAdminProfileFallback();
  }
  
  Map<String, dynamic>? _adminProfile;
  
  Future<void> _loadAdminProfile() async {
    try {
      final profile = ApiService.cachedAdminProfile;
      if (profile != null) {
        setState(() => _adminProfile = profile);
      }
    } catch (_) {}
  }
  
  // Fallback: load profile from SharedPreferences if ApiService cache is empty
  Future<void> _loadAdminProfileFallback() async {
    try {
      if (_adminProfile != null) return;
      final prefs = await SharedPreferences.getInstance();
      final profileJson = prefs.getString('admin_profile');
      if (profileJson != null) {
        final map = jsonDecode(profileJson) as Map<String, dynamic>;
        setState(() => _adminProfile = map);
      }
    } catch (_) {}
  }

  Future<void> _loadDashboardData() async {
    if (!mounted) return;
    
    try {
      debugPrint(' [Dashboard] Loading dashboard data...');
      
      //  Always clear cache BEFORE loading to ensure fresh data
      ApiService.clearCache();
      setState(() => _isLoading = true);
      
      //  NEW: Use single endpoint instead of 6 separate requests!
      final dashboardStats = await ApiService.getDashboardStats();
      debugPrint(' [Dashboard] Received dashboard stats');
      
      final orders = dashboardStats['orders'] as List? ?? [];
      double totalRevenue = 0.0;
      double appRevenue = 0.0;
      
      for (final o in orders) {
        final price = double.tryParse((o['total_price'] ?? '0').toString()) ?? 0.0;
        totalRevenue += price;
        appRevenue += RevenueCalculator.calculateAppRevenue(price);
      }
      
      final approvedStoresCount = (dashboardStats['approved_stores'] as List?)?.length ?? 0;
      final pendingStoresCount = (dashboardStats['pending_stores'] as List?)?.length ?? 0;
      
      debugPrint(' [Dashboard] Stats: Approved=${approvedStoresCount}, Pending=${pendingStoresCount}');
      
      if (!mounted) return;
      
      setState(() {
        _dashboardData = {
          'approvedStores': approvedStoresCount,
          'pendingStores': pendingStoresCount,
          'pendingProducts': dashboardStats['pending_products_count'] ?? 0,
          'activeDrivers': dashboardStats['active_deliveries_count'] ?? 0,
          'pendingDrivers': dashboardStats['pending_deliveries_count'] ?? 0,
          'ordersCount': orders.length,
          'totalRevenue': totalRevenue,
          'appRevenue': appRevenue,
        };
        _isLoading = false;
      });
      
      debugPrint(' [Dashboard] Updated UI with new data');
    } catch (e) {
      debugPrint('❌ [Dashboard] Error loading dashboard data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _refreshData() {
    //  Generate new keys to force all views to rebuild
    setState(() {
      _storesKey = UniqueKey();
      _productsKey = UniqueKey();
      _driversKey = UniqueKey();
    });
    _loadDashboardData();
  }

  void _onSelectMenu(int idx) {
    //  AGGRESSIVE cache clearing to prevent stale data
    ApiService.clearCache();
    ApiService.clearPendingRequests();
    
    setState(() {
      _selectedIndex = idx;
      
      //  Generate new keys when navigating to force fresh data load
      // But NOT when coming from callbacks (to avoid race conditions)
      if (idx == 1) _driversKey = UniqueKey();
      if (idx == 2) _storesKey = UniqueKey();
      if (idx == 3) _productsKey = UniqueKey();
      
      //  If navigating to dashboard, reload data
      if (idx == 0) {
        _loadDashboardData();
      }
      
      // clear active store when switching to other sections
      if (idx != 3) {
        _activeStoreId = null;
        _activeStoreName = null;
      }
    });
  }

  void _openStoreInProducts(String storeId, String storeName) {
    setState(() {
      _activeStoreId = storeId;
      _activeStoreName = storeName;
      _selectedIndex = 3; // switch to Products view
    });
  }

  void _logout() {
    ApiService.adminLogout();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const admin_login.AdminLoginView()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isWide = constraints.maxWidth >= 900;
        
        return Scaffold(
          backgroundColor: kDarkBackground,
          drawer: !isWide ? _buildDrawer() : null,
          body: Stack(
            children: [
              // Background gradient
              _buildBackground(),
              
              // Main content
              Row(
                children: [
                  // Sidebar (desktop only)
                  if (isWide)
                    AdminSidebar(
                      selectedIndex: _selectedIndex,
                      onSelect: _onSelectMenu,
                      onLogout: _logout,
                      currentUserName: _adminProfile != null ? '${_adminProfile!["first_name"] ?? ''} ${_adminProfile!["last_name"] ?? ''}' : 'Admin',
                      currentUserRole: _adminProfile != null ? (_adminProfile!["role"] ?? 'Admin') : 'Admin',
                    ),
                  
                  // Main area
                  Expanded(
                    child: Column(
                      children: [
                        _buildAppBar(isWide),
                        Expanded(child: _buildContent()),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBackground() {
    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topRight,
            radius: 1.5,
            colors: [
              kAccentBlue.withOpacity(0.08),
              kAccentPurple.withOpacity(0.05),
              kDarkBackground,
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(bool isWide) {
    String title = 'Dashboard';
    switch (_selectedIndex) {
      case 1: title = 'Drivers Management'; break;
      case 2: title = 'Stores Management'; break;
      case 3: title = 'Products Management'; break;
      case 4: title = 'Admins Management'; break;
      case 5: title = 'Users Management'; break;
      case 6: title = 'Orders & Revenue'; break;
      case 8: title = 'Returns Management'; break;
    }
    
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      automaticallyImplyLeading: !isWide,
      leading: !isWide
          ? Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Icons.menu_rounded, color: kPrimaryTextColor),
                onPressed: () => Scaffold.of(ctx).openDrawer(),
              ),
            )
          : null,
      title: Text(
        title,
        style: const TextStyle(
          color: kPrimaryTextColor,
          fontSize: 24,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.5,
        ),
      ),
      actions: [
        // Refresh button
        IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: kGlassBackground,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: kGlassBorder, width: 1),
            ),
            child: const Icon(Icons.refresh_rounded, color: kPrimaryTextColor, size: 20),
          ),
          onPressed: _refreshData,
          tooltip: 'Refresh',
        ),
        const SizedBox(width: 12),
      ],
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: kDeepBackground,
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: AppGradients.primary,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Center(
                      child: Text(
                        'Y',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'YSHOP',
                        style: TextStyle(
                          color: kPrimaryTextColor,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'Admin Panel',
                        style: TextStyle(
                          color: kSecondaryTextColor,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            const Divider(color: kSeparatorColor),
            
            // Nav items
            Expanded(
              child: Builder(builder: (ctx) {
                final role = ApiService.cachedAdminRole?.toLowerCase() ?? 'admin';
                final bool isSuper = role == 'superadmin';
                return ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  children: [
                    _buildDrawerItem(0, Icons.dashboard_rounded, 'Dashboard'),
                    _buildDrawerItem(6, Icons.receipt_long_rounded, 'Orders'),
                    _buildDrawerItem(8, Icons.assignment_return_rounded, 'Returns'),
                    const SizedBox(height: 8),
                    _buildDrawerItem(2, Icons.storefront_rounded, 'Stores'),
                    _buildDrawerItem(3, Icons.inventory_2_rounded, 'Products'),
                    if (!role.startsWith('user')) _buildDrawerItem(1, Icons.delivery_dining_rounded, 'Drivers'),
                    const SizedBox(height: 8),
                    if (isSuper) _buildDrawerItem(4, Icons.admin_panel_settings_rounded, 'Admins'),
                    if (!role.startsWith('user')) _buildDrawerItem(5, Icons.people_rounded, 'Users'),
                    const SizedBox(height: 8),
                    _buildDrawerItem(7, Icons.settings_rounded, 'Settings'),
                  ],
                );
              }),
            ),
            
            // Logout
            Container(
              padding: const EdgeInsets.all(16),
              child: w.GlassOutlineButton(
                label: 'Logout',
                icon: Icons.logout_rounded,
                color: kAccentRed,
                onPressed: _logout,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerItem(int index, IconData icon, String label) {
    final isSelected = _selectedIndex == index;
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: ListTile(
        leading: Icon(
          icon,
          color: isSelected ? kAccentBlue : kSecondaryTextColor,
          size: 22,
        ),
        title: Text(
          label,
          style: TextStyle(
            color: isSelected ? kPrimaryTextColor : kSecondaryTextColor,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
        selected: isSelected,
        selectedTileColor: kAccentBlue.withOpacity(0.1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onTap: () {
          _onSelectMenu(index);
          Navigator.pop(context);
        },
      ),
    );
  }

  Widget _buildContent() {
    switch (_selectedIndex) {
      case 0:
        return _buildDashboard();
      case 1:
        return DriversManagementView(
          key: _driversKey, //  Force rebuild with new key
          initialTabIndex: _driversTabIndex,
          onDriverUpdated: _loadDashboardData, //  Refresh dashboard when driver changes
        );
      case 2:
        return StoresManagementView(
          key: _storesKey, //  Force rebuild with new key
          onOpenStore: (s) => _openStoreInProducts(s.id, s.storeName),
          initialTabIndex: _storesTabIndex,
          onStoreUpdated: _loadDashboardData, //  Refresh dashboard when store changes
        );
      case 3:
        if (_activeStoreId != null) {
          return sp.StoreProductsView(
            key: ValueKey('store_products_$_activeStoreId'),
            storeId: _activeStoreId!,
            storeName: _activeStoreName ?? 'Store',
            embedInAdmin: true,
          );
        }
        return ProductsManagementView(
          key: _productsKey, //  Force rebuild with new key
          initialTabIndex: _productsTabIndex,
          onProductUpdated: _loadDashboardData, //  Refresh dashboard when product changes
        );
      case 4:
        return const AdminsManagementView();
      case 5:
        return const UsersManagementView();
      case 6:
        return OrdersManagementView();
      case 7:
        return const SettingsView();
      case 8:
        return const ReturnsManagementView();
      default:
        return _buildDashboard();
    }
  }

  Widget _buildDashboard() {
    return RefreshIndicator(
      onRefresh: () async => _refreshData(),
      color: kAccentBlue,
      backgroundColor: kCardBackground,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome section
            _buildWelcomeSection(),
            
            const SizedBox(height: 32),
            
            // Revenue card (prominent)
            _buildRevenueSection(),
            
            const SizedBox(height: 32),
            
            // Stats grid
            w.SectionHeader(
              title: 'Quick Stats',
              subtitle: 'Overview of your business',
            ),
            _buildStatsGrid(),
            
            const SizedBox(height: 32),
            
            // Quick actions
            w.SectionHeader(
              title: 'Quick Actions',
              subtitle: 'Navigate to management sections',
            ),
            _buildQuickActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeSection() {
    final hour = DateTime.now().hour;
    String greeting = 'Good Morning';
    if (hour >= 12 && hour < 17) greeting = 'Good Afternoon';
    if (hour >= 17) greeting = 'Good Evening';
    
    return w.GlassContainer(
      padding: const EdgeInsets.all(28),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  greeting,
                  style: TextStyle(
                    color: kSecondaryTextColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Welcome back, ${_adminProfile != null ? '${_adminProfile!["first_name"] ?? ''} ${_adminProfile!["last_name"] ?? ''}' : 'Admin'}',
                  style: const TextStyle(
                    color: kPrimaryTextColor,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Here\'s what\'s happening with your store today.',
                  style: TextStyle(
                    color: kSecondaryTextColor,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: AppGradients.primary,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: kAccentBlue.withOpacity(0.4),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(
              Icons.rocket_launch_rounded,
              color: Colors.white,
              size: 40,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRevenueSection() {
    final totalRevenue = _dashboardData['totalRevenue'] ?? 0.0;
    final appRevenue = _dashboardData['appRevenue'] ?? 0.0;
    final storeRevenue = totalRevenue - appRevenue;
    final ordersCount = _dashboardData['ordersCount'] ?? 0;
    
    return w.RevenueCard(
      totalRevenue: totalRevenue.toDouble(),
      appRevenue: appRevenue.toDouble(),
      storeRevenue: storeRevenue.toDouble(),
      ordersCount: ordersCount,
    );
  }

  Widget _buildStatsGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 1200
            ? 4
            : constraints.maxWidth > 800
                ? 3
                : 2;
        
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 1.3,
          children: [
            w.GlassStatCard(
              title: 'Active Stores',
              value: _isLoading ? '...' : '${_dashboardData['approvedStores'] ?? 0}',
              subtitle: 'Approved stores',
              icon: Icons.storefront_rounded,
              gradient: AppGradients.success,
              isLoading: _isLoading,
              onTap: () {
                setState(() => _storesTabIndex = 0); //  Approved tab
                _onSelectMenu(2);
              },
            ),
            w.GlassStatCard(
              title: 'Pending Stores',
              value: _isLoading ? '...' : '${_dashboardData['pendingStores'] ?? 0}',
              subtitle: 'Awaiting approval',
              icon: Icons.store_mall_directory_rounded,
              gradient: AppGradients.warning,
              isLoading: _isLoading,
              onTap: () {
                setState(() => _storesTabIndex = 1); //  Pending tab
                _onSelectMenu(2);
              },
            ),
            w.GlassStatCard(
              title: 'Pending Products',
              value: _isLoading ? '...' : '${_dashboardData['pendingProducts'] ?? 0}',
              subtitle: 'Need review',
              icon: Icons.inventory_2_rounded,
              gradient: AppGradients.purple,
              isLoading: _isLoading,
              onTap: () {
                setState(() => _productsTabIndex = 1); //  Pending tab
                _onSelectMenu(3);
              },
            ),
            w.GlassStatCard(
              title: 'Active Drivers',
              value: _isLoading ? '...' : '${_dashboardData['activeDrivers'] ?? 0}',
              subtitle: 'Ready to deliver',
              icon: Icons.delivery_dining_rounded,
              gradient: AppGradients.cyan,
              isLoading: _isLoading,
              onTap: () {
                setState(() => _driversTabIndex = 0); //  Active tab
                _onSelectMenu(1);
              },
            ),
            w.GlassStatCard(
              title: 'Pending Drivers',
              value: _isLoading ? '...' : '${_dashboardData['pendingDrivers'] ?? 0}',
              subtitle: 'Awaiting approval',
              icon: Icons.person_add_rounded,
              gradient: AppGradients.pink,
              isLoading: _isLoading,
              onTap: () {
                setState(() => _driversTabIndex = 2); //  Pending tab
                _onSelectMenu(1);
              },
            ),
            w.GlassStatCard(
              title: 'Total Orders',
              value: _isLoading ? '...' : '${_dashboardData['ordersCount'] ?? 0}',
              subtitle: 'All time orders',
              icon: Icons.receipt_long_rounded,
              gradient: AppGradients.primary,
              isLoading: _isLoading,
              onTap: () => _onSelectMenu(6),
            ),
          ],
        );
      },
    );
  }

  Widget _buildQuickActions() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _QuickActionCard(
          icon: Icons.add_business_rounded,
          label: 'View Store Requests',
          gradient: AppGradients.success,
          onTap: () {
            setState(() => _storesTabIndex = 1); // Pending stores
            _onSelectMenu(2);
          },
        ),
        _QuickActionCard(
          icon: Icons.playlist_add_check_rounded,
          label: 'Review Products',
          gradient: AppGradients.warning,
          onTap: () {
            setState(() => _productsTabIndex = 1); // Pending products
            _onSelectMenu(3);
          },
        ),
        _QuickActionCard(
          icon: Icons.person_search_rounded,
          label: 'Driver Requests',
          gradient: AppGradients.cyan,
          onTap: () {
            setState(() => _driversTabIndex = 2); // Pending drivers
            _onSelectMenu(1);
          },
        ),
        _QuickActionCard(
          icon: Icons.analytics_rounded,
          label: 'View Orders',
          gradient: AppGradients.purple,
          onTap: () => _onSelectMenu(6),
        ),
        _QuickActionCard(
          icon: Icons.assignment_return_rounded,
          label: 'View Returns',
          gradient: AppGradients.danger,
          onTap: () => _onSelectMenu(8),
        ),
        Builder(builder: (_) {
          final role = ApiService.cachedAdminRole?.toLowerCase() ?? 'admin';
          if (role == 'superadmin') {
            return _QuickActionCard(
              icon: Icons.admin_panel_settings_rounded,
              label: 'Manage Admins',
              gradient: AppGradients.pink,
              onTap: () => _onSelectMenu(4),
            );
          }
          return const SizedBox.shrink();
        }),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  QUICK ACTION CARD
// ─────────────────────────────────────────────────────────────────────────────

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Gradient gradient;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return w.GlassContainer(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: const TextStyle(
              color: kPrimaryTextColor,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.arrow_forward_ios_rounded,
            color: kSecondaryTextColor,
            size: 14,
          ),
        ],
      ),
    );
  }
}