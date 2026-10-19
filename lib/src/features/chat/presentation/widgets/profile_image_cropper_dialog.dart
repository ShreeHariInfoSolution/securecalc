import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../core/utils/app_toast.dart';

class ProfileImageCropperDialog extends StatefulWidget {
  final File imageFile;

  const ProfileImageCropperDialog({
    super.key,
    required this.imageFile,
  });

  /// Opens the cropper dialog and returns the cropped File (or null if cancelled).
  static Future<File?> cropImage(
    BuildContext context, {
    required File imageFile,
  }) async {
    return showGeneralDialog<File>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'CropImage',
      barrierColor: Colors.black.withValues(alpha: 0.88),
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, anim1, anim2) => ProfileImageCropperDialog(
        imageFile: imageFile,
      ),
      transitionBuilder: (context, anim1, anim2, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: anim1, curve: Curves.easeOut),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.95, end: 1.0).animate(
              CurvedAnimation(parent: anim1, curve: Curves.easeOutBack),
            ),
            child: child,
          ),
        );
      },
    );
  }

  @override
  State<ProfileImageCropperDialog> createState() =>
      _ProfileImageCropperDialogState();
}

class _ProfileImageCropperDialogState
    extends State<ProfileImageCropperDialog> {
  final TransformationController _transformationController =
      TransformationController();
  ui.Image? _decodedImage;
  bool _isLoading = true;
  bool _isProcessing = false;
  int _quarterTurns = 0; // 0, 1, 2, 3

  @override
  void initState() {
    super.initState();
    _loadAndDecodeImage();
  }

  Future<void> _loadAndDecodeImage() async {
    try {
      final bytes = await widget.imageFile.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frameInfo = await codec.getNextFrame();
      if (mounted) {
        setState(() {
          _decodedImage = frameInfo.image;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[CROPPER ERROR] $e');
      if (mounted) {
        AppToast.show('Unable to load image for cropping', isError: true);
        Navigator.pop(context, null);
      }
    }
  }

  void _rotateImage() {
    HapticFeedback.selectionClick();
    setState(() {
      _quarterTurns = (_quarterTurns + 1) % 4;
      _transformationController.value = Matrix4.identity();
    });
  }

  void _resetTransform() {
    HapticFeedback.selectionClick();
    setState(() {
      _quarterTurns = 0;
      _transformationController.value = Matrix4.identity();
    });
  }

  Future<void> _performCrop() async {
    if (_decodedImage == null || _isProcessing) return;
    setState(() => _isProcessing = true);
    HapticFeedback.mediumImpact();

    try {
      const double outputResolution = 600.0; // 600x600 high res cropped output
      const double cropViewSize = 280.0; // Displayed crop box on screen

      final rawW = _decodedImage!.width.toDouble();
      final rawH = _decodedImage!.height.toDouble();

      final scale = math.max(cropViewSize / rawW, cropViewSize / rawH);
      final fittedRawW = rawW * scale;
      final fittedRawH = rawH * scale;
      final rawDx = (cropViewSize - fittedRawW) / 2.0;
      final rawDy = (cropViewSize - fittedRawH) / 2.0;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(
        recorder,
        Rect.fromLTWH(0, 0, outputResolution, outputResolution),
      );

      // Draw black background fill
      final bgPaint = Paint()..color = Colors.black;
      canvas.drawRect(
        Rect.fromLTWH(0, 0, outputResolution, outputResolution),
        bgPaint,
      );

      final scaleFactor = outputResolution / cropViewSize;

      canvas.save();
      canvas.scale(scaleFactor);

      // Apply TransformationController matrix from InteractiveViewer
      canvas.transform(_transformationController.value.storage);

      // Handle rotation around center (140, 140) if applied
      if (_quarterTurns != 0) {
        canvas.translate(cropViewSize / 2, cropViewSize / 2);
        canvas.rotate(_quarterTurns * (math.pi / 2));
        canvas.translate(-cropViewSize / 2, -cropViewSize / 2);
      }

      final imagePaint = Paint()..filterQuality = ui.FilterQuality.high;
      canvas.drawImageRect(
        _decodedImage!,
        Rect.fromLTWH(0, 0, rawW, rawH),
        Rect.fromLTWH(rawDx, rawDy, fittedRawW, fittedRawH),
        imagePaint,
      );
      canvas.restore();

      final picture = recorder.endRecording();
      final croppedUiImage = await picture.toImage(
        outputResolution.toInt(),
        outputResolution.toInt(),
      );

      final byteData =
          await croppedUiImage.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('Failed to encode image');

      final croppedBytes = byteData.buffer.asUint8List();
      final tempDir = await getTemporaryDirectory();
      final croppedFilePath =
          '${tempDir.path}/cropped_avatar_${DateTime.now().millisecondsSinceEpoch}.png';
      final croppedFile = File(croppedFilePath);
      await croppedFile.writeAsBytes(croppedBytes, flush: true);

      if (mounted) {
        Navigator.pop(context, croppedFile);
      }
    } catch (e) {
      debugPrint('[CROPPER SAVE ERROR] $e');
      if (mounted) {
        AppToast.show('Error saving cropped image: $e', isError: true);
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  void dispose() {
    _transformationController.dispose();
    _decodedImage?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.paddingOf(context).top;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    const double cropBoxSize = 280.0;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Crop Viewport Center
          Center(
            child: _isLoading
                ? const CircularProgressIndicator(color: Colors.white)
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'Move and Scale',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Drag to position your face inside the circle',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Interactive Cropper Box
                      SizedBox(
                        width: cropBoxSize,
                        height: cropBoxSize,
                        child: Stack(
                          clipBehavior: Clip.hardEdge,
                          children: [
                            // Interactive Viewer Image
                            Positioned.fill(
                              child: ClipOval(
                                child: Container(
                                  color: Colors.black,
                                  child: InteractiveViewer(
                                    transformationController:
                                        _transformationController,
                                    minScale: 1.0,
                                    maxScale: 5.0,
                                    boundaryMargin: const EdgeInsets.all(300),
                                    child: RotatedBox(
                                      quarterTurns: _quarterTurns,
                                      child: Image.file(
                                        widget.imageFile,
                                        fit: BoxFit.cover,
                                        width: cropBoxSize,
                                        height: cropBoxSize,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            // Circular Frame Overlay & Grid Lines
                            Positioned.fill(
                              child: IgnorePointer(
                                child: Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: const Color(0xFF007AFF),
                                      width: 2.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.4,
                                        ),
                                        blurRadius: 16,
                                      ),
                                    ],
                                  ),
                                  child: CustomPaint(
                                    painter: _CropGridPainter(),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 28),

                      // Toolbar Controls: Rotate & Reset
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton.filledTonal(
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.white12,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.all(12),
                            ),
                            onPressed: _rotateImage,
                            icon: const Icon(
                              Icons.rotate_right_rounded,
                              size: 22,
                            ),
                            tooltip: 'Rotate',
                          ),
                          const SizedBox(width: 16),
                          IconButton.filledTonal(
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.white12,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.all(12),
                            ),
                            onPressed: _resetTransform,
                            icon: const Icon(
                              Icons.restart_alt_rounded,
                              size: 22,
                            ),
                            tooltip: 'Reset',
                          ),
                        ],
                      ),
                    ],
                  ),
          ),

          // Top Header Bar (Cancel)
          Positioned(
            top: topPadding + 10,
            left: 16,
            right: 16,
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context, null),
                  icon: const Icon(
                    CupertinoIcons.xmark,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const Spacer(),
                const Text(
                  'Profile Picture',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                const SizedBox(width: 40),
              ],
            ),
          ),

          // Bottom Action Button (Crop & Save)
          Positioned(
            bottom: bottomPadding + 20,
            left: 20,
            right: 20,
            child: SafeArea(
              child: SizedBox(
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF007AFF),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26),
                    ),
                    elevation: 6,
                  ),
                  onPressed: _isProcessing ? null : _performCrop,
                  child: _isProcessing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_rounded, size: 22),
                            SizedBox(width: 8),
                            Text(
                              'Choose Profile Picture',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
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

class _CropGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;

    // Rule of thirds grid lines
    final thirdW = size.width / 3;
    final thirdH = size.height / 3;

    canvas.drawLine(
      Offset(thirdW, 0),
      Offset(thirdW, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(thirdW * 2, 0),
      Offset(thirdW * 2, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(0, thirdH),
      Offset(size.width, thirdH),
      paint,
    );
    canvas.drawLine(
      Offset(0, thirdH * 2),
      Offset(size.width, thirdH * 2),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
