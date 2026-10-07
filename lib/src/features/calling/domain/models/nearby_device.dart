enum DiscoverySource {
  wifi,
  bluetooth,
  both,
}

/// Model representing a discovered nearby device over Wi-Fi/Bluetooth.
class NearbyDevice {
  final String deviceId;
  String displayName;
  String? profileImagePath;
  String? ipAddress;
  int? port;
  DiscoverySource source;
  bool isWifiAvailable;
  bool isBluetoothAvailable;
  DateTime lastSeen;

  NearbyDevice({
    required this.deviceId,
    String? displayName,
    this.profileImagePath,
    this.ipAddress,
    this.port,
    required this.source,
    this.isWifiAvailable = false,
    this.isBluetoothAvailable = false,
    DateTime? lastSeen,
  })  : displayName = (displayName != null && displayName.trim().isNotEmpty)
            ? displayName
            : deviceId,
        lastSeen = lastSeen ?? DateTime.now();

  NearbyDevice copyWith({
    String? displayName,
    String? profileImagePath,
    String? ipAddress,
    int? port,
    DiscoverySource? source,
    bool? isWifiAvailable,
    bool? isBluetoothAvailable,
    DateTime? lastSeen,
  }) {
    return NearbyDevice(
      deviceId: deviceId,
      displayName: displayName ?? this.displayName,
      profileImagePath: profileImagePath ?? this.profileImagePath,
      ipAddress: ipAddress ?? this.ipAddress,
      port: port ?? this.port,
      source: source ?? this.source,
      isWifiAvailable: isWifiAvailable ?? this.isWifiAvailable,
      isBluetoothAvailable: isBluetoothAvailable ?? this.isBluetoothAvailable,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'displayName': displayName,
        'profileImagePath': profileImagePath,
        'ipAddress': ipAddress,
        'port': port,
        'wifiAvailable': isWifiAvailable,
        'bluetoothAvailable': isBluetoothAvailable,
        'source': source.name,
      };

  @override
  String toString() {
    return 'NearbyDevice(id: $deviceId, name: $displayName, ip: $ipAddress, port: $port, source: ${source.name}, wifi: $isWifiAvailable, bt: $isBluetoothAvailable)';
  }
}
