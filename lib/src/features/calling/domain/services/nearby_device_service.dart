import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../../core/utils/app_logger.dart';
import '../../../chat/domain/services/local_chat_storage.dart';
import '../models/nearby_device.dart';
import 'bluetooth_discovery_service.dart';
import 'device_identity_service.dart';
import 'wifi_discovery_service.dart'; // Retained so stopDiscovery can stop an older active session.

/// Unified service managing device identity, Wi-Fi & Bluetooth discovery, and merging.
class NearbyDeviceService {
  NearbyDeviceService._internal();
  static final NearbyDeviceService instance = NearbyDeviceService._internal();

  final Map<String, NearbyDevice> _discoveredDevices = {};

  final ValueNotifier<List<NearbyDevice>> devicesNotifier =
      ValueNotifier<List<NearbyDevice>>([]);

  final StreamController<List<NearbyDevice>> _devicesStreamController =
      StreamController<List<NearbyDevice>>.broadcast();

  final StreamController<NearbyDevice> _deviceDiscoveredController =
      StreamController<NearbyDevice>.broadcast();

  Stream<List<NearbyDevice>> get onDevicesChanged =>
      _devicesStreamController.stream;

  Stream<NearbyDevice> get onDeviceDiscovered =>
      _deviceDiscoveredController.stream;

  String? _currentDeviceId;
  bool _isSearching = false;

  bool get isSearching => _isSearching;
  String? get currentDeviceId => _currentDeviceId;

  /// Returns current list of unique merged nearby devices.
  List<NearbyDevice> getNearbyDevices() {
    return List.unmodifiable(_discoveredDevices.values);
  }

  /// Start unified Wi-Fi and Bluetooth discovery.
  Future<void> startDiscovery() async {
    if (_isSearching) return;

    _isSearching = true;

    // 1. Get permanent unique Device ID
    _currentDeviceId = await DeviceIdentityService.instance.getDeviceId();
    AppLogger.info('[DEVICE] Current Device ID: $_currentDeviceId');

    _discoveredDevices.clear();
    _notifyUpdates();

    // Wi-Fi discovery was disabled when local Wi-Fi chat was removed.

    // 3. Wire Bluetooth Discovery callbacks
    BluetoothDiscoveryService.instance.onDeviceDiscovered =
        _handleBluetoothDeviceDiscovered;
    BluetoothDiscoveryService.instance.onDeviceLost =
        _handleBluetoothDeviceLost;

    // Start Bluetooth discovery only; local Wi-Fi discovery stays disabled.
    await BluetoothDiscoveryService.instance
        .startDiscovery(currentDeviceId: _currentDeviceId!);

    AppLogger.info('[NEARBY] Discovery started for $_currentDeviceId');
  }

  /// Stop discovery on all transports.
  Future<void> stopDiscovery() async {
    if (!_isSearching) return;

    _isSearching = false;

    // Stop any Wi-Fi discovery session left active from an earlier app version.
    await WifiDiscoveryService.instance.stopDiscovery();
    await BluetoothDiscoveryService.instance.stopDiscovery();

    _discoveredDevices.clear();
    _notifyUpdates();

    AppLogger.info('[NEARBY] Discovery stopped');
  }

  // --- MERGING & DEDUPLICATION LOGIC ---

  void _handleWifiDeviceDiscovered(
      String deviceId, String displayName, String? profileImagePath, String ipAddress, int port) {
    if (deviceId == _currentDeviceId) return; // Never show current device

    // Update conversation in LocalChatStorage with peer's display name and profile image!
    LocalChatStorage.instance.updatePeerProfile(
      deviceId: deviceId,
      displayName: displayName,
      avatarUrl: profileImagePath,
    );

    final existing = _discoveredDevices[deviceId];

    if (existing == null) {
      final newDevice = NearbyDevice(
        deviceId: deviceId,
        displayName: displayName,
        profileImagePath: profileImagePath,
        ipAddress: ipAddress,
        port: port,
        source: DiscoverySource.wifi,
        isWifiAvailable: true,
        isBluetoothAvailable: false,
        lastSeen: DateTime.now(),
      );
      _discoveredDevices[deviceId] = newDevice;
      _deviceDiscoveredController.add(newDevice);
      AppLogger.info(
          '[NEARBY] Merged $displayName ($deviceId) - Sources: ${newDevice.source.name} (IP: $ipAddress)');
    } else {
      final updatedSource = existing.isBluetoothAvailable
          ? DiscoverySource.both
          : DiscoverySource.wifi;

      final updatedDevice = existing.copyWith(
        displayName: displayName,
        profileImagePath: profileImagePath ?? existing.profileImagePath,
        ipAddress: ipAddress,
        port: port,
        isWifiAvailable: true,
        source: updatedSource,
        lastSeen: DateTime.now(),
      );
      _discoveredDevices[deviceId] = updatedDevice;
      AppLogger.info(
          '[NEARBY] Merged $displayName ($deviceId) - Sources: ${updatedDevice.source.name} (IP: $ipAddress)');
    }

    _notifyUpdates();
  }

  void _handleBluetoothDeviceDiscovered(String deviceId) {
    if (deviceId == _currentDeviceId) return; // Never show current device

    final existing = _discoveredDevices[deviceId];

    if (existing == null) {
      final newDevice = NearbyDevice(
        deviceId: deviceId,
        source: DiscoverySource.bluetooth,
        isWifiAvailable: false,
        isBluetoothAvailable: true,
        lastSeen: DateTime.now(),
      );
      _discoveredDevices[deviceId] = newDevice;
      _deviceDiscoveredController.add(newDevice);
      AppLogger.info(
          '[NEARBY] Merged $deviceId - Sources: ${newDevice.source.name}');
    } else {
      final updatedSource = existing.isWifiAvailable
          ? DiscoverySource.both
          : DiscoverySource.bluetooth;

      final updatedDevice = existing.copyWith(
        isBluetoothAvailable: true,
        source: updatedSource,
        lastSeen: DateTime.now(),
      );
      _discoveredDevices[deviceId] = updatedDevice;
      AppLogger.info(
          '[NEARBY] Merged $deviceId - Sources: ${updatedDevice.source.name}');
    }

    _notifyUpdates();
  }

  void _handleWifiDeviceLost(String deviceId) {
    final existing = _discoveredDevices[deviceId];
    if (existing == null) return;

    if (existing.isBluetoothAvailable) {
      final updatedDevice = existing.copyWith(
        isWifiAvailable: false,
        source: DiscoverySource.bluetooth,
      );
      _discoveredDevices[deviceId] = updatedDevice;
      AppLogger.info('[NEARBY] $deviceId lost Wi-Fi, keeping via Bluetooth');
    } else {
      _discoveredDevices.remove(deviceId);
      AppLogger.info('[NEARBY] $deviceId removed');
    }

    _notifyUpdates();
  }

  void _handleBluetoothDeviceLost(String deviceId) {
    final existing = _discoveredDevices[deviceId];
    if (existing == null) return;

    if (existing.isWifiAvailable) {
      final updatedDevice = existing.copyWith(
        isBluetoothAvailable: false,
        source: DiscoverySource.wifi,
      );
      _discoveredDevices[deviceId] = updatedDevice;
      AppLogger.info('[NEARBY] $deviceId lost Bluetooth, keeping via Wi-Fi');
    } else {
      _discoveredDevices.remove(deviceId);
      AppLogger.info('[NEARBY] $deviceId removed');
    }

    _notifyUpdates();
  }

  void _notifyUpdates() {
    final list = List<NearbyDevice>.unmodifiable(_discoveredDevices.values);
    devicesNotifier.value = list;
    if (!_devicesStreamController.isClosed) {
      _devicesStreamController.add(list);
    }
  }
}
