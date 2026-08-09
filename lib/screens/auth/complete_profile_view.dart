// lib/screens/auth/complete_profile_view.dart
//
// Shown right after a first-time Google sign-in (or any account that's
// otherwise missing required fields). This is a hard gate, not a nag
// screen — no back button, no "skip" option. The session already has a
// valid JWT at this point (Google sign-in itself succeeded), but the
// account isn't considered fully set up — matching the same required
// fields the email/password signup form collects — until this is
// submitted successfully.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:latlong2/latlong.dart';

import '../../services/api_service.dart';
import '../../state_management/auth_manager.dart';
import '../../widgets/map_picker_sheet.dart';
import 'sign_in_ui.dart';
import '../customers/category_home_view.dart';

class CompleteProfileView extends StatefulWidget {
  /// When true, a successful save pops back to the caller with `true`
  /// instead of navigating to CategoryHomeView itself — used when this
  /// screen is reached mid-way through some other in-progress action
  /// (e.g. a guest's add-to-cart login detour) that needs to resume.
  final bool popOnSuccess;
  const CompleteProfileView({super.key, this.popOnSuccess = false});

  @override
  State<CompleteProfileView> createState() => _CompleteProfileViewState();
}

class _CompleteProfileViewState extends State<CompleteProfileView> {
  final _nameController = TextEditingController();
  final _surnameController = TextEditingController();
  final _nationalIdController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _buildingInfoController = TextEditingController();
  final _apartmentNumberController = TextEditingController();
  final _deliveryInstructionsController = TextEditingController();

  double _latitude = 0.0;
  double _longitude = 0.0;
  bool _isLoading = false;
  String _message = '';

  @override
  void initState() {
    super.initState();
    // Pre-fill whatever Google already gave us (display name), so the user
    // isn't retyping something the sign-in already provided.
    final profile = Provider.of<AuthManager>(context, listen: false).userProfile;
    final name = profile?['name'] as String?;
    final surname = profile?['surname'] as String?;
    if (name != null && name.isNotEmpty) _nameController.text = name;
    if (surname != null && surname.isNotEmpty) _surnameController.text = surname;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _surnameController.dispose();
    _nationalIdController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _buildingInfoController.dispose();
    _apartmentNumberController.dispose();
    _deliveryInstructionsController.dispose();
    super.dispose();
  }

  Future<void> _pickLocation() async {
    const defaultLat = 41.0082;
    const defaultLng = 28.9784;
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => MapPickerSheet(
          initialCoordinate: LatLng(_latitude != 0.0 ? _latitude : defaultLat, _longitude != 0.0 ? _longitude : defaultLng),
        ),
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

  Future<void> _submit() async {
    if (_isLoading) return;

    final name = _nameController.text.trim();
    final surname = _surnameController.text.trim();
    final nationalId = _nationalIdController.text.trim();
    final phone = _phoneController.text.trim();
    final address = _addressController.text.trim();

    if (name.isEmpty || surname.isEmpty || nationalId.isEmpty || phone.isEmpty || address.isEmpty) {
      setState(() => _message = 'Please fill in all required fields before continuing.');
      return;
    }

    setState(() { _isLoading = true; _message = ''; });
    try {
      final response = await ApiService.putRequest('/users/profile', {
        'displayName': '$name $surname',
        'surname': surname,
        'phone': phone,
        'nationalId': nationalId,
        'address': address,
        'latitude': _latitude != 0.0 ? _latitude : null,
        'longitude': _longitude != 0.0 ? _longitude : null,
        'buildingInfo': _buildingInfoController.text.trim(),
        'apartmentNumber': _apartmentNumberController.text.trim(),
        'deliveryInstructions': _deliveryInstructionsController.text.trim(),
      });

      if (response != null && response['success'] == true) {
        if (!mounted) return;
        final authManager = Provider.of<AuthManager>(context, listen: false);
        await authManager.refreshProfile();
        if (!mounted) return;
        if (widget.popOnSuccess) {
          Navigator.of(context).pop(true);
        } else {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const CategoryHomeView()),
          );
        }
        return;
      }
      throw Exception(response?['message'] ?? 'Failed to save your details');
    } catch (e) {
      if (mounted) setState(() => _message = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = LuxuryTheme.isDark(context);
    return PopScope(
      // Hard gate — no dismissing this without completing it. The account
      // is real (Google auth already succeeded) but not fully usable yet.
      canPop: false,
      child: Scaffold(
        backgroundColor: isDark ? LuxuryTheme.kDarkBackground : LuxuryTheme.kLightBackground,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'One last step',
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'We need a few more details before your account is ready.',
                      style: TextStyle(fontSize: 14, color: (isDark ? Colors.white : Colors.black).withOpacity(0.6)),
                    ),
                    const SizedBox(height: 28),
                    SignInUIComponents.luxuryInput(placeholder: 'NAME', controller: _nameController, isDark: isDark),
                    SignInUIComponents.luxuryInput(placeholder: 'SURNAME', controller: _surnameController, isDark: isDark),
                    SignInUIComponents.luxuryInput(placeholder: 'NATIONAL ID / RESIDENCY', controller: _nationalIdController, isDark: isDark, keyboardType: TextInputType.number),
                    SignInUIComponents.luxuryInput(placeholder: 'PHONE NUMBER', controller: _phoneController, isDark: isDark, keyboardType: TextInputType.phone),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: _pickLocation,
                      child: AbsorbPointer(
                        child: SignInUIComponents.luxuryInput(
                          placeholder: 'ADDRESS (TAP TO PICK ON MAP)',
                          controller: _addressController,
                          isDark: isDark,
                        ),
                      ),
                    ),
                    SignInUIComponents.luxuryInput(placeholder: 'BUILDING NAME (NUMBER)', controller: _buildingInfoController, isDark: isDark),
                    SignInUIComponents.luxuryInput(placeholder: 'APARTMENT NUMBER', controller: _apartmentNumberController, isDark: isDark),
                    SignInUIComponents.luxuryInput(placeholder: 'DELIVERY INSTRUCTIONS', controller: _deliveryInstructionsController, isDark: isDark),
                    if (_message.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(_message, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                    ],
                    const SizedBox(height: 20),
                    SignInUIComponents.prestigeButton(title: 'CONTINUE', action: _submit, isLoading: _isLoading, isDark: isDark),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
