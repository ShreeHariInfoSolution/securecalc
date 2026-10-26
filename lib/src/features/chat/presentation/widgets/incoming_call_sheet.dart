import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/ios_avatar.dart';
import '../../domain/services/call_service.dart';

class IncomingCallSheet extends StatefulWidget {
  final CallService callService;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const IncomingCallSheet({
    super.key,
    required this.callService,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  State<IncomingCallSheet> createState() => _IncomingCallSheetState();
}

class _IncomingCallSheetState extends State<IncomingCallSheet>
    with SingleTickerProviderStateMixin {
  bool _isMinimized = false;
  Alignment _dockAlignment = Alignment.centerRight;
  double _verticalOffset = 0;
  double _dragDx = 0;
  double _dragDy = 0;

  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _onPanUpdate(DragUpdateDetails details) {
    _dragDx += details.delta.dx;
    _dragDy += details.delta.dy;
    if (_isMinimized) {
      setState(() {
        _verticalOffset += details.delta.dy;
      });
    }
  }

  void _onPanEnd(DragEndDetails details) {
    final vX = details.velocity.pixelsPerSecond.dx;
    final vY = details.velocity.pixelsPerSecond.dy;

    if (!_isMinimized) {
      if (vX < -200 || _dragDx < -40) {
        // Swiped left -> dock left edge
        setState(() {
          _dockAlignment = Alignment.centerLeft;
          _isMinimized = true;
          _verticalOffset = 0;
        });
      } else if (vX > 200 || _dragDx > 40) {
        // Swiped right -> dock right edge
        setState(() {
          _dockAlignment = Alignment.centerRight;
          _isMinimized = true;
          _verticalOffset = 0;
        });
      } else if (vY < -200 || _dragDy < -40) {
        // Swiped up -> dock right edge higher up
        setState(() {
          _dockAlignment = Alignment.centerRight;
          _isMinimized = true;
          _verticalOffset = -180;
        });
      }
    } else {
      final isLeft = _dockAlignment == Alignment.centerLeft;
      // Swiping away from edge towards center expands back to full sheet
      if ((isLeft && (vX > 180 || _dragDx > 35)) ||
          (!isLeft && (vX < -180 || _dragDx < -35))) {
        setState(() {
          _isMinimized = false;
          _verticalOffset = 0;
        });
      }
    }
    _dragDx = 0;
    _dragDy = 0;
  }

  Widget _buildFullSheet(BuildContext context, bool isDark, bool isVideo) {
    return Align(
      key: const ValueKey('full_sheet'),
      alignment: Alignment.bottomCenter,
      child: Container(
        margin: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.paddingOf(context).bottom + 12,
        ),
        child: GestureDetector(
          onPanUpdate: _onPanUpdate,
          onPanEnd: _onPanEnd,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xF21C1C1E)
                      : Colors.white.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(
                    color: isDark ? Colors.white24 : Colors.black12,
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Top Indicator Pill
                    Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white30 : Colors.black26,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Slide hint
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          CupertinoIcons.chevron_left,
                          size: 11,
                          color: AppTheme.secondaryText(isDark).withValues(alpha: 0.6),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Swipe left or right to minimize to edge',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.secondaryText(isDark).withValues(alpha: 0.7),
                            decoration: TextDecoration.none,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          CupertinoIcons.chevron_right,
                          size: 11,
                          color: AppTheme.secondaryText(isDark).withValues(alpha: 0.6),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Avatar
                    IosAvatar(
                      name: widget.callService.peerName,
                      imagePath: widget.callService.peerAvatar,
                      size: 74,
                      showOnline: false,
                    ),
                    const SizedBox(height: 12),

                    // Peer Name
                    Text(
                      widget.callService.peerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryText(isDark),
                        letterSpacing: -0.4,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 4),

                    // Subtitle
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isVideo ? CupertinoIcons.videocam_fill : CupertinoIcons.phone_fill,
                          size: 14,
                          color: AppTheme.primaryColor,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isVideo ? 'Incoming Video Call…' : 'Incoming Voice Call…',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.secondaryText(isDark),
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),

                    // Action Buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Decline Button
                        GestureDetector(
                          onTap: widget.onDecline,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 62,
                                height: 62,
                                decoration: const BoxDecoration(
                                  color: Colors.redAccent,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.redAccent,
                                      blurRadius: 10,
                                      offset: Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: const Center(
                                  child: Icon(
                                    CupertinoIcons.phone_down_fill,
                                    color: Colors.white,
                                    size: 28,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Decline',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.secondaryText(isDark),
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Accept Button
                        GestureDetector(
                          onTap: widget.onAccept,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 62,
                                height: 62,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF34C759),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Color(0xFF34C759),
                                      blurRadius: 10,
                                      offset: Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Icon(
                                    isVideo
                                        ? CupertinoIcons.videocam_fill
                                        : CupertinoIcons.phone_fill,
                                    color: Colors.white,
                                    size: 28,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Accept',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.secondaryText(isDark),
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEdgeDockedChip(BuildContext context, bool isDark, bool isVideo) {
    final isLeft = _dockAlignment == Alignment.centerLeft;

    return Align(
      key: const ValueKey('edge_docked_chip'),
      alignment: isLeft ? Alignment.centerLeft : Alignment.centerRight,
      child: Transform.translate(
        offset: Offset(0, _verticalOffset),
        child: GestureDetector(
          onTap: () {
            setState(() {
              _isMinimized = false;
              _verticalOffset = 0;
            });
          },
          onPanUpdate: _onPanUpdate,
          onPanEnd: _onPanEnd,
          child: AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              final scale = 1.0 + (_pulseController.value * 0.08);
              final glowAlpha = 0.25 + (_pulseController.value * 0.45);
              final ringScale = 1.0 + (_pulseController.value * 0.32);
              final ringAlpha = (1.0 - _pulseController.value) * 0.6;

              return Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  // Expanding radar wave ripple ring
                  Transform.scale(
                    scale: ringScale,
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF34C759).withValues(alpha: ringAlpha),
                          width: 2,
                        ),
                      ),
                    ),
                  ),

                  // Pulsing Edge Avatar Badge
                  Transform.scale(
                    scale: scale,
                    child: Material(
                      color: Colors.transparent,
                      type: MaterialType.transparency,
                      child: ClipRRect(
                        borderRadius: isLeft
                            ? const BorderRadius.only(
                                topRight: Radius.circular(26),
                                bottomRight: Radius.circular(26),
                              )
                            : const BorderRadius.only(
                                topLeft: Radius.circular(26),
                                bottomLeft: Radius.circular(26),
                              ),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                          child: Container(
                            padding: EdgeInsets.fromLTRB(
                              isLeft ? 6 : 10,
                              6,
                              isLeft ? 10 : 6,
                              6,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xF21C1C1E)
                                  : Colors.white.withValues(alpha: 0.94),
                              borderRadius: isLeft
                                  ? const BorderRadius.only(
                                      topRight: Radius.circular(26),
                                      bottomRight: Radius.circular(26),
                                    )
                                  : const BorderRadius.only(
                                      topLeft: Radius.circular(26),
                                      bottomLeft: Radius.circular(26),
                                    ),
                              border: Border.all(
                                color: const Color(0xFF34C759).withValues(
                                  alpha: 0.5 + (_pulseController.value * 0.5),
                                ),
                                width: 1.2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF34C759).withValues(alpha: glowAlpha),
                                  blurRadius: 14 + (_pulseController.value * 8),
                                  spreadRadius: 1 + (_pulseController.value * 3),
                                ),
                              ],
                            ),
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                IosAvatar(
                                  name: widget.callService.peerName,
                                  imagePath: widget.callService.peerAvatar,
                                  size: 38,
                                  showOnline: false,
                                ),
                                Positioned(
                                  right: -2,
                                  bottom: -2,
                                  child: Container(
                                    padding: const EdgeInsets.all(3.5),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF34C759),
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black26,
                                          blurRadius: 4,
                                        ),
                                      ],
                                    ),
                                    child: Icon(
                                      isVideo
                                          ? CupertinoIcons.videocam_fill
                                          : CupertinoIcons.phone_fill,
                                      color: Colors.white,
                                      size: 10,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isVideo = widget.callService.callType == CallType.video;

    return Material(
      color: Colors.transparent,
      type: MaterialType.transparency,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.92, end: 1.0).animate(animation),
              child: child,
            ),
          );
        },
        child: _isMinimized
            ? _buildEdgeDockedChip(context, isDark, isVideo)
            : _buildFullSheet(context, isDark, isVideo),
      ),
    );
  }
}
