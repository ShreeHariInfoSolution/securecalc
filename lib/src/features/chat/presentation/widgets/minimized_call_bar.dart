import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../domain/services/call_service.dart';

/// Top App Bar Minimized Call Banner matching iOS / WhatsApp native design (Screenshots 1 & 2).
/// Compact adaptive UI with zero pixel overflow or stretched headers.
class TopAppBarCallBanner extends StatefulWidget {
  final CallService callService;
  final VoidCallback onTapExpand;

  const TopAppBarCallBanner({
    super.key,
    required this.callService,
    required this.onTapExpand,
  });

  @override
  State<TopAppBarCallBanner> createState() => _TopAppBarCallBannerState();
}

class _TopAppBarCallBannerState extends State<TopAppBarCallBanner> {
  String _getStatusText(CallState state, Duration duration) {
    switch (state) {
      case CallState.outgoingRinging:
        return 'Ringing';
      case CallState.incomingRinging:
        return 'Incoming Call';
      case CallState.connecting:
        return 'Connecting...';
      case CallState.active:
        final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
        final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
        if (duration.inHours > 0) {
          final hours = duration.inHours.toString().padLeft(2, '0');
          return '$hours:$minutes:$seconds';
        }
        return '$minutes:$seconds';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.paddingOf(context).top;
    final callService = widget.callService;
    final state = callService.state;
    final isIncoming = state == CallState.incomingRinging;
    final statusText = _getStatusText(state, callService.duration);
    final peerName = callService.peerName.isNotEmpty ? callService.peerName : 'Contact';
    final displayText = statusText.isNotEmpty ? '$peerName - $statusText' : peerName;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: double.infinity,
        color: const Color(0xFF111111),
        padding: EdgeInsets.only(
          top: topPadding > 0 ? topPadding + 2 : 8,
          left: 14,
          right: 14,
          bottom: 8,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Left Action: Red Decline if incoming, or Mute Mic if outgoing/active
            if (isIncoming)
              GestureDetector(
                onTap: () async {
                  await callService.rejectCall();
                },
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFF3B30),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Icon(
                      CupertinoIcons.phone_down_fill,
                      color: Colors.white,
                      size: 17,
                    ),
                  ),
                ),
              )
            else
              GestureDetector(
                onTap: () => callService.toggleMute(),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: callService.micOn
                        ? const Color(0xFF2C2C2E)
                        : const Color(0xFFFF3B30).withValues(alpha: 0.25),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: callService.micOn
                          ? Colors.white12
                          : const Color(0xFFFF3B30),
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    callService.micOn
                        ? CupertinoIcons.mic_fill
                        : CupertinoIcons.mic_slash_fill,
                    color: Colors.white,
                    size: 17,
                  ),
                ),
              ),

            // Center Area (Peer name & Status / Timer) - Tap to expand
            Expanded(
              child: GestureDetector(
                onTap: widget.onTapExpand,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        CupertinoIcons.phone_fill,
                        color: Color(0xFF34C759),
                        size: 15,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          displayText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF34C759),
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Right Action: Green Accept if incoming, or Red Hangup if outgoing/active
            if (isIncoming)
              GestureDetector(
                onTap: () async {
                  await callService.acceptCall();
                },
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: Color(0xFF34C759),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Icon(
                      CupertinoIcons.phone_fill,
                      color: Colors.white,
                      size: 17,
                    ),
                  ),
                ),
              )
            else
              GestureDetector(
                onTap: () async {
                  await callService.hangUp();
                },
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFF3B30),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x66FF3B30),
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      CupertinoIcons.phone_down_fill,
                      color: Colors.white,
                      size: 17,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Legacy MinimizedCallBar alias for backward compatibility.
class MinimizedCallBar extends StatelessWidget {
  final CallService callService;
  final VoidCallback onTap;

  const MinimizedCallBar({
    super.key,
    required this.callService,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TopAppBarCallBanner(
      callService: callService,
      onTapExpand: onTap,
    );
  }
}
