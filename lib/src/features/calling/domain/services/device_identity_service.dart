import 'package:uuid/uuid.dart';
import '../../../../core/config/app_preferences.dart';
import '../../../../core/utils/app_logger.dart';

/// Reusable service responsible for maintaining a permanent unique Device ID.
class DeviceIdentityService {
  DeviceIdentityService._internal();
  static final DeviceIdentityService instance = DeviceIdentityService._internal();

  String? _cachedDeviceId;

  /// Get or initialize the permanent device identity.
  Future<String> getDeviceId() async {
    if (_cachedDeviceId != null && _cachedDeviceId!.isNotEmpty) {
      return _cachedDeviceId!;
    }

    final existingId = AppPreferences.getDeviceIdSync();
    if (existingId != null && existingId.isNotEmpty) {
      _cachedDeviceId = existingId;
      AppLogger.info('[DEVICE] Existing Device ID found: $_cachedDeviceId');
      return _cachedDeviceId!;
    }

    return await createDeviceIdIfMissing();
  }

  /// Create a new device ID if missing and persist it.
  Future<String> createDeviceIdIfMissing() async {
    final existingId = AppPreferences.getDeviceIdSync();
    if (existingId != null && existingId.isNotEmpty) {
      _cachedDeviceId = existingId;
      return existingId;
    }

    final newId = 'device_${const Uuid().v4()}';
    await AppPreferences.setDeviceId(newId);
    _cachedDeviceId = newId;
    AppLogger.info('[DEVICE] Generated and saved new Device ID: $newId');
    return newId;
  }

  /// Initialize device ID on application startup.
  Future<String> initializeDeviceId() async {
    final id = await getDeviceId();
    AppLogger.info('[DEVICE] Current Device ID initialized: $id');
    return id;
  }
}
