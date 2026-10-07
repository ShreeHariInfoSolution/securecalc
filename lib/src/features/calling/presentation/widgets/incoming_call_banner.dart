import 'package:flutter/material.dart';
import 'package:securecalc/src/core/theme/app_theme.dart';
import '../../domain/p2p_call_service.dart';
import '../pages/p2p_call_screen.dart';

class IncomingCallBanner extends StatelessWidget {
  const IncomingCallBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CallState>(
      valueListenable: P2pCallService.instance.callStateNotifier,
      builder: (context, state, _) {
        if (state != CallState.incomingRinging) {
          return const SizedBox.shrink();
        }

        final session = P2pCallService.instance.activeSession;
        final peerName = session?.peerName ?? 'Unknown Vault User';

        return Positioned(
          top: MediaQuery.of(context).padding.top + 10,
          left: 16,
          right: 16,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(20),
            color: const Color(0xFF1C1C1E),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.2),
                    child: Text(
                      peerName[0].toUpperCase(),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          peerName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Incoming Local Call...',
                          style: TextStyle(
                            color: AppTheme.primaryColor,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Decline
                  IconButton(
                    icon: const Icon(Icons.call_end_rounded, color: Colors.red, size: 24),
                    onPressed: () {
                      P2pCallService.instance.endCall();
                    },
                  ),
                  const SizedBox(width: 4),
                  // Accept
                  IconButton(
                    icon: const Icon(Icons.call_rounded, color: AppTheme.primaryColor, size: 24),
                    onPressed: () {
                      P2pCallService.instance.acceptIncomingCall();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => P2pCallScreen(
                            peerName: peerName,
                            peerIp: session?.peerIp ?? '127.0.0.1',
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
