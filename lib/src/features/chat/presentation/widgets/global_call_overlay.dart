import 'package:flutter/material.dart';

import '../../domain/services/call_island_manager.dart';
import '../../domain/services/call_service.dart';
import '../pages/call_page.dart';
import 'floating_call_widget.dart';
import 'minimized_call_bar.dart';

class GlobalCallOverlay extends StatefulWidget {
  final Widget child;

  const GlobalCallOverlay({super.key, required this.child});

  @override
  State<GlobalCallOverlay> createState() => _GlobalCallOverlayState();
}

class _GlobalCallOverlayState extends State<GlobalCallOverlay> {
  final _callService = CallService.instance;

  @override
  void initState() {
    super.initState();
    _callService.addListener(_onCallStateChanged);
    CallIslandManager.instance.init();
  }

  @override
  void dispose() {
    CallIslandManager.instance.dispose();
    _callService.removeListener(_onCallStateChanged);
    super.dispose();
  }

  void _onCallStateChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _callService.isMinimizedNotifier,
      builder: (context, isMinimized, _) {
        final state = _callService.state;

        // Native CallKit / Notification handles incoming call presentation.
        // Ignore incomingRinging on Flutter screens so no on-screen banner/overlay interrupts the app before accepting.
        final isIncoming = (state == CallState.incomingRinging);
        if (isIncoming) {
          return widget.child;
        }

        final isCallActive = (state == CallState.active ||
            state == CallState.outgoingRinging ||
            state == CallState.connecting);

        final isVideoCall = _callService.callType == CallType.video;

        final showFullCallPage = isCallActive && !isMinimized;
        final showFloatingVideoWindow = isCallActive && isMinimized && isVideoCall;
        final showVoiceTopCallBar = isCallActive && isMinimized && !isVideoCall;

        final topPadding = MediaQuery.paddingOf(context).top;
        final topBarHeight = topPadding > 0 ? topPadding + 46.0 : 52.0;

        return Stack(
          children: [
            // Main App Content (Pushed down with top rounded corners ONLY for minimized Voice Calls)
            if (showVoiceTopCallBar)
              Positioned.fill(
                top: topBarHeight,
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  child: MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      padding: MediaQuery.of(context).padding.copyWith(top: 6.0),
                      viewPadding: MediaQuery.of(context).viewPadding.copyWith(top: 6.0),
                    ),
                    child: widget.child,
                  ),
                ),
              )
            else
              widget.child,

            // Voice Call Top App Bar Banner (for Minimized Voice Calls)
            if (showVoiceTopCallBar)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: TopAppBarCallBanner(
                  callService: _callService,
                  onTapExpand: () {
                    _callService.setMinimized(false);
                  },
                ),
              ),

            // Video Call Floating Small Window (for Minimized Video Calls)
            if (showFloatingVideoWindow)
              FloatingCallWidget(
                callService: _callService,
                onTap: () {
                  _callService.setMinimized(false);
                },
              ),

            // Full Screen Call Page Overlay
            if (showFullCallPage)
              const Positioned.fill(
                child: CallPage(),
              ),
          ],
        );
      },
    );
  }
}
