import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'dart:ui';
import 'package:provider/provider.dart';
import 'package:latlong2/latlong.dart';

import '../../state_management/cart_manager.dart'; 
import '../../state_management/theme_manager.dart';
import '../../state_management/auth_manager.dart';
import '../../constants/store_categories.dart';
import '../../widgets/map_picker_sheet.dart';
import '../../widgets/welcoming_page_shimmer.dart';
import '../customers/category_home_view.dart';
import 'complete_profile_view.dart';
import '../delivery/delivery_signup_view.dart';
import '../delivery/delivery_home_view.dart';
import '../stores/store_admin_view.dart';
import 'admin_login_view.dart' as Admin;
import 'sign_in_ui.dart';

class SignInView extends StatefulWidget {
  /// When true (e.g. pushed as a login detour from an in-progress guest
  /// action like add-to-cart), a successful sign-in pops back to the
  /// caller with `true` instead of navigating to a home screen itself —
  /// the caller resumes whatever it was doing.
  final bool popOnSuccess;
  const SignInView({super.key, this.popOnSuccess = false});

  @override
  State<SignInView> createState() => _SignInViewState();
}

class _SignInViewState extends State<SignInView> with SingleTickerProviderStateMixin {
  // State Variables
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _surnameController = TextEditingController();
  final TextEditingController _storeNameController = TextEditingController();
  final TextEditingController _storeTypeController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _customerAddressController = TextEditingController();
  
  double _latitude = 0.0;
  double _longitude = 0.0;
  
  final TextEditingController _contactNumberController = TextEditingController();
  final TextEditingController _nationalIDController = TextEditingController();
  final TextEditingController _storePhoneNumberController = TextEditingController();
  final TextEditingController _buildingInfoController = TextEditingController();
  final TextEditingController _apartmentNumberController = TextEditingController();
  final TextEditingController _deliveryInstructionsController = TextEditingController();
  
  bool _isStoreOwner = false;
  bool _isLoading = false;
  bool _isNewStoreOwner = false;
  bool _showSignUp = false;
  String _message = "";

  /// Shows errors as a centered dialog instead of the old bottom-of-form
  /// text, which required scrolling past long forms (store signup) to see,
  /// especially on small Android screens.
  void _showError(String message) {
    if (!mounted) return;
    SignInUIComponents.showMessageDialog(
      context,
      message: message,
      isDark: LuxuryTheme.isDark(context),
    );
  }

  void _showSuccess(String message, {VoidCallback? onDismiss}) {
    if (!mounted) return;
    SignInUIComponents.showMessageDialog(
      context,
      message: message,
      isDark: LuxuryTheme.isDark(context),
      isSuccess: true,
      onDismiss: onDismiss,
    );
  }

  /// Clears everything except email/password, so after a signup that lands
  /// back on the login form the user doesn't have to retype credentials
  /// they just typed seconds ago.
  void _resetFormFieldsKeepCredentials() {
    if (!mounted) return;
    setState(() {
      _confirmPasswordController.clear();
      _nameController.clear();
      _surnameController.clear();
      _storeNameController.clear();
      _storeTypeController.clear();
      _addressController.clear();
      _customerAddressController.clear();
      _contactNumberController.clear();
      _nationalIDController.clear();
      _storePhoneNumberController.clear();
      _buildingInfoController.clear();
      _apartmentNumberController.clear();
      _deliveryInstructionsController.clear();
      _message = "";
    });
  }

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _fadeAnimation = CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic);
    _animationController.forward();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nameController.dispose();
    _surnameController.dispose();
    _storeNameController.dispose();
    _storeTypeController.dispose();
    _addressController.dispose();
    _customerAddressController.dispose();
    _contactNumberController.dispose();
    _nationalIDController.dispose();
    _storePhoneNumberController.dispose();
    _buildingInfoController.dispose();
    _apartmentNumberController.dispose();
    _deliveryInstructionsController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  // Map pickers
  Future<void> _showMapPickerForSignup() async {
    final defaultLat = 41.0082;
    final defaultLng = 28.9784;

    final initialCoordinate = LatLng(
      _latitude != 0.0 ? _latitude : defaultLat,
      _longitude != 0.0 ? _longitude : defaultLng,
    );

    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => MapPickerSheet(initialCoordinate: initialCoordinate),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _customerAddressController.text = result['address'] as String? ?? '';
        _latitude = result['latitude'] as double? ?? 0.0;
        _longitude = result['longitude'] as double? ?? 0.0;
      });
    }
  }

  Future<void> _showMapPickerForStoreOwner() async {
    final defaultLat = 41.0082;
    final defaultLng = 28.9784;

    final initialCoordinate = LatLng(
      _latitude != 0.0 ? _latitude : defaultLat,
      _longitude != 0.0 ? _longitude : defaultLng,
    );

    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => MapPickerSheet(initialCoordinate: initialCoordinate),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _addressController.text = result['address'] as String? ?? '';
        _latitude = result['latitude'] as double? ?? 0.0;
        _longitude = result['longitude'] as double? ?? 0.0;
      });
    }
  }

  void _resetFormFields() {
    if (mounted) {
      setState(() {
        _emailController.clear();
        _passwordController.clear();
        _confirmPasswordController.clear();
        _nameController.clear();
        _surnameController.clear();
        _storeNameController.clear();
        _storeTypeController.clear();
        _addressController.clear();
        _customerAddressController.clear();
        _contactNumberController.clear();
        _nationalIDController.clear();
        _storePhoneNumberController.clear();
        _buildingInfoController.clear();
        _apartmentNumberController.clear();
        _deliveryInstructionsController.clear();
        _message = "";
      });
    }
  }

  Future<void> _showStoreCategoryPicker() async {
    if (kIsWeb) {
      await _showHtmlNativeStorePicker();
      return;
    }
    _showMaterialStorePicker();
  }

  Future<void> _showHtmlNativeStorePicker() async {
    // Use Material picker for all platforms
    await _showMaterialStorePicker();
  }

  Future<void> _showMaterialStorePicker() async {
    await showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Select Store Type'),
        children: StoreCategories.all.map((c) => SimpleDialogOption(
          child: Text(c),
          onPressed: () {
            setState(() => _storeTypeController.text = c);
            Navigator.pop(context);
          },
        )).toList(),
      ),
    );
  }

  void _navigateToHomeScreen() {
    if (!mounted) return;

    if (widget.popOnSuccess) {
      Navigator.of(context).pop(true);
      return;
    }

    final authManager = Provider.of<AuthManager>(context, listen: false);
    final userType = authManager.userProfile?['userType'] as String?;
    final storeName = authManager.userProfile?['name'] as String? ?? 'Store';
    final displayName = authManager.userProfile?['display_name'] as String? ?? 'Driver';
    
    // إذا كان صاحب متجر → اذهب إلى StoreAdminView
    if (userType == 'storeOwner') {
      debugPrint(' Store Owner detected - redirecting to StoreAdminView');
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => StoreAdminView(initialStoreName: storeName),
        ),
      );
    } 
    // إذا كان صاحب توصيل → اذهب إلى DeliveryHomeView
    else if (userType == 'deliveryDriver') {
      debugPrint('🚗 Delivery Driver detected - redirecting to DeliveryHomeView');
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => DeliveryHomeView(driverName: displayName)),
      );
    } 
    // وإلا → اذهب إلى الصفحة الرئيسية للزبون
    else {
      debugPrint(' Regular customer detected - redirecting to CategoryHomeView');
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const CategoryHomeView()),
      );
    }
  }

  // Auth Methods
  void _login() async {
    if (_isLoading) return;
    setState(() { _isLoading = true; _message = ""; });

    try {
      final authManager = Provider.of<AuthManager>(context, listen: false);
      
      // First try delivery driver login, if that fails try regular login
      try {
        await authManager.deliveryLogin(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      } catch (deliveryError) {
        // If delivery login fails, try regular login
        await authManager.signIn(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      }
      
      if (mounted) _navigateToHomeScreen();
    } catch (e) {
      if (mounted) _showError(e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleGoogleSignIn() async {
    if (_isLoading) return;
    setState(() { _isLoading = true; _message = ""; });

    try {
      final authManager = Provider.of<AuthManager>(context, listen: false);
      final result = await authManager.signInWithGoogle();

      if (!mounted) return;
      if (result['success'] != true) {
        // User closed the Google picker — not an error, just do nothing.
        setState(() => _isLoading = false);
        return;
      }

      if (result['needsProfileCompletion'] == true) {
        if (widget.popOnSuccess) {
          final completed = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => CompleteProfileView(popOnSuccess: true)),
          );
          if (completed == true && mounted) Navigator.of(context).pop(true);
        } else {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const CompleteProfileView()),
          );
        }
      } else {
        _navigateToHomeScreen();
      }
    } catch (e) {
      if (mounted) _showError(e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _signUpCustomer() async {
    if (_isLoading) return;
    setState(() { _isLoading = true; _message = ""; });

    if (_passwordController.text != _confirmPasswordController.text) {
      setState(() => _isLoading = false);
      _showError("Passwords do not match.");
      return;
    }

    try {
      final authManager = Provider.of<AuthManager>(context, listen: false);
      await authManager.register(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
        displayName: '${_nameController.text.trim()} ${_surnameController.text.trim()}',
        phone: _contactNumberController.text.trim(),
        nationalId: _nationalIDController.text.trim(),
        address: _customerAddressController.text.trim(),
        latitude: _latitude != 0.0 ? _latitude : null,
        longitude: _longitude != 0.0 ? _longitude : null,
        buildingInfo: _buildingInfoController.text.trim(),
        apartmentNumber: _apartmentNumberController.text.trim(),
        deliveryInstructions: _deliveryInstructionsController.text.trim(),
      );

      if (mounted) {
        setState(() => _showSignUp = false);
        _resetFormFieldsKeepCredentials();
        _showSuccess("✓ Account created!\n\nGo check your email now to verify before logging in.");
      }
    } catch (e) {
      if (mounted) _showError(e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _storeOwnerLogin() async {
    if (_isLoading) return;
    setState(() { _isLoading = true; _message = ""; });
    
    try {
      final authManager = Provider.of<AuthManager>(context, listen: false);
      // Use new storeLogin() method instead of generic signIn()
      await authManager.storeLogin(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      
      if (mounted) _navigateToHomeScreen();
    } catch (e) {
      if (mounted) _showError(e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _requestStoreOwnerAccount() async {
    if (_isLoading) return;
    setState(() { _isLoading = true; _message = ""; });

    if (_passwordController.text != _confirmPasswordController.text) {
      setState(() => _isLoading = false);
      _showError("Passwords do not match.");
      return;
    }

    if (_storeNameController.text.isEmpty) {
      setState(() => _isLoading = false);
      _showError("Store name is required.");
      return;
    }

    if (_storeTypeController.text.isEmpty) {
      setState(() => _isLoading = false);
      _showError("Store type is required.");
      return;
    }

    if (_addressController.text.isEmpty || _latitude == 0.0 || _longitude == 0.0) {
      setState(() => _isLoading = false);
      _showError("Store location is required.");
      return;
    }

    try {
      final authManager = Provider.of<AuthManager>(context, listen: false);
      await authManager.storeSignup(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
        storeName: _storeNameController.text.trim(),
        storeType: _storeTypeController.text.trim(),
        phone: _storePhoneNumberController.text.trim(),
        address: _addressController.text.trim(),
        latitude: _latitude,
        longitude: _longitude,
      );

      if (mounted) {
        // Reset loading immediately — leaving it true here is what made the
        // login button spin forever once the view switched back to login.
        setState(() {
          _isLoading = false;
          _isNewStoreOwner = false;
        });
        // Keep email/password so the user isn't forced to retype them on
        // the login form they're about to land on.
        _resetFormFieldsKeepCredentials();
        _showSuccess(
          "✓ Account created!\n\nGo check your email now to verify your store before logging in.",
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showError(e.toString().replaceAll('Exception: ', ''));
      }
    }
  }

  Widget _buildCurrentForm(bool isDark) {
    if (_isStoreOwner) {
      return Column(
        children: [
          SignInUIComponents.storeOwnerSectionHeader(
            isNewStoreOwner: _isNewStoreOwner,
            onToggleNewStoreOwner: () => setState(() => _isNewStoreOwner = !_isNewStoreOwner),
            isDark: isDark,
          ),
          if (_isNewStoreOwner)
            Column(
              children: [
                SignInUIComponents.requestStoreOwnerForm(
                  storeNameController: _storeNameController,
                  storeTypeController: _storeTypeController,
                  addressController: _addressController,
                  phoneController: _storePhoneNumberController,
                  emailController: _emailController,
                  passwordController: _passwordController,
                  confirmPasswordController: _confirmPasswordController,
                  onSelectStoreType: _showStoreCategoryPicker,
                  onSelectMap: _showMapPickerForStoreOwner,
                  onRequest: _requestStoreOwnerAccount,
                  isLoading: _isLoading,
                  context: context,
                ),
                SignInUIComponents.prestigeButton(
                  title: "BACK",
                  action: () => setState(() => _isNewStoreOwner = false),
                  isLoading: false,
                  isDark: isDark,
                  isPrimary: false,
                  leadingIcon: Icons.arrow_back_rounded,
                ),
              ],
            )
          else
            Column(
              children: [
                SignInUIComponents.loginStoreOwnerForm(
                  emailController: _emailController,
                  passwordController: _passwordController,
                  onLogin: _storeOwnerLogin,
                  isLoading: _isLoading,
                  context: context,
                ),
                const SizedBox(height: 15),
                InkWell(
                  onTap: () => setState(() { _isNewStoreOwner = true; }),
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withOpacity(0.04) : Colors.white.withOpacity(0.72),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.08)),
                    ),
                    child: const Text("New Store Owner?", style: TextStyle(fontSize: 14)),
                  ),
                ),
                const SizedBox(height: 10),
                InkWell(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (c) => const DeliverySignupView())),
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withOpacity(0.04) : Colors.white.withOpacity(0.72),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.08)),
                    ),
                    child: const Text("Become a Delivery Driver", style: TextStyle(fontSize: 14), textAlign: TextAlign.center),
                  ),
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (c) => const Admin.AdminLoginView())),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black87,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  ),
                  child: const Text("Admin Login"),
                ),
              ],
            ),
        ],
      );
    } else {
      return Column(
        children: [
          if (_showSignUp)
            SignInUIComponents.signUpCustomerForm(
              nameController: _nameController,
              surnameController: _surnameController,
              nationalIdController: _nationalIDController,
              phoneController: _contactNumberController,
              addressController: _customerAddressController,
              buildingInfoController: _buildingInfoController,
              apartmentNumberController: _apartmentNumberController,
              deliveryInstructionsController: _deliveryInstructionsController,
              emailController: _emailController,
              passwordController: _passwordController,
              confirmPasswordController: _confirmPasswordController,
              onSelectMap: _showMapPickerForSignup,
              onSignUp: _signUpCustomer,
              isLoading: _isLoading,
              context: context,
            )
          else
            Column(
              children: [
                SignInUIComponents.loginCustomerForm(
                  emailController: _emailController,
                  passwordController: _passwordController,
                  onLogin: _login,
                  isLoading: _isLoading,
                  context: context,
                ),
                SignInUIComponents.googleSignInDivider(isDark: isDark),
                SignInUIComponents.googleSignInButton(
                  onTap: _handleGoogleSignIn,
                  isLoading: _isLoading,
                  isDark: isDark,
                ),
              ],
            ),
          const SizedBox(height: 20),
          SignInUIComponents.toggleSignUpLoginButton(
            showSignUp: _showSignUp,
            onToggle: () { setState(() { _showSignUp = !_showSignUp; }); },
            isDark: isDark,
          ),
          const SizedBox(height: 10),
          SignInUIComponents.toggleOwnershipButton(
            isStoreOwner: _isStoreOwner,
            onToggle: () { setState(() { _isStoreOwner = true; }); },
            isDark: isDark,
          ),
        ],
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeManager = Provider.of<ThemeManager>(context);
    final isDark = themeManager.isDarkMode;
    
    final backgroundColor = isDark ? const Color(0xFF0A0A0A) : const Color(0xFFF5F5F5);

    return Scaffold(
      backgroundColor: backgroundColor,
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          HapticFeedback.lightImpact(); // لمسة خفيفة
          final themeManager = Provider.of<ThemeManager>(context, listen: false);
          themeManager.switchTheme();
        },
        backgroundColor: const Color(0xFF42A5F5),
        child: Icon(
          isDark ? Icons.light_mode : Icons.dark_mode,
          color: Colors.white,
        ),
      ),
      body: Stack(
        children: [
          // Elegant gradient background
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark 
                  ? [const Color(0xFF0A0A0A), const Color(0xFF1A1A1A)]
                  : [const Color(0xFFF5F5F5), const Color(0xFFE8E8E8)],
              ),
            ),
          ),

          // Main content
          Center(
            child: LayoutBuilder(
              builder: (context, constraints) {
                bool isWide = constraints.maxWidth > 1000;

                if (isWide) {
                  return Row(
                    children: [
                      // Left: Brand Panel
                      Expanded(
                        flex: 5,
                        child: FadeTransition(
                          opacity: _fadeAnimation,
                          child: Padding(
                            padding: const EdgeInsets.all(60),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // Brand tag
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1E88E5).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: const Color(0xFF1E88E5).withOpacity(0.3),
                                    ),
                                  ),
                                  child: const Text(
                                    "YSHOP PLATFORM",
                                    style: TextStyle(
                                      color: Color(0xFF1E88E5),
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.5,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 32),
                                
                                // Main heading
                                Text(
                                  _isStoreOwner 
                                    ? (_isNewStoreOwner ? "Join as Partner" : "Store Access")
                                    : (_showSignUp ? "Create Account" : "Welcome Back"),
                                  style: TextStyle(
                                    fontSize: 56,
                                    fontWeight: FontWeight.w900,
                                    color: isDark ? Colors.white : Colors.black87,
                                    height: 1.1,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                
                                // Description
                                Text(
                                  "Seamless shopping experience.\nSecure authentication.\nElegant interface design.",
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: isDark ? Colors.grey[400] : Colors.grey[700],
                                    height: 1.6,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // Right: Form Panel (Glass Card)
                      Expanded(
                        flex: 4,
                        child: FadeTransition(
                          opacity: _fadeAnimation,
                          child: Padding(
                            padding: const EdgeInsets.all(30),
                            child: Center(
                              child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 420),
                                child: _buildGlassCard(isDark),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                } else {
                  // Mobile layout
                  return SingleChildScrollView(
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                        child: Column(
                          children: [
                            FadeTransition(
                              opacity: _fadeAnimation,
                              child: _buildMobileIntro(isDark),
                            ),
                            const SizedBox(height: 18),
                            FadeTransition(
                              opacity: _fadeAnimation,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 460),
                                child: _buildGlassCard(isDark, isMobile: true),
                              ),
                            ),
                            const SizedBox(height: 28),
                          ],
                        ),
                      ),
                    ),
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileIntro(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  Colors.white.withOpacity(0.06),
                  Colors.white.withOpacity(0.03),
                ]
              : [
                  Colors.white.withOpacity(0.9),
                  Colors.white.withOpacity(0.75),
                ],
        ),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF1E88E5).withOpacity(0.12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0xFF1E88E5).withOpacity(0.28)),
            ),
            child: const Text(
              'YSHOP PLATFORM',
              style: TextStyle(
                color: Color(0xFF1E88E5),
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            _isStoreOwner
                ? (_isNewStoreOwner ? 'Join as Partner' : 'Store Access')
                : (_showSignUp ? 'Create Account' : 'Welcome Back'),
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w800,
              height: 1.0,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            "Seamless shopping experience.",
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: isDark ? Colors.white.withOpacity(0.62) : Colors.black.withOpacity(0.55),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassCard(bool isDark, {bool isMobile = false}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(isMobile ? 22 : 16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: isMobile ? 18 : 10, sigmaY: isMobile ? 18 : 10),
        child: Container(
          decoration: BoxDecoration(
            color: isDark
              ? Colors.white.withOpacity(0.05)
              : Colors.white,
            borderRadius: BorderRadius.circular(isMobile ? 22 : 16),
            border: Border.all(
              color: isDark
                ? Colors.white.withOpacity(0.1)
                : Colors.grey.shade300,
            ),
            boxShadow: isDark
              ? []
              : [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  )
                ],
          ),
          child: Padding(
            padding: EdgeInsets.all(isMobile ? 20 : 30),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // WelcomingPageShimmer with animation
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: Padding(
                      padding: EdgeInsets.only(bottom: isMobile ? 14 : 20),
                      child: Transform.scale(
                        scale: isMobile ? 0.76 : 1.0,
                        alignment: Alignment.topCenter,
                        child: const WelcomingPageShimmer(),
                      ),
                    ),
                  ),
                  
                  SizedBox(height: isMobile ? 6 : 10),

                  // Forms with smooth animation
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(animation),
                        child: child,
                      ),
                    ),
                    child: KeyedSubtree(
                      key: ValueKey("$_isStoreOwner$_showSignUp$_isNewStoreOwner"),
                      child: _buildCurrentForm(isDark),
                    ),
                  ),

                SizedBox(height: isMobile ? 12 : 15),
                  SignInUIComponents.messageDisplay(message: _message, isDark: isDark),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
