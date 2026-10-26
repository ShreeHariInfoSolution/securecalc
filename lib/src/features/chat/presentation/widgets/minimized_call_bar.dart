import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../domain/services/call_service.dart';

/// Minimized Call Bar overlay shown inside the app when a call is active but minimized.
/// Allows the user to quickly return to the full-screen CallPage or hang up.
class MinimizedCallBar extends StatefulWidget {
  final CallService callService;
  final VoidCallback onTap;

  const MinimizedCallBar({
    super.key,
    required this.callService,
    required this.onTap,
  });

  @override
  State<MinimizedCallBar> createState() => _MinimizedCallBarState();
}

class _MinimizedCallBarState extends State<MinimizedCallBar> {
  Offset? _position;

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      final hours = d.inHours.toString().padLeft(2, '0');
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.paddingOf(context).top;
    final screenSize = MediaQuery.of(context).size;
    final callService = widget.callService;

    // Default position: top right below notch
    final defaultY = topPadding > 0 ? topPadding + 6 : 14.0;
    _position ??= Offset(screenSize.width - 210, defaultY);

    return Positioned(
      left: _position!.dx,
      top: _position!.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            double newX = _position!.dx + details.delta.dx;
            double newY = _position!.dy + details.delta.dy;
            newX = newX.clamp(10.0, screenSize.width - 200.0);
            newY = newY.clamp(4.0, screenSize.height - 100.0);
            _position = Offset(newX, newY);
          });
        },
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(22),
            child: Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1E),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: const Color(0xFF34C759).withValues(alpha: 0.6),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                  BoxShadow(
                    color: const Color(0xFF34C759).withValues(alpha: 0.2),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Active Green Call Icon
                  Container(
                    width: 26,
                    height: 26,
                    decoration: const BoxDecoration(
                      color: Color(0xFF34C759),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      callService.callType == CallType.video
                          ? CupertinoIcons.videocam_fill
                          : CupertinoIcons.phone_fill,
                      color: Colors.white,
                      size: 13,
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Name & Timer
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 90),
                        child: Text(
                          callService.peerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            height: 1.15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        callService.state == CallState.active
                            ? _formatDuration(callService.duration)
                            : 'Connecting...',
                        style: const TextStyle(
                          color: Color(0xFF34C759),
                          fontSize: 10,
                          height: 1.15,
                          fontWeight: FontWeight.w500,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),

                  // Hangup Button
                  GestureDetector(
                    onTap: () async {
                      await callService.hangUp();
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFF3B30),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Icon(
                          CupertinoIcons.phone_down_fill,
                          color: Colors.white,
                          size: 12,
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
