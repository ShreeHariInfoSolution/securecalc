import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import 'package:securecalc/src/app.dart';
import 'package:securecalc/src/core/utils/app_toast.dart';
import 'call_kit_service.dart';
import 'local_chat_storage.dart';
import 'server_api_service.dart';
import 'socket_chat_service.dart';

enum CallState { idle, outgoingRinging, incomingRinging, connecting, active, ended }

enum CallType { voice, video }

enum AudioRoute { earpiece, speaker, bluetooth }

class CallException implements Exception {
  final int status;
  final String message;
  CallException(this.status, this.message);
  @override
  String toString() => 'CallException($status): $message';
}

class CallEndInfo {
  final int callId;
  final int chatHeadId;
  final String status;
  final int? endedBy;
  CallEndInfo(this.callId, this.chatHeadId, this.status, this.endedBy);
}

class CallService extends ChangeNotifier {
  CallService._();
  static final CallService instance = CallService._();

  // ---------- public state ----------
  CallState state = CallState.idle;
  CallType callType = CallType.voice;
  int? callId;
  int? chatHeadId;
  int? peerId;
  String peerName = 'Contact';
  String peerAvatar = '';
  String? pendingVideoSwitchCaller;
  bool isCaller = false;

  bool micOn = true;
  bool camOn = true;
  bool remoteAudioOn = true;
  bool remoteVideoOn = true;
  bool speakerOn = false;
  AudioRoute audioRoute = AudioRoute.speaker;
  String selectedAudioDeviceName = 'Speaker';
  String? selectedAudioDeviceId;
  List<MediaDeviceInfo> availableAudioDevices = [];

  final ValueNotifier<bool> isMinimizedNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isCalculatorVisibleNotifier = ValueNotifier<bool>(false);

  DateTime? activeSince;
  Duration get duration =>
      activeSince == null ? Duration.zero : DateTime.now().difference(activeSince!);

  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  final StreamController<CallEndInfo> _endCtrl = StreamController.broadcast();
  Stream<CallEndInfo> get onCallEnded => _endCtrl.stream;

  // ---------- internals ----------
  io.Socket? _socket;
  bool _inited = false;

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  Future<void>? _prepared;
  final List<RTCIceCandidate> _iceBuffer = [];
  bool _remoteDescSet = false;
  Timer? _tick;

  AudioPlayer? _ringtonePlayer;
  int _ringtoneToken = 0;

  Future<void> init() async {
    if (_inited) return;
    _inited = true;
    try {
      await localRenderer.initialize();
      await remoteRenderer.initialize();
    } catch (e) {
      debugPrint('[CALL] Error initializing video renderers: $e');
    }
    try {
      navigator.mediaDevices.ondevicechange = (event) async {
        debugPrint('[CALL] Media devices changed, refreshing audio devices...');
        await refreshAudioDevices();
      };
    } catch (e) {
      debugPrint('[CALL] Error binding device change listener: $e');
    }
  }

  final StreamController<String> _videoSwitchRequestCtrl = StreamController<String>.broadcast();
  Stream<String> get onVideoSwitchRequested => _videoSwitchRequestCtrl.stream;

  void attachSocket(io.Socket socket) {
    _socket = socket;
    _socket!.off('incoming_call');
    _socket!.off('call_accepted');
    _socket!.off('call_ended');
    _socket!.off('webrtc_signal');
    _socket!.off('call_media_state');
    _socket!.off('call_type_switched');
    _socket!.off('request_video_switch');
    _socket!.off('video_switch_requested');
    _socket!.off('video_call_request');
    _socket!.off('switch_call_type_request');
    _socket!.off('call_type_switch_request');
    _socket!.off('video_switch_accepted');
    _socket!.off('video_switch_rejected');

    _socket!.on('incoming_call', (d) => _guard(() => _onIncoming(_map(d))));
    _socket!.on('call_accepted', (d) => _guard(() => _onAccepted(_map(d))));
    _socket!.on('call_ended', (d) => _guard(() => _onEnded(_map(d))));
    _socket!.on('webrtc_signal', (d) => _guard(() => _onSignal(_map(d))));
    _socket!.on('call_media_state', (d) => _guard(() => _onMediaState(_map(d))));
    _socket!.on('call_type_switched', (d) => _guard(() => _onCallTypeSwitched(_map(d))));
    _socket!.on('request_video_switch', (d) => _guard(() => _onVideoSwitchRequested(_map(d))));
    _socket!.on('video_switch_requested', (d) => _guard(() => _onVideoSwitchRequested(_map(d))));
    _socket!.on('video_call_request', (d) => _guard(() => _onVideoSwitchRequested(_map(d))));
    _socket!.on('switch_call_type_request', (d) => _guard(() => _onVideoSwitchRequested(_map(d))));
    _socket!.on('call_type_switch_request', (d) => _guard(() => _onVideoSwitchRequested(_map(d))));
    _socket!.on('video_switch_accepted', (d) => _guard(() => _onVideoSwitchAccepted(_map(d))));
    _socket!.on('video_switch_rejected', (d) => _guard(() => _onVideoSwitchRejected(_map(d))));
    _socket!.on('disconnect', (_) {
      if (state != CallState.idle && state != CallState.ended) {
        _setState(CallState.connecting); // Attempting socket reconnect
      }
    });
  }

  void setupIncomingFromBackground({
    required int callId,
    required int chatHeadId,
    required int callerId,
    required CallType callType,
    required String callerName,
  }) {
    this.callId = callId;
    this.chatHeadId = chatHeadId;
    peerId = callerId;
    this.callType = callType;
    peerName = callerName;
    isCaller = false;
    isMinimizedNotifier.value = false;
    _setState(CallState.incomingRinging);
  }

  // =====================================================================
  // Public actions
  // =====================================================================

  Future<void> startCall({
    required int chatHeadId,
    required CallType type,
    String? name,
    String? avatar,
    int? peerUserId,
  }) async {
    FocusManager.instance.primaryFocus?.unfocus();
    unawaited(SystemChannels.textInput.invokeMethod('TextInput.hide'));

    await init();
    if (state != CallState.idle) throw CallException(409, 'You are already in a call');
    if (!await _ensurePermissions(type)) {
      throw CallException(403, 'Microphone/camera permission is required');
    }

    peerName = name ?? peerName;
    peerAvatar = avatar ?? peerAvatar;
    peerId = peerUserId;

    final data = await _emit('call_invite', {
      'chat_head_id': chatHeadId,
      'call_type': type == CallType.video ? 'video' : 'voice',
    });

    if (data['status'] == 'busy') {
      _cleanup(notifyEnd: null);
      throw CallException(409, 'User is busy');
    }

    callId = _asInt(data['call_id']);
    this.chatHeadId = chatHeadId;
    callType = type;
    isCaller = true;
    isMinimizedNotifier.value = false;
    await initializeDefaultAudioRoute(type);
    _setState(CallState.outgoingRinging);

    if (callId != null) {
      unawaited(
        CallKitService.instance.startOutgoingCall(
          callId: callId!,
          chatHeadId: chatHeadId,
          callerId: peerUserId ?? 0,
          callerName: peerName,
          callType: type == CallType.video ? 'video' : 'voice',
          avatar: peerAvatar,
        ),
      );
    }

    final id = callId!;
    _prepared = _prepare(id, type).catchError((e) {
      _failCall(id, 'prepare failed: $e');
    });
  }

  bool _isAccepting = false;

  Future<void> acceptCall() async {
    if (_isAccepting || state != CallState.incomingRinging || callId == null) return;
    _isAccepting = true;

    FocusManager.instance.primaryFocus?.unfocus();
    unawaited(SystemChannels.textInput.invokeMethod('TextInput.hide'));

    try {
      await init();
      final id = callId;
      if (id == null) return;

      if (!await _ensurePermissions(callType)) {
        await rejectCall();
        throw CallException(403, 'Microphone/camera permission is required');
      }

      _setState(CallState.connecting);
      _prepared = _prepare(id, callType);
      await _prepared;
      if (callId != id) return;

      try {
        await _emit('call_accept', {'call_id': id});
      } on CallException catch (ce) {
        if (ce.status == 409) {
          debugPrint('[CALL] call_accept returned 409 (already accepted on server): $ce');
          return;
        }
        rethrow;
      }
    } catch (e) {
      final id = callId;
      if (id != null && state == CallState.incomingRinging) {
        await _emit('call_reject', {'call_id': id}).catchError((_) => <String, dynamic>{});
        _cleanup(notifyEnd: null);
      } else {
        debugPrint('[CALL] acceptCall warning/error: $e');
      }
      rethrow;
    } finally {
      _isAccepting = false;
    }
  }

  Future<void> rejectCall() async {
    if (state != CallState.incomingRinging || callId == null) return;
    final id = callId!;
    await _emit('call_reject', {'call_id': id}).catchError((_) => <String, dynamic>{});
    if (callId == id) _cleanup(notifyEnd: null);
  }

  Future<void> hangUp() async {
    final id = callId;
    if (id == null) {
      _cleanup(notifyEnd: null);
      return;
    }
    try {
      if (state == CallState.outgoingRinging) {
        await _emit('call_cancel', {'call_id': id});
      } else if (state == CallState.incomingRinging) {
        await _emit('call_reject', {'call_id': id});
      } else {
        await _emit('call_end', {'call_id': id});
      }
    } catch (_) {}
    if (callId == id) _cleanup(notifyEnd: null);
  }

  void toggleMute() {
    micOn = !micOn;
    for (final t in _localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = micOn;
    }
    _sendMediaState();
    notifyListeners();
  }

  void toggleCamera() {
    if (callType != CallType.video) return;
    camOn = !camOn;
    for (final t in _localStream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = camOn;
    }
    _sendMediaState();
    notifyListeners();
  }

  Future<bool> _ensureVideoTrack() async {
    try {
      var cameraStatus = await Permission.camera.status;
      if (!cameraStatus.isGranted) {
        cameraStatus = await Permission.camera.request();
      }
      if (!cameraStatus.isGranted && !cameraStatus.isLimited) {
        if (cameraStatus.isPermanentlyDenied) {
          _showPermissionDialog(CallType.video);
        } else {
          AppToast.show('Camera permission is required for video call', isError: true);
        }
        return false;
      }

      var videoTracks = _localStream?.getVideoTracks() ?? <MediaStreamTrack>[];
      if (videoTracks.isEmpty) {
        final videoStream = await navigator.mediaDevices.getUserMedia({
          'audio': false,
          'video': {
            'facingMode': 'user',
            'width': 640,
            'height': 480,
            'frameRate': 24,
          },
        });
        if (videoStream.getVideoTracks().isNotEmpty) {
          final newTrack = videoStream.getVideoTracks().first;
          _localStream?.addTrack(newTrack);
          localRenderer.srcObject = _localStream;
          if (_pc != null) {
            await _pc!.addTrack(newTrack, _localStream!);
            final offer = await _pc!.createOffer();
            await _pc!.setLocalDescription(offer);
            final id = callId;
            if (id != null) {
              await _emit('webrtc_signal', {
                'call_id': id,
                'type': 'offer',
                'data': {'sdp': offer.sdp, 'type': offer.type},
              }).catchError((_) => <String, dynamic>{});
            }
          }
        }
      }
      return true;
    } catch (e) {
      debugPrint('[CALL] Ensure video track error: $e');
      return false;
    }
  }

  // Directly switch call type without request dialog
  Future<void> requestVideoCallSwitch() async {
    await switchCallType(CallType.video);
  }

  Future<void> acceptVideoCallSwitch() async {
    pendingVideoSwitchCaller = null;
    final id = callId;
    if (id == null) return;
    final hasCam = await _ensureVideoTrack();
    if (!hasCam) return;

    callType = CallType.video;
    camOn = true;
    for (final t in _localStream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = true;
    }
    if (audioRoute == AudioRoute.earpiece && !hasConnectedHeadphones) {
      await setAudioRoute(AudioRoute.speaker);
    }
    _sendMediaState();
    final payload = {'call_id': id, 'callId': id};
    _emit('video_switch_accepted', payload).catchError((_) => <String, dynamic>{});
    notifyListeners();
  }

  Future<void> rejectVideoCallSwitch() async {
    pendingVideoSwitchCaller = null;
    final id = callId;
    if (id == null) return;
    final payload = {'call_id': id, 'callId': id};
    _emit('video_switch_rejected', payload).catchError((_) => <String, dynamic>{});
    notifyListeners();
  }

  void _onVideoSwitchRequested(Map<String, dynamic> d) {
    // Directly handle video call switch without request dialog
    _onCallTypeSwitched({'call_id': d['call_id'], 'call_type': 'video'});
  }

  void _onVideoSwitchAccepted(Map<String, dynamic> d) async {
    final incomingCallId = _asInt(d['call_id']) ?? _asInt(d['callId']) ?? _asInt(d['id']);
    if (incomingCallId != null && callId != null && incomingCallId != callId) return;

    pendingVideoSwitchCaller = null;
    final hasCam = await _ensureVideoTrack();
    if (hasCam) {
      callType = CallType.video;
      camOn = true;
      for (final t in _localStream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
        t.enabled = true;
      }
      if (audioRoute == AudioRoute.earpiece && !hasConnectedHeadphones) {
        await setAudioRoute(AudioRoute.speaker);
      }
      _sendMediaState();
      notifyListeners();
      AppToast.show('$peerName accepted video call request');
    }
  }

  void _onVideoSwitchRejected(Map<String, dynamic> d) {
    final incomingCallId = _asInt(d['call_id']) ?? _asInt(d['callId']) ?? _asInt(d['id']);
    if (incomingCallId != null && callId != null && incomingCallId != callId) return;

    pendingVideoSwitchCaller = null;
    notifyListeners();
    AppToast.show('$peerName declined video call request');
  }

  Future<void> switchCallType(CallType newType) async {
    if (callType == newType) {
      if (newType == CallType.video && !camOn) {
        final hasCam = await _ensureVideoTrack();
        if (hasCam) {
          camOn = true;
          for (final t in _localStream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
            t.enabled = true;
          }
          _sendMediaState();
          notifyListeners();
        }
      }
      return;
    }

    if (newType == CallType.video) {
      final hasCam = await _ensureVideoTrack();
      if (hasCam) {
        callType = CallType.video;
        camOn = true;
        for (final t in _localStream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
          t.enabled = true;
        }
        if (audioRoute == AudioRoute.earpiece && !hasConnectedHeadphones) {
          await setAudioRoute(AudioRoute.speaker);
        }
        _sendMediaState();
        final id = callId;
        if (id != null) {
          _emit('call_type_switched', {
            'call_id': id,
            'call_type': 'video',
          }).catchError((_) => <String, dynamic>{});
        }
        notifyListeners();
      }
    } else {
      callType = CallType.voice;
      camOn = false;
      for (final t in _localStream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
        t.enabled = false;
      }
      try {
        localRenderer.srcObject = null;
        remoteRenderer.srcObject = null;
      } catch (_) {}
      if (!hasConnectedHeadphones) {
        await setAudioRoute(AudioRoute.earpiece);
      }
      _sendMediaState();
      final id = callId;
      if (id != null) {
        _emit('call_type_switched', {
          'call_id': id,
          'call_type': 'voice',
        }).catchError((_) => <String, dynamic>{});
      }
      notifyListeners();
    }
  }

  Future<void> switchCamera() async {
    final tracks = _localStream?.getVideoTracks();
    if (tracks == null || tracks.isEmpty) return;
    try {
      await Helper.switchCamera(tracks.first);
    } catch (e) {
      debugPrint('[CALL] Switch camera error: $e');
    }
  }

  Future<void> setSpeaker(bool on) async {
    await setAudioRoute(on ? AudioRoute.speaker : AudioRoute.earpiece);
  }

  bool get hasConnectedHeadset => hasConnectedHeadphones;

  String get connectedHeadsetName {
    for (final d in availableAudioDevices) {
      final label = d.label.toLowerCase();
      final id = d.deviceId.toLowerCase();
      if ((label.contains('bluetooth') ||
              label.contains('airpods') ||
              label.contains('buds') ||
              label.contains('headset') ||
              label.contains('wired') ||
              label.contains('headphone') ||
              label.contains('earphones') ||
              label.contains('handsfree')) &&
          !label.contains('speaker') &&
          !label.contains('earpiece') &&
          !label.contains('receiver') &&
          !label.contains('built-in') &&
          !id.contains('speaker') &&
          !id.contains('earpiece') &&
          !id.contains('receiver')) {
        return d.label.isNotEmpty ? d.label : 'Bluetooth / Headset';
      }
    }
    if (selectedAudioDeviceName.isNotEmpty &&
        selectedAudioDeviceName != 'Speaker' &&
        selectedAudioDeviceName != 'Phone' &&
        selectedAudioDeviceName != 'Earpiece') {
      return selectedAudioDeviceName;
    }
    return 'Headphones';
  }

  Future<void> refreshAudioDevices() async {
    try {
      final devices = await navigator.mediaDevices.enumerateDevices();
      availableAudioDevices = devices
          .where((d) => d.kind == 'audiooutput' || d.kind == 'audioinput')
          .toList();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> selectAudioDevice(MediaDeviceInfo device) async {
    selectedAudioDeviceId = device.deviceId;
    final labelLower = device.label.toLowerCase();
    selectedAudioDeviceName = device.label.isNotEmpty ? device.label : 'Headset';

    try {
      if (labelLower.contains('speaker') || labelLower.contains('loudspeaker')) {
        await setAudioRoute(AudioRoute.speaker);
      } else if (labelLower.contains('earpiece') || labelLower.contains('receiver') || labelLower.contains('built-in')) {
        await setAudioRoute(AudioRoute.earpiece);
      } else {
        await setAudioRoute(AudioRoute.bluetooth);
        if (device.deviceId.isNotEmpty) {
          try {
            await Helper.selectAudioOutput(device.deviceId);
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('[CALL] Select audio device error: $e');
    }
    notifyListeners();
  }

  bool get hasConnectedHeadphones {
    for (final d in availableAudioDevices) {
      final label = d.label.toLowerCase();
      final id = d.deviceId.toLowerCase();
      if ((label.contains('bluetooth') ||
              label.contains('headset') ||
              label.contains('pods') ||
              label.contains('buds') ||
              label.contains('airpods') ||
              label.contains('wired') ||
              label.contains('headphone') ||
              label.contains('earphones') ||
              label.contains('handsfree') ||
              label.contains('sco') ||
              id.contains('bluetooth') ||
              id.contains('headset') ||
              id.contains('wired') ||
              id.contains('headphone')) &&
          !label.contains('speaker') &&
          !label.contains('earpiece') &&
          !label.contains('receiver') &&
          !label.contains('built-in') &&
          !id.contains('speaker') &&
          !id.contains('earpiece') &&
          !id.contains('receiver')) {
        return true;
      }
    }
    if (audioRoute == AudioRoute.bluetooth && availableAudioDevices.isNotEmpty) return true;
    return false;
  }

  Future<void> initializeDefaultAudioRoute(CallType type) async {
    try {
      // Retry device enumeration up to 3 times on call start to ensure connected headphones/Bluetooth are discovered
      for (int i = 0; i < 3; i++) {
        await refreshAudioDevices();
        if (hasConnectedHeadphones) break;
        await Future.delayed(const Duration(milliseconds: 150));
      }

      if (hasConnectedHeadphones) {
        debugPrint('[CALL] Connected headphones found on call start -> Route to Headphones');
        await setAudioRoute(AudioRoute.bluetooth);
      } else {
        if (type == CallType.video) {
          debugPrint('[CALL] Video call without headphones -> Route to Speaker');
          await setAudioRoute(AudioRoute.speaker);
        } else {
          debugPrint('[CALL] Voice call without headphones -> Route to Earpiece');
          await setAudioRoute(AudioRoute.earpiece);
        }
      }
    } catch (e) {
      debugPrint('[CALL] Audio route init warning: $e');
    }
  }

  Future<void> setAudioRoute(AudioRoute route) async {
    audioRoute = route;
    try {
      await refreshAudioDevices();
      if (route == AudioRoute.speaker) {
        speakerOn = true;
        selectedAudioDeviceName = 'Speaker';
        await Helper.setSpeakerphoneOn(true);
        try {
          await Helper.selectAudioOutput('speaker');
        } catch (_) {}
        for (final d in availableAudioDevices) {
          final label = d.label.toLowerCase();
          if (label.contains('speaker') || label.contains('loudspeaker')) {
            if (d.deviceId.isNotEmpty && d.deviceId != 'speaker') {
              try {
                await Helper.selectAudioOutput(d.deviceId);
              } catch (_) {}
            }
            break;
          }
        }
      } else if (route == AudioRoute.earpiece) {
        speakerOn = false;
        selectedAudioDeviceName = 'Phone';
        await Helper.setSpeakerphoneOn(false);
        try {
          await Helper.selectAudioOutput('earpiece');
        } catch (_) {}
        try {
          await Helper.selectAudioOutput('receiver');
        } catch (_) {}
        for (final d in availableAudioDevices) {
          final label = d.label.toLowerCase();
          final id = d.deviceId.toLowerCase();
          if (label.contains('earpiece') || label.contains('receiver') ||
              id.contains('earpiece') || id.contains('receiver')) {
            if (d.deviceId.isNotEmpty && d.deviceId != 'earpiece' && d.deviceId != 'receiver') {
              try {
                await Helper.selectAudioOutput(d.deviceId);
              } catch (_) {}
            }
            break;
          }
        }
      } else {
        speakerOn = false;
        selectedAudioDeviceName = connectedHeadsetName.isNotEmpty ? connectedHeadsetName : 'Headset';
        await Helper.setSpeakerphoneOn(false);
        try {
          await Helper.selectAudioOutput('bluetooth');
        } catch (_) {}
        try {
          await Helper.selectAudioOutput('headset');
        } catch (_) {}
        try {
          await Helper.selectAudioOutput('wired');
        } catch (_) {}
        for (final d in availableAudioDevices) {
          final label = d.label.toLowerCase();
          final id = d.deviceId.toLowerCase();
          if ((label.contains('bluetooth') ||
                  label.contains('airpods') ||
                  label.contains('buds') ||
                  label.contains('headset') ||
                  label.contains('wired') ||
                  label.contains('headphone') ||
                  label.contains('earphones') ||
                  id.contains('bluetooth') ||
                  id.contains('headset') ||
                  id.contains('wired')) &&
              !label.contains('speaker') &&
              !label.contains('earpiece')) {
            if (d.deviceId.isNotEmpty &&
                d.deviceId != 'bluetooth' &&
                d.deviceId != 'headset' &&
                d.deviceId != 'wired') {
              try {
                await Helper.selectAudioOutput(d.deviceId);
              } catch (_) {}
            }
            break;
          }
        }
      }
    } catch (e) {
      debugPrint('[CALL] Set audio route error: $e');
    }
    notifyListeners();
  }

  void setMinimized(bool value) {
    isMinimizedNotifier.value = value;
    notifyListeners();
  }

  // =====================================================================
  // Socket event handlers
  // =====================================================================

  Future<void> _onIncoming(Map<String, dynamic> d) async {
    final incomingCallId = _asInt(d['call_id']);
    if (incomingCallId == null) return;

    if (state != CallState.idle) {
      if (callId == incomingCallId) return; // Duplicate event
      // Busy in another call
      await _emit('call_reject', {'call_id': incomingCallId}).catchError((_) => <String, dynamic>{});
      return;
    }

    callId = incomingCallId;
    chatHeadId = _asInt(d['chat_head_id']);
    peerId = _asInt(d['caller_id']);
    callType = d['call_type'] == 'video' ? CallType.video : CallType.voice;
    isCaller = false;
    isMinimizedNotifier.value = false;

    // Resolve caller name & avatar
    final convs = LocalChatStorage.instance.conversationsNotifier.value;
    final conv = convs.cast<dynamic>().firstWhere(
      (c) => c.id == chatHeadId.toString(),
      orElse: () => null,
    );
    if (conv != null && conv.name.isNotEmpty && !conv.name.startsWith('User #')) {
      peerName = conv.name;
      peerAvatar = conv.avatarUrl;
    } else if (peerId != null && peerId! > 0) {
      try {
        final user = await ServerApiService.instance.getUser(peerId!);
        if (user != null) {
          peerName = user.name.isNotEmpty ? user.name : (user.phone ?? user.email ?? 'Contact');
          peerAvatar = user.avatar ?? '';
        }
      } catch (_) {}
    }

    _setState(CallState.incomingRinging);

    if (callId != null && chatHeadId != null) {
      unawaited(
        CallKitService.instance.showIncomingCall(
          callId: callId!,
          chatHeadId: chatHeadId!,
          callerId: peerId ?? 0,
          callerName: peerName,
          callType: callType == CallType.video ? 'video' : 'voice',
          avatar: peerAvatar,
        ),
      );
    }
  }

  Future<void> _onAccepted(Map<String, dynamic> d) async {
    if (_asInt(d['call_id']) != callId) return;
    _setState(CallState.connecting);
    if (!isCaller) return;

    final id = callId!;
    await _prepared;
    final pc = _pc;
    if (pc == null || callId != id) return;

    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    await _emit('webrtc_signal', {
      'call_id': id,
      'type': 'offer',
      'data': {'sdp': offer.sdp, 'type': offer.type},
    });
  }

  final List<Map<String, dynamic>> _pendingSignals = [];

  Future<void> _onSignal(Map<String, dynamic> d) async {
    if (_asInt(d['call_id']) != callId) return;
    final id = callId!;

    if (_prepared != null) {
      await _prepared;
    }

    final pc = _pc;
    if (pc == null || callId != id) {
      debugPrint('[CALL] Peer connection not ready for signal ${d['type']}. Queueing signal...');
      _pendingSignals.add(d);
      return;
    }

    await _processSignal(d, pc, id);
  }

  Future<void> _processPendingSignals() async {
    final pc = _pc;
    final id = callId;
    if (pc == null || id == null || _pendingSignals.isEmpty) return;

    final List<Map<String, dynamic>> toProcess = List.from(_pendingSignals);
    _pendingSignals.clear();

    for (final d in toProcess) {
      if (_asInt(d['call_id']) == id) {
        debugPrint('[CALL] Processing queued WebRTC signal: ${d['type']}');
        await _processSignal(d, pc, id);
      }
    }
  }

  Future<void> _processSignal(Map<String, dynamic> d, RTCPeerConnection pc, int id) async {
    final type = d['type'];
    final data = _map(d['data']);

    switch (type) {
      case 'offer':
        await pc.setRemoteDescription(RTCSessionDescription(data['sdp'], data['type']));
        _remoteDescSet = true;
        await _flushIce();
        final answer = await pc.createAnswer();
        await pc.setLocalDescription(answer);
        await _emit('webrtc_signal', {
          'call_id': id,
          'type': 'answer',
          'data': {'sdp': answer.sdp, 'type': answer.type},
        });
        break;

      case 'answer':
        await pc.setRemoteDescription(RTCSessionDescription(data['sdp'], data['type']));
        _remoteDescSet = true;
        await _flushIce();
        break;

      case 'ice':
        final candidateData = _map(data['candidate'] is Map ? data['candidate'] : data);
        final candidateStr = candidateData['candidate'] ?? data['candidate'];
        final sdpMid = candidateData['sdpMid'] ?? data['sdpMid'];
        final sdpMLineIndex = _asInt(candidateData['sdpMLineIndex'] ?? data['sdpMLineIndex']);

        if (candidateStr != null) {
          final c = RTCIceCandidate(
            candidateStr.toString(),
            sdpMid?.toString(),
            sdpMLineIndex,
          );
          if (_remoteDescSet) {
            await pc.addCandidate(c);
          } else {
            _iceBuffer.add(c);
          }
        }
        break;

      case 'request_video_switch':
      case 'video_switch_requested':
      case 'video_call_request':
      case 'switch_call_type_request':
        _onVideoSwitchRequested(d);
        break;

      case 'video_switch_accepted':
        _onVideoSwitchAccepted(d);
        break;

      case 'video_switch_rejected':
        _onVideoSwitchRejected(d);
        break;
    }
  }

  void _onMediaState(Map<String, dynamic> d) {
    if (_asInt(d['call_id']) != callId) return;
    remoteAudioOn = d['audio'] == true;
    remoteVideoOn = d['video'] == true;
    notifyListeners();
  }

  void _onCallTypeSwitched(Map<String, dynamic> d) async {
    if (_asInt(d['call_id']) != callId) return;
    final typeStr = d['call_type']?.toString().toLowerCase();
    if (typeStr == 'video') {
      callType = CallType.video;
      if (audioRoute == AudioRoute.earpiece && !hasConnectedHeadphones) {
        setAudioRoute(AudioRoute.speaker);
      }
      notifyListeners();
    } else if (typeStr == 'voice') {
      callType = CallType.voice;
      camOn = false;
      for (final t in _localStream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
        t.enabled = false;
      }
      setAudioRoute(AudioRoute.earpiece);
      notifyListeners();
    }
  }

  void _onEnded(Map<String, dynamic> d) {
    if (_asInt(d['call_id']) != callId) return;
    _cleanup(
      notifyEnd: CallEndInfo(
        callId!,
        _asInt(d['chat_head_id']) ?? chatHeadId ?? 0,
        '${d['status']}',
        _asInt(d['ended_by']),
      ),
    );
  }

  // =====================================================================
  // WebRTC setup
  // =====================================================================

  Future<void> _prepare(int id, CallType type) async {
    localRenderer.srcObject = null;
    remoteRenderer.srcObject = null;
    camOn = type == CallType.video;
    remoteVideoOn = type == CallType.video;

    final ice = await ServerApiService.instance.getIceServers();
    if (callId != id) return;

    MediaStream stream;
    try {
      stream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': type == CallType.video
            ? {'facingMode': 'user', 'width': 640, 'height': 480, 'frameRate': 24}
            : false,
      });
    } catch (e) {
      debugPrint('[CALL] Primary getUserMedia error: $e. Retrying with basic constraints...');
      try {
        stream = await navigator.mediaDevices.getUserMedia({
          'audio': true,
          'video': type == CallType.video ? true : false,
        });
      } catch (err) {
        debugPrint('[CALL] Secondary getUserMedia error: $err. Falling back to audio stream...');
        stream = await navigator.mediaDevices.getUserMedia({
          'audio': true,
          'video': false,
        });
        camOn = false;
        callType = CallType.voice;
      }
    }

    if (callId != id) {
      _stopStream(stream);
      return;
    }
    _localStream = stream;
    localRenderer.srcObject = stream;
    micOn = true;
    camOn = type == CallType.video && stream.getVideoTracks().isNotEmpty;

    try {
      await initializeDefaultAudioRoute(type);
    } catch (e) {
      debugPrint('[CALL] Audio route setup warning: $e');
    }

    final pc = await createPeerConnection({
      'iceServers': ice,
      'sdpSemantics': 'unified-plan',
    });
    if (callId != id) {
      await pc.close();
      _stopStream(stream);
      _localStream = null;
      return;
    }
    _pc = pc;
    _remoteDescSet = false;
    _iceBuffer.clear();

    pc.onIceCandidate = (c) {
      if (c.candidate == null || callId != id) return;
      _emit('webrtc_signal', {
        'call_id': id,
        'type': 'ice',
        'data': {
          'candidate': c.candidate,
          'sdpMid': c.sdpMid,
          'sdpMLineIndex': c.sdpMLineIndex,
        },
      }).catchError((_) => <String, dynamic>{});
    };

    pc.onTrack = (e) {
      if (e.streams.isNotEmpty) {
        remoteRenderer.srcObject = e.streams.first;
        notifyListeners();
      }
    };

    pc.onConnectionState = (s) {
      if (callId != id) return;
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        if (state != CallState.active) {
          activeSince = DateTime.now();
          _tick?.cancel();
          _tick = Timer.periodic(const Duration(seconds: 1), (_) => notifyListeners());
          _setState(CallState.active);
        }
      } else if (s == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        if (state == CallState.active) {
          _setState(CallState.connecting);
        }
      } else if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        hangUp();
      }
    };

    for (final t in stream.getTracks()) {
      await pc.addTrack(t, stream);
    }

    await _processPendingSignals();
  }

  Future<void> _flushIce() async {
    final pc = _pc;
    if (pc == null) return;
    for (final c in List.of(_iceBuffer)) {
      try {
        await pc.addCandidate(c);
      } catch (e) {
        debugPrint('[CALL] Error adding candidate: $e');
      }
    }
    _iceBuffer.clear();
  }

  void _sendMediaState() {
    final id = callId;
    if (id == null) return;
    _emit('call_media_state', {'call_id': id, 'audio': micOn, 'video': camOn})
        .catchError((_) => <String, dynamic>{});
  }

  void _playRingtone({required bool isOutgoing}) async {
    _stopRingtone();
    if (!isOutgoing) {
      // System CallKit / Telecom handles native incoming ringtone cleanly without duplicate audio
      return;
    }
    final currentToken = ++_ringtoneToken;

    try {
      final player = AudioPlayer();
      _ringtonePlayer = player;

      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final isSpeaker = audioRoute == AudioRoute.speaker;
        await player.setAudioContext(
          AudioContext(
            iOS: AudioContextIOS(
              category: isSpeaker
                  ? AVAudioSessionCategory.playback
                  : AVAudioSessionCategory.playAndRecord,
              options: {
                if (isSpeaker) AVAudioSessionOptions.defaultToSpeaker,
                AVAudioSessionOptions.mixWithOthers,
              },
            ),
          ),
        );
      } else {
        await player.setAudioContext(
          AudioContext(
            android: const AudioContextAndroid(
              stayAwake: true,
              contentType: AndroidContentType.music,
              usageType: AndroidUsageType.notificationRingtone,
              audioFocus: AndroidAudioFocus.gainTransient,
            ),
          ),
        );
      }

      if (_ringtoneToken != currentToken ||
          state == CallState.idle ||
          state == CallState.active ||
          state == CallState.connecting ||
          state == CallState.ended) {
        await player.stop();
        await player.dispose();
        if (_ringtonePlayer == player) _ringtonePlayer = null;
        return;
      }

      await player.setReleaseMode(ReleaseMode.loop);
      final soundFile = isOutgoing ? 'sounds/calling_ringtone.wav' : 'sounds/incoming_ringtone.wav';

      if (_ringtoneToken != currentToken ||
          state == CallState.idle ||
          state == CallState.active ||
          state == CallState.connecting ||
          state == CallState.ended) {
        await player.stop();
        await player.dispose();
        if (_ringtonePlayer == player) _ringtonePlayer = null;
        return;
      }

      try {
        await player.play(AssetSource(soundFile));
      } catch (_) {
        final fallback = isOutgoing ? 'sounds/sound_2.wav' : 'sounds/sound_1.wav';
        await player.play(AssetSource(fallback));
      }
    } catch (e) {
      debugPrint('[CALL] Ringtone exception: $e');
    }
  }

  void _stopRingtone() {
    _ringtoneToken++;
    try {
      _ringtonePlayer?.stop();
      _ringtonePlayer?.dispose();
      _ringtonePlayer = null;
    } catch (_) {}
  }

  // =====================================================================
  // Helpers
  // =====================================================================

  void _cleanup({required CallEndInfo? notifyEnd}) {
    _stopRingtone();
    _tick?.cancel();
    _tick = null;

    final pc = _pc;
    _pc = null;
    pc?.onIceCandidate = null;
    pc?.onTrack = null;
    pc?.onConnectionState = null;
    pc?.close();

    final s = _localStream;
    _localStream = null;
    if (s != null) _stopStream(s);

    localRenderer.srcObject = null;
    remoteRenderer.srcObject = null;
    _prepared = null;
    _iceBuffer.clear();
    _pendingSignals.clear();
    _remoteDescSet = false;

    final oldCallId = callId;
    final hadCall = oldCallId != null;

    if (oldCallId != null) {
      unawaited(CallKitService.instance.endCall(oldCallId.toString()));
    }

    callId = null;
    chatHeadId = null;
    peerId = null;
    pendingVideoSwitchCaller = null;
    isCaller = false;
    activeSince = null;
    micOn = true;
    camOn = false;
    remoteAudioOn = true;
    remoteVideoOn = false;
    isMinimizedNotifier.value = false;

    if (hadCall) {
      _setState(CallState.ended);
      if (notifyEnd != null) _endCtrl.add(notifyEnd);
    }
    _setState(CallState.idle);
  }

  void _failCall(int id, String why) {
    if (callId != id) return;
    debugPrint('[CALL] Call failed: $why');
    hangUp();
  }

  void _stopStream(MediaStream s) {
    for (final t in s.getTracks()) {
      t.stop();
    }
    s.dispose();
  }

  Future<bool> _ensurePermissions(CallType type) async {
    try {
      final perms = [Permission.microphone, if (type == CallType.video) Permission.camera];
      bool allGranted = true;
      bool permanentlyDenied = false;

      for (final p in perms) {
        var status = await p.status;
        if (!status.isGranted) {
          status = await p.request();
        }
        if (!status.isGranted && !status.isLimited) {
          allGranted = false;
        }
        if (status.isPermanentlyDenied) {
          permanentlyDenied = true;
        }
      }

      if (!allGranted) {
        if (permanentlyDenied) {
          _showPermissionDialog(type);
        } else {
          AppToast.show(
            type == CallType.video
                ? 'Camera & Microphone permission required for call'
                : 'Microphone permission required for call',
            isError: true,
          );
        }
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('[CALL] Permission check error: $e');
      return true;
    }
  }

  void _showPermissionDialog(CallType type) {
    final navContext = navigatorKey.currentContext;
    if (navContext == null) return;
    final isVideo = type == CallType.video;

    showCupertinoDialog<void>(
      context: navContext,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text('${isVideo ? "Camera & Microphone" : "Microphone"} Permission Required'),
        content: Text(
          'This app requires ${isVideo ? "Camera and Microphone" : "Microphone"} permission to place or receive calls. Please grant permission in App Settings.',
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(ctx),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            child: const Text('Open Settings'),
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
          ),
        ],
      ),
    );
  }

  Future<Map<String, dynamic>> _emit(String event, Map<String, dynamic> payload) async {
    io.Socket? socket = _socket ?? SocketChatService.instance.rawSocket;

    if (socket == null || !socket.connected) {
      debugPrint('[CALL] Socket not connected for event $event. Connecting...');
      SocketChatService.instance.connect();

      final deadline = DateTime.now().add(const Duration(seconds: 7));
      while (DateTime.now().isBefore(deadline)) {
        socket = _socket ?? SocketChatService.instance.rawSocket;
        if (socket != null && socket.connected) {
          _socket = socket;
          attachSocket(socket);
          break;
        }
        await Future.delayed(const Duration(milliseconds: 150));
      }
    }

    if (socket == null || !socket.connected) {
      debugPrint('[CALL ERROR] Socket connection timeout for event $event');
      throw CallException(500, 'Socket not connected');
    }

    final c = Completer<Map<String, dynamic>>();
    socket.emitWithAck(event, payload, ack: (res) {
      final r = _map(res);
      final status = _asInt(r['status']) ?? 500;
      if (status >= 400) {
        if (!c.isCompleted) c.completeError(CallException(status, '${r['message']}'));
      } else {
        if (!c.isCompleted) c.complete(_map(r['data']));
      }
    });
    return c.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw CallException(408, 'No response from server'),
    );
  }

  void _guard(FutureOr<void> Function() fn) {
    try {
      final r = fn();
      if (r is Future) {
        r.catchError((e) => debugPrint('[CALL] Handler error: $e'));
      }
    } catch (e) {
      debugPrint('[CALL] Handler error: $e');
    }
  }

  void _setState(CallState s) {
    state = s;
    if (s == CallState.outgoingRinging) {
      _playRingtone(isOutgoing: true);
    } else if (s == CallState.incomingRinging) {
      _playRingtone(isOutgoing: false);
    } else if (s == CallState.active) {
      _stopRingtone();
      if (callId != null) {
        unawaited(CallKitService.instance.setCallConnected(callId!));
      }
    } else {
      _stopRingtone();
    }
    notifyListeners();
  }

  Map<String, dynamic> _map(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  int? _asInt(dynamic v) => v == null ? null : (v is int ? v : int.tryParse('$v'));
}
