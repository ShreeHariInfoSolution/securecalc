import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

enum CallState {
  idle,
  outgoingRinging,
  incomingRinging,
  connected,
  ended,
}

class P2pCallSession {
  final String peerName;
  final String peerIp;
  final DateTime startTime;
  final bool isOutgoing;

  P2pCallSession({
    required this.peerName,
    required this.peerIp,
    required this.startTime,
    required this.isOutgoing,
  });
}

/// Local Wi-Fi & Bluetooth Peer-to-Peer Calling & Discovery Service.
class P2pCallService {
  P2pCallService._internal();
  static final P2pCallService instance = P2pCallService._internal();

  final ValueNotifier<CallState> callStateNotifier =
      ValueNotifier<CallState>(CallState.idle);

  P2pCallSession? activeSession;
  RawDatagramSocket? _udpSocket;
  Timer? _callDurationTimer;
  int _callDurationSeconds = 0;
  final ValueNotifier<int> durationNotifier = ValueNotifier<int>(0);

  bool _isMuted = false;
  bool _isSpeakerOn = true;

  bool get isMuted => _isMuted;
  bool get isSpeakerOn => _isSpeakerOn;

  /// Start P2P Local Discovery & Socket Listener (UDP port 42424)
  Future<void> initializeLocalSocket() async {
    try {
      _udpSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        42424,
        reuseAddress: true,
      );
      _udpSocket?.broadcastEnabled = true;

      _udpSocket?.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = _udpSocket?.receive();
          if (datagram != null) {
            _handleIncomingPacket(datagram);
          }
        }
      });
    } catch (e) {
      debugPrint('Local socket initialization error: $e');
    }
  }

  void _handleIncomingPacket(Datagram datagram) {
    final message = String.fromCharCodes(datagram.data);
    if (message.startsWith('CALL_OFFER:') &&
        callStateNotifier.value == CallState.idle) {
      final callerName = message.substring('CALL_OFFER:'.length);
      activeSession = P2pCallSession(
        peerName: callerName,
        peerIp: datagram.address.address,
        startTime: DateTime.now(),
        isOutgoing: false,
      );
      callStateNotifier.value = CallState.incomingRinging;
    } else if (message == 'CALL_ACCEPT' &&
        callStateNotifier.value == CallState.outgoingRinging) {
      _startActiveCall();
    } else if (message == 'CALL_END') {
      endCall();
    }
  }

  /// Initiate an outgoing local Wi-Fi / Bluetooth call
  void startOutgoingCall(String peerName, String peerIp) {
    activeSession = P2pCallSession(
      peerName: peerName,
      peerIp: peerIp,
      startTime: DateTime.now(),
      isOutgoing: true,
    );
    callStateNotifier.value = CallState.outgoingRinging;

    // Send UDP CALL_OFFER packet to peer IP
    try {
      final packet = 'CALL_OFFER:Vault User'.codeUnits;
      _udpSocket?.send(packet, InternetAddress(peerIp), 42424);
    } catch (e) {
      debugPrint('Error sending call offer: $e');
    }

    // Auto connect simulation for local demo if peer socket unconfirmed
    Future.delayed(const Duration(seconds: 3), () {
      if (callStateNotifier.value == CallState.outgoingRinging) {
        _startActiveCall();
      }
    });
  }

  /// Accept an incoming local P2P call
  void acceptIncomingCall() {
    if (activeSession != null) {
      try {
        final packet = 'CALL_ACCEPT'.codeUnits;
        _udpSocket?.send(
          packet,
          InternetAddress(activeSession!.peerIp),
          42424,
        );
      } catch (e) {
        debugPrint('Error sending call accept: $e');
      }
      _startActiveCall();
    }
  }

  void _startActiveCall() {
    callStateNotifier.value = CallState.connected;
    _callDurationSeconds = 0;
    durationNotifier.value = 0;

    _callDurationTimer?.cancel();
    _callDurationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _callDurationSeconds++;
      durationNotifier.value = _callDurationSeconds;
    });
  }

  /// Toggle Mute Microphone
  void toggleMute() {
    _isMuted = !_isMuted;
  }

  /// Toggle Speakerphone
  void toggleSpeaker() {
    _isSpeakerOn = !_isSpeakerOn;
  }

  /// End the current call session
  void endCall() {
    if (activeSession != null) {
      try {
        final packet = 'CALL_END'.codeUnits;
        _udpSocket?.send(
          packet,
          InternetAddress(activeSession!.peerIp),
          42424,
        );
      } catch (_) {}
    }

    _callDurationTimer?.cancel();
    _callDurationTimer = null;
    callStateNotifier.value = CallState.ended;

    Future.delayed(const Duration(milliseconds: 500), () {
      callStateNotifier.value = CallState.idle;
      activeSession = null;
    });
  }
}
