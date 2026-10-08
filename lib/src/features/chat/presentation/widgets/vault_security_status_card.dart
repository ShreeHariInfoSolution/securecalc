import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

class VaultSecurityStatusCard extends StatelessWidget {
  const VaultSecurityStatusCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
        ),
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
          _buildSecurityStatusRow(
            isDark: isDark,
            icon: CupertinoIcons.lock_shield,
            iconColor: const Color(0xFF30D158),
            label: 'Client Encryption',
            value: 'AES-256 E2EE Active',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Divider(
              height: 1,
              color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
            ),
          ),
          _buildSecurityStatusRow(
            isDark: isDark,
            icon: CupertinoIcons.device_phone_portrait,
            iconColor: const Color(0xFF007AFF),
            label: 'App Disguise',
            value: 'Calculator Enabled',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Divider(
              height: 1,
              color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
            ),
          ),
          _buildSecurityStatusRow(
            isDark: isDark,
            icon: CupertinoIcons.hand_draw,
            iconColor: const Color(0xFFFF9500),
            label: 'Panic Gesture',
            value: 'Real Shake Sensor Armed',
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityStatusRow({
    required bool isDark,
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, color: iconColor, size: 20),
        const SizedBox(width: 12),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppTheme.subtitleGrey,
          ),
        ),
      ],
    );
  }
}
