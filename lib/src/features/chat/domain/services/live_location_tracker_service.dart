import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'server_api_service.dart';
import 'socket_chat_service.dart';

class LiveLocationTrackerService {
  LiveLocationTrackerService._();

  static final LiveLocationTrackerService instance =
      LiveLocationTrackerService._();

  StreamSubscription<Position>? _positionSub;
  StreamSubscription? _endedSub;
  Timer? _expirationTimer;
  Timer? _restFallbackTimer;

  int? _activeLocationId;
  int? _activeChatHeadId;
  DateTime? _activeExpiresAt;
  Position? _lastPosition;
  DateTime _lastSent = DateTime.fromMillisecondsSinceEpoch(0);

  final ValueNotifier<int?> activeLocationIdNotifier = ValueNotifier<int?>(null);
  final ValueNotifier<Position?> positionNotifier = ValueNotifier<Position?>(null);

  Position? get lastPosition => _lastPosition;
  int? get activeLocationId => _activeLocationId;
  int? get activeChatHeadId => _activeChatHeadId;
  bool get isTracking => _positionSub != null && _activeLocationId != null;

  /// Requests location permissions if needed and returns current position
  Future<Position?> getCurrentPosition() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('[LOCATION] Location services are disabled.');
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint('[LOCATION] Location permissions are denied');
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint('[LOCATION] Location permissions are permanently denied.');
        return null;
      }

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (e) {
      debugPrint('[LOCATION] Error getting current position: $e');
      return null;
    }
  }

  /// Starts live location tracking for a specific location_id
  Future<void> startTracking({
    required int locationId,
    required int chatHeadId,
    required int durationMinutes,
    DateTime? expiresAt,
  }) async {
    // If tracking a different location share, stop the old one first
    if (_activeLocationId != null && _activeLocationId != locationId) {
      await stopTracking();
    }

    _activeLocationId = locationId;
    _activeChatHeadId = chatHeadId;
    activeLocationIdNotifier.value = locationId;
    _activeExpiresAt = expiresAt ??
        DateTime.now().add(Duration(minutes: durationMinutes));

    final remainingSecs =
        _activeExpiresAt!.difference(DateTime.now()).inSeconds;
    if (remainingSecs <= 0) {
      debugPrint('[LOCATION TRACKER] Already expired ($locationId)');
      await stopTracking();
      return;
    }

    // Timer to stop tracking when expired
    _expirationTimer?.cancel();
    _expirationTimer = Timer(Duration(seconds: remainingSecs), () {
      debugPrint('[LOCATION TRACKER] Duration expired ($locationId)');
      stopTracking();
    });

    _endedSub?.cancel();
    _endedSub = SocketChatService.instance.onLiveLocationEnded.listen((d) {
      final raw = d['location'] is Map ? d['location'] as Map : d;
      final id = int.tryParse('${raw['id'] ?? raw['location_id']}');
      if (id != null && id == _activeLocationId) {
        stopTracking(notifyServer: false);
      }
    });

    // Request permissions and start position stream
    final initialPos = await getCurrentPosition();
    if (initialPos != null) {
      _lastPosition = initialPos;
      positionNotifier.value = initialPos;
      _sendLocationUpdate(locationId, initialPos);
    }

    final LocationSettings locationSettings = switch (defaultTargetPlatform) {
      TargetPlatform.android => AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
          intervalDuration: const Duration(seconds: 5),
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationTitle: 'Sharing live location',
            notificationText: 'Your live location is visible in a chat',
            enableWakeLock: true,
            setOngoing: true,
          ),
        ),
      TargetPlatform.iOS => AppleSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
          activityType: ActivityType.otherNavigation,
          pauseLocationUpdatesAutomatically: false,
          showBackgroundLocationIndicator: true,
          allowBackgroundLocationUpdates: true,
        ),
      _ => const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10),
    };

    _positionSub?.cancel();
    _positionSub = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position p) {
      _lastPosition = p;
      positionNotifier.value = p;
      _sendLocationUpdate(locationId, p);
    }, onError: (e) {
      debugPrint('[LOCATION TRACKER] Position stream error: $e');
    });

    // REST fallback timer every 15s if socket is dead
    _restFallbackTimer?.cancel();
    _restFallbackTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_lastPosition != null && _activeLocationId != null) {
        if (!SocketChatService.instance.isConnected) {
          ServerApiService.instance.updateLiveLocation(
            locationId: _activeLocationId!,
            latitude: _lastPosition!.latitude,
            longitude: _lastPosition!.longitude,
            accuracy: _lastPosition!.accuracy,
            heading: _lastPosition!.heading,
            speed: _lastPosition!.speed,
          );
        }
      }
    });

    debugPrint(
        '[LOCATION TRACKER] Started tracking locationId=$locationId duration=$durationMinutes mins');
  }

  /// Sends position update via socket (or REST fallback)
  void _sendLocationUpdate(int locationId, Position p) {
    final now = DateTime.now();
    if (now.difference(_lastSent) < const Duration(seconds: 3)) return;
    _lastSent = now;

    final socket = SocketChatService.instance.rawSocket;
    final payload = {
      'location_id': locationId,
      'latitude': p.latitude,
      'longitude': p.longitude,
      'accuracy': p.accuracy,
      'heading': p.heading,
      'speed': p.speed,
    };

    if (socket != null && socket.connected) {
      socket.emitWithAck('live_location_update', payload, ack: (dynamic response) {
        if (response is Map) {
          final status = response['status'] ?? response['statusCode'];
          if (status == 410) {
            debugPrint(
                '[LOCATION TRACKER] Server returned 410 (ended/expired). Stopping stream.');
            stopTracking();
          }
        }
      });
    } else {
      ServerApiService.instance.updateLiveLocation(
        locationId: locationId,
        latitude: p.latitude,
        longitude: p.longitude,
        accuracy: p.accuracy,
        heading: p.heading,
        speed: p.speed,
      );
    }
  }

  /// Stops active live location tracking
  Future<void> stopTracking({bool notifyServer = true}) async {
    final locId = _activeLocationId;
    _endedSub?.cancel();
    _endedSub = null;
    _lastSent = DateTime.fromMillisecondsSinceEpoch(0);
    positionNotifier.value = null;

    _positionSub?.cancel();
    _positionSub = null;

    _expirationTimer?.cancel();
    _expirationTimer = null;

    _restFallbackTimer?.cancel();
    _restFallbackTimer = null;

    _activeLocationId = null;
    _activeChatHeadId = null;
    activeLocationIdNotifier.value = null;
    _activeExpiresAt = null;
    _lastPosition = null;

    if (locId != null && notifyServer) {
      final socket = SocketChatService.instance.rawSocket;
      if (socket != null && socket.connected) {
        socket.emit('live_location_stop', {'location_id': locId});
      }
      await ServerApiService.instance.stopLiveLocation(locationId: locId);
      debugPrint('[LOCATION TRACKER] Stopped live location $locId');
    }
  }
}
