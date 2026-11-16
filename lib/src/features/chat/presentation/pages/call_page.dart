import 'dart:async';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/ios_avatar.dart';
import '../../domain/services/call_service.dart';

enum _CallOverlayType { none, audioRoute }

class CallPage extends StatefulWidget {
  const CallPage({super.key});

  static Future<void> open(BuildContext context) async {
    FocusManager.instance.primaryFocus?.unfocus();
    unawaited(SystemChannels.textInput.invokeMethod('TextInput.hide'));
    CallService.instance.setMinimized(false);
  }

  @override
  State<CallPage> createState() => _CallPageState();
}

class _CallPageState extends State<CallPage> {
  final _callService = CallService.instance;
  bool _isSwapped = false; // false = remote main, local small; true = local main, remote small
  Offset? _smallWindowOffset;
  bool _isCollapsedLeft = false;
  bool _isCollapsedRight = false;
  bool _showControls = true;
  _CallOverlayType _activeOverlay = _CallOverlayType.none;

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

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (duration.inHours > 0) {
      final hours = duration.inHours.toString().padLeft(2, '0');
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  String _getStatusText() {
    switch (_callService.state) {
      case CallState.outgoingRinging:
        return 'Ringing…';
      case CallState.incomingRinging:
        return 'Incoming Call…';
      case CallState.connecting:
        return 'Connecting…';
      case CallState.active:
        return _formatDuration(_callService.duration);
      case CallState.ended:
        return 'Call Ended';
      case CallState.idle:
        return '';
    }
  }

  void _minimize() {
    _callService.setMinimized(true);
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
  }

  void _handleAudioRouteTap() async {
    await _callService.getAudioRouteInfo();
    if (!mounted) return;

    if (_callService.hasConnectedHeadphones) {
      setState(() {
        _activeOverlay = _activeOverlay == _CallOverlayType.audioRoute
            ? _CallOverlayType.none
            : _CallOverlayType.audioRoute;
      });
    } else {
      final nextRoute = _callService.audioRoute == AudioRoute.speaker
          ? AudioRoute.earpiece
          : AudioRoute.speaker;
      await _callService.setAudioRoute(nextRoute, isUserAction: true);
      if (mounted) {
        setState(() {
          _activeOverlay = _CallOverlayType.none;
        });
      }
    }
  }

  bool _isAudioButtonActive() {
    if (_activeOverlay == _CallOverlayType.audioRoute) {
      return true;
    }
    return _callService.audioRoute == AudioRoute.speaker ||
        _callService.audioRoute == AudioRoute.bluetooth;
  }

  Widget _buildRemoteVideoWidget() {
    if (!_callService.remoteVideoOn ||
        _callService.state != CallState.active ||
        _callService.remoteRenderer.srcObject == null ||
        !_callService.hasFirstRemoteFrame) {
      return Container(
        color: const Color(0xFF1C1C1E),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IosAvatar(
                name: _callService.peerName,
                imagePath: _callService.peerAvatar,
                size: 90,
                showOnline: false,
              ),
              const SizedBox(height: 12),
              Text(
                _callService.peerName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Camera Off',
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return RTCVideoView(
      _callService.remoteRenderer,
      key: ValueKey('remote_${_callService.callId}_${_callService.remoteIsFrontCamera}'),
      mirror: _callService.remoteIsFrontCamera,
      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
    );
  }

  Widget _buildLocalVideoWidget() {
    if (!_callService.camOn ||
        _callService.localRenderer.srcObject == null ||
        !_callService.hasFirstLocalFrame) {
      return Container(
        color: const Color(0xFF111113),
        child: const Center(
          child: Icon(
            Icons.videocam_off_rounded,
            color: Colors.white54,
            size: 32,
          ),
        ),
      );
    }
    return RTCVideoView(
      _callService.localRenderer,
      key: ValueKey('local_${_callService.callId}_${_callService.isFrontCamera}'),
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

    if (_isCollapsedLeft) {
      return AnimatedPositioned(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        left: 0,
        top: (_smallWindowOffset?.dy ?? (topPadding + 70.0)) + (pipHeight / 2) - 30,
        child: GestureDetector(
          onTap: () {
            setState(() {
              _isCollapsedLeft = false;
              _smallWindowOffset = Offset(16.0, _smallWindowOffset?.dy ?? (topPadding + 70.0));
            });
          },
          child: Container(
            width: 28,
            height: 60,
            decoration: BoxDecoration(
              color: const Color(0xCC1C1C1E),
              borderRadius: const BorderRadius.horizontal(right: Radius.circular(16)),
              border: Border.all(color: Colors.white30, width: 1.5),
              boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 10)],
            ),
            child: const Center(
              child: Icon(CupertinoIcons.chevron_right, color: Colors.white, size: 18),
            ),
          ),
        ),
      );
    }

    if (_isCollapsedRight) {
      return AnimatedPositioned(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        right: 0,
        top: (_smallWindowOffset?.dy ?? (topPadding + 70.0)) + (pipHeight / 2) - 30,
        child: GestureDetector(
          onTap: () {
            setState(() {
              _isCollapsedRight = false;
              _smallWindowOffset = Offset(screenSize.width - pipWidth - 16.0, _smallWindowOffset?.dy ?? (topPadding + 70.0));
            });
          },
          child: Container(
            width: 28,
            height: 60,
            decoration: BoxDecoration(
              color: const Color(0xCC1C1C1E),
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
              border: Border.all(color: Colors.white30, width: 1.5),
              boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 10)],
            ),
            child: const Center(
              child: Icon(CupertinoIcons.chevron_left, color: Colors.white, size: 18),
            ),
          ),
        ),
      );
    }

    final maxAllowedY = _showControls
        ? screenSize.height - bottomPadding - 110.0 - pipHeight
        : screenSize.height - bottomPadding - 24.0 - pipHeight;

    if (_smallWindowOffset != null && _smallWindowOffset!.dy > maxAllowedY) {
      _smallWindowOffset = Offset(_smallWindowOffset!.dx, maxAllowedY);
    }

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      left: _smallWindowOffset!.dx,
      top: _smallWindowOffset!.dy,
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
            final midX = _smallWindowOffset!.dx + (pipWidth / 2);
            final currentX = _smallWindowOffset!.dx;

            if (currentX <= 16.0) {
              _isCollapsedLeft = true;
              _isCollapsedRight = false;
            } else if (currentX >= screenSize.width - pipWidth - 16.0) {
              _isCollapsedRight = true;
              _isCollapsedLeft = false;
            } else {
              _isCollapsedLeft = false;
              _isCollapsedRight = false;
              final targetX = midX < (screenSize.width / 2)
                  ? 16.0
                  : (screenSize.width - pipWidth - 16.0);
              _smallWindowOffset = Offset(targetX, _smallWindowOffset!.dy);
            }
          });
        },
        onTap: () {
          setState(() {
            _isSwapped = !_isSwapped;
          });
        },
        child: Container(
          width: pipWidth,
          height: pipHeight,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.35),
              width: 2,
            ),
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 16,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              children: [
                Positioned.fill(
                  child: _isSwapped ? _buildRemoteVideoWidget() : _buildZoomableLocalVideoWidget(),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      CupertinoIcons.arrow_2_squarepath,
                      color: Colors.white,
                      size: 12,
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
    final isVideo = _callService.callType == CallType.video;
    final topPadding = MediaQuery.paddingOf(context).top;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final screenSize = MediaQuery.of(context).size;

    _smallWindowOffset ??= Offset(screenSize.width - 131, topPadding + 70);

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
          onTap: _toggleControls,
          behavior: HitTestBehavior.opaque,
          child: Stack(
            children: [
              // 1. Video Background or Voice Background
              if (isVideo && _callService.state == CallState.active) ...[
                Positioned.fill(
                  child: _isSwapped ? _buildZoomableLocalVideoWidget() : _buildRemoteVideoWidget(),
                ),
                _buildPipWindow(screenSize, topPadding, bottomPadding),

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
              ] else ...[
                Positioned.fill(
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0xFF1E1E24),
                          Color(0xFF121216),
                          Color(0xFF070709),
                        ],
                      ),
                    ),
                  ),
                ),
              ],

              // 2. Header Bar with Minimize Banner Button
              Positioned(
                top: topPadding + 10,
                left: 16,
                right: 16,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(
                      onTap: _minimize,
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.2),
                            width: 1,
                          ),
                        ),
                        child: const Center(
                          child: Icon(
                            CupertinoIcons.chevron_down,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isVideo ? CupertinoIcons.videocam_fill : CupertinoIcons.phone_fill,
                            color: AppTheme.primaryColor,
                            size: 15,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isVideo ? 'Video Call' : 'Voice Call',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 42),
                  ],
                ),
              ),

              // 3. Adaptive User Info Section (Voice Call or pre-active Video Call)
              if (!isVideo || _callService.state != CallState.active)
                Positioned(
                  top: topPadding + 60,
                  left: 20,
                  right: 20,
                  bottom: bottomPadding + 140,
                  child: Center(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppTheme.primaryColor.withValues(alpha: 0.12),
                                border: Border.all(
                                  color: AppTheme.primaryColor.withValues(alpha: 0.3),
                                  width: 2,
                                ),
                              ),
                              child: IosAvatar(
                                name: _callService.peerName,
                                imagePath: _callService.peerAvatar,
                                size: 88,
                                showOnline: false,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _callService.peerName,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _getStatusText(),
                            style: TextStyle(
                              color: _callService.state == CallState.active
                                  ? const Color(0xFF34C759)
                                  : Colors.white70,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // Video active info top banner overlay
              if (isVideo && _callService.state == CallState.active)
                Positioned(
                  top: topPadding + 62,
                  left: 20,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _callService.peerName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _getStatusText(),
                        style: const TextStyle(
                          color: Color(0xFF34C759),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
                        ),
                      ),
                    ],
                  ),
                ),



              // 4. Floating Control Bar
              AnimatedPositioned(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutBack,
                left: 16,
                right: 16,
                bottom: _showControls ? bottomPadding + 16 : -130,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 500),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(40),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xB32C2C2E),
                            borderRadius: BorderRadius.circular(40),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.22),
                              width: 1,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black45,
                                blurRadius: 20,
                                offset: Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Video Switch / Request Button
                              Expanded(
                                child: _CallControlButton(
                                  icon: isVideo ? CupertinoIcons.videocam_fill : CupertinoIcons.videocam,
                                  label: isVideo ? 'Video On' : 'Video',
                                  isActive: isVideo,
                                  onTap: () {
                                    if (isVideo) {
                                      _callService.switchCallType(CallType.voice);
                                    } else {
                                      _callService.requestVideoCallUpgrade();
                                    }
                                  },
                                ),
                              ),

                              // Camera Flip Button (when camera is on in video call)
                              if (isVideo && _callService.camOn)
                                Expanded(
                                  child: _CallControlButton(
                                    icon: CupertinoIcons.camera_rotate_fill,
                                    label: 'Flip',
                                    isActive: false,
                                    onTap: () {
                                      _callService.switchCamera();
                                    },
                                  ),
                                ),

                              // Speaker / Audio Route Button
                              Expanded(
                                child: _CallControlButton(
                                  icon: _getSpeakerIcon(_callService.audioRoute),
                                  label: _getSpeakerLabel(_callService.audioRoute),
                                  isActive: _isAudioButtonActive(),
                                  onTap: _handleAudioRouteTap,
                                ),
                              ),

                              // Mute Mic Button
                              Expanded(
                                child: _CallControlButton(
                                  icon: _callService.micOn
                                      ? CupertinoIcons.mic_fill
                                      : CupertinoIcons.mic_slash_fill,
                                  label: _callService.micOn ? 'Mute' : 'Muted',
                                  isActive: !_callService.micOn,
                                  onTap: _callService.toggleMute,
                                ),
                              ),

                              // End Call Button (Red Circle)
                              Expanded(
                                child: _CallControlButton(
                                  icon: CupertinoIcons.phone_down_fill,
                                  label: 'End',
                                  backgroundColor: const Color(0xFFFF3B30),
                                  iconColor: Colors.white,
                                  onTap: () async {
                                    await _callService.hangUp();
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // 5. Anchored Frosted Glass Pop-up Capsule Overlay
              if (_activeOverlay != _CallOverlayType.none)
                _buildCallOverlay(context, bottomPadding),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCallOverlay(BuildContext context, double bottomPadding) {
    final screenSize = MediaQuery.of(context).size;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: () {
              setState(() {
                _activeOverlay = _CallOverlayType.none;
              });
            },
            behavior: HitTestBehavior.opaque,
            child: Container(color: Colors.transparent),
          ),
        ),
        Positioned(
          bottom: bottomPadding + 115,
          left: 20,
          right: 20,
          child: Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: 320,
                    maxHeight: screenSize.height * 0.45,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xEB2C2C2E),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.22),
                      width: 1,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black54,
                        blurRadius: 25,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: _buildAudioRouteCard(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAudioRouteCard() {
    final options = _callService.getAvailableAudioOptions();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final opt in options)
          _PopUpMenuTile(
            icon: opt.icon,
            title: opt.label,
            subtitle: opt.subtitle,
            isSelected: _callService.isAudioOptionSelected(opt),
            onTap: () {
              _callService.selectAudioOption(opt);
              if (mounted) {
                setState(() {
                  _activeOverlay = _CallOverlayType.none;
                });
              }
            },
          ),
      ],
    );
  }

  IconData _getSpeakerIcon(AudioRoute route) {
    if (_callService.hasConnectedHeadphones && route == AudioRoute.bluetooth) {
      return CupertinoIcons.headphones;
    }
    switch (route) {
      case AudioRoute.speaker:
        return CupertinoIcons.speaker_3_fill;
      case AudioRoute.bluetooth:
        return CupertinoIcons.headphones;
      case AudioRoute.earpiece:
        return CupertinoIcons.phone_fill;
    }
  }

  String _getSpeakerLabel(AudioRoute route) {
    if (route == AudioRoute.bluetooth && _callService.hasConnectedHeadphones) {
      final name = _callService.connectedHeadsetName;
      if (name.isNotEmpty && name != 'Speaker' && name != 'Phone' && name != 'Earpiece') {
        return name.length > 8 ? '${name.substring(0, 7)}…' : name;
      }
      return 'Headset';
    }
    switch (route) {
      case AudioRoute.speaker:
        return 'Speaker';
      case AudioRoute.earpiece:
        return 'Phone';
      case AudioRoute.bluetooth:
        return 'Headset';
    }
  }
}

class _PopUpMenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  const _PopUpMenuTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                child: isSelected
                    ? const Icon(
                        CupertinoIcons.checkmark,
                        color: Colors.white,
                        size: 18,
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(width: 8),
              Icon(
                icon,
                color: isSelected ? Colors.white : Colors.white70,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontSize: 15,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CallControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final Color? backgroundColor;
  final Color? iconColor;
  final VoidCallback onTap;

  const _CallControlButton({
    required this.icon,
    required this.label,
    this.isActive = false,
    this.backgroundColor,
    this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ??
        (isActive ? Colors.white : Colors.white.withValues(alpha: 0.18));
    final ic = iconColor ?? (isActive ? Colors.black : Colors.white);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: bg,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Icon(icon, color: ic, size: 22),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
