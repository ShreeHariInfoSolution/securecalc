import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../core/config/app_preferences.dart';

class AppCameraPage extends StatefulWidget {
  const AppCameraPage({super.key});

  @override
  State<AppCameraPage> createState() => _AppCameraPageState();
}

enum CameraMode { video, photo }

enum ZoomMode { continuous, lensSwap, none }

class _AppCameraPageState extends State<AppCameraPage>
    with WidgetsBindingObserver {
  CameraDescription? _mainCamera;
  CameraDescription? _ultraWideCamera;
  CameraDescription? _frontCamera;

  bool _isUsingFrontCamera = false;
  bool _isUsingUltraWide = false;

  CameraController? _controller;
  bool _isInitializing = true;
  bool _isRecording = false;
  CameraMode _mode = CameraMode.photo;
  FlashMode _flashMode = FlashMode.off;

  // Zoom
  ZoomMode _zoomMode = ZoomMode.none;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  double _mainMinZoom = 1.0;
  double _currentZoom = 1.0;
  double _displayedZoom = 1.0;
  double _baseZoom = 1.0;
  double _latestPinchDisplayZoom = 1.0;
  bool _isPinching = false;

  // Throttling / Single Zoom Entry Point
  bool _zoomInFlight = false;
  double? _pendingZoom;

  // iOS Curved Zoom Slider
  bool _showZoomSlider = false;
  Timer? _zoomSliderHideTimer;
  double _sliderDragStartZoom = 1.0;
  double _sliderDragStartX = 0.0;
  int _lastHapticZoomFloor = 1;

  bool _iosQuarterFix = false; // iPhone 17 family needs a manual quarter-turn

  Timer? _recordingTimer;
  int _recordingSeconds = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]));
    _detectDevice().then((_) => _initCamera());
  }

  Future<void> _detectDevice() async {
    if (!Platform.isIOS) return;
    try {
      final machine = (await DeviceInfoPlugin().iosInfo).utsname.machine; // e.g. iPhone18,2
      final major =
          int.tryParse(RegExp(r'iPhone(\d+),').firstMatch(machine)?.group(1) ?? '') ?? 0;
      _iosQuarterFix = major >= 18;
      debugPrint('[DEVICE] machine=$machine quarterFix=$_iosQuarterFix');
    } catch (e) {
      debugPrint('[DEVICE ERROR] $e');
    }
  }

  int _previewTurns(CameraController c) {
    // Fixed quarter turn for locked portrait UI mode, preventing physical device flipping from flipping the visual
    return 1;
  }

  Future<void> _initCamera() async {
    try {
      final allCameras = await availableCameras();
      if (allCameras.isEmpty) {
        if (mounted) setState(() => _isInitializing = false);
        return;
      }

      // Phase 0: Diagnostics on real devices
      for (final c in allCameras) {
        String typeStr = 'unknown';
        try {
          typeStr = (c as dynamic).lensType?.toString() ?? 'n/a';
        } catch (_) {}
        debugPrint('[CAM DIAGNOSTIC] CAM ${c.name} dir=${c.lensDirection} type=$typeStr');
      }

      _frontCamera = null;
      _mainCamera = null;
      _ultraWideCamera = null;

      final List<CameraDescription> backCameras = [];

      for (final cam in allCameras) {
        if (cam.lensDirection == CameraLensDirection.front) {
          _frontCamera ??= cam;
        } else if (cam.lensDirection == CameraLensDirection.back) {
          backCameras.add(cam);
        }
      }

      for (final cam in backCameras) {
        final nameLower = cam.name.toLowerCase();
        String typeStr = '';
        try {
          typeStr = (cam as dynamic).lensType?.toString().toLowerCase() ?? '';
        } catch (_) {}

        final bool isUltra = typeStr.contains('ultra') ||
            nameLower.contains('ultrawide') ||
            nameLower.contains('ultra wide') ||
            nameLower.contains('ultra_wide');

        if (isUltra && _ultraWideCamera == null) {
          _ultraWideCamera = cam;
        } else {
          _mainCamera ??= cam;
        }
      }

      if (_mainCamera == null && backCameras.isNotEmpty) {
        _mainCamera = backCameras.first;
      }
      if (_mainCamera == _ultraWideCamera) {
        _ultraWideCamera = null;
      }

      _frontCamera ??= allCameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => allCameras.first,
      );

      final initialCam = _isUsingFrontCamera
          ? _frontCamera!
          : (_isUsingUltraWide && _ultraWideCamera != null
              ? _ultraWideCamera!
              : (_mainCamera ?? allCameras.first));

      await _setupController(initialCam);
    } catch (e) {
      debugPrint('[APP CAMERA ERROR] $e');
      if (mounted) setState(() => _isInitializing = false);
    }
  }

  Future<void> _setupController(CameraDescription camera) async {
    if (mounted) setState(() => _isInitializing = true);

    final old = _controller;
    _controller = null;
    old?.removeListener(_onControllerUpdate);
    await old?.dispose();

    final controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: true,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    try {
      await controller.initialize();

      final v = controller.value;
      debugPrint('[PREVIEW DIAG] cam=${camera.name} previewSize=${v.previewSize} '
          'aspect=${v.aspectRatio} deviceOrientation=${v.deviceOrientation} '
          'lockedCapture=${v.lockedCaptureOrientation}');

      try {
        await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      } catch (e) {
        debugPrint('[LOCK CAPTURE ORIENTATION ERROR] $e');
      }
      await controller.setFlashMode(_flashMode);

      _minZoom = await controller.getMinZoomLevel();
      _maxZoom = await controller.getMaxZoomLevel();

      // Phase 0: Diagnostics
      debugPrint(
          '[ZOOM DIAGNOSTIC] min=$_minZoom max=$_maxZoom camera=${camera.name}');

      if (camera == _mainCamera ||
          (!_isUsingFrontCamera && !_isUsingUltraWide)) {
        _mainMinZoom = _minZoom;
      }

      _detectZoomMode();

      double targetControllerZoom = 1.0;
      if (_zoomMode == ZoomMode.lensSwap && _isUsingUltraWide) {
        targetControllerZoom =
            (_displayedZoom / 0.5).clamp(_minZoom, _maxZoom);
      } else {
        targetControllerZoom = _displayedZoom.clamp(_minZoom, _maxZoom);
      }

      try {
        await controller.setZoomLevel(targetControllerZoom);
        _currentZoom = targetControllerZoom;
      } catch (e) {
        debugPrint('[INITIAL ZOOM ERROR] $e');
      }

      controller.addListener(_onControllerUpdate);
      _controller = controller;
    } catch (e) {
      debugPrint('[CAMERA SETUP ERROR] $e');
    } finally {
      if (mounted) {
        setState(() => _isInitializing = false);
      }
    }
  }

  void _detectZoomMode() {
    if (_isUsingFrontCamera) {
      _zoomMode = _maxZoom > 1.0 ? ZoomMode.continuous : ZoomMode.none;
    } else if (_mainMinZoom < 1.0) {
      _zoomMode = ZoomMode.continuous; // Android logical camera
    } else if (_ultraWideCamera != null) {
      _zoomMode = ZoomMode.lensSwap; // iOS / Android physical multi-lens
    } else {
      _zoomMode = _maxZoom > 1.0 ? ZoomMode.continuous : ZoomMode.none;
    }
    debugPrint(
        '[ZOOM MODE] Mode: $_zoomMode (front=$_isUsingFrontCamera, mainMinZoom=$_mainMinZoom, ultraWide=${_ultraWideCamera?.name})');
  }

  // Phase 2: Single zoom entry point with throttle guard
  Future<void> _requestZoom(double display) async {
    _pendingZoom = display;
    if (_zoomInFlight) return;
    _zoomInFlight = true;
    while (_pendingZoom != null) {
      final d = _pendingZoom!;
      _pendingZoom = null;
      await _applyDisplayedZoom(d);
    }
    _zoomInFlight = false;
    debugPrint('[ZOOM UPDATE] displayedZoom=$_displayedZoom currentZoom=$_currentZoom mode=$_zoomMode');
  }

  Future<void> _applyDisplayedZoom(double display) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    switch (_zoomMode) {
      case ZoomMode.continuous:
        final targetZoom = display.clamp(_minZoom, _maxZoom);
        try {
          await controller.setZoomLevel(targetZoom);
          if (mounted) {
            setState(() {
              _displayedZoom = targetZoom;
              _currentZoom = targetZoom;
            });
          }
        } catch (e) {
          debugPrint('[ZOOM ERROR] $e');
        }
        break;

      case ZoomMode.lensSwap:
        // Phase 3: Don't swap while recording video or mid-pinch
        final bool preventSwap = _isRecording || _isPinching;

        if (preventSwap) {
          if (_isUsingUltraWide) {
            final targetZoom = display.clamp(0.5, 1.0);
            final controllerZoom =
                (targetZoom / 0.5).clamp(_minZoom, _maxZoom);
            try {
              await controller.setZoomLevel(controllerZoom);
              if (mounted) {
                setState(() {
                  _displayedZoom = targetZoom;
                  _currentZoom = controllerZoom;
                });
              }
            } catch (e) {
              debugPrint('[ZOOM ERROR] $e');
            }
          } else {
            final targetZoom = display.clamp(1.0, _maxZoom);
            final controllerZoom = targetZoom.clamp(_minZoom, _maxZoom);
            try {
              await controller.setZoomLevel(controllerZoom);
              if (mounted) {
                setState(() {
                  _displayedZoom = targetZoom;
                  _currentZoom = controllerZoom;
                });
              }
            } catch (e) {
              debugPrint('[ZOOM ERROR] $e');
            }
          }
          return;
        }

        // Hysteresis threshold logic: switch down at < 0.98, up at >= 1.0
        if (!_isUsingUltraWide && display < 0.98 && _ultraWideCamera != null) {
          _isUsingUltraWide = true;
          _displayedZoom = display.clamp(0.5, 1.0);
          await _setupController(_ultraWideCamera!);
        } else if (_isUsingUltraWide && display >= 1.0 && _mainCamera != null) {
          _isUsingUltraWide = false;
          _displayedZoom = display.clamp(1.0, _maxZoom);
          await _setupController(_mainCamera!);
        } else {
          if (_isUsingUltraWide) {
            final targetZoom = display.clamp(0.5, 1.0);
            final controllerZoom =
                (targetZoom / 0.5).clamp(_minZoom, _maxZoom);
            try {
              await controller.setZoomLevel(controllerZoom);
              if (mounted) {
                setState(() {
                  _displayedZoom = targetZoom;
                  _currentZoom = controllerZoom;
                });
              }
            } catch (e) {
              debugPrint('[ZOOM ERROR] $e');
            }
          } else {
            final targetZoom = display.clamp(1.0, _maxZoom);
            final controllerZoom = targetZoom.clamp(_minZoom, _maxZoom);
            try {
              await controller.setZoomLevel(controllerZoom);
              if (mounted) {
                setState(() {
                  _displayedZoom = targetZoom;
                  _currentZoom = controllerZoom;
                });
              }
            } catch (e) {
              debugPrint('[ZOOM ERROR] $e');
            }
          }
        }
        break;

      case ZoomMode.none:
        final targetZoom = display.clamp(_minZoom, _maxZoom);
        try {
          await controller.setZoomLevel(targetZoom);
          if (mounted) {
            setState(() {
              _displayedZoom = targetZoom;
              _currentZoom = targetZoom;
            });
          }
        } catch (e) {
          debugPrint('[ZOOM ERROR] $e');
        }
        break;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      AppPreferences.isPickerActive = false;
      if (controller != null && controller.value.isInitialized) {
        _controller = null;
        controller.removeListener(_onControllerUpdate);
        controller.dispose();
      }
      if (mounted) Navigator.of(context).maybePop();
      return;
    }

    if (controller == null || !controller.value.isInitialized) return;

    if (state == AppLifecycleState.resumed) {
      _setupController(controller.description);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AppPreferences.isPickerActive = false;
    _recordingTimer?.cancel();
    _zoomSliderHideTimer?.cancel();
    _controller?.removeListener(_onControllerUpdate);
    _controller?.dispose();
    unawaited(SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]));
    super.dispose();
  }

  Future<void> _toggleCamera() async {
    if (_frontCamera == null || _mainCamera == null) return;

    _isUsingFrontCamera = !_isUsingFrontCamera;
    _isUsingUltraWide = false;
    _displayedZoom = 1.0;

    final nextCam = _isUsingFrontCamera ? _frontCamera! : _mainCamera!;
    await _setupController(nextCam);
  }

  Future<void> _toggleFlash() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    FlashMode nextMode;
    switch (_flashMode) {
      case FlashMode.off:
        nextMode = FlashMode.auto;
        break;
      case FlashMode.auto:
        nextMode = FlashMode.always;
        break;
      default:
        nextMode = FlashMode.off;
        break;
    }
    try {
      await _controller!.setFlashMode(nextMode);
      setState(() => _flashMode = nextMode);
    } catch (e) {
      debugPrint('[FLASH MODE ERROR] $e');
    }
  }

  List<double> get _availableZoomPresets {
    final List<double> candidates = [0.5, 1.0, 2.0, 3.0];
    if (_isUsingFrontCamera) {
      return candidates.where((p) => p >= _minZoom && p <= _maxZoom).toList();
    }

    if (_zoomMode == ZoomMode.continuous) {
      return candidates.where((p) => p >= _minZoom && p <= _maxZoom).toList();
    } else if (_zoomMode == ZoomMode.lensSwap) {
      final List<double> list = [];
      if (_ultraWideCamera != null && !_isRecording) {
        list.add(0.5);
      }
      for (final p in [1.0, 2.0, 3.0]) {
        if (p <= _maxZoom) list.add(p);
      }
      return list;
    } else {
      return candidates.where((p) => p >= 1.0 && p <= _maxZoom).toList();
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final picker = ImagePicker();
      final List<XFile> files =
          await picker.pickMultipleMedia(imageQuality: 90);
      if (files.isNotEmpty && mounted) {
        Navigator.pop(context, File(files.first.path));
      }
    } catch (e) {
      debugPrint('[GALLERY PICK ERROR] $e');
    }
  }

  Future<File> _flipHorizontallyIfNeeded(File imageFile) async {
    try {
      final tempDir = await getTemporaryDirectory();

      // 1. Bake EXIF rotation so the physical pixel buffer is guaranteed upright portrait on all devices
      final normalizedPath = '${tempDir.path}${Platform.pathSeparator}norm_${DateTime.now().microsecondsSinceEpoch}.jpg';
      final compressed = await FlutterImageCompress.compressAndGetFile(
        imageFile.absolute.path,
        normalizedPath,
        quality: 95,
        format: CompressFormat.jpeg,
        keepExif: false,
        autoCorrectionAngle: true,
      );
      final workingFile = compressed != null ? File(compressed.path) : imageFile;

      if (!_isUsingFrontCamera) return workingFile;

      final bytes = await workingFile.readAsBytes();
      if (bytes.isEmpty) return workingFile;

      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // Now that orientation is genuinely upright, mirror horizontally to match the front camera preview
      canvas.translate(image.width.toDouble(), 0);
      canvas.scale(-1, 1);
      canvas.drawImage(image, Offset.zero, Paint());

      final picture = recorder.endRecording();
      final flippedImage = await picture.toImage(image.width, image.height);
      final byteData =
          await flippedImage.toByteData(format: ui.ImageByteFormat.png);

      if (byteData == null) return workingFile;

      final flippedFile = File(
        '${tempDir.path}${Platform.pathSeparator}selfie_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      final outJpg = await FlutterImageCompress.compressWithList(
        byteData.buffer.asUint8List(),
        quality: 95,
        format: CompressFormat.jpeg,
      );
      await flippedFile.writeAsBytes(outJpg, flush: true);
      return flippedFile;
    } catch (e) {
      debugPrint('[FLIP SELFIE ERROR] $e');
      return imageFile;
    }
  }

  Future<void> _takePhoto() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        controller.value.isTakingPicture) {
      return;
    }

    try {
      final XFile photo = await controller.takePicture();
      final File rawFile = File(photo.path);
      final File finalFile = await _flipHorizontallyIfNeeded(rawFile);
      if (!mounted) return;
      Navigator.pop(context, finalFile);
    } catch (e) {
      debugPrint('[TAKE PHOTO ERROR] $e');
    }
  }

  Future<void> _startRecording() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        controller.value.isRecordingVideo) {
      return;
    }

    try {
      await controller.startVideoRecording();
      setState(() {
        _isRecording = true;
        _recordingSeconds = 0;
      });
      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted) {
          setState(() => _recordingSeconds++);
        }
      });
    } catch (e) {
      debugPrint('[START RECORDING ERROR] $e');
    }
  }

  Future<void> _stopRecording() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        !controller.value.isRecordingVideo) {
      return;
    }

    try {
      _recordingTimer?.cancel();
      final XFile video = await controller.stopVideoRecording();
      setState(() => _isRecording = false);
      if (!mounted) return;
      Navigator.pop(context, File(video.path));
    } catch (e) {
      debugPrint('[STOP RECORDING ERROR] $e');
      if (mounted) setState(() => _isRecording = false);
    }
  }

  void _onControllerUpdate() {
    if (mounted) setState(() {});
  }

  String _formatRecordingTime(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  double get _previewAspectRatio {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return 1.0;
    final aspect = controller.value.aspectRatio;
    return aspect < 1.0 ? aspect : 1.0 / aspect;
  }

  void _onZoomSliderDragStart(DragStartDetails details) {
    _zoomSliderHideTimer?.cancel();
    setState(() {
      _showZoomSlider = true;
      _sliderDragStartX = details.globalPosition.dx;
      _sliderDragStartZoom = _displayedZoom;
    });
  }

  void _onZoomSliderDragUpdate(DragUpdateDetails details) {
    _zoomSliderHideTimer?.cancel();
    final deltaX = details.globalPosition.dx - _sliderDragStartX;
    final zoomDelta = (deltaX / 140.0) * (_maxZoom > 4.0 ? 3.5 : 2.0);
    final minZ = _isUsingUltraWide
        ? 0.5
        : (_zoomMode == ZoomMode.lensSwap && _ultraWideCamera != null ? 0.5 : 1.0);
    final newZoom = (_sliderDragStartZoom + zoomDelta).clamp(minZ, _maxZoom.clamp(minZ, 10.0));
    final floor = newZoom.floor();
    if (floor != _lastHapticZoomFloor) {
      _lastHapticZoomFloor = floor;
      HapticFeedback.selectionClick();
    }
    _requestZoom(newZoom);
  }

  void _onZoomSliderDragEnd([DragEndDetails? _]) {
    _zoomSliderHideTimer?.cancel();
    _zoomSliderHideTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _showZoomSlider = false);
    });
  }

  Widget _buildZoomControls() {
    final presets = _availableZoomPresets;
    if (presets.isEmpty) return const SizedBox.shrink();

    final minZ = _isUsingUltraWide
        ? 0.5
        : (_zoomMode == ZoomMode.lensSwap && _ultraWideCamera != null ? 0.5 : 1.0);
    final maxZ = _maxZoom.clamp(minZ + 1.0, 10.0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 1. iOS-style Curved Arc Zoom Slider (appears on drag or tap)
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 200),
          crossFadeState: _showZoomSlider
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          firstChild: const SizedBox(height: 0),
          secondChild: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GestureDetector(
              onHorizontalDragStart: _onZoomSliderDragStart,
              onHorizontalDragUpdate: _onZoomSliderDragUpdate,
              onHorizontalDragEnd: _onZoomSliderDragEnd,
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: 280,
                height: 52,
                child: CustomPaint(
                  painter: _IosZoomDialPainter(
                    currentZoom: _displayedZoom,
                    minZoom: minZ,
                    maxZoom: maxZ,
                  ),
                ),
              ),
            ),
          ),
        ),

        // 2. Preset Pills (tap to jump, drag horizontally to slide/open curved dial)
        GestureDetector(
          onHorizontalDragStart: _onZoomSliderDragStart,
          onHorizontalDragUpdate: _onZoomSliderDragUpdate,
          onHorizontalDragEnd: _onZoomSliderDragEnd,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.white24,
                width: 0.8,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: presets.map((preset) {
                final bool isExactMatch = (_displayedZoom - preset).abs() < 0.05;
                final bool isClosest = presets.every(
                  (p) => (_displayedZoom - preset).abs() <= (_displayedZoom - p).abs(),
                );
                final bool isSelected = isExactMatch || isClosest;

                String label;
                if (preset == 0.5) {
                  label = '.5';
                } else if (preset == 1.0) {
                  label = '1x';
                } else if (preset == 2.0) {
                  label = '2x';
                } else if (preset == 3.0) {
                  label = '3x';
                } else {
                  label = '${preset.toStringAsFixed(1)}x';
                }

                if (isSelected && !isExactMatch) {
                  label = '${_displayedZoom.toStringAsFixed(1)}x';
                }

                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    _requestZoom(preset);
                    setState(() {
                      _showZoomSlider = true;
                      _sliderDragStartZoom = preset;
                    });
                    _onZoomSliderDragEnd();
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFFFFCC00) : Colors.transparent,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        color: isSelected ? Colors.black : Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final isReady =
        controller != null && controller.value.isInitialized;

    final bool needsQuarterFix = _iosQuarterFix &&
        (_isUsingFrontCamera ||
            (controller != null &&
                controller.description.lensDirection ==
                    CameraLensDirection.front));

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Viewfinder Frame with smooth 150ms AnimatedOpacity for lens swap (Phase 3)
          Positioned.fill(
            child: Center(
              child: AspectRatio(
                aspectRatio: _previewAspectRatio,
                child: GestureDetector(
                  onScaleStart: (_) {
                    _baseZoom = _displayedZoom;
                    _latestPinchDisplayZoom = _displayedZoom;
                    _isPinching = true;
                  },
                  onScaleUpdate: (details) {
                    final targetDisplay = _baseZoom * details.scale;
                    _latestPinchDisplayZoom = targetDisplay;
                    _requestZoom(targetDisplay);
                  },
                  onScaleEnd: (_) {
                    _isPinching = false;
                    _requestZoom(_latestPinchDisplayZoom);
                  },
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 150),
                    opacity: _isInitializing ? 0.0 : 1.0,
                    child: isReady
                        ? (needsQuarterFix
                            ? RotatedBox(
                                quarterTurns: _previewTurns(controller),
                                child: controller.buildPreview(),
                              )
                            : CameraPreview(controller))
                        : const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),

          if (_isInitializing && !isReady)
            const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),

          // 2. Top Vignette Gradient Overlay
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 120,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black38, Colors.transparent],
                ),
              ),
            ),
          ),

          // 3. Top Action Bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 26, 16, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Close Button
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: const BoxDecoration(
                          color: Colors.black45,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),

                    // Timer Pill
                    if (_mode == CameraMode.video || _isRecording)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _isRecording
                              ? Colors.redAccent.withValues(alpha: 0.85)
                              : Colors.black45,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          _isRecording
                              ? _formatRecordingTime(_recordingSeconds)
                              : '00:00',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                      )
                    else
                      const SizedBox(width: 42),

                    // Flash Toggle
                    GestureDetector(
                      onTap: _toggleFlash,
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: const BoxDecoration(
                          color: Colors.black45,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _flashMode == FlashMode.off
                              ? CupertinoIcons.bolt_slash_fill
                              : (_flashMode == FlashMode.auto
                                  ? CupertinoIcons.bolt_badge_a_fill
                                  : CupertinoIcons.bolt_fill),
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 4. Bottom Shutter & Controls Bar (UI stays visible during swap!)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12, top: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Zoom Indicator Pills
                    _buildZoomControls(),

                    const SizedBox(height: 16),

                    // Main Action Buttons Row
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Left: Gallery Picker
                          GestureDetector(
                            onTap: _pickFromGallery,
                            child: Container(
                              width: 48,
                              height: 48,
                              decoration: const BoxDecoration(
                                color: Colors.white24,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                CupertinoIcons.photo,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                          ),

                          // Center-Left: Secondary Flash/Light Toggle
                          GestureDetector(
                            onTap: _toggleFlash,
                            child: Container(
                              width: 42,
                              height: 42,
                              decoration: const BoxDecoration(
                                color: Colors.white12,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                CupertinoIcons.sparkles,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),

                          // Center: Shutter Button
                          GestureDetector(
                            onTap: () {
                              if (_mode == CameraMode.photo) {
                                _takePhoto();
                              } else {
                                if (_isRecording) {
                                  _stopRecording();
                                } else {
                                  _startRecording();
                                }
                              }
                            },
                            onLongPressStart: (_) {
                              if (!_isRecording) {
                                _startRecording();
                              }
                            },
                            onLongPressEnd: (_) {
                              if (_isRecording) {
                                _stopRecording();
                              }
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _isRecording
                                      ? Colors.redAccent
                                      : Colors.white,
                                  width: 4,
                                ),
                              ),
                              child: Center(
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  width: _isRecording ? 42 : 64,
                                  height: _isRecording ? 42 : 64,
                                  decoration: BoxDecoration(
                                    color: _mode == CameraMode.video ||
                                            _isRecording
                                        ? const Color(0xFFFF2B54)
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(
                                      _isRecording ? 10 : 40,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(width: 42),

                          // Right: Camera Switch (Front / Rear)
                          GestureDetector(
                            onTap: _toggleCamera,
                            child: Container(
                              width: 48,
                              height: 48,
                              decoration: const BoxDecoration(
                                color: Colors.white24,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                CupertinoIcons.arrow_2_circlepath,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Bottom Mode Selector: VIDEO | PHOTO
                    if (!_isRecording)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          GestureDetector(
                            onTap: () {
                              setState(() => _mode = CameraMode.video);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 4,
                              ),
                              child: Text(
                                'VIDEO',
                                style: TextStyle(
                                  color: _mode == CameraMode.video
                                      ? const Color(0xFFFFCC00)
                                      : Colors.white70,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          GestureDetector(
                            onTap: () {
                              setState(() => _mode = CameraMode.photo);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 4,
                              ),
                              child: Text(
                                'PHOTO',
                                style: TextStyle(
                                  color: _mode == CameraMode.photo
                                      ? const Color(0xFFFFCC00)
                                      : Colors.white70,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ),
                          ),
                        ],
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
}

/// Native iOS-style curved arc ruler for camera zoom
class _IosZoomDialPainter extends CustomPainter {
  final double currentZoom;
  final double minZoom;
  final double maxZoom;

  _IosZoomDialPainter({
    required this.currentZoom,
    required this.minZoom,
    required this.maxZoom,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final arcCenter = Offset(centerX, size.height + 150);
    const arcRadius = 185.0;

    final arcPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.20)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    // Draw background guide arc
    canvas.drawArc(
      Rect.fromCircle(center: arcCenter, radius: arcRadius),
      -math.pi / 2 - 0.42,
      0.84,
      false,
      arcPaint,
    );

    final tickPaint = Paint()..strokeCap = StrokeCap.round;

    // Draw ticks along arc relative to center
    for (double z = minZoom; z <= maxZoom; z += 0.2) {
      final isMajor = (z == 0.5 || (z - z.round()).abs() < 0.05);
      final diff = z - currentZoom;
      final angle = -math.pi / 2 + (diff * 0.18);

      if (angle < -math.pi / 2 - 0.42 || angle > -math.pi / 2 + 0.42) continue;

      final startR = isMajor ? arcRadius - 10 : arcRadius - 5;
      final endR = arcRadius + 3;

      final p1 = Offset(
        arcCenter.dx + startR * math.cos(angle),
        arcCenter.dy + startR * math.sin(angle),
      );
      final p2 = Offset(
        arcCenter.dx + endR * math.cos(angle),
        arcCenter.dy + endR * math.sin(angle),
      );

      tickPaint.color = isMajor
          ? Colors.white.withValues(alpha: 0.9)
          : Colors.white.withValues(alpha: 0.35);
      tickPaint.strokeWidth = isMajor ? 2.0 : 1.0;
      canvas.drawLine(p1, p2, tickPaint);
    }

    // Prominent yellow needle in center
    final needlePaint = Paint()
      ..color = const Color(0xFFFFCC00)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final n1 = Offset(centerX, arcCenter.dy - arcRadius + 15);
    final n2 = Offset(centerX, arcCenter.dy - arcRadius - 6);
    canvas.drawLine(n1, n2, needlePaint);
  }

  @override
  bool shouldRepaint(covariant _IosZoomDialPainter oldDelegate) {
    return oldDelegate.currentZoom != currentZoom;
  }
}

