import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:visionar/screens/home/model_core.dart';
import 'package:visionar/screens/home/models_screen.dart';

// TODO: adjust this import to wherever ModelRecord / ModelFullViewScreen
// actually live in your project (the file you pasted earlier).

class ScanQRScreen extends StatefulWidget {
  const ScanQRScreen({super.key});

  @override
  State<ScanQRScreen> createState() => _ScanQRScreenState();
}

class _ScanQRScreenState extends State<ScanQRScreen> {
  final MobileScannerController _cameraController = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );

  bool _isScanning = false;
  bool _isProcessing = false;
  bool _torchOn = false;
  String? _errorText;

  @override
  void dispose() {
    _cameraController.dispose();
    super.dispose();
  }

  void _startScanning() {
    setState(() {
      _isScanning = true;
      _errorText = null;
    });
  }

  void _stopScanning() {
    setState(() {
      _isScanning = false;
      _isProcessing = false;
      _errorText = null;
    });
  }

  Future<void> _toggleTorch() async {
    await _cameraController.toggleTorch();
    setState(() {
      _torchOn = !_torchOn;
    });
  }

  /// Called every time the camera detects a barcode/QR code.
  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return; // ignore extra frames while we're busy

    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final rawValue = barcodes.first.rawValue?.trim();
    if (rawValue == null || rawValue.isEmpty) return;

    setState(() {
      _isProcessing = true;
      _errorText = null;
    });

    try {
      final model = await _resolveModelFromScannedText(rawValue);

      if (!mounted) return;

      if (model == null) {
        setState(() {
          _isProcessing = false;
          _errorText = 'Ye QR code kisi valid model se link nahi hai.';
        });
        return;
      }

      // Stop the camera before navigating away so it doesn't keep
      // running (and draining battery) behind the 3D viewer.
      await _cameraController.stop();

      if (!mounted) return;

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ModelFullViewScreen(model: model),
        ),
      );

      if (!mounted) return;

      // Coming back from the viewer: reset scanner state and camera.
      setState(() {
        _isProcessing = false;
      });
      await _cameraController.start();
    } catch (e) {
      debugPrint('[SCAN QR] Failed to resolve model: $e');
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _errorText = 'Model open nahi ho saka. Dobara try karein.';
      });
    }
  }

  /// Turns whatever text was inside the QR code into a [ModelRecord].
  ///
  /// Expected format is the link produced by ModelQrShareScreen:
  ///   https://rara-a10ab.web.app/viewer.html?model=<glbUrl>&name=<name>&id=<modelId>
  ///
  /// Preferred path: use `id` to pull the FULL record straight out of
  /// Firebase (thumbnail, media gallery, voting flag, etc. all come
  /// along for free). Fallback: if `id` is missing/not found, build a
  /// minimal record directly from `model` + `name` so scanning still
  /// works even for links generated some other way.
  Future<ModelRecord?> _resolveModelFromScannedText(String rawValue) async {
    final uri = Uri.tryParse(rawValue);
    if (uri == null || !uri.hasScheme) return null;

    final modelId = uri.queryParameters['id']?.trim();
    final modelUrlParam = uri.queryParameters['model']?.trim();
    final nameParam = uri.queryParameters['name']?.trim();

    if ((modelId == null || modelId.isEmpty) &&
        (modelUrlParam == null || modelUrlParam.isEmpty)) {
      return null; // not one of our QR links
    }

    // ---- Preferred: fetch the full record from Firebase by id ---------
    if (modelId != null && modelId.isNotEmpty) {
      try {
        final snapshot =
        await FirebaseDatabase.instance.ref('models/$modelId').get();

        if (snapshot.exists) {
          final model = ModelRecord.fromSnapshot(snapshot);
          if (model.modelUrl.trim().isNotEmpty) {
            return model;
          }
        }
      } catch (e) {
        debugPrint('[SCAN QR] Firebase lookup failed for id=$modelId: $e');
        // fall through to the URL-only fallback below
      }
    }

    // ---- Fallback: build a minimal record from the query params -------
    if (modelUrlParam != null && modelUrlParam.isNotEmpty) {
      final now = DateTime.now().millisecondsSinceEpoch;
      return ModelRecord(
        id: modelId ?? now.toString(),
        modelName: (nameParam == null || nameParam.isEmpty)
            ? '3D Model'
            : nameParam,
        modelUrl: modelUrlParam,
        thumbnailUrl: null,
        description: null,
        location: null,
        fileName: null,
        storagePath: null,
        createdAt: now,
        updatedAt: now,
        votingEnabled: false,
        category: 'Optional',
        media: const [], externalImageUrl: '',
      );
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070D12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF070D12),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Scan QR',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          if (_isScanning)
            IconButton(
              tooltip: 'Torch',
              onPressed: _toggleTorch,
              icon: Icon(
                _torchOn ? Icons.flash_on : Icons.flash_off,
                color: Colors.white70,
              ),
            ),
        ],
      ),
      body: _isScanning ? _buildScannerView() : _buildIdleView(),
    );
  }

  // -------------------------------------------------------------------
  // IDLE VIEW - your original design, unchanged.
  // -------------------------------------------------------------------
  Widget _buildIdleView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 230,
              height: 230,
              decoration: BoxDecoration(
                color: const Color(0xFF111920),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: const Color(0xFFD4A843).withOpacity(0.5),
                  width: 2,
                ),
              ),
              child: const Center(
                child: Icon(
                  Icons.qr_code_2_rounded,
                  color: Colors.white,
                  size: 130,
                ),
              ),
            ),
            const SizedBox(height: 30),
            const Text(
              'Scan Project QR Code',
              style: TextStyle(
                color: Colors.white,
                fontSize: 21,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Scan a VISIONAR project QR code\nto explore its details and 3D experience.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white54,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 25),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _startScanning,
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Open Camera'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD4A843),
                  foregroundColor: Colors.black,
                  elevation: 5,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------
  // SCANNER VIEW - live camera + scan frame overlay + status/error text.
  // -------------------------------------------------------------------
  Widget _buildScannerView() {
    return Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(
          controller: _cameraController,
          onDetect: _onDetect,
          // NOTE: mobile_scanner ^5.2.3's errorBuilder signature is
          // Widget Function(BuildContext, MobileScannerException, Widget?)
          // i.e. it DOES take a third `child` param in this version.
          // (This was only removed in later major versions.)
          errorBuilder: (BuildContext context, MobileScannerException error,
              Widget? child) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.no_photography_outlined,
                      color: Colors.redAccent,
                      size: 48,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Camera access nahi mila.\n${error.errorDetails?.message ?? ''}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
            );
          },
        ),

        // Dim overlay with a cut-out scan frame.
        IgnorePointer(
          child: Container(
            decoration: ShapeDecoration(
              shape: _ScannerOverlayShape(
                borderColor: const Color(0xFFD4A843),
                cutOutSize: 250,
              ),
            ),
          ),
        ),

        // Close button.
        Positioned(
          top: 16,
          left: 16,
          child: SafeArea(
            child: Material(
              color: const Color(0x99111920),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _stopScanning,
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child: Icon(Icons.close, color: Colors.white, size: 20),
                ),
              ),
            ),
          ),
        ),

        // Bottom status / error text.
        Positioned(
          left: 24,
          right: 24,
          bottom: 40,
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isProcessing)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: CircularProgressIndicator(color: Color(0xFFD4A843)),
                  ),
                Text(
                  _errorText ??
                      (_isProcessing
                          ? 'Model open ho raha hai...'
                          : 'QR code ko frame ke andar rakhein'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _errorText != null ? Colors.redAccent : Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Draws a dark overlay with a transparent square "viewfinder" cut out
/// of the middle, with a bordered corner-style frame - the classic QR
/// scanner look.
class _ScannerOverlayShape extends ShapeBorder {
  final Color borderColor;
  final double borderWidth;
  final double cutOutSize;
  final double borderRadius;
  final double borderLength;

  const _ScannerOverlayShape({
    this.borderColor = Colors.white,
    this.borderWidth = 4,
    this.cutOutSize = 250,
    this.borderRadius = 16,
    this.borderLength = 32,
  });

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return Path()
      ..addRect(rect)
      ..addRRect(_cutOutRRect(rect))
      ..fillType = PathFillType.evenOdd;
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    return Path()..addRect(rect);
  }

  RRect _cutOutRRect(Rect rect) {
    final cutOutRect = Rect.fromCenter(
      center: rect.center,
      width: cutOutSize,
      height: cutOutSize,
    );
    return RRect.fromRectAndRadius(cutOutRect, Radius.circular(borderRadius));
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final backgroundPaint = Paint()..color = Colors.black.withOpacity(0.55);
    final cutOutRRect = _cutOutRRect(rect);

    canvas.saveLayer(rect, Paint());
    canvas.drawRect(rect, backgroundPaint);
    canvas.drawRRect(
      cutOutRRect,
      Paint()..blendMode = BlendMode.clear,
    );
    canvas.restore();

    // Corner brackets.
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth
      ..strokeCap = StrokeCap.round;

    final r = cutOutRRect.outerRect;
    final radius = borderRadius;

    void corner(Offset a, Offset b, Offset c) {
      final path = Path()
        ..moveTo(a.dx, a.dy)
        ..lineTo(b.dx, b.dy)
        ..lineTo(c.dx, c.dy);
      canvas.drawPath(path, borderPaint);
    }

    // top-left
    corner(
      Offset(r.left, r.top + borderLength),
      Offset(r.left, r.top + radius),
      Offset(r.left + radius, r.top),
    );
    canvas.drawLine(
      Offset(r.left + radius, r.top),
      Offset(r.left + borderLength, r.top),
      borderPaint,
    );

    // top-right
    canvas.drawLine(
      Offset(r.right - borderLength, r.top),
      Offset(r.right - radius, r.top),
      borderPaint,
    );
    corner(
      Offset(r.right - radius, r.top),
      Offset(r.right, r.top + radius),
      Offset(r.right, r.top + borderLength),
    );

    // bottom-left
    corner(
      Offset(r.left, r.bottom - borderLength),
      Offset(r.left, r.bottom - radius),
      Offset(r.left + radius, r.bottom),
    );
    canvas.drawLine(
      Offset(r.left + radius, r.bottom),
      Offset(r.left + borderLength, r.bottom),
      borderPaint,
    );

    // bottom-right
    canvas.drawLine(
      Offset(r.right - borderLength, r.bottom),
      Offset(r.right - radius, r.bottom),
      borderPaint,
    );
    corner(
      Offset(r.right - radius, r.bottom),
      Offset(r.right, r.bottom - radius),
      Offset(r.right, r.bottom - borderLength),
    );
  }

  @override
  ShapeBorder scale(double t) => this;
}