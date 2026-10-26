import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../domain/services/call_service.dart';

/// Camera Island / Dynamic Island Pop Call Overlay Widget.
///
/// Adaptive UI matching Apple Dynamic Island & Android Camera Cutout.
/// Features:
/// - Calculator Icon on the left
/// - Peer Name / Active Call Status in middle (NO TIMER as requested)
/// - Red Hang Up button on the right
/// - Tapping body expands call page, tapping hang up ends the call.
class CameraIslandCallWidget extends StatefulWidget {
  final CallService callService;
  final VoidCallback onTap;

  const CameraIslandCallWidget({
    super.key,
    required this.callService,
    required this.onTap,
  });

  @override
  State<CameraIslandCallWidget> createState() => _CameraIslandCallWidgetState();
}

class _CameraIslandCallWidgetState extends State<CameraIslandCallWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  Offset? _position;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.elasticOut,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeIn,
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.paddingOf(context).top;
    final screenSize = MediaQuery.of(context).size;
    final callService = widget.callService;

    // Default position: Centered horizontally right at the top camera notch
    final defaultY = topPadding > 0 ? topPadding + 4 : 12.0;
    _position ??= Offset((screenSize.width - 230) / 2, defaultY);

    return Positioned(
      left: _position!.dx,
      top: _position!.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            double newX = _position!.dx + details.delta.dx;
            double newY = _position!.dy + details.delta.dy;
            newX = newX.clamp(10.0, screenSize.width - 240.0);
            newY = newY.clamp(4.0, screenSize.height - 100.0);
            _position = Offset(newX, newY);
          });
        },
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Material(
              color: Colors.transparent,
              child: GestureDetector(
                onTap: widget.onTap,
                child: Container(
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A0A0C),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.18),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.6),
                        blurRadius: 18,
                        spreadRadius: 2,
                        offset: const Offset(0, 6),
                      ),
                      BoxShadow(
                        color: const Color(0xFF34C759).withValues(alpha: 0.15),
                        blurRadius: 12,
                        spreadRadius: -2,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // 1. Calculator App Icon (Left Side)
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black38,
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Image.asset(
                          'assets/icons/app_icon.png',
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Container(
                            color: const Color(0xFF2C2C2E),
                            child: const Icon(
                              Icons.calculate,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(width: 8),

                      // 2. Active Pulsing Green Dot + Peer Name (Middle)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _PulsingGreenDot(),
                          const SizedBox(width: 6),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 95),
                            child: Text(
                              callService.peerName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(width: 10),

                      // 3. Red Circular Hang Up Button (Right Side)
                      GestureDetector(
                        onTap: () async {
                          await callService.hangUp();
                        },
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: const BoxDecoration(
                            color: Color(0xFFFF3B30),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Color(0x66FF3B30),
                                blurRadius: 6,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Icon(
                              CupertinoIcons.phone_down_fill,
                              color: Colors.white,
                              size: 14,
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
        ),
      ),
    );
  }
}

/// Animated Green Pulsing Dot indicating active call status.
class _PulsingGreenDot extends StatefulWidget {
  @override
  State<_PulsingGreenDot> createState() => _PulsingGreenDotState();
}

class _PulsingGreenDotState extends State<_PulsingGreenDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.5, end: 1.0).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _animation,
      child: Container(
        width: 7,
        height: 7,
        decoration: const BoxDecoration(
          color: Color(0xFF34C759),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Color(0x9934C759),
              blurRadius: 4,
            ),
          ],
        ),
      ),
    );
  }
}
