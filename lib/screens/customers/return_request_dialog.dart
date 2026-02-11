// lib/screens/customers/return_request_dialog.dart - DJI STYLE
// Clean, simple, elegant return request flow

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import '../../services/api_service.dart';

class ReturnRequestDialog extends StatefulWidget {
  final int orderId;
  final Map<String, dynamic> orderData;
  final VoidCallback onSuccess;

  const ReturnRequestDialog({
    Key? key,
    required this.orderId,
    required this.orderData,
    required this.onSuccess,
  }) : super(key: key);

  @override
  State<ReturnRequestDialog> createState() => _ReturnRequestDialogState();
}

class _ReturnRequestDialogState extends State<ReturnRequestDialog> {
  late PageController _pageController;
  int _currentStep = 0;
  
  final TextEditingController _reasonController = TextEditingController();
  final Map<String, XFile?> _photos = {
    'top': null,
    'bottom': null,
    'left': null,
    'right': null,
    'front': null,
    'back': null,
  };

  bool _isSubmitting = false;
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(String photoType) async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
      
      if (image != null) {
        setState(() => _photos[photoType] = image);
      }
    } catch (e) {
      _showMessage('Error: $e', isError: true);
    }
  }

  Future<void> _submitReturn() async {
    if (_reasonController.text.trim().length < 10) {
      _showMessage('Reason must be at least 10 characters', isError: true);
      return;
    }

    if (_photos.values.where((photo) => photo != null).length < 6) {
      _showMessage('Please provide all 6 photos', isError: true);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final response = await ApiService.submitReturnRequest(
        orderId: widget.orderId,
        reason: _reasonController.text.trim(),
        photos: _photos,
      );

      if (response['success'] == true && mounted) {
        Navigator.pop(context);
        widget.onSuccess();
        _showMessage('Return request submitted');
      } else {
        _showMessage(response['message'] ?? 'Error submitting', isError: true);
      }
    } catch (e) {
      _showMessage('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError 
            ? Colors.red.withOpacity(0.9) 
            : Colors.green.withOpacity(0.9),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF0A0A0A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (page) => setState(() => _currentStep = page),
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildReasonStep(),
                  _buildPhotosStep(),
                  _buildReviewStep(),
                ],
              ),
            ),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    const steps = ['Reason', 'Photos', 'Review'];
    
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withOpacity(0.05),
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Request Return',
                style: TextStyle(
                  fontFamily: 'TenorSans',
                  fontSize: 24,
                  fontWeight: FontWeight.w300,
                  color: Colors.white,
                  letterSpacing: -0.5,
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.close,
                    color: Colors.white.withOpacity(0.7),
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 24),
          
          // Progress Dots
          Row(
            children: List.generate(3, (index) {
              return Expanded(
                child: Container(
                  margin: EdgeInsets.only(
                    right: index < 2 ? 8 : 0,
                  ),
                  height: 3,
                  decoration: BoxDecoration(
                    color: index <= _currentStep
                        ? Colors.white
                        : Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
          
          const SizedBox(height: 12),
          
          Text(
            'Step ${_currentStep + 1}: ${steps[_currentStep]}',
            style: TextStyle(
              fontFamily: 'TenorSans',
              fontSize: 13,
              color: Colors.white.withOpacity(0.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReasonStep() {
    final reasonLength = _reasonController.text.length;
    final isValid = reasonLength >= 10;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Why are you returning this?',
            style: TextStyle(
              fontFamily: 'TenorSans',
              fontSize: 18,
              fontWeight: FontWeight.w400,
              color: Colors.white,
            ),
          ),
          
          const SizedBox(height: 12),
          
          Text(
            'Please provide a detailed reason',
            style: TextStyle(
              fontFamily: 'TenorSans',
              fontSize: 14,
              color: Colors.white.withOpacity(0.5),
            ),
          ),
          
          const SizedBox(height: 32),
          
          TextField(
            controller: _reasonController,
            maxLines: 8,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(
              fontFamily: 'TenorSans',
              fontSize: 14,
              color: Colors.white,
            ),
            decoration: InputDecoration(
              hintText: 'Describe the issue or reason for return...',
              hintStyle: TextStyle(
                fontFamily: 'TenorSans',
                color: Colors.white.withOpacity(0.3),
              ),
              filled: true,
              fillColor: Colors.white.withOpacity(0.03),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Colors.white.withOpacity(0.08),
                  width: 1,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Colors.white.withOpacity(0.08),
                  width: 1,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: isValid ? Colors.green.withOpacity(0.5) : Colors.white.withOpacity(0.2),
                  width: 1.5,
                ),
              ),
              contentPadding: const EdgeInsets.all(16),
            ),
          ),
          
          const SizedBox(height: 12),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Minimum 10 characters',
                style: TextStyle(
                  fontFamily: 'TenorSans',
                  fontSize: 12,
                  color: Colors.white.withOpacity(0.3),
                ),
              ),
              Text(
                '$reasonLength/10',
                style: TextStyle(
                  fontFamily: 'TenorSans',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isValid ? Colors.green : Colors.white.withOpacity(0.3),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPhotosStep() {
    final photoLabels = {
      'top': 'Top',
      'bottom': 'Bottom',
      'left': 'Left',
      'right': 'Right',
      'front': 'Front',
      'back': 'Back',
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Take 6 Photos',
            style: TextStyle(
              fontFamily: 'TenorSans',
              fontSize: 18,
              fontWeight: FontWeight.w400,
              color: Colors.white,
            ),
          ),
          
          const SizedBox(height: 12),
          
          Text(
            'Capture all angles of the product',
            style: TextStyle(
              fontFamily: 'TenorSans',
              fontSize: 14,
              color: Colors.white.withOpacity(0.5),
            ),
          ),
          
          const SizedBox(height: 32),
          
          GridView.count(
            crossAxisCount: 2,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: _photos.entries.map((entry) {
              final isComplete = entry.value != null;
              
              return GestureDetector(
                onTap: () => _pickImage(entry.key),
                child: Container(
                  decoration: BoxDecoration(
                    color: isComplete
                        ? Colors.green.withOpacity(0.05)
                        : Colors.white.withOpacity(0.03),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isComplete
                          ? Colors.green.withOpacity(0.3)
                          : Colors.white.withOpacity(0.08),
                      width: 1.5,
                    ),
                  ),
                  child: Stack(
                    children: [
                      if (isComplete && entry.value != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: FutureBuilder<Uint8List>(
                            future: entry.value!.readAsBytes(),
                            builder: (context, snapshot) {
                              if (snapshot.hasData) {
                                return Image.memory(
                                  snapshot.data!,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  height: double.infinity,
                                );
                              }
                              return Container(
                                color: Colors.grey.shade800,
                              );
                            },
                          ),
                        )
                      else
                        Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.camera_alt_outlined,
                                size: 32,
                                color: Colors.white.withOpacity(0.3),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Tap to capture',
                                style: TextStyle(
                                  fontFamily: 'TenorSans',
                                  fontSize: 11,
                                  color: Colors.white.withOpacity(0.3),
                                ),
                              ),
                            ],
                          ),
                        ),
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.7),
                            borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(12),
                              bottomRight: Radius.circular(12),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                photoLabels[entry.key]!,
                                style: const TextStyle(
                                  fontFamily: 'TenorSans',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white,
                                ),
                              ),
                              if (isComplete)
                                const Icon(
                                  Icons.check_circle,
                                  size: 16,
                                  color: Colors.green,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewStep() {
    final photoCount = _photos.values.where((p) => p != null).length;
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Review & Confirm',
            style: TextStyle(
              fontFamily: 'TenorSans',
              fontSize: 18,
              fontWeight: FontWeight.w400,
              color: Colors.white,
            ),
          ),
          
          const SizedBox(height: 32),
          
          _buildReviewItem('Return Reason', _reasonController.text.trim()),
          const SizedBox(height: 16),
          _buildReviewItem('Photos', '$photoCount / 6'),
          
          const SizedBox(height: 32),
          
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.amber.withOpacity(0.2),
                width: 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  color: Colors.amber.shade300,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Your return request will be reviewed within 24-48 hours',
                    style: TextStyle(
                      fontFamily: 'TenorSans',
                      fontSize: 13,
                      color: Colors.amber.shade300,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewItem(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withOpacity(0.06),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: 'TenorSans',
              fontSize: 13,
              color: Colors.white.withOpacity(0.5),
            ),
          ),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(
                fontFamily: 'TenorSans',
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    final canProceed = _currentStep == 0
        ? _reasonController.text.trim().length >= 10
        : _currentStep == 1
            ? _photos.values.where((p) => p != null).length == 6
            : true;

    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: Colors.white.withOpacity(0.05),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          if (_currentStep > 0)
            Expanded(
              child: GestureDetector(
                onTap: () => _pageController.previousPage(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.1),
                      width: 1.5,
                    ),
                  ),
                  child: const Center(
                    child: Text(
                      'Back',
                      style: TextStyle(
                        fontFamily: 'TenorSans',
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (_currentStep > 0) const SizedBox(width: 16),
          Expanded(
            child: GestureDetector(
              onTap: canProceed
                  ? () {
                      if (_currentStep < 2) {
                        _pageController.nextPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      } else {
                        _submitReturn();
                      }
                    }
                  : null,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: canProceed
                      ? (_currentStep == 2 ? Colors.green.withOpacity(0.9) : Colors.white.withOpacity(0.9))
                      : Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : Text(
                          _currentStep < 2 ? 'Next' : 'Submit Request',
                          style: const TextStyle(
                            fontFamily: 'TenorSans',
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Colors.black,
                          ),
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