import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../core/utils/app_toast.dart';

/// WhatsApp-style "Move and Scale" Profile Image Cropper Dialog.
class ProfileImageCropperDialog extends StatefulWidget {
  final File imageFile;

  const ProfileImageCropperDialog({
    super.key,
    required this.imageFile,
  });

  /// Opens the cropper dialog and returns the cropped square File (or null if cancelled).
  static Future<File?> cropImage(
    BuildContext context, {
    required File imageFile,
  }) async {
    return showGeneralDialog<File>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'CropImage',
      barrierColor: Colors.black.withValues(alpha: 0.95),
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, anim1, anim2) => ProfileImageCropperDialog(
        imageFile: imageFile,
      ),
      transitionBuilder: (context, anim1, anim2, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: anim1, curve: Curves.easeOut),
          child: child,
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
      const double outputResolution = 600.0; // 600x600 square output
      final screenWidth = MediaQuery.of(context).size.width;
      final double cropViewSize = (screenWidth * 0.88).clamp(280.0, 340.0);

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

      // Black background
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

      // Rotation around center
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
        AppToast.show(
          AppToast.userFriendlyMessage('Error saving cropped image: $e'),
          isError: true,
        );
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
    final screenWidth = MediaQuery.of(context).size.width;
    final double cropBoxSize = (screenWidth * 0.88).clamp(280.0, 340.0);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar: "Move and scale"
            Padding(
              padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
              child: const Text(
                'Move and scale',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0.2,
                ),
              ),
            ),

            const Spacer(),

            // Center Cropper Canvas Box (WhatsApp Style)
            Center(
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : SizedBox(
                      width: cropBoxSize,
                      height: cropBoxSize,
                      child: Stack(
                        clipBehavior: Clip.hardEdge,
                        children: [
                          // Square Interactive Image Layer
                          Positioned.fill(
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

                          // Circular Overlay Mask (WhatsApp Style)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: CustomPaint(
                                size: Size(cropBoxSize, cropBoxSize),
                                painter: _WhatsAppCropOverlayPainter(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),

            const SizedBox(height: 24),

            // Rotation & Reset Tools
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white12,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.all(10),
                  ),
                  onPressed: _rotateImage,
                  icon: const Icon(
                    Icons.rotate_right_rounded,
                    size: 20,
                  ),
                  tooltip: 'Rotate',
                ),
                const SizedBox(width: 16),
                IconButton(
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white12,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.all(10),
                  ),
                  onPressed: _resetTransform,
                  icon: const Icon(
                    Icons.restart_alt_rounded,
                    size: 20,
                  ),
                  tooltip: 'Reset',
                ),
              ],
            ),

            const Spacer(),

            // Bottom Actions Bar: Cancel / Choose (WhatsApp Style)
            Padding(
              padding: EdgeInsets.only(
                left: 24.0,
                right: 24.0,
                bottom: bottomPadding + 16.0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: _isProcessing
                        ? null
                        : () => Navigator.pop(context, null),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                  _isProcessing
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : TextButton(
                          onPressed: _performCrop,
                          child: const Text(
                            'Choose',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
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
}

/// Draws the WhatsApp-style circular overlay mask:
/// Outer square is dimmed with a 60% dark mask, leaving a clear circular aperture in the middle.
class _WhatsAppCropOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);

    // Dark semi-transparent mask outside the circle
    final maskPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.62)
      ..style = PaintingStyle.fill;

    final path = Path()
      ..addRect(rect)
      ..addOval(Rect.fromLTWH(0, 0, size.width, size.height));
    path.fillType = PathFillType.evenOdd;

    canvas.drawPath(path, maskPaint);

    // Subtle white circle border line
    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.45)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    canvas.drawOval(Rect.fromLTWH(0, 0, size.width, size.height), borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
