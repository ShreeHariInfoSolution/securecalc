import 'dart:io';
import 'package:flutter/material.dart';
import 'package:securecalc/src/core/config/app_preferences.dart';
import 'package:securecalc/src/core/theme/app_theme.dart';
import 'package:securecalc/src/core/widgets/shake_panic_wrapper.dart';
import 'package:securecalc/src/features/chat/domain/entities/chat_conversation.dart';
import 'package:securecalc/src/features/chat/domain/services/local_chat_storage.dart';
import 'package:securecalc/src/features/chat/presentation/pages/chat_detail_page.dart';
import '../../domain/models/nearby_device.dart';
import '../../domain/services/device_identity_service.dart';
import '../../domain/services/nearby_device_service.dart';

class P2pCallsPage extends StatefulWidget {
  const P2pCallsPage({super.key});

  @override
  State<P2pCallsPage> createState() => _P2pCallsPageState();
}

class _P2pCallsPageState extends State<P2pCallsPage> {
  String? _myDeviceId;
  String? _myDisplayName;

  @override
  void initState() {
    super.initState();
    _initializeIdentityAndDiscovery();
  }

  Future<void> _initializeIdentityAndDiscovery() async {
    final deviceId = await DeviceIdentityService.instance.getDeviceId();
    final name = AppPreferences.getDisplayName();
    if (mounted) {
      setState(() {
        _myDeviceId = deviceId;
        _myDisplayName = name;
      });
    }
    await NearbyDeviceService.instance.startDiscovery();
  }

  @override
  void dispose() {
    NearbyDeviceService.instance.stopDiscovery();
    super.dispose();
  }

  void _panicLock(BuildContext context) {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _openChatWithDevice(NearbyDevice device) async {
    final devId = device.deviceId;
    final name = device.displayName;

    await LocalChatStorage.instance.createOrGetConversation(
      deviceId: devId,
      displayName: name,
      avatarUrl: device.profileImagePath,
    );

    final messages = await LocalChatStorage.instance.loadMessages(devId);

    final conversation = ChatConversation(
      id: devId,
      name: name,
      avatarUrl: device.profileImagePath ?? '',
      lastMessage: messages.isNotEmpty ? messages.last.content : 'Start thread',
      lastMessageTime: 'Just now',
      unreadCount: 0,
      isPinned: false,
      messages: messages,
    );

    if (mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ChatDetailPage(
            conversation: conversation,
            peerIp: device.ipAddress,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ShakePanicWrapper(
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              // iOS Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 16, 8),
                child: Row(
                  children: [
                    Text(
                      'Nearby',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.8,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.wifi_rounded,
                              size: 12, color: AppTheme.primaryColor),
                          SizedBox(width: 4),
                          Text(
                            'Wi-Fi Direct',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.lock_rounded,
                          color: Colors.amber, size: 22),
                      tooltip: 'Panic Lock',
                      onPressed: () => _panicLock(context),
                    ),
                  ],
                ),
              ),

              // Local Network Status Banner
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.03),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.wifi_tethering_rounded,
                                color: AppTheme.primaryColor, size: 22),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Wi-Fi Local Secret Messaging Active',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Send messages, photos, and videos directly to nearby devices on Wi-Fi.',
                                  style: TextStyle(fontSize: 11, color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (_myDeviceId != null) ...[
                        const SizedBox(height: 10),
                        const Divider(height: 1),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.badge_rounded,
                                size: 14, color: AppTheme.primaryColor),
                            const SizedBox(width: 6),
                            Text(
                              'My Display Name: ',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white70 : Colors.black87,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                _myDisplayName ?? 'Vault User',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.primaryColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Discovered Nearby Devices Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'DISCOVERED NEARBY DEVICES',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                        color: Colors.grey,
                      ),
                    ),
                    Row(
                      children: const [
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
                          ),
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Scanning Wi-Fi',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.primaryColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 6),

              // Discovered Nearby Devices List
              Expanded(
                child: ValueListenableBuilder<List<NearbyDevice>>(
                  valueListenable:
                      NearbyDeviceService.instance.devicesNotifier,
                  builder: (context, devices, _) {
                    if (devices.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? const Color(0xFF1C1C1E)
                                      : const Color(0xFFF2F2F7),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.radar_rounded,
                                  size: 48,
                                  color: AppTheme.primaryColor,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Searching for Devices on Same Wi-Fi...',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : Colors.black,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Open Synq Chat on another phone connected to this Wi-Fi network.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: devices.length,
                      separatorBuilder: (context, index) => Divider(
                        height: 1,
                        indent: 76,
                        color: isDark
                            ? const Color(0xFF2C2C2E)
                            : const Color(0xFFE5E5EA),
                      ),
                      itemBuilder: (context, index) {
                        final device = devices[index];
                        final name = device.displayName;
                        final ip = device.ipAddress ?? 'Local Wi-Fi';
                        final profilePath = device.profileImagePath;
                        final hasProfilePic = profilePath != null &&
                            profilePath.isNotEmpty &&
                            File(profilePath).existsSync();

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
                          leading: CircleAvatar(
                            radius: 24,
                            backgroundColor: isDark
                                ? const Color(0xFF2C2C2E)
                                : const Color(0xFFE5E5EA),
                            backgroundImage: hasProfilePic
                                ? FileImage(File(profilePath))
                                : null,
                            child: !hasProfilePic
                                ? Text(
                                    name[0].toUpperCase(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                      color: AppTheme.primaryColor,
                                    ),
                                  )
                                : null,
                          ),
                          title: Text(
                            name,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                          ),
                          subtitle: Row(
                            children: [
                              const Icon(Icons.wifi_rounded,
                                  size: 13, color: AppTheme.primaryColor),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  '$ip • Wi-Fi Direct',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          trailing: IconButton(
                            icon: const Icon(
                              Icons.chat_bubble_rounded,
                              color: AppTheme.primaryColor,
                              size: 22,
                            ),
                            onPressed: () => _openChatWithDevice(device),
                          ),
                          onTap: () => _openChatWithDevice(device),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
