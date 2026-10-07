import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../../../../core/config/app_preferences.dart';
import '../../../../core/utils/app_logger.dart';

typedef OnWifiDeviceDiscovered = void Function(
    String deviceId, String displayName, String? profileImagePath, String ipAddress, int port);
typedef OnWifiDeviceLost = void Function(String deviceId);

/// Service for discovering nearby devices running Synq Chat over Wi-Fi local network.
class WifiDiscoveryService {
  WifiDiscoveryService._internal();
  static final WifiDiscoveryService instance = WifiDiscoveryService._internal();

  static const int wifiDiscoveryPort = 48231;
  static const Duration broadcastInterval = Duration(seconds: 3);
  static const Duration deviceTimeout = Duration(seconds: 10);

  RawDatagramSocket? _socket;
  Timer? _broadcastTimer;
  Timer? _cleanupTimer;
  bool _isDiscovering = false;
  String? _currentDeviceId;

  OnWifiDeviceDiscovered? onDeviceDiscovered;
  OnWifiDeviceLost? onDeviceLost;

  final Map<String, DateTime> _lastSeenMap = {};

  bool get isDiscovering => _isDiscovering;

  /// Start Wi-Fi discovery and advertisement.
  Future<void> startDiscovery({required String currentDeviceId}) async {
    if (_isDiscovering) return;

    _currentDeviceId = currentDeviceId;
    _isDiscovering = true;
    _lastSeenMap.clear();

    AppLogger.info('[WIFI] Starting Wi-Fi discovery for device: $_currentDeviceId');

    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        wifiDiscoveryPort,
        reuseAddress: true,
      );
      _socket?.broadcastEnabled = true;

      _socket?.listen(
        (RawSocketEvent event) {
          if (event == RawSocketEvent.read) {
            final datagram = _socket?.receive();
            if (datagram != null) {
              _handleIncomingDatagram(datagram);
            }
          }
        },
        onError: (e) {
          AppLogger.error('[WIFI] Socket listener error: $e');
        },
      );

      // Start periodic advertisement broadcast
      _broadcastTimer = Timer.periodic(broadcastInterval, (_) {
        _sendBroadcastAnnouncement();
      });

      // Send initial announcement immediately
      _sendBroadcastAnnouncement();

      // Start periodic timeout cleanup
      _cleanupTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        _checkDeviceTimeouts();
      });

      AppLogger.info('[WIFI] Advertising started on port $wifiDiscoveryPort');
    } catch (e) {
      AppLogger.error('[WIFI] Wi-Fi discovery initialization failed: $e');
      _isDiscovering = false;
    }
  }

  void _sendBroadcastAnnouncement() async {
    if (!_isDiscovering || _socket == null || _currentDeviceId == null) return;

    // Respect user privacy setting for online status
    if (!AppPreferences.getShowOnlineStatus()) return;

    final displayName = AppPreferences.getDisplayName();
    String? profileBase64;

    try {
      final profilePath = AppPreferences.getProfileImagePath();
      if (profilePath != null && profilePath.isNotEmpty) {
        final file = File(profilePath);
        if (file.existsSync()) {
          final bytes = await file.readAsBytes();
          if (bytes.length < 60000) {
            profileBase64 = base64Encode(bytes);
          }
        }
      }
    } catch (_) {}

    final payload = jsonEncode({
      'deviceId': _currentDeviceId,
      'displayName': displayName,
      'profileBase64': profileBase64,
      'port': wifiDiscoveryPort,
      'type': 'SYNQ_CHAT_DISCOVERY',
    });

    final data = utf8.encode(payload);

    try {
      _socket?.send(data, InternetAddress('255.255.255.255'), wifiDiscoveryPort);
    } catch (e) {
      AppLogger.error('[WIFI] Failed to send broadcast announcement: $e');
    }
  }

  void _handleIncomingDatagram(Datagram datagram) async {
    try {
      final rawStr = utf8.decode(datagram.data);
      final jsonMap = jsonDecode(rawStr) as Map<String, dynamic>;

      if (jsonMap['type'] == 'SYNQ_CHAT_DISCOVERY') {
        final deviceId = jsonMap['deviceId'] as String?;
        final displayName = (jsonMap['displayName'] as String?) ?? deviceId ?? 'Unknown';
        final profileBase64 = jsonMap['profileBase64'] as String?;
        final port = (jsonMap['port'] as int?) ?? wifiDiscoveryPort;
        final senderIp = datagram.address.address;

        if (deviceId != null && deviceId.isNotEmpty) {
          if (deviceId == _currentDeviceId) {
            // Ignore self
            return;
          }

          String? savedProfilePath;
          if (profileBase64 != null && profileBase64.isNotEmpty) {
            try {
              final bytes = base64Decode(profileBase64);
              final tempDir = await getTemporaryDirectory();
              final file = File('${tempDir.path}/peer_profile_$deviceId.jpg');
              await file.writeAsBytes(bytes);
              savedProfilePath = file.path;
            } catch (_) {}
          }

          _lastSeenMap[deviceId] = DateTime.now();
          AppLogger.info('[WIFI] Found $displayName ($deviceId) at IP: $senderIp:$port');
          onDeviceDiscovered?.call(deviceId, displayName, savedProfilePath, senderIp, port);
        }
      }
    } catch (_) {
      // Ignore invalid packet formatting
    }
  }

  void _checkDeviceTimeouts() {
    final now = DateTime.now();
    final expiredDevices = <String>[];

    _lastSeenMap.forEach((deviceId, lastSeenTime) {
      if (now.difference(lastSeenTime) > deviceTimeout) {
        expiredDevices.add(deviceId);
      }
    });

    for (final deviceId in expiredDevices) {
      _lastSeenMap.remove(deviceId);
      AppLogger.info('[WIFI] Lost Wi-Fi device $deviceId (timeout)');
      onDeviceLost?.call(deviceId);
    }
  }

  /// Stop Wi-Fi discovery and advertisement.
  Future<void> stopDiscovery() async {
    if (!_isDiscovering) return;

    _isDiscovering = false;
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    _cleanupTimer?.cancel();
    _cleanupTimer = null;

    _socket?.close();
    _socket = null;
    _lastSeenMap.clear();

    AppLogger.info('[WIFI] Wi-Fi discovery stopped');
  }
}
