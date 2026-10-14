import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../core/theme/app_theme.dart';

class ImageEditorResult {
  final List<File> images;
  final String caption;

  ImageEditorResult({
    required this.images,
    required this.caption,
  });
}

class DrawingStroke {
  final List<Offset> points; // Normalized 0.0 .. 1.0 coordinates
  final Color color;
  final double strokeWidth;

  DrawingStroke({
    required this.points,
    required this.color,
    this.strokeWidth = 4.0,
  });
}

class ImagePreviewEditorPage extends StatefulWidget {
  final List<File> imageFiles;

  const ImagePreviewEditorPage({
    super.key,
    required this.imageFiles,
  });

  @override
  State<ImagePreviewEditorPage> createState() => _ImagePreviewEditorPageState();
}

class _ImagePreviewEditorPageState extends State<ImagePreviewEditorPage> {
  late List<File> _files;
  late Map<int, List<DrawingStroke>> _strokesPerImage;
  final Map<int, Size> _imageSizes = {};
  int _currentIndex = 0;
  bool _isDrawingMode = false;
  Color _selectedColor = Colors.red;
  double _strokeWidth = 4.0;

  final TextEditingController _captionController = TextEditingController();
  final PageController _pageController = PageController();

  final List<Color> _colors = const [
    Colors.white,
    Colors.black,
    Colors.red,
    Colors.amber,
    Colors.green,
    Colors.lightBlue,
    Colors.purpleAccent,
  ];

  @override
  void initState() {
    super.initState();
    _files = List.from(widget.imageFiles);
    _strokesPerImage = {
      for (int i = 0; i < _files.length; i++) i: <DrawingStroke>[],
    };
    _preloadImageSizes();
  }

  Future<void> _preloadImageSizes() async {
    for (int i = 0; i < _files.length; i++) {
      try {
        final bytes = await _files[i].readAsBytes();
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        if (mounted) {
          setState(() {
            _imageSizes[i] = Size(
              frame.image.width.toDouble(),
              frame.image.height.toDouble(),
            );
          });
        }
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _captionController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  List<DrawingStroke> get _currentStrokes =>
      _strokesPerImage[_currentIndex] ??= <DrawingStroke>[];

  void _undoStroke() {
    if (_currentStrokes.isNotEmpty) {
      setState(() {
        _currentStrokes.removeLast();
      });
    }
  }

  Offset? _toNormalized(Offset touch, Size boxSize, Size imageSize) {
    if (imageSize.width <= 0 || imageSize.height <= 0) return null;
    final fitted = applyBoxFit(BoxFit.contain, imageSize, boxSize);
    final fitW = fitted.destination.width;
    final fitH = fitted.destination.height;
    if (fitW <= 0 || fitH <= 0) return null;

    final offsetX = (boxSize.width - fitW) / 2;
    final offsetY = (boxSize.height - fitH) / 2;

    final normX = ((touch.dx - offsetX) / fitW).clamp(0.0, 1.0);
    final normY = ((touch.dy - offsetY) / fitH).clamp(0.0, 1.0);
    return Offset(normX, normY);
  }

  Future<File> _exportSingleImage(
    File originalFile,
    List<DrawingStroke> strokes,
  ) async {
    if (strokes.isEmpty) return originalFile;

    try {
      final bytes = await originalFile.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final ui.Image image = frame.image;
      final double imgW = image.width.toDouble();
      final double imgH = image.height.toDouble();

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(
        recorder,
        Rect.fromLTWH(0, 0, imgW, imgH),
      );

      // Draw original image
      canvas.drawImage(image, Offset.zero, Paint());

      // Scale stroke width relative to resolution
      final scaleFactor = math.max(1.0, imgW / 400.0);

      for (final stroke in strokes) {
        if (stroke.points.length < 2) continue;
        final paint = Paint()
          ..color = stroke.color
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = stroke.strokeWidth * scaleFactor
          ..style = PaintingStyle.stroke;

        for (int i = 0; i < stroke.points.length - 1; i++) {
          final p1 = stroke.points[i];
          final p2 = stroke.points[i + 1];
          final pixelP1 = Offset(p1.dx * imgW, p1.dy * imgH);
          final pixelP2 = Offset(p2.dx * imgW, p2.dy * imgH);
          canvas.drawLine(pixelP1, pixelP2, paint);
        }
      }

      final picture = recorder.endRecording();
      final img = await picture.toImage(image.width, image.height);
      final pngData = await img.toByteData(format: ui.ImageByteFormat.png);

      if (pngData == null) return originalFile;

      final tempDir = await getTemporaryDirectory();
      final editedFile = File(
        '${tempDir.path}${Platform.pathSeparator}edited_${DateTime.now().millisecondsSinceEpoch}_${math.Random().nextInt(999)}.png',
      );
      await editedFile.writeAsBytes(pngData.buffer.asUint8List(), flush: true);
      return editedFile;
    } catch (_) {
      return originalFile;
    }
  }

  Future<void> _handleSend() async {
    final processed = <File>[];
    for (int i = 0; i < _files.length; i++) {
      final strokes = _strokesPerImage[i] ?? [];
      final exported = await _exportSingleImage(_files[i], strokes);
      processed.add(exported);
    }

    if (!mounted) return;
    Navigator.pop(
      context,
      ImageEditorResult(
        images: processed,
        caption: _captionController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Top Control Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  if (_isDrawingMode) ...[
                    IconButton(
                      icon: const Icon(Icons.undo_rounded, color: Colors.white, size: 26),
                      onPressed: _currentStrokes.isNotEmpty ? _undoStroke : null,
                      tooltip: 'Undo draw',
                    ),
                    const SizedBox(width: 8),
                  ],
                  IconButton(
                    icon: Icon(
                      Icons.draw_rounded,
                      color: _isDrawingMode ? AppTheme.primaryColor : Colors.white,
                      size: 26,
                    ),
                    onPressed: () {
                      setState(() {
                        _isDrawingMode = !_isDrawingMode;
                      });
                    },
                    tooltip: 'Draw tool',
                  ),
                ],
              ),
            ),

            // Color Palette Row when Drawing Mode active
            if (_isDrawingMode)
              Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: _colors
                      .map(
                        (color) => GestureDetector(
                          onTap: () => setState(() => _selectedColor = color),
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 6),
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _selectedColor == color
                                    ? Colors.white
                                    : Colors.transparent,
                                width: 2.5,
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black45,
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),

            // Main Interactive Image & Drawing Canvas Area
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                physics: _isDrawingMode
                    ? const NeverScrollableScrollPhysics()
                    : const BouncingScrollPhysics(),
                onPageChanged: (idx) {
                  setState(() {
                    _currentIndex = idx;
                  });
                },
                itemCount: _files.length,
                itemBuilder: (context, index) {
                  final file = _files[index];
                  final strokes = _strokesPerImage[index] ?? [];
                  final imageSize = _imageSizes[index] ?? const Size(1, 1);

                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final boxSize = Size(constraints.maxWidth, constraints.maxHeight);

                      return GestureDetector(
                        onPanStart: _isDrawingMode
                            ? (details) {
                                final norm = _toNormalized(
                                  details.localPosition,
                                  boxSize,
                                  imageSize,
                                );
                                if (norm != null) {
                                  setState(() {
                                    strokes.add(
                                      DrawingStroke(
                                        points: [norm],
                                        color: _selectedColor,
                                        strokeWidth: _strokeWidth,
                                      ),
                                    );
                                  });
                                }
                              }
                            : null,
                        onPanUpdate: _isDrawingMode
                            ? (details) {
                                final norm = _toNormalized(
                                  details.localPosition,
                                  boxSize,
                                  imageSize,
                                );
                                if (norm != null && strokes.isNotEmpty) {
                                  setState(() {
                                    strokes.last.points.add(norm);
                                  });
                                }
                              }
                            : null,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Image.file(
                              file,
                              width: boxSize.width,
                              height: boxSize.height,
                              fit: BoxFit.contain,
                            ),
                            CustomPaint(
                              size: boxSize,
                              painter: _DrawingCanvasPainter(
                                strokes: strokes,
                                imageSize: imageSize,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),

            // Thumbnail Carousel if multiple images
            if (_files.length > 1)
              Container(
                height: 60,
                margin: const EdgeInsets.symmetric(vertical: 6),
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _files.length,
                  itemBuilder: (context, index) {
                    final selected = index == _currentIndex;
                    return GestureDetector(
                      onTap: () {
                        _pageController.animateToPage(
                          index,
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeInOut,
                        );
                      },
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: selected ? AppTheme.primaryColor : Colors.transparent,
                            width: 2.5,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.file(
                            _files[index],
                            width: 50,
                            height: 50,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

            // Bottom Caption Bar & Send Button
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1C1E),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.white12,
                          width: 1,
                        ),
                      ),
                      child: TextField(
                        controller: _captionController,
                        style: const TextStyle(color: Colors.white, fontSize: 15),
                        decoration: const InputDecoration(
                          hintText: 'Add a caption…',
                          hintStyle: TextStyle(
                            color: AppTheme.subtitleGrey,
                            fontSize: 15,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: _handleSend,
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: const BoxDecoration(
                        color: AppTheme.primaryColor,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black38,
                            blurRadius: 6,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.send_rounded,
                        color: Colors.white,
                        size: 22,
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

class _DrawingCanvasPainter extends CustomPainter {
  final List<DrawingStroke> strokes;
  final Size imageSize;

  _DrawingCanvasPainter({
    required this.strokes,
    required this.imageSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (imageSize.width <= 0 || imageSize.height <= 0) return;

    final fitted = applyBoxFit(BoxFit.contain, imageSize, size);
    final fitW = fitted.destination.width;
    final fitH = fitted.destination.height;
    final offsetX = (size.width - fitW) / 2;
    final offsetY = (size.height - fitH) / 2;

    for (final stroke in strokes) {
      if (stroke.points.length < 2) continue;
      final paint = Paint()
        ..color = stroke.color
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = stroke.strokeWidth
        ..style = PaintingStyle.stroke;

      for (int i = 0; i < stroke.points.length - 1; i++) {
        final p1 = stroke.points[i];
        final p2 = stroke.points[i + 1];
        final screenP1 = Offset(offsetX + p1.dx * fitW, offsetY + p1.dy * fitH);
        final screenP2 = Offset(offsetX + p2.dx * fitW, offsetY + p2.dy * fitH);
        canvas.drawLine(screenP1, screenP2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DrawingCanvasPainter oldDelegate) => true;
}
