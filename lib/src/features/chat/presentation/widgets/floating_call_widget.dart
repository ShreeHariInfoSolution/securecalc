import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../../core/widgets/ios_avatar.dart';
import '../../domain/services/call_service.dart';

class FloatingCallWidget extends StatefulWidget {
  final CallService callService;
  final VoidCallback onTap;

  const FloatingCallWidget({
    super.key,
    required this.callService,
    required this.onTap,
  });

  @override
  State<FloatingCallWidget> createState() => _FloatingCallWidgetState();
}

class _FloatingCallWidgetState extends State<FloatingCallWidget> {
  Offset? _position;
  bool _isDragging = false;
  bool _isCollapsedLeft = false;
  bool _isCollapsedRight = false;

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.callService.callType == CallType.video;
    final topPadding = MediaQuery.paddingOf(context).top;
    final screenSize = MediaQuery.of(context).size;

    final widgetWidth = isVideo ? 130.0 : 270.0;
    final widgetHeight = isVideo ? 180.0 : 50.0;

    // Default initial position (Centered at Top Notification / Status Bar Area)
    _position ??= Offset(
      (screenSize.width - widgetWidth) / 2,
      topPadding + 4.0,
    );

    double currentLeft = _position!.dx;
    if (_isCollapsedRight) {
      currentLeft = screenSize.width - 32.0;
    } else if (_isCollapsedLeft) {
      currentLeft = 0.0;
    }

    return AnimatedPositioned(
      duration: _isDragging ? Duration.zero : const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      left: currentLeft,
      top: _position!.dy,
      child: GestureDetector(
        onPanStart: (_) {
          setState(() {
            _isDragging = true;
          });
        },
        onPanUpdate: (details) {
          setState(() {
            double newX = _position!.dx + details.delta.dx;
            double newY = _position!.dy + details.delta.dy;

            // Clamp vertical position
            newY = newY.clamp(topPadding + 6.0, screenSize.height - widgetHeight - 20.0);

            // Auto-expand if dragged inward when collapsed
            if (_isCollapsedRight && details.delta.dx < -4) {
              _isCollapsedRight = false;
              newX = screenSize.width - widgetWidth - 16.0;
            } else if (_isCollapsedLeft && details.delta.dx > 4) {
              _isCollapsedLeft = false;
              newX = 16.0;
            } else if (!_isCollapsedLeft && !_isCollapsedRight) {
              newX = newX.clamp(-10.0, screenSize.width - widgetWidth + 10.0);
            }

            _position = Offset(newX, newY);
          });
        },
        onPanEnd: (_) {
          setState(() {
            _isDragging = false;

            if (_isCollapsedLeft || _isCollapsedRight) return;

            // Collapse to edge when slided/dragged to boundaries
            if (_position!.dx >= screenSize.width - widgetWidth - 8.0) {
              _isCollapsedRight = true;
              _isCollapsedLeft = false;
            } else if (_position!.dx <= 8.0) {
              _isCollapsedLeft = true;
              _isCollapsedRight = false;
            } else {
              _isCollapsedLeft = false;
              _isCollapsedRight = false;
              final midX = _position!.dx + (widgetWidth / 2);
              final targetX = midX < (screenSize.width / 2)
                  ? 16.0
                  : (screenSize.width - widgetWidth - 16.0);
              _position = Offset(targetX, _position!.dy);
            }
          });
        },
        child: _isCollapsedRight
            ? _buildRightCollapsedHandle(context, widgetWidth)
            : (_isCollapsedLeft
                ? _buildLeftCollapsedHandle(context)
                : (isVideo
                    ? _buildFloatingVideoCard(context)
                    : _buildFloatingVoiceBar(context))),
      ),
    );
  }

  /// Right Edge Collapsed Handle
  Widget _buildRightCollapsedHandle(BuildContext context, double widgetWidth) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _isCollapsedRight = false;
          final screenSize = MediaQuery.of(context).size;
          _position = Offset(screenSize.width - widgetWidth - 16.0, _position!.dy);
        });
      },
      child: Container(
        width: 32,
        height: 52,
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            bottomLeft: Radius.circular(16),
          ),
          border: Border.all(
            color: const Color(0xFF34C759),
            width: 1.5,
          ),
          boxShadow: const [
            BoxShadow(
              color: Colors.black45,
              blurRadius: 10,
              offset: Offset(-3, 3),
            ),
          ],
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              CupertinoIcons.chevron_left,
              color: Color(0xFF34C759),
              size: 15,
            ),
            SizedBox(height: 3),
            Icon(
              CupertinoIcons.phone_fill,
              color: Colors.white,
              size: 11,
            ),
          ],
        ),
      ),
    );
  }

  /// Left Edge Collapsed Handle
  Widget _buildLeftCollapsedHandle(BuildContext context) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _isCollapsedLeft = false;
          _position = Offset(16.0, _position!.dy);
        });
      },
      child: Container(
        width: 32,
        height: 52,
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: const BorderRadius.only(
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
          border: Border.all(
            color: const Color(0xFF34C759),
            width: 1.5,
          ),
          boxShadow: const [
            BoxShadow(
              color: Colors.black45,
              blurRadius: 10,
              offset: Offset(3, 3),
            ),
          ],
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              CupertinoIcons.chevron_right,
              color: Color(0xFF34C759),
              size: 15,
            ),
            SizedBox(height: 3),
            Icon(
              CupertinoIcons.phone_fill,
              color: Colors.white,
              size: 11,
            ),
          ],
        ),
      ),
    );
  }

  /// Draggable Mini Floating Video Call Window
  Widget _buildFloatingVideoCard(BuildContext context) {
    final callService = widget.callService;

    return Material(
      color: Colors.transparent,
      elevation: 16,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 130,
        height: 180,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.35),
            width: 1.5,
          ),
          boxShadow: const [
            BoxShadow(
              color: Colors.black54,
              blurRadius: 16,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            children: [
              // 1. Live RTC Video Stream
              Positioned.fill(
                child: GestureDetector(
                  onTap: widget.onTap,
                  child: callService.remoteVideoOn
                      ? RTCVideoView(
                          callService.remoteRenderer,
                          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                        )
                      : (callService.camOn
                          ? RTCVideoView(
                              callService.localRenderer,
                              mirror: true,
                              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                            )
                          : Container(
                              color: const Color(0xFF1C1C1E),
                              child: Center(
                                child: IosAvatar(
                                  name: callService.peerName,
                                  imagePath: callService.peerAvatar,
                                  size: 48,
                                  showOnline: false,
                                ),
                              ),
                            )),
                ),
              ),

              // 2. Gradient Vignette Top & Bottom
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black54,
                          Colors.transparent,
                          Colors.transparent,
                          Colors.black54,
                        ],
                        stops: [0.0, 0.35, 0.65, 1.0],
                      ),
                    ),
                  ),
                ),
              ),

              // 3. Top Header Info (Peer Name + Timer)
              Positioned(
                top: 8,
                left: 8,
                right: 8,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            callService.peerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                            ),
                          ),
                          Text(
                            callService.state == CallState.active
                                ? _formatDuration(callService.duration)
                                : 'Connecting…',
                            style: const TextStyle(
                              color: Color(0xFF34C759),
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Expand Button
                    GestureDetector(
                      onTap: widget.onTap,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.black45,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          CupertinoIcons.arrow_up_left_arrow_down_right,
                          color: Colors.white,
                          size: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 4. Bottom Controls (Mute & Hangup)
              Positioned(
                bottom: 8,
                left: 8,
                right: 8,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Mute Toggle
                    GestureDetector(
                      onTap: callService.toggleMute,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: callService.micOn ? Colors.black54 : Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          callService.micOn
                              ? CupertinoIcons.mic_fill
                              : CupertinoIcons.mic_slash_fill,
                          color: callService.micOn ? Colors.white : Colors.black,
                          size: 13,
                        ),
                      ),
                    ),

                    // End Call Button
                    GestureDetector(
                      onTap: () async {
                        await callService.hangUp();
                      },
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: Colors.redAccent,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          CupertinoIcons.phone_down_fill,
                          color: Colors.white,
                          size: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Draggable Voice Call Bar
  Widget _buildFloatingVoiceBar(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final callService = widget.callService;

    return GestureDetector(
      onTap: widget.onTap,
      child: Material(
        color: Colors.transparent,
        elevation: 12,
        shadowColor: Colors.black45,
        borderRadius: BorderRadius.circular(24),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF34C759).withValues(alpha: isDark ? 0.92 : 0.96),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Call Animated Pulse / Icon
                  Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(
                      color: Colors.white24,
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Icon(
                        CupertinoIcons.phone_fill,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Peer Name & Call Status
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        callService.peerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        callService.state == CallState.active
                            ? _formatDuration(callService.duration)
                            : 'Connecting…',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),

                  // Return Button
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Return',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(width: 3),
                        Icon(
                          CupertinoIcons.arrow_up_right,
                          color: Colors.white,
                          size: 12,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 8),

                  // Hangup Button
                  GestureDetector(
                    onTap: () async {
                      await callService.hangUp();
                    },
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: const BoxDecoration(
                        color: Colors.redAccent,
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Icon(
                          CupertinoIcons.phone_down_fill,
                          color: Colors.white,
                          size: 15,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
