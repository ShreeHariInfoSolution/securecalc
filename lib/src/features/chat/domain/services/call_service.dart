import 'dart:async';
import 'dart:convert';
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
import 'package:securecalc/src/features/calling/presentation/pages/call_history_view.dart';

enum CallState { idle, outgoingRinging, incomingRinging, connecting, active, ended }

enum CallType { voice, video }

enum AudioRoute { earpiece, speaker, bluetooth }

class AudioOutputOption {
  final String id;
  final String label;
  final String subtitle;
  final IconData icon;
  final AudioRoute route;
  final MediaDeviceInfo? rawDevice;

  const AudioOutputOption({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.route,
    this.rawDevice,
  });
}

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
  static const MethodChannel _nativeAudioChannel = MethodChannel('com.shis.securecalc/audio');

  // ---------- public state ----------
  CallState state = CallState.idle;
  CallType callType = CallType.voice;
  int? callId;
  int? chatHeadId;
  int? peerId;
  String peerName = 'Contact';
  String peerAvatar = '';
  String? pendingVideoSwitchCaller;
  String? endReasonMessage;
  bool isCaller = false;

  bool micOn = true;
  bool camOn = true;
  bool remoteAudioOn = true;
  bool remoteVideoOn = true;
  bool remoteIsFrontCamera = true;
  bool speakerOn = false;
  AudioRoute audioRoute = AudioRoute.speaker;
  AudioRoute requestedAudioRoute = AudioRoute.speaker;
  AudioRoute? userSelectedAudioRoute;
  String actualInputPort = '';
  String actualOutputPort = '';
  bool isRouteSwitching = false;

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
  bool hasFirstLocalFrame = false;
  bool hasFirstRemoteFrame = false;
  bool isFrontCamera = true;
  double cameraZoomScale = 1.0;
  bool isUltraWideActive = false;
  String? _currentVideoDeviceId;
  String? get currentVideoDeviceId => _currentVideoDeviceId;

  final StreamController<CallEndInfo> _endCtrl = StreamController.broadcast();
  Stream<CallEndInfo> get onCallEnded => _endCtrl.stream;

  // ---------- internals ----------
  io.Socket? _socket;
  bool _inited = false;

  RTCPeerConnection? _pc;
  RTCDataChannel? _dc;
  MediaStream? _localStream;
  Future<void>? _prepared;
  final List<RTCIceCandidate> _iceBuffer = [];
  bool _remoteDescSet = false;
  Timer? _tick;

  void _setupDataChannel(RTCDataChannel ch) {
    _dc = ch;
    ch.onDataChannelState = (s) {
      if (s == RTCDataChannelState.RTCDataChannelOpen) _sendFacing();
    };
    ch.onMessage = (m) {
      if (m.isBinary) return;
      try {
        final j = jsonDecode(m.text);
        if (j['t'] == 'front') {
          remoteIsFrontCamera = j['v'] == true;
          notifyListeners();
        }
      } catch (_) {}
    };
  }

  void _sendFacing() {
    final ch = _dc;
    if (ch == null || ch.state != RTCDataChannelState.RTCDataChannelOpen) return;
    ch.send(RTCDataChannelMessage(jsonEncode({'t': 'front', 'v': isFrontCamera})));
  }

  AudioPlayer? _ringtonePlayer;
  int _ringtoneToken = 0;

  bool _isUserSwitchingAudioRoute = false;

  String headsetName = '';
  String actualInputType = '';
  String actualOutputType = '';
  String activeDeviceUid = '';
  String activeDeviceName = '';
  String activeDeviceType = '';
  bool hasBluetoothDevice = false;
  List<Map<String, dynamic>> iosInputs = [];
  int _routeSwitchRequestId = 0;

  Future<void> _native(String method, [Map<String, dynamic>? args]) async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    try {
      final res = await _nativeAudioChannel.invokeMethod(method, args);
      if (res is Map) {
        _applyNativeState(Map<String, dynamic>.from(res));
      }
    } on MissingPluginException catch (e) {
      debugPrint('[AUDIO] channel missing: $method: $e');
    } catch (e) {
      debugPrint('[AUDIO_LOG ERROR] $method: $e');
    }
  }

  Future<void> _configureIosAudio(CallType type) async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    await Helper.setAppleAudioConfiguration(AppleAudioConfiguration(
      appleAudioCategory: AppleAudioCategory.playAndRecord,
      appleAudioCategoryOptions: {
        AppleAudioCategoryOption.allowBluetooth,
        AppleAudioCategoryOption.allowBluetoothA2DP,
        AppleAudioCategoryOption.allowAirPlay,
      },
      appleAudioMode: type == CallType.video
          ? AppleAudioMode.videoChat
          : AppleAudioMode.voiceChat,
    ));
  }

  void _applyNativeState(Map<String, dynamic> args) {
    actualInputPort = args['actualInputPort']?.toString() ?? actualInputPort;
    actualOutputPort = args['actualOutputPort']?.toString() ?? actualOutputPort;
    actualInputType = args['actualInputType']?.toString() ?? actualInputType;
    actualOutputType = args['actualOutputType']?.toString() ?? actualOutputType;
    activeDeviceUid = args['activeDeviceUid']?.toString() ?? activeDeviceUid;
    activeDeviceName = args['activeDeviceName']?.toString() ?? activeDeviceName;
    activeDeviceType = args['activeDeviceType']?.toString() ?? activeDeviceType;
    
    final hadHeadset = hasBluetoothDevice;
    hasBluetoothDevice = args['hasBluetooth'] == true;
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      if (!hadHeadset && hasBluetoothDevice && state == CallState.active) {
        unawaited(setAudioRoute(AudioRoute.bluetooth));
      } else if (hadHeadset && !hasBluetoothDevice && audioRoute == AudioRoute.bluetooth) {
        unawaited(setAudioRoute(callType == CallType.video ? AudioRoute.speaker : AudioRoute.earpiece));
      }
    }

    headsetName = args['headsetName']?.toString() ?? '';
    iosInputs = ((args['inputs'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final nativeRouteStr = args['actualRoute']?.toString();
    if (nativeRouteStr == 'speaker') {
      audioRoute = AudioRoute.speaker;
      speakerOn = true;
    } else if (nativeRouteStr == 'earpiece') {
      audioRoute = AudioRoute.earpiece;
      speakerOn = false;
    } else if (nativeRouteStr == 'bluetooth') {
      audioRoute = AudioRoute.bluetooth;
      speakerOn = false;
      if (activeDeviceUid.isNotEmpty) {
        selectedAudioDeviceId = activeDeviceUid;
      }
    }
    notifyListeners();
  }

  void _initNativeAudioChannel() {
    _nativeAudioChannel.setMethodCallHandler((call) async {
      if (call.method == 'onAudioRouteChanged') {
        final Map<dynamic, dynamic> args = call.arguments is Map ? call.arguments : {};
        if (defaultTargetPlatform == TargetPlatform.iOS) {
          _applyNativeState(Map<String, dynamic>.from(args));
        }
      }
    });
  }

  Future<void> init() async {
    if (_inited) return;
    _inited = true;
    _initNativeAudioChannel();

    try {
      await localRenderer.initialize();
      await remoteRenderer.initialize();
      localRenderer.onFirstFrameRendered = () {
        hasFirstLocalFrame = true;
        notifyListeners();
      };
      remoteRenderer.onFirstFrameRendered = () {
        hasFirstRemoteFrame = true;
        notifyListeners();
      };
    } catch (e) {
      debugPrint('[CALL] Error initializing video renderers: $e');
    }

    if (defaultTargetPlatform != TargetPlatform.iOS) {
      try {
        navigator.mediaDevices.ondevicechange = (event) async {
          debugPrint('[CALL] Media devices changed event received...');
          if (_isUserSwitchingAudioRoute || isRouteSwitching) {
            await refreshAudioDevices();
            return;
          }

          await refreshAudioDevices();
          await getAudioRouteInfo();

          if (userSelectedAudioRoute != null) return;

          if (hasBluetoothDevice && audioRoute != AudioRoute.bluetooth) {
            await setAudioRoute(AudioRoute.bluetooth, isUserAction: false);
          } else if (!hasBluetoothDevice && audioRoute == AudioRoute.bluetooth) {
            final fallback = (callType == CallType.video) ? AudioRoute.speaker : AudioRoute.earpiece;
            await setAudioRoute(fallback, isUserAction: false);
          }
        };
      } catch (e) {
        debugPrint('[CALL] Error binding device change listener: $e');
      }
    }
  }

  Map<String, dynamic>? pendingUpgradeRequest;

  void attachSocket(io.Socket socket) {
    _socket = socket;
    _socket!.off('incoming_call');
    _socket!.off('call_ringing');
    _socket!.off('call_accepted');
    _socket!.off('call_ended');
    _socket!.off('webrtc_signal');
    _socket!.off('call_media_state');
    _socket!.off('call_upgrade_requested');
    _socket!.off('call_upgrade_cancelled');
    _socket!.off('call_upgrade_rejected');
    _socket!.off('call_upgraded');
    _socket!.off('call_type_switched');

    _socket!.on('incoming_call', (d) => _guard(() => _onIncoming(_map(d))));
    _socket!.on('call_ringing', (d) => _guard(() => _onRinging(_map(d))));
    _socket!.on('call_accepted', (d) => _guard(() => _onAccepted(_map(d))));
    _socket!.on('call_ended', (d) => _guard(() => _onEnded(_map(d))));
    _socket!.on('webrtc_signal', (d) => _guard(() => _onSignal(_map(d))));
    _socket!.on('call_media_state', (d) => _guard(() => _onMediaState(_map(d))));
    _socket!.on('call_upgrade_requested', (d) => _guard(() => _onUpgradeRequested(_map(d))));
    _socket!.on('call_upgrade_cancelled', (d) => _guard(() => _onUpgradeCancelled(_map(d))));
    _socket!.on('call_upgrade_rejected', (d) => _guard(() => _onUpgradeRejected(_map(d))));
    _socket!.on('call_upgraded', (d) => _guard(() => _onUpgraded(_map(d))));
    _socket!.on('call_type_switched', (d) => _guard(() => _onCallTypeSwitched(_map(d))));
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
    localRenderer.srcObject = null;
    remoteRenderer.srcObject = null;
    hasFirstLocalFrame = false;
    hasFirstRemoteFrame = false;
    if (_localStream != null) {
      _stopStream(_localStream!);
      _localStream = null;
    }
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

    localRenderer.srcObject = null;
    remoteRenderer.srcObject = null;
    hasFirstLocalFrame = false;
    hasFirstRemoteFrame = false;
    if (_localStream != null) {
      _stopStream(_localStream!);
      _localStream = null;
    }

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

    callId = _asInt(data['call_id']);
    this.chatHeadId = chatHeadId;
    callType = type;
    isCaller = true;
    isMinimizedNotifier.value = false;
    await initializeDefaultAudioRoute(type);

    if (data['status'] == 'busy') {
      endReasonMessage = 'User is busy';
      _setState(CallState.ended);
      notifyListeners();
      Timer(const Duration(milliseconds: 2000), () {
        _cleanup(notifyEnd: null);
      });
      return;
    }

    // Caller stays on Connecting... until call_ringing socket event is received
    _setState(CallState.connecting);

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
    localRenderer.srcObject = null;
    remoteRenderer.srcObject = null;
    if (_localStream != null) {
      _stopStream(_localStream!);
      _localStream = null;
    }

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
    if (callType != CallType.video) {
      unawaited(switchCallType(CallType.video));
      return;
    }
    camOn = !camOn;
    if (!camOn) hasFirstLocalFrame = false;
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
            'width': {'ideal': 1080, 'min': 720},
            'height': {'ideal': 1920, 'min': 1280},
            'frameRate': 30,
          },
        });
        if (videoStream.getVideoTracks().isNotEmpty) {
          final newTrack = videoStream.getVideoTracks().first;
          isFrontCamera = true;
          cameraZoomScale = 1.0;
          _localStream?.addTrack(newTrack);
          localRenderer.srcObject = _localStream;
          if (_pc != null) {
            await _pc!.addTrack(newTrack, _localStream!);
            final offer = await _pc!.createOffer();
            final id = callId;
            if (id != null) {
              await _setLocalDescriptionAndSignal(_pc!, offer, id);
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

  bool isUpgradeRequestPending = false;

  // 1. Emit call_upgrade_request (user presses video button on voice call screen)
  Future<void> requestVideoCallUpgrade() async {
    final id = callId;
    if (id == null || state != CallState.active) return;
    if (isUpgradeRequestPending) return;

    try {
      isUpgradeRequestPending = true;
      notifyListeners();
      AppToast.show('Requesting video call switch...');

      final payload = {'call_id': id};
      final ack = await _emit('call_upgrade_request', payload);
      debugPrint('[CALL] call_upgrade_request ack: $ack');
    } on CallException catch (e) {
      isUpgradeRequestPending = false;
      notifyListeners();
      debugPrint('[CALL] call_upgrade_request exception: $e');
      if (e.status == 409) {
        AppToast.show('Upgrade request already pending');
      } else {
        AppToast.show(e.message, isError: true);
      }
    } catch (e) {
      isUpgradeRequestPending = false;
      notifyListeners();
      debugPrint('[CALL] Video upgrade request error: $e');
    }
  }

  // 2. Emit call_upgrade_cancel
  Future<void> cancelVideoCallUpgrade() async {
    final id = callId;
    if (id == null) return;
    isUpgradeRequestPending = false;
    notifyListeners();
    await _emit('call_upgrade_cancel', {'call_id': id}).catchError((_) => <String, dynamic>{});
  }

  // 3. Emit call_upgrade_accept (other user accepts request on voice call screen)
  Future<void> acceptVideoCallUpgrade() async {
    final id = callId;
    pendingUpgradeRequest = null;
    isUpgradeRequestPending = false;

    // Immediately enable local camera and switch callType to video for accepting user
    final hasCam = await _ensureVideoTrack();
    if (hasCam) {
      callType = CallType.video;
      camOn = true;
      for (final t in _localStream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
        t.enabled = true;
      }
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await _configureIosAudio(CallType.video);
        if (audioRoute == AudioRoute.earpiece) await setAudioRoute(AudioRoute.speaker);
        await _native('setCallType', {'isVideo': true});
      } else if (audioRoute == AudioRoute.earpiece && !hasConnectedHeadphones) {
        await setAudioRoute(AudioRoute.speaker);
      }
      _sendMediaState();
    }
    notifyListeners();

    if (id == null) return;

    try {
      debugPrint('[CALL] Accepting video upgrade request for call_id: $id');
      await _emit('call_upgrade_accept', {'call_id': id});
    } catch (e) {
      debugPrint('[CALL] acceptVideoCallUpgrade error: $e');
    }
  }

  // 4. Emit call_upgrade_reject (other user declines request on voice call screen)
  Future<void> rejectVideoCallUpgrade() async {
    final id = callId;
    pendingUpgradeRequest = null;
    isUpgradeRequestPending = false;
    notifyListeners();
    if (id == null) return;

    try {
      debugPrint('[CALL] Rejecting video upgrade request for call_id: $id');
      await _emit('call_upgrade_reject', {'call_id': id});
    } catch (e) {
      debugPrint('[CALL] rejectVideoCallUpgrade error: $e');
    }
  }

  // 5. Socket Listener: call_upgrade_requested
  void _onUpgradeRequested(Map<String, dynamic> d) {
    debugPrint('[CALL] call_upgrade_requested event received: $d');
    final incomingCallId = _asInt(d['call_id']) ?? _asInt(d['callId']) ?? _asInt(d['id']);
    if (incomingCallId != null && callId != null && incomingCallId != callId) return;

    pendingUpgradeRequest = d;
    notifyListeners();
  }

  // 6. Socket Listener: call_upgrade_cancelled
  void _onUpgradeCancelled(Map<String, dynamic> d) {
    debugPrint('[CALL] call_upgrade_cancelled event received: $d');
    if (_asInt(d['call_id']) != callId) return;
    pendingUpgradeRequest = null;
    isUpgradeRequestPending = false;
    notifyListeners();
  }

  // 7. Socket Listener: call_upgrade_rejected
  void _onUpgradeRejected(Map<String, dynamic> d) {
    debugPrint('[CALL] call_upgrade_rejected event received: $d');
    if (_asInt(d['call_id']) != callId) return;
    pendingUpgradeRequest = null;
    isUpgradeRequestPending = false;
    notifyListeners();

    final reason = d['reason']?.toString().toLowerCase();
    if (reason == 'timeout') {
      AppToast.show('No response', isError: true);
    } else {
      AppToast.show('Request declined');
    }
  }

  // 8. Socket Listener: call_upgraded
  void _onUpgraded(Map<String, dynamic> d) async {
    debugPrint('[CALL] call_upgraded event received: $d');
    if (_asInt(d['call_id']) != callId) return;

    pendingUpgradeRequest = null;
    isUpgradeRequestPending = false;

    final requestedBy = _asInt(d['requested_by']) ?? _asInt(d['from']);
    final myUserId = ServerApiService.instance.currentUserId;

    // Step 1: Both users turn on camera with getUserMedia / local video track
    final hasCam = await _ensureVideoTrack();
    if (!hasCam) {
      debugPrint('[CALL] Failed to initialize camera for video upgrade');
      return;
    }

    callType = CallType.video;
    camOn = true;
    for (final t in _localStream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = true;
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await _configureIosAudio(CallType.video);
      if (audioRoute == AudioRoute.earpiece) await setAudioRoute(AudioRoute.speaker);
      await _native('setCallType', {'isVideo': true});
    } else if (audioRoute == AudioRoute.earpiece && !hasConnectedHeadphones) {
      await setAudioRoute(AudioRoute.speaker);
    }

    // Step 2: ONLY the requester creates offer and sends via webrtc_signal
    final isRequester = (requestedBy != null && myUserId != null && requestedBy == myUserId);
    if (isRequester || (requestedBy == null && isCaller)) {
      debugPrint('[CALL] I am the requester ($myUserId). Creating WebRTC offer for video upgrade...');
      if (_pc != null) {
        final offer = await _pc!.createOffer();
        final id = callId;
        if (id != null) {
          await _setLocalDescriptionAndSignal(_pc!, offer, id);
        }
      }
    } else {
      debugPrint('[CALL] I am the callee ($myUserId). Waiting for requester WebRTC offer...');
    }

    _sendMediaState();
    notifyListeners();
    AppToast.show('Call upgraded to Video');
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
        if (defaultTargetPlatform == TargetPlatform.iOS) {
          await _configureIosAudio(CallType.video);
          if (audioRoute == AudioRoute.earpiece) await setAudioRoute(AudioRoute.speaker);
          await _native('setCallType', {'isVideo': true});
        } else if (audioRoute == AudioRoute.earpiece && !hasConnectedHeadphones) {
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
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await _native('setCallType', {'isVideo': false});
      } else if (!hasConnectedHeadphones) {
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
    final tracks = _localStream?.getVideoTracks() ?? <MediaStreamTrack>[];
    if (tracks.isEmpty) return;

    try {
      await Helper.switchCamera(tracks.first);

      isFrontCamera = !isFrontCamera;
      isUltraWideActive = false;
      cameraZoomScale = 1.0;

      _sendMediaState();
      _sendFacing();

      final id = callId;
      if (id != null) {
        _emit('webrtc_signal', {
          'call_id': id,
          'type': 'camera_facing',
          'data': {'front': isFrontCamera},
        }).catchError((_) => <String, dynamic>{});
      }

      notifyListeners();
    } catch (e) {
      debugPrint('[CALL] Switch camera error: $e');
    }
  }

  Future<void> setCameraZoom(double scale) async {
    final clampedScale = scale.clamp(1.0, 5.0);
    if ((cameraZoomScale - clampedScale).abs() < 0.01) return;

    cameraZoomScale = clampedScale;
    notifyListeners();

    final tracks = _localStream?.getVideoTracks();
    if (tracks == null || tracks.isEmpty) return;
    final track = tracks.first;

    try {
      await Helper.setZoom(track, clampedScale);
    } catch (e) {
      debugPrint('[CALL] Native camera setZoom error: $e');
    }
  }

  Future<void> setSpeaker(bool on) async {
    await setAudioRoute(on ? AudioRoute.speaker : AudioRoute.earpiece, isUserAction: true);
  }

  bool get hasConnectedHeadset => hasConnectedHeadphones;

  bool _isBuiltInAudioDevice(MediaDeviceInfo d) {
    if (d.kind == 'audioinput') return true;

    final label = d.label.toLowerCase();
    final id = d.deviceId.toLowerCase();

    if (label.contains('speaker') ||
        label.contains('loudspeaker') ||
        label.contains('earpiece') ||
        label.contains('receiver') ||
        label.contains('phone') ||
        label.contains('built-in') ||
        label.contains('builtin') ||
        label.contains('microphone') ||
        id == 'speaker' ||
        id == 'earpiece' ||
        id == 'receiver' ||
        id == 'phone' ||
        id == 'microphone' ||
        id == 'built-in') {
      return true;
    }

    return false;
  }

  bool get hasConnectedHeadphones {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return hasBluetoothDevice || audioRoute == AudioRoute.bluetooth;
    }
    for (final d in availableAudioDevices) {
      if (d.kind == 'audiooutput' && !_isBuiltInAudioDevice(d)) {
        return true;
      }
    }
    return false;
  }

  String get connectedHeadsetName {
    if (activeDeviceName.isNotEmpty &&
        activeDeviceName != 'Speaker' &&
        activeDeviceName != 'Phone' &&
        activeDeviceName != 'Phone Earpiece' &&
        activeDeviceName != 'Receiver' &&
        activeDeviceName != 'Built-In Receiver' &&
        activeDeviceName != 'Built-In Speaker') {
      return activeDeviceName;
    }
    if (headsetName.isNotEmpty &&
        headsetName != 'Speaker' &&
        headsetName != 'Phone' &&
        headsetName != 'Phone Earpiece') {
      return headsetName;
    }
    for (final d in availableAudioDevices) {
      if (d.kind == 'audiooutput' && !_isBuiltInAudioDevice(d)) {
        return d.label.isNotEmpty ? d.label : 'Bluetooth Headset';
      }
    }
    if (actualOutputPort.isNotEmpty &&
        actualOutputPort != 'Unknown' &&
        actualOutputPort != 'Speaker' &&
        actualOutputPort != 'Receiver' &&
        actualOutputPort != 'Built-In Receiver' &&
        actualOutputPort != 'Built-In Speaker') {
      return actualOutputPort;
    }
    if (actualInputPort.isNotEmpty &&
        actualInputPort != 'Unknown' &&
        actualInputPort != 'Built-In Microphone' &&
        actualInputPort != 'iPhone Microphone') {
      return actualInputPort;
    }
    if (selectedAudioDeviceName.isNotEmpty &&
        selectedAudioDeviceName != 'Speaker' &&
        selectedAudioDeviceName != 'Phone' &&
        selectedAudioDeviceName != 'Phone Earpiece' &&
        selectedAudioDeviceName != 'Earpiece') {
      return selectedAudioDeviceName;
    }
    return 'Bluetooth Headset';
  }

  Future<void> refreshAudioDevices() async {
    try {
      final devices = await navigator.mediaDevices.enumerateDevices();
      availableAudioDevices = devices
          .where((d) => d.kind == 'audiooutput' || d.kind == 'audioinput')
          .toList();
      debugPrint('[AUDIO_LOG] Refreshed devices (${availableAudioDevices.length} total):');
      for (final d in availableAudioDevices) {
        debugPrint('[AUDIO_LOG]   - kind=${d.kind}, id="${d.deviceId}", label="${d.label}"');
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[AUDIO_LOG ERROR] refreshAudioDevices error: $e');
    }
  }

  Future<void> selectAudioDevice(MediaDeviceInfo device) async {
    selectedAudioDeviceId = device.deviceId;
    final labelLower = device.label.toLowerCase();
    selectedAudioDeviceName = device.label.isNotEmpty ? device.label : 'Headset';

    try {
      if (labelLower.contains('speaker') || labelLower.contains('loudspeaker')) {
        await setAudioRoute(AudioRoute.speaker, deviceId: device.deviceId, isUserAction: true);
      } else if (labelLower.contains('earpiece') || labelLower.contains('receiver') || labelLower.contains('built-in')) {
        await setAudioRoute(AudioRoute.earpiece, deviceId: device.deviceId, isUserAction: true);
      } else {
        await setAudioRoute(AudioRoute.bluetooth, deviceId: device.deviceId, isUserAction: true);
      }
    } catch (e) {
      debugPrint('[CALL] Select audio device error: $e');
    }
    notifyListeners();
  }

  List<AudioOutputOption> getAvailableAudioOptions() {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final isVideo = callType == CallType.video;
      final list = <AudioOutputOption>[];

      // 1. External connected headphone / Bluetooth devices
      if (iosInputs.isNotEmpty) {
        for (final inp in iosInputs) {
          final name = inp['name']?.toString() ?? 'Headphones';
          final uid = inp['uid']?.toString() ?? 'bluetooth';
          final isCar = inp['isCar'] == true || name.toLowerCase().contains('car');
          list.add(AudioOutputOption(
            id: uid,
            label: name,
            subtitle: isCar ? 'CarPlay speaker & mic' : 'Headphone speaker & mic',
            icon: isCar ? CupertinoIcons.car : CupertinoIcons.headphones,
            route: AudioRoute.bluetooth,
          ));
        }
      } else if (hasConnectedHeadphones) {
        final name = connectedHeadsetName.isNotEmpty ? connectedHeadsetName : 'Headphones';
        final isCar = name.toLowerCase().contains('car') || activeDeviceType == 'CarAudio';
        list.add(AudioOutputOption(
          id: 'bluetooth',
          label: name,
          subtitle: isCar ? 'CarPlay speaker & mic' : 'Headphone speaker & mic',
          icon: isCar ? CupertinoIcons.car : CupertinoIcons.headphones,
          route: AudioRoute.bluetooth,
        ));
      }

      // 2. Phone earpiece ONLY for voice calls (NEVER for video calls)
      if (!isVideo) {
        list.add(const AudioOutputOption(
          id: 'earpiece',
          label: 'Phone Earpiece',
          subtitle: 'Phone receiver & mic',
          icon: CupertinoIcons.phone_fill,
          route: AudioRoute.earpiece,
        ));
      }

      // 3. Speaker
      list.add(const AudioOutputOption(
        id: 'speaker',
        label: 'Speaker',
        subtitle: 'Device speaker & mic',
        icon: CupertinoIcons.speaker_3_fill,
        route: AudioRoute.speaker,
      ));

      return list;
    }

    final List<AudioOutputOption> options = [];

    // Connected external headsets/Bluetooth devices (Android)
    final externalDevices = <MediaDeviceInfo>[];
    for (final d in availableAudioDevices) {
      if (d.kind == 'audiooutput' && !_isBuiltInAudioDevice(d)) {
        final cleanLabel = d.label.trim();
        final alreadyAdded = externalDevices.any((ex) {
          if (ex.deviceId.isNotEmpty && ex.deviceId == d.deviceId) return true;
          if (cleanLabel.isNotEmpty && ex.label.trim().toLowerCase() == cleanLabel.toLowerCase()) return true;
          return false;
        });

        if (!alreadyAdded) {
          externalDevices.add(d);
        }
      }
    }

    if (externalDevices.isNotEmpty) {
      for (final dev in externalDevices) {
        final displayName = dev.label.isNotEmpty ? dev.label : 'Headphones / Bluetooth';
        final isCar = displayName.toLowerCase().contains('car') || displayName.toLowerCase().contains('auto');
        options.add(
          AudioOutputOption(
            id: dev.deviceId.isNotEmpty ? dev.deviceId : 'bluetooth',
            label: displayName,
            subtitle: isCar ? 'CarPlay / Car speaker & mic' : 'Headphone speaker & mic',
            icon: isCar ? CupertinoIcons.car : CupertinoIcons.headphones,
            route: AudioRoute.bluetooth,
            rawDevice: dev,
          ),
        );
      }
    } else if (hasConnectedHeadphones) {
      final name = connectedHeadsetName.isNotEmpty ? connectedHeadsetName : 'Headphones / Bluetooth';
      final isCar = name.toLowerCase().contains('car') || name.toLowerCase().contains('auto');
      options.add(
        AudioOutputOption(
          id: 'bluetooth',
          label: name,
          subtitle: isCar ? 'CarPlay / Car speaker & mic' : 'Headphone speaker & mic',
          icon: isCar ? CupertinoIcons.car : CupertinoIcons.headphones,
          route: AudioRoute.bluetooth,
        ),
      );
    }

    // Phone earpiece ONLY for voice calls
    if (callType != CallType.video) {
      options.add(const AudioOutputOption(
        id: 'earpiece',
        label: 'Phone Earpiece',
        subtitle: 'Phone receiver & mic',
        icon: CupertinoIcons.phone_fill,
        route: AudioRoute.earpiece,
      ));
    }

    options.add(const AudioOutputOption(
      id: 'speaker',
      label: 'Speaker',
      subtitle: 'Device speaker & mic',
      icon: CupertinoIcons.speaker_3_fill,
      route: AudioRoute.speaker,
    ));

    return options;
  }

  bool isAudioOptionSelected(AudioOutputOption option) {
    if (option.route == AudioRoute.speaker) {
      return audioRoute == AudioRoute.speaker;
    }
    if (option.route == AudioRoute.earpiece) {
      return audioRoute == AudioRoute.earpiece;
    }
    if (option.route == AudioRoute.bluetooth) {
      if (audioRoute != AudioRoute.bluetooth) return false;
      if (defaultTargetPlatform == TargetPlatform.iOS && iosInputs.length > 1) {
        return option.label.toLowerCase() == activeDeviceName.toLowerCase() ||
            option.id == activeDeviceUid;
      }
      return true;
    }
    return false;
  }

  Future<void> selectAudioOption(AudioOutputOption option) async {
    debugPrint('[AUDIO_LOG] selectAudioOption tapped: id="${option.id}", label="${option.label}", route=${option.route}');
    selectedAudioDeviceId = option.id;
    selectedAudioDeviceName = option.label;
    await setAudioRoute(option.route, deviceId: option.id, deviceName: option.label, isUserAction: true);

    // For Bluetooth-to-Bluetooth switching the native SCO handoff takes ~400-800ms.
    // Schedule two refreshes so the UI reflects the confirmed native state.
    if (option.route == AudioRoute.bluetooth && defaultTargetPlatform == TargetPlatform.iOS) {
      Future.delayed(const Duration(milliseconds: 500), () async {
        if (state == CallState.active || state == CallState.connecting) {
          await getAudioRouteInfo();
        }
      });
      Future.delayed(const Duration(milliseconds: 1100), () async {
        if (state == CallState.active || state == CallState.connecting) {
          await getAudioRouteInfo();
        }
      });
    }
  }

  Future<Map<String, dynamic>> getAudioRouteInfo() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return {};
    try {
      final res = await _nativeAudioChannel.invokeMethod('getAudioRouteInfo');
      if (res is Map) {
        final m = Map<String, dynamic>.from(res);
        _applyNativeState(m);
        return m;
      }
    } catch (e) {
      debugPrint('[AUDIO_LOG ERROR] getAudioRouteInfo error: $e');
    }
    return {};
  }

  Future<void> reapplyRoute() async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await _native('reapplyRoute');
    }
  }

  Future<void> showSystemRoutePicker() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    try {
      await _nativeAudioChannel.invokeMethod('showRoutePicker');
    } catch (e) {
      debugPrint('[AUDIO_LOG ERROR] showRoutePicker: $e');
    }
  }

  Future<void> initializeDefaultAudioRoute(CallType type) async {
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await _configureIosAudio(type);
        final res = await _nativeAudioChannel.invokeMethod('configureCall', {
          'callType': type == CallType.video ? 'video' : 'voice',
        });
        if (res is Map) {
          _applyNativeState(Map<String, dynamic>.from(res));
        }
        notifyListeners();
        return;
      }

      for (int i = 0; i < 3; i++) {
        await refreshAudioDevices();
        if (hasConnectedHeadphones) break;
        await Future.delayed(const Duration(milliseconds: 150));
      }

      if (hasConnectedHeadphones) {
        await setAudioRoute(AudioRoute.bluetooth, isUserAction: false);
      } else {
        if (type == CallType.video) {
          await setAudioRoute(AudioRoute.speaker, isUserAction: false);
        } else {
          await setAudioRoute(AudioRoute.earpiece, isUserAction: false);
        }
      }
    } catch (e) {
      debugPrint('[AUDIO_LOG ERROR] Audio route init warning: $e');
    }
  }

  MediaDeviceInfo? get _builtInMicrophoneDevice {
    for (final d in availableAudioDevices) {
      if (d.kind == 'audioinput') {
        final label = d.label.toLowerCase();
        final id = d.deviceId.toLowerCase();
        if (label.contains('iphone microphone') ||
            label.contains('built-in') ||
            label.contains('microphone') ||
            id.contains('built-in') ||
            id.contains('microphone')) {
          return d;
        }
      }
    }
    return null;
  }

  MediaDeviceInfo? get _bluetoothMicrophoneDevice {
    for (final d in availableAudioDevices) {
      if (d.kind == 'audioinput') {
        final label = d.label.toLowerCase();
        final id = d.deviceId.toLowerCase();
        final isBuiltIn = label.contains('iphone microphone') ||
            label.contains('built-in') ||
            label.contains('receiver') ||
            label.contains('speaker') ||
            id.contains('built-in');
        if (!isBuiltIn) {
          return d;
        }
      }
    }
    return null;
  }

  Future<void> setAudioRoute(
    AudioRoute route, {
    String? deviceId,
    String? deviceName,
    bool isUserAction = false,
  }) async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      _isUserSwitchingAudioRoute = true;
      isRouteSwitching = true;
      if (isUserAction) userSelectedAudioRoute = route;

      final routeStr = route == AudioRoute.speaker
          ? 'speaker'
          : (route == AudioRoute.earpiece ? 'earpiece' : 'bluetooth');

      try {
        final res = await _nativeAudioChannel.invokeMethod('setAudioRoute', {
          'route': routeStr,
          'portUid': deviceId ?? '',
          'name': deviceName ?? '',
        });
        if (res is Map) {
          _applyNativeState(Map<String, dynamic>.from(res));
        }
      } catch (e) {
        debugPrint('[AUDIO] iOS route error: $e');
      } finally {
        _isUserSwitchingAudioRoute = false;
        isRouteSwitching = false;
      }
      notifyListeners();
      return;
    }

    final requestId = ++_routeSwitchRequestId;
    debugPrint('[AUDIO_LOG] === setAudioRoute START [#$requestId]: target route=$route, deviceId=$deviceId, isUserAction=$isUserAction, current route=$audioRoute ===');

    _isUserSwitchingAudioRoute = true;
    isRouteSwitching = true;
    requestedAudioRoute = route;
    if (isUserAction) {
      userSelectedAudioRoute = route;
    }
    if (deviceId != null && deviceId.isNotEmpty) {
      selectedAudioDeviceId = deviceId;
    }

    try {
      // Android routing
      await refreshAudioDevices();
      final builtInMic = _builtInMicrophoneDevice;
      final bluetoothMic = _bluetoothMicrophoneDevice;

      if (route == AudioRoute.speaker) {
        speakerOn = true;
        selectedAudioDeviceName = 'Speaker';
        await Helper.setSpeakerphoneOn(true);
        try { await Helper.selectAudioOutput('speaker'); } catch (_) {}
        if (builtInMic != null && builtInMic.deviceId.isNotEmpty) {
          try { await Helper.selectAudioInput(builtInMic.deviceId); } catch (_) {}
        }
      } else if (route == AudioRoute.earpiece) {
        speakerOn = false;
        selectedAudioDeviceName = 'Phone';
        await Helper.setSpeakerphoneOn(false);
        if (builtInMic != null && builtInMic.deviceId.isNotEmpty) {
          try { await Helper.selectAudioInput(builtInMic.deviceId); } catch (_) {}
        }
        try { await Helper.selectAudioOutput('earpiece'); } catch (_) {}
        try { await Helper.selectAudioOutput('receiver'); } catch (_) {}
      } else {
        speakerOn = false;
        selectedAudioDeviceName = (deviceId != null && deviceId.isNotEmpty && deviceId != 'bluetooth')
            ? _getLabelForDeviceId(deviceId)
            : connectedHeadsetName;
        await Helper.setSpeakerphoneOn(false);
        if (bluetoothMic != null && bluetoothMic.deviceId.isNotEmpty) {
          try { await Helper.selectAudioInput(bluetoothMic.deviceId); } catch (_) {}
        }
        try { await Helper.selectAudioOutput('bluetooth'); } catch (_) {}
      }
      audioRoute = route;
    } catch (e) {
      debugPrint('[AUDIO_LOG ERROR] Set audio route error [#$requestId]: $e');
    } finally {
      if (requestId == _routeSwitchRequestId) {
        isRouteSwitching = false;
        Future.delayed(const Duration(milliseconds: 600), () {
          _isUserSwitchingAudioRoute = false;
        });
      }
    }
    notifyListeners();
  }

  String _getLabelForDeviceId(String id) {
    for (final d in availableAudioDevices) {
      if (d.deviceId == id && d.label.isNotEmpty) return d.label;
    }
    return connectedHeadsetName;
  }

  void setMinimized(bool value) {
    if (!value) {
      FocusManager.instance.primaryFocus?.unfocus();
      unawaited(SystemChannels.textInput.invokeMethod('TextInput.hide'));
    }
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

    localRenderer.srcObject = null;
    remoteRenderer.srcObject = null;
    hasFirstLocalFrame = false;
    hasFirstRemoteFrame = false;
    if (_localStream != null) {
      _stopStream(_localStream!);
      _localStream = null;
    }

    callId = incomingCallId;
    chatHeadId = _asInt(d['chat_head_id']);
    peerId = _asInt(d['caller_id']);
    callType = d['call_type'] == 'video' ? CallType.video : CallType.voice;
    isCaller = false;
    isMinimizedNotifier.value = false;

    // Immediately emit call_ringing so caller transitions from Connecting... to Ringing...
    unawaited(_emit('call_ringing', {'call_id': incomingCallId}).catchError((_) => <String, dynamic>{}));

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

  void _onRinging(Map<String, dynamic> d) {
    final incomingCallId = _asInt(d['call_id']);
    if (incomingCallId != null && callId == incomingCallId && isCaller) {
      if (state == CallState.connecting) {
        _setState(CallState.outgoingRinging);
      }
    }
  }

  String _optimizeSdpQuality(String sdp) {
    if (sdp.isEmpty) return sdp;
    final lines = sdp.split('\r\n');
    final newLines = <String>[];
    bool inVideoSection = false;
    bool inAudioSection = false;

    for (final line in lines) {
      if (line.startsWith('m=video')) {
        inVideoSection = true;
        inAudioSection = false;
        newLines.add(line);
        newLines.add('b=AS:4500');
        continue;
      } else if (line.startsWith('m=audio')) {
        inAudioSection = true;
        inVideoSection = false;
        newLines.add(line);
        newLines.add('b=AS:128');
        continue;
      } else if (line.startsWith('m=')) {
        inVideoSection = false;
        inAudioSection = false;
      }

      if (inAudioSection && line.startsWith('a=fmtp:')) {
        if (!line.contains('stereo=')) {
          newLines.add('$line;stereo=1;sprop-stereo=1;useinbandfec=1;maxaveragebitrate=128000');
        } else {
          newLines.add(line);
        }
        continue;
      }

      if (inVideoSection && line.startsWith('a=fmtp:')) {
        if (!line.contains('x-google-min-bitrate')) {
          newLines.add('$line;x-google-min-bitrate=150;x-google-start-bitrate=1200;x-google-max-bitrate=4500');
        } else {
          newLines.add(line);
        }
        continue;
      }

      newLines.add(line);
    }
    return newLines.join('\r\n');
  }

  Future<void> _setLocalDescriptionAndSignal(
    RTCPeerConnection pc,
    RTCSessionDescription desc,
    int id,
  ) async {
    final optimizedSdp = _optimizeSdpQuality(desc.sdp ?? '');
    final optimizedDesc = RTCSessionDescription(optimizedSdp, desc.type);
    await pc.setLocalDescription(optimizedDesc);

    await _optimizeSenderParameters(pc);

    await _emit('webrtc_signal', {
      'call_id': id,
      'type': desc.type,
      'data': {'sdp': optimizedDesc.sdp, 'type': optimizedDesc.type},
    });
  }

  Future<void> _optimizeSenderParameters(RTCPeerConnection pc) async {
    try {
      final senders = await pc.getSenders();
      for (final sender in senders) {
        if (sender.track?.kind == 'video') {
          final params = sender.parameters;
          params.degradationPreference = RTCDegradationPreference.BALANCED;
          if (params.encodings != null && params.encodings!.isNotEmpty) {
            for (final encoding in params.encodings!) {
              encoding.maxBitrate = 4500000; // Uncapped 4.5 Mbps max for 1080p 60fps HD on fast internet
              encoding.minBitrate = 150000;  // 150 Kbps floor when internet slows down
              encoding.maxFramerate = 60;
            }
          }
          await sender.setParameters(params);
        } else if (sender.track?.kind == 'audio') {
          final params = sender.parameters;
          if (params.encodings != null && params.encodings!.isNotEmpty) {
            for (final encoding in params.encodings!) {
              encoding.maxBitrate = 96000;
            }
          }
          await sender.setParameters(params);
        }
      }
    } catch (e) {
      debugPrint('[CALL] _optimizeSenderParameters error: $e');
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
    await _setLocalDescriptionAndSignal(pc, offer, id);
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
        await _setLocalDescriptionAndSignal(pc, answer, id);
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

      case 'camera_facing':
        remoteIsFrontCamera = data['front'] == true;
        notifyListeners();
        break;

      case 'call_upgrade_requested':
      case 'request_video_switch':
      case 'video_switch_requested':
        _onUpgradeRequested(d);
        break;

      case 'call_upgraded':
      case 'video_switch_accepted':
        _onUpgraded(d);
        break;

      case 'call_upgrade_rejected':
      case 'video_switch_rejected':
        _onUpgradeRejected(d);
        break;
    }
  }

  void _onMediaState(Map<String, dynamic> d) {
    debugPrint('[CALL] media_state received: $d');
    if (_asInt(d['call_id']) != callId) return;
    if (d.containsKey('audio')) remoteAudioOn = d['audio'] == true;
    if (d.containsKey('video')) remoteVideoOn = d['video'] == true;
    if (d.containsKey('front')) remoteIsFrontCamera = d['front'] == true;
    notifyListeners();
  }

  void _onCallTypeSwitched(Map<String, dynamic> d) async {
    if (_asInt(d['call_id']) != callId) return;
    final typeStr = d['call_type']?.toString().toLowerCase();
    if (typeStr == 'video') {
      callType = CallType.video;
      final hasCam = await _ensureVideoTrack();
      if (hasCam) {
        camOn = true;
        for (final t in _localStream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
          t.enabled = true;
        }
        _sendMediaState();
      }
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await _native('setCallType', {'isVideo': true});
      } else if (audioRoute == AudioRoute.earpiece && !hasConnectedHeadphones) {
        await setAudioRoute(AudioRoute.speaker);
      }
      notifyListeners();
    } else if (typeStr == 'voice') {
      callType = CallType.voice;
      camOn = false;
      for (final t in _localStream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
        t.enabled = false;
      }
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        _native('setCallType', {'isVideo': false});
      } else {
        setAudioRoute(AudioRoute.earpiece);
      }
      notifyListeners();
    }
  }

  void _onEnded(Map<String, dynamic> d) {
    if (_asInt(d['call_id']) != callId) return;
    final statusStr = '${d['status']}'.toLowerCase();

    localRenderer.srcObject = null;
    remoteRenderer.srcObject = null;
    if (_localStream != null) {
      _stopStream(_localStream!);
      _localStream = null;
    }

    String message = 'Call ended';
    if (statusStr == 'busy') {
      message = 'User is busy';
    } else if (statusStr == 'missed') {
      message = 'No answer';
    } else if (statusStr == 'rejected') {
      message = 'Call declined';
    } else if (statusStr == 'cancelled') {
      message = 'Call cancelled';
    }

    endReasonMessage = message;
    _setState(CallState.ended);
    notifyListeners();

    if (statusStr == 'missed' || statusStr == 'rejected' || statusStr == 'busy' || statusStr == 'cancelled') {
      CallHistoryViewState.onNewMissedCallReceived();
    }

    final endedCallId = callId;
    final endedChatHeadId = chatHeadId;
    Timer(const Duration(milliseconds: 2200), () {
      if (callId == endedCallId) {
        _cleanup(
          notifyEnd: CallEndInfo(
            endedCallId!,
            _asInt(d['chat_head_id']) ?? endedChatHeadId ?? 0,
            statusStr,
            _asInt(d['ended_by']),
          ),
        );
      }
    });
  }

  // =====================================================================
  // WebRTC setup
  // =====================================================================

  Future<void> _prepare(int id, CallType type) async {
    localRenderer.srcObject = null;
    remoteRenderer.srcObject = null;
    camOn = type == CallType.video;
    remoteVideoOn = type == CallType.video;

    await _configureIosAudio(type);

    final ice = await ServerApiService.instance.getIceServers();
    if (callId != id) return;

    MediaStream stream;
    try {
      stream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': type == CallType.video
            ? {
                'facingMode': isFrontCamera ? 'user' : 'environment',
                'width': {'ideal': 1080, 'min': 480},
                'height': {'ideal': 1920, 'min': 640},
                'frameRate': {'ideal': 30, 'max': 30, 'min': 15},
              }
            : false,
      });
    } catch (e) {
      debugPrint('[CALL] Primary getUserMedia error: $e. Retrying with basic constraints...');
      try {
        stream = await navigator.mediaDevices.getUserMedia({
          'audio': true,
          'video': type == CallType.video
              ? {
                  'facingMode': isFrontCamera ? 'user' : 'environment',
                  'width': {'ideal': 720},
                  'height': {'ideal': 1280},
                  'frameRate': 30,
                }
              : false,
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

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await initializeDefaultAudioRoute(type);
    } else {
      try {
        await initializeDefaultAudioRoute(type);
      } catch (e) {
        debugPrint('[CALL] Audio route setup warning: $e');
      }
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

    pc.onDataChannel = (ch) => _setupDataChannel(ch);
    if (isCaller) {
      final ch = await pc.createDataChannel('meta', RTCDataChannelInit()..ordered = true);
      _setupDataChannel(ch);
    }

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
          if (defaultTargetPlatform == TargetPlatform.iOS) {
            unawaited(_native('ensureAudioEnabled'));
            unawaited(_native('reapplyRoute'));
          }
          _sendMediaState();
          _sendFacing();
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
    _emit('call_media_state', {
      'call_id': id,
      'audio': micOn,
      'video': camOn,
      'front': isFrontCamera,
    }).catchError((_) => <String, dynamic>{});
    _sendFacing();
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

      if (defaultTargetPlatform != TargetPlatform.iOS) {
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
      // iOS: do NOT call setAudioContext. It rewrites the global AVAudioSession.

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

    _dc?.close();
    _dc = null;

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
    hasFirstLocalFrame = false;
    hasFirstRemoteFrame = false;
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
    pendingUpgradeRequest = null;
    endReasonMessage = null;
    isCaller = false;
    isFrontCamera = true;
    remoteIsFrontCamera = true;
    activeSince = null;
    micOn = true;
    camOn = false;
    remoteAudioOn = true;
    remoteVideoOn = false;
    isMinimizedNotifier.value = false;
    userSelectedAudioRoute = null;
    setKeepScreenOn(false);
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      unawaited(_native('endCall'));
    }

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

  void _enforceActiveAudioRoute() {
    if (defaultTargetPlatform == TargetPlatform.iOS) return; // native owns iOS

    // Android path
    debugPrint('[AUDIO_LOG] Scheduling _enforceActiveAudioRoute (target route=$audioRoute, deviceId=$selectedAudioDeviceId)...');
    Future.delayed(const Duration(milliseconds: 250), () async {
      if (state == CallState.active) {
        debugPrint('[AUDIO_LOG] [250ms] Enforcing active audio route ($audioRoute, deviceId: $selectedAudioDeviceId)');
        await setAudioRoute(audioRoute, deviceId: selectedAudioDeviceId);
      }
    });
    Future.delayed(const Duration(milliseconds: 700), () async {
      if (state == CallState.active) {
        debugPrint('[AUDIO_LOG] [700ms] Enforcing active audio route ($audioRoute, deviceId: $selectedAudioDeviceId)');
        await setAudioRoute(audioRoute, deviceId: selectedAudioDeviceId);
      }
    });
  }

  static const MethodChannel _securityChannel = MethodChannel('com.shis.securecalc/security');

  Future<void> setKeepScreenOn(bool enable) async {
    try {
      debugPrint('[CALL] Setting keepScreenOn = $enable');
      await _securityChannel.invokeMethod('setKeepScreenOn', {'enable': enable});
    } catch (e) {
      debugPrint('[CALL] setKeepScreenOn error: $e');
    }
  }

  void _setState(CallState s) {
    state = s;
    if (s == CallState.outgoingRinging) {
      _playRingtone(isOutgoing: true);
      setKeepScreenOn(true);
    } else if (s == CallState.incomingRinging) {
      _playRingtone(isOutgoing: false);
      setKeepScreenOn(true);
    } else if (s == CallState.active) {
      _stopRingtone();
      if (callId != null) {
        unawaited(CallKitService.instance.setCallConnected(callId!));
      }
      _enforceActiveAudioRoute();
      setKeepScreenOn(true);
    } else {
      _stopRingtone();
    }
    notifyListeners();
  }

  Map<String, dynamic> _map(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  int? _asInt(dynamic v) => v == null ? null : (v is int ? v : int.tryParse('$v'));
}
