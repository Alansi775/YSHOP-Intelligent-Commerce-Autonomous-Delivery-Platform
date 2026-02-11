// lib/screens/stores/store_settings_view.dart - DJI STYLE
// Clean, minimal, elegant settings page

import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../services/api_service.dart';
import '../../state_management/auth_manager.dart';
import '../../widgets/map_picker_sheet.dart';
import 'package:latlong2/latlong.dart';
import '../../models/store.dart';

class StoreSettingsView extends StatefulWidget {
  const StoreSettingsView({super.key});

  @override
  State<StoreSettingsView> createState() => _StoreSettingsViewState();
}

class _StoreSettingsViewState extends State<StoreSettingsView> {
  static const String _baseUrl = 'http://localhost:3000/api/v1';

  String? _storeIconUrl;
  File? _pickedImage;
  XFile? _pickedXFile;
  double _latitude = 0.0;
  double _longitude = 0.0;
  bool _isLoading = false;
  bool _isFetching = true;
  String? _storeId;

  @override
  void initState() {
    super.initState();
    _fetchStoreData();
  }

  void _showMapPicker() async {
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

    if (result != null && _storeId != null) {
      try {
        final lat = result['latitude'] as double;
        final lng = result['longitude'] as double;
        setState(() {
          _latitude = lat;
          _longitude = lng;
        });
        await ApiService.updateStoreLocation(_storeId!, latitude: lat, longitude: lng);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location saved'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _fetchStoreData() async {
    setState(() => _isFetching = true);
    try {
      final storeData = await ApiService.getUserStore();
      if (storeData != null) {
        final store = Store.fromJson(storeData);
        setState(() {
          _storeId = store.id;
          _storeIconUrl = store.storeIconUrl.isNotEmpty ? store.storeIconUrl : null;
          try {
            final lat = storeData['latitude'];
            final lng = storeData['longitude'];
            if (lat != null) _latitude = lat is num ? lat.toDouble() : double.tryParse(lat.toString()) ?? 0.0;
            if (lng != null) _longitude = lng is num ? lng.toDouble() : double.tryParse(lng.toString()) ?? 0.0;
          } catch (_) {}
        });
      }
    } catch (e) {
      debugPrint('Error: $e');
    } finally {
      setState(() => _isFetching = false);
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
      maxWidth: 500,
      maxHeight: 500,
    );

    if (pickedFile != null) {
      setState(() {
        _pickedXFile = pickedFile;
        if (!kIsWeb) {
          _pickedImage = File(pickedFile.path);
        }
      });
    }
  }

  Future<String?> _uploadImageToBackend() async {
    if (_storeId == null || (_pickedImage == null && _pickedXFile == null)) {
      return null;
    }

    try {
      final fileBytes = kIsWeb
          ? await _pickedXFile!.readAsBytes()
          : await _pickedImage!.readAsBytes();

      final fileName = 'store_icon_${DateTime.now().millisecondsSinceEpoch}.jpg';

      var request = http.MultipartRequest(
        'PUT',
        Uri.parse('$_baseUrl/stores/$_storeId'),
      );

      final authManager = Provider.of<AuthManager>(context, listen: false);
      final token = authManager.token;
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      request.files.add(
        http.MultipartFile.fromBytes(
          'icon',
          fileBytes,
          filename: fileName,
        ),
      );

      var streamedResponse = await request.send().timeout(
        const Duration(seconds: 30),
      );
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final iconUrl = data['data']?['icon_url'] as String?;
        
        if (iconUrl != null && iconUrl.isNotEmpty) {
          final fullUrl = iconUrl.startsWith('http') 
              ? iconUrl 
              : 'http://localhost:3000$iconUrl';
          return fullUrl;
        }
      }
      return null;
    } catch (e) {
      debugPrint('Error: $e');
      return null;
    }
  }

  Future<void> _saveStoreIcon() async {
    final isNewImageSelected = _pickedImage != null || _pickedXFile != null;
    if (!isNewImageSelected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Select an icon first")),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final newIconUrl = await _uploadImageToBackend();

      if (newIconUrl == null) {
        throw Exception("Upload failed");
      }

      setState(() {
        _storeIconUrl = newIconUrl;
        _pickedImage = null;
        _pickedXFile = null;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Icon saved'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 900;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(
            Icons.arrow_back,
            color: Colors.white.withOpacity(0.7),
          ),
        ),
        title: const Text(
          'Settings',
          style: TextStyle(
            fontFamily: 'TenorSans',
            fontSize: 18,
            fontWeight: FontWeight.w400,
            color: Colors.white,
            letterSpacing: -0.2,
          ),
        ),
        centerTitle: true,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: isDesktop ? 80 : 32,
              vertical: 48,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Store Icon
                _buildStoreIconDisplay(),
                
                const SizedBox(height: 48),
                
                // Upload Button
                _buildActionButton(
                  label: 'Choose Icon',
                  icon: Icons.photo_camera_outlined,
                  onTap: _isLoading ? null : _pickImage,
                  isSecondary: true,
                ),
                
                const SizedBox(height: 16),
                
                // Save Button
                _buildActionButton(
                  label: _isLoading ? 'Saving...' : 'Save Icon',
                  icon: _isLoading ? null : Icons.check,
                  onTap: (_pickedImage == null && _pickedXFile == null) || _isLoading
                      ? null
                      : _saveStoreIcon,
                  isLoading: _isLoading,
                ),
                
                const SizedBox(height: 64),
                
                // Location Section
                _buildLocationSection(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStoreIconDisplay() {
    const double size = 140;

    Widget imageWidget;

    if (_isFetching) {
      imageWidget = SizedBox(
        width: size,
        height: size,
        child: Center(
          child: SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white.withOpacity(0.3),
            ),
          ),
        ),
      );
    } else if (_pickedImage != null || _pickedXFile != null) {
      imageWidget = kIsWeb
          ? Image.network(
              _pickedXFile!.path,
              fit: BoxFit.cover,
              width: size,
              height: size,
            )
          : Image.file(
              _pickedImage!,
              fit: BoxFit.cover,
              width: size,
              height: size,
            );
    } else if (_storeIconUrl != null && _storeIconUrl!.isNotEmpty) {
      imageWidget = CachedNetworkImage(
        imageUrl: _storeIconUrl!,
        fit: BoxFit.cover,
        width: size,
        height: size,
        placeholder: (context, url) => SizedBox(
          width: size,
          height: size,
          child: Center(
            child: SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white.withOpacity(0.3),
              ),
            ),
          ),
        ),
        errorWidget: (context, url, error) => Icon(
          Icons.store,
          size: size * 0.5,
          color: Colors.white.withOpacity(0.15),
        ),
      );
    } else {
      imageWidget = Icon(
        Icons.store,
        size: size * 0.5,
        color: Colors.white.withOpacity(0.15),
      );
    }

    return Center(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.02),
          border: Border.all(
            color: Colors.white.withOpacity(0.08),
            width: 2,
          ),
        ),
        child: ClipOval(child: imageWidget),
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    IconData? icon,
    VoidCallback? onTap,
    bool isSecondary = false,
    bool isLoading = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isSecondary
              ? Colors.transparent
              : Colors.white.withOpacity(onTap == null ? 0.03 : 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Colors.white.withOpacity(onTap == null ? 0.04 : 0.12),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white.withOpacity(0.7),
                ),
              )
            else if (icon != null)
              Icon(
                icon,
                color: Colors.white.withOpacity(onTap == null ? 0.3 : 0.7),
                size: 20,
              ),
            if (icon != null || isLoading) const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'TenorSans',
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: Colors.white.withOpacity(onTap == null ? 0.3 : 0.9),
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationSection() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.06),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Store Location',
            style: TextStyle(
              fontFamily: 'TenorSans',
              fontSize: 18,
              fontWeight: FontWeight.w400,
              color: Colors.white,
              letterSpacing: -0.3,
            ),
          ),
          
          const SizedBox(height: 16),
          
          Text(
            _latitude == 0.0 && _longitude == 0.0
                ? 'No location set'
                : 'Lat: ${_latitude.toStringAsFixed(4)}, Lng: ${_longitude.toStringAsFixed(4)}',
            style: TextStyle(
              fontFamily: 'TenorSans',
              fontSize: 13,
              color: Colors.white.withOpacity(0.45),
            ),
          ),
          
          const SizedBox(height: 20),
          
          GestureDetector(
            onTap: _showMapPicker,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withOpacity(0.10),
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.location_on_outlined,
                    color: Colors.white.withOpacity(0.7),
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Set Location',
                    style: TextStyle(
                      fontFamily: 'TenorSans',
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withOpacity(0.9),
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}