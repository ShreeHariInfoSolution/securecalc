import 'dart:async';
import 'dart:io';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../../core/utils/app_logger.dart';

typedef OnBluetoothDeviceDiscovered = void Function(String deviceId);
typedef OnBluetoothDeviceLost = void Function(String deviceId);

/// Service for discovering nearby devices running Synq Chat over Bluetooth Low Energy (BLE).
class BluetoothDiscoveryService {
  BluetoothDiscoveryService._internal();
  static final BluetoothDiscoveryService instance =
      BluetoothDiscoveryService._internal();

  static const String serviceUuid = 'a3f81010-3c22-4a41-bf1a-1d8f341d2d01';
  static const Duration deviceTimeout = Duration(seconds: 15);

  final FlutterBlePeripheral _blePeripheral = FlutterBlePeripheral();
  StreamSubscription? _scanSubscription;
  Timer? _periodicScanTimer;
  Timer? _cleanupTimer;

  bool _isDiscovering = false;
  String? _currentDeviceId;

  OnBluetoothDeviceDiscovered? onDeviceDiscovered;
  OnBluetoothDeviceLost? onDeviceLost;

  final Map<String, DateTime> _lastSeenMap = {};

  bool get isDiscovering => _isDiscovering;

  /// Start BLE advertisement & scanning.
  Future<void> startDiscovery({required String currentDeviceId}) async {
    if (_isDiscovering) return;

    _currentDeviceId = currentDeviceId;
    _isDiscovering = true;
    _lastSeenMap.clear();

    AppLogger.info(
        '[BLUETOOTH] Starting Bluetooth discovery for device: $_currentDeviceId');

    // 1. Request required Bluetooth permissions
    final hasPermissions = await _requestBluetoothPermissions();
    if (!hasPermissions) {
      AppLogger.error(
          '[BLUETOOTH] Bluetooth permissions denied. Bluetooth discovery unavailable.');
      return;
    }

    // 2. Check Bluetooth status
    try {
      final isSupported = await FlutterBluePlus.isSupported;
      if (!isSupported) {
        AppLogger.error(
            '[BLUETOOTH] Bluetooth hardware unsupported on this device.');
        return;
      }

      final adapterState = await FlutterBluePlus.adapterState.first;
      if (adapterState != BluetoothAdapterState.on) {
        AppLogger.error(
            '[BLUETOOTH] Bluetooth adapter is turned OFF. Bluetooth discovery unavailable.');
        return;
      }
    } catch (e) {
      AppLogger.error('[BLUETOOTH] Bluetooth status check failed: $e');
    }

    // 3. Start BLE Advertising
    await _startAdvertising();

    // 4. Start BLE Scanning
    await _startScanning();

    // 5. Cleanup Timer for lost Bluetooth devices
    _cleanupTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _checkDeviceTimeouts();
    });
  }

  Future<bool> _requestBluetoothPermissions() async {
    try {
      if (Platform.isAndroid) {
        final scanStatus = await Permission.bluetoothScan.request();
        final advertiseStatus = await Permission.bluetoothAdvertise.request();
        final connectStatus = await Permission.bluetoothConnect.request();
        final locationStatus = await Permission.locationWhenInUse.request();

        return scanStatus.isGranted &&
            advertiseStatus.isGranted &&
            connectStatus.isGranted &&
            locationStatus.isGranted;
      } else if (Platform.isIOS) {
        final bluetoothStatus = await Permission.bluetooth.request();
        return bluetoothStatus.isGranted;
      }
    } catch (e) {
      AppLogger.error('[BLUETOOTH] Permission request error: $e');
    }
    return true; // Proceed best-effort
  }

  Future<void> _startAdvertising() async {
    if (_currentDeviceId == null) return;

    try {
      final isAdvertisingSupported =
          await _blePeripheral.isSupported;
      if (isAdvertisingSupported) {
        final advertiseData = AdvertiseDataCore(
          serviceUuid: serviceUuid,
          localName: _currentDeviceId,
        );

        await _blePeripheral.start(advertiseData: advertiseData);
        AppLogger.info('[BLUETOOTH] Advertising started with ID: $_currentDeviceId');
      } else {
        AppLogger.error('[BLUETOOTH] BLE advertising not supported on hardware');
      }
    } catch (e) {
      AppLogger.error('[BLUETOOTH] Failed to start BLE advertising: $e');
    }
  }

  Future<void> _startScanning() async {
    try {
      _scanSubscription?.cancel();
      _scanSubscription = FlutterBluePlus.scanResults.listen(
        (results) {
          for (final result in results) {
            _processScanResult(result);
          }
        },
        onError: (e) {
          AppLogger.error('[BLUETOOTH] Scan listener error: $e');
        },
      );

      // Start continuous scanning interval
      await _performScanCycle();
      _periodicScanTimer = Timer.periodic(const Duration(seconds: 12), (_) {
        _performScanCycle();
      });
    } catch (e) {
      AppLogger.error('[BLUETOOTH] Failed to start BLE scanning: $e');
    }
  }

  Future<void> _performScanCycle() async {
    if (!_isDiscovering) return;
    try {
      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.stopScan();
      }
      await FlutterBluePlus.startScan(
        withServices: [Guid(serviceUuid)],
        timeout: const Duration(seconds: 8),
      );
    } catch (e) {
      AppLogger.error('[BLUETOOTH] Scan cycle error: $e');
    }
  }

  void _processScanResult(ScanResult result) {
    String? discoveredId;

    final advName = result.advertisementData.advName;
    final deviceName = result.device.platformName;

    if (advName.startsWith('device_')) {
      discoveredId = advName;
    } else if (deviceName.startsWith('device_')) {
      discoveredId = deviceName;
    }

    if (discoveredId != null && discoveredId.isNotEmpty) {
      if (discoveredId == _currentDeviceId) {
        return; // Ignore self
      }

      _lastSeenMap[discoveredId] = DateTime.now();
      AppLogger.info('[BLUETOOTH] Found device over BLE: $discoveredId');
      onDeviceDiscovered?.call(discoveredId);
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
      AppLogger.info('[BLUETOOTH] Lost Bluetooth device $deviceId (timeout)');
      onDeviceLost?.call(deviceId);
    }
  }

  /// Stop BLE advertising & scanning.
  Future<void> stopDiscovery() async {
    if (!_isDiscovering) return;

    _isDiscovering = false;

    _periodicScanTimer?.cancel();
    _periodicScanTimer = null;

    _cleanupTimer?.cancel();
    _cleanupTimer = null;

    _scanSubscription?.cancel();
    _scanSubscription = null;

    try {
      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.stopScan();
      }
      await _blePeripheral.stop();
    } catch (e) {
      AppLogger.error('[BLUETOOTH] Error stopping Bluetooth discovery: $e');
    }

    _lastSeenMap.clear();
    AppLogger.info('[BLUETOOTH] Bluetooth discovery stopped');
  }
}
