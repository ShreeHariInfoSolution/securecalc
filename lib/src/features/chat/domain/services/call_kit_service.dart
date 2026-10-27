import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

import 'call_service.dart';
import 'server_api_service.dart';
import 'socket_chat_service.dart';

String formatCallUuid(dynamic rawCallId) {
  if (rawCallId == null) return '00000000-0000-0000-0000-000000000000';
  final str = rawCallId.toString().trim();
  if (str.isEmpty) return '00000000-0000-0000-0000-000000000000';
  if (RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$').hasMatch(str)) {
    return str;
  }
  final numId = int.tryParse(str) ?? str.hashCode;
  final hex = numId.abs().toRadixString(16).padLeft(12, '0');
  final safeHex = hex.length > 12 ? hex.substring(hex.length - 12) : hex;
  return '00000000-0000-0000-0000-$safeHex';
}

class CallKitService {
  CallKitService._();
  static final CallKitService instance = CallKitService._();

  final Set<String> _processedCallIds = {};
  bool _listenerInitialized = false;

  void _handleCallAccept(int callId, Map<String, dynamic> extra) {
    if (CallService.instance.callId == callId &&
        (CallService.instance.state == CallState.connecting ||
            CallService.instance.state == CallState.active)) {
      debugPrint('[CallKit] Call $callId is already connecting or active.');
      return;
    }

    final chatHeadId = int.tryParse(extra['chat_head_id']?.toString() ?? '0') ?? 0;
    final callerId = int.tryParse(extra['caller_id']?.toString() ?? '0') ?? 0;
    final callTypeStr = extra['call_type']?.toString() ?? 'voice';
    final callerName = extra['caller_name']?.toString() ?? 'Contact';

    debugPrint('[CallKit] Processing call acceptance for callId: $callId');

    // Connect socket immediately
    SocketChatService.instance.connect();

    // Setup call service for incoming background accept
    CallService.instance.setupIncomingFromBackground(
      callId: callId,
      chatHeadId: chatHeadId,
      callerId: callerId,
      callType: callTypeStr == 'video' ? CallType.video : CallType.voice,
      callerName: callerName,
    );

    // Ensure call screen is shown full screen
    CallService.instance.setMinimized(false);

    // Trigger acceptance
    unawaited(CallService.instance.acceptCall());
  }

  Future<void> checkAndProcessInitialCall() async {
    try {
      final calls = await FlutterCallkitIncoming.activeCalls();
      if (calls is List && calls.isNotEmpty) {
        for (final call in calls) {
          if (call is Map) {
            final isAccepted = call['isAccepted'] == true || call['accepted'] == true;
            final extra = call['extra'] is Map
                ? Map<String, dynamic>.from(call['extra'] as Map)
                : Map<String, dynamic>.from(call);
            final rawCallId = extra['call_id'] ?? extra['callId'] ?? call['id'];
            final callId = int.tryParse(rawCallId?.toString() ?? '');

            if (callId != null && isAccepted) {
              debugPrint('[CallKit] Found initial active accepted call on cold start: $callId');
              _handleCallAccept(callId, extra);
              break;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[CallKit ERROR] Error checking initial active calls on cold start: $e');
    }
  }

  void initListener({void Function(Map<String, dynamic> data)? onAcceptNavigation}) {
    if (_listenerInitialized) return;
    _listenerInitialized = true;

    FlutterCallkitIncoming.onEvent.listen((CallEvent? event) async {
      if (event == null) return;
      debugPrint('[CallKit] Event received: ${event.event}, body: ${event.body}');

      final body = event.body is Map ? Map<String, dynamic>.from(event.body as Map) : <String, dynamic>{};
      final extra = body['extra'] is Map
          ? Map<String, dynamic>.from(body['extra'] as Map)
          : body;

      final rawCallId = extra['call_id'] ?? extra['callId'] ?? body['id'];
      final callId = int.tryParse(rawCallId?.toString() ?? '');

      switch (event.event) {
        case Event.actionCallAccept:
          debugPrint('[CallKit] Call accepted by user for callId: $callId');
          if (callId != null) {
            _handleCallAccept(callId, extra);
            if (onAcceptNavigation != null) {
              onAcceptNavigation(extra);
            }
          }
          break;

        case Event.actionCallDecline:
          debugPrint('[CallKit] Call declined by user for callId: $callId');
          if (callId != null) {
            if (CallService.instance.state != CallState.idle &&
                CallService.instance.callId == callId) {
              unawaited(CallService.instance.rejectCall());
            } else {
              unawaited(ServerApiService.instance.rejectCallREST(callId));
            }
          }
          await endCall(callId?.toString() ?? '');
          break;

        case Event.actionCallEnded:
        case Event.actionCallTimeout:
          debugPrint('[CallKit] Call ended/timed out for callId: $callId');
          if (callId != null &&
              CallService.instance.callId == callId &&
              CallService.instance.state != CallState.idle) {
            unawaited(CallService.instance.hangUp());
          }
          break;

        default:
          break;
      }
    });

    unawaited(checkAndProcessInitialCall());
  }

  Future<void> showIncomingCall({
    required int callId,
    required int chatHeadId,
    required int callerId,
    required String callerName,
    required String callType,
    String? avatar,
  }) async {
    final callUuid = formatCallUuid(callId);
    if (_processedCallIds.contains(callUuid)) {
      debugPrint('[CallKit] Skipping duplicate incoming call show for callUuid: $callUuid');
      return;
    }
    _processedCallIds.add(callUuid);

    // Keep cache reasonable size
    if (_processedCallIds.length > 50) {
      _processedCallIds.remove(_processedCallIds.first);
    }

    final isVideo = callType.toLowerCase() == 'video';

    final params = CallKitParams(
      id: callUuid,
      nameCaller: callerName.isNotEmpty ? callerName : 'Incoming Call',
      appName: 'Calculator',
      avatar: avatar ?? '',
      handle: isVideo ? 'Incoming Video Call' : 'Incoming Voice Call',
      type: isVideo ? 1 : 0,
      duration: 45000,
      textAccept: 'Accept',
      textDecline: 'Decline',
      extra: <String, dynamic>{
        'call_id': callId,
        'chat_head_id': chatHeadId,
        'caller_id': callerId,
        'caller_name': callerName,
        'call_type': callType,
      },
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#095544',
        actionColor: '#4CAF50',
        textColor: '#FFFFFF',
        isShowCallID: false,
        isShowFullLockedScreen: true,
      ),
      ios: const IOSParams(
        iconName: 'AppIcon',
        handleType: 'generic',
        supportsVideo: true,
        maximumCallGroups: 1,
        maximumCallsPerCallGroup: 1,
        audioSessionMode: 'voiceChat',
        audioSessionActive: true,
        supportsDTMF: true,
        supportsHolding: false,
        supportsGrouping: false,
        supportsUngrouping: false,
        ringtonePath: '',
      ),
    );

    try {
      final paramsMap = params.toJson();
      if (paramsMap['ios'] is Map) {
        (paramsMap['ios'] as Map<String, dynamic>)['includesCallsInRecents'] = false;
      } else {
        paramsMap['ios'] = <String, dynamic>{'includesCallsInRecents': false};
      }
      await const MethodChannel('flutter_callkit_incoming')
          .invokeMethod('showCallkitIncoming', paramsMap);
      debugPrint('[CallKit] Incoming call presented via CallKit (recents disabled) for callUuid: $callUuid');
    } catch (e) {
      debugPrint('[CallKit ERROR] Failed to show CallKit UI: $e');
    }
  }

  Future<void> startOutgoingCall({
    required int callId,
    required int chatHeadId,
    required int callerId,
    required String callerName,
    required String callType,
    String? avatar,
  }) async {
    final callUuid = formatCallUuid(callId);
    if (_processedCallIds.contains(callUuid)) {
      debugPrint('[CallKit] Skipping duplicate outgoing call start for callUuid: $callUuid');
      return;
    }
    _processedCallIds.add(callUuid);

    final isVideo = callType.toLowerCase() == 'video';

    final params = CallKitParams(
      id: callUuid,
      nameCaller: callerName.isNotEmpty ? callerName : 'Contact',
      appName: 'Calculator',
      avatar: avatar ?? '',
      handle: isVideo ? 'Outgoing Video Call' : 'Outgoing Voice Call',
      type: isVideo ? 1 : 0,
      duration: 45000,
      extra: <String, dynamic>{
        'call_id': callId,
        'chat_head_id': chatHeadId,
        'caller_id': callerId,
        'caller_name': callerName,
        'call_type': callType,
      },
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#095544',
        actionColor: '#4CAF50',
        textColor: '#FFFFFF',
        isShowCallID: false,
        isShowFullLockedScreen: true,
      ),
      ios: const IOSParams(
        iconName: 'AppIcon',
        handleType: 'generic',
        supportsVideo: true,
        maximumCallGroups: 1,
        maximumCallsPerCallGroup: 1,
        audioSessionMode: 'voiceChat',
        audioSessionActive: true,
        supportsDTMF: true,
        supportsHolding: false,
        supportsGrouping: false,
        supportsUngrouping: false,
        ringtonePath: '',
      ),
    );

    try {
      final paramsMap = params.toJson();
      if (paramsMap['ios'] is Map) {
        (paramsMap['ios'] as Map<String, dynamic>)['includesCallsInRecents'] = false;
      } else {
        paramsMap['ios'] = <String, dynamic>{'includesCallsInRecents': false};
      }
      await FlutterCallkitIncoming.startCall(params);
      debugPrint('[CallKit] Outgoing call presented via CallKit for callUuid: $callUuid');
    } catch (e) {
      debugPrint('[CallKit ERROR] Failed to start CallKit outgoing call: $e');
    }
  }

  Future<void> setCallConnected(dynamic callId) async {
    try {
      final callUuid = formatCallUuid(callId);
      if (callUuid.isNotEmpty) {
        await FlutterCallkitIncoming.setCallConnected(callUuid);
        debugPrint('[CallKit] Set call connected for callUuid: $callUuid');
      }
    } catch (e) {
      debugPrint('[CallKit ERROR] Failed to set CallKit call connected: $e');
    }
  }

  Future<void> endCall(dynamic callId) async {
    try {
      final callUuid = formatCallUuid(callId);
      if (callUuid.isNotEmpty) {
        await FlutterCallkitIncoming.endCall(callUuid);
      }
      await FlutterCallkitIncoming.endAllCalls();
      debugPrint('[CallKit] Ended CallKit for callUuid: $callUuid');
    } catch (e) {
      debugPrint('[CallKit ERROR] Failed to end CallKit call: $e');
    }
  }

  Future<void> clearAll() async {
    try {
      await FlutterCallkitIncoming.endAllCalls();
      _processedCallIds.clear();
    } catch (_) {}
  }
}
