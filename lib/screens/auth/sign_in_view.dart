import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'dart:html' as html show document, SelectElement, OptionElement;
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
import '../delivery/delivery_signup_view.dart';
import '../delivery/delivery_home_view.dart';
import '../stores/store_admin_view.dart';
import 'admin_login_view.dart' as Admin;
import 'sign_in_ui.dart';

class SignInView extends StatefulWidget {
  const SignInView({super.key});

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
    final defaultLat = 24.7136;
    final defaultLng = 46.6753;

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
    final defaultLat = 24.7136;
    final defaultLng = 46.6753;

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
    try {
      final select = html.SelectElement();
      select.style.position = 'fixed';
      select.style.top = '50%';
      select.style.left = '50%';
      select.style.transform = 'translate(-50%, -50%)';
      select.style.width = '280px';
      select.style.height = '45px';
      select.style.padding = '10px 12px';
      select.style.fontSize = '15px';
      select.style.borderRadius = '10px';
      select.style.border = '1px solid #444';
      select.style.backgroundColor = '#2c2c2e';
      select.style.color = '#fff';
      select.style.zIndex = '99999';
      
      final emptyOption = html.OptionElement()..value = ''..text = 'Select Store Type'..disabled = true;
      select.append(emptyOption);
      
      for (final category in StoreCategories.all) {
        final option = html.OptionElement()..value = category..text = category;
        select.append(option);
      }
      
      select.selectedIndex = 0;
      html.document.body!.append(select);
      
      bool handled = false;
      select.onChange.listen((event) {
        if (!handled) {
          handled = true;
          final selected = select.value;
          select.remove();
          if (selected != null && selected.isNotEmpty && mounted) {
            setState(() => _storeTypeController.text = selected);
          }
        }
      });
      
      select.onBlur.listen((event) {
        if (!handled) {
          handled = true;
          if (select.parent != null) select.remove();
        }
      });
      
      select.click();
    } catch (e) {
      _showMaterialStorePicker();
    }
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
      if (mounted) setState(() => _message = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _signUpCustomer() async {
    if (_isLoading) return;
    setState(() { _isLoading = true; _message = ""; });

    if (_passwordController.text != _confirmPasswordController.text) {
      setState(() { _message = "Passwords do not match."; _isLoading = false; });
      return;
    }

    try {
      final authManager = Provider.of<AuthManager>(context, listen: false);
      await authManager.register(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
        displayName: '${_nameController.text} ${_surnameController.text}',
        phone: _contactNumberController.text.trim(),
        name: _nameController.text.trim(),
        surname: _surnameController.text.trim(),
        nationalId: _nationalIDController.text.trim(),
        address: _customerAddressController.text.trim(),
        latitude: _latitude,
        longitude: _longitude,
        buildingInfo: _buildingInfoController.text.trim(),
        apartmentNumber: _apartmentNumberController.text.trim(),
        deliveryInstructions: _deliveryInstructionsController.text.trim(),
      );

      if (mounted) {
        setState(() => _message = "✓ Account created. Verify your email.");
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() {
              _showSignUp = false;
              _resetFormFields();
            });
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _message = e.toString().replaceAll('Exception: ', ''));
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
      if (mounted) setState(() => _message = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _requestStoreOwnerAccount() async {
    if (_isLoading) return;
    setState(() { _isLoading = true; _message = ""; });

    if (_passwordController.text != _confirmPasswordController.text) {
      setState(() { _message = "Passwords do not match."; _isLoading = false; });
      return;
    }

    if (_storeNameController.text.isEmpty) {
      setState(() { _message = "Store name is required."; _isLoading = false; });
      return;
    }

    if (_storeTypeController.text.isEmpty) {
      setState(() { _message = "Store type is required."; _isLoading = false; });
      return;
    }

    if (_addressController.text.isEmpty || _latitude == 0.0 || _longitude == 0.0) {
      setState(() { _message = "Store location is required."; _isLoading = false; });
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
        setState(() => _message = "✓ Store application submitted. Verify your email and wait for admin approval.");
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() {
              _isNewStoreOwner = false;
              _resetFormFields();
            });
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() { _message = e.toString().replaceAll('Exception: ', ''); _isLoading = false; });
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
                TextButton(
                  onPressed: () => setState(() => _isNewStoreOwner = false),
                  child: Text("Back", style: TextStyle(color: isDark ? Colors.grey : Colors.grey.shade600)),
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
                TextButton(
                  onPressed: () => setState(() { _isNewStoreOwner = true; }),
                  child: const Text("New Store Owner?", style: TextStyle(fontSize: 14)),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (c) => const DeliverySignupView())),
                  child: const Text("Become a Delivery Driver", style: TextStyle(fontSize: 14)),
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (c) => const Admin.AdminLoginView())),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black87,
                    foregroundColor: Colors.white,
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
            SignInUIComponents.loginCustomerForm(
              emailController: _emailController,
              passwordController: _passwordController,
              onLogin: _login,
              isLoading: _isLoading,
              context: context,
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
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          const SizedBox(height: 20),
                          FadeTransition(
                            opacity: _fadeAnimation,
                            child: _buildGlassCard(isDark),
                          ),
                          const SizedBox(height: 40),
                        ],
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

  Widget _buildGlassCard(bool isDark) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: isDark
              ? Colors.white.withOpacity(0.05)
              : Colors.white,
            borderRadius: BorderRadius.circular(16),
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
            padding: const EdgeInsets.all(30),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // WelcomingPageShimmer with animation
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: const Padding(
                      padding: EdgeInsets.only(bottom: 20),
                      child: WelcomingPageShimmer(),
                    ),
                  ),
                  
                  const SizedBox(height: 10),

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

                const SizedBox(height: 15),
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
