import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/auth/sign_in_view.dart';
import 'screens/admin/admin_home_view.dart';
import 'screens/customers/category_home_view.dart';
import 'screens/delivery/delivery_home_view.dart';
import 'screens/stores/store_admin_view.dart';
import 'widgets/order_tracker_widget.dart';
import 'services/navigation_service.dart';

import 'state_management/cart_manager.dart';
import 'state_management/auth_manager.dart';
import 'state_management/theme_manager.dart';
import 'providers/ai_chat_provider.dart'; // 🤖 YSHOP AI Chat 

// Global ValueNotifier for tracking hero section scroll position
final isAboveHeroNotifier = ValueNotifier<bool>(true); 

// =======================================================
// MARK: - تعريفات الثيم (Themes Definitions)
// =======================================================

final _lightThemeData = ThemeData(
  brightness: Brightness.light,
  scaffoldBackgroundColor: Colors.white, 
  primaryColor: Colors.black,
  colorScheme: ColorScheme.light(
    primary: Colors.black, 
    secondary: Colors.blueAccent, 
    background: Colors.white, 
  ),
  primarySwatch: Colors.blue, 
  splashColor: Colors.black.withOpacity(0.1), 
  highlightColor: Colors.black.withOpacity(0.05), 
  fontFamily: 'TenorSans',
  appBarTheme: const AppBarTheme(
    backgroundColor: Colors.white, 
    elevation: 0, 
    centerTitle: true,
    iconTheme: IconThemeData(color: Colors.black), 
    titleTextStyle: TextStyle(
      color: Colors.black, 
      fontSize: 20, 
      fontWeight: FontWeight.bold,
      fontFamily: 'TenorSans',
    ),
  ),
);

final _darkThemeData = ThemeData(
  brightness: Brightness.dark,
  scaffoldBackgroundColor: Colors.grey[900], 
  primaryColor: Colors.white, 
  colorScheme: ColorScheme.dark(
    primary: Colors.white, 
    secondary: Colors.blueAccent,
    background: Colors.grey[900]!,
  ),
  primarySwatch: Colors.blue, 
  splashColor: Colors.white.withOpacity(0.1), 
  highlightColor: Colors.white.withOpacity(0.05), 
  fontFamily: 'TenorSans',
  appBarTheme: AppBarTheme(
    backgroundColor: Colors.grey[900], 
    elevation: 0, 
    centerTitle: true,
    iconTheme: const IconThemeData(color: Colors.white), 
    titleTextStyle: const TextStyle(
      color: Colors.white, 
      fontSize: 20, 
      fontWeight: FontWeight.bold,
      fontFamily: 'TenorSans',
    ),
  ),
);


// =======================================================
// MARK: - الدالة الرئيسية (main)
// =======================================================

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables from .env (do NOT commit secrets)
  // For Flutter Web the env file must be included as an asset — we bundle it as assets/.env
  // For native builds, either fileName '.env' or 'assets/.env' works; prefer assets for consistency.
  await dotenv.load(fileName: 'assets/.env');

  //  CRITICAL: Initialize SharedPreferences before anything else
  await SharedPreferences.getInstance();

  // Create AuthManager and load cached token BEFORE running app
  final authManager = AuthManager();
  await authManager.initializeAsync();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authManager),
        ChangeNotifierProvider(create: (_) => CartManager()),
        ChangeNotifierProvider(create: (_) => ThemeManager()),
        ChangeNotifierProvider(create: (_) => AIChatProvider()), // 🤖 YSHOP AI Chat
      ],
      child: const MyApp(),
    ),
  );
}


// =======================================================
// MARK: - Widget التطبيق (MyApp)
// =======================================================

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    //  استخدام Consumer للاستماع للتغييرات تلقائياً فقط للـ themeMode
    return Consumer<ThemeManager>(
      builder: (context, themeManager, child) {
        debugPrint(' Theme updated: ${themeManager.themeMode}');
        
        // Build MaterialApp without listening to theme changes in home
        return MaterialApp(
          navigatorKey: NavigationService.navigatorKey,
          title: 'YSHOP',
          theme: _lightThemeData, 
          darkTheme: _darkThemeData,
          themeMode: themeManager.themeMode, //  يتحدث تلقائياً

          debugShowCheckedModeBanner: false, 

          // Wrap navigator content with a builder so we can overlay the global OrderTrackerWidget
          builder: (context, child) {
            return Stack(
              children: [
                // The app's normal content (Navigator)
                if (child != null) child,
                // Global persistent order tracker overlay
                const OrderTrackerWidget(),
              ],
            );
          },

          home: child ?? const _HomeScreen(),
        );
      },
      child: const _HomeScreen(),
    );
  }
}
 

class _HomeScreen extends StatelessWidget {
  const _HomeScreen();

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthManager>(
      builder: (context, authManager, child) {
        // Use isAuthenticated which is set synchronously if token exists in SharedPreferences
        // authManager.initializeAsync() was called before main(), so token/profile should be loaded
        
        if (authManager.isAuthenticated) {
          final userType = authManager.userProfile?['userType'] as String?;
          final storeName = authManager.userProfile?['name'] as String? ?? 'Store';
          final driverName = authManager.userProfile?['display_name'] as String? ?? 'Driver';

          // التحقق من نوع المستخدم وإعادة التوجيه للصفحة المناسبة
          if (userType == 'storeOwner') {
            debugPrint(' Store Owner persisted - showing StoreAdminView');
            return StoreAdminView(initialStoreName: storeName);
          } else if (userType == 'deliveryDriver') {
            debugPrint('🚗 Delivery Driver persisted - showing DeliveryHomeView');
            return DeliveryHomeView(driverName: driverName);
          } else if (userType == 'admin' || userType == 'superadmin') {
            debugPrint('👨‍💼 Admin persisted - showing AdminHomeView');
            return const AdminHomeView();
          } else {
            debugPrint(' Customer persisted - showing CategoryHomeView');
            return const CategoryHomeView();
          }
        } else {
          return const SignInView();
        }
      },
    );
  }
}