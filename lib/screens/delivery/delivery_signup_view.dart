import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import 'package:provider/provider.dart';
import '../../state_management/theme_manager.dart';
import '../../widgets/map_picker_sheet.dart';
import '../auth/sign_in_ui.dart';
import 'package:latlong2/latlong.dart';


class DeliverySignupView extends StatefulWidget {
  const DeliverySignupView({super.key});

  @override
  State<DeliverySignupView> createState() => _DeliverySignupViewState();
}

class _DeliverySignupViewState extends State<DeliverySignupView> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _nationalIDController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  
  // Location variables
  double _latitude = 0.0;
  double _longitude = 0.0;
  
  bool _isLoading = false;
  String _message = "";

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _nationalIDController.dispose();
    _addressController.dispose();
    super.dispose();
  }
  
  void _showMapPicker() async {
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

    if (result != null) {
      setState(() {
        _latitude = result['latitude'] as double;
        _longitude = result['longitude'] as double;
        _addressController.text = result['address'] as String? ?? 'Location Selected';
      });
    }
  }

  void _requestDriverAccount() async {
    if (_isLoading) return;
    
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty ||
        _nameController.text.isEmpty || _phoneController.text.isEmpty ||
        _latitude == 0.0 || _longitude == 0.0) {
      _showDriverMessage("Please fill in all required fields including location.");
      return;
    }

    // تحقق من تطابق كلمة المرور
    if (_passwordController.text != _confirmPasswordController.text) {
      _showDriverMessage("Passwords do not match.");
      return;
    }

    setState(() {
      _isLoading = true;
      _message = "";
    });

    try {
      final response = await ApiService.deliverySignup(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
      );

      if (mounted) {
        setState(() => _isLoading = false);
        _showDriverMessage(
          "✓ Account created!\n\nGo check your email now to verify before you can log in.",
          isSuccess: true,
          onDismiss: () {
            if (mounted && Navigator.canPop(context)) Navigator.pop(context);
          },
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showDriverMessage("Error: ${e.toString()}");
      }
    } finally {
      if (mounted && _isLoading) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Centered dialog instead of the old bottom-of-form text, which required
  /// scrolling to see on this long form.
  void _showDriverMessage(String message, {bool isSuccess = false, VoidCallback? onDismiss}) {
    if (!mounted) return;
    SignInUIComponents.showMessageDialog(
      context,
      message: message,
      isDark: LuxuryTheme.isDark(context),
      isSuccess: isSuccess,
      onDismiss: onDismiss,
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeManager = Provider.of<ThemeManager>(context);
    final isDark = themeManager.isDarkMode;
    
    final backgroundColor = isDark ? const Color(0xFF0A0A0A) : const Color(0xFFF5F5F5);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Stack(
        children: [
          // Background
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [const Color(0xFF0A0A0A), const Color(0xFF1A1A1A)]
                    : [const Color(0xFFF5F5F5), const Color(0xFFEEEEEE)],
              ),
            ),
          ),
          
          // Content
          SingleChildScrollView(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: Padding(
                  padding: const EdgeInsets.all(30.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      Padding(
                        padding: const EdgeInsets.only(top: 40.0, bottom: 30.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "DELIVERY PARTNER",
                              style: TextStyle(
                                color: LuxuryTheme.kLightBlueAccent,
                                letterSpacing: 3,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              "Join Our Team",
                              style: TextStyle(
                                color: isDark ? Colors.white : Colors.black,
                                fontSize: 32,
                                fontFamily: 'Didot',
                                fontWeight: FontWeight.w300,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Form Card
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
                            border: Border.all(
                              color: isDark ? Colors.white10 : Colors.black12,
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: isDark 
                                    ? Colors.black.withOpacity(0.3) 
                                    : Colors.black.withOpacity(0.05),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              )
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(32.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Full Name
                                SignInUIComponents.luxuryInput(
                                  placeholder: "FULL NAME",
                                  controller: _nameController,
                                  isDark: isDark,
                                ),

                                // Phone
                                SignInUIComponents.luxuryInput(
                                  placeholder: "PHONE NUMBER",
                                  controller: _phoneController,
                                  keyboardType: TextInputType.phone,
                                  isDark: isDark,
                                ),

                                // National ID
                                SignInUIComponents.luxuryInput(
                                  placeholder: "NATIONAL ID",
                                  controller: _nationalIDController,
                                  keyboardType: TextInputType.number,
                                  isDark: isDark,
                                ),

                                // Location Picker
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 15),
                                  child: SignInUIComponents.prestigeButton(
                                    title: _addressController.text.isEmpty 
                                        ? "PICK ON MAP" 
                                        : "📍 ${_addressController.text}",
                                    action: _showMapPicker,
                                    isLoading: false,
                                    isDark: isDark,
                                    isPrimary: false,
                                    leadingIcon: Icons.location_on
                                  ),
                                ),

                                // Email
                                SignInUIComponents.luxuryInput(
                                  placeholder: "EMAIL ADDRESS",
                                  controller: _emailController,
                                  keyboardType: TextInputType.emailAddress,
                                  isDark: isDark,
                                ),

                                // Password
                                SignInUIComponents.luxuryInput(
                                  placeholder: "CREATE PASSWORD",
                                  controller: _passwordController,
                                  isSecure: true,
                                  isDark: isDark,
                                ),

                                // Confirm Password
                                SignInUIComponents.luxuryInput(
                                  placeholder: "CONFIRM PASSWORD",
                                  controller: _confirmPasswordController,
                                  isSecure: true,
                                  onSubmitted: (_) => _requestDriverAccount(),
                                  isDark: isDark,
                                ),

                                const SizedBox(height: 10),

                                // Submit Button
                                SignInUIComponents.prestigeButton(
                                  title: "SUBMIT",
                                  action: _requestDriverAccount,
                                  isLoading: _isLoading,
                                  isDark: isDark,
                                ),

                                SignInUIComponents.prestigeButton(
                                  title: "BACK",
                                  action: () => Navigator.maybePop(context),
                                  isLoading: false,
                                  isDark: isDark,
                                  isPrimary: false,
                                  leadingIcon: Icons.arrow_back_rounded,
                                ),

                                // Message Display
                                SignInUIComponents.messageDisplay(
                                  message: _message,
                                  isDark: isDark,
                                ),

                                const SizedBox(height: 20),
                              ],
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}