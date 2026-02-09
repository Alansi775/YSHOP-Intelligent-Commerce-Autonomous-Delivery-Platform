// side_menu_view.dart - TRUE DJI STYLE
// Ultra minimal, elegant, sophisticated

import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:provider/provider.dart';
import '../screens/customers/settings_view.dart';
import '../screens/customers/my_orders_view.dart';
import '../screens/auth/sign_in_view.dart'; 
import '../state_management/auth_manager.dart'; 

class SideMenuViewContents extends StatefulWidget {
  const SideMenuViewContents({Key? key}) : super(key: key);

  @override
  State<SideMenuViewContents> createState() => _SideMenuViewContentsState();
}

class _SideMenuViewContentsState extends State<SideMenuViewContents> {
  @override
  Widget build(BuildContext context) {
    return const Placeholder();
  }
}

// ============== TRUE DJI STYLE PROFILE ==============
class ProfilePopupView {
  static void show(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.black.withOpacity(0.7),
        transitionDuration: const Duration(milliseconds: 500),
        reverseTransitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (context, animation, secondaryAnimation) {
          return Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 420, maxHeight: 680),
              margin: const EdgeInsets.symmetric(horizontal: 32, vertical: 60),
              child: Material(
                color: Colors.transparent,
                child: _ProfileDialogContent(),
              ),
            ),
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
            ),
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.94, end: 1.0).animate(
                CurvedAnimation(
                  parent: animation,
                  curve: const Interval(0.0, 0.8, curve: Curves.easeOutCubic),
                ),
              ),
              child: child,
            ),
          );
        },
      ),
    );
  }
}

class _ProfileDialogContent extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final authManager = Provider.of<AuthManager>(context);

    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
        child: Container(
          decoration: BoxDecoration(
            color: isDark 
              ? const Color(0xFF1A1A1A).withOpacity(0.98)  // أفتح شوي + أقوى
              : const Color(0xFFF8F8F8).withOpacity(0.98), // أغمق شوي + أقوى
            borderRadius: BorderRadius.circular(32),
            border: Border.all(
              color: isDark 
                ? Colors.white.withOpacity(0.12)  // أوضح
                : Colors.black.withOpacity(0.08),  // أوضح
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.4),  // أقوى
                blurRadius: 60,
                spreadRadius: 0,
                offset: const Offset(0, 20),
              ),
            ],
          ),
          child: Column(
            children: [
              _buildMinimalHeader(context, isDark),
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(32, 24, 32, 32),
                  child: _buildContent(context, authManager, isDark),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMinimalHeader(BuildContext context, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 28, 24, 24),
      child: Row(
        children: [
          const SizedBox(width: 32),
          const Spacer(),
          
          // Close button - more visible
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isDark 
                  ? Colors.white.withOpacity(0.08)  // كان 0.04 - أوضح
                  : Colors.black.withOpacity(0.05), // كان 0.02 - أوضح
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.close,
                size: 18,
                color: isDark 
                  ? Colors.white.withOpacity(0.80)  // كان 0.6 - أوضح
                  : Colors.black.withOpacity(0.80), // كان 0.6 - أوضح
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, AuthManager authManager, bool isDark) {
    final profile = authManager.userProfile;
    final displayName = profile?['display_name'] ?? 'User';
    final email = profile?['email'] ?? 'user@email.com';

    return Column(
      children: [
        const SizedBox(height: 8),
        
        // Avatar - more visible
        Container(
          width: 110,
          height: 110,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDark
              ? Colors.white.withOpacity(0.12)  // أوضح بكثير
              : Colors.black.withOpacity(0.08), // أوضح بكثير
          ),
          child: Center(
            child: Text(
              displayName[0].toUpperCase(),
              style: TextStyle(
                fontFamily: 'TenorSans',
                fontSize: 44,
                fontWeight: FontWeight.w300,
                color: isDark 
                  ? Colors.white.withOpacity(0.95)  // أوضح
                  : Colors.black.withOpacity(0.95), // أوضح
                letterSpacing: 0,
              ),
            ),
          ),
        ),
        
        const SizedBox(height: 28),
        
        // Name - واضح تماماً
        Text(
          displayName,
          style: TextStyle(
            fontFamily: 'TenorSans',
            fontSize: 26,
            fontWeight: FontWeight.w400,
            color: isDark ? Colors.white : Colors.black,  // 100% واضح
            letterSpacing: -0.3,
            height: 1.3,
          ),
          textAlign: TextAlign.center,
        ),
        
        const SizedBox(height: 8),
        
        // Email - أوضح
        Text(
          email,
          style: TextStyle(
            fontFamily: 'TenorSans',
            fontSize: 13,
            fontWeight: FontWeight.w400,
            color: isDark 
              ? Colors.white.withOpacity(0.55)  // كان 0.35 - الآن أوضح
              : Colors.black.withOpacity(0.55), // كان 0.35 - الآن أوضح
            letterSpacing: 0.3,
          ),
        ),
        
        const SizedBox(height: 64),
        
        // Menu items
        _buildCleanMenuItem(
          context,
          'Settings',
          isDark,
          () {
            Navigator.pop(context);
            Navigator.push(
              context,
              PageRouteBuilder(
                pageBuilder: (context, animation, secondaryAnimation) => const SettingsView(),
                transitionsBuilder: (context, animation, secondaryAnimation, child) {
                  return FadeTransition(opacity: animation, child: child);
                },
              ),
            );
          },
        ),
        
        const SizedBox(height: 8),
        
        // My Orders
        _buildCleanMenuItem(
          context,
          'My Orders',
          isDark,
          () {
            Navigator.pop(context);
            Navigator.push(
              context,
              PageRouteBuilder(
                pageBuilder: (context, animation, secondaryAnimation) => const MyOrdersView(),
                transitionsBuilder: (context, animation, secondaryAnimation, child) {
                  return FadeTransition(opacity: animation, child: child);
                },
              ),
            );
          },
        ),
        
        const SizedBox(height: 56),
        
        // Separator - أوضح
        Container(
          height: 1,
          margin: const EdgeInsets.symmetric(horizontal: 48),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.transparent,
                isDark 
                  ? Colors.white.withOpacity(0.15)  // كان 0.08 - أوضح
                  : Colors.black.withOpacity(0.12), // كان 0.06 - أوضح
                Colors.transparent,
              ],
            ),
          ),
        ),
        
        const SizedBox(height: 40),
        
        // Sign Out - واضح
        GestureDetector(
          onTap: () {
            Navigator.pop(context);
            authManager.signOut();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text(
              'Sign Out',
              style: TextStyle(
                fontFamily: 'TenorSans',
                fontSize: 15,
                fontWeight: FontWeight.w400,
                color: isDark 
                  ? const Color(0xFFEF5350)           // 100% واضح
                  : const Color(0xFFE53935),          // 100% واضح
                letterSpacing: 0.4,
              ),
            ),
          ),
        ),
        
        const SizedBox(height: 24),
        
        // Phone - أوضح شوي
        Text(
          '+90 539 255 4609',
          style: TextStyle(
            fontFamily: 'TenorSans',
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: isDark 
              ? Colors.white.withOpacity(0.35)  // كان 0.20 - أوضح
              : Colors.black.withOpacity(0.35), // كان 0.20 - أوضح
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }

  Widget _buildCleanMenuItem(
    BuildContext context,
    String label,
    bool isDark,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
        decoration: BoxDecoration(
          color: Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: isDark 
                ? Colors.white.withOpacity(0.10)  // كان 0.05 - أوضح بكثير
                : Colors.black.withOpacity(0.08), // كان 0.04 - أوضح
              width: 1,
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'TenorSans',
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                  color: isDark 
                    ? Colors.white                    // 100% واضح
                    : Colors.black,                   // 100% واضح
                  letterSpacing: 0.2,
                ),
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 13,
              color: isDark 
                ? Colors.white.withOpacity(0.40)  // كان 0.25 - أوضح
                : Colors.black.withOpacity(0.40), // كان 0.25 - أوضح
            ),
          ],
        ),
      ),
    );
  }
}