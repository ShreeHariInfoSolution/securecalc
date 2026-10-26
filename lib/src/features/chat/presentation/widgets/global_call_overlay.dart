import 'package:flutter/material.dart';

import '../../domain/services/call_island_manager.dart';
import '../../domain/services/call_service.dart';
import '../pages/call_page.dart';
import 'floating_call_widget.dart';

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
        final showFullCallPage = (state == CallState.active ||
                state == CallState.outgoingRinging ||
                state == CallState.connecting) &&
            !isMinimized;
        final showFloatingWidget = (state == CallState.active ||
                state == CallState.outgoingRinging ||
                state == CallState.connecting) &&
            isMinimized;

        return Stack(
          children: [
            widget.child,

            // Full Screen Call Page Overlay
            if (showFullCallPage)
              const Positioned.fill(
                child: CallPage(),
              ),

            // Floating Mini Window Overlay
            if (showFloatingWidget)
              FloatingCallWidget(
                callService: _callService,
                onTap: () {
                  _callService.setMinimized(false);
                },
              ),
          ],
        );
      },
    );
  }
}
