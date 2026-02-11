// settings_view.dart - TRUE DJI STYLE
// Ultra minimal, clean, elegant

import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import '../../services/api_service.dart';
import 'package:provider/provider.dart'; 
import 'package:latlong2/latlong.dart'; 

import '../../widgets/settings_widgets.dart'; 
import '../../widgets/map_picker_sheet.dart'; 
import '../../state_management/theme_manager.dart';
import '../../state_management/auth_manager.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({Key? key}) : super(key: key);

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  String _name = "";
  String _surname = "";
  String _address = "";
  String _contactNumber = "";
  String _nationalID = "";
  String _errorMessage = "";
  bool _isLoading = false;
  double _latitude = 0.0;
  double _longitude = 0.0;
  bool _isSuccessMessage = false;
  String _buildingInfo = "";
  String _apartmentNumber = "";
  String _deliveryInstructions = "";

  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _buildingController = TextEditingController();
  final TextEditingController _apartmentController = TextEditingController();
  final TextEditingController _instructionsController = TextEditingController();

  double _parseToDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  @override
  void initState() {
    super.initState();
    _fetchCustomerInfo();
  }
  
  void _updateControllers() {
    _addressController.text = _address;
    _buildingController.text = _buildingInfo;
    _apartmentController.text = _apartmentNumber;
    _instructionsController.text = _deliveryInstructions;
  }

  @override
  void dispose() {
    _addressController.dispose();
    _buildingController.dispose();
    _apartmentController.dispose();
    _instructionsController.dispose();
    super.dispose();
  }

  void _fetchCustomerInfo() async {
    final authManager = Provider.of<AuthManager>(context, listen: false);
    Map<String, dynamic>? cachedProfile = authManager.userProfile;
    
    if (cachedProfile != null && cachedProfile.containsKey('name')) {
      _updateProfileData(cachedProfile);
    }

    setState(() => _isLoading = true);
    try {
      Map<String, dynamic>? apiProfile = await ApiService.getUserProfile();
      
      if (apiProfile != null && mounted) {
        _updateProfileData(apiProfile);
        authManager.updateCachedProfile(apiProfile);
      } else {
        if (mounted) setState(() { _errorMessage = "Could not load profile"; });
      }
    } catch (e) {
      if (mounted) setState(() { _errorMessage = "Error: $e"; });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
  
  void _updateProfileData(Map<String, dynamic> profile) {
    if (!mounted) return;
    
    setState(() {
      final dn = (profile['display_name'] as String?) ?? (profile['displayName'] as String?) ?? "";
      _name = (profile['name'] as String?) ?? "";
      _surname = (profile['surname'] as String?) ?? "";

      if (_name.isEmpty) {
        final parts = dn.trim().split(RegExp(r'\s+'));
        if (parts.isNotEmpty) {
          _name = parts.first;
          if (_surname.isEmpty && parts.length > 1) {
            _surname = parts.last;
          }
        }
      }

      _address = (profile['address'] as String?) ?? "";
      _contactNumber = (profile['phone'] as String?) ?? "";
      _nationalID = (profile['national_id'] as String?) ?? "";
      _latitude = _parseToDouble(profile['latitude']);
      _longitude = _parseToDouble(profile['longitude']);
      _buildingInfo = (profile['building_info'] as String?) ?? (profile['buildingInfo'] as String?) ?? "";
      _apartmentNumber = (profile['apartment_number'] as String?) ?? (profile['apartmentNumber'] as String?) ?? "";
      _deliveryInstructions = (profile['delivery_instructions'] as String?) ?? (profile['deliveryInstructions'] as String?) ?? "";
    });
    _updateControllers();
  }

  void _updateAddress() async {
    setState(() { 
      _isLoading = true;
      _errorMessage = "";
      _isSuccessMessage = false;
    });

    try {
      final updatePayload = <String, dynamic>{};
      
      final displayName = _name.trim().isNotEmpty ? '$_name ${_surname.trim()}'.trim() : null;
      if (displayName != null) updatePayload['displayName'] = displayName;
      if (_surname.trim().isNotEmpty) updatePayload['surname'] = _surname.trim();
      if (_contactNumber.trim().isNotEmpty) updatePayload['phone'] = _contactNumber.trim();
      if (_addressController.text.trim().isNotEmpty) updatePayload['address'] = _addressController.text.trim();
      if (_latitude != 0.0) updatePayload['latitude'] = _latitude;
      if (_longitude != 0.0) updatePayload['longitude'] = _longitude;
      if (_nationalID.trim().isNotEmpty) updatePayload['nationalId'] = _nationalID.trim();
      if (_buildingController.text.trim().isNotEmpty) updatePayload['buildingInfo'] = _buildingController.text.trim();
      if (_apartmentController.text.trim().isNotEmpty) updatePayload['apartmentNumber'] = _apartmentController.text.trim();
      if (_instructionsController.text.trim().isNotEmpty) updatePayload['deliveryInstructions'] = _instructionsController.text.trim();
      
      await ApiService.updateUserProfile(
        displayName: updatePayload['displayName'] as String?,
        surname: updatePayload['surname'] as String?,
        phone: updatePayload['phone'] as String?,
        address: updatePayload['address'] as String?,
        latitude: updatePayload['latitude'] as double?,
        longitude: updatePayload['longitude'] as double?,
        nationalId: updatePayload['nationalId'] as String?,
        buildingInfo: updatePayload['buildingInfo'] as String?,
        apartmentNumber: updatePayload['apartmentNumber'] as String?,
        deliveryInstructions: updatePayload['deliveryInstructions'] as String?,
      );

      if (mounted) {
        setState(() {
          _errorMessage = "Saved successfully";
          _isSuccessMessage = true;
        });
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _errorMessage = "");
        });
      }
    } catch (e) {
      if (mounted) setState(() { _errorMessage = "Update failed: $e"; });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showMapPicker() async {
    final defaultLat = 24.7136; 
    final defaultLng = 46.6753;
    
    final initialCoordinate = LatLng(
        _latitude != 0.0 ? _latitude : defaultLat,
        _longitude != 0.0 ? _longitude : defaultLng
    );
    
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => MapPickerSheet(initialCoordinate: initialCoordinate),
      ),
    );

    if (result != null) {
      setState(() {
        _address = result['address'] as String;
        _latitude = result['latitude'] as double;
        _longitude = result['longitude'] as double;
        _addressController.text = _address; 
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeManager = Provider.of<ThemeManager>(context);
    final isDark = themeManager.isDarkMode;
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 900;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A0A0A) : const Color(0xFFFAFAFA),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // Minimal App Bar
          SliverAppBar(
            backgroundColor: isDark ? const Color(0xFF0A0A0A) : const Color(0xFFFAFAFA),
            elevation: 0,
            pinned: true,
            expandedHeight: 120,
            leading: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(
                  Icons.arrow_back_ios,
                  size: 20,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              centerTitle: false,
              titlePadding: EdgeInsets.only(
                left: isDesktop ? 80 : 60,
                bottom: 20,
              ),
              title: Text(
                'Settings',
                style: TextStyle(
                  fontFamily: 'TenorSans',
                  fontSize: 32,
                  fontWeight: FontWeight.w300,
                  color: isDark ? Colors.white : Colors.black,
                  letterSpacing: -0.5,
                ),
              ),
            ),
          ),

          // Content
          if (_isLoading && _name.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: isDark ? Colors.white.withOpacity(0.5) : Colors.black.withOpacity(0.5),
                ),
              ),
            )
          else
            SliverPadding(
              padding: EdgeInsets.symmetric(
                horizontal: isDesktop ? 80 : 24,
                vertical: 32,
              ),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 600),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Personal Info Section
                          _buildSection(
                            isDark,
                            'Personal Information',
                            [
                              _buildInfoRow(isDark, 'Name', '$_name $_surname'),
                              _buildInfoRow(isDark, 'Phone', _contactNumber),
                              _buildInfoRow(isDark, 'National ID', _nationalID),
                            ],
                          ),
                          
                          const SizedBox(height: 48),
                          
                          // Theme Section
                          _buildSection(
                            isDark,
                            'Appearance',
                            [_buildThemeToggle(isDark, themeManager)],
                          ),
                          
                          const SizedBox(height: 48),
                          
                          // Address Section
                          _buildSection(
                            isDark,
                            'Delivery Address',
                            [
                              _buildTextField(isDark, 'Address', _addressController, readOnly: true),
                              const SizedBox(height: 20),
                              _buildMapButton(isDark),
                              const SizedBox(height: 20),
                              _buildTextField(isDark, 'Building', _buildingController),
                              const SizedBox(height: 16),
                              _buildTextField(isDark, 'Apartment', _apartmentController),
                              const SizedBox(height: 16),
                              _buildTextField(isDark, 'Instructions', _instructionsController),
                            ],
                          ),
                          
                          if (_errorMessage.isNotEmpty) ...[
                            const SizedBox(height: 24),
                            Center(
                              child: Text(
                                _errorMessage,
                                style: TextStyle(
                                  fontFamily: 'TenorSans',
                                  fontSize: 13,
                                  color: _isSuccessMessage ? Colors.green : Colors.red,
                                ),
                              ),
                            ),
                          ],
                          
                          const SizedBox(height: 48),
                          
                          // Save Button
                          _buildSaveButton(isDark),
                        ],
                      ),
                    ),
                  ),
                ]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSection(bool isDark, String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontFamily: 'TenorSans',
            fontSize: 22,
            fontWeight: FontWeight.w500,  // كان 400 - أقوى!
            color: isDark ? Colors.white : Colors.black,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 20),  // كان 24 - أقرب شوي
        Container(
          padding: const EdgeInsets.all(28),  // كان 24 - أكبر
          decoration: BoxDecoration(
            color: isDark 
              ? Colors.white.withOpacity(0.04)  // كان 0.02 - أوضح!
              : Colors.white.withOpacity(0.75), // كان 0.6 - أبيض أكثر!
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark 
                ? Colors.white.withOpacity(0.10)  // كان 0.06 - أوضح!
                : Colors.black.withOpacity(0.10), // كان 0.06 - أوضح!
              width: 1.5,  // كان 1 - أسمك!
            ),
            boxShadow: [
              BoxShadow(
                color: isDark 
                  ? Colors.black.withOpacity(0.2)
                  : Colors.black.withOpacity(0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(bool isDark, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),  // كان 20 - أقرب شوي
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,  // كان 110 - أصغر شوي
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'TenorSans',
                fontSize: 14,
                fontWeight: FontWeight.w500,  // كان normal - أقوى!
                color: isDark 
                  ? Colors.white.withOpacity(0.55)  // كان 0.45 - أوضح!
                  : Colors.black.withOpacity(0.55), // كان 0.45 - أوضح!
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: TextStyle(
                fontFamily: 'TenorSans',
                fontSize: 15,  // كان 14 - أكبر!
                fontWeight: FontWeight.w600,  // كان 500 - أقوى!
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeToggle(bool isDark, ThemeManager themeManager) {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () {
              if (!isDark) themeManager.switchTheme();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 18),  // كان 16 - أكبر
              decoration: BoxDecoration(
                color: isDark 
                  ? Colors.white.withOpacity(0.12)  // كان 0.08 - أوضح!
                  : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark 
                    ? Colors.white.withOpacity(0.25)  // كان 0.15 - أقوى!
                    : Colors.black.withOpacity(0.12), // كان 0.08 - أقوى!
                  width: 1.5,  // كان 1 - أسمك!
                ),
              ),
              child: Center(
                child: Text(
                  'Dark',
                  style: TextStyle(
                    fontFamily: 'TenorSans',
                    fontSize: 15,  // كان 14 - أكبر
                    fontWeight: isDark ? FontWeight.w700 : FontWeight.w400,  // كان 600 - أقوى!
                    color: isDark 
                      ? Colors.white 
                      : Colors.black.withOpacity(0.35),  // كان 0.4 - أخف
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: GestureDetector(
            onTap: () {
              if (isDark) themeManager.switchTheme();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 18),  // كان 16 - أكبر
              decoration: BoxDecoration(
                color: !isDark 
                  ? Colors.black.withOpacity(0.06)  // كان 0.04 - أوضح!
                  : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: !isDark 
                    ? Colors.black.withOpacity(0.18)  // كان 0.12 - أقوى!
                    : Colors.white.withOpacity(0.12), // كان 0.08 - أقوى!
                  width: 1.5,  // كان 1 - أسمك!
                ),
              ),
              child: Center(
                child: Text(
                  'Light',
                  style: TextStyle(
                    fontFamily: 'TenorSans',
                    fontSize: 15,  // كان 14 - أكبر
                    fontWeight: !isDark ? FontWeight.w700 : FontWeight.w400,  // كان 600 - أقوى!
                    color: !isDark 
                      ? Colors.black 
                      : Colors.white.withOpacity(0.35),  // كان 0.4 - أخف
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTextField(bool isDark, String label, TextEditingController controller, {bool readOnly = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'TenorSans',
            fontSize: 13,
            fontWeight: FontWeight.w500,  // كان normal - أقوى!
            color: isDark 
              ? Colors.white.withOpacity(0.55)  // كان 0.45 - أوضح!
              : Colors.black.withOpacity(0.55), // كان 0.45 - أوضح!
          ),
        ),
        const SizedBox(height: 10),  // كان 8 - أكبر شوي
        TextField(
          controller: controller,
          readOnly: readOnly,
          style: TextStyle(
            fontFamily: 'TenorSans',
            fontSize: 15,  // كان 14 - أكبر!
            fontWeight: FontWeight.w500,  // أضفته!
            color: isDark ? Colors.white : Colors.black,
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor: isDark 
              ? Colors.white.withOpacity(0.05)  // كان 0.03 - أوضح!
              : Colors.black.withOpacity(0.03), // كان 0.02 - أوضح!
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: isDark 
                  ? Colors.white.withOpacity(0.15)  // كان 0.08 - أوضح!
                  : Colors.black.withOpacity(0.12), // كان 0.08 - أوضح!
                width: 1.5,  // كان 1 - أسمك!
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: isDark 
                  ? Colors.white.withOpacity(0.15)  // كان 0.08 - أوضح!
                  : Colors.black.withOpacity(0.12), // كان 0.08 - أوضح!
                width: 1.5,  // كان 1 - أسمك!
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: isDark 
                  ? Colors.white.withOpacity(0.35)  // كان 0.2 - أقوى!
                  : Colors.black.withOpacity(0.30), // كان 0.2 - أقوى!
                width: 2,  // كان 1 - أسمك!
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),  // كان 16, 14 - أكبر!
          ),
        ),
      ],
    );
  }

  Widget _buildMapButton(bool isDark) {
    return GestureDetector(
      onTap: _showMapPicker,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),  // كان 14 - أكبر
        decoration: BoxDecoration(
          color: isDark 
            ? Colors.white.withOpacity(0.08)  // كان 0.06 - أوضح!
            : Colors.black.withOpacity(0.06), // كان 0.04 - أوضح!
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark 
              ? Colors.white.withOpacity(0.18)  // كان 0.12 - أقوى!
              : Colors.black.withOpacity(0.15), // كان 0.08 - أقوى!
            width: 1.5,  // كان 1 - أسمك!
          ),
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.location_on_outlined,
                size: 20,  // كان 18 - أكبر
                color: isDark 
                  ? Colors.white.withOpacity(0.85)  // كان 0.7 - أوضح!
                  : Colors.black.withOpacity(0.85), // كان 0.7 - أوضح!
              ),
              const SizedBox(width: 10),  // كان 8 - أكبر
              Text(
                'Select Location',
                style: TextStyle(
                  fontFamily: 'TenorSans',
                  fontSize: 15,  // كان 14 - أكبر
                  fontWeight: FontWeight.w600,  // كان 500 - أقوى!
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSaveButton(bool isDark) {
    return GestureDetector(
      onTap: _isLoading ? null : _updateAddress,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),  // كان 16 - أكبر
        decoration: BoxDecoration(
          color: isDark 
            ? Colors.white.withOpacity(_isLoading ? 0.06 : 0.14)  // كان 0.05 : 0.1 - أوضح!
            : Colors.black.withOpacity(_isLoading ? 0.04 : 0.10), // كان 0.03 : 0.08 - أوضح!
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark 
              ? Colors.white.withOpacity(_isLoading ? 0.10 : 0.28)  // كان 0.08 : 0.2 - أقوى!
              : Colors.black.withOpacity(_isLoading ? 0.06 : 0.20), // كان 0.05 : 0.15 - أقوى!
            width: 1.5,  // كان 1 - أسمك!
          ),
        ),
        child: Center(
          child: _isLoading
            ? SizedBox(
                width: 22,  // كان 20 - أكبر
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,  // كان 2 - أسمك
                  color: isDark ? Colors.white : Colors.black,
                ),
              )
            : Text(
                'Save Changes',
                style: TextStyle(
                  fontFamily: 'TenorSans',
                  fontSize: 16,  // كان 15 - أكبر
                  fontWeight: FontWeight.w600,  // كان 500 - أقوى!
                  color: isDark ? Colors.white : Colors.black,
                  letterSpacing: 0.3,
                ),
              ),
        ),
      ),
    );
  }
}