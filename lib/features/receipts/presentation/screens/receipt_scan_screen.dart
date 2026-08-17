import 'dart:developer' as developer;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:spendsense/core/routing/app_router.dart';
import 'package:spendsense/core/widgets/validation_snackbar.dart';
import 'package:spendsense/features/receipts/application/receipt_providers.dart';
import 'package:spendsense/features/receipts/data/remote/http_receipt_scan_repository.dart';
import 'package:spendsense/features/receipts/domain/entities/receipt.dart';

class ReceiptScanScreen extends ConsumerStatefulWidget {
  const ReceiptScanScreen({super.key});

  @override
  ConsumerState<ReceiptScanScreen> createState() => _ReceiptScanScreenState();
}

class _ReceiptScanScreenState extends ConsumerState<ReceiptScanScreen> {
  CameraController? _controller;
  Future<void>? _initFuture;
  String? _cameraError;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _setupCamera();
  }

  Future<void> _setupCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _cameraError = 'No camera available on this device.');
        return;
      }
      final controller = CameraController(cameras.first, ResolutionPreset.medium, enableAudio: false);
      final initFuture = controller.initialize();
      setState(() {
        _controller = controller;
        _initFuture = initFuture;
      });
    } catch (e, stackTrace) {
      developer.log('Camera setup failed', error: e, stackTrace: stackTrace, name: 'ReceiptScanScreen');
      setState(() => _cameraError = "Camera unavailable. You can pick a photo from your gallery instead.");
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    final file = await _controller!.takePicture();
    await _runScan(file.path);
  }

  Future<void> _pickFromGallery() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    await _runScan(picked.path);
  }

  Future<void> _runScan(String imagePath) async {
    setState(() => _scanning = true);
    try {
      final result = await ref.read(receiptScanRepositoryProvider).scan(imagePath);
      if (!mounted) return;

      // A low-confidence read is worse than no read: it silently prefills a
      // wrong amount the user is likely to accept. Make them retake instead.
      if (!result.isTrustworthy) {
        await _showRetakeDialog(result);
        return;
      }

      context.pushReplacement('/receipts/review', extra: ReceiptReviewArgs(scanResult: result, imagePath: imagePath));
    } on ReceiptScanException catch (e) {
      if (mounted) showValidationSnackBar(context, e.message);
    } catch (e, stackTrace) {
      developer.log('Receipt scan failed', error: e, stackTrace: stackTrace, name: 'ReceiptScanScreen');
      if (mounted) showValidationSnackBar(context, "Couldn't read that receipt. Please try again.");
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _showRetakeDialog(ReceiptScanResult result) async {
    final advice = switch (result.qualityIssue) {
      ReceiptQualityIssue.blurry => 'The photo came out blurry. Hold your phone steady and let it focus before tapping.',
      ReceiptQualityIssue.cropped => 'Part of the receipt is cut off. Fit the whole receipt inside the frame.',
      ReceiptQualityIssue.glare => "There's glare covering some of the text. Move away from direct light or tilt the receipt.",
      ReceiptQualityIssue.tooDark => "It's too dark to read. Move somewhere brighter and try again.",
      ReceiptQualityIssue.unreadable => "The text isn't clear enough to read. Get closer and make sure the receipt is flat.",
      ReceiptQualityIssue.none => "I couldn't read the total clearly enough to be sure. Take another photo with the total fully visible.",
    };

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(LucideIcons.scanLine, size: 32),
        title: const Text('Take another photo'),
        content: Text(advice),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Retake')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Receipt'),
        actions: [
          IconButton(
            tooltip: 'Scan a photo from your gallery',
            onPressed: _scanning ? null : _pickFromGallery,
            icon: const Icon(LucideIcons.scanLine),
          ),
        ],
      ),
      body: _cameraError != null
          ? _fallback(_cameraError!)
          : FutureBuilder(
              future: _initFuture,
              builder: (context, snapshot) {
                if (_controller == null || snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    CameraPreview(_controller!),
                    if (_scanning)
                      Container(
                        color: Colors.black.withValues(alpha: 0.72),
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 40),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const CircularProgressIndicator(color: Colors.white),
                                const SizedBox(height: 20),
                                const Text(
                                  'Scanning your receipt…',
                                  style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Reading the merchant, items and total. This takes a few seconds — please keep the app open.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.white.withValues(alpha: 0.75), height: 1.4),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    if (!_scanning) ...[
                      _shutterHint(),
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 28),
                          child: _ShutterButton(onPressed: _capture),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
    );
  }

  Widget _shutterHint() {
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(999),
          ),
          child: const Text(
            'Fit the whole receipt in frame',
            style: TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
      ),
    );
  }

  Widget _fallback(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.camera, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _scanning ? null : _pickFromGallery,
              icon: const Icon(LucideIcons.image, size: 18),
              label: const Text('Pick a photo instead'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Classic camera shutter: a ring with a filled centre, sized closer to a
/// system camera app's button than Material's oversized large FAB.
class _ShutterButton extends StatefulWidget {
  const _ShutterButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  State<_ShutterButton> createState() => _ShutterButtonState();
}

class _ShutterButtonState extends State<_ShutterButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Capture receipt',
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _pressed ? 0.92 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: Container(
            width: 66,
            height: 66,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              color: Colors.white.withValues(alpha: 0.15),
            ),
            child: Center(
              child: Container(
                width: 50,
                height: 50,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
