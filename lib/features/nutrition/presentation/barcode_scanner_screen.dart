import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'widgets/nutrition_cards.dart';

/// Live camera barcode scanner powered by `mobile_scanner` — the same ML Kit /
/// CameraX / AVFoundation engine the official Open Food Facts app uses.
///
/// Pops with the scanned barcode string on success, or `null` if the user
/// cancels or chooses manual entry.
class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    // Product barcodes only (skip QR/data-matrix noise for faster locking).
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.itf,
    ],
    detectionSpeed: DetectionSpeed.normal,
  );

  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final code = barcode.rawValue?.trim();
      if (code != null && code.isNotEmpty) {
        _handled = true;
        Navigator.of(context).pop(code);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => _buildError(context, error),
          ),
          // Dimmed overlay with a clear scanning window.
          _buildScanWindow(context),
          // Top bar: close + torch + camera flip.
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  _circleButton(Icons.close_rounded,
                      () => Navigator.of(context).pop()),
                  const Spacer(),
                  _torchButton(),
                  const SizedBox(width: 8),
                  _circleButton(Icons.cameraswitch_rounded,
                      () => _controller.switchCamera()),
                ],
              ),
            ),
          ),
          // Bottom hint + manual entry escape hatch.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Point the camera at a product barcode',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: () => Navigator.of(context).pop('__manual__'),
                      icon: const Icon(Icons.keyboard_rounded,
                          color: Colors.white70),
                      label: const Text('Enter number manually',
                          style: TextStyle(color: Colors.white70)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanWindow(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Container(
          width: 260,
          height: 170,
          decoration: BoxDecoration(
            border: Border.all(color: kNutritionAccent, width: 3),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.35),
                blurRadius: 0,
                spreadRadius: 4000,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _torchButton() {
    return ValueListenableBuilder<MobileScannerState>(
      valueListenable: _controller,
      builder: (context, state, _) {
        final on = state.torchState == TorchState.on;
        return _circleButton(
          on ? Icons.flash_on_rounded : Icons.flash_off_rounded,
          () => _controller.toggleTorch(),
          highlight: on,
        );
      },
    );
  }

  Widget _circleButton(IconData icon, VoidCallback onTap,
      {bool highlight = false}) {
    return Material(
      color: highlight
          ? kNutritionAccent
          : Colors.black.withOpacity(0.4),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: Colors.white, size: 24),
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context, MobileScannerException error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_rounded,
                color: Colors.white70, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Camera unavailable',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Check camera permission in Settings, or enter the barcode '
              'number manually.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: kNutritionAccent,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(context).pop('__manual__'),
              icon: const Icon(Icons.keyboard_rounded),
              label: const Text('Enter manually'),
            ),
          ],
        ),
      ),
    );
  }
}
