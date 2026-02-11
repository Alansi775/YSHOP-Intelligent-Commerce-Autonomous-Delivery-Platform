// lib/screens/admin/sidebar.dart

import 'dart:ui';
import 'package:flutter/material.dart';
import 'common.dart';
import 'package:shimmer/shimmer.dart';
import '../../widgets/welcoming_page_shimmer.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  MODERN ADMIN SIDEBAR - Apple-Inspired Navigation
// ═══════════════════════════════════════════════════════════════════════════════

class AdminSidebar extends StatefulWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback? onLogout;
  final String? currentUserName;
  final String? currentUserRole;

  const AdminSidebar({
    super.key,
    required this.selectedIndex,
    required this.onSelect,
    this.onLogout,
    this.currentUserName,
    this.currentUserRole,
  });

  @override
  State<AdminSidebar> createState() => _AdminSidebarState();
}

class _AdminSidebarState extends State<AdminSidebar> with SingleTickerProviderStateMixin {
  bool _collapsed = false;
  int? _hoveredIndex;
  late AnimationController _animController;
  late Animation<double> _widthAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _widthAnimation = Tween<double>(begin: 280, end: 80).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOutCubic),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _toggleCollapse() {
    setState(() {
      _collapsed = !_collapsed;
      if (_collapsed) {
        _animController.forward();
      } else {
        _animController.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _widthAnimation,
      builder: (context, child) {
        return Container(
          width: _widthAnimation.value,
          decoration: BoxDecoration(
            color: kDeepBackground,
            border: Border(
              right: BorderSide(
                color: kGlassBorder,
                width: 1,
              ),
            ),
          ),
          child: ClipRRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Column(
                children: [
                  _buildHeader(),
                  const SizedBox(height: 8),
                  Expanded(child: _buildNavigation()),
                  _buildFooter(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 80,
      padding: EdgeInsets.symmetric(horizontal: _collapsed ? 8 : 20),
      child: Row(
        children: [
          // Logo
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: AppGradients.primary,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: kAccentBlue.withOpacity(0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Center(
              child: Text(
                'Y',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          if (!_collapsed) ...[
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Show name and role if provided
                  Text(
                    widget.currentUserName ?? 'YSHOP',
                    style: const TextStyle(
                      color: kPrimaryTextColor,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.currentUserRole ?? 'Admin Panel',
                    style: TextStyle(
                      color: kSecondaryTextColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNavigation() {
    final role = (widget.currentUserRole ?? 'admin').toLowerCase();
    final bool isSuper = role == 'superadmin';
    final bool isAdmin = role == 'admin';

    return ListView(
      padding: EdgeInsets.symmetric(horizontal: _collapsed ? 12 : 16, vertical: 8),
      physics: const BouncingScrollPhysics(),
      children: [
        if (!_collapsed) _buildSectionLabel('OVERVIEW'),
        _buildNavItem(
          index: 0,
          icon: Icons.dashboard_rounded,
          label: 'Dashboard',
          gradient: AppGradients.primary,
        ),
        _buildNavItem(
          index: 6,
          icon: Icons.receipt_long_rounded,
          label: 'Orders',
          gradient: AppGradients.success,
        ),
        _buildNavItem(
          index: 8,
          icon: Icons.assignment_return_rounded,
          label: 'Returns',
          gradient: AppGradients.danger,
        ),

        const SizedBox(height: 16),
        if (!_collapsed) _buildSectionLabel('MANAGEMENT'),
        _buildNavItem(
          index: 2,
          icon: Icons.storefront_rounded,
          label: 'Stores',
          gradient: AppGradients.purple,
        ),
        _buildNavItem(
          index: 3,
          icon: Icons.inventory_2_rounded,
          label: 'Products',
          gradient: AppGradients.warning,
        ),
        // Drivers visible to admin and superadmin; users see read-only lists elsewhere if needed
        if (!role.startsWith('user'))
          _buildNavItem(
            index: 1,
            icon: Icons.delivery_dining_rounded,
            label: 'Drivers',
            gradient: AppGradients.cyan,
          ),

        const SizedBox(height: 16),
        if (!_collapsed) _buildSectionLabel('ADMINISTRATION'),
        // Admins management only for superadmin
        if (isSuper)
          _buildNavItem(
            index: 4,
            icon: Icons.admin_panel_settings_rounded,
            label: 'Admins',
            gradient: AppGradients.pink,
          ),
        // Users visible to admin and superadmin
        if (!role.startsWith('user'))
          _buildNavItem(
            index: 5,
            icon: Icons.people_rounded,
            label: 'Users',
            gradient: AppGradients.danger,
          ),

        const SizedBox(height: 12),
        // Settings visible to all roles (user/admin/superadmin)
        _buildNavItem(
          index: 7,
          icon: Icons.settings_rounded,
          label: 'Settings',
          gradient: AppGradients.purple,
        ),
      ],
    );
  }

  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, top: 16, bottom: 8),
      child: Text(
        label,
        style: TextStyle(
          color: kTertiaryTextColor,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required String label,
    required Gradient gradient,
  }) {
    final bool isSelected = widget.selectedIndex == index;
    final bool isHovered = _hoveredIndex == index;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hoveredIndex = index),
        onExit: (_) => setState(() => _hoveredIndex = null),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => widget.onSelect(index),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: EdgeInsets.symmetric(
              vertical: 14,
              horizontal: _collapsed ? 0 : 14,
            ),
            decoration: BoxDecoration(
              gradient: isSelected
                  ? LinearGradient(
                      colors: [
                        gradient.colors.first.withOpacity(0.2),
                        gradient.colors.last.withOpacity(0.05),
                      ],
                    )
                  : null,
              color: isHovered && !isSelected
                  ? Colors.white.withOpacity(0.05)
                  : null,
              borderRadius: BorderRadius.circular(12),
              border: isSelected
                  ? Border.all(
                      color: gradient.colors.first.withOpacity(0.3),
                      width: 1,
                    )
                  : null,
            ),
            child: Row(
              mainAxisSize: _collapsed ? MainAxisSize.min : MainAxisSize.max,
              mainAxisAlignment: _collapsed
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                // Icon container
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: isSelected ? gradient : null,
                    color: isSelected ? null : Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: gradient.colors.first.withOpacity(0.4),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(
                    icon,
                    size: 20,
                    color: isSelected
                        ? Colors.white
                        : isHovered
                            ? kPrimaryTextColor
                            : kSecondaryTextColor,
                  ),
                ),
                if (!_collapsed) ...[
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: isSelected
                            ? kPrimaryTextColor
                            : isHovered
                                ? kPrimaryTextColor
                                : kSecondaryTextColor,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  if (isSelected)
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        gradient: gradient,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: gradient.colors.first.withOpacity(0.6),
                            blurRadius: 6,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: kSeparatorColor, width: 1),
        ),
      ),
      child: Column(
        children: [
          // Small YSHOP shimmer in footer (keep name/role only in header)
          if (!_collapsed)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: kGlassBackground,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kGlassBorder, width: 1),
              ),
              child: SizedBox(
                height: 40,
                child: Center(
                  child: Shimmer.fromColors(
                    baseColor: Colors.grey.shade600,
                    highlightColor: kAccentBlue,
                    period: const Duration(seconds: 8),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: 'YS',
                            style: TextStyle(
                              fontFamily: 'TenorSans',
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: kAccentBlue,
                            ),
                          ),
                          TextSpan(
                            text: 'HOP',
                            style: TextStyle(
                              fontFamily: 'TenorSans',
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),
          
          // Actions row
          if (_collapsed)
            Center(
              child: _buildFooterButton(
                icon: Icons.logout_rounded,
                label: '',
                onTap: widget.onLogout,
                isDestructive: true,
              ),
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Logout button (full)
                _buildFooterButton(
                  icon: Icons.logout_rounded,
                  label: 'Logout',
                  onTap: widget.onLogout,
                  isDestructive: true,
                ),
                const SizedBox(width: 8),
                // Collapse button
                _buildFooterButton(
                  icon: Icons.keyboard_double_arrow_left_rounded,
                  label: '',
                  onTap: _toggleCollapse,
                ),
              ],
            ),
          
          if (_collapsed) ...[
            const SizedBox(height: 8),
            _buildFooterButton(
              icon: Icons.keyboard_double_arrow_right_rounded,
              label: '',
              onTap: _toggleCollapse,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFooterButton({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
    bool isDestructive = false,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: label.isEmpty ? 10 : 14,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: isDestructive
                ? kAccentRed.withOpacity(0.1)
                : Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDestructive
                  ? kAccentRed.withOpacity(0.3)
                  : kGlassBorder,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: isDestructive ? kAccentRed : kSecondaryTextColor,
              ),
              if (label.isNotEmpty && !_collapsed) ...[
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: isDestructive ? kAccentRed : kSecondaryTextColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}