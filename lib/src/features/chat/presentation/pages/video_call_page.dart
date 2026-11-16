import 'dart:async';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../../core/widgets/ios_avatar.dart';
import '../../domain/services/call_service.dart';

class VideoCallPage extends StatefulWidget {
  const VideoCallPage({super.key});

  @override
  State<VideoCallPage> createState() => _VideoCallPageState();
}

class _VideoCallPageState extends State<VideoCallPage> {
  final _callService = CallService.instance;
  bool _isSwapped = false; // false = remote main, local small; true = local main, remote small
  Offset? _smallWindowOffset;
  bool _isPinnedLeft = false;
  bool _isPinnedRight = false;
  bool _showAudioRoutePopup = false;
  bool _showControls = true;
  String? _toastMessage;
  String? _switchingToDeviceId; // ID of device currently being switched to

  double _baseZoomScale = 1.0;
  bool _showZoomBadge = false;
  Timer? _zoomBadgeTimer;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.primaryFocus?.unfocus();
    unawaited(SystemChannels.textInput.invokeMethod('TextInput.hide'));
    _callService.addListener(_onCallStateChanged);

    _callService.refreshAudioDevices().then((_) async {
      await _callService.getAudioRouteInfo();
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _callService.removeListener(_onCallStateChanged);
    super.dispose();
  }

  void _onCallStateChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _showToast(String message) {
    setState(() {
      _toastMessage = message;
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && _toastMessage == message) {
        setState(() {
          _toastMessage = null;
        });
      }
    });
  }

  void _minimize() {
    _callService.setMinimized(true);
  }

  void _handleAudioTap() async {
    // Refresh both device list and route info so popup shows current state
    await Future.wait([
      _callService.refreshAudioDevices(),
      _callService.getAudioRouteInfo(),
    ]);
    if (!mounted) return;

    if (_callService.hasConnectedHeadphones) {
      setState(() => _showAudioRoutePopup = !_showAudioRoutePopup);
    } else {
      // Video calls have no earpiece: stay on speaker
      await _callService.setAudioRoute(AudioRoute.speaker, isUserAction: true);
      if (mounted) setState(() => _showAudioRoutePopup = false);
    }
  }

  bool get _isAudioButtonActive {
    if (_showAudioRoutePopup) return true;
    return _callService.audioRoute == AudioRoute.speaker ||
        _callService.audioRoute == AudioRoute.bluetooth;
  }

  IconData _getAudioRouteIcon() {
    final route = _callService.audioRoute;
    switch (route) {
      case AudioRoute.bluetooth:
        if (_callService.activeDeviceType == 'CarAudio' ||
            _callService.connectedHeadsetName.toLowerCase().contains('car') ||
            _callService.connectedHeadsetName.toLowerCase().contains('carplay')) {
          return CupertinoIcons.car;
        }
        return CupertinoIcons.headphones;
      case AudioRoute.speaker:
      case AudioRoute.earpiece:
        return CupertinoIcons.speaker_3_fill;
    }
  }

  Widget _buildQualityPill() {
    final quality = _callService.networkQuality;
    final isPoor = quality == CallNetworkQuality.poor;
    final isGood = quality == CallNetworkQuality.good;

    final badgeColor = isPoor
        ? const Color(0xFFFF9F0A)
        : (isGood ? const Color(0xFF30D158) : const Color(0xFF64D2FF));
    final badgeText = isPoor ? 'Weak Net' : 'HD';

    final duration = _callService.duration;
    final m = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    final timeStr = duration.inHours > 0
        ? '${duration.inHours.toString().padLeft(2, '0')}:$m:$s'
        : '$m:$s';

    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: const Color(0x60404040),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.24),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: badgeColor.withValues(alpha: 0.7),
                    width: 0.8,
                  ),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(
                    color: badgeColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                timeStr,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRemoteVideoWidget() {
    if (!_callService.remoteVideoOn ||
        _callService.state != CallState.active ||
        _callService.remoteRenderer.srcObject == null ||
        !_callService.hasFirstRemoteFrame) {
      return Container(
        color: const Color(0xFF17191D),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IosAvatar(
                name: _callService.peerName,
                imagePath: _callService.peerAvatar,
                size: 96,
                showOnline: false,
              ),
              const SizedBox(height: 14),
              Text(
                _callService.peerName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _callService.state == CallState.active
                    ? 'Camera Off'
                    : (_callService.state == CallState.outgoingRinging
                        ? 'Ringing…'
                        : 'Connecting…'),
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return RTCVideoView(
      _callService.remoteRenderer,
      key: ValueKey('remote_${_callService.callId}_${_callService.remoteRenderer.srcObject?.id}'),
      mirror: false,
      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
    );
  }

  Widget _buildLocalVideoWidget() {
    if (!_callService.camOn ||
        _callService.localRenderer.srcObject == null ||
        !_callService.hasFirstLocalFrame) {
      return Container(
        color: const Color(0xFF22282C),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                CupertinoIcons.videocam,
                color: Colors.white54,
                size: 32,
              ),
              SizedBox(height: 6),
              Text(
                'Camera Off',
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ),
        ),
      );
    }
    return RTCVideoView(
      _callService.localRenderer,
      key: ValueKey('local_${_callService.callId}_${_callService.isFrontCamera}_${_callService.localRenderer.srcObject?.id}'),
      mirror: _callService.isFrontCamera,
      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
    );
  }

  Widget _buildZoomableLocalVideoWidget() {
    return GestureDetector(
      onScaleStart: (details) {
        _baseZoomScale = _callService.cameraZoomScale;
      },
      onScaleUpdate: (details) {
        if (details.scale != 1.0) {
          final targetScale = (_baseZoomScale * details.scale).clamp(1.0, 5.0);
          _callService.setCameraZoom(targetScale);
          setState(() {
            _showZoomBadge = true;
          });
          _zoomBadgeTimer?.cancel();
          _zoomBadgeTimer = Timer(const Duration(milliseconds: 1500), () {
            if (mounted) setState(() => _showZoomBadge = false);
          });
        }
      },
      behavior: HitTestBehavior.translucent,
      child: _buildLocalVideoWidget(),
    );
  }

  Widget _buildPipWindow(Size screenSize, double topPadding, double bottomPadding) {
    const pipWidth = 112.0;
    const pipHeight = 198.0;

    // 1. Pinned to Left Edge
    if (_isPinnedLeft) {
      return AnimatedPositioned(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        left: 0,
        top: (_smallWindowOffset?.dy ?? (topPadding + 90.0)).clamp(topPadding + 60.0, screenSize.height - bottomPadding - 200.0),
        child: GestureDetector(
          onTap: () {
            setState(() {
              _isPinnedLeft = false;
              _smallWindowOffset = Offset(16.0, _smallWindowOffset?.dy ?? (topPadding + 90.0));
            });
          },
          child: Container(
            width: 32,
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xDC232326),
              borderRadius: const BorderRadius.horizontal(right: Radius.circular(18)),
              border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1.5),
              boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 12)],
            ),
            child: const Center(
              child: Icon(CupertinoIcons.chevron_right, color: Colors.white, size: 20),
            ),
          ),
        ),
      );
    }

    // 2. Pinned to Right Edge
    if (_isPinnedRight) {
      return AnimatedPositioned(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        right: 0,
        top: (_smallWindowOffset?.dy ?? (topPadding + 90.0)).clamp(topPadding + 60.0, screenSize.height - bottomPadding - 200.0),
        child: GestureDetector(
          onTap: () {
            setState(() {
              _isPinnedRight = false;
              _smallWindowOffset = Offset(screenSize.width - pipWidth - 16.0, _smallWindowOffset?.dy ?? (topPadding + 90.0));
            });
          },
          child: Container(
            width: 32,
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xDC232326),
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(18)),
              border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1.5),
              boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 12)],
            ),
            child: const Center(
              child: Icon(CupertinoIcons.chevron_left, color: Colors.white, size: 20),
            ),
          ),
        ),
      );
    }

    // 3. Normal Floating / Draggable Window
    final maxAllowedY = screenSize.height - bottomPadding - 120.0 - pipHeight;
    _smallWindowOffset ??= Offset(16.0, topPadding + 90.0);

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      left: _smallWindowOffset!.dx,
      top: _smallWindowOffset!.dy.clamp(topPadding + 60.0, maxAllowedY),
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            double newX = _smallWindowOffset!.dx + details.delta.dx;
            double newY = _smallWindowOffset!.dy + details.delta.dy;
            newY = newY.clamp(topPadding + 60.0, maxAllowedY);
            _smallWindowOffset = Offset(newX, newY);
          });
        },
        onPanEnd: (_) {
          setState(() {
            final currentX = _smallWindowOffset!.dx;

            if (currentX <= 12.0) {
              _isPinnedLeft = true;
              _isPinnedRight = false;
            } else if (currentX >= screenSize.width - pipWidth - 12.0) {
              _isPinnedRight = true;
              _isPinnedLeft = false;
            } else {
              _isPinnedLeft = false;
              _isPinnedRight = false;
              final targetX = currentX < (screenSize.width / 2 - pipWidth / 2)
                  ? 16.0
                  : (screenSize.width - pipWidth - 90.0); // Keep space for control buttons
              _smallWindowOffset = Offset(targetX, _smallWindowOffset!.dy);
            }
          });
        },
        onTap: () {
          setState(() {
            _isSwapped = !_isSwapped;
          });
          _showToast(_isSwapped
              ? 'You are now full screen'
              : '${_callService.peerName} is now full screen');
        },
        child: Container(
          width: pipWidth,
          height: pipHeight,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.28),
              width: 1.5,
            ),
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 20,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Stack(
              children: [
                Positioned.fill(
                  child: _isSwapped ? _buildRemoteVideoWidget() : _buildZoomableLocalVideoWidget(),
                ),

                // Participant Label & Tap to Swap Hint
                Positioned(
                  bottom: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _isSwapped ? _callService.peerName : 'You',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),

                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      CupertinoIcons.arrow_2_squarepath,
                      color: Colors.white,
                      size: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.paddingOf(context).top;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final screenSize = MediaQuery.of(context).size;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop && _callService.state != CallState.idle) {
          _callService.setMinimized(true);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onTap: () {
            setState(() {
              _showControls = !_showControls;
            });
          },
          behavior: HitTestBehavior.opaque,
          child: Stack(
            children: [
              // 1. Main Full Screen Video View (Remote or Swapped Local View)
              Positioned.fill(
                child: _isSwapped ? _buildZoomableLocalVideoWidget() : _buildRemoteVideoWidget(),
              ),

              // Zoom Level Indicator Badge Overlay
              if (_showZoomBadge || _callService.cameraZoomScale != 1.0)
                Positioned(
                  top: topPadding + 70,
                  left: screenSize.width / 2 - 30,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: _showZoomBadge ? 1.0 : 0.0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white24, width: 1),
                      ),
                      child: Text(
                        '${_callService.cameraZoomScale.toStringAsFixed(1)}x',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),

              // 2. Floating Draggable / Pinnable PiP Window
              _buildPipWindow(screenSize, topPadding, bottomPadding),

              // 3. Top Glass Contact Bar
              Positioned(
                top: topPadding + 8,
                left: 20,
                right: 20,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Contact Pill Glass Button (Minimize / Contact Info)
                    GestureDetector(
                      onTap: _minimize,
                      behavior: HitTestBehavior.opaque,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(30),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                          child: Container(
                            height: 50,
                            padding: const EdgeInsets.only(left: 6, right: 14),
                            decoration: BoxDecoration(
                              color: const Color(0x60404040),
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.24),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IosAvatar(
                                  name: _callService.peerName,
                                  imagePath: _callService.peerAvatar,
                                  size: 38,
                                  showOnline: false,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  _callService.peerName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Icon(
                                  CupertinoIcons.chevron_down,
                                  color: Colors.white70,
                                  size: 16,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_callService.state == CallState.active)
                      _buildQualityPill(),
                  ],
                ),
              ),

              // 4. Right-Side Glass Control Column (Hide/Show on Tap)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                right: _showControls ? 20 : -90,
                bottom: bottomPadding + 20,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: _showControls ? 1.0 : 0.0,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 1. Camera On/Off
                      _LiquidGlassButton(
                        icon: _callService.camOn
                            ? CupertinoIcons.videocam_fill
                            : CupertinoIcons.videocam,
                        isActive: _callService.camOn,
                        onTap: () {
                          _callService.toggleCamera();
                          _showToast(_callService.camOn ? 'Camera on' : 'Camera off');
                        },
                      ),
                      const SizedBox(height: 12),

                      // 2. Mute / Unmute
                      _LiquidGlassButton(
                        icon: _callService.micOn
                            ? CupertinoIcons.mic_fill
                            : CupertinoIcons.mic_slash_fill,
                        isActive: _callService.micOn,
                        isWarning: !_callService.micOn,
                        onTap: () {
                          _callService.toggleMute();
                          _showToast(_callService.micOn ? 'Microphone on' : 'Microphone muted');
                        },
                      ),
                      const SizedBox(height: 12),

                      // 3. Audio Output (Speaker / Headphones)
                      _LiquidGlassButton(
                        icon: _getAudioRouteIcon(),
                        isActive: _isAudioButtonActive,
                        onTap: _handleAudioTap,
                      ),
                      const SizedBox(height: 12),

                      // 4. Flip Camera
                      _LiquidGlassButton(
                        icon: CupertinoIcons.camera_rotate_fill,
                        onTap: () async {
                          await _callService.switchCamera();
                          _showToast('Camera flipped');
                        },
                      ),
                      const SizedBox(height: 12),

                      // 5. End Call (RED BUTTON)
                      _LiquidGlassButton(
                        icon: CupertinoIcons.phone_down_fill,
                        isDanger: true,
                        onTap: () async {
                          await _callService.hangUp();
                        },
                      ),
                    ],
                  ),
                ),
              ),

            // 6. Audio Route Popover Sheet
            if (_showAudioRoutePopup)
              _buildAudioRoutePopover(context, bottomPadding),

            // 7. Dynamic Toast Banner
            if (_toastMessage != null)
              Positioned(
                bottom: bottomPadding + 24,
                left: 0,
                right: 0,
                child: Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(25),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xDC232326),
                          borderRadius: BorderRadius.circular(25),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.25),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          _toastMessage!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAudioRoutePopover(BuildContext context, double bottomPadding) {
    final options = _callService.getAvailableAudioOptions();

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: () {
              if (mounted) {
                setState(() {
                  _showAudioRoutePopup = false;
                });
              }
            },
            behavior: HitTestBehavior.opaque,
            child: Container(color: Colors.transparent),
          ),
        ),
        Positioned(
          right: 90,
          bottom: bottomPadding + 140,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
              child: Container(
                width: 260,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xDC323238),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.24),
                    width: 1,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black45,
                      blurRadius: 25,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'AUDIO OUTPUT',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.55),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                    ),
                    for (final opt in options)
                      _AudioPopoverRow(
                        icon: opt.icon,
                        title: opt.label,
                        subtitle: opt.subtitle,
                        isSelected: _callService.isAudioOptionSelected(opt),
                        isSwitching: _switchingToDeviceId == opt.id,
                        onTap: () async {
                          setState(() => _switchingToDeviceId = opt.id);
                          await _callService.selectAudioOption(opt);
                          _showToast('Audio switched to ${opt.label}');
                          if (mounted) {
                            setState(() {
                              _switchingToDeviceId = null;
                              _showAudioRoutePopup = false;
                            });
                          }
                        },
                      ),
                    if (defaultTargetPlatform == TargetPlatform.iOS) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        child: Divider(color: Colors.white.withValues(alpha: 0.12), height: 1),
                      ),
                      _AudioPopoverRow(
                        icon: Icons.airplay,
                        title: 'AirPlay & Bluetooth…',
                        subtitle: 'Switch between audio devices',
                        isSelected: false,
                        onTap: () {
                          _callService.showSystemRoutePicker();
                          _showToast('Select device or switch from Control Center');
                          if (mounted) {
                            setState(() {
                              _showAudioRoutePopup = false;
                            });
                          }
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AudioPopoverRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isSelected;
  final bool isSwitching;
  final VoidCallback onTap;

  const _AudioPopoverRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
    this.isSwitching = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected || isSwitching
                      ? const Color(0x3359D36C)
                      : Colors.white.withValues(alpha: 0.12),
                ),
                child: Center(
                  child: isSwitching
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF59D36C)),
                          ),
                        )
                      : Icon(
                          icon,
                          color: isSelected ? const Color(0xFF59D36C) : Colors.white,
                          size: 18,
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected && !isSwitching)
                const Icon(
                  CupertinoIcons.checkmark,
                  color: Color(0xFF59D36C),
                  size: 18,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LiquidGlassButton extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final bool isWarning;
  final bool isDanger;
  final VoidCallback onTap;

  const _LiquidGlassButton({
    required this.icon,
    this.isActive = false,
    this.isWarning = false,
    this.isDanger = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color border;
    Color iconColor;
    List<BoxShadow>? shadows;

    if (isDanger) {
      bg = const Color(0xFFFF3B30);
      border = const Color(0x66FF7268);
      iconColor = Colors.white;
      shadows = [
        BoxShadow(
          color: const Color(0xFFFF3B30).withValues(alpha: 0.45),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ];
    } else if (isWarning) {
      bg = Colors.white.withValues(alpha: 0.18);
      border = const Color(0x66FF9F36);
      iconColor = const Color(0xFFFF9F36);
    } else if (isActive) {
      bg = Colors.white.withValues(alpha: 0.94);
      border = Colors.white;
      iconColor = const Color(0xFF141417);
      shadows = [
        BoxShadow(
          color: Colors.white.withValues(alpha: 0.25),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ];
    } else {
      bg = const Color(0x60404040);
      border = Colors.white.withValues(alpha: 0.24);
      iconColor = Colors.white;
    }

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: bg,
              shape: BoxShape.circle,
              border: Border.all(color: border, width: 1),
              boxShadow: shadows,
            ),
            child: Center(
              child: Icon(icon, color: iconColor, size: 26),
            ),
          ),
        ),
      ),
    );
  }
}
