import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../../core/config/app_preferences.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/ios_avatar.dart';
import '../../domain/services/socket_chat_service.dart';

class VaultDashboardHeader extends StatelessWidget {
  final bool isDuressMode;
  final VoidCallback onOpenSettings;

  const VaultDashboardHeader({
    super.key,
    required this.isDuressMode,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Real-Time Socket Status Badge
            ValueListenableBuilder<bool>(
              valueListenable:
                  SocketChatService.instance.connectionStateNotifier,
              builder: (context, isConnected, _) {
                final isOnline = isConnected && !isDuressMode;
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDark ? AppTheme.darkSurface : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isDuressMode
                          ? Colors.orange.withValues(alpha: 0.3)
                          : isOnline
                              ? const Color(0xFF30D158).withValues(alpha: 0.3)
                              : Colors.redAccent.withValues(alpha: 0.3),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black
                            .withValues(alpha: isDark ? 0.25 : 0.04),
                        blurRadius: 6,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: isDuressMode
                              ? Colors.orange
                              : isOnline
                                  ? const Color(0xFF30D158)
                                  : Colors.redAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isDuressMode
                            ? 'Decoy Mode'
                            : isOnline
                                ? 'Vault Active (Online)'
                                : 'Vault Active (Offline)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isDuressMode
                              ? Colors.orange
                              : isOnline
                                  ? const Color(0xFF30D158)
                                  : Colors.redAccent,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            // Settings Icon Button
            IconButton(
              onPressed: onOpenSettings,
              icon: Icon(
                CupertinoIcons.gear_alt,
                color: isDark ? Colors.white70 : Colors.black87,
                size: 24,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Welcome User Section
        ValueListenableBuilder<String>(
          valueListenable: AppPreferences.displayNameNotifier,
          builder: (context, name, _) {
            return ValueListenableBuilder<String?>(
              valueListenable: AppPreferences.profileImagePathNotifier,
              builder: (context, profilePath, _) {
                return Row(
                  children: [
                    IosAvatar(
                      name: name,
                      imagePath: profilePath,
                      size: 52,
                      isOnline: true,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isDuressMode ? 'Welcome' : 'Hello, $name',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'End-to-End Encrypted Dashboard',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.subtitleGrey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ],
    );
  }
}
