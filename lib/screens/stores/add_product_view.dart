import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../../services/api_service.dart';
import '../../widgets/multi_media_picker.dart';
import '../../models/currency.dart';
import '../../state_management/auth_manager.dart';

class AddProductView extends StatefulWidget {
  const AddProductView({super.key});

  @override
  State<AddProductView> createState() => _AddProductViewState();
}

class _AddProductViewState extends State<AddProductView> {
  final _formKey = GlobalKey<FormState>();
  static const String _currencyPrefKey = 'store_add_product_currency_code';
  
  // Controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _stockController = TextEditingController();

  List<MediaItem> _selectedMedia = [];
  bool _isLoading = false;
  Currency? _selectedCurrency;
  bool _isLoadingSavedCurrency = true;

  // --- Theme Colors (Modern & Minimalist) ---
  final Color _bgDark = const Color(0xFF121212); // خلفية أصلية
  final Color _surfaceColor = const Color(0xFF1E1E1E); // لون الكروت
  final Color _accentColor = const Color(0xFF2979FF); // أزرق كهربائي عصري (بديل البنفسجي)
  final Color _textPrimary = Colors.white;
  final Color _textSecondary = const Color(0xFF9E9E9E);

  // --- Logic (Same as before) ---
  @override
  void initState() {
    super.initState();
    _loadSavedCurrency();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedCurrency() async {
    final prefs = await SharedPreferences.getInstance();
    final savedCode = prefs.getString(_currencyPrefKey);

    if (!mounted) return;

    setState(() {
      _selectedCurrency = savedCode == null ? null : Currency.fromCode(savedCode);
      _isLoadingSavedCurrency = false;
    });
  }

  Future<void> _saveSelectedCurrency(Currency currency) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_currencyPrefKey, currency.code);
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate() || _selectedMedia.isEmpty) {
      _showSnack("Please fill required fields & add an image", isError: true);
      return;
    }

    if (_selectedCurrency == null) {
      _showSnack("Please select a currency", isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final authManager = Provider.of<AuthManager>(context, listen: false);
      final uid = authManager.userProfile?['uid'] as String?;
      
      if (uid == null) throw Exception("User not logged in.");

      final storeResponse = await ApiService.getUserStore(uid: uid);
      final storeId = storeResponse?['id'] ?? 1;

      final productData = {
        "name": _nameController.text.trim(),
        "description": _descriptionController.text.trim(),
        "price": double.tryParse(_priceController.text.trim()) ?? 0.0,
        "stock": int.parse(_stockController.text.trim()),
        "storeId": storeId,
        "currencyId": _selectedCurrency!.id,
        "currencyCode": _selectedCurrency!.code,
      };

      final firstImageMedia = _selectedMedia.firstWhere((m) => !m.isVideo);
      final imageFile = kIsWeb ? firstImageMedia.fileNative : firstImageMedia.fileWeb;
      
      await ApiService.createProductWithImage(productData, imageFile as dynamic);

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) _showSnack("Error: ${e.toString()}", isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white)),
        backgroundColor: isError ? Colors.redAccent : _accentColor,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Custom Input Style
    final inputDecoration = InputDecoration(
      filled: true,
      fillColor: Colors.transparent, // Glass effect
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 0),
      hintStyle: TextStyle(color: _textSecondary.withOpacity(0.5), fontWeight: FontWeight.w300, fontSize: 16),
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
    );

    return Scaffold(
      backgroundColor: _bgDark,
      // Minimal App Bar
      appBar: AppBar(
        backgroundColor: _bgDark,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "Create Product",
          style: TextStyle(color: _textPrimary, fontWeight: FontWeight.w300, fontSize: 18),
        ),
        centerTitle: true,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            physics: const BouncingScrollPhysics(),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  
                  // --- 1. Product Name (SwiftUI Style) ---
                  _buildSectionTitle("PRODUCT DETAILS"),
                  const SizedBox(height: 10),
                  Container(
                    decoration: _modernBoxDecoration(),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _nameController,
                          style: TextStyle(color: _textPrimary, fontSize: 18, fontWeight: FontWeight.w400),
                          cursorColor: _accentColor,
                          decoration: inputDecoration.copyWith(
                            hintText: "Product Name",
                            labelText: "Name",
                            labelStyle: TextStyle(color: _textSecondary),
                            floatingLabelBehavior: FloatingLabelBehavior.auto,
                          ),
                          validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                        ),
                        Divider(color: _textSecondary.withOpacity(0.1), height: 1),
                        TextFormField(
                          controller: _descriptionController,
                          style: TextStyle(color: _textPrimary, fontSize: 16, fontWeight: FontWeight.w300),
                          cursorColor: _accentColor,
                          maxLines: 3,
                          decoration: inputDecoration.copyWith(
                            hintText: "Describe your product...",
                            labelText: "Description",
                            labelStyle: TextStyle(color: _textSecondary),
                            floatingLabelBehavior: FloatingLabelBehavior.auto,
                            alignLabelWithHint: true,
                          ),
                          validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 30),

                  // --- 2. Price & Currency (Clean Row) ---
                  _buildSectionTitle("PRICING"),
                  const SizedBox(height: 10),
                  Container(
                    decoration: _modernBoxDecoration(),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
                    child: Row(
                      children: [
                        // Currency "Pill" - Minimalist
                        Expanded(
                          flex: 2,
                          child: Theme(
                            data: Theme.of(context).copyWith(canvasColor: _surfaceColor),
                            child: DropdownButtonFormField<Currency>(
                              value: _selectedCurrency,
                              isExpanded: true,
                              icon: Icon(Icons.keyboard_arrow_down_rounded, color: _accentColor, size: 18),
                              dropdownColor: _surfaceColor,
                              style: TextStyle(color: _textPrimary, fontSize: 16, fontWeight: FontWeight.w500),
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                isDense: true,
                              ),
                              hint: Text(
                                "Select currency",
                                style: TextStyle(color: _textSecondary.withOpacity(0.8), fontSize: 16),
                              ),
                              items: Currency.getAll().map((c) {
                                return DropdownMenuItem(
                                  value: c,
                                  child: Text("${c.code} (${c.symbol})"),
                                );
                              }).toList(),
                              validator: (v) => v == null ? 'Required' : null,
                              onChanged: (v) {
                                if (v == null) return;
                                setState(() => _selectedCurrency = v);
                                _saveSelectedCurrency(v);
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 15),
                        Container(width: 1, height: 30, color: _textSecondary.withOpacity(0.2)),
                        const SizedBox(width: 15),
                        // Price Input
                        Expanded(
                          child: TextFormField(
                            controller: _priceController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            style: TextStyle(color: _textPrimary, fontSize: 20, fontWeight: FontWeight.w300),
                            cursorColor: _accentColor,
                            decoration: inputDecoration.copyWith(
                              hintText: "0.00",
                            ),
                            validator: (v) {
                              final value = v?.trim() ?? '';
                              if (value.isEmpty) return 'Required';
                              if (double.tryParse(value) == null || double.parse(value) <= 0) {
                                return 'Enter a valid price';
                              }
                              return null;
                            },
                            onChanged: (_) => setState(() {}), // Trigger rebuild to update revenue breakdown
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // --- Revenue Breakdown Display ---
                  _buildRevenueBreakdown(),

                  const SizedBox(height: 30),

                  // --- 3. Inventory (Modern Counter) ---
                  _buildSectionTitle("INVENTORY"),
                  const SizedBox(height: 10),
                  Container(
                    decoration: _modernBoxDecoration(),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("Stock Available", 
                          style: TextStyle(color: _textPrimary, fontSize: 16, fontWeight: FontWeight.w400)),
                        
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: _textSecondary.withOpacity(0.2)),
                          ),
                          child: Row(
                            children: [
                              _buildIconButton(Icons.remove, () {
                                int val = int.tryParse(_stockController.text) ?? 1;
                                if (val > 1) _stockController.text = (val - 1).toString();
                              }),
                              SizedBox(
                                width: 40,
                                child: TextFormField(
                                  controller: _stockController,
                                  textAlign: TextAlign.center,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                  style: TextStyle(color: _textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                                  decoration: const InputDecoration(
                                    border: InputBorder.none,
                                    isDense: true,
                                    hintText: '1',
                                  ),
                                  validator: (v) {
                                    final value = v?.trim() ?? '';
                                    final parsed = int.tryParse(value);
                                    if (value.isEmpty) return 'Required';
                                    if (parsed == null || parsed <= 0) return 'Invalid';
                                    return null;
                                  },
                                ),
                              ),
                              _buildIconButton(Icons.add, () {
                                int val = int.tryParse(_stockController.text) ?? 0;
                                _stockController.text = (val + 1).toString();
                              }),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 30),

                  // --- 4. Media (Clean Grid) ---
                  _buildSectionTitle("MEDIA"),
                  const SizedBox(height: 10),
                  Container(
                    decoration: _modernBoxDecoration(),
                    padding: const EdgeInsets.all(20),
                    child: MultiMediaPicker(
                      onMediaSelected: (media) => setState(() => _selectedMedia = media),
                      maxImages: 4,
                      allowVideo: true,
                      maxVideoDurationSeconds: 40,
                    ),
                  ),

                  const SizedBox(height: 40),

                  // --- Submit Button ---
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _saveProduct,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accentColor,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text(
                              "Publish Product",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.5,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- Helper Widgets ---

  // Stylish small header (SwiftUI List Section style)
  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: TextStyle(
          color: _textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  // The modern "Glass/Card" effect
  BoxDecoration _modernBoxDecoration() {
    return BoxDecoration(
      color: _surfaceColor,
      borderRadius: BorderRadius.circular(16),
      // Very subtle border to define edges without looking "boxy"
      border: Border.all(color: Colors.white.withOpacity(0.05)),
    );
  }

  Widget _buildIconButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Icon(icon, size: 18, color: _textPrimary),
      ),
    );
  }

  // 💰 Revenue Breakdown Widget
  Widget _buildRevenueBreakdown() {
    final double price = double.tryParse(_priceController.text) ?? 0.0;

    // This is your price exactly as entered — fees are added ON TOP for
    // the customer, never deducted from what you typed. Must match
    // backend src/utils/pricing.js.
    const double platformFeeRate = 0.25; // always
    const double deliveryFeeRate = 0.10; // online orders only

    final inStorePrice = price * (1 + platformFeeRate);
    final onlinePrice = price * (1 + platformFeeRate + deliveryFeeRate);
    final symbol = _selectedCurrency?.symbol ?? '';

    if (price <= 0) {
      return Container(
        decoration: _modernBoxDecoration(),
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Text(
            "Enter a price to see what customers will pay",
            style: TextStyle(color: _textSecondary, fontSize: 13, fontStyle: FontStyle.italic),
          ),
        ),
      );
    }

    Widget row({required Color color, required String title, required String subtitle, required double amount}) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 4,
                  height: 20,
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(color: _textSecondary, fontSize: 12)),
                    Text(subtitle, style: TextStyle(color: _textSecondary.withOpacity(0.7), fontSize: 11)),
                  ],
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withOpacity(0.5)),
              ),
              child: Text(
                "$symbol${amount.toStringAsFixed(2)}",
                style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: _modernBoxDecoration(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "What customers will pay",
            style: TextStyle(color: _textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          row(
            color: Colors.green.shade500,
            title: "Your earning",
            subtitle: "Exactly what you entered — always yours",
            amount: price,
          ),
          row(
            color: Colors.blue.shade500,
            title: "In-store / dine-in price",
            subtitle: "No delivery fee — no driver involved",
            amount: inStorePrice,
          ),
          const SizedBox(height: 4),
          Divider(color: _textSecondary.withOpacity(0.2)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Online price (delivery)",
                style: TextStyle(color: _textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
              ),
              Text(
                "$symbol${onlinePrice.toStringAsFixed(2)}",
                style: TextStyle(color: _textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
        ],
      ),
    );
  }
}