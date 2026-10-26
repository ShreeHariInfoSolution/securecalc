import 'dart:io';
import 'package:flutter/material.dart';
import 'package:live_activities/live_activities.dart';

import 'call_service.dart';

/// CallIslandManager
/// Orchestrates the Adaptive Dynamic / Camera Island overlay state
/// and iOS ActivityKit Live Activities for native iOS Dynamic Island.
class CallIslandManager with WidgetsBindingObserver {
  CallIslandManager._();
  static final CallIslandManager instance = CallIslandManager._();

  final LiveActivities _liveActivities = LiveActivities();
  bool _initialized = false;
  String? _activityId;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    WidgetsBinding.instance.addObserver(this);
    CallService.instance.addListener(_onCallStateChanged);

    if (Platform.isIOS) {
      try {
        await _liveActivities.init(
          appGroupId: "group.com.shis.securecalc",
          requireNotificationPermission: false,
        );
      } catch (e) {
        debugPrint('[LiveActivities] Init error: $e');
      }
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    CallService.instance.removeListener(_onCallStateChanged);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _updateIslandState();
  }

  void _onCallStateChanged() {
    _updateIslandState();
  }

  Future<void> _updateIslandState() async {
    if (!Platform.isIOS) return;

    final callService = CallService.instance;
    final isCallActive = callService.state == CallState.active ||
        callService.state == CallState.outgoingRinging ||
        callService.state == CallState.connecting;

    if (isCallActive) {
      final startTimeSeconds = (callService.activeSince?.millisecondsSinceEpoch ??
              DateTime.now().millisecondsSinceEpoch) /
          1000.0;
      final Map<String, dynamic> activityData = {
        'peerName': callService.peerName,
        'isVideo': callService.callType == CallType.video,
        'status': callService.state == CallState.active ? 'Call Active' : 'Calling...',
        'startTime': startTimeSeconds,
      };

      if (_activityId == null) {
        try {
          const actId = "active_call_island";
          _activityId = await _liveActivities.createActivity(
            actId,
            activityData,
            removeWhenAppIsKilled: true,
          );
        } catch (e) {
          debugPrint('[LiveActivities] Create error: $e');
        }
      } else {
        try {
          await _liveActivities.updateActivity(_activityId!, activityData);
        } catch (_) {}
      }
    } else {
      if (_activityId != null) {
        try {
          await _liveActivities.endActivity(_activityId!);
        } catch (_) {}
        _activityId = null;
      }
      try {
        await _liveActivities.endAllActivities();
      } catch (_) {}
    }
  }
}
