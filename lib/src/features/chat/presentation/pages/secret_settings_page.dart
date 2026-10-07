import 'dart:io';
import 'package:flutter/material.dart';
import 'package:securecalc/src/core/config/app_preferences.dart';
import 'package:securecalc/src/core/theme/app_theme.dart';
import 'package:securecalc/src/core/widgets/compact_settings_header.dart';
import 'package:securecalc/src/core/widgets/shake_panic_wrapper.dart';
import 'package:securecalc/src/features/calculator/presentation/pages/calculator_page.dart';
import '../../domain/services/server_chat_manager.dart';
import 'settings/appearance_settings_page.dart';
import 'settings/disguise_settings_page.dart';
import 'settings/emergency_settings_page.dart';
import 'settings/personal_settings_page.dart';

class SecretSettingsPage extends StatefulWidget {
  const SecretSettingsPage({super.key});

  @override
  State<SecretSettingsPage> createState() => _SecretSettingsPageState();
}

class _SecretSettingsPageState extends State<SecretSettingsPage> {
  bool _bannerDismissed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ShakePanicWrapper(
      child: Scaffold(
        backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
        body: SafeArea(
          child: Column(
            children: [
              // Header
              const CompactSettingsHeader(
                title: 'Vault Settings',
                showBackButton: false,
              ),

              // Content List
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16.0, vertical: 8.0),
                  children: [
                    // Profile Header Section (Screenshot 1)
                    _buildProfileHeader(isDark),

                    const SizedBox(height: 16),

                    // Setup Notification Banner
                    if (!_bannerDismissed) ...[
                      _buildSetupBanner(isDark),
                      const SizedBox(height: 16),
                    ],

                    // Grouped Settings Card
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.03),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Material(
                        color: isDark ? AppTheme.darkSurface : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            _buildSettingListTile(
                              context: context,
                              title: 'Personal Profile & Passcode',
                              icon: Icons.person_outline_rounded,
                              isDark: isDark,
                              targetPage: const PersonalSettingsPage(),
                            ),
                            Divider(
                              height: 1,
                              indent: 52,
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : Colors.black.withValues(alpha: 0.06),
                            ),
                            _buildSettingListTile(
                              context: context,
                              title: 'Appearance & Theme',
                              icon: Icons.palette_outlined,
                              isDark: isDark,
                              targetPage: const AppearanceSettingsPage(),
                            ),
                            Divider(
                              height: 1,
                              indent: 52,
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : Colors.black.withValues(alpha: 0.06),
                            ),
                            _buildSettingListTile(
                              context: context,
                              title: 'Disguise & Security Sensors',
                              icon: Icons.shield_outlined,
                              isDark: isDark,
                              targetPage: const DisguiseSettingsPage(),
                            ),
                            Divider(
                              height: 1,
                              indent: 52,
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : Colors.black.withValues(alpha: 0.06),
                            ),
                            _buildSettingListTile(
                              context: context,
                              title: 'Emergency & Vault Zone',
                              icon: Icons.warning_amber_rounded,
                              isDark: isDark,
                              targetPage: const EmergencySettingsPage(),
                            ),
                            Divider(
                              height: 1,
                              indent: 52,
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : Colors.black.withValues(alpha: 0.06),
                            ),
                            ListTile(
                              leading: Icon(
                                Icons.privacy_tip_outlined,
                                size: 22,
                                color: isDark ? Colors.white70 : Colors.black87,
                              ),
                              title: Text(
                                'Privacy Policy & Disclosures',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white : Colors.black,
                                ),
                              ),
                              trailing: const Icon(
                                Icons.chevron_right_rounded,
                                size: 20,
                                color: AppTheme.subtitleGrey,
                              ),
                              onTap: () => _showPrivacyPolicyDialog(context),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Logout Button Card
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.03),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Material(
                        color: isDark ? AppTheme.darkSurface : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          leading: const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 22),
                        title: const Text(
                          'Log Out of Server Session',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.redAccent,
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.subtitleGrey, size: 20),
                        onTap: () async {
                          await ServerChatManager.instance.logout();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Logged out. All account data cleared from this device.',
                                ),
                              ),
                            );
                            Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                              PageRouteBuilder(
                                transitionDuration: Duration.zero,
                                reverseTransitionDuration: Duration.zero,
                                pageBuilder: (context, animation, secondaryAnimation) {
                                  return const CalculatorPage();
                                },
                              ),
                              (route) => false,
                            );
                          }
                        },
                      ),
                    ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPrivacyPolicyDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.privacy_tip_outlined, color: AppTheme.primaryColor),
              SizedBox(width: 8),
              Text('Privacy & Data Safety', style: TextStyle(fontSize: 18)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text(
                  'Calculator Vault Privacy Policy',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                SizedBox(height: 8),
                Text(
                  '1. End-to-End Encryption:\nAll chat messages, photos, videos, and documents exchanged in the vault are encrypted client-side using AES-256 before transmission.\n\n'
                  '2. User Data & Storage:\nVault content is stored securely on device. Account credentials are managed via secure token authentication.\n\n'
                  '3. App Disguise & Security:\nThe calculator interface functions as a disguise. Entering your passcode ("1234=") unlocks the vault. Panic gestures (shake device) instantly lock the vault.\n\n'
                  '4. Permissions Disclosure:\n- Camera: Capturing media inside vault.\n- Microphone: Recording voice notes.\n- Media & Files: Attaching photos/files via system photo picker.',
                  style: TextStyle(fontSize: 12, height: 1.4, color: AppTheme.subtitleGrey),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildProfileHeader(bool isDark) {
    final displayName = AppPreferences.getDisplayName();
    final profileImgPath = AppPreferences.getProfileImagePath();
    final hasImg = profileImgPath != null &&
        profileImgPath.isNotEmpty &&
        File(profileImgPath).existsSync();
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : 'H';

    return Column(
      children: [
        // Pill status badge matching Screenshot 1: 🟢 Online • Wi-Fi Direct
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkSurface : Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
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
                decoration: const BoxDecoration(
                  color: AppTheme.onlineGreen,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Online • Wi-Fi Direct',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Large Light-Blue Circle Avatar matching Screenshot 1
        CircleAvatar(
          radius: 46,
          backgroundColor: const Color(0xFF60A5FA),
          backgroundImage: hasImg ? FileImage(File(profileImgPath)) : null,
          child: !hasImg
              ? Text(
                  initial,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                )
              : null,
        ),
        const SizedBox(height: 12),

        // Display Name + Verified Badge
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              displayName,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.3,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.check_circle_rounded,
              size: 20,
              color: AppTheme.primaryColor,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSetupBanner(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF), // Soft blue bg
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.check_box_outlined,
              color: AppTheme.primaryColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Finish vault email setup',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Use email address to log in or recover your secret vault.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.subtitleGrey,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () {
              setState(() {
                _bannerDismissed = true;
              });
            },
            child: const Icon(Icons.close_rounded,
                size: 18, color: AppTheme.subtitleGrey),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingListTile({
    required BuildContext context,
    required String title,
    required IconData icon,
    required bool isDark,
    required Widget targetPage,
  }) {
    return ListTile(
      leading: Icon(
        icon,
        size: 22,
        color: isDark ? Colors.white70 : Colors.black87,
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white : Colors.black,
        ),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        size: 20,
        color: AppTheme.subtitleGrey,
      ),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => targetPage),
        );
      },
    );
  }
}
