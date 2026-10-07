import 'package:flutter/material.dart';
import 'package:securecalc/src/core/theme/app_theme.dart';
import 'package:securecalc/src/core/widgets/shake_panic_wrapper.dart';
import '../../domain/p2p_call_service.dart';

class P2pCallScreen extends StatefulWidget {
  final String peerName;
  final String peerIp;

  const P2pCallScreen({
    super.key,
    required this.peerName,
    required this.peerIp,
  });

  @override
  State<P2pCallScreen> createState() => _P2pCallScreenState();
}

class _P2pCallScreenState extends State<P2pCallScreen> {
  bool _isMuted = false;
  bool _isSpeaker = true;

  @override
  void initState() {
    super.initState();
    P2pCallService.instance.startOutgoingCall(widget.peerName, widget.peerIp);
  }

  String _formatDuration(int seconds) {
    final mins = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  @override
  Widget build(BuildContext context) {
    return ShakePanicWrapper(
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: ValueListenableBuilder<CallState>(
            valueListenable: P2pCallService.instance.callStateNotifier,
            builder: (context, state, _) {
              if (state == CallState.ended) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (Navigator.canPop(context)) {
                    Navigator.pop(context);
                  }
                });
              }

              return Column(
                children: [
                  const SizedBox(height: 20),

                  // Top Encryption Badge
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock_rounded, size: 12, color: Colors.amber),
                        SizedBox(width: 5),
                        Text(
                          'End-to-End Encrypted Local Call',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white70,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Spacer(),

                  // Contact Avatar with Pulsing Effect
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.primaryColor.withValues(alpha: 0.15),
                    ),
                    child: CircleAvatar(
                      radius: 54,
                      backgroundColor: const Color(0xFF1C1C1E),
                      child: Text(
                        widget.peerName[0].toUpperCase(),
                        style: const TextStyle(
                          fontSize: 42,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Peer Name
                  Text(
                    widget.peerName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Call Status / Duration Timer
                  ValueListenableBuilder<int>(
                    valueListenable: P2pCallService.instance.durationNotifier,
                    builder: (context, seconds, _) {
                      String statusText;
                      if (state == CallState.outgoingRinging) {
                        statusText = 'Ringing (Same Wi-Fi / Bluetooth)...';
                      } else if (state == CallState.connected) {
                        statusText = _formatDuration(seconds);
                      } else {
                        statusText = 'Connecting...';
                      }

                      return Text(
                        statusText,
                        style: TextStyle(
                          color: state == CallState.connected
                              ? AppTheme.primaryColor
                              : Colors.white60,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      );
                    },
                  ),

                  const Spacer(),

                  // Control Action Buttons Bar (matching Screenshots)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Mute Button
                        _buildCallActionButton(
                          icon: _isMuted
                              ? Icons.mic_off_rounded
                              : Icons.mic_rounded,
                          label: 'Mute',
                          isActive: _isMuted,
                          onTap: () {
                            setState(() {
                              _isMuted = !_isMuted;
                              P2pCallService.instance.toggleMute();
                            });
                          },
                        ),

                        // End Call Red Circle Button
                        GestureDetector(
                          onTap: () {
                            P2pCallService.instance.endCall();
                            if (Navigator.canPop(context)) {
                              Navigator.pop(context);
                            }
                          },
                          child: CircleAvatar(
                            radius: 34,
                            backgroundColor: Colors.red,
                            child: const Icon(
                              Icons.call_end_rounded,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                        ),

                        // Speaker Button
                        _buildCallActionButton(
                          icon: _isSpeaker
                              ? Icons.volume_up_rounded
                              : Icons.volume_off_rounded,
                          label: 'Speaker',
                          isActive: _isSpeaker,
                          onTap: () {
                            setState(() {
                              _isSpeaker = !_isSpeaker;
                              P2pCallService.instance.toggleSpeaker();
                            });
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 48),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCallActionButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: isActive
                ? Colors.white
                : Colors.white.withValues(alpha: 0.15),
            child: Icon(
              icon,
              color: isActive ? Colors.black : Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
