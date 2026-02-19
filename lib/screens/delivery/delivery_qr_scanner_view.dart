// lib/screens/delivery_qr_scanner_view.dart
// ═══════════════════════════════════════════════════════════════════════════════
//  QR SCANNER VIEW - Scan order QR at store pickup
// ═══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 📷 QR SCANNER VIEW
// ─────────────────────────────────────────────────────────────────────────────

class QRScannerView extends StatefulWidget {
  final String orderId;
  final Color kDarkBackground;
  final Color kCardBackground;
  final Color kAppBarBackground;
  final Color kPrimaryTextColor;
  final Color kSecondaryTextColor;
  final Color kAccentBlue;
  final VoidCallback onScanSuccess;

  const QRScannerView({
    super.key,
    required this.orderId,
    required this.kDarkBackground,
    required this.kCardBackground,
    required this.kAppBarBackground,
    required this.kPrimaryTextColor,
    required this.kSecondaryTextColor,
    required this.kAccentBlue,
    required this.onScanSuccess,
  });

  @override
  State<QRScannerView> createState() => _QRScannerViewState();
}

class _QRScannerViewState extends State<QRScannerView> with SingleTickerProviderStateMixin {
  MobileScannerController? _scannerController;
  bool _hasScanned = false;
  bool _isFlashOn = false;
  String? _errorMessage;
  
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _initScanner();
    _initAnimation();
  }

  void _initScanner() {
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
  }

  void _initAnimation() {
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    
    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _scannerController?.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasScanned) return;
    
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;
    
    final String? scannedValue = barcodes.first.rawValue;
    if (scannedValue == null) return;

    debugPrint(' Scanned: $scannedValue');
    debugPrint(' Expected Order ID: ${widget.orderId}');

    // Check if scanned value matches order ID
    // Support multiple formats: just ID, "ORDER-ID", or full JSON
    bool isMatch = false;
    
    if (scannedValue == widget.orderId) {
      isMatch = true;
    } else if (scannedValue == 'ORDER-${widget.orderId}') {
      isMatch = true;
    } else if (scannedValue.contains(widget.orderId)) {
      isMatch = true;
    }
    
    // Also try parsing as number if orderId is numeric
    if (!isMatch) {
      try {
        final scannedNum = int.tryParse(scannedValue);
        final orderNum = int.tryParse(widget.orderId);
        if (scannedNum != null && orderNum != null && scannedNum == orderNum) {
          isMatch = true;
        }
      } catch (_) {}
    }

    if (isMatch) {
      setState(() => _hasScanned = true);
      HapticFeedback.heavyImpact();
      _showSuccessAndProceed();
    } else {
      HapticFeedback.lightImpact();
      setState(() {
        _errorMessage = 'QR code does not match this order';
      });
      
      // Clear error after 3 seconds
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _errorMessage = null);
      });
    }
  }

  void _showSuccessAndProceed() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: widget.kCardBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle, color: Colors.green, size: 60),
            ),
            const SizedBox(height: 20),
            Text(
              "QR Verified!",
              style: TextStyle(
                color: widget.kPrimaryTextColor,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Order pickup confirmed.\nHead to the customer!",
              textAlign: TextAlign.center,
              style: TextStyle(color: widget.kSecondaryTextColor),
            ),
          ],
        ),
      ),
    );

    // Auto proceed after 1.5 seconds
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) {
        Navigator.of(context).pop(); // Close dialog
        widget.onScanSuccess();
      }
    });
  }

  void _toggleFlash() {
    _scannerController?.toggleTorch();
    setState(() => _isFlashOn = !_isFlashOn);
  }

  void _switchCamera() {
    _scannerController?.switchCamera();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: widget.kDarkBackground,
      appBar: AppBar(
        title: const Text('Scan Order QR', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: widget.kAppBarBackground,
        foregroundColor: widget.kPrimaryTextColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(_isFlashOn ? Icons.flash_on : Icons.flash_off),
            onPressed: _toggleFlash,
          ),
          IconButton(
            icon: const Icon(Icons.cameraswitch),
            onPressed: _switchCamera,
          ),
        ],
      ),
      body: Stack(
        children: [
          // Scanner
          if (_scannerController != null)
            MobileScanner(
              controller: _scannerController!,
              onDetect: _onDetect,
            ),
          
          // Overlay
          _buildScannerOverlay(),
          
          // Instructions
          _buildInstructions(),
          
          // Error message
          if (_errorMessage != null)
            _buildErrorMessage(),
        ],
      ),
    );
  }

  Widget _buildScannerOverlay() {
    return Container(
      decoration: ShapeDecoration(
        shape: QRScannerOverlayShape(
          borderColor: widget.kAccentBlue,
          borderRadius: 16,
          borderLength: 40,
          borderWidth: 6,
          cutOutSize: 280,
          overlayColor: Colors.black.withOpacity(0.7),
        ),
      ),
      child: Center(
        child: SizedBox(
          width: 280,
          height: 280,
          child: Stack(
            children: [
              // Animated scan line
              AnimatedBuilder(
                animation: _animation,
                builder: (context, child) {
                  return Positioned(
                    top: _animation.value * 260 + 10,
                    left: 10,
                    right: 10,
                    child: Container(
                      height: 2,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            widget.kAccentBlue,
                            widget.kAccentBlue,
                            Colors.transparent,
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: widget.kAccentBlue.withOpacity(0.5),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInstructions() {
    return Positioned(
      bottom: 80,
      left: 32,
      right: 32,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: widget.kCardBackground.withOpacity(0.95),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: widget.kAccentBlue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.qr_code, color: widget.kAccentBlue, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Scan Store QR Code",
                        style: TextStyle(
                          color: widget.kPrimaryTextColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "Point camera at the order QR code",
                        style: TextStyle(
                          color: widget.kSecondaryTextColor,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.grey.shade800,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.tag, color: widget.kSecondaryTextColor, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    "Order #${widget.orderId}",
                    style: TextStyle(
                      color: widget.kSecondaryTextColor,
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorMessage() {
    return Positioned(
      top: 100,
      left: 32,
      right: 32,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.9),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  QR SCANNER OVERLAY SHAPE
// ─────────────────────────────────────────────────────────────────────────────

class QRScannerOverlayShape extends ShapeBorder {
  final Color borderColor;
  final double borderWidth;
  final Color overlayColor;
  final double borderRadius;
  final double borderLength;
  final double cutOutSize;

  const QRScannerOverlayShape({
    this.borderColor = Colors.white,
    this.borderWidth = 3.0,
    this.overlayColor = Colors.black54,
    this.borderRadius = 12,
    this.borderLength = 30,
    this.cutOutSize = 250,
  });

  @override
  EdgeInsetsGeometry get dimensions => const EdgeInsets.all(0);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: rect.center,
            width: cutOutSize,
            height: cutOutSize,
          ),
          Radius.circular(borderRadius),
        ),
      );
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    return Path()
      ..addRect(rect)
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: rect.center,
            width: cutOutSize,
            height: cutOutSize,
          ),
          Radius.circular(borderRadius),
        ),
      )
      ..fillType = PathFillType.evenOdd;
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final paint = Paint()
      ..color = overlayColor
      ..style = PaintingStyle.fill;

    final cutOutRect = Rect.fromCenter(
      center: rect.center,
      width: cutOutSize,
      height: cutOutSize,
    );

    // Draw overlay
    canvas.drawPath(
      Path()
        ..addRect(rect)
        ..addRRect(RRect.fromRectAndRadius(cutOutRect, Radius.circular(borderRadius)))
        ..fillType = PathFillType.evenOdd,
      paint,
    );

    // Draw corner borders
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth
      ..strokeCap = StrokeCap.round;

    final double left = cutOutRect.left;
    final double top = cutOutRect.top;
    final double right = cutOutRect.right;
    final double bottom = cutOutRect.bottom;
    final double r = borderRadius;
    final double l = borderLength;

    // Top-left corner
    canvas.drawPath(
      Path()
        ..moveTo(left, top + l)
        ..lineTo(left, top + r)
        ..arcToPoint(Offset(left + r, top), radius: Radius.circular(r))
        ..lineTo(left + l, top),
      borderPaint,
    );

    // Top-right corner
    canvas.drawPath(
      Path()
        ..moveTo(right - l, top)
        ..lineTo(right - r, top)
        ..arcToPoint(Offset(right, top + r), radius: Radius.circular(r))
        ..lineTo(right, top + l),
      borderPaint,
    );

    // Bottom-left corner
    canvas.drawPath(
      Path()
        ..moveTo(left, bottom - l)
        ..lineTo(left, bottom - r)
        ..arcToPoint(Offset(left + r, bottom), radius: Radius.circular(r))
        ..lineTo(left + l, bottom),
      borderPaint,
    );

    // Bottom-right corner
    canvas.drawPath(
      Path()
        ..moveTo(right - l, bottom)
        ..lineTo(right - r, bottom)
        ..arcToPoint(Offset(right, bottom - r), radius: Radius.circular(r))
        ..lineTo(right, bottom - l),
      borderPaint,
    );
  }

  @override
  ShapeBorder scale(double t) {
    return QRScannerOverlayShape(
      borderColor: borderColor,
      borderWidth: borderWidth * t,
      overlayColor: overlayColor,
      borderRadius: borderRadius * t,
      borderLength: borderLength * t,
      cutOutSize: cutOutSize * t,
    );
  }
}