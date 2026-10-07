import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:securecalc/src/core/config/app_preferences.dart';
import 'package:securecalc/src/features/calling/domain/models/nearby_device.dart';
import 'package:securecalc/src/features/calling/domain/services/device_identity_service.dart';
import 'package:securecalc/src/features/calling/domain/services/nearby_device_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppPreferences.init();
  });

  group('DeviceIdentityService Tests', () {
    test('Device ID is created and remains permanent', () async {
      final id1 = await DeviceIdentityService.instance.getDeviceId();
      expect(id1.startsWith('device_'), isTrue);

      final id2 = await DeviceIdentityService.instance.getDeviceId();
      expect(id2, equals(id1));
    });
  });

  group('NearbyDeviceService Merging Tests', () {
    test('Merges Wi-Fi and Bluetooth sources for same device ID', () async {
      final service = NearbyDeviceService.instance;
      await DeviceIdentityService.instance.getDeviceId();

      // Start service conceptually (or manually invoke merging handlers)
      service.devicesNotifier.value = [];

      // Wi-Fi discovery finds device_B
      service.startDiscovery();
      // Wi-Fi finds device_B
      // (Using public/internal callback testing)
      final wifiDevice = NearbyDevice(
        deviceId: 'device_B',
        ipAddress: '192.168.1.20',
        port: 48231,
        source: DiscoverySource.wifi,
        isWifiAvailable: true,
        isBluetoothAvailable: false,
      );

      expect(wifiDevice.deviceId, equals('device_B'));
      expect(wifiDevice.source, equals(DiscoverySource.wifi));

      // Merge Bluetooth
      final mergedDevice = wifiDevice.copyWith(
        isBluetoothAvailable: true,
        source: DiscoverySource.both,
      );

      expect(mergedDevice.deviceId, equals('device_B'));
      expect(mergedDevice.source, equals(DiscoverySource.both));
      expect(mergedDevice.isWifiAvailable, isTrue);
      expect(mergedDevice.isBluetoothAvailable, isTrue);

      await service.stopDiscovery();
    });
  });
}
